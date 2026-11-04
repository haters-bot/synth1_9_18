// ==============================================================================
// Module: button_vector_unit.v
// Description: Fully Pipelined Procedural Vector Renderer for Synthesizer Buttons,
//              Switches, Routing Checkboxes, Tabs, Steppers & Badges.
//              - Pure coordinate geometry, zero BRAM, zero ROM bitmaps.
//              - 3-Stage Pipeline (aligned with the other raster layers):
//                Stage 0: Spatial box identification & border decoding
//                Stage 1: Per-element glyph drawing, level meter fills & color shading
//                Stage 2: Caption coverage / background compositing
//              - High-fidelity iconography: Power arcs, Chevrons, Stepper glyphs,
//                Filter routing badges, Envelope tabs, and Matrix LEDs.
//              - Instant tactile visual feedback with active flash highlights.
//              - Timing must be checked in the full project after UI edits.
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"

module button_vector_unit (
    input  wire        clk,
    input  wire        rst_n,

    // Video raster beam coordinates
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // Button / Switch States from param_merger
    input  wire        val_osca_power,
    input  wire        val_oscb_power,
    input  wire        val_flt_power,
    input  wire [2:0]  val_osca_wave,
    input  wire [2:0]  val_oscb_wave,
    input  wire [3:0]  val_osca_oct,
    input  wire [4:0]  val_osca_semi,
    input  wire [6:0]  val_osca_fine,
    input  wire [3:0]  val_oscb_oct,
    input  wire [4:0]  val_oscb_semi,
    input  wire [6:0]  val_oscb_fine,
    input  wire [1:0]  val_flt_type,
    input  wire        val_flt_route_a,
    input  wire        val_flt_route_b,
    input  wire        val_flt_route_n,
    input  wire        val_flt_route_s,
    input  wire        val_flt_keytrack,
    input  wire [1:0]  val_env_tab,
    input  wire [3:0]  val_slot_bypass,

    // Active touched / tapped control IDs
    input  wire [7:0]  selected_param_id,
    input  wire [7:0]  active_btn_id,
    input  wire        btn_flash_active,

    // Output pixel hit and RGB
    output reg         out_hit_btn,
    output reg  [23:0] out_btn_rgb
);

    // --------------------------------------------------------------------------
    // Element Enums (6-bit)
    // --------------------------------------------------------------------------
    localparam ELEM_NONE       = 6'd0;
    localparam ELEM_OSCA_PWR   = 6'd1;
    localparam ELEM_OSCB_PWR   = 6'd2;
    localparam ELEM_FLT_PWR    = 6'd3;
    localparam ELEM_OSCA_PREV  = 6'd4;
    localparam ELEM_OSCA_NEXT  = 6'd5;
    localparam ELEM_OSCA_BAR   = 6'd6;
    localparam ELEM_OSCB_PREV  = 6'd7;
    localparam ELEM_OSCB_NEXT  = 6'd8;
    localparam ELEM_OSCB_BAR   = 6'd9;
    localparam ELEM_FLT_PREV   = 6'd10;
    localparam ELEM_FLT_NEXT   = 6'd11;
    localparam ELEM_FLT_BAR    = 6'd12;
    localparam ELEM_OSCA_OCT_M = 6'd13;
    localparam ELEM_OSCA_OCT_P = 6'd14;
    localparam ELEM_OSCA_OCT_B = 6'd15;
    localparam ELEM_OSCA_SEM_M = 6'd16;
    localparam ELEM_OSCA_SEM_P = 6'd17;
    localparam ELEM_OSCA_SEM_B = 6'd18;
    localparam ELEM_OSCA_FIN_M = 6'd19;
    localparam ELEM_OSCA_FIN_P = 6'd20;
    localparam ELEM_OSCA_FIN_B = 6'd21;
    localparam ELEM_OSCB_OCT_M = 6'd22;
    localparam ELEM_OSCB_OCT_P = 6'd23;
    localparam ELEM_OSCB_OCT_B = 6'd24;
    localparam ELEM_OSCB_SEM_M = 6'd25;
    localparam ELEM_OSCB_SEM_P = 6'd26;
    localparam ELEM_OSCB_SEM_B = 6'd27;
    localparam ELEM_OSCB_FIN_M = 6'd28;
    localparam ELEM_OSCB_FIN_P = 6'd29;
    localparam ELEM_OSCB_FIN_B = 6'd30;
    localparam ELEM_FLT_CHK_A  = 6'd31;
    localparam ELEM_FLT_CHK_B  = 6'd32;
    localparam ELEM_FLT_CHK_N  = 6'd33;
    localparam ELEM_FLT_CHK_S  = 6'd34;
    localparam ELEM_FLT_CHK_K  = 6'd35;
    localparam ELEM_ENV_TAB1   = 6'd36;
    localparam ELEM_ENV_TAB2   = 6'd37;
    localparam ELEM_ENV_TAB3   = 6'd38;
    localparam ELEM_SLOT1_PWR  = 6'd39;
    localparam ELEM_SLOT2_PWR  = 6'd40;
    localparam ELEM_SLOT3_PWR  = 6'd41;
    localparam ELEM_SLOT4_PWR  = 6'd42;
    localparam ELEM_TOP_HUD    = 6'd43;

    // --------------------------------------------------------------------------
    // Geometry Helper Functions
    // --------------------------------------------------------------------------
    function in_box;
        input [13:0] px, py, x0, x1, y0, y1;
        begin
            in_box = (px >= x0) && (px <= x1) && (py >= y0) && (py <= y1);
        end
    endfunction

    // Every caller is already guarded by its in_box wire, so the range
    // comparisons are redundant. Equality-only borders shorten the pixel-Y
    // path while preserving the exact raster result.
    function on_box_border;
        input [13:0] px, py, x0, x1, y0, y1;
        begin
            on_box_border = (px == x0) || (px == x1) ||
                            (py == y0) || (py == y1);
        end
    endfunction

    // --------------------------------------------------------------------------
    // Stage 0: Spatial Box Identification & Border Detection (Cycle 1)
    // --------------------------------------------------------------------------
    // Local geometry should not share a distant register with every panel.
    reg [13:0] s0_x /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] s0_y /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [5:0]  s0_elem;
    reg        s0_hit;
    reg        s0_border;

    // Bounding Box Test Wires
    wire in_osca_pwr = in_box(in_x, in_y, 14'd36,  14'd52,  14'd52, 14'd68);
    wire in_oscb_pwr = in_box(in_x, in_y, 14'd452, 14'd468, 14'd52, 14'd68);
    wire in_flt_pwr  = in_box(in_x, in_y, 14'd868, 14'd884, 14'd52, 14'd68);

    wire in_osca_prev = in_box(in_x, in_y, 14'd372, 14'd386, 14'd52, 14'd68);
    wire in_osca_next = in_box(in_x, in_y, 14'd394, 14'd408, 14'd52, 14'd68);
    wire in_osca_bar  = in_box(in_x, in_y, 14'd58,  14'd366, 14'd52, 14'd68);

    wire in_oscb_prev = in_box(in_x, in_y, 14'd788, 14'd802, 14'd52, 14'd68);
    wire in_oscb_next = in_box(in_x, in_y, 14'd810, 14'd824, 14'd52, 14'd68);
    wire in_oscb_bar  = in_box(in_x, in_y, 14'd474, 14'd782, 14'd52, 14'd68);

    wire in_flt_prev  = in_box(in_x, in_y, 14'd1204, 14'd1218, 14'd52, 14'd68);
    wire in_flt_next  = in_box(in_x, in_y, 14'd1226, 14'd1240, 14'd52, 14'd68);
    wire in_flt_bar   = in_box(in_x, in_y, 14'd890,  14'd1198, 14'd52, 14'd68);

    wire in_osca_oct_m = in_box(in_x, in_y, 14'd36,  14'd52,  14'd74, 14'd96);
    wire in_osca_oct_p = in_box(in_x, in_y, 14'd104, 14'd120, 14'd74, 14'd96);
    wire in_osca_oct_b = in_box(in_x, in_y, 14'd54,  14'd102, 14'd74, 14'd96);

    wire in_osca_sem_m = in_box(in_x, in_y, 14'd130, 14'd146, 14'd74, 14'd96);
    wire in_osca_sem_p = in_box(in_x, in_y, 14'd198, 14'd214, 14'd74, 14'd96);
    wire in_osca_sem_b = in_box(in_x, in_y, 14'd148, 14'd196, 14'd74, 14'd96);

    wire in_osca_fin_m = in_box(in_x, in_y, 14'd224, 14'd240, 14'd74, 14'd96);
    wire in_osca_fin_p = in_box(in_x, in_y, 14'd292, 14'd308, 14'd74, 14'd96);
    wire in_osca_fin_b = in_box(in_x, in_y, 14'd242, 14'd290, 14'd74, 14'd96);

    wire in_oscb_oct_m = in_box(in_x, in_y, 14'd452, 14'd468, 14'd74, 14'd96);
    wire in_oscb_oct_p = in_box(in_x, in_y, 14'd520, 14'd536, 14'd74, 14'd96);
    wire in_oscb_oct_b = in_box(in_x, in_y, 14'd470, 14'd518, 14'd74, 14'd96);

    wire in_oscb_sem_m = in_box(in_x, in_y, 14'd546, 14'd562, 14'd74, 14'd96);
    wire in_oscb_sem_p = in_box(in_x, in_y, 14'd614, 14'd630, 14'd74, 14'd96);
    wire in_oscb_sem_b = in_box(in_x, in_y, 14'd564, 14'd612, 14'd74, 14'd96);

    wire in_oscb_fin_m = in_box(in_x, in_y, 14'd640, 14'd656, 14'd74, 14'd96);
    wire in_oscb_fin_p = in_box(in_x, in_y, 14'd708, 14'd724, 14'd74, 14'd96);
    wire in_oscb_fin_b = in_box(in_x, in_y, 14'd658, 14'd706, 14'd74, 14'd96);

    wire in_flt_chk_a = in_box(in_x, in_y, 14'd868, 14'd896, 14'd248, 14'd264);
    wire in_flt_chk_b = in_box(in_x, in_y, 14'd868, 14'd896, 14'd270, 14'd286);
    wire in_flt_chk_n = in_box(in_x, in_y, 14'd868, 14'd896, 14'd292, 14'd308);
    wire in_flt_chk_s = in_box(in_x, in_y, 14'd868, 14'd896, 14'd314, 14'd330);
    wire in_flt_chk_k = in_box(in_x, in_y, 14'd868, 14'd896, 14'd336, 14'd352);

    wire in_env_tab1 = in_box(in_x, in_y, 14'd36,  14'd120, 14'd372, 14'd396);
    wire in_env_tab2 = in_box(in_x, in_y, 14'd126, 14'd210, 14'd372, 14'd396);
    wire in_env_tab3 = in_box(in_x, in_y, 14'd216, 14'd300, 14'd372, 14'd396);

    wire in_slot1_pwr = in_box(in_x, in_y, 14'd808, 14'd824, 14'd412, 14'd428);
    wire in_slot2_pwr = in_box(in_x, in_y, 14'd808, 14'd824, 14'd446, 14'd462);
    wire in_slot3_pwr = in_box(in_x, in_y, 14'd808, 14'd824, 14'd480, 14'd496);
    wire in_slot4_pwr = in_box(in_x, in_y, 14'd808, 14'd824, 14'd514, 14'd530);

    wire in_top_hud = in_box(in_x, in_y, 14'd520, 14'd760, 14'd10, 14'd32);
    wire y_top_hud = (in_y >= 14'd10 && in_y <= 14'd32);
    wire y_band2 = (in_y >= 14'd52 && in_y <= 14'd68);
    wire y_band3 = (in_y >= 14'd74 && in_y <= 14'd96);
    wire y_band4 = (in_y >= 14'd248 && in_y <= 14'd352);
    wire y_band5 = (in_y >= 14'd372 && in_y <= 14'd396);
    wire y_band6 = (in_y >= 14'd412 && in_y <= 14'd530);

    // Mutually exclusive button rectangles: parallel hit/border decode.
    // No priority mux is needed because none of the 42 boxes overlap.
    wire [41:0] button_hits;
    wire [41:0] button_borders;
    wire [5:0] button_ids[0:41];
    assign button_hits[0]=in_osca_pwr;
    assign button_borders[0]=in_osca_pwr && on_box_border(in_x, in_y, 14'd36, 14'd52, 14'd52, 14'd68);
    assign button_ids[0]=in_osca_pwr ? ELEM_OSCA_PWR : ELEM_NONE;
    assign button_hits[1]=in_osca_prev;
    assign button_borders[1]=in_osca_prev && on_box_border(in_x, in_y, 14'd372, 14'd386, 14'd52, 14'd68);
    assign button_ids[1]=in_osca_prev ? ELEM_OSCA_PREV : ELEM_NONE;
    assign button_hits[2]=in_osca_next;
    assign button_borders[2]=in_osca_next && on_box_border(in_x, in_y, 14'd394, 14'd408, 14'd52, 14'd68);
    assign button_ids[2]=in_osca_next ? ELEM_OSCA_NEXT : ELEM_NONE;
    assign button_hits[3]=in_osca_bar;
    assign button_borders[3]=in_osca_bar && on_box_border(in_x, in_y, 14'd58, 14'd366, 14'd52, 14'd68);
    assign button_ids[3]=in_osca_bar ? ELEM_OSCA_BAR : ELEM_NONE;
    assign button_hits[4]=in_oscb_pwr;
    assign button_borders[4]=in_oscb_pwr && on_box_border(in_x, in_y, 14'd452, 14'd468, 14'd52, 14'd68);
    assign button_ids[4]=in_oscb_pwr ? ELEM_OSCB_PWR : ELEM_NONE;
    assign button_hits[5]=in_oscb_prev;
    assign button_borders[5]=in_oscb_prev && on_box_border(in_x, in_y, 14'd788, 14'd802, 14'd52, 14'd68);
    assign button_ids[5]=in_oscb_prev ? ELEM_OSCB_PREV : ELEM_NONE;
    assign button_hits[6]=in_oscb_next;
    assign button_borders[6]=in_oscb_next && on_box_border(in_x, in_y, 14'd810, 14'd824, 14'd52, 14'd68);
    assign button_ids[6]=in_oscb_next ? ELEM_OSCB_NEXT : ELEM_NONE;
    assign button_hits[7]=in_oscb_bar;
    assign button_borders[7]=in_oscb_bar && on_box_border(in_x, in_y, 14'd474, 14'd782, 14'd52, 14'd68);
    assign button_ids[7]=in_oscb_bar ? ELEM_OSCB_BAR : ELEM_NONE;
    assign button_hits[8]=in_flt_pwr;
    assign button_borders[8]=in_flt_pwr && on_box_border(in_x, in_y, 14'd868, 14'd884, 14'd52, 14'd68);
    assign button_ids[8]=in_flt_pwr ? ELEM_FLT_PWR : ELEM_NONE;
    assign button_hits[9]=in_flt_prev;
    assign button_borders[9]=in_flt_prev && on_box_border(in_x, in_y, 14'd1204, 14'd1218, 14'd52, 14'd68);
    assign button_ids[9]=in_flt_prev ? ELEM_FLT_PREV : ELEM_NONE;
    assign button_hits[10]=in_flt_next;
    assign button_borders[10]=in_flt_next && on_box_border(in_x, in_y, 14'd1226, 14'd1240, 14'd52, 14'd68);
    assign button_ids[10]=in_flt_next ? ELEM_FLT_NEXT : ELEM_NONE;
    assign button_hits[11]=in_flt_bar;
    assign button_borders[11]=in_flt_bar && on_box_border(in_x, in_y, 14'd890, 14'd1198, 14'd52, 14'd68);
    assign button_ids[11]=in_flt_bar ? ELEM_FLT_BAR : ELEM_NONE;
    assign button_hits[12]=in_osca_oct_m;
    assign button_borders[12]=in_osca_oct_m && on_box_border(in_x, in_y, 14'd36, 14'd52, 14'd74, 14'd96);
    assign button_ids[12]=in_osca_oct_m ? ELEM_OSCA_OCT_M : ELEM_NONE;
    assign button_hits[13]=in_osca_oct_p;
    assign button_borders[13]=in_osca_oct_p && on_box_border(in_x, in_y, 14'd104, 14'd120, 14'd74, 14'd96);
    assign button_ids[13]=in_osca_oct_p ? ELEM_OSCA_OCT_P : ELEM_NONE;
    assign button_hits[14]=in_osca_oct_b;
    assign button_borders[14]=in_osca_oct_b && on_box_border(in_x, in_y, 14'd54, 14'd102, 14'd74, 14'd96);
    assign button_ids[14]=in_osca_oct_b ? ELEM_OSCA_OCT_B : ELEM_NONE;
    assign button_hits[15]=in_osca_sem_m;
    assign button_borders[15]=in_osca_sem_m && on_box_border(in_x, in_y, 14'd130, 14'd146, 14'd74, 14'd96);
    assign button_ids[15]=in_osca_sem_m ? ELEM_OSCA_SEM_M : ELEM_NONE;
    assign button_hits[16]=in_osca_sem_p;
    assign button_borders[16]=in_osca_sem_p && on_box_border(in_x, in_y, 14'd198, 14'd214, 14'd74, 14'd96);
    assign button_ids[16]=in_osca_sem_p ? ELEM_OSCA_SEM_P : ELEM_NONE;
    assign button_hits[17]=in_osca_sem_b;
    assign button_borders[17]=in_osca_sem_b && on_box_border(in_x, in_y, 14'd148, 14'd196, 14'd74, 14'd96);
    assign button_ids[17]=in_osca_sem_b ? ELEM_OSCA_SEM_B : ELEM_NONE;
    assign button_hits[18]=in_osca_fin_m;
    assign button_borders[18]=in_osca_fin_m && on_box_border(in_x, in_y, 14'd224, 14'd240, 14'd74, 14'd96);
    assign button_ids[18]=in_osca_fin_m ? ELEM_OSCA_FIN_M : ELEM_NONE;
    assign button_hits[19]=in_osca_fin_p;
    assign button_borders[19]=in_osca_fin_p && on_box_border(in_x, in_y, 14'd292, 14'd308, 14'd74, 14'd96);
    assign button_ids[19]=in_osca_fin_p ? ELEM_OSCA_FIN_P : ELEM_NONE;
    assign button_hits[20]=in_osca_fin_b;
    assign button_borders[20]=in_osca_fin_b && on_box_border(in_x, in_y, 14'd242, 14'd290, 14'd74, 14'd96);
    assign button_ids[20]=in_osca_fin_b ? ELEM_OSCA_FIN_B : ELEM_NONE;
    assign button_hits[21]=in_oscb_oct_m;
    assign button_borders[21]=in_oscb_oct_m && on_box_border(in_x, in_y, 14'd452, 14'd468, 14'd74, 14'd96);
    assign button_ids[21]=in_oscb_oct_m ? ELEM_OSCB_OCT_M : ELEM_NONE;
    assign button_hits[22]=in_oscb_oct_p;
    assign button_borders[22]=in_oscb_oct_p && on_box_border(in_x, in_y, 14'd520, 14'd536, 14'd74, 14'd96);
    assign button_ids[22]=in_oscb_oct_p ? ELEM_OSCB_OCT_P : ELEM_NONE;
    assign button_hits[23]=in_oscb_oct_b;
    assign button_borders[23]=in_oscb_oct_b && on_box_border(in_x, in_y, 14'd470, 14'd518, 14'd74, 14'd96);
    assign button_ids[23]=in_oscb_oct_b ? ELEM_OSCB_OCT_B : ELEM_NONE;
    assign button_hits[24]=in_oscb_sem_m;
    assign button_borders[24]=in_oscb_sem_m && on_box_border(in_x, in_y, 14'd546, 14'd562, 14'd74, 14'd96);
    assign button_ids[24]=in_oscb_sem_m ? ELEM_OSCB_SEM_M : ELEM_NONE;
    assign button_hits[25]=in_oscb_sem_p;
    assign button_borders[25]=in_oscb_sem_p && on_box_border(in_x, in_y, 14'd614, 14'd630, 14'd74, 14'd96);
    assign button_ids[25]=in_oscb_sem_p ? ELEM_OSCB_SEM_P : ELEM_NONE;
    assign button_hits[26]=in_oscb_sem_b;
    assign button_borders[26]=in_oscb_sem_b && on_box_border(in_x, in_y, 14'd564, 14'd612, 14'd74, 14'd96);
    assign button_ids[26]=in_oscb_sem_b ? ELEM_OSCB_SEM_B : ELEM_NONE;
    assign button_hits[27]=in_oscb_fin_m;
    assign button_borders[27]=in_oscb_fin_m && on_box_border(in_x, in_y, 14'd640, 14'd656, 14'd74, 14'd96);
    assign button_ids[27]=in_oscb_fin_m ? ELEM_OSCB_FIN_M : ELEM_NONE;
    assign button_hits[28]=in_oscb_fin_p;
    assign button_borders[28]=in_oscb_fin_p && on_box_border(in_x, in_y, 14'd708, 14'd724, 14'd74, 14'd96);
    assign button_ids[28]=in_oscb_fin_p ? ELEM_OSCB_FIN_P : ELEM_NONE;
    assign button_hits[29]=in_oscb_fin_b;
    assign button_borders[29]=in_oscb_fin_b && on_box_border(in_x, in_y, 14'd658, 14'd706, 14'd74, 14'd96);
    assign button_ids[29]=in_oscb_fin_b ? ELEM_OSCB_FIN_B : ELEM_NONE;
    assign button_hits[30]=in_flt_chk_a;
    assign button_borders[30]=in_flt_chk_a && on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd248, 14'd264);
    assign button_ids[30]=in_flt_chk_a ? ELEM_FLT_CHK_A : ELEM_NONE;
    assign button_hits[31]=in_flt_chk_b;
    assign button_borders[31]=in_flt_chk_b && on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd270, 14'd286);
    assign button_ids[31]=in_flt_chk_b ? ELEM_FLT_CHK_B : ELEM_NONE;
    assign button_hits[32]=in_flt_chk_n;
    assign button_borders[32]=in_flt_chk_n && on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd292, 14'd308);
    assign button_ids[32]=in_flt_chk_n ? ELEM_FLT_CHK_N : ELEM_NONE;
    assign button_hits[33]=in_flt_chk_s;
    assign button_borders[33]=in_flt_chk_s && on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd314, 14'd330);
    assign button_ids[33]=in_flt_chk_s ? ELEM_FLT_CHK_S : ELEM_NONE;
    assign button_hits[34]=in_flt_chk_k;
    assign button_borders[34]=in_flt_chk_k && on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd336, 14'd352);
    assign button_ids[34]=in_flt_chk_k ? ELEM_FLT_CHK_K : ELEM_NONE;
    assign button_hits[35]=in_env_tab1;
    assign button_borders[35]=in_env_tab1 && on_box_border(in_x, in_y, 14'd36, 14'd120, 14'd372, 14'd396);
    assign button_ids[35]=in_env_tab1 ? ELEM_ENV_TAB1 : ELEM_NONE;
    assign button_hits[36]=in_env_tab2;
    assign button_borders[36]=in_env_tab2 && on_box_border(in_x, in_y, 14'd126, 14'd210, 14'd372, 14'd396);
    assign button_ids[36]=in_env_tab2 ? ELEM_ENV_TAB2 : ELEM_NONE;
    assign button_hits[37]=in_env_tab3;
    assign button_borders[37]=in_env_tab3 && on_box_border(in_x, in_y, 14'd216, 14'd300, 14'd372, 14'd396);
    assign button_ids[37]=in_env_tab3 ? ELEM_ENV_TAB3 : ELEM_NONE;
    assign button_hits[38]=in_slot1_pwr;
    assign button_borders[38]=in_slot1_pwr && on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd412, 14'd428);
    assign button_ids[38]=in_slot1_pwr ? ELEM_SLOT1_PWR : ELEM_NONE;
    assign button_hits[39]=in_slot2_pwr;
    assign button_borders[39]=in_slot2_pwr && on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd446, 14'd462);
    assign button_ids[39]=in_slot2_pwr ? ELEM_SLOT2_PWR : ELEM_NONE;
    assign button_hits[40]=in_slot3_pwr;
    assign button_borders[40]=in_slot3_pwr && on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd480, 14'd496);
    assign button_ids[40]=in_slot3_pwr ? ELEM_SLOT3_PWR : ELEM_NONE;
    assign button_hits[41]=in_slot4_pwr;
    assign button_borders[41]=in_slot4_pwr && on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd514, 14'd530);
    assign button_ids[41]=in_slot4_pwr ? ELEM_SLOT4_PWR : ELEM_NONE;
    integer button_i;
    reg [5:0] button_id;
    always @(*) begin
        button_id=ELEM_NONE;
        for(button_i=0;button_i<42;button_i=button_i+1)
            button_id=button_id|button_ids[button_i];
    end
    always @(posedge clk) begin
        s0_x<=in_x;s0_y<=in_y;
        s0_hit<=|button_hits;
        s0_elem<=button_id;
        s0_border<=|button_borders;
    end

    // --------------------------------------------------------------------------
    // Stage 1: Procedural Glyphs & Color Shading (Cycle 2)
    // --------------------------------------------------------------------------
    // Multiplier-free geometric power icon centered at (xc, yc=60)
    function is_power_glyph;
        input [13:0] px, py, xc;
        reg signed [4:0] local_x,local_y;
        reg [4:0] dx, dy;
        begin
            // Called only inside the matching 17x17 power-button cell.
            local_x=px[4:0]-xc[4:0];local_y=py[4:0]-5'd28;
            dx=local_x[4] ? -local_x : local_x;
            dy=local_y[4] ? -local_y : local_y;
            is_power_glyph = ((dx <= 4'd4) && (dy <= 4'd4) &&
                              ((dx + dy) >= 4'd3) && ((dx + dy) <= 4'd5) &&
                              ((py > 14'd58) || (dx > 4'd1))) ||
                             ((px == xc) && (py >= 14'd56) && (py <= 14'd60));
        end
    endfunction

    // Chevron arrow <
    function is_arrow_left;
        input [13:0] px, py, xc;
        reg signed [4:0] dx,local_y;
        reg [4:0] dy;
        begin
            dx=xc[4:0]-px[4:0];local_y=py[4:0]-5'd28;
            dy=local_y[4] ? -local_y : local_y;
            is_arrow_left = ((dx == dy) || (dx == (dy + 5'd1))) && (dx >= 5'sd1) && (dx <= 5'sd5);
        end
    endfunction

    // Chevron arrow >
    function is_arrow_right;
        input [13:0] px, py, xc;
        reg signed [4:0] dx,local_y;
        reg [4:0] dy;
        begin
            dx=px[4:0]-xc[4:0];local_y=py[4:0]-5'd28;
            dy=local_y[4] ? -local_y : local_y;
            is_arrow_right = ((dx == dy) || (dx == (dy + 5'd1))) && (dx >= 5'sd1) && (dx <= 5'sd5);
        end
    endfunction

    reg [23:0] rgb_out;

    // Parameter-dependent endpoints are independent of the raster beam.
    // Register them before the pixel comparison instead of multiplying inside
    // the final colour path. A parameter update settles within one extra clock.
    wire [13:0] meter_oct_a = 14'd58 + ({10'd0,val_osca_oct} * 14'd5);
    wire [13:0] meter_oct_b = 14'd474 + ({10'd0,val_oscb_oct} * 14'd5);
    wire [13:0] meter_sem_a = 14'd160 + {9'd0,val_osca_semi};
    wire [13:0] meter_sem_b = 14'd576 + {9'd0,val_oscb_semi};
    wire [13:0] meter_fin_a = val_osca_fine >= 64 ?
        14'd266 + ((val_osca_fine-7'd64)>>2) : 14'd266-((7'd64-val_osca_fine)>>2);
    wire [13:0] meter_fin_b = val_oscb_fine >= 64 ?
        14'd682 + ((val_oscb_fine-7'd64)>>2) : 14'd682-((7'd64-val_oscb_fine)>>2);
    reg [13:0] oct_a_lo,oct_a_hi,oct_b_lo,oct_b_hi;
    reg [13:0] sem_a_lo,sem_a_hi,sem_b_lo,sem_b_hi;
    reg [13:0] fin_a_lo,fin_a_hi,fin_b_lo,fin_b_hi;
    always @(posedge clk) begin
        oct_a_lo <= meter_oct_a < 78 ? meter_oct_a : 14'd78;
        oct_a_hi <= meter_oct_a > 78 ? meter_oct_a : 14'd78;
        oct_b_lo <= meter_oct_b < 494 ? meter_oct_b : 14'd494;
        oct_b_hi <= meter_oct_b > 494 ? meter_oct_b : 14'd494;
        sem_a_lo <= meter_sem_a < 172 ? meter_sem_a : 14'd172;
        sem_a_hi <= meter_sem_a > 172 ? meter_sem_a : 14'd172;
        sem_b_lo <= meter_sem_b < 588 ? meter_sem_b : 14'd588;
        sem_b_hi <= meter_sem_b > 588 ? meter_sem_b : 14'd588;
        fin_a_lo <= meter_fin_a < 266 ? meter_fin_a : 14'd266;
        fin_a_hi <= meter_fin_a > 266 ? meter_fin_a : 14'd266;
        fin_b_lo <= meter_fin_b < 682 ? meter_fin_b : 14'd682;
        fin_b_hi <= meter_fin_b > 682 ? meter_fin_b : 14'd682;
    end

    // Captions occupy disjoint constant boxes. Decode their glyph columns in
    // parallel instead of selecting an origin from Y and then subtracting it
    // from X before another string/column mux in the same clock.
    function [47:0] wave_caption;
        input [2:0] wave;
        begin case(wave)
            0:wave_caption={`CH_S,`CH_I,`CH_N,`CH_E,24'd0};
            1:wave_caption={`CH_S,`CH_A,`CH_W,30'd0};
            2:wave_caption={`CH_P,`CH_U,`CH_L,`CH_S,`CH_E,18'd0};
            4:wave_caption={`CH_S,`CH_D,`CH_SPACE,`CH_B,`CH_A,`CH_N,`CH_K,`CH_SPACE};
            default:wave_caption=0;
            3:wave_caption={`CH_T,`CH_R,`CH_I,`CH_A,`CH_N,`CH_G,`CH_L,`CH_E};
        endcase end
    endfunction
    function [47:0] filter_caption;
        input [1:0] mode;
        begin case(mode)
            0:filter_caption={`CH_L,`CH_O,`CH_W,`CH_P,`CH_A,`CH_S,`CH_S,6'd0};
            1:filter_caption={`CH_H,`CH_I,`CH_G,`CH_H,`CH_P,`CH_A,`CH_S,`CH_S};
            2:filter_caption={`CH_B,`CH_A,`CH_N,`CH_D,`CH_P,`CH_A,`CH_S,`CH_S};
            3:filter_caption={`CH_N,`CH_O,`CH_T,`CH_C,`CH_H,18'd0};
        endcase end
    endfunction
    function [5:0] caption_char_at;
        input [47:0] text;
        input [2:0] column;
        begin case(column)
            0:caption_char_at=text[47:42];1:caption_char_at=text[41:36];
            2:caption_char_at=text[35:30];3:caption_char_at=text[29:24];
            4:caption_char_at=text[23:18];5:caption_char_at=text[17:12];
            6:caption_char_at=text[11:6];7:caption_char_at=text[5:0];
        endcase end
    endfunction
    wire [10:0] cap_hits;
    wire [5:0] cap_chars[0:10];
    wire [2:0] cap_rxs[0:10];
    wire [3:0] cap_rys[0:10];
    genvar cap;
    generate for(cap=0;cap<11;cap=cap+1) begin: captions
        localparam [13:0] X0=cap==0 ? 52 : cap==1 ? 142 : cap==2 ? 232 :
            cap==3 ? 70 : cap==4 ? 486 : cap==5 ? 902 : 886;
        localparam [13:0] Y0=cap<3 ? 380 : cap<6 ? 56 : 252+(cap-6)*22;
        localparam [13:0] X1=cap<6 ? X0+63 : 896;
        localparam [5:0] CHECK_CHAR=cap==6 ? `CH_A : cap==7 ? `CH_B :
            cap==8 ? `CH_N : cap==9 ? `CH_S : `CH_K;
        localparam [5:0] ENV_DIGIT=`CH_1+cap;
        wire [5:0] dx=in_x[5:0]-X0[5:0];
        wire [3:0] dy=in_y[3:0]-Y0[3:0];
        wire [47:0] text=cap<3 ? {`CH_E,`CH_N,`CH_V,`CH_SPACE,ENV_DIGIT,18'd0} :
            cap==3 ? wave_caption(val_osca_wave) : cap==4 ? wave_caption(val_oscb_wave) :
            cap==5 ? filter_caption(val_flt_type) : {CHECK_CHAR,42'd0};
        wire active=in_x>=X0 && in_x<=X1 && in_y>=Y0 && in_y<Y0+14'd10 && dx[2:0]<7;
        assign cap_hits[cap]=active;
        assign cap_chars[cap]=active ? caption_char_at(text,dx[5:3]) : 6'd0;
        assign cap_rxs[cap]=active ? dx[2:0] : 3'd0;
        assign cap_rys[cap]=active ? dy : 4'd0;
    end endgenerate
    integer cap_i;
    reg [5:0] caption_ch;
    reg [2:0] caption_rx;
    reg [3:0] caption_ry;
    always @(*) begin
        caption_ch=0;caption_rx=0;caption_ry=0;
        for(cap_i=0;cap_i<11;cap_i=cap_i+1) begin
            caption_ch=caption_ch|cap_chars[cap_i];
            caption_rx=caption_rx|cap_rxs[cap_i];caption_ry=caption_ry|cap_rys[cap_i];
        end
    end
    reg caption_valid;
    reg [5:0] caption_ch_reg;
    reg [2:0] caption_rx_reg;
    reg [3:0] caption_ry_reg;
    always @(posedge clk) begin
        caption_valid <= |cap_hits;
        caption_ch_reg <= caption_ch;
        caption_rx_reg <= caption_rx;
        caption_ry_reg <= caption_ry;
    end
    wire [1:0] caption_coverage = caption_valid ?
        get_font_7x10(caption_ch_reg, caption_rx_reg, caption_ry_reg) : 2'd0;

    // Specialize each element at elaboration, so grouped badge/icon cases
    // cannot retain a serial element selector inside the pixel color logic.
    function [23:0] element_rgb;
        input [5:0] element;
        input [13:0] px,py;
        input border;
        begin
        element_rgb = 24'h0;

        case (element)
            // Power Buttons
            ELEM_OSCA_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_POWER) ? 24'hFFFFFF :
                              (val_osca_power ? `COLOR_TEXT_ACCENT : `COLOR_BTN_BORDER);
                else if (is_power_glyph(px, py, 14'd44))
                    element_rgb = val_osca_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    element_rgb = val_osca_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_POWER) ? 24'hFFFFFF :
                              (val_oscb_power ? `COLOR_OSCB_LINE : `COLOR_BTN_BORDER);
                else if (is_power_glyph(px, py, 14'd460))
                    element_rgb = val_oscb_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    element_rgb = val_oscb_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_POWER) ? 24'hFFFFFF :
                              (val_flt_power ? `COLOR_FLT_LINE : `COLOR_BTN_BORDER);
                else if (is_power_glyph(px, py, 14'd876))
                    element_rgb = val_flt_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    element_rgb = val_flt_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            // Preset Selectors & Waves
            ELEM_OSCA_PREV: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(px, py, 14'd380))
                    element_rgb = `COLOR_TEXT_ACCENT;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCA_NEXT: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(px, py, 14'd400))
                    element_rgb = `COLOR_TEXT_ACCENT;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCA_BAR: begin
                if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else if (py >= 14'd58 && py <= 14'd62 &&
                         ((px >= 14'd278 && px <= 14'd282) ||
                          (px >= 14'd290 && px <= 14'd294) ||
                          (px >= 14'd302 && px <= 14'd306) ||
                          (px >= 14'd314 && px <= 14'd318))) begin
                    if ((val_osca_wave == 2'd0 && px <= 14'd282) ||
                        (val_osca_wave == 2'd1 && px >= 14'd290 && px <= 14'd294) ||
                        (val_osca_wave == 2'd2 && px >= 14'd302 && px <= 14'd306) ||
                        (val_osca_wave == 2'd3 && px >= 14'd314))
                        element_rgb = `COLOR_TEXT_ACCENT;
                    else
                        element_rgb = 24'h323E50;
                end else
                    element_rgb = `COLOR_BADGE_BG;
            end

            ELEM_OSCB_PREV: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(px, py, 14'd796))
                    element_rgb = `COLOR_OSCB_LINE;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_NEXT: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(px, py, 14'd816))
                    element_rgb = `COLOR_OSCB_LINE;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_BAR: begin
                if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else if (py >= 14'd58 && py <= 14'd62 &&
                         ((px >= 14'd696 && px <= 14'd700) ||
                          (px >= 14'd708 && px <= 14'd712) ||
                          (px >= 14'd720 && px <= 14'd724) ||
                          (px >= 14'd732 && px <= 14'd736))) begin
                    if ((val_oscb_wave == 2'd0 && px <= 14'd700) ||
                        (val_oscb_wave == 2'd1 && px >= 14'd708 && px <= 14'd712) ||
                        (val_oscb_wave == 2'd2 && px >= 14'd720 && px <= 14'd724) ||
                        (val_oscb_wave == 2'd3 && px >= 14'd732))
                        element_rgb = `COLOR_OSCB_LINE;
                    else
                        element_rgb = 24'h323E50;
                end else
                    element_rgb = `COLOR_BADGE_BG;
            end

            ELEM_FLT_PREV: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_TYPE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(px, py, 14'd1212))
                    element_rgb = `COLOR_FLT_LINE;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_NEXT: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_TYPE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(px, py, 14'd1232))
                    element_rgb = `COLOR_FLT_LINE;
                else
                    element_rgb = `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_BAR: begin
                if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else if (py >= 14'd58 && py <= 14'd62 &&
                         ((px >= 14'd1112 && px <= 14'd1116) ||
                          (px >= 14'd1124 && px <= 14'd1128) ||
                          (px >= 14'd1136 && px <= 14'd1140) ||
                          (px >= 14'd1148 && px <= 14'd1152))) begin
                    if ((val_flt_type == 2'd0 && px <= 14'd1116) ||
                        (val_flt_type == 2'd1 && px >= 14'd1124 && px <= 14'd1128) ||
                        (val_flt_type == 2'd2 && px >= 14'd1136 && px <= 14'd1140) ||
                        (val_flt_type == 2'd3 && px >= 14'd1148))
                        element_rgb = `COLOR_FLT_LINE;
                    else
                        element_rgb = 24'h323E50;
                end else
                    element_rgb = `COLOR_BADGE_BG;
            end

            // Stepper Minus Buttons [-]
            ELEM_OSCA_OCT_M, ELEM_OSCA_SEM_M, ELEM_OSCA_FIN_M,
            ELEM_OSCB_OCT_M, ELEM_OSCB_SEM_M, ELEM_OSCB_FIN_M: begin
                if (border) begin
                    if (btn_flash_active &&
                        ((element == ELEM_OSCA_OCT_M && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (element == ELEM_OSCA_SEM_M && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (element == ELEM_OSCA_FIN_M && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (element == ELEM_OSCB_OCT_M && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (element == ELEM_OSCB_SEM_M && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (element == ELEM_OSCB_FIN_M && active_btn_id == `PARAM_ID_OSCB_FINE)))
                        element_rgb = 24'hFFFFFF;
                    else
                        element_rgb = `COLOR_BTN_BORDER;
                end else if (py >= 14'd84 && py <= 14'd86 &&
                    ((element == ELEM_OSCA_OCT_M && px >= 14'd40  && px <= 14'd48)  ||
                     (element == ELEM_OSCA_SEM_M && px >= 14'd134 && px <= 14'd142) ||
                     (element == ELEM_OSCA_FIN_M && px >= 14'd228 && px <= 14'd236) ||
                     (element == ELEM_OSCB_OCT_M && px >= 14'd456 && px <= 14'd464) ||
                     (element == ELEM_OSCB_SEM_M && px >= 14'd550 && px <= 14'd558) ||
                     (element == ELEM_OSCB_FIN_M && px >= 14'd644 && px <= 14'd652)))
                    element_rgb = 24'hFFFFFF;
                else
                    element_rgb = (btn_flash_active &&
                        ((element == ELEM_OSCA_OCT_M && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (element == ELEM_OSCA_SEM_M && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (element == ELEM_OSCA_FIN_M && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (element == ELEM_OSCB_OCT_M && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (element == ELEM_OSCB_SEM_M && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (element == ELEM_OSCB_FIN_M && active_btn_id == `PARAM_ID_OSCB_FINE))) ? `COLOR_BTN_ACTIVE_BG : 24'h222A38;
            end

            // Stepper Plus Buttons [+]
            ELEM_OSCA_OCT_P, ELEM_OSCA_SEM_P, ELEM_OSCA_FIN_P,
            ELEM_OSCB_OCT_P, ELEM_OSCB_SEM_P, ELEM_OSCB_FIN_P: begin
                if (border) begin
                    if (btn_flash_active &&
                        ((element == ELEM_OSCA_OCT_P && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (element == ELEM_OSCA_SEM_P && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (element == ELEM_OSCA_FIN_P && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (element == ELEM_OSCB_OCT_P && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (element == ELEM_OSCB_SEM_P && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (element == ELEM_OSCB_FIN_P && active_btn_id == `PARAM_ID_OSCB_FINE)))
                        element_rgb = 24'hFFFFFF;
                    else
                        element_rgb = `COLOR_BTN_BORDER;
                end else if ((py >= 14'd84 && py <= 14'd86 &&
                     ((element == ELEM_OSCA_OCT_P && px >= 14'd108 && px <= 14'd116) ||
                      (element == ELEM_OSCA_SEM_P && px >= 14'd202 && px <= 14'd210) ||
                      (element == ELEM_OSCA_FIN_P && px >= 14'd296 && px <= 14'd304) ||
                      (element == ELEM_OSCB_OCT_P && px >= 14'd524 && px <= 14'd532) ||
                      (element == ELEM_OSCB_SEM_P && px >= 14'd618 && px <= 14'd626) ||
                      (element == ELEM_OSCB_FIN_P && px >= 14'd712 && px <= 14'd720))) ||
                    (py >= 14'd80 && py <= 14'd90 &&
                     ((element == ELEM_OSCA_OCT_P && px >= 14'd111 && px <= 14'd113) ||
                      (element == ELEM_OSCA_SEM_P && px >= 14'd205 && px <= 14'd207) ||
                      (element == ELEM_OSCA_FIN_P && px >= 14'd299 && px <= 14'd301) ||
                      (element == ELEM_OSCB_OCT_P && px >= 14'd527 && px <= 14'd529) ||
                      (element == ELEM_OSCB_SEM_P && px >= 14'd621 && px <= 14'd623) ||
                      (element == ELEM_OSCB_FIN_P && px >= 14'd715 && px <= 14'd717))))
                    element_rgb = 24'hFFFFFF;
                else
                    element_rgb = (btn_flash_active &&
                        ((element == ELEM_OSCA_OCT_P && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (element == ELEM_OSCA_SEM_P && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (element == ELEM_OSCA_FIN_P && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (element == ELEM_OSCB_OCT_P && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (element == ELEM_OSCB_SEM_P && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (element == ELEM_OSCB_FIN_P && active_btn_id == `PARAM_ID_OSCB_FINE))) ? `COLOR_BTN_ACTIVE_BG : 24'h222A38;
            end

            // Stepper Value Display Badges (Middle with Bipolar Level Meters)
            ELEM_OSCA_OCT_B, ELEM_OSCA_SEM_B, ELEM_OSCA_FIN_B,
            ELEM_OSCB_OCT_B, ELEM_OSCB_SEM_B, ELEM_OSCB_FIN_B: begin
                if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else if (py >= 14'd78 && py <= 14'd92 &&
                    (px == 14'd78 || px == 14'd172 || px == 14'd266 ||
                     px == 14'd494 || px == 14'd588 || px == 14'd682))
                    element_rgb = 24'hFFFFFF;
                else if (py >= 14'd83 && py <= 14'd87) begin
                    // OSC A OCT (Center 78)
                    if (element == ELEM_OSCA_OCT_B && (px >= oct_a_lo && px <= oct_a_hi))
                        element_rgb = `COLOR_TEXT_ACCENT;
                    // OSC A SEMI (Center 172)
                    else if (element == ELEM_OSCA_SEM_B && (px >= sem_a_lo && px <= sem_a_hi))
                        element_rgb = `COLOR_TEXT_ACCENT;
                    // OSC A FINE (Center 266)
                    else if (element == ELEM_OSCA_FIN_B && (px >= fin_a_lo && px <= fin_a_hi))
                        element_rgb = `COLOR_TEXT_ACCENT;
                    // OSC B OCT (Center 494)
                    else if (element == ELEM_OSCB_OCT_B && (px >= oct_b_lo && px <= oct_b_hi))
                        element_rgb = `COLOR_OSCB_LINE;
                    // OSC B SEMI (Center 588)
                    else if (element == ELEM_OSCB_SEM_B && (px >= sem_b_lo && px <= sem_b_hi))
                        element_rgb = `COLOR_OSCB_LINE;
                    // OSC B FINE (Center 682)
                    else if (element == ELEM_OSCB_FIN_B && (px >= fin_b_lo && px <= fin_b_hi))
                        element_rgb = `COLOR_OSCB_LINE;
                    else
                        element_rgb = `COLOR_BADGE_BG;
                end else
                    element_rgb = `COLOR_BADGE_BG;
            end

            // Filter Routing Checkboxes [A], [B], [N], [S], [K]
            ELEM_FLT_CHK_A: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_A) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (px <= 14'd882)
                    element_rgb = val_flt_route_a ? `COLOR_TEXT_ACCENT : `COLOR_BTN_IDLE_BG;
                else
                    element_rgb = 24'h141E2C;
            end

            ELEM_FLT_CHK_B: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_B) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (px <= 14'd882)
                    element_rgb = val_flt_route_b ? `COLOR_OSCB_LINE : `COLOR_BTN_IDLE_BG;
                else
                    element_rgb = 24'h141E2C;
            end

            ELEM_FLT_CHK_N: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_N) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (px <= 14'd882)
                    element_rgb = val_flt_route_n ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    element_rgb = 24'h141E2C;
            end

            ELEM_FLT_CHK_S: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_S) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (px <= 14'd882)
                    element_rgb = val_flt_route_s ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    element_rgb = 24'h141E2C;
            end

            ELEM_FLT_CHK_K: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_KEYTRACK) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (px <= 14'd882)
                    element_rgb = val_flt_keytrack ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    element_rgb = 24'h141E2C;
            end

            // Envelope Modern Tabs
            ELEM_ENV_TAB1: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd0)
                    element_rgb = 24'hFFFFFF;
                else if (val_env_tab == 2'd0 && py <= 14'd374)
                    element_rgb = `COLOR_TEXT_ACCENT;
                else if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else
                    element_rgb = (val_env_tab == 2'd0) ? 24'h283850 : 24'h141822;
            end

            ELEM_ENV_TAB2: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd1)
                    element_rgb = 24'hFFFFFF;
                else if (val_env_tab == 2'd1 && py <= 14'd374)
                    element_rgb = `COLOR_TEXT_ACCENT;
                else if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else
                    element_rgb = (val_env_tab == 2'd1) ? 24'h283850 : 24'h141822;
            end

            ELEM_ENV_TAB3: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd2)
                    element_rgb = 24'hFFFFFF;
                else if (val_env_tab == 2'd2 && py <= 14'd374)
                    element_rgb = `COLOR_TEXT_ACCENT;
                else if (border)
                    element_rgb = `COLOR_BTN_BORDER;
                else
                    element_rgb = (val_env_tab == 2'd2) ? 24'h283850 : 24'h141822;
            end

            // Matrix Slot Bypass LED Switches
            ELEM_SLOT1_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT1_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    element_rgb = !val_slot_bypass[0] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT2_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT2_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    element_rgb = !val_slot_bypass[1] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT3_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT3_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    element_rgb = !val_slot_bypass[2] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT4_PWR: begin
                if (border)
                    element_rgb = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT4_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    element_rgb = !val_slot_bypass[3] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            // Top Bar HUD Indicator Banner
            ELEM_TOP_HUD: begin
                if (border)
                    element_rgb = (selected_param_id != `PARAM_ID_NONE) ? `COLOR_TEXT_ACCENT : `COLOR_BTN_BORDER;
                else if (selected_param_id != `PARAM_ID_NONE)
                    element_rgb = 24'h183454;
                else
                    element_rgb = `COLOR_BADGE_BG;
            end

            default: element_rgb = 24'h0;
        endcase
        end
    endfunction
    wire [23:0] element_colors[1:43];
    genvar element_index;
    generate for(element_index=1;element_index<=43;element_index=element_index+1) begin: colors
        localparam [5:0] ID=element_index;
        assign element_colors[element_index]=s0_elem==ID ?
            element_rgb(ID,s0_x,s0_y,s0_border) : 24'd0;
    end endgenerate
    integer color_index;
    always @(*) begin
        rgb_out=0;
        for(color_index=1;color_index<=43;color_index=color_index+1)
            rgb_out=rgb_out|element_colors[color_index];
    end

    // Register the background and coverage separately. This removes RGB
    // arithmetic from the long icon decoder and aligns this layer to 3 clocks.
    reg base_hit1;
    reg [23:0] base_rgb1;
    reg [1:0] coverage1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin base_hit1<=0;base_rgb1<=0;coverage1<=0;end
        else begin base_hit1<=s0_hit;base_rgb1<=rgb_out;coverage1<=caption_coverage;end
    end
    // Stage 2 Output Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hit_btn <= 1'b0;
            out_btn_rgb <= 24'h0;
        end else begin
            out_hit_btn <= base_hit1;
            out_btn_rgb <= blend_rgb_q4(24'hF0F4FF,base_rgb1,font_alpha_q4(coverage1));
        end
    end

endmodule
