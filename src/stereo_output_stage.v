// 将处理后的Mid与旁路保存的Side重构为左右声道，并应用Master Level和全局Pan。
// 所有四次乘法复用一个乘法器；输出样本在out_valid时更新并保持到下一次结果。
module stereo_output_stage (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] processed_mid,
    input  wire signed [15:0] side_sample,
    input  wire [8:0]         master_gain_q8,
    input  wire [6:0]         global_pan,
    output wire               in_ready,

    output wire               out_valid,
    output reg  signed [15:0] left_sample,
    output reg  signed [15:0] right_sample,
    output wire               clip_pulse,
    output reg                input_overrun
);

    localparam [2:0] STATE_IDLE     = 3'd0;
    localparam [2:0] STATE_MASTER_L = 3'd1;
    localparam [2:0] STATE_MASTER_R = 3'd2;
    localparam [2:0] STATE_PAN_L    = 3'd3;
    localparam [2:0] STATE_PAN_R    = 3'd4;
    localparam [2:0] STATE_DONE     = 3'd5;

    reg [2:0] state;
    reg signed [15:0] raw_left;
    reg signed [15:0] raw_right;
    reg signed [15:0] master_left;
    reg signed [15:0] master_right;
    reg [8:0] master_gain_latched;
    reg [8:0] pan_left_latched;
    reg [8:0] pan_right_latched;
    reg clip_work;

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

    wire signed [17:0] reconstructed_left =
        $signed({{2{processed_mid[15]}}, processed_mid})
      + $signed({{2{side_sample[15]}}, side_sample});
    wire signed [17:0] reconstructed_right =
        $signed({{2{processed_mid[15]}}, processed_mid})
      - $signed({{2{side_sample[15]}}, side_sample});
    wire reconstruct_clip = (reconstructed_left > 18'sd32767)
                         || (reconstructed_left < -18'sd32768)
                         || (reconstructed_right > 18'sd32767)
                         || (reconstructed_right < -18'sd32768);

    wire signed [15:0] multiply_sample =
        (state == STATE_MASTER_L) ? raw_left :
        (state == STATE_MASTER_R) ? raw_right :
        (state == STATE_PAN_L)    ? master_left : master_right;
    wire [8:0] multiply_gain =
        ((state == STATE_MASTER_L) || (state == STATE_MASTER_R))
        ? master_gain_latched
        : ((state == STATE_PAN_L) ? pan_left_latched : pan_right_latched);
    wire signed [25:0] multiply_product =
        $signed(multiply_sample) * $signed({1'b0, multiply_gain});
    wire signed [26:0] multiply_extended =
        {multiply_product[25], multiply_product};
    wire signed [26:0] master_scaled = multiply_extended >>> 8;
    wire signed [26:0] pan_scaled = multiply_extended >>> 7;
    wire master_scale_clip = (master_scaled > 27'sd32767)
                          || (master_scaled < -27'sd32768);
    wire pan_scale_clip = (pan_scaled > 27'sd32767)
                       || (pan_scaled < -27'sd32768);

    assign in_ready = (state == STATE_IDLE);
    assign out_valid = (state == STATE_DONE);
    assign clip_pulse = out_valid && clip_work;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= STATE_IDLE;
            raw_left            <= 16'sd0;
            raw_right           <= 16'sd0;
            master_left         <= 16'sd0;
            master_right        <= 16'sd0;
            master_gain_latched <= 9'd0;
            pan_left_latched    <= 9'd128;
            pan_right_latched   <= 9'd128;
            left_sample         <= 16'sd0;
            right_sample        <= 16'sd0;
            clip_work           <= 1'b0;
            input_overrun       <= 1'b0;
        end else begin
            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (in_valid) begin
                        raw_left            <= saturate_s18_to_s16(reconstructed_left);
                        raw_right           <= saturate_s18_to_s16(reconstructed_right);
                        master_gain_latched <= master_gain_q8;
                        pan_left_latched    <= left_gain_q7(global_pan);
                        pan_right_latched   <= right_gain_q7(global_pan);
                        clip_work           <= reconstruct_clip;
                        state               <= STATE_MASTER_L;
                    end
                end
                STATE_MASTER_L: begin
                    master_left <= saturate_s27_to_s16(master_scaled);
                    clip_work   <= clip_work || master_scale_clip;
                    state       <= STATE_MASTER_R;
                end
                STATE_MASTER_R: begin
                    master_right <= saturate_s27_to_s16(master_scaled);
                    clip_work    <= clip_work || master_scale_clip;
                    state        <= STATE_PAN_L;
                end
                STATE_PAN_L: begin
                    left_sample <= saturate_s27_to_s16(pan_scaled);
                    clip_work   <= clip_work || pan_scale_clip;
                    state       <= STATE_PAN_R;
                end
                STATE_PAN_R: begin
                    right_sample <= saturate_s27_to_s16(pan_scaled);
                    clip_work    <= clip_work || pan_scale_clip;
                    state        <= STATE_DONE;
                end
                STATE_DONE: state <= STATE_IDLE;
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
