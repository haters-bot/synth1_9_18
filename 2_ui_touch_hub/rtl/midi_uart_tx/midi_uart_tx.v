// ==============================================================================
// Module: midi_uart_tx.v
// Description: MIDI UART Protocol Transmitter for Audio Engine (Teammate 3)
//              - Baud Rate: 31250 bit/s (Standard MIDI) @ 62.5MHz Pixel Clock
//              - Channel 1 (Priority 1): Note-On (0x90) / Note-Off (0x80)
//              - Channel 16 (Priority 2): Control Change (0xBF)
//                CC10: Pan, CC20: WT Pos, CC21: Waveform, CC22: Detune, CC23: Unison,
//                CC74: Cutoff, CC71: Res, CC73: Attack, CC72: Release
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

`include "params.vh"

module midi_uart_tx #(
    parameter CLK_FREQ = 62500000,
    parameter BAUD     = 31250
)(
    input  wire        clk,
    input  wire        rst_n,

    // Note Event Inputs (Priority 1, from touch_event_router)
    input  wire        note_on_req,
    input  wire        note_off_req,
    input  wire [6:0]  note_number,
    input  wire [6:0]  note_velocity,

    // Parameter CC Event Inputs (Priority 2, from param_merger)
    input  wire        cc_req,
    input  wire [7:0]  cc_param_id,
    input  wire [6:0]  cc_val,

    // Hardware UART Serial Output (to Teammate 3 Audio Engine)
    output reg         uart_tx,
    output wire        tx_busy
);

    localparam CLK_DIV = CLK_FREQ / BAUD; // 62,500,000 / 31250 = 2000

    // --------------------------------------------------------------------------
    // 1. Parameter ID to MIDI CC Number Translation
    // --------------------------------------------------------------------------
    function [6:0] map_id_to_cc;
        input [7:0] id;
        begin
            case (id)
                `PARAM_ID_OSCA_PAN,
                `PARAM_ID_OSCB_PAN:     map_id_to_cc = 7'd10; // CC10 Pan
                `PARAM_ID_OSCA_WT_POS,
                `PARAM_ID_OSCB_WT_POS:  map_id_to_cc = 7'd20; // CC20 WT Position
                `PARAM_ID_OSCA_WARP,
                `PARAM_ID_OSCB_WARP:    map_id_to_cc = 7'd21; // CC21 Waveform
                `PARAM_ID_OSCA_DETUNE,
                `PARAM_ID_OSCB_DETUNE:  map_id_to_cc = 7'd22; // CC22 Detune
                `PARAM_ID_OSCA_UNISON,
                `PARAM_ID_OSCB_UNISON:  map_id_to_cc = 7'd23; // CC23 Unison
                `PARAM_ID_FLT_CUTOFF:   map_id_to_cc = 7'd74; // CC74 Cutoff
                `PARAM_ID_FLT_RES:      map_id_to_cc = 7'd71; // CC71 Resonance
                `PARAM_ID_FLT_DRIVE:    map_id_to_cc = 7'd13; // CC13 Drive
                `PARAM_ID_FLT_MIX:      map_id_to_cc = 7'd95; // CC95 Mix
                `PARAM_ID_FLT_PAN:      map_id_to_cc = 7'd10; // CC10 Pan
                `PARAM_ID_ENV1_ATTACK:  map_id_to_cc = 7'd73; // CC73 Attack
                `PARAM_ID_ENV1_RELEASE: map_id_to_cc = 7'd72; // CC72 Release
                `PARAM_ID_ENV1_DECAY:   map_id_to_cc = 7'd75; // CC75 Decay
                `PARAM_ID_ENV1_SUSTAIN: map_id_to_cc = 7'd76; // CC76 Sustain
                `PARAM_ID_ENV1_HOLD:    map_id_to_cc = 7'd79; // CC79 Hold
                `PARAM_ID_FX_REVERB:    map_id_to_cc = 7'd91; // CC91 Reverb
                `PARAM_ID_FX_DELAY:     map_id_to_cc = 7'd12; // CC12 Delay
                `PARAM_ID_FX_CHORUS:    map_id_to_cc = 7'd93; // CC93 Chorus
                `PARAM_ID_PORTAMENTO:   map_id_to_cc = 7'd5;  // CC5 Portamento
                `PARAM_ID_MASTER_VOL:   map_id_to_cc = 7'd7;  // CC7 Master Volume
                `PARAM_ID_MACRO1:       map_id_to_cc = 7'd1;  // CC1 Macro 1 / Mod Wheel
                `PARAM_ID_MACRO2:       map_id_to_cc = 7'd2;  // CC2 Macro 2
                `PARAM_ID_MACRO3:       map_id_to_cc = 7'd3;  // CC3 Macro 3
                `PARAM_ID_MACRO4:       map_id_to_cc = 7'd4;  // CC4 Macro 4
                `PARAM_ID_OSCA_POWER:   map_id_to_cc = 7'd102;// CC102 OSC A Power
                `PARAM_ID_OSCB_POWER:   map_id_to_cc = 7'd103;// CC103 OSC B Power
                `PARAM_ID_FLT_POWER:    map_id_to_cc = 7'd104;// CC104 Filter Power
                `PARAM_ID_SLOT1_BYPASS: map_id_to_cc = 7'd110;// CC110 Slot 1 Bypass
                `PARAM_ID_SLOT2_BYPASS: map_id_to_cc = 7'd111;// CC111 Slot 2 Bypass
                `PARAM_ID_SLOT3_BYPASS: map_id_to_cc = 7'd112;// CC112 Slot 3 Bypass
                `PARAM_ID_SLOT4_BYPASS: map_id_to_cc = 7'd113;// CC113 Slot 4 Bypass
                default:                map_id_to_cc = 7'd0;
            endcase
        end
    endfunction

    // --------------------------------------------------------------------------
    // 2. Transmit Packet FIFO / Arbiter (8-entry FIFO for 3-byte MIDI Messages)
    // --------------------------------------------------------------------------
    reg [23:0] fifo_mem [0:7];
    reg [2:0]  fifo_wr_ptr;
    reg [2:0]  fifo_rd_ptr;
    reg [3:0]  fifo_count;

    reg [23:0] active_msg;
    reg        uart_start_byte;
    reg [7:0]  uart_byte_data;
    wire       uart_byte_busy;

    // 3-Byte Sequencer FSM
    localparam SEQ_IDLE  = 2'd0;
    localparam SEQ_BYTE1 = 2'd1;
    localparam SEQ_BYTE2 = 2'd2;
    localparam SEQ_BYTE3 = 2'd3;

    reg [1:0] seq_state;

    // Safe Unison clamping (1..8)
    wire [6:0] safe_cc_val = (map_id_to_cc(cc_param_id) == 7'd23) ?
                             ((cc_val == 7'd0) ? 7'd1 : ((cc_val > 7'd8) ? 7'd8 : cc_val)) : cc_val;

    wire        in_push = (note_on_req || note_off_req || (cc_req && fifo_count < 4'd7)) && (fifo_count < 4'd8);
    wire [23:0] in_msg  = note_on_req  ? {8'h90, 1'b0, note_number, 1'b0, note_velocity} :
                          note_off_req ? {8'h80, 1'b0, note_number, 8'h00} :
                                         {8'hBF, 1'b0, map_id_to_cc(cc_param_id), 1'b0, safe_cc_val};

    wire in_pop = (seq_state == SEQ_IDLE) && (fifo_count != 4'd0) && !uart_byte_busy;

    integer f_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr     <= 3'd0;
            fifo_rd_ptr     <= 3'd0;
            fifo_count      <= 4'd0;
            active_msg      <= 24'd0;
            seq_state       <= SEQ_IDLE;
            uart_start_byte <= 1'b0;
            uart_byte_data  <= 8'd0;
            for (f_i = 0; f_i < 8; f_i = f_i + 1) fifo_mem[f_i] <= 24'd0;
        end else begin
            uart_start_byte <= 1'b0;

            // FIFO Push
            if (in_push) begin
                fifo_mem[fifo_wr_ptr] <= in_msg;
                fifo_wr_ptr <= fifo_wr_ptr + 3'd1;
            end

            // FIFO Pop & 3-Byte Sequencer
            case (seq_state)
                SEQ_IDLE: begin
                    if (fifo_count != 4'd0 && !uart_byte_busy) begin
                        active_msg      <= fifo_mem[fifo_rd_ptr];
                        uart_byte_data  <= fifo_mem[fifo_rd_ptr][23:16]; // Status Byte
                        uart_start_byte <= 1'b1;
                        fifo_rd_ptr     <= fifo_rd_ptr + 3'd1;
                        seq_state       <= SEQ_BYTE1;
                    end
                end

                SEQ_BYTE1: begin
                    if (!uart_byte_busy && !uart_start_byte) begin
                        uart_byte_data  <= active_msg[15:8];  // Data Byte 1
                        uart_start_byte <= 1'b1;
                        seq_state       <= SEQ_BYTE2;
                    end
                end

                SEQ_BYTE2: begin
                    if (!uart_byte_busy && !uart_start_byte) begin
                        uart_byte_data  <= active_msg[7:0];   // Data Byte 2
                        uart_start_byte <= 1'b1;
                        seq_state       <= SEQ_BYTE3;
                    end
                end

                SEQ_BYTE3: begin
                    if (!uart_byte_busy && !uart_start_byte) begin
                        seq_state <= SEQ_IDLE;
                    end
                end
            endcase

            // FIFO Count Tracking
            if (in_push && !in_pop)
                fifo_count <= fifo_count + 4'd1;
            else if (!in_push && in_pop)
                fifo_count <= fifo_count - 4'd1;
        end
    end

    // --------------------------------------------------------------------------
    // 3. Low-Level 8N1 Byte Transmitter
    // --------------------------------------------------------------------------
    reg [15:0] baud_timer;
    reg [3:0]  bit_count;
    reg [8:0]  shift_reg; // 8 data, 1 stop
    reg        byte_active;

    assign uart_byte_busy = byte_active;
    assign tx_busy = byte_active || (fifo_count != 4'd0) || (seq_state != SEQ_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx     <= 1'b1;
            baud_timer  <= 16'd0;
            bit_count   <= 4'd0;
            shift_reg   <= 9'h1FF;
            byte_active <= 1'b0;
        end else begin
            if (!byte_active) begin
                uart_tx <= 1'b1;
                if (uart_start_byte) begin
                    // 10-bit frame: 1 Start (0) + 8 Data + 1 Stop (1)
                    uart_tx     <= 1'b0; // Start bit
                    shift_reg   <= {1'b1, uart_byte_data};
                    baud_timer  <= CLK_DIV - 1;
                    bit_count   <= 4'd10;
                    byte_active <= 1'b1;
                end
            end else begin
                if (baud_timer == 16'd0) begin
                    baud_timer <= CLK_DIV - 1;
                    bit_count  <= bit_count - 4'd1;
                    if (bit_count == 4'd1) begin
                        byte_active <= 1'b0;
                        uart_tx     <= 1'b1; // Line idles high
                    end else begin
                        uart_tx   <= shift_reg[0];
                        shift_reg <= {1'b1, shift_reg[8:1]};
                    end
                end else begin
                    baud_timer <= baud_timer - 16'd1;
                end
            end
        end
    end

endmodule
