// MAX98357A标准I2S发送器。
//
// Clocking for this project:
//   sys_clk : 50 MHz
//   LRCK    : 96 kHz
//   BCLK    : 3.072 MHz (96 kHz * 32 bits/frame)
//   oversample_tick: 768 kHz, exactly 8 pulses per LRCK frame
//
// BCLK由分数相位累加器产生，避免50 MHz系统时钟使用误差较大的整数分频。
// MAX98357A不需要MCLK输入。
module i2s_tx(
    input  wire               sys_clk,
    input  wire               rst_n,
    input  wire signed [15:0] sample_data,
    output wire               bclk,
    output reg                lrck,
    output reg                sdata,
    output reg                sample_tick,
    output reg                oversample_tick
);

    // round(3.072 MHz * 2^32 / 50 MHz)
    localparam [31:0] BCLK_PHASE_INC = 32'h0FBA8827;

    reg  [31:0] bclk_phase;
    reg  [4:0]  bit_count;
    reg signed [15:0] left_reg;
    reg signed [15:0] right_reg;

    wire [31:0] bclk_phase_next;
    wire        bclk_fall;

    assign bclk_phase_next = bclk_phase + BCLK_PHASE_INC;
    assign bclk            = bclk_phase[31];

    // Detect transitions of the generated BCLK while remaining in the
    // 50 MHz clock domain.  Data changes on falling BCLK edges and is
    // sampled by the DAC on rising BCLK edges.
    assign bclk_fall = bclk_phase[31] & (~bclk_phase_next[31]);

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_phase <= 32'd0;
            bit_count  <= 5'd0;
            left_reg   <= 16'sd0;
            right_reg  <= 16'sd0;
            lrck       <= 1'b0;   // low = left channel
            sdata      <= 1'b0;
            sample_tick <= 1'b0;
            oversample_tick <= 1'b0;
        end else begin
            bclk_phase <= bclk_phase_next;
            sample_tick <= 1'b0;
            oversample_tick <= 1'b0;

            if (bclk_fall) begin
                // Four BCLK periods per 768 kHz internal sample.  Since
                // an I2S frame contains 32 BCLK periods, this produces
                // exactly eight internal samples per 96 kHz frame.
                if (bit_count[1:0] == 2'b00)
                    oversample_tick <= 1'b1;

                // Standard I2S changes LRCK one BCLK before the next
                // channel MSB.  Therefore the previous channel LSB shares
                // the BCLK slot in which LRCK changes.
                if (bit_count == 5'd0) begin
                    lrck       <= 1'b0;
                    sdata      <= right_reg[0];
                    bit_count  <= 5'd1;
                    left_reg   <= sample_data;
                    right_reg  <= sample_data;
                    sample_tick <= 1'b1;
                end else if (bit_count == 5'd16) begin
                    lrck      <= 1'b1;
                    sdata     <= left_reg[0];
                    bit_count <= 5'd17;
                end else begin
                    bit_count <= bit_count + 5'd1;

                    if (bit_count < 5'd16)
                        sdata <= left_reg[16 - bit_count];
                    else
                        sdata <= right_reg[32 - bit_count];
                end
            end
        end
    end

endmodule
