// ==============================================================================
// Testbench: tb_midi_uart_tx.v
// Verification: MIDI UART Protocol Transmitter for Audio Engine (Teammate 3)
// ==============================================================================

`timescale 1ns / 1ps
`include "../rtl/ui_vector_engine/params.vh"

module tb_midi_uart_tx;

    reg clk;
    reg rst_n;

    reg        note_on_req;
    reg        note_off_req;
    reg [6:0]  note_number;
    reg [6:0]  note_velocity;

    reg        cc_req;
    reg [7:0]  cc_param_id;
    reg [6:0]  cc_val;

    wire uart_tx;
    wire tx_busy;
    reg [7:0] b0, b1, b2;

    // Use smaller divider in testbench for fast simulation (CLK_DIV=20 instead of 2000)
    midi_uart_tx #(
        .CLK_FREQ (62500000),
        .BAUD     (3125000) // 100x speed for fast simulation
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .note_on_req   (note_on_req),
        .note_off_req  (note_off_req),
        .note_number   (note_number),
        .note_velocity (note_velocity),
        .cc_req        (cc_req),
        .cc_param_id   (cc_param_id),
        .cc_val        (cc_val),
        .uart_tx       (uart_tx),
        .tx_busy       (tx_busy)
    );

    always #8 clk = ~clk;

    // Helper task to receive and verify 1 UART byte
    task receive_byte;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit (0)
            @(negedge uart_tx);
            #(16 * 10); // Center of start bit

            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                #(16 * 20); // 1 bit period
                data[i] = uart_tx;
            end

            // Wait for stop bit (1)
            #(16 * 20);
            if (uart_tx !== 1'b1) begin
                $display("[FAIL] Missing stop bit!");
                $stop;
            end
        end
    endtask

    task send_cc_check;
        input [7:0] parameter_id;
        input [6:0] value;
        input [6:0] expected_cc;
        input [6:0] expected_value;
        begin
            @(negedge clk);
            cc_req = 1'b1;
            cc_param_id = parameter_id;
            cc_val = value;
            @(negedge clk);
            cc_req = 1'b0;
            receive_byte(b0);
            receive_byte(b1);
            receive_byte(b2);
            if (b0 !== 8'hBF || b1 !== {1'b0, expected_cc}
                || b2 !== {1'b0, expected_value}) begin
                $display("[FAIL] CC map id=%02h got %02h %02h %02h expected BF %02h %02h",
                         parameter_id, b0, b1, b2,
                         {1'b0, expected_cc}, {1'b0, expected_value});
                $stop;
            end else begin
                $display("[PASS] CC map id=%02h -> CC%0d value=%0d",
                         parameter_id, expected_cc, expected_value);
            end
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        note_on_req = 0;
        note_off_req = 0;
        note_number = 0;
        note_velocity = 0;
        cc_req = 0;
        cc_param_id = 0;
        cc_val = 0;

        #32 rst_n = 1;
        #100;

        // ----------------------------------------------------------------------
        // Test 1: Note-On (Middle C, Note 60 = 0x3C, Vel 100 = 0x64)
        // Expected MIDI Packet: 0x90, 0x3C, 0x64
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 1: Note-On Channel 1");
        @(posedge clk);
        note_on_req   = 1;
        note_number   = 7'd60;
        note_velocity = 7'd100;
        @(posedge clk);
        note_on_req   = 0;

        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);

        if (b0 !== 8'h90 || b1 !== 8'h3C || b2 !== 8'h64) begin
            $display("[FAIL] Note-On packet mismatch! Got %h %h %h, expected 90 3C 64", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received Note-On: %h %h %h (Ch1 Note=60 Vel=100)", b0, b1, b2);
        end

        #200;

        // ----------------------------------------------------------------------
        // Test 2: Note-Off (Note 60 = 0x3C, Vel 0 = 0x00)
        // Expected MIDI Packet: 0x80, 0x3C, 0x00
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 2: Note-Off Channel 1");
        @(posedge clk);
        note_off_req  = 1;
        note_number   = 7'd60;
        @(posedge clk);
        note_off_req  = 0;

        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);

        if (b0 !== 8'h80 || b1 !== 8'h3C || b2 !== 8'h00) begin
            $display("[FAIL] Note-Off packet mismatch! Got %h %h %h, expected 80 3C 00", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received Note-Off: %h %h %h (Ch1 Note=60 Off)", b0, b1, b2);
        end

        #200;

        // ----------------------------------------------------------------------
        // Test 3: Parameter CC (OSC A WT POS -> CC20 = 0x14, Val 85 = 0x55)
        // Expected MIDI Packet: 0xBF, 0x14, 0x55
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 3: Parameter CC Channel 16 (WT POS)");
        @(posedge clk);
        cc_req      = 1;
        cc_param_id = `PARAM_ID_OSCA_WT_POS;
        cc_val      = 7'd85;
        @(posedge clk);
        cc_req      = 0;

        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);

        if (b0 !== 8'hBF || b1 !== 8'h14 || b2 !== 8'h55) begin
            $display("[FAIL] CC WT_POS packet mismatch! Got %h %h %h, expected BF 14 55", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received CC20: %h %h %h (Ch16 WT_POS=85)", b0, b1, b2);
        end

        #200;

        // ----------------------------------------------------------------------
        // Test 4: Parameter CC (Filter Cutoff -> audio protocol CC43)
        // Expected MIDI Packet: 0xBF, 0x2B, 0x70
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 4: Parameter CC Channel 16 (Cutoff)");
        @(posedge clk);
        cc_req      = 1;
        cc_param_id = `PARAM_ID_FLT_CUTOFF;
        cc_val      = 7'd112;
        @(posedge clk);
        cc_req      = 0;

        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);

        if (b0 !== 8'hBF || b1 !== 8'h2B || b2 !== 8'h70) begin
            $display("[FAIL] CC Cutoff packet mismatch! Got %h %h %h, expected BF 2B 70", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received CC43: %h %h %h (Ch16 Cutoff=112)", b0, b1, b2);
        end

        // Audio-engine protocol v1: B oscillator controls are independent,
        // wave enums are converted to the centers of the audio value bands.
        send_cc_check(`PARAM_ID_OSCB_WT_POS, 7'd85, 7'd28, 7'd85);
        send_cc_check(`PARAM_ID_OSCB_DETUNE, 7'd52, 7'd30, 7'd52);
        send_cc_check(`PARAM_ID_OSCB_UNISON, 7'd127, 7'd31, 7'd8);
        send_cc_check(`PARAM_ID_OSCB_WAVE, 7'd3, 7'd29, 7'd32);
        send_cc_check(`PARAM_ID_OSCA_WAVE, 7'd2, 7'd21, 7'd64);
        send_cc_check(`PARAM_ID_FLT_RES, 7'd48, 7'd44, 7'd48);
        send_cc_check(`PARAM_ID_FLT_MIX, 7'd72, 7'd45, 7'd72);
        send_cc_check(`PARAM_ID_FLT_TYPE, 7'd4, 7'd42, 7'd4);
        send_cc_check(`PARAM_ID_FLT_POWER, 7'd0, 7'd42, 7'd0);
        send_cc_check(`PARAM_ID_ENV1_ATTACK, 7'd12, 7'd24, 7'd12);
        send_cc_check(`PARAM_ID_ENV1_RELEASE, 7'd67, 7'd27, 7'd67);
        send_cc_check(`PARAM_ID_MASTER_VOL, 7'd100, 7'd48, 7'd100);

        // Unsupported legacy/local-only controls must not emit CC0 or alias
        // into unrelated audio parameters (Hold, pan, and FX placeholders).
        @(negedge clk);
        cc_req = 1'b1;
        cc_param_id = `PARAM_ID_ENV1_HOLD;
        cc_val = 7'd90;
        @(negedge clk);
        cc_req = 1'b0;
        repeat (8) @(posedge clk);
        if (tx_busy !== 1'b0 || uart_tx !== 1'b1) begin
            $display("[FAIL] Unsupported Hold control emitted UART data");
            $stop;
        end else begin
            $display("[PASS] Unsupported Hold control was suppressed");
        end
        @(negedge clk);cc_req=1;cc_param_id=`PARAM_ID_OSCA_PAN;cc_val=7'd127;
        @(negedge clk);cc_req=0;
        repeat (8) @(posedge clk);
        if (tx_busy !== 1'b0 || uart_tx !== 1'b1) begin
            $display("[FAIL] Unsupported mono Pan control emitted UART data");
            $stop;
        end else begin
            $display("[PASS] Unsupported mono Pan control was suppressed");
        end

        // ----------------------------------------------------------------------
        // Test 5: Rapid Back-to-Back Enqueue (FIFO Protection)
        // Assert Note-On then Note-Off immediately on consecutive clocks
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 5: Rapid FIFO Back-to-Back Note-On & Note-Off");
        @(posedge clk);
        note_on_req   = 1;
        note_number   = 7'd48;
        note_velocity = 7'd110;
        @(posedge clk);
        note_on_req   = 0;
        note_off_req  = 1; // Immediate next cycle while Note-On is still serializing
        note_number   = 7'd48;
        @(posedge clk);
        note_off_req  = 0;

        // Packet 1: Note-On (0x90 0x30 0x6E)
        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);
        if (b0 !== 8'h90 || b1 !== 8'h30 || b2 !== 8'h6E) begin
            $display("[FAIL] FIFO Packet 1 Note-On mismatch! Got %h %h %h, expected 90 30 6E", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received Queued Note-On: %h %h %h", b0, b1, b2);
        end

        // Packet 2: Note-Off (0x80 0x30 0x00)
        receive_byte(b0);
        receive_byte(b1);
        receive_byte(b2);
        if (b0 !== 8'h80 || b1 !== 8'h30 || b2 !== 8'h00) begin
            $display("[FAIL] FIFO Packet 2 Note-Off mismatch! Got %h %h %h, expected 80 30 00", b0, b1, b2);
            $stop;
        end else begin
            $display("[PASS] Received Queued Note-Off: %h %h %h", b0, b1, b2);
        end

        $display("=================================================");
        $display("   ALL MIDI_UART_TX PROTOCOL TESTS PASSED (100%%)");
        $display("=================================================");
        $finish;
    end

endmodule
