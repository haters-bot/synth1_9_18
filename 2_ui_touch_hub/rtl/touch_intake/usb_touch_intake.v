// ==============================================================================
// Module: usb_touch_intake.v
// Description: USB Host Touchscreen Intake & Coordinate Demuxer for UI Touch Hub
//              - Integrates Full-Speed (12Mbps) / Low-Speed (1.5Mbps) USB HID Host
//              - Connects directly to FPGA Bank 3 pins M15 (D+) and M16 (D-)
//              - Supports ILITEK Multi-Touch Digitizers (VID 0x222A, PID 0x0001)
//                and standard Windows/HID compliant capacitive touchscreens
//              - Auto-adapts to Report ID Format (Byte 0=ID, Byte 1=Tip Switch)
//                and Direct Format (Byte 0=Tip Switch) + Mouse Emulation Fallback
//              - Safe Clock Domain Crossing from 60MHz USB Clock to 62.5MHz Pixel Clock
//              - Hardware watchdog auto-release (prevents stuck touch on finger lift)
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`timescale 1ns / 1ps

module usb_touch_intake (
    // 60MHz USB Clock Domain (from Gowin_PLL_USB)
    input  wire        clk_usb,         // 60.0MHz clock
    input  wire        rst_usb_n,       // Active-low reset for USB domain

    // Physical USB-A Pins (J18 on Tang Mega 138K Dock)
    inout  wire        usb_dp,          // M15: USB D+ (Host Port 1)
    inout  wire        usb_dm,          // M16: USB D- (Host Port 1)

    // Video/Pixel Clock Domain (62.5MHz clk_pixel)
    input  wire        clk_pixel,       // 62.5MHz pixel clock
    input  wire        pixel_rst_n,     // Active-low reset for pixel domain

    // Decoded Touch Stream (to touch_event_router via merged_touch)
    output reg         touch_valid,     // 1-cycle strobe per valid touch report
    output reg  [15:0] touch_x,         // Raw touch X coordinate (passed to dynamic normalizer)
    output reg  [15:0] touch_y,         // Raw touch Y coordinate (passed to dynamic normalizer)
    output reg         touch_state,     // 1: Contact down (pressed), 0: Lifted (released)

    // Hardware Diagnostic Status
    output wire        usb_connected,   // USB device successfully enumerated
    output wire [1:0]  usb_dev_type,    // 0: none, 1: keyboard, 2: mouse, 3: touch/gamepad
    output wire        usb_conn_err,    // Connection / bus error indicator
    output reg         touch_activity,  // Blinks/toggles on received touch packets
    output wire [63:0] dbg_report,      // Last 64-bit HID report
    output wire [63:0] dbg_regs,        // VID, PID, Class, SubClass, Protocol
    output reg  [7:0]  dbg_pkt_cnt      // Incremental packet counter (pixel domain)
);

    // --------------------------------------------------------------------------
    // 1. Physical USB Pin Tri-State Buffer
    // --------------------------------------------------------------------------
    wire usb_dp_i = usb_dp;
    wire usb_dm_i = usb_dm;
    wire usb_dp_o;
    wire usb_dm_o;
    wire usb_oe;

    assign usb_dp = usb_oe ? usb_dp_o : 1'bz;
    assign usb_dm = usb_oe ? usb_dm_o : 1'bz;

    // --------------------------------------------------------------------------
    // 2. Compact USB Full-Speed/Low-Speed HID Host Core
    // --------------------------------------------------------------------------
    wire [1:0]  hid_typ;
    wire        hid_report_pulse;
    wire        hid_connerr;
    wire [63:0] hid_report_data;
    wire [63:0] hid_regs;
    wire [2:0]  mouse_btn;
    wire signed [7:0] mouse_dx, mouse_dy;

    wire [9:0]  rom_addr;
    wire [3:0]  rom_dout;
    wire        rom_en;
    wire        u_dev_conn;

    usb_hid_host #(
        .FULL_SPEED              (1),
        .KEYBOARD_SUPPORT        (0),
        .MOUSE_SUPPORT           (1),
        .GAME_SUPPORT            (1),
        .XINPUT_SWAP_AB_XY       (0),
        .FORCE_ARDUINO_KEYBOARD  (0)
    ) u_usb_hid_host (
        .clk                     (clk_usb),
        .reset                   (~rst_usb_n),
        .cs                      (1'b1),
        .usb_dm_i                (usb_dm_i),
        .usb_dp_i                (usb_dp_i),
        .usb_dm_o                (usb_dm_o),
        .usb_dp_o                (usb_dp_o),
        .usb_oe                  (usb_oe),
        .typ                     (hid_typ),
        .full_report             (hid_report_pulse),
        .connerr                 (hid_connerr),
        .busy                    (),
        .key_modifiers           (),
        .key_0                   (),
        .key_1                   (),
        .key_2                   (),
        .key_3                   (),
        .key_4                   (),
        .key_5                   (),
        .mouse_btn               (mouse_btn),
        .mouse_dx                (mouse_dx),
        .mouse_dy                (mouse_dy),
        .game_l                  (),
        .game_r                  (),
        .game_u                  (),
        .game_d                  (),
        .game_a                  (),
        .game_b                  (),
        .game_x                  (),
        .game_y                  (),
        .game_sel                (),
        .game_sta                (),
        .game_extra              (),
        .dbg_hid_report          (hid_report_data),
        .dbg_hid_regs            (hid_regs),
        .dev_connected           (u_dev_conn),
        .rom_addr                (rom_addr),
        .rom_dout                (rom_dout),
        .rom_en                  (rom_en)
    );

    usb_hid_host_rom u_usb_rom (
        .clk                     (clk_usb),
        .addr                    (rom_addr),
        .dout                    (rom_dout),
        .en                      (rom_en)
    );

    assign usb_connected = u_dev_conn | (hid_typ != 2'd0);
    assign usb_dev_type  = (hid_typ != 2'd0) ? hid_typ : (u_dev_conn ? 2'd3 : 2'd0);
    assign usb_conn_err  = hid_connerr;

    // --------------------------------------------------------------------------
    // 3. Multi-Format Touchscreen Report Decoder (60MHz USB Domain)
    // --------------------------------------------------------------------------
    wire [7:0] b0 = hid_report_data[7:0];
    wire [7:0] b1 = hid_report_data[15:8];
    wire [7:0] b2 = hid_report_data[23:16];
    wire [7:0] b3 = hid_report_data[31:24];
    wire [7:0] b4 = hid_report_data[39:32];
    wire [7:0] b5 = hid_report_data[47:40];
    wire [7:0] b6 = hid_report_data[55:48];
    wire [7:0] b7 = hid_report_data[63:56];

    // Mouse mode cursor accumulator (fallback if screen enumerates as HID mouse)
    reg signed [15:0] mouse_pos_x = 16'sd640;
    reg signed [15:0] mouse_pos_y = 16'sd360;

    always @(posedge clk_usb or negedge rst_usb_n) begin
        if (!rst_usb_n) begin
            mouse_pos_x <= 16'sd640;
            mouse_pos_y <= 16'sd360;
        end else if (hid_report_pulse && hid_typ == 2'd2) begin
            if (mouse_pos_x + mouse_dx < 16'sd0)
                mouse_pos_x <= 16'sd0;
            else if (mouse_pos_x + mouse_dx > 16'sd1279)
                mouse_pos_x <= 16'sd1279;
            else
                mouse_pos_x <= mouse_pos_x + mouse_dx;

            if (mouse_pos_y + mouse_dy < 16'sd0)
                mouse_pos_y <= 16'sd0;
            else if (mouse_pos_y + mouse_dy > 16'sd719)
                mouse_pos_y <= 16'sd719;
            else
                mouse_pos_y <= mouse_pos_y + mouse_dy;
        end
    end

    // Sticky Report Format Tracking (prevents release misclassification bug)
    reg format_is_report_id;
    always @(posedge clk_usb or negedge rst_usb_n) begin
        if (!rst_usb_n) begin
            format_is_report_id <= 1'b1; // Default to standard Windows/ILITEK Digitizer Report ID format
        end else if (hid_report_pulse) begin
            if (b0 >= 8'h01 && b0 <= 8'h08) begin
                // Report ID is explicitly present in Byte 0
                format_is_report_id <= 1'b1;
            end else if (b0 == 8'h00) begin
                // Byte 0 is 0x00, indicating direct unformatted touch report
                format_is_report_id <= 1'b0;
            end
        end
    end

    // Tip switch: b1[0] when Report ID is present, b0[0] for direct reports
    wire raw_down = (hid_typ == 2'd2)   ? mouse_btn[0] :
                    format_is_report_id ? b1[0] :
                    b0[0];

    // Little-endian 16-bit coordinate decoding:
    // With Report ID: Byte 0=ID, Byte 1=Status, Byte 2=ContactID, Bytes 3..4=X, Bytes 5..6=Y
    // Direct report:  Byte 0=Status, Byte 1=ContactID, Bytes 2..3=X, Bytes 4..5=Y
    wire [15:0] raw_x = (hid_typ == 2'd2)   ? mouse_pos_x :
                        format_is_report_id ? {b4, b3} :
                        {b3, b2};

    wire [15:0] raw_y = (hid_typ == 2'd2)   ? mouse_pos_y :
                        format_is_report_id ? {b6, b5} :
                        {b5, b4};

    // --------------------------------------------------------------------------
    // 4. Safe Clock Domain Crossing (60MHz USB -> 62.5MHz Pixel Domain)
    // --------------------------------------------------------------------------
    reg [15:0] hold_x;
    reg [15:0] hold_y;
    reg        hold_down;
    reg        usb_toggle;

    always @(posedge clk_usb or negedge rst_usb_n) begin
        if (!rst_usb_n) begin
            hold_x     <= 16'd0;
            hold_y     <= 16'd0;
            hold_down  <= 1'b0;
            usb_toggle <= 1'b0;
        end else if (hid_report_pulse) begin
            hold_x     <= raw_x;
            hold_y     <= raw_y;
            hold_down  <= raw_down;
            usb_toggle <= ~usb_toggle;
        end
    end

    // Pixel clock domain synchronization
    reg [2:0]  toggle_sync;
    reg [23:0] wdt_count;

    wire packet_strobe = (toggle_sync[2] ^ toggle_sync[1]);

    always @(posedge clk_pixel or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            toggle_sync    <= 3'd0;
            touch_valid    <= 1'b0;
            touch_x        <= 16'd0;
            touch_y        <= 16'd0;
            touch_state    <= 1'b0;
            wdt_count      <= 24'd0;
            touch_activity <= 1'b0;
            dbg_pkt_cnt    <= 8'd0;
        end else begin
            toggle_sync <= {toggle_sync[1:0], usb_toggle};
            touch_valid <= 1'b0;

            if (packet_strobe) begin
                touch_valid    <= 1'b1;
                touch_x        <= hold_x;
                touch_y        <= hold_y;
                touch_state    <= hold_down;
                wdt_count      <= 24'd0;
                touch_activity <= ~touch_activity;
                dbg_pkt_cnt    <= dbg_pkt_cnt + 8'd1;
            end else begin
                // Auto-release contact if no new packet received for 50ms (3,125,000 cycles at 62.5MHz)
                if (wdt_count < 24'd2_500_000) begin
                    wdt_count <= wdt_count + 24'd1;
                end else begin
                    touch_state <= 1'b0;
                end
            end
        end
    end

    assign dbg_report = hid_report_data;
    assign dbg_regs   = hid_regs;

endmodule
