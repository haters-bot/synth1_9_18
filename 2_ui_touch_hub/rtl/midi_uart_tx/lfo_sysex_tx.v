// ==============================================================================
// Module: lfo_sysex_tx.v
// Description: LFO configuration SysEx dispatcher (UI LFO Modulation Protocol V2)
//   - Waits for the LFO UI to fall quiet, snapshots the full configuration
//     (3 banks x 7 points, rates/modes, 53 routes), diffs it against the last
//     committed snapshot and streams only changed 6-byte frames
//     F0 7D <id> <msb> <lsb> F7 into midi_uart_tx.
//   - A batch always ends with the atomic commit frame (ID 126). Edits during
//     a stream still finish the current consistent snapshot first; the new
//     difference triggers the next batch.
//   - Phase-sync frames (ID 72) ride along with any curve/mode change of a
//     bank so the audio board restarts its phase accumulator in lockstep.
//   - CC/Note traffic always wins same-cycle FIFO conflicts in midi_uart_tx.
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================
module lfo_sysex_tx #(
    parameter PRESET_ENABLE=0,
    parameter HOLD_CYCLES      = 1_000_000,  // 20 ms edit-quiet window @ 50 MHz
    parameter FIRST_HOLD_CYCLES = 300_000    // initial full sync after 6 ms
)(
    input wire preset_hold,preset_adopt,
    input  wire        clk,
    input  wire        rst_n,

    // Live configuration (snapshots from lfo_editor_state / lfo_binding_state)
    input  wire [146:0] cfg_nodes,   // 3 banks x 7 points x 7 bit, bank-major
    input  wire [8:0]   cfg_rates,   // bank b rate at [b*3 +: 3]
    input  wire [2:0]   cfg_steps,   // bank b stepped flag at [b]
    input  wire [2:0]   cfg_once,    // bank b one-shot flag at [b]
    input  wire [105:0] cfg_sources, // route t source at [t*2 +: 2]
    input  wire [423:0] cfg_depths,  // route t signed depth at [t*8 +: 8]

    // Injection handshake (midi_uart_tx accepts when FIFO has room and no
    // Note/CC event lands on the same cycle; tx_accept pulses on success)
    input  wire        tx_accept,
    output reg         sysex_req,
    output reg  [47:0] sysex_msgs,   // {F0,7D,id | value[13:7],value[6:0],F7}
    output wire        busy
);
    // Entry layout of one snapshot batch (scan order):
    //   0..20  curve points : ID 48+idx, value = point amplitude 0..127
    //   21..23 bank modes   : ID 69+b,   value = rate | stepped<<3 | once<<4
    //   24..26 phase sync   : ID 72,     value = bank | 0x0004
    //   27..79 routes       : ID 73+t,   value = source<<8 | (depth & 0xFF)
    // commit               : ID 126,    value ignored
    localparam [7:0] ID_POINT0  = 8'd48;
    localparam [7:0] ID_MODE0   = 8'd69;
    localparam [7:0] ID_SYNC    = 8'd72;
    localparam [7:0] ID_ROUTE0  = 8'd73;
    localparam [7:0] ID_COMMIT  = 8'd126;

    localparam S_WATCH = 2'd0, S_LATCH = 2'd1, S_STREAM = 2'd2, S_COMMIT = 2'd3;

    // Last committed snapshot; updated together with the batch dirty set.
    reg [146:0] sh_nodes;
    reg [8:0]   sh_rates;
    reg [2:0]   sh_steps, sh_once;
    reg [105:0] sh_sources;
    reg [423:0] sh_depths;
    reg [79:0]  dirty;
    reg [6:0]   scan;
    reg [1:0]   state;
    reg [20:0]  hold;
    reg         first_boot;
    integer e, b, t;

    // Input register stage: the source registers (binding/editor) live far
    // away in the fabric; registering first keeps their fanout path pure
    // routing so the wide comparators only ever start from local flops.
    reg [146:0] q_nodes;
    reg [8:0]   q_rates;
    reg [2:0]   q_steps, q_once;
    reg [105:0] q_sources;
    reg [423:0] q_depths;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_nodes <= 147'd0; q_rates <= 9'd0; q_steps <= 3'd0; q_once <= 3'd0;
            q_sources <= 106'd0; q_depths <= 424'd0;
        end else begin
            q_nodes <= cfg_nodes;   q_rates <= cfg_rates;
            q_steps <= cfg_steps;   q_once <= cfg_once;
            q_sources <= cfg_sources; q_depths <= cfg_depths;
        end
    end

    // Pipelined change detection. Long source buses never feed one wide
    // comparator: stage 1 registers a per-entry 1-bit difference vector
    // (each entry compares at most 10 bits), stage 2 reduces the vectors,
    // and the LATCH cycle assembles the dirty set from those registers only.
    // Edit activity is detected from changes of the difference signature
    // (77 bit) instead of a second 692-bit previous-value bank; a signature
    // that misses a re-edit of an already-dirty entry only merges that edit
    // into the next batch, which is functionally safe.
    reg [20:0] dpt_vec;            // per-point diff against shadow
    reg [2:0]  dmd_vec;            // per-bank mode diff
    reg [52:0] drt_vec;            // per-route diff
    reg [76:0] sig_prev;
    reg diff_any, chg_any;
    wire [76:0] diff_sig = {drt_vec, dmd_vec, dpt_vec};
    integer p, m, r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dpt_vec <= 21'h1FFFFF; dmd_vec <= 3'b111; drt_vec <= 53'h1FFFFFFFFFFFF;
            sig_prev <= 77'd0;
            diff_any <= 1'b1; chg_any <= 1'b1;
        end else begin
            for (p = 0; p < 21; p = p + 1)
                dpt_vec[p] <= (q_nodes[p*7 +: 7] != sh_nodes[p*7 +: 7]);
            for (m = 0; m < 3; m = m + 1)
                dmd_vec[m] <= (q_rates[m*3 +: 3] != sh_rates[m*3 +: 3])
                            || (q_steps[m] != sh_steps[m]) || (q_once[m] != sh_once[m]);
            for (r = 0; r < 53; r = r + 1)
                drt_vec[r] <= (q_sources[r*2 +: 2] != sh_sources[r*2 +: 2])
                            || (q_depths [r*8 +: 8] != sh_depths [r*8 +: 8]);
            // Stage-2 aggregates (registered, shallow ORs from the vectors)
            diff_any <= (|dpt_vec) | (|dmd_vec) | (|drt_vec);
            chg_any  <= (diff_sig != sig_prev);
            sig_prev <= diff_sig;
        end
    end
    wire pending     = diff_any;   // uncommitted differences exist
    wire edit_active = chg_any;    // configuration is still being edited

    // Frame assembly for the streaming entry (values come from the committed
    // shadow, guaranteeing one batch describes one consistent snapshot).
    reg [15:0] entry_value;
    reg [7:0]  entry_id;
    // Decode into a local registered one-hot bank before selecting payloads.
    // This breaks scan/subtract -> 53-way priority mux -> frame on GW5A.
    // The tag prevents the extra decode cycle from sending the previous entry.
    reg [79:0] entry_select /* synthesis syn_preserve=1 syn_keep=1 */;
    reg [6:0] entry_scan /* synthesis syn_preserve=1 syn_keep=1 */;
    integer decode_entry,encode_point,encode_bank,encode_route;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin entry_select<=80'd1;entry_scan<=0;end
        else begin
            entry_scan<=scan;
            for(decode_entry=0;decode_entry<80;decode_entry=decode_entry+1)
                entry_select[decode_entry]<=scan==decode_entry;
        end
    end
    always @(*) begin
        entry_id    = 8'd0;
        entry_value = 16'd0;
        // Constant slices retain the existing workaround for Gowin's
        // variable-index route/mode reads. Parallel masks avoid priority chains.
        for(encode_point=0;encode_point<21;encode_point=encode_point+1)begin
            entry_id=entry_id|({8{entry_select[encode_point]}}&(ID_POINT0+encode_point[7:0]));
            entry_value=entry_value|({16{entry_select[encode_point]}}&{9'd0,sh_nodes[encode_point*7+:7]});
        end
        for(encode_bank=0;encode_bank<3;encode_bank=encode_bank+1)begin
            entry_id=entry_id|({8{entry_select[21+encode_bank]}}&(ID_MODE0+encode_bank[7:0]));
            entry_id=entry_id|({8{entry_select[24+encode_bank]}}&ID_SYNC);
            entry_value=entry_value|({16{entry_select[21+encode_bank]}}&
                {11'd0,sh_once[encode_bank],sh_steps[encode_bank],sh_rates[encode_bank*3+:3]});
            entry_value=entry_value|({16{entry_select[24+encode_bank]}}&(16'd4+encode_bank[15:0]));
        end
        for(encode_route=0;encode_route<53;encode_route=encode_route+1)begin
            entry_id=entry_id|({8{entry_select[27+encode_route]}}&(ID_ROUTE0+encode_route[7:0]));
            entry_value=entry_value|({16{entry_select[27+encode_route]}}&
                {6'd0,sh_sources[encode_route*2+:2],sh_depths[encode_route*8+:8]});
        end
    end

    wire [47:0] commit_msgs = {8'hF0, 8'h7D, ID_COMMIT, 8'h00, 8'h00, 8'hF7};

    assign busy = (state != S_WATCH) | sysex_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh_nodes <= 147'd0; sh_rates <= 9'd0;
            sh_steps <= 3'd0;   sh_once  <= 3'd0;
            sh_sources <= 106'd0; sh_depths <= 424'd0;
            dirty    <= 80'd0;
            scan     <= 7'd0;
            state    <= S_WATCH;
            hold     <= 21'd0;
            first_boot <= 1'b1;
            sysex_req  <= 1'b0;
            sysex_msgs <= 48'd0;
        end else if(PRESET_ENABLE && preset_adopt)begin
            sh_nodes<=q_nodes;sh_rates<=q_rates;sh_steps<=q_steps;sh_once<=q_once;
            sh_sources<=q_sources;sh_depths<=q_depths;
            dirty<=0;scan<=0;state<=S_WATCH;hold<=0;first_boot<=0;sysex_req<=0;
        end else if(PRESET_ENABLE && preset_hold)begin
            dirty<=0;scan<=0;state<=S_WATCH;hold<=0;sysex_req<=0;
        end else begin
            case (state)
                S_WATCH: begin
                    // The quiet timer only advances while the UI is idle and
                    // caps at the target; a batch starts when the cap is
                    // reached with uncommitted differences pending.
                    if (edit_active)
                        hold <= 21'd0;
                    else if (hold < (first_boot ? FIRST_HOLD_CYCLES[20:0] : HOLD_CYCLES[20:0]))
                        hold <= hold + 21'd1;
                    if (!edit_active
                        && hold == (first_boot ? FIRST_HOLD_CYCLES[20:0] : HOLD_CYCLES[20:0])
                        && pending)
                        state <= S_LATCH;
                end
                S_LATCH: begin
                    sh_nodes   <= q_nodes;
                    sh_rates   <= q_rates;
                    sh_steps   <= q_steps;
                    sh_once    <= q_once;
                    sh_sources <= q_sources;
                    sh_depths  <= q_depths;
                    // Compare the SAME q values being latched above. The
                    // pipelined difference vectors lag q by one clock: using
                    // them here can absorb a fresh binding into the shadow
                    // without ever marking its route dirty (lost forever).
                    for (e = 0; e < 21; e = e + 1)
                        dirty[e] <= first_boot | (q_nodes[e*7+:7] != sh_nodes[e*7+:7]);
                    for (b = 0; b < 3; b = b + 1) begin
                        dirty[21+b] <= first_boot |
                            (q_rates[b*3+:3] != sh_rates[b*3+:3]) |
                            (q_steps[b] != sh_steps[b]) | (q_once[b] != sh_once[b]);
                        // Curve or mode edits reset that bank's phase in the
                        // UI editor; the audio board must restart as well.
                        dirty[24+b] <= first_boot |
                            (q_nodes[b*49+:49] != sh_nodes[b*49+:49]) |
                            (q_rates[b*3+:3] != sh_rates[b*3+:3]) |
                            (q_steps[b] != sh_steps[b]) | (q_once[b] != sh_once[b]);
                    end
                    for (t = 0; t < 53; t = t + 1)
                        dirty[27+t] <= first_boot |
                            (q_sources[t*2+:2] != sh_sources[t*2+:2]) |
                            (q_depths[t*8+:8] != sh_depths[t*8+:8]);
                    first_boot <= 1'b0;
                    scan       <= 7'd0;
                    state      <= S_STREAM;
                end
                S_STREAM: begin
                    if (dirty == 80'd0) begin
                        state <= S_COMMIT;
                    end else if (dirty[scan] && entry_scan==scan) begin
                        sysex_msgs <= {8'hF0, 8'h7D, entry_id,
                                       1'b0, entry_value[13:7],
                                       1'b0, entry_value[6:0], 8'hF7};
                        sysex_req  <= 1'b1;
                        if (tx_accept) begin
                            dirty[scan] <= 1'b0;
                            sysex_req   <= 1'b0;
                            scan        <= (scan == 7'd79) ? 7'd0 : scan + 7'd1;
                        end
                    end else if(!dirty[scan]) begin
                        scan <= (scan == 7'd79) ? 7'd0 : scan + 7'd1;
                    end
                end
                S_COMMIT: begin
                    sysex_msgs <= commit_msgs;
                    sysex_req  <= 1'b1;
                    if (tx_accept) begin
                        sysex_req <= 1'b0;
                        hold      <= 21'd0;
                        state     <= S_WATCH;
                    end
                end
            endcase
        end
    end
endmodule
