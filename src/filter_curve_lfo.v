// 三控制点、两段曲率的通用 LFO 源。
// 上位机只在配置变化时写影子寄存器，PARAM_COMMIT 使曲线与路由同时生效。
// 输出采用有符号 Q1.13，约为 -1.0～+1.0；本模块不再绑定具体合成参数。
module curve_lfo_core #(
    parameter [6:0] PARAM_ENABLE  = 7'd16,
    parameter [6:0] PARAM_STEP_0  = 7'd17,
    parameter [6:0] PARAM_STEP_1  = 7'd18,
    parameter [6:0] PARAM_POINT_0 = 7'd20,
    parameter [6:0] PARAM_POINT_1 = 7'd21,
    parameter [6:0] PARAM_POINT_2 = 7'd22,
    parameter [6:0] PARAM_CURVE_0 = 7'd23,
    parameter [6:0] PARAM_CURVE_1 = 7'd24,
    parameter [6:0] PARAM_COMMIT  = 7'd25
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_tick,
    input  wire               parameter_valid,
    input  wire [6:0]         parameter_id,
    input  wire [13:0]        parameter_value,
    output reg  signed [14:0] lfo_value_q13,
    output reg                lfo_value_valid,
    output wire               lfo_enabled,
    output reg                active_segment,
    output reg  [23:0]        segment_phase
);

    localparam [13:0] ENABLE_SLEW_STEP = 14'd16;
    localparam [13:0] UNITY_Q13 = 14'd8192;

    reg        shadow_enable;
    reg [13:0] shadow_step_0;
    reg [13:0] shadow_step_1;
    reg [13:0] shadow_point_0;
    reg [13:0] shadow_point_1;
    reg [13:0] shadow_point_2;
    reg [13:0] shadow_curve_0;
    reg [13:0] shadow_curve_1;

    reg        active_enable;
    reg [13:0] active_step_0;
    reg [13:0] active_step_1;
    reg [13:0] active_point_0;
    reg [13:0] active_point_1;
    reg [13:0] active_point_2;
    reg [13:0] active_curve_0;
    reg [13:0] active_curve_1;
    reg [13:0] amplitude_current_q13;

    wire [13:0] selected_phase_step = active_segment
                                          ? active_step_1 : active_step_0;
    wire [24:0] segment_phase_sum = {1'b0, segment_phase}
                                   + {11'd0, selected_phase_step};

    assign lfo_enabled = active_enable;

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

    reg [12:0] s1_t;
    reg [26:0] s1_t_square;
    reg [26:0] s1_one_minus_t_square;
    reg signed [14:0] s1_y0;
    reg signed [14:0] s1_y1;
    reg signed [14:0] s1_curve;

    reg [27:0] s2_smooth_product;
    reg [26:0] s2_bump_product;
    reg signed [14:0] s2_y0;
    reg signed [14:0] s2_y1;
    reg signed [14:0] s2_curve;

    reg signed [14:0] s3_y0;
    reg signed [14:0] s3_y1;
    reg [13:0] s3_smooth_q13;
    reg signed [29:0] s3_curve_adjust_product;

    reg signed [14:0] s4_y0;
    reg signed [30:0] s4_interpolation_product;

    reg signed [29:0] s5_amplitude_product;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_enable  <= 1'b0;
            shadow_step_0  <= 14'd175;
            shadow_step_1  <= 14'd175;
            shadow_point_0 <= 14'd0;
            shadow_point_1 <= 14'd16383;
            shadow_point_2 <= 14'd0;
            shadow_curve_0 <= 14'd8192;
            shadow_curve_1 <= 14'd8192;

            active_enable  <= 1'b0;
            active_step_0  <= 14'd175;
            active_step_1  <= 14'd175;
            active_point_0 <= 14'd0;
            active_point_1 <= 14'd16383;
            active_point_2 <= 14'd0;
            active_curve_0 <= 14'd8192;
            active_curve_1 <= 14'd8192;
            amplitude_current_q13 <= 14'd0;
            active_segment <= 1'b0;
            segment_phase  <= 24'd0;

            valid_0 <= 1'b0;
            valid_1 <= 1'b0;
            valid_2 <= 1'b0;
            valid_3 <= 1'b0;
            valid_4 <= 1'b0;
            valid_5 <= 1'b0;
            lfo_value_q13  <= 15'sd0;
            lfo_value_valid <= 1'b0;
        end else begin
            valid_0 <= sample_tick;
            valid_1 <= valid_0;
            valid_2 <= valid_1;
            valid_3 <= valid_2;
            valid_4 <= valid_3;
            valid_5 <= valid_4;
            lfo_value_valid <= valid_5;

            if (parameter_valid) begin
                case (parameter_id)
                    PARAM_ENABLE:  shadow_enable  <= parameter_value != 14'd0;
                    PARAM_STEP_0:  shadow_step_0  <= parameter_value;
                    PARAM_STEP_1:  shadow_step_1  <= parameter_value;
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
                end else if (amplitude_current_q13 == 14'd0) begin
                    active_segment <= 1'b0;
                    segment_phase  <= 24'd0;
                end

                if (active_enable) begin
                    if (amplitude_current_q13 < UNITY_Q13 - ENABLE_SLEW_STEP)
                        amplitude_current_q13 <= amplitude_current_q13
                                               + ENABLE_SLEW_STEP;
                    else
                        amplitude_current_q13 <= UNITY_Q13;
                end else begin
                    if (amplitude_current_q13 > ENABLE_SLEW_STEP)
                        amplitude_current_q13 <= amplitude_current_q13
                                               - ENABLE_SLEW_STEP;
                    else
                        amplitude_current_q13 <= 14'd0;
                end

                s0_t <= segment_phase[23:11];
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
            end

            if (valid_1) begin
                s2_smooth_product <= s1_t_squared_q13 * s1_smooth_factor;
                s2_bump_product <= s1_t_squared_q13
                                   * s1_one_minus_t_squared_q13;
                s2_y0    <= s1_y0;
                s2_y1    <= s1_y1;
                s2_curve <= s1_curve;
            end

            if (valid_2) begin
                s3_y0 <= s2_y0;
                s3_y1 <= s2_y1;
                s3_smooth_q13 <= s2_smooth_q13;
                s3_curve_adjust_product <= s2_curve
                                           * $signed({1'b0, s2_bump_q13});
            end

            if (valid_3) begin
                s4_y0 <= s3_y0;
                s4_interpolation_product <= s3_level_delta
                                            * $signed({1'b0, s3_shaped_t});
            end

            if (valid_4) begin
                s5_amplitude_product <= s4_level_q13
                                        * $signed({1'b0,
                                                   amplitude_current_q13});
            end

            if (valid_5)
                lfo_value_q13 <= s5_amplitude_product >>> 13;
        end
    end

endmodule


// 三个通用 LFO 共享的 8 槽调制矩阵。
// 每个槽位保存 Enable、Source、Destination 和双极性 Depth，允许多个槽位叠加到同一目标。
// 路由运算在 50 MHz 域时分复用，收到一个 LFO 样本后用 10 拍完成全部目标更新。
module lfo_modulation_router #(
    parameter integer ROUTE_COUNT = 8,
    parameter [6:0] PARAM_COMMIT       = 7'd25,
    parameter [6:0] PARAM_ROUTE_INDEX  = 7'd26,
    parameter [6:0] PARAM_ROUTE_ENABLE = 7'd27,
    parameter [6:0] PARAM_ROUTE_DEST   = 7'd28,
    parameter [6:0] PARAM_ROUTE_DEPTH  = 7'd29,
    parameter [6:0] PARAM_ROUTE_SOURCE = 7'd30
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               lfo_value_valid,
    input  wire signed [14:0] lfo_value_q13,
    input  wire signed [14:0] lfo_1_value_q13,
    input  wire signed [14:0] lfo_2_value_q13,
    input  wire               parameter_valid,
    input  wire [6:0]         parameter_id,
    input  wire [13:0]        parameter_value,
    input  wire [2:0]         filter_mode,

    input  wire [6:0]  base_osc_a_wt,
    input  wire [6:0]  base_osc_a_warp,
    input  wire [6:0]  base_osc_a_level,
    input  wire [6:0]  base_osc_b_wt,
    input  wire [6:0]  base_osc_b_warp,
    input  wire [6:0]  base_osc_b_level,
    input  wire [6:0]  base_pan,
    input  wire [14:0] base_filter_cutoff_q8,
    input  wire [6:0]  base_filter_resonance,
    input  wire [6:0]  base_filter_mix,

    output reg [6:0]  mod_osc_a_wt,
    output reg [6:0]  mod_osc_a_warp,
    output reg [6:0]  mod_osc_a_level,
    output reg [6:0]  mod_osc_b_wt,
    output reg [6:0]  mod_osc_b_warp,
    output reg [6:0]  mod_osc_b_level,
    output reg [6:0]  mod_pan,
    output reg [14:0] mod_filter_cutoff_q8,
    output reg [6:0]  mod_filter_resonance,
    output reg [6:0]  mod_filter_mix,
    input wire [6:0] base_master_level,
    output reg [6:0] mod_master_level,
    input wire [6:0] base_distortion_drive,
    output reg [6:0] mod_distortion_drive,
    input wire [6:0] base_distortion_mix,
    output reg [6:0] mod_distortion_mix,
    input wire [6:0] base_chorus_depth,
    output reg [6:0] mod_chorus_depth,
    input wire [6:0] base_chorus_mix,
    output reg [6:0] mod_chorus_mix,
    input wire [6:0] base_phaser_depth,
    output reg [6:0] mod_phaser_depth,
    input wire [6:0] base_phaser_mix,
    output reg [6:0] mod_phaser_mix,
    input wire [6:0] base_reverb_mix,
    output reg [6:0] mod_reverb_mix,
    input wire [6:0] base_delay_mix,
    output reg [6:0] mod_delay_mix,
    input wire [6:0] base_osc_a_detune, base_osc_b_detune,
    output reg [6:0] mod_osc_a_detune, mod_osc_b_detune,
    output reg        route_overrun
);

    localparam [5:0] DEST_NONE             = 6'd0;
    localparam [5:0] DEST_OSC_A_WT         = 6'd1;
    localparam [5:0] DEST_OSC_A_WARP       = 6'd2;
    localparam [5:0] DEST_OSC_A_LEVEL      = 6'd3;
    localparam [5:0] DEST_OSC_B_WT         = 6'd4;
    localparam [5:0] DEST_OSC_B_WARP       = 6'd5;
    localparam [5:0] DEST_OSC_B_LEVEL      = 6'd6;
    localparam [5:0] DEST_PAN               = 6'd7;
    localparam [5:0] DEST_FILTER_CUTOFF     = 6'd8;
    localparam [5:0] DEST_FILTER_RESONANCE  = 6'd9;
    localparam [5:0] DEST_FILTER_MIX        = 6'd10;

    localparam [5:0] DEST_MASTER_LEVEL = 6'd13;
    localparam [5:0] DEST_DISTORTION_DRIVE = 6'd14;
    localparam [5:0] DEST_DISTORTION_MIX = 6'd15;
    localparam [5:0] DEST_CHORUS_DEPTH = 6'd16;
    localparam [5:0] DEST_CHORUS_MIX = 6'd17;
    localparam [5:0] DEST_PHASER_DEPTH = 6'd18;
    localparam [5:0] DEST_PHASER_MIX = 6'd19;
    localparam [5:0] DEST_REVERB_MIX = 6'd20;
    localparam [5:0] DEST_DELAY_MIX = 6'd21;

    localparam [5:0] DEST_OSC_A_DETUNE = 6'd11;
    localparam [5:0] DEST_OSC_B_DETUNE = 6'd12;
    localparam [1:0] STATE_IDLE    = 2'd0;
    localparam [1:0] STATE_PROCESS = 2'd1;
    localparam [1:0] STATE_COMMIT  = 2'd2;
    // 第一版协议固定为8条路由，显式位宽可避免综合器把整型常量带入比较。
    localparam [2:0] LAST_ROUTE_INDEX = 3'd7;

    reg [2:0] shadow_route_index;
    reg shadow_enable [0:ROUTE_COUNT-1];
    reg [5:0] shadow_destination [0:ROUTE_COUNT-1];
    reg signed [13:0] shadow_depth_q13 [0:ROUTE_COUNT-1];
    reg [1:0] shadow_source [0:ROUTE_COUNT-1];
    reg active_enable [0:ROUTE_COUNT-1];
    reg [5:0] active_destination [0:ROUTE_COUNT-1];
    reg signed [13:0] active_depth_q13 [0:ROUTE_COUNT-1];
    reg [1:0] active_source [0:ROUTE_COUNT-1];

    reg [1:0] state;
    reg [2:0] route_index;
    reg signed [14:0] lfo_value_latched;
    reg signed [14:0] lfo_1_value_latched;
    reg signed [14:0] lfo_2_value_latched;

    reg signed [17:0] acc_osc_a_wt;
    reg signed [17:0] acc_osc_a_warp;
    reg signed [17:0] acc_osc_a_level;
    reg signed [17:0] acc_osc_b_wt;
    reg signed [17:0] acc_osc_b_warp;
    reg signed [17:0] acc_osc_b_level;
    reg signed [17:0] acc_pan;
    reg signed [23:0] acc_filter_cutoff_q8;
    reg signed [17:0] acc_filter_resonance;
    reg signed [17:0] acc_filter_mix;

    reg signed [17:0] acc_master_level;
    reg signed [17:0] acc_distortion_drive;
    reg signed [17:0] acc_distortion_mix;
    reg signed [17:0] acc_chorus_depth;
    reg signed [17:0] acc_chorus_mix;
    reg signed [17:0] acc_phaser_depth;
    reg signed [17:0] acc_phaser_mix;
    reg signed [17:0] acc_reverb_mix;
    reg signed [17:0] acc_delay_mix;

    reg signed [17:0] acc_osc_a_detune, acc_osc_b_detune;
    integer reset_index;
    integer commit_index;

    reg signed [14:0] selected_lfo_value;
    always @(*) begin
        case (active_source[route_index])
            2'd1: selected_lfo_value = lfo_1_value_latched;
            2'd2: selected_lfo_value = lfo_2_value_latched;
            default: selected_lfo_value = lfo_value_latched;
        endcase
    end
    wire signed [28:0] route_product =
        selected_lfo_value * active_depth_q13[route_index];
    wire signed [17:0] route_delta_u7 = route_product >>> 19;
    wire signed [23:0] route_delta_q8 = route_product >>> 11;
    wire comb_filter_mode = (filter_mode == 3'd5)
                          || (filter_mode == 3'd6);
    // 141/256 约等于 70/127。使用移位加法保留原有 Comb 深度限制。
    wire signed [23:0] comb_route_delta_q8 =
        (route_delta_q8 >>> 1)
        + (route_delta_q8 >>> 5)
        + (route_delta_q8 >>> 6)
        + (route_delta_q8 >>> 8);
    wire signed [23:0] selected_cutoff_delta_q8 = comb_filter_mode
                                                ? comb_route_delta_q8
                                                : route_delta_q8;

    function [6:0] saturate_s18_to_u7;
        input signed [17:0] value;
        begin
            if (value < 0)
                saturate_s18_to_u7 = 7'd0;
            else if (value > 18'sd127)
                saturate_s18_to_u7 = 7'd127;
            else
                saturate_s18_to_u7 = value[6:0];
        end
    endfunction

    function [14:0] saturate_s24_to_cutoff_q8;
        input signed [23:0] value;
        begin
            if (value < 0)
                saturate_s24_to_cutoff_q8 = 15'd0;
            else if (value > 24'sd32512)
                saturate_s24_to_cutoff_q8 = 15'd32512;
            else
                saturate_s24_to_cutoff_q8 = value[14:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_route_index <= 3'd0;
            state <= STATE_IDLE;
            route_index <= 3'd0;
            lfo_value_latched <= 15'sd0;
            lfo_1_value_latched <= 15'sd0;
            lfo_2_value_latched <= 15'sd0;
            route_overrun <= 1'b0;

            mod_osc_a_wt <= 7'd0;
            mod_osc_a_warp <= 7'd0;
            mod_osc_a_level <= 7'd127;
            mod_osc_b_wt <= 7'd0;
            mod_osc_b_warp <= 7'd0;
            mod_osc_b_level <= 7'd127;
            mod_pan <= 7'd64;
            mod_osc_a_detune <= 64; mod_osc_b_detune <= 64;
            acc_osc_a_detune <= 64; acc_osc_b_detune <= 64;
            mod_master_level <= 7'd127;
            acc_master_level <= 18'sd127;
            mod_distortion_drive <= 7'd0;
            acc_distortion_drive <= 18'sd0;
            mod_distortion_mix <= 7'd0;
            acc_distortion_mix <= 18'sd0;
            mod_chorus_depth <= 7'd0;
            acc_chorus_depth <= 18'sd0;
            mod_chorus_mix <= 7'd0;
            acc_chorus_mix <= 18'sd0;
            mod_phaser_depth <= 7'd0;
            acc_phaser_depth <= 18'sd0;
            mod_phaser_mix <= 7'd0;
            acc_phaser_mix <= 18'sd0;
            mod_reverb_mix <= 7'd0;
            acc_reverb_mix <= 18'sd0;
            mod_delay_mix <= 7'd0;
            acc_delay_mix <= 18'sd0;

            mod_filter_cutoff_q8 <= 15'd32512;
            mod_filter_resonance <= 7'd0;
            mod_filter_mix <= 7'd127;

            acc_osc_a_wt <= 18'sd0;
            acc_osc_a_warp <= 18'sd0;
            acc_osc_a_level <= 18'sd127;
            acc_osc_b_wt <= 18'sd0;
            acc_osc_b_warp <= 18'sd0;
            acc_osc_b_level <= 18'sd127;
            acc_pan <= 18'sd64;
            acc_filter_cutoff_q8 <= 24'sd32512;
            acc_filter_resonance <= 18'sd0;
            acc_filter_mix <= 18'sd127;

            for (reset_index = 0;
                 reset_index < ROUTE_COUNT;
                 reset_index = reset_index + 1) begin
                shadow_enable[reset_index] <= 1'b0;
                shadow_destination[reset_index] <= DEST_NONE;
                shadow_depth_q13[reset_index] <= 14'sd0;
                shadow_source[reset_index] <= 2'd0;
                active_enable[reset_index] <= 1'b0;
                active_destination[reset_index] <= DEST_NONE;
                active_depth_q13[reset_index] <= 14'sd0;
                active_source[reset_index] <= 2'd0;
            end
        end else begin
            if (parameter_valid) begin
                case (parameter_id)
                    PARAM_ROUTE_INDEX:
                        shadow_route_index <= parameter_value[2:0];
                    PARAM_ROUTE_ENABLE:
                        shadow_enable[shadow_route_index]
                            <= parameter_value != 14'd0;
                    PARAM_ROUTE_DEST:
                        shadow_destination[shadow_route_index]
                            <= parameter_value <= 14'd21
                               ? parameter_value[5:0] : DEST_NONE;
                    PARAM_ROUTE_DEPTH:
                        // 协议采用 Offset Binary：0=-1，8192=0，16383≈+1。
                        shadow_depth_q13[shadow_route_index]
                            <= $signed(parameter_value ^ 14'h2000);
                    PARAM_ROUTE_SOURCE:
                        shadow_source[shadow_route_index]
                            <= parameter_value[1:0] <= 2'd2
                               ? parameter_value[1:0] : 2'd0;
                    PARAM_COMMIT: begin
                        for (commit_index = 0;
                             commit_index < ROUTE_COUNT;
                             commit_index = commit_index + 1) begin
                            active_enable[commit_index]
                                <= shadow_enable[commit_index];
                            active_destination[commit_index]
                                <= shadow_destination[commit_index];
                            active_depth_q13[commit_index]
                                <= shadow_depth_q13[commit_index];
                            active_source[commit_index]
                                <= shadow_source[commit_index];
                        end
                    end
                    default: begin
                    end
                endcase
            end

            if (lfo_value_valid && state != STATE_IDLE)
                route_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (lfo_value_valid) begin
                        lfo_value_latched <= lfo_value_q13;
                        lfo_1_value_latched <= lfo_1_value_q13;
                        lfo_2_value_latched <= lfo_2_value_q13;
                        route_index <= 3'd0;
                        acc_osc_a_wt <= $signed({1'b0, base_osc_a_wt});
                        acc_osc_a_warp <= $signed({1'b0, base_osc_a_warp});
                        acc_osc_a_level <= $signed({1'b0, base_osc_a_level});
                        acc_osc_b_wt <= $signed({1'b0, base_osc_b_wt});
                        acc_osc_b_warp <= $signed({1'b0, base_osc_b_warp});
                        acc_osc_b_level <= $signed({1'b0, base_osc_b_level});
                        acc_pan <= $signed({1'b0, base_pan});
                        acc_filter_cutoff_q8
                            <= $signed({1'b0, base_filter_cutoff_q8});
                        acc_filter_resonance
                            <= $signed({1'b0, base_filter_resonance});
                        acc_filter_mix <= $signed({1'b0, base_filter_mix});
                        acc_master_level <= $signed({1'b0, base_master_level});
                        acc_distortion_drive <= $signed({1'b0, base_distortion_drive});
                        acc_distortion_mix <= $signed({1'b0, base_distortion_mix});
                        acc_chorus_depth <= $signed({1'b0, base_chorus_depth});
                        acc_chorus_mix <= $signed({1'b0, base_chorus_mix});
                        acc_phaser_depth <= $signed({1'b0, base_phaser_depth});
                        acc_phaser_mix <= $signed({1'b0, base_phaser_mix});
                        acc_reverb_mix <= $signed({1'b0, base_reverb_mix});
                        acc_delay_mix <= $signed({1'b0, base_delay_mix});
                        acc_osc_a_detune <= $signed({1'b0,base_osc_a_detune});
                        acc_osc_b_detune <= $signed({1'b0,base_osc_b_detune});
                        state <= STATE_PROCESS;
                    end
                end

                STATE_PROCESS: begin
                    if (active_enable[route_index]) begin
                        case (active_destination[route_index])
                            DEST_OSC_A_WT:
                                acc_osc_a_wt <= acc_osc_a_wt + route_delta_u7;
                            DEST_OSC_A_WARP:
                                acc_osc_a_warp <= acc_osc_a_warp
                                                + route_delta_u7;
                            DEST_OSC_A_LEVEL:
                                acc_osc_a_level <= acc_osc_a_level
                                                 + route_delta_u7;
                            DEST_OSC_B_WT:
                                acc_osc_b_wt <= acc_osc_b_wt + route_delta_u7;
                            DEST_OSC_B_WARP:
                                acc_osc_b_warp <= acc_osc_b_warp
                                                + route_delta_u7;
                            DEST_OSC_B_LEVEL:
                                acc_osc_b_level <= acc_osc_b_level
                                                 + route_delta_u7;
                            DEST_PAN:
                                acc_pan <= acc_pan + route_delta_u7;
                            DEST_FILTER_CUTOFF:
                                acc_filter_cutoff_q8 <= acc_filter_cutoff_q8
                                                       + selected_cutoff_delta_q8;
                            DEST_FILTER_RESONANCE:
                                acc_filter_resonance <= acc_filter_resonance
                                                        + route_delta_u7;
                            DEST_FILTER_MIX:
                                acc_filter_mix <= acc_filter_mix + route_delta_u7;
                            DEST_OSC_A_DETUNE: acc_osc_a_detune <= acc_osc_a_detune + route_delta_u7;
                            DEST_OSC_B_DETUNE: acc_osc_b_detune <= acc_osc_b_detune + route_delta_u7;
                            DEST_MASTER_LEVEL: acc_master_level <= acc_master_level + route_delta_u7;
                            DEST_DISTORTION_DRIVE: acc_distortion_drive <= acc_distortion_drive + route_delta_u7;
                            DEST_DISTORTION_MIX: acc_distortion_mix <= acc_distortion_mix + route_delta_u7;
                            DEST_CHORUS_DEPTH: acc_chorus_depth <= acc_chorus_depth + route_delta_u7;
                            DEST_CHORUS_MIX: acc_chorus_mix <= acc_chorus_mix + route_delta_u7;
                            DEST_PHASER_DEPTH: acc_phaser_depth <= acc_phaser_depth + route_delta_u7;
                            DEST_PHASER_MIX: acc_phaser_mix <= acc_phaser_mix + route_delta_u7;
                            DEST_REVERB_MIX: acc_reverb_mix <= acc_reverb_mix + route_delta_u7;
                            DEST_DELAY_MIX: acc_delay_mix <= acc_delay_mix + route_delta_u7;
                            default: begin
                            end
                        endcase
                    end

                    if (route_index == LAST_ROUTE_INDEX) begin
                        state <= STATE_COMMIT;
                    end else begin
                        route_index <= route_index + 3'd1;
                    end
                end

                STATE_COMMIT: begin
                    mod_osc_a_wt <= saturate_s18_to_u7(acc_osc_a_wt);
                    mod_osc_a_warp <= saturate_s18_to_u7(acc_osc_a_warp);
                    mod_osc_a_level <= saturate_s18_to_u7(acc_osc_a_level);
                    mod_osc_b_wt <= saturate_s18_to_u7(acc_osc_b_wt);
                    mod_osc_b_warp <= saturate_s18_to_u7(acc_osc_b_warp);
                    mod_osc_b_level <= saturate_s18_to_u7(acc_osc_b_level);
                    mod_pan <= saturate_s18_to_u7(acc_pan);
                    mod_filter_cutoff_q8
                        <= saturate_s24_to_cutoff_q8(acc_filter_cutoff_q8);
                    mod_filter_resonance
                        <= saturate_s18_to_u7(acc_filter_resonance);
                    mod_filter_mix <= saturate_s18_to_u7(acc_filter_mix);
                    mod_master_level <= saturate_s18_to_u7(acc_master_level);
                    mod_distortion_drive <= saturate_s18_to_u7(acc_distortion_drive);
                    mod_distortion_mix <= saturate_s18_to_u7(acc_distortion_mix);
                    mod_chorus_depth <= saturate_s18_to_u7(acc_chorus_depth);
                    mod_chorus_mix <= saturate_s18_to_u7(acc_chorus_mix);
                    mod_phaser_depth <= saturate_s18_to_u7(acc_phaser_depth);
                    mod_phaser_mix <= saturate_s18_to_u7(acc_phaser_mix);
                    mod_reverb_mix <= saturate_s18_to_u7(acc_reverb_mix);
                    mod_delay_mix <= saturate_s18_to_u7(acc_delay_mix);
                    mod_osc_a_detune <= saturate_s18_to_u7(acc_osc_a_detune);
                    mod_osc_b_detune <= saturate_s18_to_u7(acc_osc_b_detune);
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
