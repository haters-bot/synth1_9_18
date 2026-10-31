// 四延迟线反馈延迟网络（FDN）混响。
//
// 外部接口仍只使用 Size、Decay、Mix 三个参数：
//   Size  控制四条互质延迟线的长度；
//   Decay 使用非线性映射控制反馈增益；
//   Mix   控制干湿比例。
//
// 四条延迟线并行读取，但阻尼、反馈乘法和写回按通道分时完成，
// 因而只需要一条反馈乘法路径。每个输入样本约占 17 个 50 MHz 时钟，
// 远低于 96 kHz 采样周期所提供的 520 个时钟。
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

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_FDN_READ    = 4'd1;
    localparam [3:0] STATE_FDN_CAPTURE = 4'd2;
    localparam [3:0] STATE_FDN_DAMP    = 4'd3;
    localparam [3:0] STATE_FDN_WRITE   = 4'd4;
    localparam [3:0] STATE_AP1_READ    = 4'd5;
    localparam [3:0] STATE_AP1_PROCESS = 4'd6;
    localparam [3:0] STATE_AP2_READ    = 4'd7;
    localparam [3:0] STATE_AP2_PROCESS = 4'd8;
    localparam [3:0] STATE_DC_BLOCK    = 4'd9;
    localparam [3:0] STATE_MIX         = 4'd10;

    // 18 位内部存储为反馈累加保留余量。数组不在复位时清零，
    // fill 计数器会在历史数据有效前将 RAM 输出屏蔽为零。
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] fdn_memory_0 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] fdn_memory_1 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] fdn_memory_2 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] fdn_memory_3 [0:4095];
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] allpass_memory_1 [0:511];
    (* syn_ramstyle = "block_ram" *) reg signed [17:0] allpass_memory_2 [0:255];

    reg [3:0] state;
    reg [1:0] channel_index;
    reg signed [15:0] dry_sample_latched;

    reg [11:0] fdn_length_0;
    reg [11:0] fdn_length_1;
    reg [11:0] fdn_length_2;
    reg [11:0] fdn_length_3;
    reg [11:0] fdn_pointer_0;
    reg [11:0] fdn_pointer_1;
    reg [11:0] fdn_pointer_2;
    reg [11:0] fdn_pointer_3;
    reg [12:0] fdn_fill_0;
    reg [12:0] fdn_fill_1;
    reg [12:0] fdn_fill_2;
    reg [12:0] fdn_fill_3;

    reg signed [17:0] fdn_read_data_0;
    reg signed [17:0] fdn_read_data_1;
    reg signed [17:0] fdn_read_data_2;
    reg signed [17:0] fdn_read_data_3;
    reg signed [17:0] fdn_delayed_0;
    reg signed [17:0] fdn_delayed_1;
    reg signed [17:0] fdn_delayed_2;
    reg signed [17:0] fdn_delayed_3;
    reg signed [17:0] fdn_damp_0;
    reg signed [17:0] fdn_damp_1;
    reg signed [17:0] fdn_damp_2;
    reg signed [17:0] fdn_damp_3;
    reg signed [17:0] fdn_damped_0;
    reg signed [17:0] fdn_damped_1;
    reg signed [17:0] fdn_damped_2;
    reg signed [17:0] fdn_damped_3;

    reg [15:0] feedback_gain_smoothed_q15;
    reg [15:0] feedback_gain_latched_q15;
    reg [6:0] mix_smoothed;
    reg [6:0] mix_latched;

    reg [8:0] allpass_pointer_1;
    reg [7:0] allpass_pointer_2;
    reg [9:0] allpass_fill_1;
    reg [8:0] allpass_fill_2;
    reg signed [17:0] allpass_read_data_1;
    reg signed [17:0] allpass_read_data_2;
    reg signed [17:0] allpass_1_output;
    reg signed [17:0] allpass_2_output;

    reg signed [17:0] dc_input_previous;
    reg signed [17:0] dc_output_previous;
    reg signed [17:0] reverb_wet_sample;

    // 互不成整数倍的奇数长度可以减少明显的金属共振。
    // 乘常数只使用移位和加减，不引入额外乘法器。
    wire [13:0] size_times_9 = {7'd0, size_control}
                                  + ({7'd0, size_control} << 3);
    wire [13:0] size_times_11 = {7'd0, size_control}
                                   + ({7'd0, size_control} << 1)
                                   + ({7'd0, size_control} << 3);
    wire [13:0] size_times_13 = {7'd0, size_control}
                                   + ({7'd0, size_control} << 2)
                                   + ({7'd0, size_control} << 3);
    wire [13:0] size_times_15 = ({7'd0, size_control} << 4)
                                   - {7'd0, size_control};
    wire [11:0] requested_length_0 = (12'd1153 + size_times_9[11:0]) | 12'd1;
    wire [11:0] requested_length_1 = (12'd1399 + size_times_11[11:0]) | 12'd1;
    wire [11:0] requested_length_2 = (12'd1667 + size_times_13[11:0]) | 12'd1;
    wire [11:0] requested_length_3 = (12'd1999 + size_times_15[11:0]) | 12'd1;
    wire [11:0] next_length_0 = slew_delay_length(fdn_length_0,
                                                   requested_length_0);
    wire [11:0] next_length_1 = slew_delay_length(fdn_length_1,
                                                   requested_length_1);
    wire [11:0] next_length_2 = slew_delay_length(fdn_length_2,
                                                   requested_length_2);
    wire [11:0] next_length_3 = slew_delay_length(fdn_length_3,
                                                   requested_length_3);

    wire [15:0] feedback_gain_target_q15 = decay_to_gain_q15(decay_control);
    wire [15:0] feedback_gain_next_q15 =
        slew_gain_q15(feedback_gain_smoothed_q15, feedback_gain_target_q15);
    wire [6:0] mix_next = slew_mix(mix_smoothed, mix_control);

    reg signed [17:0] selected_delayed;
    reg signed [17:0] selected_damp;
    always @(*) begin
        case (channel_index)
            2'd0: begin
                selected_delayed = fdn_delayed_0;
                selected_damp = fdn_damp_0;
            end
            2'd1: begin
                selected_delayed = fdn_delayed_1;
                selected_damp = fdn_damp_1;
            end
            2'd2: begin
                selected_delayed = fdn_delayed_2;
                selected_damp = fdn_damp_2;
            end
            default: begin
                selected_delayed = fdn_delayed_3;
                selected_damp = fdn_damp_3;
            end
        endcase
    end

    wire signed [18:0] damping_difference =
        $signed({selected_delayed[17], selected_delayed})
        - $signed({selected_damp[17], selected_damp});
    reg signed [19:0] damping_delta;
    always @(*) begin
        case (channel_index)
            2'd0: damping_delta = $signed(damping_difference) >>> 2; // 1/4
            2'd1: damping_delta = ($signed(damping_difference) >>> 2)
                                      + ($signed(damping_difference) >>> 4); // 5/16
            2'd2: damping_delta = ($signed(damping_difference) >>> 2)
                                      + ($signed(damping_difference) >>> 3); // 3/8
            default: damping_delta = ($signed(damping_difference) >>> 1)
                                      - ($signed(damping_difference) >>> 4); // 7/16
        endcase
    end
    wire signed [19:0] damped_next_wide =
        $signed({{2{selected_damp[17]}}, selected_damp}) + damping_delta;
    wire signed [17:0] damped_next = saturate_s20_to_s18(damped_next_wide);

    // 归一化 4x4 Hadamard 矩阵。除以 2 后能量增益为 1，
    // 四条反馈路径会互相扩散，不再形成四组彼此独立的梳状尾音。
    wire signed [19:0] hadamard_0 =
        ($signed({{2{fdn_damped_0[17]}}, fdn_damped_0})
        + $signed({{2{fdn_damped_1[17]}}, fdn_damped_1})
        + $signed({{2{fdn_damped_2[17]}}, fdn_damped_2})
        + $signed({{2{fdn_damped_3[17]}}, fdn_damped_3})) >>> 1;
    wire signed [19:0] hadamard_1 =
        ($signed({{2{fdn_damped_0[17]}}, fdn_damped_0})
        - $signed({{2{fdn_damped_1[17]}}, fdn_damped_1})
        + $signed({{2{fdn_damped_2[17]}}, fdn_damped_2})
        - $signed({{2{fdn_damped_3[17]}}, fdn_damped_3})) >>> 1;
    wire signed [19:0] hadamard_2 =
        ($signed({{2{fdn_damped_0[17]}}, fdn_damped_0})
        + $signed({{2{fdn_damped_1[17]}}, fdn_damped_1})
        - $signed({{2{fdn_damped_2[17]}}, fdn_damped_2})
        - $signed({{2{fdn_damped_3[17]}}, fdn_damped_3})) >>> 1;
    wire signed [19:0] hadamard_3 =
        ($signed({{2{fdn_damped_0[17]}}, fdn_damped_0})
        - $signed({{2{fdn_damped_1[17]}}, fdn_damped_1})
        - $signed({{2{fdn_damped_2[17]}}, fdn_damped_2})
        + $signed({{2{fdn_damped_3[17]}}, fdn_damped_3})) >>> 1;

    reg signed [19:0] selected_hadamard;
    always @(*) begin
        case (channel_index)
            2'd0: selected_hadamard = hadamard_0;
            2'd1: selected_hadamard = hadamard_1;
            2'd2: selected_hadamard = hadamard_2;
            default: selected_hadamard = hadamard_3;
        endcase
    end

    wire signed [36:0] feedback_product =
        selected_hadamard * $signed({1'b0, feedback_gain_latched_q15});
    // 负数的算术右移会向负无穷舍入，使很小的负反馈长期停在 -1。
    // 这里对正负值都向零截断，消除固定点反馈中的最低位极限环。
    wire signed [36:0] feedback_scaled_full = (feedback_product >= 0)
        ? ($signed(feedback_product) >>> 15)
        : -($signed(-feedback_product) >>> 15);
    wire signed [21:0] feedback_scaled = feedback_scaled_full[21:0];
    wire signed [21:0] fdn_write_wide =
        $signed({{6{dry_sample_latched[15]}}, dry_sample_latched})
        + feedback_scaled;
    wire signed [17:0] fdn_write_data = saturate_s22_to_s18(fdn_write_wide);

    wire signed [19:0] fdn_output_sum =
        $signed({{2{fdn_delayed_0[17]}}, fdn_delayed_0})
        + $signed({{2{fdn_delayed_1[17]}}, fdn_delayed_1})
        + $signed({{2{fdn_delayed_2[17]}}, fdn_delayed_2})
        + $signed({{2{fdn_delayed_3[17]}}, fdn_delayed_3});
    wire signed [17:0] fdn_wet_input =
        saturate_s20_to_s18($signed(fdn_output_sum) >>> 2);

    // 标准全通结构：w[n] = x[n] + g*d[n]，y[n] = d[n] - g*w[n]。
    // 旧实现的输出使用了 x[n]，会破坏全通幅频特性；这里改为使用 w[n]。
    wire signed [17:0] ap1_delayed = (allpass_fill_1 >= 10'd347)
                                            ? allpass_read_data_1 : 18'sd0;
    wire signed [19:0] ap1_write_wide =
        $signed({{2{fdn_wet_input[17]}}, fdn_wet_input})
        + ($signed({{2{ap1_delayed[17]}}, ap1_delayed}) >>> 1);
    wire signed [17:0] ap1_write_data = saturate_s20_to_s18(ap1_write_wide);
    wire signed [19:0] ap1_output_wide =
        $signed({{2{ap1_delayed[17]}}, ap1_delayed})
        - ($signed({{2{ap1_write_data[17]}}, ap1_write_data}) >>> 1);

    wire signed [17:0] ap2_delayed = (allpass_fill_2 >= 9'd113)
                                            ? allpass_read_data_2 : 18'sd0;
    wire signed [19:0] ap2_write_wide =
        $signed({{2{allpass_1_output[17]}}, allpass_1_output})
        + ($signed({{2{ap2_delayed[17]}}, ap2_delayed}) >>> 1);
    wire signed [17:0] ap2_write_data = saturate_s20_to_s18(ap2_write_wide);
    wire signed [19:0] ap2_output_wide =
        $signed({{2{ap2_delayed[17]}}, ap2_delayed})
        - ($signed({{2{ap2_write_data[17]}}, ap2_write_data}) >>> 1);

    // 湿声直流阻断器：y[n]=x[n]-x[n-1]+0.996*y[n-1]。
    // 0.996 近似为 1-1/256，避免新增乘法器。
    wire signed [18:0] dc_previous_extended =
        $signed({dc_output_previous[17], dc_output_previous});
    wire signed [18:0] dc_leak = (dc_previous_extended > 0)
        ? (($signed(dc_previous_extended) + 19'sd255) >>> 8)
        : ((dc_previous_extended < 0)
            ? -(($signed(-dc_previous_extended) + 19'sd255) >>> 8)
            : 19'sd0);
    wire signed [19:0] dc_block_wide =
        $signed({{2{allpass_2_output[17]}}, allpass_2_output})
        - $signed({{2{dc_input_previous[17]}}, dc_input_previous})
        + $signed({{2{dc_output_previous[17]}}, dc_output_previous})
        - $signed({dc_leak[18], dc_leak});
    wire signed [17:0] dc_block_output = saturate_s20_to_s18(dc_block_wide);

    wire signed [18:0] wet_dry_difference =
        $signed({reverb_wet_sample[17], reverb_wet_sample})
        - $signed({{3{dry_sample_latched[15]}}, dry_sample_latched});
    wire signed [26:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [27:0] mixed_sample_wide =
        $signed({{12{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_product) >>> 7);

    assign in_ready = state == STATE_IDLE;

    function [15:0] decay_to_gain_q15;
        input [6:0] value;
        reg [15:0] offset;
        begin
            // 0、32、64、96、127 分别约为 0、0.55、0.78、0.90、0.96。
            // 低段保留可听的短尾音，高段提供更长衰减但仍低于自激阈值。
            if (value == 7'd0)
                decay_to_gain_q15 = 16'd0;
            else if (value <= 7'd32) begin
                offset = value;
                decay_to_gain_q15 = (offset << 9) + (offset << 5)
                                    + (offset << 4) + (offset << 1) + offset;
            end else if (value <= 7'd64) begin
                offset = value - 7'd32;
                decay_to_gain_q15 = 16'd18016 + (offset << 8)
                                    - (offset << 4) - (offset << 2);
            end else if (value <= 7'd96) begin
                offset = value - 7'd64;
                decay_to_gain_q15 = 16'd25568 + (offset << 7)
                                    - (offset << 2) - offset;
            end else begin
                offset = value - 7'd96;
                decay_to_gain_q15 = 16'd29504 + (offset << 6) - offset;
            end
        end
    endfunction

    function [15:0] slew_gain_q15;
        input [15:0] current_value;
        input [15:0] target_value;
        begin
            if (target_value == 16'd0)
                slew_gain_q15 = 16'd0;
            else if (target_value > current_value + 16'd256)
                slew_gain_q15 = current_value + 16'd256;
            else if (current_value > target_value + 16'd256)
                slew_gain_q15 = current_value - 16'd256;
            else
                slew_gain_q15 = target_value;
        end
    endfunction

    function [6:0] slew_mix;
        input [6:0] current_value;
        input [6:0] target_value;
        begin
            if (target_value == 7'd0)
                slew_mix = 7'd0;
            else if (target_value > current_value)
                slew_mix = current_value + 7'd1;
            else if (current_value > target_value)
                slew_mix = current_value - 7'd1;
            else
                slew_mix = current_value;
        end
    endfunction

    function [11:0] slew_delay_length;
        input [11:0] current_value;
        input [11:0] target_value;
        begin
            if (target_value > current_value + 12'd64)
                slew_delay_length = current_value + 12'd64;
            else if (current_value > target_value + 12'd64)
                slew_delay_length = current_value - 12'd64;
            else
                slew_delay_length = target_value;
        end
    endfunction

    function [12:0] update_fill_after_write;
        input [12:0] current_fill;
        input [11:0] old_length;
        input [11:0] new_length;
        reg [12:0] filled_value;
        begin
            filled_value = current_fill;
            if (filled_value < {1'b0, old_length})
                filled_value = filled_value + 13'd1;
            if (filled_value > {1'b0, new_length})
                filled_value = {1'b0, new_length};
            update_fill_after_write = filled_value;
        end
    endfunction

    function signed [17:0] saturate_s20_to_s18;
        input signed [19:0] value;
        begin
            if (value > 20'sd131071)
                saturate_s20_to_s18 = 18'sh1FFFF;
            else if (value < -20'sd131072)
                saturate_s20_to_s18 = 18'sh20000;
            else
                saturate_s20_to_s18 = value[17:0];
        end
    endfunction

    function signed [17:0] saturate_s22_to_s18;
        input signed [21:0] value;
        begin
            if (value > 22'sd131071)
                saturate_s22_to_s18 = 18'sh1FFFF;
            else if (value < -22'sd131072)
                saturate_s22_to_s18 = 18'sh20000;
            else
                saturate_s22_to_s18 = value[17:0];
        end
    endfunction

    function signed [15:0] saturate_s28_to_s16;
        input signed [27:0] value;
        begin
            if (value > 28'sd32767)
                saturate_s28_to_s16 = 16'sh7FFF;
            else if (value < -28'sd32768)
                saturate_s28_to_s16 = 16'sh8000;
            else
                saturate_s28_to_s16 = value[15:0];
        end
    endfunction

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

    // 每个数组均使用独立的同步读寄存器，读写状态互斥，便于 Gowin
    // 将其识别为 BSRAM，而不是展开为触发器和大型选择器。
    always @(posedge clk) begin
        if (state == STATE_FDN_READ)
            fdn_read_data_0 <= fdn_memory_0[fdn_pointer_0];
    end
    always @(posedge clk) begin
        if ((state == STATE_FDN_WRITE) && (channel_index == 2'd0))
            fdn_memory_0[fdn_pointer_0] <= fdn_write_data;
    end

    always @(posedge clk) begin
        if (state == STATE_FDN_READ)
            fdn_read_data_1 <= fdn_memory_1[fdn_pointer_1];
    end
    always @(posedge clk) begin
        if ((state == STATE_FDN_WRITE) && (channel_index == 2'd1))
            fdn_memory_1[fdn_pointer_1] <= fdn_write_data;
    end

    always @(posedge clk) begin
        if (state == STATE_FDN_READ)
            fdn_read_data_2 <= fdn_memory_2[fdn_pointer_2];
    end
    always @(posedge clk) begin
        if ((state == STATE_FDN_WRITE) && (channel_index == 2'd2))
            fdn_memory_2[fdn_pointer_2] <= fdn_write_data;
    end

    always @(posedge clk) begin
        if (state == STATE_FDN_READ)
            fdn_read_data_3 <= fdn_memory_3[fdn_pointer_3];
    end
    always @(posedge clk) begin
        if ((state == STATE_FDN_WRITE) && (channel_index == 2'd3))
            fdn_memory_3[fdn_pointer_3] <= fdn_write_data;
    end

    always @(posedge clk) begin
        if (state == STATE_AP1_READ)
            allpass_read_data_1 <= allpass_memory_1[allpass_pointer_1];
    end
    always @(posedge clk) begin
        if (state == STATE_AP1_PROCESS)
            allpass_memory_1[allpass_pointer_1] <= ap1_write_data;
    end

    always @(posedge clk) begin
        if (state == STATE_AP2_READ)
            allpass_read_data_2 <= allpass_memory_2[allpass_pointer_2];
    end
    always @(posedge clk) begin
        if (state == STATE_AP2_PROCESS)
            allpass_memory_2[allpass_pointer_2] <= ap2_write_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            channel_index <= 2'd0;
            dry_sample_latched <= 16'sd0;
            fdn_length_0 <= 12'd1153;
            fdn_length_1 <= 12'd1399;
            fdn_length_2 <= 12'd1667;
            fdn_length_3 <= 12'd1999;
            fdn_pointer_0 <= 12'd0;
            fdn_pointer_1 <= 12'd0;
            fdn_pointer_2 <= 12'd0;
            fdn_pointer_3 <= 12'd0;
            fdn_fill_0 <= 13'd0;
            fdn_fill_1 <= 13'd0;
            fdn_fill_2 <= 13'd0;
            fdn_fill_3 <= 13'd0;
            fdn_delayed_0 <= 18'sd0;
            fdn_delayed_1 <= 18'sd0;
            fdn_delayed_2 <= 18'sd0;
            fdn_delayed_3 <= 18'sd0;
            fdn_damp_0 <= 18'sd0;
            fdn_damp_1 <= 18'sd0;
            fdn_damp_2 <= 18'sd0;
            fdn_damp_3 <= 18'sd0;
            fdn_damped_0 <= 18'sd0;
            fdn_damped_1 <= 18'sd0;
            fdn_damped_2 <= 18'sd0;
            fdn_damped_3 <= 18'sd0;
            feedback_gain_smoothed_q15 <= 16'd0;
            feedback_gain_latched_q15 <= 16'd0;
            mix_smoothed <= 7'd0;
            mix_latched <= 7'd0;
            allpass_pointer_1 <= 9'd0;
            allpass_pointer_2 <= 8'd0;
            allpass_fill_1 <= 10'd0;
            allpass_fill_2 <= 9'd0;
            allpass_1_output <= 18'sd0;
            allpass_2_output <= 18'sd0;
            dc_input_previous <= 18'sd0;
            dc_output_previous <= 18'sd0;
            reverb_wet_sample <= 18'sd0;
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
                        feedback_gain_smoothed_q15 <= feedback_gain_next_q15;
                        feedback_gain_latched_q15 <= feedback_gain_next_q15;
                        mix_smoothed <= mix_next;
                        mix_latched <= mix_next;
                        state <= STATE_FDN_READ;
                    end
                end

                STATE_FDN_READ: begin
                    state <= STATE_FDN_CAPTURE;
                end

                STATE_FDN_CAPTURE: begin
                    fdn_delayed_0 <= (fdn_fill_0 >= {1'b0, fdn_length_0})
                                         ? fdn_read_data_0 : 18'sd0;
                    fdn_delayed_1 <= (fdn_fill_1 >= {1'b0, fdn_length_1})
                                         ? fdn_read_data_1 : 18'sd0;
                    fdn_delayed_2 <= (fdn_fill_2 >= {1'b0, fdn_length_2})
                                         ? fdn_read_data_2 : 18'sd0;
                    fdn_delayed_3 <= (fdn_fill_3 >= {1'b0, fdn_length_3})
                                         ? fdn_read_data_3 : 18'sd0;
                    channel_index <= 2'd0;
                    state <= STATE_FDN_DAMP;
                end

                STATE_FDN_DAMP: begin
                    case (channel_index)
                        2'd0: begin
                            fdn_damp_0 <= damped_next;
                            fdn_damped_0 <= damped_next;
                        end
                        2'd1: begin
                            fdn_damp_1 <= damped_next;
                            fdn_damped_1 <= damped_next;
                        end
                        2'd2: begin
                            fdn_damp_2 <= damped_next;
                            fdn_damped_2 <= damped_next;
                        end
                        default: begin
                            fdn_damp_3 <= damped_next;
                            fdn_damped_3 <= damped_next;
                        end
                    endcase
                    if (channel_index == 2'd3) begin
                        channel_index <= 2'd0;
                        state <= STATE_FDN_WRITE;
                    end else begin
                        channel_index <= channel_index + 2'd1;
                    end
                end

                STATE_FDN_WRITE: begin
                    case (channel_index)
                        2'd0: begin
                            if (fdn_pointer_0 + 12'd1 >= fdn_length_0) begin
                                // 长度增加时先从新增地址开始写零历史，避免
                                // 将尚未初始化的 RAM 单元当作有效反馈数据。
                                fdn_pointer_0 <= (next_length_0 > fdn_length_0)
                                                     ? fdn_length_0 : 12'd0;
                                fdn_length_0 <= next_length_0;
                                fdn_fill_0 <= update_fill_after_write(
                                    fdn_fill_0, fdn_length_0, next_length_0);
                            end else begin
                                fdn_pointer_0 <= fdn_pointer_0 + 12'd1;
                                fdn_fill_0 <= update_fill_after_write(
                                    fdn_fill_0, fdn_length_0, fdn_length_0);
                            end
                        end
                        2'd1: begin
                            if (fdn_pointer_1 + 12'd1 >= fdn_length_1) begin
                                fdn_pointer_1 <= (next_length_1 > fdn_length_1)
                                                     ? fdn_length_1 : 12'd0;
                                fdn_length_1 <= next_length_1;
                                fdn_fill_1 <= update_fill_after_write(
                                    fdn_fill_1, fdn_length_1, next_length_1);
                            end else begin
                                fdn_pointer_1 <= fdn_pointer_1 + 12'd1;
                                fdn_fill_1 <= update_fill_after_write(
                                    fdn_fill_1, fdn_length_1, fdn_length_1);
                            end
                        end
                        2'd2: begin
                            if (fdn_pointer_2 + 12'd1 >= fdn_length_2) begin
                                fdn_pointer_2 <= (next_length_2 > fdn_length_2)
                                                     ? fdn_length_2 : 12'd0;
                                fdn_length_2 <= next_length_2;
                                fdn_fill_2 <= update_fill_after_write(
                                    fdn_fill_2, fdn_length_2, next_length_2);
                            end else begin
                                fdn_pointer_2 <= fdn_pointer_2 + 12'd1;
                                fdn_fill_2 <= update_fill_after_write(
                                    fdn_fill_2, fdn_length_2, fdn_length_2);
                            end
                        end
                        default: begin
                            if (fdn_pointer_3 + 12'd1 >= fdn_length_3) begin
                                fdn_pointer_3 <= (next_length_3 > fdn_length_3)
                                                     ? fdn_length_3 : 12'd0;
                                fdn_length_3 <= next_length_3;
                                fdn_fill_3 <= update_fill_after_write(
                                    fdn_fill_3, fdn_length_3, next_length_3);
                            end else begin
                                fdn_pointer_3 <= fdn_pointer_3 + 12'd1;
                                fdn_fill_3 <= update_fill_after_write(
                                    fdn_fill_3, fdn_length_3, fdn_length_3);
                            end
                        end
                    endcase

                    if (channel_index == 2'd3) begin
                        state <= STATE_AP1_READ;
                    end else begin
                        channel_index <= channel_index + 2'd1;
                    end
                end

                STATE_AP1_READ: begin
                    state <= STATE_AP1_PROCESS;
                end

                STATE_AP1_PROCESS: begin
                    allpass_1_output <= saturate_s20_to_s18(ap1_output_wide);
                    allpass_pointer_1 <= (allpass_pointer_1 == 9'd346)
                                             ? 9'd0 : allpass_pointer_1 + 9'd1;
                    if (allpass_fill_1 < 10'd347)
                        allpass_fill_1 <= allpass_fill_1 + 10'd1;
                    state <= STATE_AP2_READ;
                end

                STATE_AP2_READ: begin
                    state <= STATE_AP2_PROCESS;
                end

                STATE_AP2_PROCESS: begin
                    allpass_2_output <= saturate_s20_to_s18(ap2_output_wide);
                    allpass_pointer_2 <= (allpass_pointer_2 == 8'd112)
                                             ? 8'd0 : allpass_pointer_2 + 8'd1;
                    if (allpass_fill_2 < 9'd113)
                        allpass_fill_2 <= allpass_fill_2 + 9'd1;
                    state <= STATE_DC_BLOCK;
                end

                STATE_DC_BLOCK: begin
                    dc_input_previous <= allpass_2_output;
                    dc_output_previous <= dc_block_output;
                    reverb_wet_sample <= dc_block_output;
                    state <= STATE_MIX;
                end

                STATE_MIX: begin
                    if (mix_latched == 7'd0)
                        sample_out <= dry_sample_latched;
                    else if (mix_latched == 7'd127)
                        sample_out <= saturate_s18_to_s16(reverb_wet_sample);
                    else
                        sample_out <= saturate_s28_to_s16(mixed_sample_wide);
                    out_valid <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
