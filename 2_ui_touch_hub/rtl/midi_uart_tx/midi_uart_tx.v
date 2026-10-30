// ==============================================================================
// Module: midi_uart_tx.v
// Description: MIDI UART Protocol Transmitter for Audio Engine (Teammate 3)
//              - Baud Rate: 31250 bit/s (Standard MIDI) @ 50MHz Pixel Clock
//              - Channel 1: Note-On (0x90) / Note-Off (0x80)
//              - Channel 16: Audio-engine CC map (see doc/MIDI_CONTROL_PROTOCOL.md)
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

`include "params.vh"

module midi_uart_tx #(
    parameter CLK_FREQ = 50000000,
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

    // LFO SysEx Frame Input (Priority 3, from lfo_sysex_tx; Protocol V2)
    //  One request presents two 24-bit FIFO words = F0 7D id | msb lsb F7.
    //  Note/CC events always win same-cycle conflicts; the request stays
    //  asserted until sysex_accept pulses.
    input  wire        sysex_req,
    input  wire [47:0] sysex_msgs,
    // Combinational accept: pulses on the exact cycle the two words enter
    // the FIFO, so the requester can drop its request next cycle without
    // ever double-pushing one frame.
    output wire        sysex_accept,

    // Hardware UART Serial Output (to Teammate 3 Audio Engine)
    output reg         uart_tx,
    output wire        tx_busy,
    output wire        note_ready
);

    localparam CLK_DIV = CLK_FREQ / BAUD; // 62,500,000 / 31250 = 2000

    // --------------------------------------------------------------------------
    // 1. UI parameter ID to the audio-engine CC map (protocol v1)
    // --------------------------------------------------------------------------
    function [6:0] map_id_to_cc;
        input [7:0] id;
        begin
            case (id)
                `PARAM_ID_OSCA_WT_POS:  map_id_to_cc = 7'd20; // OSC A WT Position
                `PARAM_ID_OSCB_WT_POS:  map_id_to_cc = 7'd28; // OSC B WT Position
                `PARAM_ID_OSCA_WAVE:    map_id_to_cc = 7'd21; // OSC A waveform
                `PARAM_ID_OSCB_WAVE:    map_id_to_cc = 7'd29; // OSC B waveform
                `PARAM_ID_OSCA_WARP:    map_id_to_cc = 7'd39; // OSC A warp amount
                `PARAM_ID_OSCB_WARP:    map_id_to_cc = 7'd41; // OSC B warp amount
                `PARAM_ID_OSCA_DETUNE:  map_id_to_cc = 7'd22; // OSC A detune
                `PARAM_ID_OSCB_DETUNE:  map_id_to_cc = 7'd30; // OSC B detune
                `PARAM_ID_OSCA_UNISON:  map_id_to_cc = 7'd23; // OSC A unison
                `PARAM_ID_OSCB_UNISON:  map_id_to_cc = 7'd31; // OSC B unison
                `PARAM_ID_OSCA_VOL:     map_id_to_cc = 7'd46; // OSC A level
                `PARAM_ID_OSCB_VOL:     map_id_to_cc = 7'd47; // OSC B level
                `PARAM_ID_OSCA_POWER:   map_id_to_cc = 7'd36; // OSC A enable
                `PARAM_ID_OSCB_POWER:   map_id_to_cc = 7'd37; // OSC B enable
                `PARAM_ID_FLT_TYPE,
                `PARAM_ID_FLT_POWER:    map_id_to_cc = 7'd42; // Filter mode
                `PARAM_ID_FLT_CUTOFF:   map_id_to_cc = 7'd43; // Filter cutoff
                `PARAM_ID_FLT_RES:      map_id_to_cc = 7'd44; // Filter resonance
                `PARAM_ID_FLT_MIX:      map_id_to_cc = 7'd45; // Filter mix
                `PARAM_ID_ENV1_ATTACK:  map_id_to_cc = 7'd24; // OSC A attack
                `PARAM_ID_ENV1_DECAY:   map_id_to_cc = 7'd25; // OSC A decay
                `PARAM_ID_ENV1_SUSTAIN: map_id_to_cc = 7'd26; // OSC A sustain
                `PARAM_ID_ENV1_RELEASE: map_id_to_cc = 7'd27; // OSC A release
                `PARAM_ID_ENV2_ATTACK:  map_id_to_cc = 7'd32; // OSC B attack
                `PARAM_ID_ENV2_DECAY:   map_id_to_cc = 7'd33; // OSC B decay
                `PARAM_ID_ENV2_SUSTAIN: map_id_to_cc = 7'd34; // OSC B sustain
                `PARAM_ID_ENV2_RELEASE: map_id_to_cc = 7'd35; // OSC B release
                `PARAM_ID_FLT_PAN:      map_id_to_cc = 7'd10; // Reused K27: global output balance
                `PARAM_ID_OSCA_PAN:     map_id_to_cc = 7'd91;
                `PARAM_ID_OSCB_PAN:     map_id_to_cc = 7'd92;
                `PARAM_ID_MASTER_VOL:   map_id_to_cc = 7'd48; // Master level
                default:                map_id_to_cc = 7'd0;
            endcase
        end
    endfunction

    function cc_id_supported;
        input [7:0] id;
        begin
            case (id)
                `PARAM_ID_OSCA_WT_POS, `PARAM_ID_OSCB_WT_POS,
                `PARAM_ID_OSCA_WAVE, `PARAM_ID_OSCB_WAVE,
                `PARAM_ID_OSCA_WARP, `PARAM_ID_OSCB_WARP,
                `PARAM_ID_OSCA_DETUNE, `PARAM_ID_OSCB_DETUNE,
                `PARAM_ID_OSCA_UNISON, `PARAM_ID_OSCB_UNISON,
                `PARAM_ID_OSCA_VOL, `PARAM_ID_OSCB_VOL,
                `PARAM_ID_OSCA_POWER, `PARAM_ID_OSCB_POWER,
                `PARAM_ID_FLT_TYPE, `PARAM_ID_FLT_POWER,
                `PARAM_ID_FLT_CUTOFF, `PARAM_ID_FLT_RES,
                `PARAM_ID_FLT_MIX,
                `PARAM_ID_ENV1_ATTACK, `PARAM_ID_ENV1_DECAY,
                `PARAM_ID_ENV1_SUSTAIN, `PARAM_ID_ENV1_RELEASE,
                `PARAM_ID_ENV2_ATTACK, `PARAM_ID_ENV2_DECAY,
                `PARAM_ID_ENV2_SUSTAIN, `PARAM_ID_ENV2_RELEASE,
                `PARAM_ID_MASTER_VOL, `PARAM_ID_FLT_PAN,
                `PARAM_ID_OSCA_PAN, `PARAM_ID_OSCB_PAN:
                    cc_id_supported = 1'b1;
                default:
                    cc_id_supported = 1'b0;
            endcase
        end
    endfunction

    function [6:0] map_id_value;
        input [7:0] id;
        input [6:0] value;
        begin
            // UI waveform enum: 0=sine, 1=saw, 2=square, 3=triangle.
            // Audio CC uses the center of each documented value band.
            if ((id == `PARAM_ID_OSCA_WAVE) || (id == `PARAM_ID_OSCB_WAVE)) begin
                case (value[1:0])
                    2'd0: map_id_value = 7'd0;
                    2'd1: map_id_value = 7'd96;
                    2'd2: map_id_value = 7'd64;
                    default: map_id_value = 7'd32;
                endcase
            end else begin
                map_id_value = value;
            end
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
    wire [6:0] safe_cc_val = ((map_id_to_cc(cc_param_id) == 7'd23)
                              || (map_id_to_cc(cc_param_id) == 7'd31)) ?
                             ((cc_val == 7'd0) ? 7'd1 : ((cc_val > 7'd8) ? 7'd8 : cc_val)) : cc_val;

    wire note_cc_push = (note_on_req || note_off_req
                        || (cc_req && cc_id_supported(cc_param_id)
                            && fifo_count < 4'd7)) && (fifo_count < 4'd8);
    wire [23:0] in_msg  = note_on_req  ? {8'h90, 1'b0, note_number, 1'b0, note_velocity} :
                          note_off_req ? {8'h80, 1'b0, note_number, 8'h00} :
                                         {8'hBF, 1'b0, map_id_to_cc(cc_param_id), 1'b0,
                                          map_id_value(cc_param_id, safe_cc_val)};

    // Yield to raw requests, independently of the CC-ID decode. An unsupported
    // CC only postpones SysEx until that request drops; accept still denotes
    // the exact FIFO write, so a held request cannot enqueue duplicate frames.
    wire sysex_push = sysex_req && !(note_on_req || note_off_req || cc_req)
                      && (fifo_count <= 4'd6);
    assign sysex_accept = sysex_push;

    wire in_pop = (seq_state == SEQ_IDLE) && (fifo_count != 4'd0) && !uart_byte_busy;
    assign note_ready = fifo_count < 4'd8;

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

            // FIFO Push (Note/CC single word, SysEx two words)
            if (note_cc_push) begin
                fifo_mem[fifo_wr_ptr] <= in_msg;
                fifo_wr_ptr <= fifo_wr_ptr + 3'd1;
            end else if (sysex_push) begin
                fifo_mem[fifo_wr_ptr]      <= sysex_msgs[47:24];
                fifo_mem[fifo_wr_ptr+3'd1] <= sysex_msgs[23:0];
                fifo_wr_ptr <= fifo_wr_ptr + 3'd2;
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

            // FIFO Count Tracking (Note/CC +1, SysEx +2, pop -1)
            fifo_count <= fifo_count
                         + (note_cc_push ? 4'd1 : 4'd0)
                         + (sysex_push  ? 4'd2 : 4'd0)
                         - (in_pop      ? 4'd1 : 4'd0);
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
