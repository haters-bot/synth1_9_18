// 触屏协议V2：ID48..68节点，69..71模式，72重启，73..125绑定，126提交。
// 输入是现有SysEx解析器的14位值；两字节均按7位打包，未更换串口协议。
module lfo_v2_engine (
    input wire clk, rst_n, sample_tick,
    input wire parameter_valid,
    input wire [6:0] parameter_id,
    input wire [13:0] parameter_value,
    input wire [370:0] base_values,
    output wire [370:0] mod_values,
    output wire output_valid, route_overrun,
    output wire config_busy,
    output reg config_error,
    output reg config_applied,
    output wire [26:0] phase_indices,
    output wire [20:0] wave_values
);
    reg [146:0] shadow_nodes, pending_nodes;
    reg [14:0] shadow_modes, pending_modes, active_modes;
    reg [105:0] shadow_sources, pending_sources, active_sources;
    reg [423:0] shadow_depths, pending_depths, active_depths;
    reg [2:0] shadow_restart, pending_restart;
    // 0=等待Commit，1=启动后台构表，2=等待构表，3=等待音频边界切换。
    reg [1:0] state;
    reg build_start, active_bank, tables_ready;
    wire [2:0] build_done;
    wire route_busy;
    wire apply_now=state==2'd3 && sample_tick && !route_busy;
    assign config_busy=state!=0;
    wire router_tick=sample_tick && !apply_now;
    integer i;
    function [48:0] default_nodes;
        input integer bank;
        begin
            case (bank)
                1: default_nodes={7'd127,7'd106,7'd85,7'd64,7'd42,7'd21,7'd0};
                2: default_nodes={7'd0,7'd0,7'd0,7'd0,7'd127,7'd127,7'd127};
                default: default_nodes={7'd0,7'd42,7'd85,7'd127,7'd85,7'd42,7'd0};
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_nodes<={default_nodes(2),default_nodes(1),default_nodes(0)};
            pending_nodes<={default_nodes(2),default_nodes(1),default_nodes(0)};
            shadow_modes<={5'd10,5'd2,5'd2};
            pending_modes<={5'd10,5'd2,5'd2}; active_modes<={5'd10,5'd2,5'd2};
            shadow_sources<=0; pending_sources<=0; active_sources<=0;
            shadow_depths<=0; pending_depths<=0; active_depths<=0;
            shadow_restart<=0; pending_restart<=3'b111;
            state<=1; build_start<=0; active_bank<=0; tables_ready<=0;
            config_error<=0; config_applied<=0;
        end else begin
            build_start<=0; config_applied<=0;
            if (parameter_valid) begin
                if (parameter_id>=48 && parameter_id<=68) begin
                    if (parameter_value<=127)
                        shadow_nodes[(parameter_id-7'd48)*7+:7]<=parameter_value[6:0];
                    else config_error<=1;
                end else if (parameter_id>=69 && parameter_id<=71) begin
                    if (parameter_value<=31)
                        shadow_modes[(parameter_id-7'd69)*5+:5]<=parameter_value[4:0];
                    else config_error<=1;
                end else if (parameter_id==72) begin
                    if (parameter_value>=4 && parameter_value<=6)
                        shadow_restart[parameter_value[1:0]]<=1;
                    else config_error<=1;
                end else if (parameter_id>=73 && parameter_id<=125) begin
                    // 低8位为二补码深度；拒绝-128和多余高位，防止静默别名。
                    if (parameter_value[13:10]==0 && parameter_value[7:0]!=8'h80) begin
                        shadow_sources[(parameter_id-7'd73)*2+:2]<=parameter_value[9:8];
                        shadow_depths[(parameter_id-7'd73)*8+:8]<=parameter_value[7:0];
                    end else config_error<=1;
                end else if (parameter_id==126) begin
                    if (state==0) begin
                        pending_nodes<=shadow_nodes; pending_modes<=shadow_modes;
                        pending_sources<=shadow_sources; pending_depths<=shadow_depths;
                        pending_restart<=shadow_restart; shadow_restart<=0; state<=1;
                    end else config_error<=1;
                end
            end
            case (state)
                1: begin build_start<=1; state<=2; end
                2: if (&build_done) state<=3;
                3: if (apply_now) begin
                    active_bank<=!active_bank; tables_ready<=1;
                    active_modes<=pending_modes; active_sources<=pending_sources;
                    active_depths<=pending_depths; config_applied<=1; state<=0;
                end
                default: begin end
            endcase
        end
    end
    // 32位归一化相位自然回绕；乘384等价于乘3后右移25位。
    // 不使用9位索引自然回绕，因此不会误扫384..511的空地址。
    function [31:0] phase_increment;
        input [2:0] rate;
        begin
            case (rate)
                0: phase_increment=32'd11185; 1: phase_increment=32'd22370;
                2: phase_increment=32'd44739; 3: phase_increment=32'd89478;
                4: phase_increment=32'd178957; 5: phase_increment=32'd357914;
                6: phase_increment=32'd715828; default: phase_increment=32'd1431656;
            endcase
        end
    endfunction
    genvar bank;
    generate for (bank=0; bank<3; bank=bank+1) begin: GEN_LFO
        reg [31:0] phase;
        reg stopped;
        wire [4:0] mode=active_modes[bank*5+:5];
        wire [32:0] next_phase={1'b0,phase}+{1'b0,phase_increment(mode[2:0])};
        wire [33:0] scaled_phase={2'b0,phase}+{1'b0,phase,1'b0};
        wire [8:0] index=scaled_phase[33:25];
        wire [12:0] value_q6;
        assign phase_indices[bank*9+:9]=index;
        assign wave_values[bank*7+:7]=tables_ready ? value_q6[12:6] : 7'd0;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin phase<=0; stopped<=0; end
            else if (apply_now && pending_restart[bank]) begin phase<=0; stopped<=0; end
            else if (sample_tick && tables_ready && !apply_now && !stopped) begin
                if (mode[4] && next_phase[32]) begin
                    // 按V2草案：Once停在第383档，不强制跳到第384端点。
                    phase<=32'hFFFFFFFF; stopped<=1;
                end else phase<=next_phase[31:0];
            end
        end
        lfo_hermite_table u_table (
            .clk(clk), .rst_n(rst_n), .build_start(build_start),
            .build_nodes(pending_nodes[bank*49+:49]),
            .build_stepped(pending_modes[bank*5+3]),
            .build_bank(!active_bank), .active_bank(active_bank),
            .read_index(index), .read_q6(value_q6), .build_done(build_done[bank]), .busy()
        );
    end endgenerate
    lfo_target_router_v2 u_router (
        .clk(clk), .rst_n(rst_n), .sample_tick(router_tick),
        .base_values(base_values), .sources(active_sources), .depths(active_depths),
        .waves(wave_values), .mod_values(mod_values), .output_valid(output_valid),
        .busy(route_busy), .overrun(route_overrun)
    );
endmodule
