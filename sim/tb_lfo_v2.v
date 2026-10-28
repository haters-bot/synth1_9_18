`timescale 1ns/1ps
// 表值与独立Fraction参考逐位比较；包含双缓冲、53目标和配置事务。
module tb_lfo_v2;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg build_start=0, stepped=0, write_bank=1, active_bank=0;
    reg [48:0] nodes=0;
    reg [8:0] read_index=0;
    wire [12:0] read_q6;
    wire build_done, table_busy;
    reg [49:0] node_vectors[0:63];
    reg [12:0] expected[0:24639];
    integer errors=0, c, p, n, old_case=-1;
    lfo_hermite_table table_dut (
        .clk(clk), .rst_n(rst_n), .build_start(build_start), .build_nodes(nodes),
        .build_stepped(stepped), .build_bank(write_bank), .active_bank(active_bank),
        .read_index(read_index), .read_q6(read_q6), .build_done(build_done), .busy(table_busy)
    );
    reg router_tick=0;
    reg [370:0] bases=0;
    reg [105:0] sources=0;
    reg [423:0] depths=0;
    reg [20:0] waves={7'd127,7'd64,7'd0};
    wire [370:0] routed;
    wire routed_valid, router_busy, router_overrun;
    lfo_target_router_v2 router_dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(router_tick), .base_values(bases),
        .sources(sources), .depths(depths), .waves(waves), .mod_values(routed),
        .output_valid(routed_valid), .busy(router_busy), .overrun(router_overrun)
    );
    reg engine_tick=0, parameter_valid=0;
    reg [6:0] parameter_id=0;
    reg [13:0] parameter_value=0;
    reg [370:0] engine_base={53{7'd32}};
    wire [370:0] engine_mod;
    wire engine_valid, engine_overrun, config_busy, config_error, config_applied;
    wire [26:0] phase_indices;
    wire [20:0] wave_values;
    reg auto_tick=0;
    integer tick_counter=0;
    // 80拍控制周期比实际521拍更紧，用于压力验证路由吞吐率。
    always @(negedge clk) begin
        engine_tick=0;
        if (auto_tick) begin
            if (tick_counter==79) begin engine_tick=1; tick_counter=0; end
            else tick_counter=tick_counter+1;
        end
    end
    lfo_v2_engine engine_dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(engine_tick),
        .parameter_valid(parameter_valid), .parameter_id(parameter_id),
        .parameter_value(parameter_value), .base_values(engine_base),
        .mod_values(engine_mod), .output_valid(engine_valid), .route_overrun(engine_overrun),
        .config_busy(config_busy), .config_error(config_error), .config_applied(config_applied),
        .phase_indices(phase_indices), .wave_values(wave_values)
    );
    task write_parameter;
        input [6:0] id;
        input [13:0] value;
        begin
            @(negedge clk); parameter_id=id; parameter_value=value; parameter_valid=1;
            @(negedge clk); parameter_valid=0;
        end
    endtask
    task commit_config;
        begin
            write_parameter(126,0);
            wait(config_applied); @(negedge clk);
            repeat(180) @(posedge clk); #1;
        end
    endtask
    integer ref_value, src, dep, wave;
    reg [370:0] expected_route, held_result;
    reg old_active;
    reg [8:0] stopped_phase;
    initial begin
        $readmemh("tmp/lfo_v2_nodes.hex",node_vectors);
        $readmemh("tmp/lfo_v2_expected.hex",expected);
        repeat(4) @(negedge clk); rst_n=1;
        for (c=0;c<64;c=c+1) begin
            @(negedge clk); nodes=node_vectors[c][48:0]; stepped=node_vectors[c][49];
            write_bank=!active_bank; build_start=1;
            @(negedge clk); build_start=0;
            // 后台写表时前台保持完整旧表。
            read_index=9'd123; repeat(3) @(negedge clk);
            if (old_case>=0 && read_q6!==expected[old_case*385+123]) begin
                $display("ERROR: active table changed during background build"); errors=errors+1;
            end
            wait(build_done); @(negedge clk); active_bank=write_bank;
            for (p=0;p<=384;p=p+1) begin
                read_index=p; @(posedge clk); #1;
                if (read_q6!==expected[c*385+p]) begin
                    if (errors<10) $display("ERROR: table case=%0d p=%0d got=%0d expected=%0d",c,p,read_q6,expected[c*385+p]);
                    errors=errors+1;
                end
                @(negedge clk);
            end
            old_case=c;
        end
        // 全53目标同时设置，验证来源、负深度、限幅和base快照。
        for (n=0;n<53;n=n+1) begin
            bases[n*7+:7]=(n*13)%128;
            sources[n*2+:2]=n%4;
            dep=(n%2) ? -127 : 127; depths[n*8+:8]=dep;
            src=n%4; wave=src==1 ? 0 : src==2 ? 64 : 127;
            ref_value=(n*13)%128 + (src==0 ? 0 : ((dep*wave)>>>7));
            expected_route[n*7+:7]=ref_value<0 ? 0 : ref_value>127 ? 127 : ref_value;
        end
        @(negedge clk); router_tick=1;
        @(negedge clk); router_tick=0;
        repeat(4) @(negedge clk); bases=0; // 运行中改base不得撕裂当前批次。
        wait(routed_valid); #1;
        if (routed!==expected_route || router_overrun) begin
            $display("ERROR: 53-target routing/snapshot"); errors=errors+1;
        end
        auto_tick=1;
        wait(!config_busy); repeat(180) @(posedge clk);
        for (n=0;n<7;n=n+1) write_parameter(48+n,127);
        write_parameter(96,14'h140); // idx23, LFO1, +64
        old_active=engine_dut.active_bank;
        repeat(180) @(posedge clk); #1;
        if (engine_mod[161+:7]!==7'd32 || engine_dut.active_bank!==old_active) begin
            $display("ERROR: shadow edit leaked before commit"); errors=errors+1;
        end
        write_parameter(72,4); commit_config();
        if (engine_mod[161+:7]!==7'd95 || config_error) begin
            $display("ERROR: atomic V2 config or positive depth got=%0d",engine_mod[161+:7]); errors=errors+1;
        end
        // 相位重启请求也是事务的一部分，不能收到ID72即提前触发。
        write_parameter(96,14'h1C0); commit_config();
        if (engine_mod[161+:7]!==0) begin $display("ERROR: signed route depth"); errors=errors+1; end
        write_parameter(96,0); commit_config();
        if (engine_mod[161+:7]!==32) begin $display("ERROR: unbind restores base"); errors=errors+1; end
        for (n=0;n<53;n=n+1) write_parameter(73+n,14'h33F);
        commit_config();
        if (engine_dut.active_sources!=={53{2'd3}} || engine_dut.active_depths!=={53{8'd63}}) begin
            $display("ERROR: all53 target bindings"); errors=errors+1;
        end
        // 速率最高档32Hz，Once约3000样本后停383；显式Restart才恢复运行。
        write_parameter(69,23); write_parameter(72,4); commit_config();
        repeat(3005) @(posedge engine_tick);
        repeat(5) @(posedge clk); #1;
        if (phase_indices[8:0]!==383 || !engine_dut.GEN_LFO[0].stopped) begin
            $display("ERROR: Once did not stop at383"); errors=errors+1;
        end
        stopped_phase=phase_indices[8:0]; repeat(5) @(posedge engine_tick); #1;
        if (phase_indices[8:0]!==stopped_phase) begin $display("ERROR: Once advanced"); errors=errors+1; end
        write_parameter(72,4); commit_config();
        if (engine_dut.GEN_LFO[0].stopped || phase_indices[8:0]>2) begin
            $display("ERROR: restart transaction"); errors=errors+1;
        end
        // 非法-128不能覆写影子配置，且需可观测错误标志。
        write_parameter(73,14'h180);
        if (!config_error || engine_dut.shadow_depths[7:0]!==8'd63) begin
            $display("ERROR: invalid route validation"); errors=errors+1;
        end
        if (engine_overrun) begin $display("ERROR: engine route budget"); errors=errors+1; end
        if (errors) $fatal(1,"FAIL: LFO V2 %0d errors",errors);
        $display("PASS: LFO V2 24640 exact Q6 values, double buffers, 53 targets, atomic commit, Once/restart");
        $finish;
    end
    initial begin #15000000; $fatal(1,"FAIL: LFO V2 timeout"); end
endmodule
