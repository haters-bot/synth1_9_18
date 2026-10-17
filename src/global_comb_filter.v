// 96 kHz全局反馈梳状滤波器。
//
// 使用2048点、16位循环延迟线。单口RAM分时读取相邻两个样本并做线性插值，
// Cutoff使用Q7.8控制量，映射为约8～2047点延迟。Resonance映射到
// 0～约0.98的反馈系数，反馈写回前经过固定一阶低通阻尼和饱和。
module global_comb_filter #(
    parameter integer DELAY_DEPTH = 2048,
    parameter integer ADDR_WIDTH  = 11
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,

    input  wire               negative_feedback,
    input  wire [14:0]        cutoff_control_q8,
    input  wire [6:0]         resonance_control,

    output reg                out_valid,
    output reg  signed [15:0] sample_out,
    output reg                input_overrun
);

    localparam [3:0] STATE_IDLE               = 4'd0;
    localparam [3:0] STATE_READ_NEAR          = 4'd1;
    localparam [3:0] STATE_READ_FAR           = 4'd2;
    localparam [3:0] STATE_INTERPOLATE        = 4'd3;
    localparam [3:0] STATE_INTERPOLATE_RESULT = 4'd4;
    localparam [3:0] STATE_DAMP               = 4'd5;
    localparam [3:0] STATE_FEEDBACK           = 4'd6;
    localparam [3:0] STATE_WRITE              = 4'd7;

    reg [3:0] state;

    // 两个属性分别兼容高云综合器和常见仿真/综合工具的RAM推断语法。
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg signed [15:0] delay_memory [0:DELAY_DEPTH-1];

    reg [ADDR_WIDTH-1:0] write_pointer;
    reg [ADDR_WIDTH:0]   filled_samples;
    reg [ADDR_WIDTH-1:0] read_address_near_latched;
    reg [ADDR_WIDTH-1:0] read_address_far_latched;
    reg [ADDR_WIDTH:0]   delay_length_latched;
    reg [7:0]            delay_fraction_latched;
    reg                  history_valid_latched;
    reg                  far_history_valid_latched;
    reg                  negative_feedback_latched;
    reg signed [15:0]    input_latched;
    reg signed [15:0]    memory_read_data;
    reg signed [15:0]    near_sample;
    reg signed [17:0]    interpolated_sample;
    reg signed [25:0]    interpolation_product;
    reg signed [17:0]    damped_state;
    reg signed [17:0]    damped_sample;
    reg signed [15:0]    feedback_coefficient_q15;
    reg signed [33:0]    feedback_product;

    wire [6:0] cutoff_integer;
    wire [7:0] cutoff_fraction;
    wire [6:0] cutoff_next_integer;
    wire [19:0] delay_at_integer_q8;
    wire [19:0] delay_at_next_q8;
    wire [19:0] delay_delta_q8;
    wire [27:0] delay_interpolation_product;
    wire [19:0] delay_length_mapped_q8;
    wire [ADDR_WIDTH:0] delay_length_mapped;
    wire [7:0] delay_fraction_mapped;
    wire [14:0] feedback_magnitude_q15;
    wire signed [16:0] interpolation_difference;
    wire signed [15:0] far_sample_effective;
    wire signed [25:0] near_sample_q8;
    wire signed [25:0] interpolation_accumulator;
    wire signed [17:0] input_extended;
    wire signed [17:0] feedback_term;
    wire signed [17:0] write_value_wide;
    wire signed [17:0] delayed_sample_extended;
    wire signed [17:0] comb_sum_wide;
    wire signed [17:0] wet_value_wide;

    assign in_ready = (state == STATE_IDLE);

    // 7位整数Cutoff映射为Q12.8延迟。低4位选择倍频程内的基值，
    // 高3位只做移位，因此不会在音频路径中推断除法器。
    function [19:0] map_cutoff_to_delay_q8;
        input [6:0] cutoff_value;
        reg [11:0] delay_base;
        begin
            case (cutoff_value[3:0])
                4'd0:  delay_base = 12'd2047;
                4'd1:  delay_base = 12'd1959;
                4'd2:  delay_base = 12'd1874;
                4'd3:  delay_base = 12'd1793;
                4'd4:  delay_base = 12'd1715;
                4'd5:  delay_base = 12'd1641;
                4'd6:  delay_base = 12'd1570;
                4'd7:  delay_base = 12'd1502;
                4'd8:  delay_base = 12'd1437;
                4'd9:  delay_base = 12'd1375;
                4'd10: delay_base = 12'd1315;
                4'd11: delay_base = 12'd1258;
                4'd12: delay_base = 12'd1204;
                4'd13: delay_base = 12'd1152;
                4'd14: delay_base = 12'd1102;
                default: delay_base = 12'd1072;
            endcase
            map_cutoff_to_delay_q8 =
                {delay_base, 8'd0} >> cutoff_value[6:4];
        end
    endfunction

    // Q7.8控制量位于两个MIDI刻度之间时，再在两组指数映射结果之间插值。
    assign cutoff_integer = cutoff_control_q8[14:8];
    assign cutoff_fraction = cutoff_control_q8[7:0];
    assign cutoff_next_integer = (cutoff_integer == 7'd127)
                               ? 7'd127 : cutoff_integer + 7'd1;
    assign delay_at_integer_q8 = map_cutoff_to_delay_q8(cutoff_integer);
    assign delay_at_next_q8 = map_cutoff_to_delay_q8(cutoff_next_integer);
    assign delay_delta_q8 = delay_at_integer_q8 - delay_at_next_q8;
    assign delay_interpolation_product = delay_delta_q8 * cutoff_fraction;
    assign delay_length_mapped_q8 = delay_at_integer_q8
                                  - ((delay_interpolation_product + 28'd128)
                                     >> 8);
    assign delay_length_mapped = delay_length_mapped_q8[19:8];
    assign delay_fraction_mapped = delay_length_mapped_q8[7:0];
    // 两个相邻延迟样本使用Q0.8权重插值。
    assign far_sample_effective = far_history_valid_latched
                                ? memory_read_data : 16'sd0;
    assign interpolation_difference =
        $signed(far_sample_effective) - $signed(near_sample);
    assign near_sample_q8 = {{2{near_sample[15]}}, near_sample, 8'd0};
    assign interpolation_accumulator = near_sample_q8
                                     + interpolation_product;

    // 253/32768约为0.00772，因此CC127对应约0.981的反馈系数。
    assign feedback_magnitude_q15 =
        ({8'd0, resonance_control} << 8)
        - ({8'd0, resonance_control} << 1)
        - {8'd0, resonance_control};
    assign input_extended = {{2{input_latched[15]}}, input_latched};
    assign feedback_term = $signed(feedback_product) >>> 15;
    assign write_value_wide = negative_feedback_latched
                            ? (input_extended - feedback_term)
                            : (input_extended + feedback_term);

    // 前馈使用插值后的原始延迟样本；输入与延迟各占0.5，避免额外削顶。
    // 一阶低通只作用于反馈回路，不削弱基础梳齿的高频深度。
    assign delayed_sample_extended = history_valid_latched
                                   ? interpolated_sample : 18'sd0;
    assign comb_sum_wide = negative_feedback_latched
                         ? (input_extended - delayed_sample_extended)
                         : (input_extended + delayed_sample_extended);
    assign wet_value_wide = history_valid_latched
                          ? ($signed(comb_sum_wide) >>> 1)
                          : input_extended;

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

    // 单口RAM在两个连续状态读取D和D+1，在写状态写回当前样本。
    always @(posedge clk) begin
        if (state == STATE_READ_NEAR)
            memory_read_data <= delay_memory[read_address_near_latched];
        else if (state == STATE_READ_FAR)
            memory_read_data <= delay_memory[read_address_far_latched];
        else if (state == STATE_WRITE)
            delay_memory[write_pointer]
                <= saturate_s18_to_s16(write_value_wide);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                       <= STATE_IDLE;
            write_pointer               <= {ADDR_WIDTH{1'b0}};
            filled_samples              <= {(ADDR_WIDTH+1){1'b0}};
            read_address_near_latched   <= {ADDR_WIDTH{1'b0}};
            read_address_far_latched    <= {ADDR_WIDTH{1'b0}};
            delay_length_latched        <= {{ADDR_WIDTH{1'b0}}, 1'b1};
            delay_fraction_latched      <= 8'd0;
            history_valid_latched       <= 1'b0;
            far_history_valid_latched   <= 1'b0;
            negative_feedback_latched   <= 1'b0;
            input_latched               <= 16'sd0;
            near_sample                 <= 16'sd0;
            interpolated_sample         <= 18'sd0;
            interpolation_product       <= 26'sd0;
            damped_state                <= 18'sd0;
            damped_sample               <= 18'sd0;
            feedback_coefficient_q15    <= 16'sd0;
            feedback_product            <= 34'sd0;
            out_valid                   <= 1'b0;
            sample_out                  <= 16'sd0;
            input_overrun               <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (in_valid) begin
                        input_latched <= sample_in;
                        delay_length_latched <= delay_length_mapped;
                        delay_fraction_latched <= delay_fraction_mapped;
                        read_address_near_latched <= write_pointer
                            - delay_length_mapped[ADDR_WIDTH-1:0];
                        read_address_far_latched <= write_pointer
                            - delay_length_mapped[ADDR_WIDTH-1:0]
                            - ((delay_fraction_mapped != 8'd0)
                               ? {{(ADDR_WIDTH-1){1'b0}}, 1'b1}
                               : {ADDR_WIDTH{1'b0}});
                        history_valid_latched <=
                            (filled_samples >= delay_length_mapped);
                        far_history_valid_latched <=
                            (filled_samples >= (delay_length_mapped
                             + {{ADDR_WIDTH{1'b0}}, 1'b1}));
                        negative_feedback_latched <= negative_feedback;
                        feedback_coefficient_q15 <= $signed({
                            1'b0, feedback_magnitude_q15
                        });
                        state <= STATE_READ_NEAR;
                    end
                end

                STATE_READ_NEAR: begin
                    state <= STATE_READ_FAR;
                end

                STATE_READ_FAR: begin
                    near_sample <= history_valid_latched
                                 ? memory_read_data : 16'sd0;
                    state <= STATE_INTERPOLATE;
                end

                STATE_INTERPOLATE: begin
                    interpolation_product <= interpolation_difference
                                           * $signed({
                                               1'b0,
                                               delay_fraction_latched
                                           });
                    state <= STATE_INTERPOLATE_RESULT;
                end

                STATE_INTERPOLATE_RESULT: begin
                    if (history_valid_latched)
                        interpolated_sample <=
                            $signed(interpolation_accumulator) >>> 8;
                    else
                        interpolated_sample <= 18'sd0;
                    state <= STATE_DAMP;
                end

                STATE_DAMP: begin
                    // 固定1/4更新量的一阶低通，削弱反馈回路中的尖锐高频。
                    if (history_valid_latched) begin
                        damped_sample <= damped_state
                            + ((interpolated_sample - damped_state) >>> 2);
                        damped_state <= damped_state
                            + ((interpolated_sample - damped_state) >>> 2);
                    end else begin
                        damped_sample <= damped_state - (damped_state >>> 2);
                        damped_state <= damped_state - (damped_state >>> 2);
                    end
                    state <= STATE_FEEDBACK;
                end

                STATE_FEEDBACK: begin
                    feedback_product <= damped_sample
                                      * feedback_coefficient_q15;
                    state <= STATE_WRITE;
                end

                STATE_WRITE: begin
                    sample_out <= saturate_s18_to_s16(wet_value_wide);
                    write_pointer <= write_pointer
                                   + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                    if (filled_samples < DELAY_DEPTH)
                        filled_samples <= filled_samples
                                        + {{ADDR_WIDTH{1'b0}}, 1'b1};
                    out_valid <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
