// ==============================================================================
// Testbench: tb_touch_event_router.v
// Verification: Tests standard 32K/64K coordinate normalization, dynamic button detection,
//               immediate tactile response, stepper hold-to-repeat, envelope tabs,
//               matrix slots, and continuous rotary knob drag accumulation.
// ==============================================================================

`timescale 1ns / 1ps
`include "../rtl/ui_vector_engine/params.vh"

module tb_touch_event_router;

    reg clk;
    reg rst_n;
    reg touch_valid;
    reg [15:0] raw_touch_x;
    reg [15:0] raw_touch_y;
    reg touch_state;

    wire [7:0]  selected_param_id;
    wire        selected_valid;
    wire        param_delta_valid;
    wire signed [7:0] param_delta_val;
    wire        btn_tap_valid;
    wire [7:0]  btn_tap_id;
    wire [1:0]  btn_tap_action;
    wire [13:0] norm_touch_x;
    wire [13:0] norm_touch_y;
    wire        touch_active_contact;
    wire [2:0]  touch_range_mode;

    touch_event_router u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .touch_valid          (touch_valid),
        .raw_touch_x          (raw_touch_x),
        .raw_touch_y          (raw_touch_y),
        .touch_state          (touch_state),
        .selected_param_id    (selected_param_id),
        .selected_valid       (selected_valid),
        .norm_touch_x         (norm_touch_x),
        .norm_touch_y         (norm_touch_y),
        .touch_active_contact (touch_active_contact),
        .param_delta_valid    (param_delta_valid),
        .param_delta_val      (param_delta_val),
        .btn_tap_valid        (btn_tap_valid),
        .btn_tap_id           (btn_tap_id),
        .btn_tap_action       (btn_tap_action),
        .touch_key_white_mask (),
        .touch_key_black_mask (),
        .touch_note_on        (),
        .touch_note_off       (),
        .touch_note_number    (),
        .touch_range_mode     (touch_range_mode)
    );

    always #8 clk = ~clk; // 62.5MHz clock

    reg saw_btn_tap;
    reg [7:0] latched_btn_id;
    reg [1:0] latched_btn_action;
    reg saw_delta;
    reg signed [7:0] latched_delta_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_btn_tap        <= 0;
            latched_btn_id     <= 0;
            latched_btn_action <= 0;
            saw_delta          <= 0;
            latched_delta_val  <= 0;
        end else begin
            if (btn_tap_valid) begin
                saw_btn_tap        <= 1;
                latched_btn_id     <= btn_tap_id;
                latched_btn_action <= btn_tap_action;
            end
            if (param_delta_valid) begin
                saw_delta         <= 1;
                latched_delta_val <= param_delta_val;
            end
        end
    end

    task send_touch;
        input [15:0] x, y;
        input state;
        begin
            @(posedge clk);
            touch_valid = 1;
            raw_touch_x = x;
            raw_touch_y = y;
            touch_state = state;
            @(posedge clk);
            touch_valid = 0;
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        touch_valid = 0;
        raw_touch_x = 0;
        raw_touch_y = 0;
        touch_state = 0;

        #32 rst_n = 1;
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 1: 16K Mode Default & OSC A Power Button Tap (ILITEK format)
        // Digitizer reports 14-bit coordinates (0..16384 X, 0..9600 Y).
        // OSC A Power is at canvas (44, 60).
        // 16K touch: X=564 -> 44, Y=801 -> 60.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 1: 16K Mode Default & OSC A Power button tap");
        if (touch_range_mode !== 3'd0) begin
            $display("[FAIL] Default touch_range_mode is %d, expected 0 (16K)!", touch_range_mode);
            $stop;
        end
        saw_btn_tap = 0;
        send_touch(16'd564, 16'd801, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_OSCA_POWER) begin
            $display("[FAIL] 16K OSC A Power button tap failed! saw=%b id=%h (expected %h)",
                     saw_btn_tap, latched_btn_id, `PARAM_ID_OSCA_POWER);
            $stop;
        end
        $display("[PASS] 16K OSC A Power button tap verified (mode=%d, id=%h, act=%d)",
                 touch_range_mode, latched_btn_id, latched_btn_action);
        send_touch(16'd564, 16'd801, 1'b0); // Release
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 2: 16K Mode ILITEK Live Telemetry Normalization
        // Using camera HUD live snapshot: X=0x23CB (9163), Y=0x214D (8525).
        // In 16K mode: 9163 * 5120 >> 16 = 715, 8525 * 4915 >> 16 = 639.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 2: 16K ILITEK live packet normalization");
        send_touch(16'd9163, 16'd8525, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd715 || norm_touch_y !== 14'd639) begin
            $display("[FAIL] 16K live packet normalization failed! norm=(%d, %d), expected (715, 639)",
                     norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 16K live packet normalization verified: norm=(%d, %d)", norm_touch_x, norm_touch_y);
        send_touch(16'd9163, 16'd8525, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 3: 16K Boundary Clamping & Normalization Verification
        // (0, 0) -> norm=(0, 0)
        // (16384, 9600) -> norm=(1279, 719)
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 3: 16K Boundary Clamping");
        send_touch(16'd0, 16'd0, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd0 || norm_touch_y !== 14'd0) begin
            $display("[FAIL] 16K origin normalization failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        send_touch(16'd16384, 16'd9600, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd1279 || norm_touch_y !== 14'd719) begin
            $display("[FAIL] 16K max normalization failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 16K Boundary Clamping verified: min=(0,0), max=(1279,719)");
        send_touch(16'd16384, 16'd9600, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 3b: 16K Edge Overshoot Immunity (ILITEK Margin Verification)
        // Slight coordinate overshoot near bezel (X=16450, Y=9700) must stay in 16K mode!
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 3b: 16K Edge Overshoot Immunity");
        send_touch(16'd16450, 16'd9700, 1'b1);
        repeat (2) @(posedge clk);
        if (touch_range_mode !== 3'd0) begin
            $display("[FAIL] Accidental 32K promotion on 16K edge overshoot! mode=%d (expected 0)", touch_range_mode);
            $stop;
        end
        if (norm_touch_x !== 14'd1279 || norm_touch_y !== 14'd719) begin
            $display("[FAIL] 16K edge clamp failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 16K Edge Overshoot Immunity verified: mode=0, clamped to (1279, 719)");
        send_touch(16'd16450, 16'd9700, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 4: Dynamic Promotion to 32K Mode & Filter Checkbox [A] Tap
        // Coordinate > 20000 promotes to 32K mode.
        // Filter Route [A] is at canvas (880, 250).
        // 32K touch: X=22528 -> 880, Y=11378 -> 250.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 4: Dynamic Promotion to 32K Mode & Filter Checkbox [A]");
        saw_btn_tap = 0;
        send_touch(16'd22528, 16'd11378, 1'b1);
        if (touch_range_mode !== 3'd1) begin
            $display("[FAIL] Expected touch_range_mode 1 (32K), got %d!", touch_range_mode);
            $stop;
        end
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_FLT_ROUTE_A) begin
            $display("[FAIL] Filter Checkbox A failed! saw=%b id=%h", saw_btn_tap, latched_btn_id);
            $stop;
        end
        $display("[PASS] Dynamic promotion to 32K and Filter Checkbox A verified (mode=%d, id=%h)",
                 touch_range_mode, latched_btn_id);
        send_touch(16'd22528, 16'd11378, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 5: OSC A Waveform Next Button Tap in 32K Mode
        // Mode remains latched in 32K even for small coordinates (<16384).
        // OSC A Waveform Next is at canvas (405, 60).
        // 32K touch: X=10368 -> 405, Y=2731 -> 60.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 5: OSC A Waveform Next button in 32K mode");
        saw_btn_tap = 0;
        send_touch(16'd10368, 16'd2731, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_OSCA_WAVE || latched_btn_action !== 2'd1) begin
            $display("[FAIL] OSC A Waveform Next failed! saw=%b id=%h act=%d",
                     saw_btn_tap, latched_btn_id, latched_btn_action);
            $stop;
        end
        $display("[PASS] OSC A Waveform Next in 32K mode verified (id=%h, act=%d)", latched_btn_id, latched_btn_action);
        send_touch(16'd10368, 16'd2731, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 6: Envelope Tab 2 Tap (ENV 2)
        // Envelope Tab 2 is at canvas (168, 384).
        // 32K touch: X=4301 -> 168, Y=17477 -> 384.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 6: Envelope Tab 2");
        saw_btn_tap = 0;
        send_touch(16'd4301, 16'd17477, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_ENV_TAB || latched_btn_action !== 2'd1) begin
            $display("[FAIL] Envelope Tab 2 failed! saw=%b id=%h act=%d", saw_btn_tap, latched_btn_id, latched_btn_action);
            $stop;
        end
        $display("[PASS] Envelope Tab 2 verified (id=%h, act=%d)", latched_btn_id, latched_btn_action);
        send_touch(16'd4301, 16'd17477, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 7: Modulation Matrix Slot 1 Bypass LED Button
        // Slot 1 Bypass is at canvas (816, 420).
        // 32K touch: X=20890 -> 816, Y=19115 -> 420.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 7: Matrix Slot 1 Bypass");
        saw_btn_tap = 0;
        send_touch(16'd20890, 16'd19115, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_SLOT1_BYPASS) begin
            $display("[FAIL] Slot 1 Bypass failed! saw=%b id=%h", saw_btn_tap, latched_btn_id);
            $stop;
        end
        $display("[PASS] Matrix Slot 1 Bypass verified (id=%h)", latched_btn_id);
        send_touch(16'd20890, 16'd19115, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 8: Filter Cutoff Knob Drag & Delta Accumulator
        // Filter Cutoff Knob is at canvas (950, 268).
        // 32K touch down: X=24320 -> 950, Y=12197 -> 268.
        // Drag up to Y=264: Y=12015 -> 264 (disp=4px >= deadband, engages drag).
        // Continuous drag up to Y=260: Y=11833 -> 260 (delta Y is +4px >= 2, produces delta).
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 8: Filter Cutoff Knob drag");
        send_touch(16'd24320, 16'd12197, 1'b1);
        if (selected_param_id !== `PARAM_ID_FLT_CUTOFF) begin
            $display("[FAIL] Knob Cutoff select failed! id=%h", selected_param_id);
            $stop;
        end
        $display("[PASS] Knob Cutoff selected confirmed: id=%h", selected_param_id);

        saw_delta = 0;
        send_touch(16'd24320, 16'd12015, 1'b1); // Movement 1: Exceeds deadband, engages drag
        send_touch(16'd24320, 16'd11833, 1'b1); // Movement 2: Continuous drag produces delta
        if (!saw_delta) begin
            $display("[FAIL] Drag did not produce parameter delta!");
            $stop;
        end
        $display("[PASS] Knob drag delta produced: val=%d", latched_delta_val);
        send_touch(16'd24320, 16'd11833, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 9: Envelope Tab 1 Tap (ENV 1: act=0)
        // Canvas center: X=78, Y=384. 32K: X=1996, Y=17477.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 9: Envelope Tab 1");
        saw_btn_tap = 0;
        send_touch(16'd1996, 16'd17477, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_ENV_TAB || latched_btn_action !== 2'd0) begin
            $display("[FAIL] Envelope Tab 1 failed! saw=%b id=%h act=%d", saw_btn_tap, latched_btn_id, latched_btn_action);
            $stop;
        end
        $display("[PASS] Envelope Tab 1 verified (id=%h, act=%d)", latched_btn_id, latched_btn_action);
        send_touch(16'd1996, 16'd17477, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 10: Envelope Tab 3 Tap (ENV 3: act=2)
        // Canvas center: X=258, Y=384. 32K: X=6604, Y=17477.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 10: Envelope Tab 3");
        saw_btn_tap = 0;
        send_touch(16'd6604, 16'd17477, 1'b1);
        if (!saw_btn_tap || latched_btn_id !== `PARAM_ID_ENV_TAB || latched_btn_action !== 2'd2) begin
            $display("[FAIL] Envelope Tab 3 failed! saw=%b id=%h act=%d", saw_btn_tap, latched_btn_id, latched_btn_action);
            $stop;
        end
        $display("[PASS] Envelope Tab 3 verified (id=%h, act=%d)", latched_btn_id, latched_btn_action);
        send_touch(16'd6604, 16'd17477, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 11: Seamless Sliding Across Envelope Tabs Without Releasing Finger
        // Finger down at ENV 1 -> drag right to ENV 2 -> drag right to ENV 3
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 11: Sliding across Envelope Tabs");
        saw_btn_tap = 0;
        send_touch(16'd1996, 16'd17477, 1'b1); // Land on Tab 1
        if (!saw_btn_tap || latched_btn_action !== 2'd0) begin
            $display("[FAIL] Slide start Tab 1 failed!"); $stop;
        end
        saw_btn_tap = 0;
        send_touch(16'd4301, 16'd17477, 1'b1); // Slide to Tab 2 without lifting finger
        if (!saw_btn_tap || latched_btn_action !== 2'd1) begin
            $display("[FAIL] Slide to Tab 2 failed! saw=%b act=%d", saw_btn_tap, latched_btn_action); $stop;
        end
        saw_btn_tap = 0;
        send_touch(16'd6604, 16'd17477, 1'b1); // Slide to Tab 3 without lifting finger
        if (!saw_btn_tap || latched_btn_action !== 2'd2) begin
            $display("[FAIL] Slide to Tab 3 failed! saw=%b act=%d", saw_btn_tap, latched_btn_action); $stop;
        end
        $display("[PASS] Seamless slide across Tab 1 -> Tab 2 -> Tab 3 verified!");
        send_touch(16'd6604, 16'd17477, 1'b0); // Lift finger
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 12: 32K Boundary Clamping & Normalization Verification
        // (0, 0) -> norm=(0, 0)
        // (32767, 32767) -> norm=(1279, 719)
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 12: 32K Boundary Clamping");
        send_touch(16'd0, 16'd0, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd0 || norm_touch_y !== 14'd0) begin
            $display("[FAIL] 32K origin normalization failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        send_touch(16'd32767, 16'd32767, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd1279 || norm_touch_y !== 14'd719) begin
            $display("[FAIL] 32K max normalization failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 32K Boundary Clamping verified: min=(0,0), max=(1279,719)");
        send_touch(16'd32767, 16'd32767, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 13: 64K Mode Triggering & Normalization Verification
        // Coordinate with bit 15 set: X=32768 (16'h8000), Y=32768 (16'h8000).
        // In 64K mode: X * 1280 >> 16 = 640, Y * 720 >> 16 = 360.
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 13: 64K Mode Detection");
        send_touch(16'h8000, 16'h8000, 1'b1);
        repeat (2) @(posedge clk);
        if (touch_range_mode !== 3'd2) begin
            $display("[FAIL] touch_range_mode is %d, expected 2 (64K)!", touch_range_mode);
            $stop;
        end
        if (norm_touch_x !== 14'd640 || norm_touch_y !== 14'd360) begin
            $display("[FAIL] 64K normalization failed! got (%d, %d), expected (640, 360)",
                     norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 64K Mode verified: mode=%d, norm=(%d, %d)", touch_range_mode, norm_touch_x, norm_touch_y);
        send_touch(16'h8000, 16'h8000, 1'b0);
        repeat (5) @(posedge clk);

        // ----------------------------------------------------------------------
        // Test 14: 64K Boundary Clamping & Normalization Verification
        // (65535, 65535) -> norm=(1279, 719)
        // ----------------------------------------------------------------------
        $display("[INFO] Starting Test 14: 64K Boundary Clamping");
        send_touch(16'hFFFF, 16'hFFFF, 1'b1);
        repeat (2) @(posedge clk);
        if (norm_touch_x !== 14'd1279 || norm_touch_y !== 14'd719) begin
            $display("[FAIL] 64K max normalization failed! norm=(%d, %d)", norm_touch_x, norm_touch_y);
            $stop;
        end
        $display("[PASS] 64K Boundary Clamping verified: max=(1279,719)");
        send_touch(16'hFFFF, 16'hFFFF, 1'b0);
        repeat (5) @(posedge clk);

        $display("=================================================");
        $display("   ALL TOUCH_EVENT_ROUTER TESTS PASSED (100%%)   ");
        $display("=================================================");
        $finish;
    end

endmodule
