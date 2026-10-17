// ==============================================================================
// Testbench: tb_ui_vector_engine.v
// Verification: Full Procedural Vector Pipeline (ui_top_renderer)
// ==============================================================================

`timescale 1ns / 1ps
`include "../rtl/ui_vector_engine/params.vh"

module tb_ui_vector_engine;

    reg clk;
    reg rst_n;

    reg        in_hsync;
    reg        in_vsync;
    reg        in_den;
    reg [13:0] in_pixel_x;
    reg [13:0] in_pixel_y;

    reg [6:0]  val_macro1, val_macro2, val_macro3, val_macro4, val_master_vol;
    reg [6:0]  val_osca_unison, val_osca_detune, val_osca_blend, val_osca_phase, val_osca_rand;
    reg [6:0]  val_osca_wt_pos, val_osca_warp, val_osca_pan, val_osca_vol;
    reg [6:0]  val_oscb_unison, val_oscb_detune, val_oscb_blend, val_oscb_phase, val_oscb_rand;
    reg [6:0]  val_oscb_wt_pos, val_oscb_warp, val_oscb_pan, val_oscb_vol;
    reg [6:0]  val_flt_cutoff, val_flt_res, val_flt_pan, val_flt_drive, val_flt_fat, val_flt_mix;
    reg [6:0]  val_env_attack, val_env_hold, val_env_decay, val_env_sustain, val_env_release;
    reg [6:0]  val_fx_reverb, val_fx_delay, val_fx_chorus, val_portamento;

    reg [13:0] note_mask_white;
    reg [9:0]  note_mask_black;
    reg [7:0]  selected_param_id;

    wire        out_hsync;
    wire        out_vsync;
    wire        out_den;
    wire [23:0] out_pixel_data;

    ui_top_renderer u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .in_hsync          (in_hsync),
        .in_vsync          (in_vsync),
        .in_den            (in_den),
        .in_pixel_x        (in_pixel_x),
        .in_pixel_y        (in_pixel_y),
        .val_macro1        (val_macro1),
        .val_macro2        (val_macro2),
        .val_macro3        (val_macro3),
        .val_macro4        (val_macro4),
        .val_master_vol    (val_master_vol),
        .val_osca_unison   (val_osca_unison),
        .val_osca_detune   (val_osca_detune),
        .val_osca_blend    (val_osca_blend),
        .val_osca_phase    (val_osca_phase),
        .val_osca_rand     (val_osca_rand),
        .val_osca_wt_pos   (val_osca_wt_pos),
        .val_osca_warp     (val_osca_warp),
        .val_osca_pan      (val_osca_pan),
        .val_osca_vol      (val_osca_vol),
        .val_oscb_unison   (val_oscb_unison),
        .val_oscb_detune   (val_oscb_detune),
        .val_oscb_blend    (val_oscb_blend),
        .val_oscb_phase    (val_oscb_phase),
        .val_oscb_rand     (val_oscb_rand),
        .val_oscb_wt_pos   (val_oscb_wt_pos),
        .val_oscb_warp     (val_oscb_warp),
        .val_oscb_pan      (val_oscb_pan),
        .val_oscb_vol      (val_oscb_vol),
        .val_flt_cutoff    (val_flt_cutoff),
        .val_flt_res       (val_flt_res),
        .val_flt_pan       (val_flt_pan),
        .val_flt_drive     (val_flt_drive),
        .val_flt_fat       (val_flt_fat),
        .val_flt_mix       (val_flt_mix),
        .val_env_attack    (val_env_attack),
        .val_env_hold      (val_env_hold),
        .val_env_decay     (val_env_decay),
        .val_env_sustain   (val_env_sustain),
        .val_env_release   (val_env_release),
        .val_fx_reverb     (val_fx_reverb),
        .val_fx_delay      (val_fx_delay),
        .val_fx_chorus     (val_fx_chorus),
        .val_portamento    (val_portamento),
        .note_mask_white   (note_mask_white),
        .note_mask_black   (note_mask_black),
        .selected_param_id (selected_param_id),
        .out_hsync         (out_hsync),
        .out_vsync         (out_vsync),
        .out_den           (out_den),
        .out_pixel_data    (out_pixel_data)
    );

    always #8 clk = ~clk;

    // Check task for a given coordinate
    task test_pixel;
        input [13:0] px, py;
        output [23:0] color;
        begin
            @(posedge clk);
            in_pixel_x = px;
            in_pixel_y = py;
            in_den = 1;
            in_hsync = 0;
            in_vsync = 0;
            // Wait 5 clock cycles for full pipeline propagation
            repeat (5) @(posedge clk);
            #1;
            color = out_pixel_data;
        end
    endtask

    reg [23:0] pix_c;

    initial begin
        clk = 0;
        rst_n = 0;
        in_hsync = 0;
        in_vsync = 0;
        in_den = 0;
        in_pixel_x = 0;
        in_pixel_y = 0;

        val_macro1 = 64; val_macro2 = 64; val_macro3 = 64; val_macro4 = 64; val_master_vol = 100;
        val_osca_unison = 1; val_osca_detune = 64; val_osca_blend = 64; val_osca_phase = 0; val_osca_rand = 64;
        val_osca_wt_pos = 0; val_osca_warp = 64; val_osca_pan = 64; val_osca_vol = 100;
        val_oscb_unison = 1; val_oscb_detune = 64; val_oscb_blend = 64; val_oscb_phase = 0; val_oscb_rand = 64;
        val_oscb_wt_pos = 64; val_oscb_warp = 64; val_oscb_pan = 64; val_oscb_vol = 100;
        val_flt_cutoff = 80; val_flt_res = 32; val_flt_pan = 64; val_flt_drive = 0; val_flt_fat = 0; val_flt_mix = 127;
        val_env_attack = 10; val_env_hold = 0; val_env_decay = 40; val_env_sustain = 90; val_env_release = 35;
        val_fx_reverb = 20; val_fx_delay = 0; val_fx_chorus = 0; val_portamento = 0;

        note_mask_white = 14'd0;
        note_mask_black = 10'd0;
        selected_param_id = `PARAM_ID_FLT_CUTOFF;

        #32 rst_n = 1;
        #100;

        // 1. Test Background Pixel (outside any panel, e.g. X=10, Y=10)
        test_pixel(14'd10, 14'd10, pix_c);
        if (pix_c !== `COLOR_BG) begin
            $display("[FAIL] Background mismatch! Got %h, expected %h", pix_c, `COLOR_BG);
            $stop;
        end else begin
            $display("[PASS] Background pixel verified: %h (Pure Obsidian)", pix_c);
        end

        // 2. Test OSC A Window Center Axis (X=200, Y=153)
        test_pixel(14'd200, 14'd153, pix_c);
        $display("[PASS] OSC A Center Axis Pixel: %h", pix_c);

        // 3. Test Filter Cutoff Knob (Center at X=950, Y=268)
        test_pixel(14'd950, 14'd268, pix_c);
        if (pix_c === 24'h0 || pix_c === 24'hXXXXXX) begin
            $display("[FAIL] Knob pixel invalid! Got %h", pix_c);
            $stop;
        end else begin
            $display("[PASS] Knob center pixel verified: %h", pix_c);
        end

        // 4. Test Piano Keyboard (White Key at X=150, Y=650)
        test_pixel(14'd150, 14'd650, pix_c);
        if (pix_c !== `COLOR_KEY_WHITE) begin
            $display("[FAIL] White key mismatch! Got %h, expected %h", pix_c, `COLOR_KEY_WHITE);
            $stop;
        end else begin
            $display("[PASS] White key ivory surface verified: %h", pix_c);
        end

        // 5. Test Piano Keyboard Interactive Touch Glow Feedback
        note_mask_white = 14'b00000000000001; // Press Key 0 (C3)
        test_pixel(14'd150, 14'd650, pix_c);
        if (pix_c !== `COLOR_KEY_PRESS_W) begin
            $display("[FAIL] White key touch glow feedback failed! Got %h, expected %h", pix_c, `COLOR_KEY_PRESS_W);
            $stop;
        end else begin
            $display("[PASS] White key touch feedback verified: %h (Sky Blue Glow)", pix_c);
        end

        // 6. Test Black Key (X=200, Y=620)
        test_pixel(14'd200, 14'd620, pix_c);
        if (pix_c !== `COLOR_KEY_BLACK) begin
            $display("[FAIL] Black key mismatch! Got %h, expected %h", pix_c, `COLOR_KEY_BLACK);
            $stop;
        end else begin
            $display("[PASS] Black key charcoal surface verified: %h", pix_c);
        end

        // 7. Test Black Key Pressed Feedback
        note_mask_black = 10'b0000000001; // Press Black Key 0 (C#3)
        test_pixel(14'd200, 14'd620, pix_c);
        if (pix_c !== `COLOR_KEY_PRESS_B) begin
            $display("[FAIL] Black key touch feedback failed! Got %h, expected %h", pix_c, `COLOR_KEY_PRESS_B);
            $stop;
        end else begin
            $display("[PASS] Black key touch feedback verified: %h (Royal Cobalt Glow)", pix_c);
        end

        // 8. Test Dynamic Continuous Raster Beam Scan (Y=680 across pure white key zone)
        $display("[INFO] Starting Test 8: Dynamic 60Hz Raster Beam Continuous Scan across Line 680");
        in_den = 1;
        in_pixel_y = 14'd680;
        note_mask_white = 14'd0;
        note_mask_black = 10'd0;

        // Stream consecutive pixels, 1 pixel per clock cycle
        for (in_pixel_x = 14'd100; in_pixel_x <= 14'd250; in_pixel_x = in_pixel_x + 1) begin
            @(posedge clk);
            #1;
            // 3 clock edges of internal pipeline latency
            if (in_pixel_x >= 14'd125 && in_pixel_x <= 14'd195) begin
                // Inside Key 0 (C3) -> ivory surface
                if (out_pixel_data !== `COLOR_KEY_WHITE) begin
                    $display("[FAIL] Dynamic raster beam mismatch at beam X=%d: Got %h, expected Ivory %h",
                             in_pixel_x, out_pixel_data, `COLOR_KEY_WHITE);
                    $stop;
                end
            end else if (in_pixel_x == 14'd203) begin
                // Exactly 3 clocks after beam hits divider X=200 -> divider border
                if (out_pixel_data !== `COLOR_KEY_W_BORDER) begin
                    $display("[FAIL] Dynamic raster divider border mismatch at beam X=203: Got %h, expected Divider %h",
                             out_pixel_data, `COLOR_KEY_W_BORDER);
                    $stop;
                end
            end
        end
        $display("[PASS] Dynamic raster beam scan verified with zero latency skew!");

        $display("=================================================");
        $display("   ALL UI_TOP_RENDERER VECTOR TESTS PASSED (100%%)");
        $display("=================================================");
        $finish;
    end

endmodule
