// ==============================================================================
// Module: knob_spi_rx.v
// Description: SPI Receiver for Teammate 1 Physical Rotary Knobs ADC
//              Receives 16-bit SPI frames from external hardware panel,
//              decodes channel ID & 12-bit ADC value, applies digital hysteresis,
//              and outputs scaled 7-bit synthesis parameters.
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

`include "params.vh"

module knob_spi_rx (
    input  wire        clk,
    input  wire        rst_n,

    // Hardware SPI Pins (from Teammate 1 PMOD / GPIO)
    input  wire        spi_cs_n,
    input  wire        spi_sclk,
    input  wire        spi_mosi,

    // Decoded Parameter Output (to param_merger)
    output reg         param_valid,
    output reg  [7:0]  param_id,
    output reg  [6:0]  param_val
);

    // --------------------------------------------------------------------------
    // 1. Clock Domain Synchronization (2-FF synchronizer on async SPI inputs)
    // --------------------------------------------------------------------------
    reg cs_d1, cs_d2;
    reg sclk_d1, sclk_d2, sclk_d3;
    reg mosi_d1, mosi_d2;

    always @(posedge clk) begin
        cs_d1   <= spi_cs_n;
        cs_d2   <= cs_d1;
        sclk_d1 <= spi_sclk;
        sclk_d2 <= sclk_d1;
        sclk_d3 <= sclk_d2;
        mosi_d1 <= spi_mosi;
        mosi_d2 <= mosi_d1;
    end

    wire sclk_rising = sclk_d2 & ~sclk_d3;
    wire cs_active   = ~cs_d2;
    wire cs_deassert = cs_d2 & ~cs_d1;

    // --------------------------------------------------------------------------
    // 2. 16-bit Shift Register
    // --------------------------------------------------------------------------
    reg [15:0] shift_reg;
    reg [4:0]  bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'd0;
            bit_cnt   <= 5'd0;
        end else if (!cs_active) begin
            bit_cnt   <= 5'd0;
        end else if (sclk_rising) begin
            shift_reg <= {shift_reg[14:0], mosi_d2};
            bit_cnt   <= bit_cnt + 5'd1;
        end
    end

    // --------------------------------------------------------------------------
    // 3. Channel to Param ID Mapping
    // --------------------------------------------------------------------------
    function [7:0] map_ch_to_param_id;
        input [3:0] ch;
        begin
            case (ch)
                4'd0:  map_ch_to_param_id = `PARAM_ID_FLT_CUTOFF;
                4'd1:  map_ch_to_param_id = `PARAM_ID_FLT_RES;
                4'd2:  map_ch_to_param_id = `PARAM_ID_OSCA_WT_POS;
                4'd3:  map_ch_to_param_id = `PARAM_ID_OSCA_DETUNE;
                4'd4:  map_ch_to_param_id = `PARAM_ID_OSCA_UNISON;
                4'd5:  map_ch_to_param_id = `PARAM_ID_OSCA_PAN;
                4'd6:  map_ch_to_param_id = `PARAM_ID_OSCA_VOL;
                4'd7:  map_ch_to_param_id = `PARAM_ID_ENV1_ATTACK;
                4'd8:  map_ch_to_param_id = `PARAM_ID_ENV1_DECAY;
                4'd9:  map_ch_to_param_id = `PARAM_ID_ENV1_SUSTAIN;
                4'd10: map_ch_to_param_id = `PARAM_ID_ENV1_RELEASE;
                4'd11: map_ch_to_param_id = `PARAM_ID_MASTER_VOL;
                4'd12: map_ch_to_param_id = `PARAM_ID_MACRO1;
                4'd13: map_ch_to_param_id = `PARAM_ID_MACRO2;
                4'd14: map_ch_to_param_id = `PARAM_ID_MACRO3;
                default: map_ch_to_param_id = `PARAM_ID_MACRO4;
            endcase
        end
    endfunction

    // --------------------------------------------------------------------------
    // 4. Digital Hysteresis Filter (16 Channels)
    // --------------------------------------------------------------------------
    reg [6:0] last_ch_val [0:15];
    reg [3:0] ch_id;
    reg [6:0] new_val;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            param_valid <= 1'b0;
            param_id    <= `PARAM_ID_NONE;
            param_val   <= 7'd0;
            ch_id       <= 4'd0;
            new_val     <= 7'd0;
            for (i = 0; i < 16; i = i + 1) begin
                last_ch_val[i] <= 7'd64;
            end
        end else begin
            param_valid <= 1'b0;

            // When CS goes high (end of transaction)
            if (cs_deassert && (bit_cnt >= 5'd16)) begin
                ch_id   = shift_reg[15:12];
                new_val = shift_reg[11:5]; // Scaled 12-bit to 7-bit

                // Hysteresis deadband: must change by at least 2 units to prevent jitter
                // Safe absolute difference check avoiding 7-bit overflow wrap at values 126/127
                if (((new_val >= last_ch_val[ch_id]) ? (new_val - last_ch_val[ch_id]) : (last_ch_val[ch_id] - new_val)) >= 7'd2) begin
                    last_ch_val[ch_id] <= new_val;
                    param_valid        <= 1'b1;
                    param_id           <= map_ch_to_param_id(ch_id);
                    param_val          <= new_val;
                end
            end
        end
    end

endmodule
