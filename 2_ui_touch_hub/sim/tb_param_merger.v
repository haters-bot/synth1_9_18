// ==============================================================================
// Testbench: tb_param_merger.v
// Verification: Parameter Merger & Master Register Bank
// ==============================================================================

`timescale 1ns / 1ps
`include "../rtl/ui_vector_engine/params.vh"

module tb_param_merger;

    reg clk;
    reg rst_n;

    // Touch inputs
    reg        touch_delta_valid;
    reg [7:0]  touch_selected_id;
    reg signed [7:0] touch_delta_val;

    // Touch button inputs
    reg        btn_tap_valid;
    reg [7:0]  btn_tap_id;
    reg [1:0]  btn_tap_action;

    // SPI inputs
    reg        spi_param_valid;
    reg [7:0]  spi_param_id;
    reg [6:0]  spi_param_val;

    // Outputs - Knobs
    wire [6:0] val_macro1, val_macro2, val_macro3, val_macro4, val_master_vol;
    wire [6:0] val_osca_unison, val_osca_detune, val_osca_blend, val_osca_phase, val_osca_rand;
    wire [6:0] val_osca_wt_pos, val_osca_warp, val_osca_pan, val_osca_vol;
    wire [6:0] val_oscb_unison, val_oscb_detune, val_oscb_blend, val_oscb_phase, val_oscb_rand;
    wire [6:0] val_oscb_wt_pos, val_oscb_warp, val_oscb_pan, val_oscb_vol;
    wire [6:0] val_flt_cutoff, val_flt_res, val_flt_pan, val_flt_drive, val_flt_fat, val_flt_mix;
    wire [6:0] val_env_attack, val_env_hold, val_env_decay, val_env_sustain, val_env_release;
    wire [6:0] val_fx_reverb, val_fx_delay, val_fx_chorus, val_portamento;

    // Outputs - Buttons & States
    wire        val_osca_power, val_oscb_power, val_flt_power;
    wire [1:0]  val_osca_wave, val_oscb_wave;
    wire [3:0]  val_osca_oct, val_oscb_oct;
    wire [4:0]  val_osca_semi, val_oscb_semi;
    wire [6:0]  val_osca_fine, val_oscb_fine;
    wire [1:0]  val_flt_type;
    wire        val_flt_route_a, val_flt_route_b, val_flt_route_n, val_flt_route_s, val_flt_keytrack;
    wire [1:0]  val_env_tab;
    wire [3:0]  val_slot_bypass;
    wire [7:0]  active_btn_id;
    wire        btn_flash_active;

    wire        midi_cc_req;
    wire [7:0]  midi_cc_param_id;
    wire [6:0]  midi_cc_val;

    param_merger u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .touch_delta_valid (touch_delta_valid),
        .touch_selected_id (touch_selected_id),
        .touch_delta_val   (touch_delta_val),
        .btn_tap_valid     (btn_tap_valid),
        .btn_tap_id        (btn_tap_id),
        .btn_tap_action    (btn_tap_action),
        .spi_param_valid   (spi_param_valid),
        .spi_param_id      (spi_param_id),
        .spi_param_val     (spi_param_val),
        .curve_update_valid(1'b0), .curve_update_filter(1'b0),
        .curve_update_tab(2'd0), .curve_update_mask(5'd0),
        .curve_update_values(35'd0), .midi_tx_busy(1'b0),
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
        .val_osca_power    (val_osca_power),
        .val_oscb_power    (val_oscb_power),
        .val_flt_power     (val_flt_power),
        .val_osca_wave     (val_osca_wave),
        .val_oscb_wave     (val_oscb_wave),
        .val_osca_oct      (val_osca_oct),
        .val_osca_semi     (val_osca_semi),
        .val_osca_fine     (val_osca_fine),
        .val_oscb_oct      (val_oscb_oct),
        .val_oscb_semi     (val_oscb_semi),
        .val_oscb_fine     (val_oscb_fine),
        .val_flt_type      (val_flt_type),
        .val_flt_route_a   (val_flt_route_a),
        .val_flt_route_b   (val_flt_route_b),
        .val_flt_route_n   (val_flt_route_n),
        .val_flt_route_s   (val_flt_route_s),
        .val_flt_keytrack  (val_flt_keytrack),
        .val_env_tab       (val_env_tab),
        .val_slot_bypass   (val_slot_bypass),
        .active_btn_id     (active_btn_id),
        .btn_flash_active  (btn_flash_active),
        .midi_cc_req       (midi_cc_req),
        .midi_cc_param_id  (midi_cc_param_id),
        .midi_cc_val       (midi_cc_val)
    );

    // 50 MHz physical parameter clock. Drive/check on the inactive edge.
    always #10 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        touch_delta_valid = 0;
        touch_selected_id = 0;
        touch_delta_val = 0;
        btn_tap_valid = 0;
        btn_tap_id = 0;
        btn_tap_action = 0;
        spi_param_valid = 0;
        spi_param_id = 0;
        spi_param_val = 0;

        #32 rst_n = 1;
        #16;

        // 1. Check Default Reset Values
        if (val_flt_cutoff !== 7'd80 || val_osca_wt_pos !== 7'd0 || val_master_vol !== 7'd100) begin
            $display("[FAIL] Default parameter mismatch! Cutoff=%d, WTPos=%d", val_flt_cutoff, val_osca_wt_pos);
            $stop;
        end else begin
            $display("[PASS] Default parameters verified: Cutoff=80, WTPos=0, MasterVol=100");
        end

        // 2. Test Physical Knob SPI Update from Teammate 1
        @(negedge clk);
        spi_param_valid = 1;
        spi_param_id    = `PARAM_ID_FLT_CUTOFF;
        spi_param_val   = 7'd112;
        @(negedge clk);
        spi_param_valid = 0;
        @(negedge clk);

        if (val_flt_cutoff !== 7'd112 || !midi_cc_req || midi_cc_val !== 7'd112) begin
            $display("[FAIL] SPI Cutoff update failed! Got %d, CC_req=%b", val_flt_cutoff, midi_cc_req);
            $stop;
        end else begin
            $display("[PASS] SPI Cutoff successfully updated to 112 with MIDI CC req");
        end

        // 3. Test Touch Delta Step Update
        @(negedge clk);
        touch_delta_valid = 1;
        touch_selected_id = `PARAM_ID_OSCA_WT_POS;
        touch_delta_val   = 8'sd15;
        @(negedge clk);
        touch_delta_valid = 0;
        @(negedge clk);

        if (val_osca_wt_pos !== 7'd15) begin
            $display("[FAIL] Touch Delta WT_POS update failed! Got %d", val_osca_wt_pos);
            $stop;
        end else begin
            $display("[PASS] Touch Delta WT_POS updated: 0 + 15 = 15");
        end

        // 4. Test Boundary Clamping at Lower Bound (0)
        @(negedge clk);
        touch_delta_valid = 1;
        touch_selected_id = `PARAM_ID_OSCA_WT_POS;
        touch_delta_val   = -8'sd50; // 15 - 50 = -35 -> should clamp to 0
        @(negedge clk);
        touch_delta_valid = 0;
        @(negedge clk);

        if (val_osca_wt_pos !== 7'd0) begin
            $display("[FAIL] Lower clamp failed! Got %d", val_osca_wt_pos);
            $stop;
        end else begin
            $display("[PASS] Lower boundary clamping verified: clamped to 0");
        end

        // 5. Test Boundary Clamping at Upper Bound (127)
        @(negedge clk);
        touch_delta_valid = 1;
        touch_selected_id = `PARAM_ID_FLT_CUTOFF;
        touch_delta_val   = 8'sd100; // 112 + 100 = 212 -> should clamp to 127
        @(negedge clk);
        touch_delta_valid = 0;
        @(negedge clk);

        if (val_flt_cutoff !== 7'd127) begin
            $display("[FAIL] Upper clamp failed! Got %d", val_flt_cutoff);
            $stop;
        end else begin
            $display("[PASS] Upper boundary clamping verified: clamped to 127");
        end

        // 6. Test Button Tap OSC A Power Toggle (default 1 -> toggle to 0 -> toggle to 1)
        @(negedge clk);
        btn_tap_valid  = 1;
        btn_tap_id     = `PARAM_ID_OSCA_POWER;
        btn_tap_action = 2'd0;
        @(negedge clk);
        btn_tap_valid  = 0;
        @(negedge clk);
        if (val_osca_power !== 1'b0) begin
            $display("[FAIL] OSC A Power toggle failed! Got %b", val_osca_power);
            $stop;
        end else begin
            $display("[PASS] OSC A Power toggle 1->0 verified");
        end

        // 7. Test Button Tap ENV Tab Switch (action=1 -> ENV 2, action=2 -> ENV 3)
        @(negedge clk);
        btn_tap_valid  = 1;
        btn_tap_id     = `PARAM_ID_ENV_TAB;
        btn_tap_action = 2'd1; // Tab 2
        @(negedge clk);
        btn_tap_valid  = 0;
        @(negedge clk);
        if (val_env_tab !== 2'd1) begin
            $display("[FAIL] ENV Tab switch failed! Got %d", val_env_tab);
            $stop;
        end else begin
            $display("[PASS] ENV Tab switched to Tab 2 verified");
        end

        // 8. Test Matrix Slot 1 Bypass Toggle (0 -> 1)
        @(negedge clk);
        btn_tap_valid  = 1;
        btn_tap_id     = `PARAM_ID_SLOT1_BYPASS;
        btn_tap_action = 2'd0;
        @(negedge clk);
        btn_tap_valid  = 0;
        @(negedge clk);
        if (val_slot_bypass[0] !== 1'b1) begin
            $display("[FAIL] Slot 1 Bypass toggle failed! Got %b", val_slot_bypass);
            $stop;
        end else begin
            $display("[PASS] Modulation Matrix Slot 1 Bypass toggle 0->1 verified");
        end

        // Consecutive events must retain ID/value pairing at one event/clock.
        @(negedge clk);spi_param_valid=1;spi_param_id=`PARAM_ID_FLT_CUTOFF;spi_param_val=21;
        @(negedge clk);spi_param_id=`PARAM_ID_OSCA_WT_POS;spi_param_val=37;
        @(negedge clk);
        if(val_flt_cutoff!==21 || midi_cc_param_id!==`PARAM_ID_FLT_CUTOFF || midi_cc_val!==21 || !midi_cc_req)
            $fatal(1,"First pipelined event not preserved");
        spi_param_valid=0;
        @(negedge clk);
        if(val_osca_wt_pos!==37 || midi_cc_param_id!==`PARAM_ID_OSCA_WT_POS || midi_cc_val!==37 || !midi_cc_req)
            $fatal(1,"Second pipelined event not preserved");
        @(negedge clk);
        if(midi_cc_req) $fatal(1,"Duplicate pipelined event");
        // Same-cycle arbitration is button > SPI > touch.
        btn_tap_valid=1;btn_tap_id=`PARAM_ID_OSCA_POWER;btn_tap_action=0;
        spi_param_valid=1;spi_param_id=`PARAM_ID_FLT_CUTOFF;spi_param_val=99;
        touch_delta_valid=1;touch_selected_id=`PARAM_ID_OSCA_WT_POS;touch_delta_val=5;
        @(negedge clk);btn_tap_valid=0;spi_param_valid=0;touch_delta_valid=0;
        @(negedge clk);
        if(val_osca_power!==1 || val_flt_cutoff!==21 || val_osca_wt_pos!==37 || midi_cc_param_id!==`PARAM_ID_OSCA_POWER)
            $fatal(1,"Same-cycle event source priority changed");
        @(negedge clk);
        spi_param_valid=1;spi_param_id=`PARAM_ID_FLT_CUTOFF;spi_param_val=99;
        touch_delta_valid=1;touch_selected_id=`PARAM_ID_OSCA_WT_POS;touch_delta_val=5;
        @(negedge clk);spi_param_valid=0;touch_delta_valid=0;
        @(negedge clk);
        if(val_flt_cutoff!==99 || val_osca_wt_pos!==37) $fatal(1,"SPI must win over touch");

        // Filter UI enum 0..3 maps to audio modes 1..4 while enabled;
        // toggling Filter Power maps to bypass 0/current mode.
        @(negedge clk);btn_tap_valid=1;btn_tap_id=`PARAM_ID_FLT_TYPE;btn_tap_action=0;
        @(negedge clk);btn_tap_valid=0;
        @(negedge clk);
        if(val_flt_type!==2'd1 || !midi_cc_req
           || midi_cc_param_id!==`PARAM_ID_FLT_TYPE || midi_cc_val!==7'd2)
            $fatal(1,"Filter type did not map HP to audio mode 2");
        @(negedge clk);btn_tap_valid=1;btn_tap_id=`PARAM_ID_FLT_POWER;btn_tap_action=0;
        @(negedge clk);btn_tap_valid=0;
        @(negedge clk);
        if(val_flt_power!==1'b0 || !midi_cc_req
           || midi_cc_param_id!==`PARAM_ID_FLT_POWER || midi_cc_val!==7'd0)
            $fatal(1,"Filter power-off did not map to audio bypass");
        @(negedge clk);btn_tap_valid=1;btn_tap_id=`PARAM_ID_FLT_POWER;btn_tap_action=0;
        @(negedge clk);btn_tap_valid=0;
        @(negedge clk);
        if(val_flt_power!==1'b1 || !midi_cc_req
           || midi_cc_param_id!==`PARAM_ID_FLT_POWER || midi_cc_val!==7'd2)
            $fatal(1,"Filter power-on did not restore selected audio mode");
        $display("[PASS] Filter UI type/power mapped to audio mode and bypass CC42 semantics");
        $display("[PASS] Event pipeline throughput, exact ID/value pairing, no duplicates, button/SPI/touch priority");
        $display("=================================================");
        $display("   ALL PARAM_MERGER UNIT TESTS PASSED (100%%)    ");
        $display("=================================================");
        $finish;
    end

endmodule
