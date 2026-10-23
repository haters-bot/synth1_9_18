// 96 kHz单声道失真。包含软削波、硬削波和折返三种波形整形方式。
module global_distortion (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire               enable,
    input  wire [1:0]         distortion_type,
    input  wire [6:0]         drive_control,
    input  wire [6:0]         tone_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    reg signed [15:0] tone_state;

    wire [11:0] drive_gain_q8 = 12'd256 + drive_control * 5'd14;
    wire signed [27:0] drive_product =
        $signed(sample_in) * $signed({1'b0, drive_gain_q8});
    wire signed [27:0] driven_wide = drive_product >>> 8;
    wire signed [15:0] shaped_sample = shape_sample(
        driven_wide, distortion_type
    );
    wire [7:0] tone_coefficient = {1'b0, tone_control} + 8'd1;
    wire signed [16:0] tone_difference =
        $signed({shaped_sample[15], shaped_sample})
        - $signed({tone_state[15], tone_state});
    wire signed [24:0] tone_product =
        tone_difference * $signed({1'b0, tone_coefficient});
    wire signed [17:0] tone_next_wide =
        $signed({{2{tone_state[15]}}, tone_state})
        + ($signed(tone_product) >>> 7);
    wire signed [15:0] tone_next = saturate_s18_to_s16(tone_next_wide);
    wire signed [16:0] wet_dry_difference =
        $signed({tone_next[15], tone_next})
        - $signed({sample_in[15], sample_in});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_control});
    wire signed [25:0] mixed_wide =
        $signed({{10{sample_in[15]}}, sample_in})
        + ($signed(mix_product) >>> 7);

    assign in_ready = 1'b1;

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

    function signed [15:0] shape_sample;
        input signed [27:0] value;
        input [1:0] shape_type;
        reg signed [27:0] shaped;
        begin
            case (shape_type)
                2'd1: begin
                    if (value > 28'sd24576)
                        shaped = 28'sd24576;
                    else if (value < -28'sd24576)
                        shaped = -28'sd24576;
                    else
                        shaped = value;
                end
                2'd2: begin
                    if (value > 28'sd49152)
                        shaped = 28'sd0;
                    else if (value > 28'sd24576)
                        shaped = 28'sd49152 - value;
                    else if (value < -28'sd49152)
                        shaped = 28'sd0;
                    else if (value < -28'sd24576)
                        shaped = -28'sd49152 - value;
                    else
                        shaped = value;
                end
                default: begin
                    if (value > 28'sd24576)
                        shaped = 28'sd20480 + ((value - 28'sd24576) >>> 3);
                    else if (value > 28'sd8192)
                        shaped = 28'sd8192 + ((value - 28'sd8192) >>> 1);
                    else if (value < -28'sd24576)
                        shaped = -28'sd20480 + ((value + 28'sd24576) >>> 3);
                    else if (value < -28'sd8192)
                        shaped = -28'sd8192 + ((value + 28'sd8192) >>> 1);
                    else
                        shaped = value;
                end
            endcase

            if (shaped > 28'sd32767)
                shape_sample = 16'sh7FFF;
            else if (shaped < -28'sd32768)
                shape_sample = 16'sh8000;
            else
                shape_sample = shaped[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_state    <= 16'sd0;
            out_valid     <= 1'b0;
            sample_out    <= 16'sd0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                tone_state <= tone_next;
                if (!enable || mix_control == 7'd0)
                    sample_out <= sample_in;
                else if (mix_control == 7'd127)
                    sample_out <= tone_next;
                else
                    sample_out <= saturate_s26_to_s16(mixed_wide);
                out_valid <= 1'b1;
            end
        end
    end

endmodule
