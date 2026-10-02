// Local wrapper for the generated Gowin Advanced FIR Filter IP.
//
// IP configuration:
//   input sample rate : 768 kHz
//   output sample rate: 96 kHz
//   decimation factor : 8
//   input width       : signed 16-bit PCM
//   coefficient width : signed Q1.17
//   IP output width   : signed 33-bit
module fir_decimator_8x_wrapper(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,

    output reg                out_valid,
    output reg  signed [15:0] sample_out,
    output reg                input_overrun
);

    localparam integer COEFF_FRAC = 17;

    wire               ip_ready;
    wire               ip_in_valid;
    wire               ip_in_sync;
    wire               ip_out_valid;
    wire               ip_out_sync;
    wire signed [32:0] ip_sample_out;

    // A sample is presented to the IP only when it is ready.  The sticky
    // input_overrun flag records any missed 768 kHz input opportunity.
    assign in_ready    = ip_ready;
    assign ip_in_valid = in_valid & ip_ready;
    assign ip_in_sync  = ip_in_valid; // every sample is channel 0

    fir_decimator_8x_ip u_fir_decimator_8x_ip (
        .clk        (clk),
        .rstn       (rst_n),
        .fir_rfi_o  (ip_ready),
        .fir_valid_i(ip_in_valid),
        .fir_sync_i (ip_in_sync),
        .fir_data_i (sample_in),
        .fir_valid_o(ip_out_valid),
        .fir_sync_o (ip_out_sync),
        .fir_data_o (ip_sample_out)
    );

    // Extend before adding the rounding offset so the 33-bit IP result
    // cannot overflow during rounding.  The arithmetic shift converts the
    // Q1.17 coefficient scaling back to signed 16-bit PCM scaling.
    wire signed [33:0] rounded_value;
    wire signed [33:0] scaled_value;

    assign rounded_value = $signed({ip_sample_out[32], ip_sample_out})
                         + 34'sd65536;
    assign scaled_value  = rounded_value >>> COEFF_FRAC;

    function signed [15:0] saturate_to_s16;
        input signed [33:0] value;
        begin
            if (value > 34'sd32767)
                saturate_to_s16 = 16'sh7FFF;
            else if (value < -34'sd32768)
                saturate_to_s16 = 16'sh8000;
            else
                saturate_to_s16 = value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out    <= 16'sd0;
            out_valid     <= 1'b0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= ip_out_valid;

            if (in_valid && !ip_ready)
                input_overrun <= 1'b1;

            if (ip_out_valid)
                sample_out <= saturate_to_s16(scaled_value);
        end
    end

endmodule
