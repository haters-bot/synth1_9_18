// 96 kHz全局状态变量滤波器。
//
// 每个外部采样执行两次内部积分迭代，相当于在192 kHz下更新状态，可提高
// Chamberlin结构在高截止频率和低阻尼时的稳定性。一个有符号乘法器按时序
// 复用完成积分与阻尼运算，不占用振荡器TDM时间。
module global_svf_filter(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,

    input  wire [1:0]         filter_mode,
    input  wire [6:0]         cutoff_control,
    input  wire [6:0]         resonance_control,

    output reg                out_valid,
    output reg  signed [15:0] sample_out,
    output reg                input_overrun
);

    localparam [1:0] FILTER_BYPASS   = 2'd0;
    localparam [1:0] FILTER_LOWPASS  = 2'd1;
    localparam [1:0] FILTER_HIGHPASS = 2'd2;
    localparam [1:0] FILTER_BANDPASS = 2'd3;

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_LOW_MUL     = 4'd1;
    localparam [3:0] STATE_LOW_UPDATE  = 4'd2;
    localparam [3:0] STATE_DAMP_MUL    = 4'd3;
    localparam [3:0] STATE_HIGH_UPDATE = 4'd4;
    localparam [3:0] STATE_BAND_MUL    = 4'd5;
    localparam [3:0] STATE_BAND_UPDATE = 4'd6;
    localparam [3:0] STATE_COMMIT      = 4'd7;

    reg [3:0] state;
    reg       substep;

    // 音频状态使用带16位小数的40位有符号定点数，保留约8位共振余量。
    reg signed [39:0] input_sample_q16;
    reg signed [39:0] low_state_q16;
    reg signed [39:0] band_state_q16;
    reg signed [39:0] low_work_q16;
    reg signed [39:0] high_work_q16;
    reg signed [39:0] band_work_q16;

    reg [1:0]  mode_latched;
    reg [17:0] cutoff_coefficient_latched;
    reg [17:0] damping_coefficient_latched;

    reg  signed [39:0] multiplier_a;
    reg  signed [18:0] multiplier_b;
    wire signed [58:0] multiplier_result;
    reg  signed [58:0] product_reg;
    wire signed [39:0] product_scaled_q16;

    reg [8:0] cutoff_base_q16;
    wire [17:0] cutoff_coefficient_q16;
    wire [17:0] resonance_extended;
    wire [17:0] resonance_scaled;
    wire [17:0] damping_coefficient_q16;

    assign in_ready = (state == STATE_IDLE);

    // Cutoff按16级/倍频程映射，控制范围约70 Hz～17.3 kHz。
    // 系数f=2*sin(pi*Fc/192kHz)，采用Q2.16格式。
    always @(*) begin
        case (cutoff_control[3:0])
            4'd0:  cutoff_base_q16 = 9'd150;
            4'd1:  cutoff_base_q16 = 9'd157;
            4'd2:  cutoff_base_q16 = 9'd164;
            4'd3:  cutoff_base_q16 = 9'd171;
            4'd4:  cutoff_base_q16 = 9'd179;
            4'd5:  cutoff_base_q16 = 9'd186;
            4'd6:  cutoff_base_q16 = 9'd195;
            4'd7:  cutoff_base_q16 = 9'd203;
            4'd8:  cutoff_base_q16 = 9'd212;
            4'd9:  cutoff_base_q16 = 9'd222;
            4'd10: cutoff_base_q16 = 9'd232;
            4'd11: cutoff_base_q16 = 9'd242;
            4'd12: cutoff_base_q16 = 9'd252;
            4'd13: cutoff_base_q16 = 9'd264;
            4'd14: cutoff_base_q16 = 9'd275;
            default: cutoff_base_q16 = 9'd288;
        endcase
    end

    assign cutoff_coefficient_q16 =
        ({9'd0, cutoff_base_q16} << cutoff_control[6:4]);

    // Resonance=0时阻尼约2.0；Resonance=127时阻尼约0.125。
    // 968=1024-32-16-8，使用移位加减避免为参数映射额外占用乘法器。
    assign resonance_extended = {11'd0, resonance_control};
    assign resonance_scaled = (resonance_extended << 10)
                              - (resonance_extended << 5)
                              - (resonance_extended << 4)
                              - (resonance_extended << 3);
    assign damping_coefficient_q16 =
        (resonance_control == 7'd127)
        ? 18'd8192 : (18'd131072 - resonance_scaled);

    always @(*) begin
        multiplier_a = 40'sd0;
        multiplier_b = 19'sd0;
        case (state)
            STATE_LOW_MUL: begin
                multiplier_a = band_state_q16;
                multiplier_b = $signed({1'b0, cutoff_coefficient_latched});
            end
            STATE_DAMP_MUL: begin
                multiplier_a = band_state_q16;
                multiplier_b = $signed({1'b0, damping_coefficient_latched});
            end
            STATE_BAND_MUL: begin
                multiplier_a = high_work_q16;
                multiplier_b = $signed({1'b0, cutoff_coefficient_latched});
            end
            default: begin
                multiplier_a = 40'sd0;
                multiplier_b = 19'sd0;
            end
        endcase
    end

    assign multiplier_result = multiplier_a * multiplier_b;
    assign product_scaled_q16 = $signed(product_reg) >>> 16;

    function signed [15:0] saturate_q16_to_s16;
        input signed [39:0] value;
        reg signed [39:0] integer_value;
        begin
            integer_value = value >>> 16;
            if (integer_value > 40'sd32767)
                saturate_q16_to_s16 = 16'sh7FFF;
            else if (integer_value < -40'sd32768)
                saturate_q16_to_s16 = 16'sh8000;
            else
                saturate_q16_to_s16 = integer_value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                          <= STATE_IDLE;
            substep                        <= 1'b0;
            input_sample_q16               <= 40'sd0;
            low_state_q16                  <= 40'sd0;
            band_state_q16                 <= 40'sd0;
            low_work_q16                   <= 40'sd0;
            high_work_q16                  <= 40'sd0;
            band_work_q16                  <= 40'sd0;
            mode_latched                   <= FILTER_BYPASS;
            cutoff_coefficient_latched     <= 18'd0;
            damping_coefficient_latched    <= 18'd131072;
            product_reg                    <= 59'sd0;
            out_valid                      <= 1'b0;
            sample_out                     <= 16'sd0;
            input_overrun                  <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (in_valid) begin
                        input_sample_q16 <= {
                            {8{sample_in[15]}}, sample_in, 16'd0
                        };
                        mode_latched <= filter_mode;
                        cutoff_coefficient_latched
                            <= cutoff_coefficient_q16;
                        damping_coefficient_latched
                            <= damping_coefficient_q16;
                        substep <= 1'b0;
                        state <= STATE_LOW_MUL;
                    end
                end

                STATE_LOW_MUL: begin
                    product_reg <= multiplier_result;
                    state <= STATE_LOW_UPDATE;
                end

                STATE_LOW_UPDATE: begin
                    low_work_q16 <= low_state_q16 + product_scaled_q16;
                    state <= STATE_DAMP_MUL;
                end

                STATE_DAMP_MUL: begin
                    product_reg <= multiplier_result;
                    state <= STATE_HIGH_UPDATE;
                end

                STATE_HIGH_UPDATE: begin
                    high_work_q16 <= input_sample_q16
                                   - low_work_q16
                                   - product_scaled_q16;
                    state <= STATE_BAND_MUL;
                end

                STATE_BAND_MUL: begin
                    product_reg <= multiplier_result;
                    state <= STATE_BAND_UPDATE;
                end

                STATE_BAND_UPDATE: begin
                    band_work_q16 <= band_state_q16 + product_scaled_q16;
                    state <= STATE_COMMIT;
                end

                STATE_COMMIT: begin
                    low_state_q16  <= low_work_q16;
                    band_state_q16 <= band_work_q16;

                    if (!substep) begin
                        substep <= 1'b1;
                        state <= STATE_LOW_MUL;
                    end else begin
                        case (mode_latched)
                            FILTER_LOWPASS:
                                sample_out <= saturate_q16_to_s16(low_work_q16);
                            FILTER_HIGHPASS:
                                sample_out <= saturate_q16_to_s16(high_work_q16);
                            FILTER_BANDPASS:
                                sample_out <= saturate_q16_to_s16(band_work_q16);
                            default:
                                sample_out <= saturate_q16_to_s16(input_sample_q16);
                        endcase
                        out_valid <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end

                default:
                    state <= STATE_IDLE;
            endcase
        end
    end

endmodule
