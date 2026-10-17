// ==============================================================================
// Module: knob_vector_unit.v
// Description: Procedural Circular Vector Knob Engine (Zero BRAM, Zero Bitmaps)
//              Renders metallic bezel, shaded cap, 270-deg arc gauge, and
//              rotating glowing needle pointer for all synth knobs.
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"

module knob_vector_unit (
    input  wire        clk,
    input  wire        rst_n,

    // Current raster beam position
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // Parameter inputs from param_merger
    input  wire [6:0]  val_macro1, val_macro2, val_macro3, val_macro4, val_master_vol,
    input  wire [6:0]  val_osca_unison, val_osca_detune, val_osca_blend, val_osca_phase, val_osca_rand,
    input  wire [6:0]  val_osca_wt_pos, val_osca_warp, val_osca_pan, val_osca_vol,
    input  wire [6:0]  val_oscb_unison, val_oscb_detune, val_oscb_blend, val_oscb_phase, val_oscb_rand,
    input  wire [6:0]  val_oscb_wt_pos, val_oscb_warp, val_oscb_pan, val_oscb_vol,
    input  wire [6:0]  val_flt_cutoff, val_flt_res, val_flt_pan, val_flt_drive, val_flt_fat, val_flt_mix,
    input  wire [6:0]  val_env_attack, val_env_hold, val_env_decay, val_env_sustain, val_env_release,
    input  wire [6:0]  val_fx_reverb, val_fx_delay, val_fx_chorus, val_portamento,

    // Currently selected/touched knob ID
    input  wire [7:0]  selected_param_id,

    // Raster output flags (Stage 2 pipelined)
    output reg         out_hit_knob,
    output reg  [23:0] out_knob_rgb
);

    // --------------------------------------------------------------------------
    // Stage 0: Nearest Knob Detection & Multiplexing
    // --------------------------------------------------------------------------
    reg        s0_active;
    reg [13:0] s0_cx;
    reg [13:0] s0_cy;
    reg [4:0]  s0_r;
    reg [6:0]  s0_val;
    reg [7:0]  s0_id;
    reg [13:0] s0_x, s0_y;

    always @(posedge clk) begin
        s0_x      <= in_x;
        s0_y      <= in_y;
        s0_active <= 1'b0;
        s0_cx     <= 14'd0;
        s0_cy     <= 14'd0;
        s0_r      <= 5'd14;
        s0_val    <= 7'd64;
        s0_id     <= `PARAM_ID_NONE;

        // --- ROW 0: Top Bar (Y = 8 .. 42, cy = 22) ---
        if (in_y >= 14'd8 && in_y <= 14'd42) begin
            s0_cy <= 14'd22;
            if (in_x >= 14'd170 && in_x <= 14'd230) begin
                s0_active <= 1'b1; s0_cx <= 14'd200; s0_r <= 5'd13; s0_val <= val_macro1; s0_id <= `PARAM_ID_MACRO1;
            end else if (in_x >= 14'd230 && in_x <= 14'd290) begin
                s0_active <= 1'b1; s0_cx <= 14'd260; s0_r <= 5'd13; s0_val <= val_macro2; s0_id <= `PARAM_ID_MACRO2;
            end else if (in_x >= 14'd290 && in_x <= 14'd350) begin
                s0_active <= 1'b1; s0_cx <= 14'd320; s0_r <= 5'd13; s0_val <= val_macro3; s0_id <= `PARAM_ID_MACRO3;
            end else if (in_x >= 14'd350 && in_x <= 14'd410) begin
                s0_active <= 1'b1; s0_cx <= 14'd380; s0_r <= 5'd13; s0_val <= val_macro4; s0_id <= `PARAM_ID_MACRO4;
            end else if (in_x >= 14'd1152 && in_x <= 14'd1212) begin
                s0_active <= 1'b1; s0_cx <= 14'd1182; s0_r <= 5'd16; s0_val <= val_master_vol; s0_id <= `PARAM_ID_MASTER_VOL;
            end
        end

        // --- ROW 1: Upper Row 1 (Y = 250 .. 298, cy = 268) ---
        else if (in_y >= 14'd250 && in_y <= 14'd298) begin
            s0_cy <= 14'd268;
            s0_r  <= 5'd14;
            // OSC A
            if (in_x >= 14'd34 && in_x <= 14'd94) begin
                s0_active <= 1'b1; s0_cx <= 14'd64; s0_val <= val_osca_unison; s0_id <= `PARAM_ID_OSCA_UNISON;
            end else if (in_x >= 14'd104 && in_x <= 14'd164) begin
                s0_active <= 1'b1; s0_cx <= 14'd134; s0_val <= val_osca_detune; s0_id <= `PARAM_ID_OSCA_DETUNE;
            end else if (in_x >= 14'd174 && in_x <= 14'd234) begin
                s0_active <= 1'b1; s0_cx <= 14'd204; s0_val <= val_osca_blend; s0_id <= `PARAM_ID_OSCA_BLEND;
            end else if (in_x >= 14'd244 && in_x <= 14'd304) begin
                s0_active <= 1'b1; s0_cx <= 14'd274; s0_val <= val_osca_phase; s0_id <= `PARAM_ID_OSCA_PHASE;
            end else if (in_x >= 14'd314 && in_x <= 14'd374) begin
                s0_active <= 1'b1; s0_cx <= 14'd344; s0_val <= val_osca_rand; s0_id <= `PARAM_ID_OSCA_RAND;
            end
            // OSC B
            else if (in_x >= 14'd450 && in_x <= 14'd510) begin
                s0_active <= 1'b1; s0_cx <= 14'd480; s0_val <= val_oscb_unison; s0_id <= `PARAM_ID_OSCB_UNISON;
            end else if (in_x >= 14'd520 && in_x <= 14'd580) begin
                s0_active <= 1'b1; s0_cx <= 14'd550; s0_val <= val_oscb_detune; s0_id <= `PARAM_ID_OSCB_DETUNE;
            end else if (in_x >= 14'd590 && in_x <= 14'd650) begin
                s0_active <= 1'b1; s0_cx <= 14'd620; s0_val <= val_oscb_blend; s0_id <= `PARAM_ID_OSCB_BLEND;
            end else if (in_x >= 14'd660 && in_x <= 14'd720) begin
                s0_active <= 1'b1; s0_cx <= 14'd690; s0_val <= val_oscb_phase; s0_id <= `PARAM_ID_OSCB_PHASE;
            end else if (in_x >= 14'd730 && in_x <= 14'd790) begin
                s0_active <= 1'b1; s0_cx <= 14'd760; s0_val <= val_oscb_rand; s0_id <= `PARAM_ID_OSCB_RAND;
            end
            // Filter
            else if (in_x >= 14'd920 && in_x <= 14'd980) begin
                s0_active <= 1'b1; s0_cx <= 14'd950; s0_r <= 5'd15; s0_val <= val_flt_cutoff; s0_id <= `PARAM_ID_FLT_CUTOFF;
            end else if (in_x >= 14'd1010 && in_x <= 14'd1070) begin
                s0_active <= 1'b1; s0_cx <= 14'd1040; s0_r <= 5'd15; s0_val <= val_flt_res; s0_id <= `PARAM_ID_FLT_RES;
            end else if (in_x >= 14'd1100 && in_x <= 14'd1160) begin
                s0_active <= 1'b1; s0_cx <= 14'd1130; s0_val <= val_flt_pan; s0_id <= `PARAM_ID_FLT_PAN;
            end
        end

        // --- ROW 2: Upper Row 2 (Y = 308 .. 356, cy = 326) ---
        else if (in_y >= 14'd308 && in_y <= 14'd356) begin
            s0_cy <= 14'd326;
            s0_r  <= 5'd14;
            // OSC A
            if (in_x >= 14'd54 && in_x <= 14'd114) begin
                s0_active <= 1'b1; s0_cx <= 14'd84; s0_r <= 5'd15; s0_val <= val_osca_wt_pos; s0_id <= `PARAM_ID_OSCA_WT_POS;
            end else if (in_x >= 14'd134 && in_x <= 14'd194) begin
                s0_active <= 1'b1; s0_cx <= 14'd164; s0_val <= val_osca_warp; s0_id <= `PARAM_ID_OSCA_WARP;
            end else if (in_x >= 14'd234 && in_x <= 14'd294) begin
                s0_active <= 1'b1; s0_cx <= 14'd264; s0_val <= val_osca_pan; s0_id <= `PARAM_ID_OSCA_PAN;
            end else if (in_x >= 14'd314 && in_x <= 14'd374) begin
                s0_active <= 1'b1; s0_cx <= 14'd344; s0_r <= 5'd15; s0_val <= val_osca_vol; s0_id <= `PARAM_ID_OSCA_VOL;
            end
            // OSC B
            else if (in_x >= 14'd470 && in_x <= 14'd530) begin
                s0_active <= 1'b1; s0_cx <= 14'd500; s0_r <= 5'd15; s0_val <= val_oscb_wt_pos; s0_id <= `PARAM_ID_OSCB_WT_POS;
            end else if (in_x >= 14'd550 && in_x <= 14'd610) begin
                s0_active <= 1'b1; s0_cx <= 14'd580; s0_val <= val_oscb_warp; s0_id <= `PARAM_ID_OSCB_WARP;
            end else if (in_x >= 14'd650 && in_x <= 14'd710) begin
                s0_active <= 1'b1; s0_cx <= 14'd680; s0_val <= val_oscb_pan; s0_id <= `PARAM_ID_OSCB_PAN;
            end else if (in_x >= 14'd730 && in_x <= 14'd790) begin
                s0_active <= 1'b1; s0_cx <= 14'd760; s0_r <= 5'd15; s0_val <= val_oscb_vol; s0_id <= `PARAM_ID_OSCB_VOL;
            end
            // Filter
            else if (in_x >= 14'd920 && in_x <= 14'd980) begin
                s0_active <= 1'b1; s0_cx <= 14'd950; s0_val <= val_flt_drive; s0_id <= `PARAM_ID_FLT_DRIVE;
            end else if (in_x >= 14'd1010 && in_x <= 14'd1070) begin
                s0_active <= 1'b1; s0_cx <= 14'd1040; s0_val <= val_flt_fat; s0_id <= `PARAM_ID_FLT_FAT;
            end else if (in_x >= 14'd1100 && in_x <= 14'd1160) begin
                s0_active <= 1'b1; s0_cx <= 14'd1130; s0_r <= 5'd15; s0_val <= val_flt_mix; s0_id <= `PARAM_ID_FLT_MIX;
            end
        end

        // --- ROW 3: Expanded Lower Deck (Envelope & FX Knobs, Y = 632 .. 682, cy = 652) ---
        else if (in_y >= 14'd632 && in_y <= 14'd682) begin
            s0_cy <= 14'd652;
            s0_r  <= 5'd15;
            // Envelope 1 (Attack, Hold, Decay, Sustain, Release)
            if (in_x >= 14'd70 && in_x <= 14'd130) begin
                s0_active <= 1'b1; s0_cx <= 14'd100; s0_val <= val_env_attack; s0_id <= `PARAM_ID_ENV1_ATTACK;
            end else if (in_x >= 14'd200 && in_x <= 14'd260) begin
                s0_active <= 1'b1; s0_cx <= 14'd230; s0_val <= val_env_hold; s0_id <= `PARAM_ID_ENV1_HOLD;
            end else if (in_x >= 14'd330 && in_x <= 14'd390) begin
                s0_active <= 1'b1; s0_cx <= 14'd360; s0_val <= val_env_decay; s0_id <= `PARAM_ID_ENV1_DECAY;
            end else if (in_x >= 14'd460 && in_x <= 14'd520) begin
                s0_active <= 1'b1; s0_cx <= 14'd490; s0_val <= val_env_sustain; s0_id <= `PARAM_ID_ENV1_SUSTAIN;
            end else if (in_x >= 14'd590 && in_x <= 14'd650) begin
                s0_active <= 1'b1; s0_cx <= 14'd620; s0_val <= val_env_release; s0_id <= `PARAM_ID_ENV1_RELEASE;
            end
            // Master FX & Voicing (Reverb, Delay, Chorus, Portamento)
            else if (in_x >= 14'd830 && in_x <= 14'd890) begin
                s0_active <= 1'b1; s0_cx <= 14'd860; s0_val <= val_fx_reverb; s0_id <= `PARAM_ID_FX_REVERB;
            end else if (in_x >= 14'd930 && in_x <= 14'd990) begin
                s0_active <= 1'b1; s0_cx <= 14'd960; s0_val <= val_fx_delay; s0_id <= `PARAM_ID_FX_DELAY;
            end else if (in_x >= 14'd1030 && in_x <= 14'd1090) begin
                s0_active <= 1'b1; s0_cx <= 14'd1060; s0_val <= val_fx_chorus; s0_id <= `PARAM_ID_FX_CHORUS;
            end else if (in_x >= 14'd1130 && in_x <= 14'd1190) begin
                s0_active <= 1'b1; s0_cx <= 14'd1160; s0_val <= val_portamento; s0_id <= `PARAM_ID_PORTAMENTO;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Stage 1: Distance Squaring & Vector Direction Projections
    // --------------------------------------------------------------------------
    reg        s1_active;
    reg        s1_selected;
    reg [4:0]  s1_r;
    reg [12:0] s1_r2;
    reg [5:0]  s1_dx_abs, s1_dy_abs;
    reg signed [5:0] s1_dx, s1_dy;
    reg signed [5:0] s1_ux, s1_uy;
    reg [6:0]  s1_val;
    reg [13:0] s1_cy;
    reg [7:0]  s1_id;
    reg [35:0] s1_label;
    reg [5:0] s1_hundreds, s1_tens, s1_ones;

    // 16-Angle Lookup (-135 to +135 deg: 16 directions, 6-bit fixed point)
    function [11:0] get_needle_vector;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  get_needle_vector = { -6'sd23,  6'sd23 }; // -135 deg (7 o'clock)
                4'd1:  get_needle_vector = { -6'sd28,  6'sd15 }; // -117 deg
                4'd2:  get_needle_vector = { -6'sd31,  6'sd6  }; // -99 deg
                4'd3:  get_needle_vector = { -6'sd31, -6'sd6  }; // -81 deg
                4'd4:  get_needle_vector = { -6'sd28, -6'sd15 }; // -63 deg
                4'd5:  get_needle_vector = { -6'sd23, -6'sd23 }; // -45 deg
                4'd6:  get_needle_vector = { -6'sd15, -6'sd28 }; // -27 deg
                4'd7:  get_needle_vector = { -6'sd6,  -6'sd31 }; // -9 deg
                4'd8:  get_needle_vector = {  6'sd6,  -6'sd31 }; // +9 deg
                4'd9:  get_needle_vector = {  6'sd15, -6'sd28 }; // +27 deg
                4'd10: get_needle_vector = {  6'sd23, -6'sd23 }; // +45 deg
                4'd11: get_needle_vector = {  6'sd28, -6'sd15 }; // +63 deg
                4'd12: get_needle_vector = {  6'sd31, -6'sd6  }; // +81 deg
                4'd13: get_needle_vector = {  6'sd31,  6'sd6  }; // +99 deg
                4'd14: get_needle_vector = {  6'sd28,  6'sd15 }; // +117 deg
                default: get_needle_vector = { 6'sd23, 6'sd23 }; // +135 deg (5 o'clock)
            endcase
        end
    endfunction

    // Subtract full raster coordinates before narrowing. Subtracting only low
    // bits under a widened multiply corrupts distances at every 64px boundary.
    wire [13:0] dx_full = (s0_x >= s0_cx) ? s0_x-s0_cx : s0_cx-s0_x;
    wire [13:0] dy_full = (s0_y >= s0_cy) ? s0_y-s0_cy : s0_cy-s0_y;
    wire [12:0] dx_square = {7'd0,dx_full[5:0]} * {7'd0,dx_full[5:0]};
    wire [12:0] dy_square = {7'd0,dy_full[5:0]} * {7'd0,dy_full[5:0]};

    always @(posedge clk) begin
        s1_active   <= s0_active;
        s1_selected <= (s0_id != `PARAM_ID_NONE) && (s0_id == selected_param_id);
        s1_r        <= s0_r;
        s1_val      <= s0_val;
        s1_cy       <= s0_cy;
        s1_id       <= s0_id;
        s1_label    <= get_param_label6(s0_id);
        s1_hundreds <= (s0_val >= 7'd100) ? `CH_1 : `CH_SPACE;
        s1_tens     <= (s0_val >= 7'd10) ? (`CH_0 + ((s0_val % 100) / 10)) : `CH_SPACE;
        s1_ones     <= `CH_0 + (s0_val % 10);

        if (s0_active) begin
            s1_dx     <= $signed(s0_x - s0_cx);
            s1_dy     <= $signed(s0_y - s0_cy);
            s1_dx_abs <= dx_full[5:0];
            s1_dy_abs <= dy_full[5:0];
            s1_r2     <= dx_square + dy_square;
            {s1_ux, s1_uy} <= get_needle_vector(s0_val[6:3]);
        end else begin
            s1_dx     <= 6'sd0;
            s1_dy     <= 6'sd0;
            s1_dx_abs <= 6'd0;
            s1_dy_abs <= 6'd0;
            s1_r2     <= 13'd0;
            s1_ux     <= 6'sd0;
            s1_uy     <= 6'sd0;
        end
    end

    // --------------------------------------------------------------------------
    // Stage 2: Geometric Pixel Compositor
    // --------------------------------------------------------------------------
    wire signed [11:0] proj = (s1_dx * s1_ux) + (s1_dy * s1_uy);
    wire signed [11:0] perp = (s1_dx * s1_uy) - (s1_dy * s1_ux);

    wire [9:0] r_limit2 = {5'd0, s1_r} * {5'd0, s1_r};
    wire [9:0] bezel_inner2 = r_limit2 - 10'd35;
    wire [9:0] arc_min2 = r_limit2 + 10'd6;
    wire [9:0] arc_max2 = r_limit2 + 10'd42;

    // Needle criteria: within inner cap, along projection vector, narrow perpendicular tolerance
    wire hit_needle = s1_active && (s1_r2 >= 10'd9) && (s1_r2 <= bezel_inner2) &&
                      (proj > 12'sd0) && (perp >= -12'sd22) && (perp <= 12'sd22);

    // 270-degree arc gauge: outer ring, excluding bottom dead-zone (dy > 0 and |dx| < dy)
    wire in_arc_deadzone = (s1_dy > 0) && (s1_dx_abs < s1_dy_abs);
    wire hit_arc = s1_active && (s1_r2 >= arc_min2) && (s1_r2 <= arc_max2) && !in_arc_deadzone;

    // Selection Halo Ring
    wire hit_halo = s1_selected && (s1_r2 >= arc_max2 + 10'd2) && (s1_r2 <= arc_max2 + 10'd16);

    // Native coverage glyphs keep the same labels / interaction geometry.
    wire is_row0 = (s1_cy == 14'd22);
    wire signed [5:0] lbl_y_start  = is_row0 ? 6'sd13 : 6'sd18;
    wire signed [5:0] lbl_y_end    = is_row0 ? 6'sd20 : 6'sd30;
    wire signed [5:0] font_y_start = is_row0 ? 6'sd14 : 6'sd19;

    wire in_lbl_box = s1_active && (s1_id != `PARAM_ID_NONE) &&
                      (s1_dy >= lbl_y_start && s1_dy <= lbl_y_end) &&
                      (is_row0 ? (s1_dx >= -6'sd13 && s1_dx <= 6'sd13) :
                                 (s1_dx >= -6'sd25 && s1_dx <= 6'sd25));

    wire on_lbl_border = in_lbl_box && 
                         (s1_dy == lbl_y_start || s1_dy == lbl_y_end);

    // Native 0..127 parameter value inside each cap; no invented Hz/ms units.
    wire signed [5:0] value_x_start = (s1_val >= 100) ? -6'sd11 :
                                             (s1_val >= 10) ? -6'sd7 : -6'sd3;
    wire [5:0] value_x_offset = s1_dx-value_x_start;
    wire [5:0] value_y_offset = s1_dy-6'sd1;
    wire [5:0] value_width = (s1_val >= 100) ? 6'd23 : (s1_val >= 10) ? 6'd15 : 6'd7;
    wire value_area = s1_dy >= 6'sd1 && s1_dy <= 6'sd10 &&
                      s1_dx >= value_x_start && value_x_offset < value_width;
    // Decode the character in stage one; the larger glyph lookup belongs to
    // stage two. Local modular deltas are valid in the detected +/-30px cells.
    wire signed [5:0] text_dx0=s0_x[5:0]-s0_cx[5:0];
    wire signed [5:0] text_dy0=s0_y[5:0]-s0_cy[5:0];
    wire row0_0=s0_cy==22;
    wire [35:0] label0=get_param_label6(s0_id);
    wire [5:0] label_x0=row0_0 ? text_dx0+6'd12 : text_dx0+6'd24;
    wire [5:0] label_y0=row0_0 ? text_dy0-6'd14 : text_dy0-6'd19;
    wire [2:0] label_col0=row0_0 ? label_x0[4:2] : label_x0[5:3];
    wire signed [5:0] value_start0=s0_val>=100 ? -6'sd11 : s0_val>=10 ? -6'sd7 : -6'sd3;
    wire [5:0] value_x0=text_dx0-value_start0;
    wire [5:0] value_y0=text_dy0-6'd1;
    reg [5:0] label_ch0,value_ch0;
    reg [1:0] value_micro_rx0;
    reg value_valid0;
    always @(*) begin
        case(label_col0)
            0:label_ch0=label0[35:30];1:label_ch0=label0[29:24];
            2:label_ch0=label0[23:18];3:label_ch0=label0[17:12];
            4:label_ch0=label0[11:6];5:label_ch0=label0[5:0];
            default:label_ch0=0;
        endcase
        value_ch0=`CH_0+(s0_val%10);value_micro_rx0=0;
        value_valid0=s0_active && text_dy0>=1 && text_dy0<=10 &&
            text_dx0>=value_start0 && value_x0<(s0_val>=100 ? 23 : s0_val>=10 ? 15 : 7);
        if(s0_val>=100) begin
            case(value_x0[4:3])
                0:value_ch0=`CH_1;
                1:value_ch0=`CH_0+((s0_val%100)/10);
            endcase
        end else if(s0_val>=10 && value_x0[4:3]==0)
            value_ch0=`CH_0+((s0_val%100)/10);
        if(row0_0) begin
            value_valid0=s0_active && text_dy0>=3 && text_dy0<=7;
            if(text_dx0>=-5 && text_dx0<=-3) begin
                value_ch0=s0_val>=100 ? `CH_1 : `CH_SPACE;
                value_micro_rx0=text_dx0+6'd5;
            end else if(text_dx0>=-1 && text_dx0<=1) begin
                value_ch0=s0_val>=10 ? `CH_0+((s0_val%100)/10) : `CH_SPACE;
                value_micro_rx0=text_dx0+6'd1;
            end else if(text_dx0>=3 && text_dx0<=5) begin
                value_ch0=`CH_0+(s0_val%10);value_micro_rx0=text_dx0-6'd3;
            end else value_valid0=0;
        end
    end
    reg [5:0] text_ch1,value_ch1;
    reg [2:0] text_rx1,value_rx1;
    reg [3:0] text_ry1,value_ry1;
    reg text_valid1,value_valid1;
    always @(posedge clk) begin
        text_ch1<=label_ch0;value_ch1<=value_ch0;
        text_rx1<=row0_0 ? {1'b0,label_x0[1:0]} : label_x0[2:0];
        text_ry1<=label_y0[3:0];
        text_valid1<=s0_active && label_col0<6 &&
            (row0_0 ? label_y0<5 && text_dx0>=-13 && text_dx0<=13 :
                       label_y0<10 && text_dx0>=-25 && text_dx0<=25);
        value_rx1<=row0_0 ? {1'b0,value_micro_rx0} : value_x0[2:0];
        value_ry1<=row0_0 ? text_dy0-6'd3 : value_y0[3:0];
        value_valid1<=value_valid0;
    end
    wire [1:0] font_coverage=text_valid1 ? (is_row0 ?
        (get_font_3x5(text_ch1,text_rx1[1:0],text_ry1[2:0]) ? 2'd3 : 2'd0) :
        get_font_7x10(text_ch1,text_rx1,text_ry1)) : 2'd0;
    wire [1:0] value_coverage=value_valid1 ? (is_row0 ?
        (get_font_3x5(value_ch1,value_rx1[1:0],value_ry1[2:0]) ? 2'd3 : 2'd0) :
        get_font_7x10(value_ch1,value_rx1,value_ry1)) : 2'd0;
    wire hit_tick = s1_active && !is_row0 &&
        ((s1_dy == -6'sd18 && s1_dx >= -6'sd1 && s1_dx <= 6'sd1) ||
         (s1_dy == 6'sd12 && (s1_dx == -6'sd17 || s1_dx == 6'sd17)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hit_knob <= 1'b0;
            out_knob_rgb <= 24'h0;
        end else begin
            out_hit_knob <= 1'b0;
            out_knob_rgb <= `COLOR_PANEL_BG;

            if (s1_active) begin
                // Priority 1: Parameter caption
                if (font_coverage!=0) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= blend_rgb_q4(s1_selected ? 24'h00FFFF : 24'hFFFFFF,
                        24'h101720,font_alpha_q4(font_coverage));
                end
                // Priority 2: Label Box Border
                else if (on_lbl_border) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= s1_selected ? 24'h00D0FF : 24'h2E3D4E;
                end
                // Priority 3: Label Box Background Pill
                else if (in_lbl_box) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= 24'h101720;
                end
                // Priority 4: Glowing Pointer Needle
                else if (value_coverage!=0) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= blend_rgb_q4(24'hF0F4FF,`COLOR_KNOB_BODY,font_alpha_q4(value_coverage));
                end else if (hit_tick) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= 24'h9FAEC2;
                end else if (hit_needle && !(is_row0 ?
                    (s1_dy >= 6'sd2 && s1_dy <= 6'sd8 && s1_dx_abs <= 6'd6) : value_area)) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= `COLOR_KNOB_NEEDLE;
                end
                // Priority 5: Selection Active Halo
                else if (hit_halo) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= `COLOR_KNOB_ARC;
                end
                // Priority 6: 270-degree Arc Gauge
                else if (hit_arc) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= `COLOR_KNOB_ARC;
                end
                // Priority 7: Metallic Bezel Rim
                else if (s1_r2 <= r_limit2 && s1_r2 >= bezel_inner2) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= `COLOR_KNOB_BEZEL;
                end
                // Priority 8: Dark Knob Inner Cap
                else if (s1_r2 < bezel_inner2) begin
                    out_hit_knob <= 1'b1;
                    out_knob_rgb <= `COLOR_KNOB_BODY;
                end
            end
        end
    end

endmodule
