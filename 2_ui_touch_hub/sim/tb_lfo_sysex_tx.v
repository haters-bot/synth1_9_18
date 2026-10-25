// ==============================================================================
// Testbench: tb_lfo_sysex_tx.v
// End-to-end verification of the LFO Protocol V2 dispatcher:
//   lfo_sysex_tx -> midi_uart_tx -> UART byte stream (100x speed)
// Covers: initial full sync (80 entries + commit), single-point edit with
// phase-sync frame, route edit, bank-mode edit, and CC preemption integrity.
// ==============================================================================
`timescale 1ns / 1ps

module tb_lfo_sysex_tx;

    reg clk, rst_n;
    always #8 clk = ~clk;   // 62.5 MHz

    // Live configuration driven by the testbench
    reg  [146:0] cfg_nodes;
    reg  [8:0]   cfg_rates;
    reg  [2:0]   cfg_steps, cfg_once;
    reg  [105:0] cfg_sources;
    reg  [423:0] cfg_depths;

    wire sysex_req, sysex_accept, uart_tx, tx_busy;
    wire [47:0] sysex_msgs;

    // CC injection (shared with SysEx into the same UART)
    reg cc_req; reg [7:0] cc_param_id; reg [6:0] cc_val;

    lfo_sysex_tx #(
        .HOLD_CYCLES       (3000),
        .FIRST_HOLD_CYCLES (800)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_nodes(cfg_nodes), .cfg_rates(cfg_rates),
        .cfg_steps(cfg_steps), .cfg_once(cfg_once),
        .cfg_sources(cfg_sources), .cfg_depths(cfg_depths),
        .tx_accept(sysex_accept),
        .sysex_req(sysex_req), .sysex_msgs(sysex_msgs), .busy()
    );

    midi_uart_tx #(
        .CLK_FREQ (62500000),
        .BAUD     (3125000)     // 100x speed for fast simulation
    ) u_tx (
        .clk(clk), .rst_n(rst_n),
        .note_on_req(1'b0), .note_off_req(1'b0), .note_number(7'd0), .note_velocity(7'd100),
        .cc_req(cc_req), .cc_param_id(cc_param_id), .cc_val(cc_val),
        .sysex_req(sysex_req), .sysex_msgs(sysex_msgs), .sysex_accept(sysex_accept),
        .uart_tx(uart_tx), .tx_busy(tx_busy)
    );

    integer errors;
    integer cc_frames_seen;

    // ---------- UART byte receiver (CLK_DIV=20, one bit = 320 ns) ----------
    task receive_byte;
        output [7:0] data;
        integer i;
        begin
            @(negedge uart_tx);
            #(16 * 10);              // center of start bit
            for (i = 0; i < 8; i = i + 1) begin
                #(16 * 20);          // one bit period
                data[i] = uart_tx;
            end
            #(16 * 20);              // stop bit
            if (uart_tx !== 1'b1) begin
                $display("[FAIL] missing stop bit");
                errors = errors + 1;
            end
        end
    endtask

    // Reads the next complete SysEx frame from the line. A CC message may
    // preempt between frames; it is counted and skipped.
    reg [7:0] b0, b1, b2, b3, b4, b5;
    task receive_frame;
        begin
            receive_byte(b0);
            while (b0 == 8'hBF) begin
                receive_byte(b1);
                receive_byte(b2);
                cc_frames_seen = cc_frames_seen + 1;
                $display("[INFO] interleaved CC seen: %02h %02h %02h", b0, b1, b2);
                receive_byte(b0);
            end
            receive_byte(b1); receive_byte(b2);
            receive_byte(b3); receive_byte(b4); receive_byte(b5);
            if (b0 !== 8'hF0 || b1 !== 8'h7D || b5 !== 8'hF7) begin
                $display("[FAIL] malformed frame: %02h %02h %02h %02h %02h %02h",
                         b0, b1, b2, b3, b4, b5);
                errors = errors + 1;
            end
        end
    endtask

    task check_frame;
        input [7:0] exp_id;
        input [15:0] exp_value;
        input [127:0] tag;
        begin
            if (b2 !== exp_id || {b3, b4} !== exp_value) begin
                $display("[FAIL] %0s: got id=%02h val=%04h expected id=%02h val=%04h",
                         tag, b2, {b3, b4}, exp_id, exp_value);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: id=%02h val=%04h", tag, b2, {b3, b4});
            end
        end
    endtask

    // ---------- Expected configuration mirror ----------
    reg [6:0] exp_point [0:20];
    reg [2:0] exp_rate  [0:2];
    reg       exp_step  [0:2];
    reg       exp_once  [0:2];
    reg [1:0] exp_src   [0:52];
    reg [7:0] exp_dep   [0:52];   // raw 8-bit pattern

    function [7:0] exp_id_of;
        input integer k;          // 0..80
        begin
            if (k <= 20)      exp_id_of = 8'd48 + k[7:0];
            else if (k <= 23) exp_id_of = 8'd69 + (k - 21);
            else if (k <= 26) exp_id_of = 8'd72;
            else              exp_id_of = 8'd73 + (k - 27);
        end
    endfunction

    function [15:0] exp_val_of;
        input integer k;
        integer b, t;
        begin
            if (k <= 20)      exp_val_of = {9'd0, exp_point[k]};
            else if (k <= 23) begin
                b = k - 21;
                exp_val_of = {11'd0, exp_once[b], exp_step[b], exp_rate[b]};
            end
            else if (k <= 26) begin
                b = k - 24;
                exp_val_of = 16'd4 + b[1:0];   // bank | 0x0004 restart bit
            end
            else begin
                t = k - 27;
                exp_val_of = {exp_src[t], 6'd0, exp_dep[t]};
            end
        end
    endfunction

    integer k, i;
    initial begin
        // Global timeout
        #60_000_000;
        $display("[FAIL] global timeout");
        $finish;
    end

    initial begin
        clk = 0; rst_n = 0;
        cc_req = 0; cc_param_id = 0; cc_val = 0;
        errors = 0; cc_frames_seen = 0;

        // Default configuration: distinguishable values everywhere
        cfg_nodes = 147'd0;
        for (k = 0; k < 21; k = k + 1) begin
            cfg_nodes[k*7 +: 7] = (k * 6) % 128;
            exp_point[k] = (k * 6) % 128;
        end
        cfg_rates = 9'b000_001_010;                 // bank0=2, bank1=1, bank2=0
        exp_rate[0] = 3'd2; exp_rate[1] = 3'd1; exp_rate[2] = 3'd0;
        cfg_steps = 3'b001;                         // bank0 stepped
        exp_step[0] = 1; exp_step[1] = 0; exp_step[2] = 0;
        cfg_once  = 3'b010;                         // bank1 one-shot
        exp_once[0] = 0; exp_once[1] = 1; exp_once[2] = 0;
        cfg_sources = 106'd0; cfg_depths = 424'd0;
        for (k = 0; k < 53; k = k + 1) begin
            exp_src[k] = 2'd0; exp_dep[k] = 8'd64;
            cfg_depths[k*8 +: 8] = 8'd64;
        end
        cfg_sources[10*2 +: 2] = 2'd1;
        exp_src[10] = 2'd1;
        cfg_depths[10*8 +: 8] = 8'd100;             // +100
        exp_dep[10] = 8'd100;
        cfg_sources[30*2 +: 2] = 2'd2;
        exp_src[30] = 2'd2;
        cfg_depths[30*8 +: 8] = 8'hCE;              // -50
        exp_dep[30] = 8'hCE;

        #64 rst_n = 1;

        // ------------------------------------------------------------------
        // T1: initial full sync = 80 entries in scan order + commit
        // ------------------------------------------------------------------
        $display("[INFO] T1: initial full sync");
        wait (sysex_req);
        for (k = 0; k <= 80; k = k + 1) begin
            receive_frame;
            if (k < 80)
                check_frame(exp_id_of(k), exp_val_of(k), "T1 entry");
            else
                check_frame(8'd126, 16'd0, "T1 commit");
        end

        // ------------------------------------------------------------------
        // T2: edit bank0 point 3 -> frame(51) + phase-sync(72,bank0) + commit
        // ------------------------------------------------------------------
        $display("[INFO] T2: point edit");
        @(posedge clk);
        cfg_nodes[3*7 +: 7] = 7'd77;
        exp_point[3] = 7'd77;
        wait (sysex_req);
        receive_frame; check_frame(8'd51, 16'd77, "T2 point");
        receive_frame; check_frame(8'd72, 16'd0004, "T2 sync");
        receive_frame; check_frame(8'd126, 16'd0, "T2 commit");

        // ------------------------------------------------------------------
        // T3: route 10 -> source 3, depth -127 -> frame(83) + commit only
        // ------------------------------------------------------------------
        $display("[INFO] T3: route edit");
        @(posedge clk);
        cfg_sources[10*2 +: 2] = 2'd3;
        cfg_depths[10*8 +: 8] = 8'h81;              // -127
        exp_src[10] = 2'd3; exp_dep[10] = 8'h81;
        wait (sysex_req);
        receive_frame; check_frame(8'd83, {2'd3, 6'd0, 8'h81}, "T3 route");
        receive_frame; check_frame(8'd126, 16'd0, "T3 commit");

        // ------------------------------------------------------------------
        // T4: bank2 rate 0->5 -> mode(71) + sync(72, bank2) + commit
        // ------------------------------------------------------------------
        $display("[INFO] T4: bank mode edit");
        @(posedge clk);
        cfg_rates[6 +: 3] = 3'd5;
        exp_rate[2] = 3'd5;
        wait (sysex_req);
        receive_frame; check_frame(8'd71, 16'd5, "T4 mode");
        receive_frame; check_frame(8'd72, 16'd0006, "T4 sync");
        receive_frame; check_frame(8'd126, 16'd0, "T4 commit");

        // ------------------------------------------------------------------
        // T5: CC preempts SysEx without corrupting either stream.
        // Edit two entries at once (bank0 point 5 + route 7); a CC lands a
        // couple of cycles after sysex_req rises, so it must overtake the
        // still-pending frames inside the FIFO. Scan order fixes the frame
        // order: point(53) -> sync(72,bank0) -> route(80) -> commit, with
        // the CC bytes observed once between frames on the wire.
        // ------------------------------------------------------------------
        $display("[INFO] T5: CC preemption");
        @(posedge clk);
        cfg_nodes[5*7 +: 7] = 7'd123;
        exp_point[5] = 7'd123;
        cfg_sources[7*2 +: 2] = 2'd2;
        cfg_depths[7*8 +: 8] = 8'd80;
        exp_src[7] = 2'd2; exp_dep[7] = 8'd80;
        fork
            begin : rx_stream
                receive_frame; check_frame(8'd53, 16'd123, "T5 point");
                receive_frame; check_frame(8'd72, 16'd0004, "T5 sync");
                receive_frame; check_frame(8'd80, {2'd2, 6'd0, 8'd80}, "T5 route");
                receive_frame; check_frame(8'd126, 16'd0, "T5 commit");
            end
            begin : cc_injector
                wait (sysex_req);
                repeat (2) @(posedge clk);
                @(negedge clk);
                cc_req = 1'b1; cc_param_id = 8'h30; cc_val = 7'd55; // FLT_CUTOFF -> CC43
                @(negedge clk);
                cc_req = 1'b0;
            end
        join
        if (cc_frames_seen !== 1) begin
            $display("[FAIL] expected 1 interleaved CC, saw %0d", cc_frames_seen);
            errors = errors + 1;
        end else
            $display("[PASS] T5 CC preempted once");

        // ------------------------------------------------------------------
        if (errors == 0) $display("[DONE] ALL TESTS PASSED");
        else             $display("[DONE] %0d ERRORS", errors);
        $finish;
    end
endmodule
