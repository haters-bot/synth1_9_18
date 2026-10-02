// PT8211 16-bit stereo transmitter.
//
// Clocking for this project:
//   sys_clk        : 50 MHz
//   HP_WS          : 96 kHz
//   HP_BCK         : 3.072 MHz (96 kHz * 2 channels * 16 bits)
//   oversample_tick: 768 kHz, exactly 8 pulses per audio frame
//
// PT8211 uses the Japanese/LSBJ format. With exactly 16 BCK periods per
// channel, the 16-bit word fills the complete channel slot: MSB first and
// LSB immediately before the WS transition. WS low selects the right
// channel and WS high selects the left channel.
module pt8211_tx(
    input  wire               sys_clk,
    input  wire               rst_n,
    input  wire signed [15:0] sample_data,
    output wire               bck,
    output reg                ws,
    output reg                din,
    output reg                sample_tick,
    output reg                oversample_tick
);

    // round(3.072 MHz * 2^32 / 50 MHz)
    localparam [31:0] BCK_PHASE_INC = 32'h0FBA8827;

    reg [31:0] bck_phase;
    reg [4:0]  bit_count;
    reg signed [15:0] left_sample;
    reg signed [15:0] right_sample;

    wire [31:0] bck_phase_next;
    wire        bck_fall;

    assign bck_phase_next = bck_phase + BCK_PHASE_INC;
    assign bck            = bck_phase[31];
    assign bck_fall       = bck_phase[31] & (~bck_phase_next[31]);

    // DIN and WS change on falling BCK edges. PT8211 samples DIN on rising
    // BCK edges, leaving approximately half a BCK period of setup time.
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            bck_phase       <= 32'd0;
            bit_count       <= 5'd0;
            left_sample     <= 16'sd0;
            right_sample    <= 16'sd0;
            ws              <= 1'b0;
            din             <= 1'b0;
            sample_tick     <= 1'b0;
            oversample_tick <= 1'b0;
        end else begin
            bck_phase       <= bck_phase_next;
            sample_tick     <= 1'b0;
            oversample_tick <= 1'b0;

            if (bck_fall) begin
                // 32 BCK periods per 96 kHz frame and four BCK periods per
                // 768 kHz internal sample produce exactly eight FIR input
                // opportunities per output frame.
                if (bit_count[1:0] == 2'b00)
                    oversample_tick <= 1'b1;

                if (bit_count == 5'd0) begin
                    // Start right channel and capture one mono sample for
                    // both channels. Use sample_data directly for the first
                    // bit because the sample registers update on this edge.
                    ws           <= 1'b0;
                    din          <= sample_data[15];
                    left_sample  <= sample_data;
                    right_sample <= sample_data;
                    sample_tick  <= 1'b1;
                    bit_count    <= 5'd1;
                end else if (bit_count < 5'd16) begin
                    din       <= right_sample[15 - bit_count];
                    bit_count <= bit_count + 5'd1;
                end else if (bit_count == 5'd16) begin
                    ws        <= 1'b1;
                    din       <= left_sample[15];
                    bit_count <= 5'd17;
                end else begin
                    din       <= left_sample[31 - bit_count];
                    bit_count <= bit_count + 5'd1;
                end
            end
        end
    end

endmodule
