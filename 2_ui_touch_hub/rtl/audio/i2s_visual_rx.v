// I2S monitor for the audio-board visualization return link.
//
// The audio board drives a standard 16-bit I2S stream:
//   VIS_BCLK  = bit clock
//   VIS_LRC   = left/right clock (low = left)
//   VIS_DIN   = MSB-first serial data
//
// The UI pixel clock is used as the processing clock.  The three external
// signals are synchronised before edge detection; at 3.072 MHz BCLK and a
// 50 MHz pixel clock there are enough samples per bit for this monitor.
// Left words retain the original sample_valid timing. stereo_valid marks a
// completed right word paired with the preceding complete left word.
module i2s_visual_rx #(
    parameter integer LINK_TIMEOUT_CYCLES = 12_500_000
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              i2s_bclk,
    input  wire              i2s_lrc,
    input  wire              i2s_din,
    output reg signed [15:0] sample,
    output reg              sample_valid,
    output reg              link_up,
    output reg signed [15:0] sample_right,
    output reg              stereo_valid
);
    reg bclk_meta, bclk_sync, bclk_prev;
    reg lrc_meta, lrc_sync;
    reg din_meta, din_sync;
    reg lrc_initialized;
    reg lrc_seen;
    reg channel_aligned;
    reg left_pending;
    reg [5:0] bit_count;
    reg [15:0] shift_reg;
    reg [31:0] link_age;

    wire bclk_rise = bclk_sync && !bclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_meta   <= 1'b0;
            bclk_sync   <= 1'b0;
            bclk_prev   <= 1'b0;
            lrc_meta    <= 1'b0;
            lrc_sync    <= 1'b0;
            din_meta    <= 1'b0;
            din_sync    <= 1'b0;
            lrc_initialized <= 1'b0;
            lrc_seen    <= 1'b0;
            channel_aligned <= 1'b0;
            bit_count   <= 6'd0;
            shift_reg   <= 16'd0;
            sample      <= 16'sd0;
            sample_right<= 16'sd0;stereo_valid<=0;left_pending<=0;
            sample_valid<= 1'b0;
            link_up     <= 1'b0;
            link_age    <= 32'd0;
        end else begin
            bclk_meta <= i2s_bclk;
            bclk_sync <= bclk_meta;
            bclk_prev <= bclk_sync;
            lrc_meta  <= i2s_lrc;
            lrc_sync  <= lrc_meta;
            din_meta  <= i2s_din;
            din_sync  <= din_meta;
            sample_valid <= 1'b0;
            stereo_valid <= 1'b0;

            if (link_age < LINK_TIMEOUT_CYCLES)
                link_age <= link_age + 32'd1;
            else begin
                link_up <= 1'b0;
                lrc_initialized <= 1'b0;
                channel_aligned <= 1'b0;left_pending<=0;
            end

            if (bclk_rise) begin
                link_age <= 32'd0;
                link_up  <= 1'b1;

                // The WS transition slot is one bit before the new MSB.
                // In the audio engine's 16-bit slots it still carries the
                // OLD channel LSB, which must complete that channel first.
                // Wait for an actual WS edge after reset or link timeout
                // so a partial channel is never exported as a full sample.
                if (!lrc_initialized) begin
                    lrc_initialized <= 1'b1;
                    lrc_seen <= lrc_sync;
                    bit_count <= 6'd0;
                    channel_aligned <= 1'b0;
                end else if (lrc_sync != lrc_seen) begin
                    if (channel_aligned && bit_count == 6'd15) begin
                        if(!lrc_seen)begin
                            sample <= {shift_reg[14:0], din_sync};
                            sample_valid <= 1'b1;left_pending<=1;
                        end else begin
                            sample_right<={shift_reg[14:0],din_sync};
                            stereo_valid<=left_pending;left_pending<=0;
                        end
                    end
                    // Starting a new left slot also discards an unmatched
                    // old left word if the intervening right slot was short.
                    if(!lrc_sync)left_pending<=0;
                    lrc_seen  <= lrc_sync;
                    bit_count <= 6'd0;
                    shift_reg <= 16'd0;
                    channel_aligned <= 1'b1;
                end else if (channel_aligned && bit_count < 6'd16) begin
                    shift_reg <= {shift_reg[14:0], din_sync};
                    bit_count <= bit_count + 6'd1;
                    if (bit_count == 6'd15) begin
                        if(!lrc_seen)begin
                            sample <= {shift_reg[14:0], din_sync};
                            sample_valid <= 1'b1;left_pending<=1;
                        end else begin
                            sample_right<={shift_reg[14:0],din_sync};
                            stereo_valid<=left_pending;left_pending<=0;
                        end
                    end
                end
            end
        end
    end
endmodule
