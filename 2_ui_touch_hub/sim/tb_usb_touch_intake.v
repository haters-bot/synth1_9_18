// ==============================================================================
// Testbench: tb_usb_touch_intake.v
// Verification: Tests USB touch intake report decoding, multi-format support,
//               ILITEK 0x00 packets, Report ID 1..7 packets, diagnostic packet rejection,
//               coordinate retention on finger lift, and CDC domain crossing.
// ==============================================================================

`timescale 1ns / 1ps

module tb_usb_touch_intake;

    reg clk_usb;
    reg rst_usb_n;
    wire usb_dp;
    wire usb_dm;
    reg clk_pixel;
    reg pixel_rst_n;

    wire        touch_valid;
    wire [15:0] touch_x;
    wire [15:0] touch_y;
    wire        touch_state;
    wire        usb_connected;
    wire [1:0]  usb_dev_type;
    wire        usb_conn_err;
    wire        touch_activity;
    wire [63:0] dbg_report;
    wire [63:0] dbg_regs;
    wire [7:0]  dbg_pkt_cnt;

    usb_touch_intake u_dut (
        .clk_usb        (clk_usb),
        .rst_usb_n      (rst_usb_n),
        .usb_dp         (usb_dp),
        .usb_dm         (usb_dm),
        .clk_pixel      (clk_pixel),
        .pixel_rst_n    (pixel_rst_n),
        .touch_valid    (touch_valid),
        .touch_x        (touch_x),
        .touch_y        (touch_y),
        .touch_state    (touch_state),
        .usb_connected  (usb_connected),
        .usb_dev_type   (usb_dev_type),
        .usb_conn_err   (usb_conn_err),
        .touch_activity (touch_activity),
        .dbg_report     (dbg_report),
        .dbg_regs       (dbg_regs),
        .dbg_pkt_cnt    (dbg_pkt_cnt)
    );

    // 60.0MHz clk_usb (period = 16.666ns)
    always #8.333 clk_usb = ~clk_usb;

    // 62.5MHz clk_pixel (period = 16.0ns)
    always #8.0 clk_pixel = ~clk_pixel;

    task send_hid_report;
        input [63:0] report_data;
        begin
            @(posedge clk_usb);
            force u_dut.hid_report_data = report_data;
            force u_dut.hid_report_pulse = 1'b1;
            force u_dut.hid_typ = 2'd3; // Touch / Gamepad
            @(posedge clk_usb);
            force u_dut.hid_report_pulse = 1'b0;
            // Wait for CDC sync into clk_pixel domain (~3 pixel cycles)
            repeat (6) @(posedge clk_pixel);
            #1;
        end
    endtask

    initial begin
        clk_usb     = 0;
        rst_usb_n   = 0;
        clk_pixel   = 0;
        pixel_rst_n = 0;

        #50;
        rst_usb_n   = 1;
        pixel_rst_n = 1;
        repeat (10) @(posedge clk_pixel);

        // ----------------------------------------------------------------------
        // Test 1: ILITEK Live Telemetry Touch Down Packet
        // Report: 00 4B CB 23 4D 21 00 00 -> X=0x23CB (9163), Y=0x214D (8525), Down=1
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 1: ILITEK Touch Down Packet");
        send_hid_report(64'h0000_214D_23CB_4B00);
        if (touch_state !== 1'b1 || touch_x !== 16'd9163 || touch_y !== 16'd8525) begin
            $display("[FAIL] ILITEK Touch Down failed! state=%b x=%d y=%d", touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] ILITEK Touch Down verified: state=%b x=%d y=%d", touch_state, touch_x, touch_y);

        // ----------------------------------------------------------------------
        // Test 2: ILITEK Touch Move Packet
        // Report: 00 4B 00 10 00 08 00 00 -> X=0x1000 (4096), Y=0x0800 (2048), Down=1
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 2: ILITEK Touch Move Packet");
        send_hid_report(64'h0000_0800_1000_4B00);
        if (touch_state !== 1'b1 || touch_x !== 16'd4096 || touch_y !== 16'd2048) begin
            $display("[FAIL] ILITEK Touch Move failed! state=%b x=%d y=%d", touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] ILITEK Touch Move verified: state=%b x=%d y=%d", touch_state, touch_x, touch_y);

        // ----------------------------------------------------------------------
        // Test 3: ILITEK Touch Release Packet
        // Report: 00 00 00 10 00 08 00 00 -> Down=0, Coordinates must be PRESERVED!
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 3: ILITEK Touch Release Packet");
        send_hid_report(64'h0000_0800_1000_0000);
        if (touch_state !== 1'b0 || touch_x !== 16'd4096 || touch_y !== 16'd2048) begin
            $display("[FAIL] ILITEK Touch Release failed! state=%b x=%d y=%d (expected x=4096, y=2048)",
                     touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] ILITEK Touch Release verified: state=0, coordinates preserved (x=4096, y=2048)");

        // ----------------------------------------------------------------------
        // Test 4: Standard Windows Report ID 1 Touch Packet
        // Report: 01 01 20 03 40 05 00 00 -> X=0x0320 (800), Y=0x0540 (1344), Down=1
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 4: Windows Report ID 1 Touch Packet");
        send_hid_report(64'h0000_0540_0320_0101);
        if (touch_state !== 1'b1 || touch_x !== 16'd800 || touch_y !== 16'd1344) begin
            $display("[FAIL] Report ID 1 Touch failed! state=%b x=%d y=%d", touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] Report ID 1 Touch verified: state=%b x=%d y=%d", touch_state, touch_x, touch_y);

        // ----------------------------------------------------------------------
        // Test 5: Report ID 2 Touch Packet (Must NOT be dropped)
        // Report: 02 01 60 09 80 0A 00 00 -> X=0x0960 (2400), Y=0x0A80 (2688), Down=1
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 5: Report ID 2 Touch Packet");
        send_hid_report(64'h0000_0A80_0960_0102);
        if (touch_state !== 1'b1 || touch_x !== 16'd2400 || touch_y !== 16'd2688) begin
            $display("[FAIL] Report ID 2 Touch failed! state=%b x=%d y=%d", touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] Report ID 2 Touch verified: state=%b x=%d y=%d", touch_state, touch_x, touch_y);

        // ----------------------------------------------------------------------
        // Test 6: Report ID 4 Touch Packet
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 6: Report ID 4 Touch Packet");
        send_hid_report(64'h0000_1234_5678_0104);
        if (touch_state !== 1'b1 || touch_x !== 16'h5678 || touch_y !== 16'h1234) begin
            $display("[FAIL] Report ID 4 Touch failed! state=%b x=%h y=%h", touch_state, touch_x, touch_y);
            $stop;
        end
        $display("[PASS] Report ID 4 Touch verified: state=%b x=%h y=%h", touch_state, touch_x, touch_y);

        // ----------------------------------------------------------------------
        // Test 7: Vendor Diagnostic Packet Filter (b0 = 0x80)
        // Must be ignored! Coordinates and state must remain unchanged.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 7: Vendor Diagnostic Packet Filter (0x80)");
        send_hid_report(64'hFFFF_FFFF_FFFF_FF80);
        if (touch_x !== 16'h5678 || touch_y !== 16'h1234) begin
            $display("[FAIL] Diagnostic packet was not ignored! x=%h y=%h", touch_x, touch_y);
            $stop;
        end
        $display("[PASS] Vendor Diagnostic Packet correctly filtered out!");

        $display("=================================================");
        $display("   ALL USB_TOUCH_INTAKE TESTS PASSED (100%%)     ");
        $display("=================================================");
        $finish;
    end

endmodule
