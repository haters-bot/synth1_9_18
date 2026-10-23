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
    // Keep local raster copies from merging into a cross-panel high-fanout net.
    reg [13:0] s0_x /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] s0_y /* synthesis syn_preserve=1 syn_maxfan=32 */;

    // Decode Y by its 32-pixel bucket first; only the two edge buckets need
    // a low-bit boundary compare. This avoids four full-width range
    // comparators feeding every 49-bit cell record.
    wire y_hi_valid = (in_y[13:10] == 4'd0);
    wire [4:0] y_bucket = in_y[9:5];
    wire knob_row0_y = y_hi_valid &&
        ((y_bucket == 5'd0 && in_y[4:0] >= 5'd8) ||
         (y_bucket == 5'd1 && in_y[4:0] <= 5'd10));
    wire knob_row1_y = y_hi_valid &&
        ((y_bucket == 5'd7 && in_y[4:0] >= 5'd26) ||
         (y_bucket == 5'd8) ||
         (y_bucket == 5'd9 && in_y[4:0] <= 5'd10));
    wire knob_row2_y = y_hi_valid &&
        ((y_bucket == 5'd9 && in_y[4:0] >= 5'd20) ||
         (y_bucket == 5'd10) ||
         (y_bucket == 5'd11 && in_y[4:0] <= 5'd4));
    wire knob_row3_y = y_hi_valid &&
        ((y_bucket == 5'd19 && in_y[4:0] >= 5'd24) ||
         (y_bucket == 5'd20) ||
         (y_bucket == 5'd21 && in_y[4:0] <= 5'd10));

    // Disjoint cells decode concurrently. The only shared boundary in row
    // zero belongs to the left cell, preserving the original priority.
    wire [48:0] knob_cells[0:37];
    assign knob_cells[0]=(knob_row0_y && in_x>=14'd170 && in_x<=14'd230) ?
        {1'b1,14'd200,14'd22,5'd13,val_macro1,`PARAM_ID_MACRO1} : 49'd0;
    assign knob_cells[1]=(knob_row0_y && in_x>=14'd231 && in_x<=14'd290) ?
        {1'b1,14'd260,14'd22,5'd13,val_macro2,`PARAM_ID_MACRO2} : 49'd0;
    assign knob_cells[2]=(knob_row0_y && in_x>=14'd291 && in_x<=14'd350) ?
        {1'b1,14'd320,14'd22,5'd13,val_macro3,`PARAM_ID_MACRO3} : 49'd0;
    assign knob_cells[3]=(knob_row0_y && in_x>=14'd351 && in_x<=14'd410) ?
        {1'b1,14'd380,14'd22,5'd13,val_macro4,`PARAM_ID_MACRO4} : 49'd0;
    assign knob_cells[4]=(knob_row0_y && in_x>=14'd1152 && in_x<=14'd1212) ?
        {1'b1,14'd1182,14'd22,5'd16,val_master_vol,`PARAM_ID_MASTER_VOL} : 49'd0;
    assign knob_cells[5]=(knob_row1_y && in_x>=14'd34 && in_x<=14'd94) ?
        {1'b1,14'd64,14'd268,5'd14,val_osca_unison,`PARAM_ID_OSCA_UNISON} : 49'd0;
    assign knob_cells[6]=(knob_row1_y && in_x>=14'd104 && in_x<=14'd164) ?
        {1'b1,14'd134,14'd268,5'd14,val_osca_detune,`PARAM_ID_OSCA_DETUNE} : 49'd0;
    assign knob_cells[7]=(knob_row1_y && in_x>=14'd174 && in_x<=14'd234) ?
        {1'b1,14'd204,14'd268,5'd14,val_osca_blend,`PARAM_ID_OSCA_BLEND} : 49'd0;
    assign knob_cells[8]=(knob_row1_y && in_x>=14'd244 && in_x<=14'd304) ?
        {1'b1,14'd274,14'd268,5'd14,val_osca_phase,`PARAM_ID_OSCA_PHASE} : 49'd0;
    assign knob_cells[9]=(knob_row1_y && in_x>=14'd314 && in_x<=14'd374) ?
        {1'b1,14'd344,14'd268,5'd14,val_osca_rand,`PARAM_ID_OSCA_RAND} : 49'd0;
    assign knob_cells[10]=(knob_row1_y && in_x>=14'd450 && in_x<=14'd510) ?
        {1'b1,14'd480,14'd268,5'd14,val_oscb_unison,`PARAM_ID_OSCB_UNISON} : 49'd0;
    assign knob_cells[11]=(knob_row1_y && in_x>=14'd520 && in_x<=14'd580) ?
        {1'b1,14'd550,14'd268,5'd14,val_oscb_detune,`PARAM_ID_OSCB_DETUNE} : 49'd0;
    assign knob_cells[12]=(knob_row1_y && in_x>=14'd590 && in_x<=14'd650) ?
        {1'b1,14'd620,14'd268,5'd14,val_oscb_blend,`PARAM_ID_OSCB_BLEND} : 49'd0;
    assign knob_cells[13]=(knob_row1_y && in_x>=14'd660 && in_x<=14'd720) ?
        {1'b1,14'd690,14'd268,5'd14,val_oscb_phase,`PARAM_ID_OSCB_PHASE} : 49'd0;
    assign knob_cells[14]=(knob_row1_y && in_x>=14'd730 && in_x<=14'd790) ?
        {1'b1,14'd760,14'd268,5'd14,val_oscb_rand,`PARAM_ID_OSCB_RAND} : 49'd0;
    assign knob_cells[15]=(knob_row1_y && in_x>=14'd920 && in_x<=14'd980) ?
        {1'b1,14'd950,14'd268,5'd15,val_flt_cutoff,`PARAM_ID_FLT_CUTOFF} : 49'd0;
    assign knob_cells[16]=(knob_row1_y && in_x>=14'd1010 && in_x<=14'd1070) ?
        {1'b1,14'd1040,14'd268,5'd15,val_flt_res,`PARAM_ID_FLT_RES} : 49'd0;
    assign knob_cells[17]=(knob_row1_y && in_x>=14'd1100 && in_x<=14'd1160) ?
        {1'b1,14'd1130,14'd268,5'd14,val_flt_pan,`PARAM_ID_FLT_PAN} : 49'd0;
    assign knob_cells[18]=(knob_row2_y && in_x>=14'd54 && in_x<=14'd114) ?
        {1'b1,14'd84,14'd326,5'd15,val_osca_wt_pos,`PARAM_ID_OSCA_WT_POS} : 49'd0;
    assign knob_cells[19]=(knob_row2_y && in_x>=14'd134 && in_x<=14'd194) ?
        {1'b1,14'd164,14'd326,5'd14,val_osca_warp,`PARAM_ID_OSCA_WARP} : 49'd0;
    assign knob_cells[20]=(knob_row2_y && in_x>=14'd234 && in_x<=14'd294) ?
        {1'b1,14'd264,14'd326,5'd14,val_osca_pan,`PARAM_ID_OSCA_PAN} : 49'd0;
    assign knob_cells[21]=(knob_row2_y && in_x>=14'd314 && in_x<=14'd374) ?
        {1'b1,14'd344,14'd326,5'd15,val_osca_vol,`PARAM_ID_OSCA_VOL} : 49'd0;
    assign knob_cells[22]=(knob_row2_y && in_x>=14'd470 && in_x<=14'd530) ?
        {1'b1,14'd500,14'd326,5'd15,val_oscb_wt_pos,`PARAM_ID_OSCB_WT_POS} : 49'd0;
    assign knob_cells[23]=(knob_row2_y && in_x>=14'd550 && in_x<=14'd610) ?
        {1'b1,14'd580,14'd326,5'd14,val_oscb_warp,`PARAM_ID_OSCB_WARP} : 49'd0;
    assign knob_cells[24]=(knob_row2_y && in_x>=14'd650 && in_x<=14'd710) ?
        {1'b1,14'd680,14'd326,5'd14,val_oscb_pan,`PARAM_ID_OSCB_PAN} : 49'd0;
    assign knob_cells[25]=(knob_row2_y && in_x>=14'd730 && in_x<=14'd790) ?
        {1'b1,14'd760,14'd326,5'd15,val_oscb_vol,`PARAM_ID_OSCB_VOL} : 49'd0;
    assign knob_cells[26]=(knob_row2_y && in_x>=14'd920 && in_x<=14'd980) ?
        {1'b1,14'd950,14'd326,5'd14,val_flt_drive,`PARAM_ID_FLT_DRIVE} : 49'd0;
    assign knob_cells[27]=(knob_row2_y && in_x>=14'd1010 && in_x<=14'd1070) ?
        {1'b1,14'd1040,14'd326,5'd14,val_flt_fat,`PARAM_ID_FLT_FAT} : 49'd0;
    assign knob_cells[28]=(knob_row2_y && in_x>=14'd1100 && in_x<=14'd1160) ?
        {1'b1,14'd1130,14'd326,5'd15,val_flt_mix,`PARAM_ID_FLT_MIX} : 49'd0;
    assign knob_cells[29]=(knob_row3_y && in_x>=14'd34 && in_x<=14'd94) ?
        {1'b1,14'd64,14'd652,5'd15,val_env_attack,`PARAM_ID_ENV1_ATTACK} : 49'd0;
    assign knob_cells[30]=(knob_row3_y && in_x>=14'd100 && in_x<=14'd160) ?
        {1'b1,14'd130,14'd652,5'd15,val_env_hold,`PARAM_ID_ENV1_HOLD} : 49'd0;
    assign knob_cells[31]=(knob_row3_y && in_x>=14'd166 && in_x<=14'd226) ?
        {1'b1,14'd196,14'd652,5'd15,val_env_decay,`PARAM_ID_ENV1_DECAY} : 49'd0;
    assign knob_cells[32]=(knob_row3_y && in_x>=14'd232 && in_x<=14'd292) ?
        {1'b1,14'd262,14'd652,5'd15,val_env_sustain,`PARAM_ID_ENV1_SUSTAIN} : 49'd0;
    assign knob_cells[33]=(knob_row3_y && in_x>=14'd298 && in_x<=14'd358) ?
        {1'b1,14'd328,14'd652,5'd15,val_env_release,`PARAM_ID_ENV1_RELEASE} : 49'd0;
    assign knob_cells[34]=(knob_row3_y && in_x>=14'd830 && in_x<=14'd890) ?
        {1'b1,14'd860,14'd652,5'd15,val_fx_reverb,`PARAM_ID_FX_REVERB} : 49'd0;
    assign knob_cells[35]=(knob_row3_y && in_x>=14'd930 && in_x<=14'd990) ?
        {1'b1,14'd960,14'd652,5'd15,val_fx_delay,`PARAM_ID_FX_DELAY} : 49'd0;
    assign knob_cells[36]=(knob_row3_y && in_x>=14'd1030 && in_x<=14'd1090) ?
        {1'b1,14'd1060,14'd652,5'd15,val_fx_chorus,`PARAM_ID_FX_CHORUS} : 49'd0;
    assign knob_cells[37]=(knob_row3_y && in_x>=14'd1130 && in_x<=14'd1190) ?
        {1'b1,14'd1160,14'd652,5'd15,val_portamento,`PARAM_ID_PORTAMENTO} : 49'd0;
    // The 38 cells occupy four disjoint raster bands. Reduce each band first,
    // then select one 49-bit record by Y; this avoids a single 38-way wide OR
    // tree feeding the first registered geometry stage.
    wire [48:0] knob_row0=knob_cells[0]|knob_cells[1]|knob_cells[2]|knob_cells[3]|knob_cells[4];
    wire [48:0] knob_row1=knob_cells[5]|knob_cells[6]|knob_cells[7]|knob_cells[8]|knob_cells[9]|
                              knob_cells[10]|knob_cells[11]|knob_cells[12]|knob_cells[13]|knob_cells[14]|
                              knob_cells[15]|knob_cells[16]|knob_cells[17];
    wire [48:0] knob_row2=knob_cells[18]|knob_cells[19]|knob_cells[20]|knob_cells[21]|knob_cells[22]|
                              knob_cells[23]|knob_cells[24]|knob_cells[25]|knob_cells[26]|knob_cells[27]|
                              knob_cells[28];
    wire [48:0] knob_row3=knob_cells[29]|knob_cells[30]|knob_cells[31]|knob_cells[32]|knob_cells[33]|
                              knob_cells[34]|knob_cells[35]|knob_cells[36]|knob_cells[37];
    // Each row record is already zero outside its Y band. A flat OR keeps
    // the four disjoint rows off the timing-critical priority mux.
    wire [48:0] knob_decode = knob_row0 | knob_row1 | knob_row2 | knob_row3;
    always @(posedge clk) begin
        s0_x<=in_x;s0_y<=in_y;
        {s0_active,s0_cx,s0_cy,s0_r,s0_val,s0_id}<=knob_decode;
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

    // Active knob boxes are at most +/-30px, so signed low-six-bit deltas
    // preserve the exact local coordinate without a full 14-bit subtractor.
    wire signed [5:0] dx_local = $signed(s0_x[5:0]-s0_cx[5:0]);
    wire signed [5:0] dy_local = $signed(s0_y[5:0]-s0_cy[5:0]);
    wire [5:0] dx_abs_local = dx_local[5] ? -dx_local : dx_local;
    wire [5:0] dy_abs_local = dy_local[5] ? -dy_local : dy_local;
    wire [12:0] dx_square = {7'd0,dx_abs_local} * {7'd0,dx_abs_local};
    wire [12:0] dy_square = {7'd0,dy_abs_local} * {7'd0,dy_abs_local};

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
            s1_dx     <= dx_local;
            s1_dy     <= dy_local;
            s1_dx_abs <= dx_abs_local;
            s1_dy_abs <= dy_abs_local;
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

    // Stage three captures font coverage and geometric classification.
    // RGB blending is isolated in stage four, matching the ENV layer.
    reg body_hit;
    reg [23:0] body_rgb;
    always @(*) begin
        body_hit=1;body_rgb=`COLOR_PANEL_BG;
        if(hit_tick) body_rgb=24'h9FAEC2;
        else if(hit_needle && !(is_row0 ?
            (s1_dy>=6'sd2 && s1_dy<=6'sd8 && s1_dx_abs<=6'd6) : value_area))
            body_rgb=`COLOR_KNOB_NEEDLE;
        else if(hit_halo || hit_arc) body_rgb=`COLOR_KNOB_ARC;
        else if(s1_r2<=r_limit2 && s1_r2>=bezel_inner2) body_rgb=`COLOR_KNOB_BEZEL;
        else if(s1_r2<bezel_inner2) body_rgb=`COLOR_KNOB_BODY;
        else body_hit=0;
    end
    reg active2,selected2,label_border2,label_box2,body_hit2;
    reg [1:0] font_coverage2,value_coverage2;
    reg [23:0] body_rgb2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active2<=0;selected2<=0;label_border2<=0;label_box2<=0;body_hit2<=0;
            font_coverage2<=0;value_coverage2<=0;body_rgb2<=0;
        end else begin
            active2<=s1_active;selected2<=s1_selected;
            label_border2<=on_lbl_border;label_box2<=in_lbl_box;
            body_hit2<=body_hit;body_rgb2<=body_rgb;
            font_coverage2<=font_coverage;value_coverage2<=value_coverage;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin out_hit_knob<=0;out_knob_rgb<=0;end
        else begin
            out_hit_knob<=0;out_knob_rgb<=`COLOR_PANEL_BG;
            if(active2) begin
                if(font_coverage2!=0) begin
                    out_hit_knob<=1;
                    out_knob_rgb<=blend_rgb_q4(selected2 ? 24'h00FFFF : 24'hFFFFFF,
                        24'h101720,font_alpha_q4(font_coverage2));
                end else if(label_border2) begin
                    out_hit_knob<=1;out_knob_rgb<=selected2 ? 24'h00D0FF : 24'h2E3D4E;
                end else if(label_box2) begin
                    out_hit_knob<=1;out_knob_rgb<=24'h101720;
                end else if(value_coverage2!=0) begin
                    out_hit_knob<=1;
                    out_knob_rgb<=blend_rgb_q4(24'hF0F4FF,`COLOR_KNOB_BODY,font_alpha_q4(value_coverage2));
                end else if(body_hit2) begin
                    out_hit_knob<=1;out_knob_rgb<=body_rgb2;
                end
            end
        end
    end
endmodule
