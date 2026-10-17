// 三控制点、两段曲率的全局滤波器LFO。
//
// 上位机只在配置变化时写入影子寄存器，并用PARAM_COMMIT一次性提交。
// LFO随后在96 kHz sample_tick上独立运行，不再依赖串口周期性发送Cutoff值。
// 两段各自使用24位局部相位累加器；phase_step由上位机根据LFO速率和
// 中间控制点时间计算，因此运行期间没有动态除法器。
module filter_curve_lfo #(
    parameter [6:0] PARAM_ENABLE = 7'd16,
    parameter [6:0] PARAM_STEP_0 = 7'd17,
    parameter [6:0] PARAM_STEP_1 = 7'd18,
    parameter [6:0] PARAM_DEPTH  = 7'd19,
    parameter [6:0] PARAM_POINT_0 = 7'd20,
    parameter [6:0] PARAM_POINT_1 = 7'd21,
    parameter [6:0] PARAM_POINT_2 = 7'd22,
    parameter [6:0] PARAM_CURVE_0 = 7'd23,
    parameter [6:0] PARAM_CURVE_1 = 7'd24,
    parameter [6:0] PARAM_COMMIT  = 7'd25
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire        parameter_valid,
    input  wire [6:0]  parameter_id,
    input  wire [13:0] parameter_value,
    input  wire [2:0]  filter_mode,
    input  wire [14:0] base_cutoff_q8,
    output reg  [14:0] cutoff_q8,
    output wire        lfo_enabled,
    output reg         active_segment,
    output reg  [23:0] segment_phase
);

    localparam [13:0] DEPTH_SLEW_STEP = 14'd16;
    localparam [14:0] MAX_CUTOFF_Q8 = {7'd127, 8'd0};

    // 影子配置：多条SysEx写入期间不会扰动正在运行的LFO。
    reg        shadow_enable;
    reg [13:0] shadow_step_0;
    reg [13:0] shadow_step_1;
    reg [13:0] shadow_depth;
    reg [13:0] shadow_point_0;
    reg [13:0] shadow_point_1;
    reg [13:0] shadow_point_2;
    reg [13:0] shadow_curve_0;
    reg [13:0] shadow_curve_1;

    reg        active_enable;
    reg [13:0] active_step_0;
    reg [13:0] active_step_1;
    reg [13:0] active_depth;
    reg [13:0] active_point_0;
    reg [13:0] active_point_1;
    reg [13:0] active_point_2;
    reg [13:0] active_curve_0;
    reg [13:0] active_curve_1;
    reg [13:0] depth_current;

    wire [13:0] selected_phase_step = active_segment
                                          ? active_step_1 : active_step_0;
    wire [24:0] segment_phase_sum = {1'b0, segment_phase}
                                   + {11'd0, selected_phase_step};
    wire comb_filter_mode = (filter_mode == 3'd5)
                          || (filter_mode == 3'd6);
    // 141/256约等于70/127。Depth协议继续使用0～127，Comb模式的
    // 实际上限约为70；乘以常数141可由综合器实现为移位加法。
    wire [21:0] comb_depth_product = active_depth * 8'd141;
    wire [13:0] comb_depth_scaled =
        (comb_depth_product + 22'd128) >> 8;
    wire [13:0] effective_depth_target = comb_filter_mode
                                       ? comb_depth_scaled : active_depth;

    assign lfo_enabled = active_enable;

    // 六级流水线只在sample_tick装入新任务，约120 ns后得到新的Cutoff。
    reg valid_0;
    reg valid_1;
    reg valid_2;
    reg valid_3;
    reg valid_4;
    reg valid_5;

    reg [12:0] s0_t;
    reg signed [14:0] s0_y0;
    reg signed [14:0] s0_y1;
    reg signed [14:0] s0_curve;
    reg [13:0] s0_depth;
    reg [14:0] s0_base;

    reg [12:0] s1_t;
    reg [26:0] s1_t_square;
    reg [26:0] s1_one_minus_t_square;
    reg signed [14:0] s1_y0;
    reg signed [14:0] s1_y1;
    reg signed [14:0] s1_curve;
    reg [13:0] s1_depth;
    reg [14:0] s1_base;

    reg [27:0] s2_smooth_product;
    reg [26:0] s2_bump_product;
    reg signed [14:0] s2_y0;
    reg signed [14:0] s2_y1;
    reg signed [14:0] s2_curve;
    reg [13:0] s2_depth;
    reg [14:0] s2_base;

    reg signed [14:0] s3_y0;
    reg signed [14:0] s3_y1;
    reg [13:0] s3_smooth_q13;
    reg signed [29:0] s3_curve_adjust_product;
    reg [13:0] s3_depth;
    reg [14:0] s3_base;

    reg signed [14:0] s4_y0;
    reg signed [30:0] s4_interpolation_product;
    reg [13:0] s4_depth;
    reg [14:0] s4_base;

    reg signed [30:0] s5_modulation_product;
    reg [14:0] s5_base;

    wire [13:0] s1_t_squared_q13 = s1_t_square[26:13];
    wire [13:0] s1_one_minus_t_squared_q13 =
        s1_one_minus_t_square[26:13];
    wire [14:0] s1_smooth_factor = 15'd24576 - {1'b0, s1_t, 1'b0};
    wire [13:0] s2_smooth_q13 = s2_smooth_product[27:13];
    wire [13:0] s2_bump_q13 =
        (s2_bump_product[26:13] << 1) + s2_bump_product[26:13];
    wire signed [31:0] s3_shaped_unclamped =
        $signed({18'd0, s3_smooth_q13})
        - (s3_curve_adjust_product >>> 13);
    wire [13:0] s3_shaped_t = s3_shaped_unclamped < 0
                            ? 14'd0
                            : (s3_shaped_unclamped > 32'sd8192
                               ? 14'd8192
                               : s3_shaped_unclamped[13:0]);
    wire signed [15:0] s3_level_delta = s3_y1 - s3_y0;
    wire signed [15:0] s4_level_q13 =
        s4_y0 + (s4_interpolation_product >>> 13);
    wire signed [31:0] s6_cutoff_unclamped =
        $signed({1'b0, s5_base}) + (s5_modulation_product >>> 12);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_enable  <= 1'b0;
            shadow_step_0  <= 14'd175;
            shadow_step_1  <= 14'd175;
            shadow_depth   <= 14'd4096;
            shadow_point_0 <= 14'd0;
            shadow_point_1 <= 14'd16383;
            shadow_point_2 <= 14'd0;
            shadow_curve_0 <= 14'd8192;
            shadow_curve_1 <= 14'd8192;

            active_enable  <= 1'b0;
            active_step_0  <= 14'd175;
            active_step_1  <= 14'd175;
            active_depth   <= 14'd4096;
            active_point_0 <= 14'd0;
            active_point_1 <= 14'd16383;
            active_point_2 <= 14'd0;
            active_curve_0 <= 14'd8192;
            active_curve_1 <= 14'd8192;
            depth_current  <= 14'd0;
            active_segment <= 1'b0;
            segment_phase  <= 24'd0;
            cutoff_q8      <= MAX_CUTOFF_Q8;

            valid_0 <= 1'b0;
            valid_1 <= 1'b0;
            valid_2 <= 1'b0;
            valid_3 <= 1'b0;
            valid_4 <= 1'b0;
            valid_5 <= 1'b0;
        end else begin
            valid_0 <= sample_tick;
            valid_1 <= valid_0;
            valid_2 <= valid_1;
            valid_3 <= valid_2;
            valid_4 <= valid_3;
            valid_5 <= valid_4;

            if (parameter_valid) begin
                case (parameter_id)
                    PARAM_ENABLE:  shadow_enable  <= parameter_value != 14'd0;
                    PARAM_STEP_0:  shadow_step_0  <= parameter_value;
                    PARAM_STEP_1:  shadow_step_1  <= parameter_value;
                    PARAM_DEPTH:   shadow_depth   <= parameter_value;
                    PARAM_POINT_0: shadow_point_0 <= parameter_value;
                    PARAM_POINT_1: shadow_point_1 <= parameter_value;
                    PARAM_POINT_2: shadow_point_2 <= parameter_value;
                    PARAM_CURVE_0: shadow_curve_0 <= parameter_value;
                    PARAM_CURVE_1: shadow_curve_1 <= parameter_value;
                    PARAM_COMMIT: begin
                        active_enable  <= shadow_enable;
                        active_step_0  <= shadow_step_0 == 14'd0
                                        ? 14'd1 : shadow_step_0;
                        active_step_1  <= shadow_step_1 == 14'd0
                                        ? 14'd1 : shadow_step_1;
                        active_depth   <= shadow_depth;
                        active_point_0 <= shadow_point_0;
                        active_point_1 <= shadow_point_1;
                        active_point_2 <= shadow_point_2;
                        active_curve_0 <= shadow_curve_0;
                        active_curve_1 <= shadow_curve_1;
                        if (!active_enable && shadow_enable) begin
                            active_segment <= 1'b0;
                            segment_phase  <= 24'd0;
                        end
                    end
                    default: begin
                    end
                endcase
            end

            if (sample_tick) begin
                if (active_enable) begin
                    if (segment_phase_sum[24]) begin
                        segment_phase  <= segment_phase_sum[23:0];
                        active_segment <= ~active_segment;
                    end else begin
                        segment_phase <= segment_phase_sum[23:0];
                    end
                end else if (depth_current == 14'd0) begin
                    active_segment <= 1'b0;
                    segment_phase  <= 24'd0;
                end

                if (active_enable) begin
                    if ((depth_current < effective_depth_target)
                        && ((effective_depth_target - depth_current)
                            > DEPTH_SLEW_STEP))
                        depth_current <= depth_current + DEPTH_SLEW_STEP;
                    else if (depth_current < effective_depth_target)
                        depth_current <= effective_depth_target;
                    else if ((depth_current > effective_depth_target)
                             && ((depth_current - effective_depth_target)
                                 > DEPTH_SLEW_STEP))
                        depth_current <= depth_current - DEPTH_SLEW_STEP;
                    else if (depth_current > effective_depth_target)
                        depth_current <= effective_depth_target;
                end else begin
                    if (depth_current > DEPTH_SLEW_STEP)
                        depth_current <= depth_current - DEPTH_SLEW_STEP;
                    else
                        depth_current <= 14'd0;
                end

                s0_t     <= segment_phase[23:11];
                s0_depth <= depth_current;
                s0_base  <= base_cutoff_q8;
                if (!active_segment) begin
                    s0_y0    <= $signed({1'b0, active_point_0}) - 15'sd8192;
                    s0_y1    <= $signed({1'b0, active_point_1}) - 15'sd8192;
                    s0_curve <= $signed({1'b0, active_curve_0}) - 15'sd8192;
                end else begin
                    s0_y0    <= $signed({1'b0, active_point_1}) - 15'sd8192;
                    s0_y1    <= $signed({1'b0, active_point_2}) - 15'sd8192;
                    s0_curve <= $signed({1'b0, active_curve_1}) - 15'sd8192;
                end
            end

            if (valid_0) begin
                s1_t        <= s0_t;
                s1_t_square <= s0_t * s0_t;
                s1_one_minus_t_square <= (14'd8192 - {1'b0, s0_t})
                                         * (14'd8192 - {1'b0, s0_t});
                s1_y0       <= s0_y0;
                s1_y1       <= s0_y1;
                s1_curve    <= s0_curve;
                s1_depth    <= s0_depth;
                s1_base     <= s0_base;
            end

            if (valid_1) begin
                s2_smooth_product <= s1_t_squared_q13 * s1_smooth_factor;
                s2_bump_product <= s1_t_squared_q13
                                   * s1_one_minus_t_squared_q13;
                s2_y0    <= s1_y0;
                s2_y1    <= s1_y1;
                s2_curve <= s1_curve;
                s2_depth <= s1_depth;
                s2_base  <= s1_base;
            end

            if (valid_2) begin
                s3_y0 <= s2_y0;
                s3_y1 <= s2_y1;
                s3_smooth_q13 <= s2_smooth_q13;
                s3_curve_adjust_product <= s2_curve
                                           * $signed({1'b0, s2_bump_q13});
                s3_depth <= s2_depth;
                s3_base  <= s2_base;
            end

            if (valid_3) begin
                s4_y0 <= s3_y0;
                s4_interpolation_product <= s3_level_delta
                                            * $signed({1'b0, s3_shaped_t});
                s4_depth <= s3_depth;
                s4_base <= s3_base;
            end

            if (valid_4) begin
                s5_modulation_product <= s4_level_q13
                                         * $signed({1'b0, s4_depth});
                s5_base <= s4_base;
            end

            if (valid_5) begin
                if (s6_cutoff_unclamped < 0)
                    cutoff_q8 <= 15'd0;
                else if (s6_cutoff_unclamped > $signed({1'b0, MAX_CUTOFF_Q8}))
                    cutoff_q8 <= MAX_CUTOFF_Q8;
                else
                    cutoff_q8 <= s6_cutoff_unclamped[14:0];
            end
        end
    end

endmodule
