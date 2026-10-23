// 96 kHz前馈峰值压缩器。内部同时提供最终饱和限制，避免定点回绕。
module global_compressor (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire               enable,
    input  wire [6:0]         threshold_control,
    input  wire [6:0]         ratio_control,
    input  wire [6:0]         attack_control,
    input  wire [6:0]         release_control,
    input  wire [6:0]         makeup_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    reg [15:0] envelope;
    reg [15:0] gain_q15;

    wire [15:0] input_magnitude = sample_in[15]
                                ? (~sample_in + 16'd1) : sample_in;
    wire [2:0] attack_shift = 3'd2 + attack_control[6:5];
    wire [3:0] release_shift = 4'd6 + release_control[6:5];
    wire signed [16:0] envelope_difference =
        $signed({1'b0, input_magnitude}) - $signed({1'b0, envelope});
    wire signed [17:0] envelope_attack_wide =
        $signed({1'b0, envelope})
        + ($signed(envelope_difference) >>> attack_shift);
    wire signed [17:0] envelope_release_wide =
        $signed({1'b0, envelope})
        + ($signed(envelope_difference) >>> release_shift);
    wire [15:0] envelope_next = (input_magnitude > envelope)
                              ? envelope_attack_wide[15:0]
                              : envelope_release_wide[15:0];
    wire [15:0] threshold_level = 16'd1024
                                + threshold_control * 8'd240;
    wire [15:0] level_excess = (envelope_next > threshold_level)
                             ? envelope_next - threshold_level : 16'd0;
    wire [22:0] reduction_product = level_excess * ratio_control;
    wire [15:0] requested_reduction = reduction_product[22:7];
    wire [15:0] target_gain_q15 = (requested_reduction >= 16'd30720)
                                ? 16'd2048
                                : 16'd32768 - requested_reduction;
    wire signed [16:0] gain_difference =
        $signed({1'b0, target_gain_q15}) - $signed({1'b0, gain_q15});
    wire signed [17:0] gain_attack_wide =
        $signed({1'b0, gain_q15})
        + ($signed(gain_difference) >>> attack_shift);
    wire signed [17:0] gain_release_wide =
        $signed({1'b0, gain_q15})
        + ($signed(gain_difference) >>> release_shift);
    wire [15:0] gain_next_q15 = (target_gain_q15 < gain_q15)
                              ? gain_attack_wide[15:0]
                              : gain_release_wide[15:0];
    wire signed [31:0] compressed_product =
        sample_in * $signed({1'b0, gain_next_q15});
    wire signed [17:0] compressed_sample_wide = compressed_product >>> 15;
    wire [8:0] makeup_gain_q8 = 9'd256 + {2'd0, makeup_control};
    wire signed [26:0] makeup_product =
        compressed_sample_wide * $signed({1'b0, makeup_gain_q8});
    wire signed [18:0] wet_sample_wide = makeup_product >>> 8;
    wire signed [15:0] wet_sample = saturate_s19_to_s16(wet_sample_wide);
    wire signed [16:0] wet_dry_difference =
        $signed({wet_sample[15], wet_sample})
        - $signed({sample_in[15], sample_in});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_control});
    wire signed [25:0] mixed_wide =
        $signed({{10{sample_in[15]}}, sample_in})
        + ($signed(mix_product) >>> 7);

    assign in_ready = 1'b1;

    function signed [15:0] saturate_s19_to_s16;
        input signed [18:0] value;
        begin
            if (value > 19'sd32767) saturate_s19_to_s16 = 16'sh7FFF;
            else if (value < -19'sd32768) saturate_s19_to_s16 = 16'sh8000;
            else saturate_s19_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s26_to_s16;
        input signed [25:0] value;
        begin
            if (value > 26'sd32767) saturate_s26_to_s16 = 16'sh7FFF;
            else if (value < -26'sd32768) saturate_s26_to_s16 = 16'sh8000;
            else saturate_s26_to_s16 = value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            envelope <= 16'd0;
            gain_q15 <= 16'd32768;
            out_valid <= 1'b0;
            sample_out <= 16'sd0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                envelope <= envelope_next;
                gain_q15 <= gain_next_q15;
                if (!enable || mix_control == 7'd0)
                    sample_out <= sample_in;
                else if (mix_control == 7'd127)
                    sample_out <= wet_sample;
                else
                    sample_out <= saturate_s26_to_s16(mixed_wide);
                out_valid <= 1'b1;
            end
        end
    end

endmodule
