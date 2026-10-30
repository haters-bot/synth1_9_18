// 两个振荡器的96 kHz立体声声像混合器。
//
// Pan采用中心不衰减的线性平衡律：
//   0   = 硬左，左增益1.0、右增益0；
//   64  = 中央，左右增益均为1.0；
//   127 = 硬右，左增益0、右增益1.0。
//
// 四次乘法由一个共享乘法器分时完成，避免为低速控制功能复制DSP和长组合路径。
// 输出使用Mid/Side表示，Mid送入现有单声道全局处理链，Side在输出端重构声像。
module stereo_pan_mixer (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] sample_a,
    input  wire signed [15:0] sample_b,
    input  wire [6:0]         pan_a,
    input  wire [6:0]         pan_b,
    output wire               in_ready,

    output wire               out_valid,
    output reg  signed [15:0] mid_sample,
    output reg  signed [15:0] side_sample,
    input  wire               out_ready,
    output reg                input_overrun
);

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_A_L   = 3'd1;
    localparam [2:0] STATE_A_R   = 3'd2;
    localparam [2:0] STATE_B_L   = 3'd3;
    localparam [2:0] STATE_B_R   = 3'd4;
    localparam [2:0] STATE_MIX   = 3'd5;
    localparam [2:0] STATE_HOLD  = 3'd6;

    reg [2:0] state;
    reg signed [15:0] sample_a_latched;
    reg signed [15:0] sample_b_latched;
    reg [6:0] pan_a_latched;
    reg [6:0] pan_b_latched;
    reg signed [25:0] product_a_left;
    reg signed [25:0] product_a_right;
    reg signed [25:0] product_b_left;
    reg signed [25:0] product_b_right;

    function [8:0] left_gain_q7;
        input [6:0] pan;
        begin
            if (pan <= 7'd64)
                left_gain_q7 = 9'd128;
            else if (pan == 7'd127)
                left_gain_q7 = 9'd0;
            else
                left_gain_q7 = 9'd128
                             - {1'b0, (pan - 7'd64), 1'b0};
        end
    endfunction

    function [8:0] right_gain_q7;
        input [6:0] pan;
        begin
            if (pan < 7'd64)
                right_gain_q7 = {1'b0, pan, 1'b0};
            else
                right_gain_q7 = 9'd128;
        end
    endfunction

    function signed [15:0] saturate_s27_to_s16;
        input signed [26:0] value;
        begin
            if (value > 27'sd32767)
                saturate_s27_to_s16 = 16'sh7FFF;
            else if (value < -27'sd32768)
                saturate_s27_to_s16 = 16'sh8000;
            else
                saturate_s27_to_s16 = value[15:0];
        end
    endfunction

    wire signed [15:0] multiply_sample =
        ((state == STATE_A_L) || (state == STATE_A_R))
        ? sample_a_latched : sample_b_latched;
    wire [8:0] multiply_gain =
        (state == STATE_A_L) ? left_gain_q7(pan_a_latched) :
        (state == STATE_A_R) ? right_gain_q7(pan_a_latched) :
        (state == STATE_B_L) ? left_gain_q7(pan_b_latched) :
                               right_gain_q7(pan_b_latched);
    wire signed [25:0] multiply_product =
        $signed(multiply_sample) * $signed({1'b0, multiply_gain});

    wire signed [26:0] left_sum_q7 =
        $signed(product_a_left) + $signed(product_b_left);
    wire signed [26:0] right_sum_q7 =
        $signed(product_a_right) + $signed(product_b_right);
    wire signed [26:0] left_scaled = left_sum_q7 >>> 7;
    wire signed [26:0] right_scaled = right_sum_q7 >>> 7;
    wire signed [15:0] left_sample = saturate_s27_to_s16(left_scaled);
    wire signed [15:0] right_sample = saturate_s27_to_s16(right_scaled);
    wire signed [16:0] mid_wide =
        ($signed({left_sample[15], left_sample})
       + $signed({right_sample[15], right_sample})) >>> 1;
    wire signed [16:0] side_wide =
        ($signed({left_sample[15], left_sample})
       - $signed({right_sample[15], right_sample})) >>> 1;

    assign in_ready = (state == STATE_IDLE);
    assign out_valid = (state == STATE_HOLD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= STATE_IDLE;
            sample_a_latched    <= 16'sd0;
            sample_b_latched    <= 16'sd0;
            pan_a_latched       <= 7'd64;
            pan_b_latched       <= 7'd64;
            product_a_left      <= 26'sd0;
            product_a_right     <= 26'sd0;
            product_b_left      <= 26'sd0;
            product_b_right     <= 26'sd0;
            mid_sample          <= 16'sd0;
            side_sample         <= 16'sd0;
            input_overrun       <= 1'b0;
        end else begin
            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (in_valid) begin
                        sample_a_latched <= sample_a;
                        sample_b_latched <= sample_b;
                        pan_a_latched    <= pan_a;
                        pan_b_latched    <= pan_b;
                        state            <= STATE_A_L;
                    end
                end
                STATE_A_L: begin
                    product_a_left <= multiply_product;
                    state <= STATE_A_R;
                end
                STATE_A_R: begin
                    product_a_right <= multiply_product;
                    state <= STATE_B_L;
                end
                STATE_B_L: begin
                    product_b_left <= multiply_product;
                    state <= STATE_B_R;
                end
                STATE_B_R: begin
                    product_b_right <= multiply_product;
                    state <= STATE_MIX;
                end
                STATE_MIX: begin
                    mid_sample  <= mid_wide[15:0];
                    side_sample <= side_wide[15:0];
                    state       <= STATE_HOLD;
                end
                STATE_HOLD: begin
                    if (out_ready)
                        state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
