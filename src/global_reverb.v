// 轻量 Schroeder 混响：4 条并联低通反馈梳状线，再串联 2 条全通线。
// 每个 96 kHz 输入样本用一套乘法路径依次处理，最坏 14 个 50 MHz 时钟。
module global_reverb (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire [6:0]         size_control,
    input  wire [6:0]         decay_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    localparam [3:0] STATE_IDLE         = 4'd0;
    localparam [3:0] STATE_COMB_READ    = 4'd1;
    localparam [3:0] STATE_COMB_PROCESS = 4'd2;
    localparam [3:0] STATE_AP1_READ     = 4'd3;
    localparam [3:0] STATE_AP1_PROCESS  = 4'd4;
    localparam [3:0] STATE_AP2_READ     = 4'd5;
    localparam [3:0] STATE_AP2_PROCESS  = 4'd6;
    localparam [3:0] STATE_MIX          = 4'd7;

    (* syn_ramstyle = "block_ram" *) reg signed [15:0] comb_memory_0 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] comb_memory_1 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] comb_memory_2 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] comb_memory_3 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] allpass_memory_1 [0:511];
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] allpass_memory_2 [0:255];

    reg [3:0] state;
    reg [1:0] comb_index;
    reg signed [15:0] dry_sample_latched;
    reg [6:0] decay_latched;
    reg [6:0] mix_latched;
    reg [11:0] comb_length_0;
    reg [11:0] comb_length_1;
    reg [11:0] comb_length_2;
    reg [11:0] comb_length_3;
    reg [11:0] comb_pointer_0;
    reg [11:0] comb_pointer_1;
    reg [11:0] comb_pointer_2;
    reg [11:0] comb_pointer_3;
    reg [12:0] comb_fill_0;
    reg [12:0] comb_fill_1;
    reg [12:0] comb_fill_2;
    reg [12:0] comb_fill_3;
    reg signed [15:0] comb_damp_0;
    reg signed [15:0] comb_damp_1;
    reg signed [15:0] comb_damp_2;
    reg signed [15:0] comb_damp_3;
    reg signed [15:0] comb_read_data_0;
    reg signed [15:0] comb_read_data_1;
    reg signed [15:0] comb_read_data_2;
    reg signed [15:0] comb_read_data_3;
    reg memory_read_valid;
    reg signed [18:0] comb_sum;

    reg [8:0] allpass_pointer_1;
    reg [7:0] allpass_pointer_2;
    reg [9:0] allpass_fill_1;
    reg [8:0] allpass_fill_2;
    // 两条全通延迟线必须使用各自独立的同步读数据寄存器。
    // 如果两个存储器共用一个读数据寄存器并把读写混在主状态机中，
    // GowinSynthesis 会把数组展开为触发器和选择器，无法映射到 BSRAM。
    reg signed [15:0] allpass_read_data_1;
    reg signed [15:0] allpass_read_data_2;
    reg allpass_read_valid;
    reg signed [15:0] allpass_1_output;
    reg signed [15:0] reverb_wet_sample;

    wire [18:0] size_product_0 = size_control * 12'd1274;
    wire [18:0] size_product_1 = size_control * 12'd1500;
    wire [18:0] size_product_2 = size_control * 12'd1740;
    wire [18:0] size_product_3 = size_control * 12'd1990;
    wire [11:0] requested_length_0 = 12'd1277 + size_product_0[18:7];
    wire [11:0] requested_length_1 = 12'd1499 + size_product_1[18:7];
    wire [11:0] requested_length_2 = 12'd1741 + size_product_2[18:7];
    wire [11:0] requested_length_3 = 12'd1999 + size_product_3[18:7];

    reg signed [15:0] selected_damp_state;
    reg signed [15:0] selected_memory_read_data;
    reg [11:0] selected_length;
    reg [11:0] selected_pointer;
    reg [12:0] selected_fill;
    always @(*) begin
        case (comb_index)
            2'd0: begin
                selected_damp_state = comb_damp_0;
                selected_memory_read_data = comb_read_data_0;
                selected_length = comb_length_0;
                selected_pointer = comb_pointer_0;
                selected_fill = comb_fill_0;
            end
            2'd1: begin
                selected_damp_state = comb_damp_1;
                selected_memory_read_data = comb_read_data_1;
                selected_length = comb_length_1;
                selected_pointer = comb_pointer_1;
                selected_fill = comb_fill_1;
            end
            2'd2: begin
                selected_damp_state = comb_damp_2;
                selected_memory_read_data = comb_read_data_2;
                selected_length = comb_length_2;
                selected_pointer = comb_pointer_2;
                selected_fill = comb_fill_2;
            end
            default: begin
                selected_damp_state = comb_damp_3;
                selected_memory_read_data = comb_read_data_3;
                selected_length = comb_length_3;
                selected_pointer = comb_pointer_3;
                selected_fill = comb_fill_3;
            end
        endcase
    end

    wire signed [15:0] selected_delayed_sample = memory_read_valid
                                                       ? selected_memory_read_data
                                                       : 16'sd0;
    wire signed [16:0] damping_difference =
        $signed({selected_delayed_sample[15], selected_delayed_sample})
        - $signed({selected_damp_state[15], selected_damp_state});
    wire signed [17:0] damped_next_wide =
        $signed({{2{selected_damp_state[15]}}, selected_damp_state})
        + ($signed(damping_difference) >>> 2);
    wire signed [15:0] damped_next = damped_next_wide[15:0];
    wire signed [23:0] feedback_product =
        damped_next * $signed({1'b0, decay_latched});
    wire signed [24:0] feedback_scaled =
        ($signed(feedback_product) >>> 7)
        - ($signed(feedback_product) >>> 10);
    wire signed [24:0] comb_write_wide =
        $signed({{9{dry_sample_latched[15]}}, dry_sample_latched})
        + feedback_scaled;
    wire signed [15:0] comb_average = saturate_s19_to_s16(comb_sum >>> 2);

    wire signed [15:0] ap1_delayed = allpass_read_valid
                                    ? allpass_read_data_1 : 16'sd0;
    wire signed [17:0] ap1_write_wide =
        $signed({{2{comb_average[15]}}, comb_average})
        + ($signed({{2{ap1_delayed[15]}}, ap1_delayed}) >>> 1);
    wire signed [17:0] ap1_output_wide =
        $signed({{2{ap1_delayed[15]}}, ap1_delayed})
        - ($signed({{2{comb_average[15]}}, comb_average}) >>> 1);
    wire signed [15:0] ap2_delayed = allpass_read_valid
                                    ? allpass_read_data_2 : 16'sd0;
    wire signed [17:0] ap2_write_wide =
        $signed({{2{allpass_1_output[15]}}, allpass_1_output})
        + ($signed({{2{ap2_delayed[15]}}, ap2_delayed}) >>> 1);
    wire signed [17:0] ap2_output_wide =
        $signed({{2{ap2_delayed[15]}}, ap2_delayed})
        - ($signed({{2{allpass_1_output[15]}}, allpass_1_output}) >>> 1);

    wire signed [16:0] wet_dry_difference =
        $signed({reverb_wet_sample[15], reverb_wet_sample})
        - $signed({dry_sample_latched[15], dry_sample_latched});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [25:0] mixed_sample_wide =
        $signed({{10{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_product) >>> 7);

    assign in_ready = state == STATE_IDLE;

    function signed [15:0] saturate_s18_to_s16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767)
                saturate_s18_to_s16 = 16'sh7FFF;
            else if (value < -18'sd32768)
                saturate_s18_to_s16 = 16'sh8000;
            else
                saturate_s18_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s19_to_s16;
        input signed [18:0] value;
        begin
            if (value > 19'sd32767)
                saturate_s19_to_s16 = 16'sh7FFF;
            else if (value < -19'sd32768)
                saturate_s19_to_s16 = 16'sh8000;
            else
                saturate_s19_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s25_to_s16;
        input signed [24:0] value;
        begin
            if (value > 25'sd32767)
                saturate_s25_to_s16 = 16'sh7FFF;
            else if (value < -25'sd32768)
                saturate_s25_to_s16 = 16'sh8000;
            else
                saturate_s25_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s26_to_s16;
        input signed [25:0] value;
        begin
            if (value > 26'sd32767)
                saturate_s26_to_s16 = 16'sh7FFF;
            else if (value < -26'sd32768)
                saturate_s26_to_s16 = 16'sh8000;
            else
                saturate_s26_to_s16 = value[15:0];
        end
    endfunction

    // 138K 器件的单口 BSRAM 不支持 Read-before-Write。这里将同步读写
    // 明确拆开且保持周期互斥，使综合器映射到器件支持的独立读写端口结构。
    wire comb_access_phase = (state == STATE_COMB_READ)
                             || (state == STATE_COMB_PROCESS);
    wire comb_write_phase = state == STATE_COMB_PROCESS;
    wire comb_ce_0 = comb_access_phase && (comb_index == 2'd0);
    wire comb_ce_1 = comb_access_phase && (comb_index == 2'd1);
    wire comb_ce_2 = comb_access_phase && (comb_index == 2'd2);
    wire comb_ce_3 = comb_access_phase && (comb_index == 2'd3);
    wire comb_wre_0 = comb_write_phase && (comb_index == 2'd0);
    wire comb_wre_1 = comb_write_phase && (comb_index == 2'd1);
    wire comb_wre_2 = comb_write_phase && (comb_index == 2'd2);
    wire comb_wre_3 = comb_write_phase && (comb_index == 2'd3);
    wire signed [15:0] comb_write_data =
        saturate_s25_to_s16(comb_write_wide);

    always @(posedge clk) begin
        if (comb_ce_0 && !comb_wre_0)
            comb_read_data_0 <= comb_memory_0[comb_pointer_0];
    end

    always @(posedge clk) begin
        if (comb_ce_0 && comb_wre_0)
            comb_memory_0[comb_pointer_0] <= comb_write_data;
    end

    always @(posedge clk) begin
        if (comb_ce_1 && !comb_wre_1)
            comb_read_data_1 <= comb_memory_1[comb_pointer_1];
    end

    always @(posedge clk) begin
        if (comb_ce_1 && comb_wre_1)
            comb_memory_1[comb_pointer_1] <= comb_write_data;
    end

    always @(posedge clk) begin
        if (comb_ce_2 && !comb_wre_2)
            comb_read_data_2 <= comb_memory_2[comb_pointer_2];
    end

    always @(posedge clk) begin
        if (comb_ce_2 && comb_wre_2)
            comb_memory_2[comb_pointer_2] <= comb_write_data;
    end

    always @(posedge clk) begin
        if (comb_ce_3 && !comb_wre_3)
            comb_read_data_3 <= comb_memory_3[comb_pointer_3];
    end

    always @(posedge clk) begin
        if (comb_ce_3 && comb_wre_3)
            comb_memory_3[comb_pointer_3] <= comb_write_data;
    end

    // 全通延迟线采用与梳状延迟线一致的同步 RAM 模板：每个数组拥有
    // 独立的读数据寄存器，读周期和写周期由状态机保证互斥。
    // 读数据寄存器不复位；allpass_read_valid 在历史数据有效前会屏蔽它。
    always @(posedge clk) begin
        if (state == STATE_AP1_READ)
            allpass_read_data_1 <= allpass_memory_1[allpass_pointer_1];
    end

    always @(posedge clk) begin
        if (state == STATE_AP1_PROCESS)
            allpass_memory_1[allpass_pointer_1]
                <= saturate_s18_to_s16(ap1_write_wide);
    end

    always @(posedge clk) begin
        if (state == STATE_AP2_READ)
            allpass_read_data_2 <= allpass_memory_2[allpass_pointer_2];
    end

    always @(posedge clk) begin
        if (state == STATE_AP2_PROCESS)
            allpass_memory_2[allpass_pointer_2]
                <= saturate_s18_to_s16(ap2_write_wide);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            comb_index <= 2'd0;
            dry_sample_latched <= 16'sd0;
            decay_latched <= 7'd0;
            mix_latched <= 7'd0;
            comb_length_0 <= 12'd1277;
            comb_length_1 <= 12'd1499;
            comb_length_2 <= 12'd1741;
            comb_length_3 <= 12'd1999;
            comb_pointer_0 <= 12'd0;
            comb_pointer_1 <= 12'd0;
            comb_pointer_2 <= 12'd0;
            comb_pointer_3 <= 12'd0;
            comb_fill_0 <= 13'd0;
            comb_fill_1 <= 13'd0;
            comb_fill_2 <= 13'd0;
            comb_fill_3 <= 13'd0;
            comb_damp_0 <= 16'sd0;
            comb_damp_1 <= 16'sd0;
            comb_damp_2 <= 16'sd0;
            comb_damp_3 <= 16'sd0;
            memory_read_valid <= 1'b0;
            comb_sum <= 19'sd0;
            allpass_pointer_1 <= 9'd0;
            allpass_pointer_2 <= 8'd0;
            allpass_fill_1 <= 10'd0;
            allpass_fill_2 <= 9'd0;
            allpass_read_valid <= 1'b0;
            allpass_1_output <= 16'sd0;
            reverb_wet_sample <= 16'sd0;
            out_valid <= 1'b0;
            sample_out <= 16'sd0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (in_valid) begin
                        dry_sample_latched <= sample_in;
                        decay_latched <= decay_control;
                        mix_latched <= mix_control;
                        comb_length_0 <= requested_length_0;
                        comb_length_1 <= requested_length_1;
                        comb_length_2 <= requested_length_2;
                        comb_length_3 <= requested_length_3;
                        comb_index <= 2'd0;
                        comb_sum <= 19'sd0;
                        state <= STATE_COMB_READ;
                    end
                end

                STATE_COMB_READ: begin
                    memory_read_valid <= selected_fill >= {1'b0, selected_length};
                    state <= STATE_COMB_PROCESS;
                end

                STATE_COMB_PROCESS: begin
                    comb_sum <= comb_sum
                                + $signed({{3{selected_delayed_sample[15]}},
                                           selected_delayed_sample});
                    case (comb_index)
                        2'd0: begin
                            comb_damp_0 <= damped_next;
                            comb_pointer_0 <= (comb_pointer_0 + 12'd1
                                               >= comb_length_0)
                                              ? 12'd0
                                              : comb_pointer_0 + 12'd1;
                            if (comb_fill_0 < {1'b0, comb_length_0})
                                comb_fill_0 <= comb_fill_0 + 13'd1;
                        end
                        2'd1: begin
                            comb_damp_1 <= damped_next;
                            comb_pointer_1 <= (comb_pointer_1 + 12'd1
                                               >= comb_length_1)
                                              ? 12'd0
                                              : comb_pointer_1 + 12'd1;
                            if (comb_fill_1 < {1'b0, comb_length_1})
                                comb_fill_1 <= comb_fill_1 + 13'd1;
                        end
                        2'd2: begin
                            comb_damp_2 <= damped_next;
                            comb_pointer_2 <= (comb_pointer_2 + 12'd1
                                               >= comb_length_2)
                                              ? 12'd0
                                              : comb_pointer_2 + 12'd1;
                            if (comb_fill_2 < {1'b0, comb_length_2})
                                comb_fill_2 <= comb_fill_2 + 13'd1;
                        end
                        default: begin
                            comb_damp_3 <= damped_next;
                            comb_pointer_3 <= (comb_pointer_3 + 12'd1
                                               >= comb_length_3)
                                              ? 12'd0
                                              : comb_pointer_3 + 12'd1;
                            if (comb_fill_3 < {1'b0, comb_length_3})
                                comb_fill_3 <= comb_fill_3 + 13'd1;
                        end
                    endcase
                    if (comb_index == 2'd3) begin
                        state <= STATE_AP1_READ;
                    end else begin
                        comb_index <= comb_index + 2'd1;
                        state <= STATE_COMB_READ;
                    end
                end

                STATE_AP1_READ: begin
                    allpass_read_valid <= allpass_fill_1 >= 10'd347;
                    state <= STATE_AP1_PROCESS;
                end

                STATE_AP1_PROCESS: begin
                    allpass_1_output <= saturate_s18_to_s16(ap1_output_wide);
                    allpass_pointer_1 <= (allpass_pointer_1 == 9'd346)
                                       ? 9'd0 : allpass_pointer_1 + 9'd1;
                    if (allpass_fill_1 < 10'd347)
                        allpass_fill_1 <= allpass_fill_1 + 10'd1;
                    state <= STATE_AP2_READ;
                end

                STATE_AP2_READ: begin
                    allpass_read_valid <= allpass_fill_2 >= 9'd113;
                    state <= STATE_AP2_PROCESS;
                end

                STATE_AP2_PROCESS: begin
                    reverb_wet_sample <= saturate_s18_to_s16(ap2_output_wide);
                    allpass_pointer_2 <= (allpass_pointer_2 == 8'd112)
                                       ? 8'd0 : allpass_pointer_2 + 8'd1;
                    if (allpass_fill_2 < 9'd113)
                        allpass_fill_2 <= allpass_fill_2 + 9'd1;
                    state <= STATE_MIX;
                end

                STATE_MIX: begin
                    if (mix_latched == 7'd0)
                        sample_out <= dry_sample_latched;
                    else if (mix_latched == 7'd127)
                        sample_out <= reverb_wet_sample;
                    else
                        sample_out <= saturate_s26_to_s16(mixed_sample_wide);
                    out_valid <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
