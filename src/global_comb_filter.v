// 96 kHz全局反馈梳状滤波器。
//
// 使用2048点、16位循环延迟线。延迟线采用同步读、分时写的单口访问方式，
// 便于综合器映射到片上BSRAM。Cutoff按照每16级约一倍频映射为8～2047点延迟，
// Resonance映射到0～约0.98的反馈系数。反馈写回前经过固定一阶低通阻尼和饱和。
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
    input  wire [6:0]         cutoff_control,
    input  wire [6:0]         resonance_control,

    output reg                out_valid,
    output reg  signed [15:0] sample_out,
    output reg                input_overrun
);

    localparam [2:0] STATE_IDLE     = 3'd0;
    localparam [2:0] STATE_READ     = 3'd1;
    localparam [2:0] STATE_DAMP     = 3'd2;
    localparam [2:0] STATE_FEEDBACK = 3'd3;
    localparam [2:0] STATE_WRITE    = 3'd4;

    reg [2:0] state;

    // 两个属性分别兼容高云综合器和常见仿真/综合工具的RAM推断语法。
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg signed [15:0] delay_memory [0:DELAY_DEPTH-1];

    reg [ADDR_WIDTH-1:0] write_pointer;
    reg [ADDR_WIDTH:0]   filled_samples;
    reg [ADDR_WIDTH-1:0] read_address_latched;
    reg [ADDR_WIDTH:0]   delay_length_latched;
    reg                  history_valid_latched;
    reg                  negative_feedback_latched;
    reg signed [15:0]    input_latched;
    reg signed [15:0]    memory_read_data;
    reg signed [17:0]    damped_state;
    reg signed [17:0]    damped_sample;
    reg signed [15:0]    feedback_coefficient_q15;
    reg signed [33:0]    feedback_product;

    reg [11:0] delay_base;
    wire [ADDR_WIDTH:0] delay_length_mapped;
    wire [14:0] feedback_magnitude_q15;
    wire signed [17:0] input_extended;
    wire signed [17:0] feedback_term;
    wire signed [17:0] write_value_wide;
    wire signed [17:0] delayed_sample_extended;
    wire signed [17:0] comb_sum_wide;
    wire signed [17:0] wet_value_wide;

    assign in_ready = (state == STATE_IDLE);

    // 16级/倍频的延迟映射。表内数值覆盖2047～1072点，再由高3位右移。
    always @(*) begin
        case (cutoff_control[3:0])
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
    end

    assign delay_length_mapped = delay_base >> cutoff_control[6:4];

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
    // 前馈支路直接使用原始延迟样本，使Resonance=0时也能形成完整深度的梳齿。
    // 输入与延迟各占0.5，最大同相增益为1，避免增强梳齿时引入额外削顶。
    // 低通阻尼只保留在反馈回路中，用于控制高Resonance时的尖锐程度。
    assign delayed_sample_extended = history_valid_latched
                                   ? {{2{memory_read_data[15]}},
                                      memory_read_data}
                                   : 18'sd0;
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

    // RAM本体不参与异步复位；读写互斥，形成一个同步单口RAM模板。
    always @(posedge clk) begin
        if (state == STATE_READ)
            memory_read_data <= delay_memory[read_address_latched];
        else if (state == STATE_WRITE)
            delay_memory[write_pointer]
                <= saturate_s18_to_s16(write_value_wide);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                       <= STATE_IDLE;
            write_pointer               <= {ADDR_WIDTH{1'b0}};
            filled_samples              <= {(ADDR_WIDTH+1){1'b0}};
            read_address_latched        <= {ADDR_WIDTH{1'b0}};
            delay_length_latched        <= {{ADDR_WIDTH{1'b0}}, 1'b1};
            history_valid_latched       <= 1'b0;
            negative_feedback_latched   <= 1'b0;
            input_latched               <= 16'sd0;
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
                        read_address_latched <= write_pointer
                            - delay_length_mapped[ADDR_WIDTH-1:0];
                        history_valid_latched <=
                            (filled_samples >= delay_length_mapped);
                        negative_feedback_latched <= negative_feedback;
                        feedback_coefficient_q15 <= $signed({
                            1'b0, feedback_magnitude_q15
                        });
                        state <= STATE_READ;
                    end
                end

                STATE_READ: begin
                    state <= STATE_DAMP;
                end

                STATE_DAMP: begin
                    // 固定1/4更新量的一阶低通，削弱反馈回路中的尖锐高频。
                    if (history_valid_latched) begin
                        damped_sample <= damped_state
                            + (($signed(memory_read_data) - damped_state) >>> 2);
                        damped_state <= damped_state
                            + (($signed(memory_read_data) - damped_state) >>> 2);
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
                    write_pointer <= write_pointer + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
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
