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
    input  wire [1:0]  val_osca_wave,
    input  wire [1:0]  val_oscb_wave,
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

    function on_box_border;
        input [13:0] px, py, x0, x1, y0, y1;
        begin
            on_box_border = (((px == x0) || (px == x1)) && (py >= y0 && py <= y1)) ||
                            (((py == y0) || (py == y1)) && (px >= x0 && px <= x1));
        end
    endfunction

    // --------------------------------------------------------------------------
    // Stage 0: Spatial Box Identification & Border Detection (Cycle 1)
    // --------------------------------------------------------------------------
    reg [13:0] s0_x, s0_y;
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

    always @(posedge clk) begin
        s0_x      <= in_x;
        s0_y      <= in_y;
        s0_hit    <= 1'b1;
        s0_border <= 1'b0;
        s0_elem   <= ELEM_NONE;

        // Band 1: Top HUD (Y: 10..32) - Passthrough to ui_top_renderer for live dynamic value HUD meter
        if (in_y >= 14'd10 && in_y <= 14'd32) begin
            s0_hit <= 1'b0;
        end

        // Band 2: Power Buttons, Wave Bars & Preset Arrows (Y: 52..68)
        else if (in_y >= 14'd52 && in_y <= 14'd68) begin
            // OSC A
            if (in_osca_pwr) begin
                s0_elem   <= ELEM_OSCA_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd36, 14'd52, 14'd52, 14'd68);
            end else if (in_osca_prev) begin
                s0_elem   <= ELEM_OSCA_PREV;
                s0_border <= on_box_border(in_x, in_y, 14'd372, 14'd386, 14'd52, 14'd68);
            end else if (in_osca_next) begin
                s0_elem   <= ELEM_OSCA_NEXT;
                s0_border <= on_box_border(in_x, in_y, 14'd394, 14'd408, 14'd52, 14'd68);
            end else if (in_osca_bar) begin
                s0_elem   <= ELEM_OSCA_BAR;
                s0_border <= on_box_border(in_x, in_y, 14'd58, 14'd366, 14'd52, 14'd68);
            end
            // OSC B
            else if (in_oscb_pwr) begin
                s0_elem   <= ELEM_OSCB_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd452, 14'd468, 14'd52, 14'd68);
            end else if (in_oscb_prev) begin
                s0_elem   <= ELEM_OSCB_PREV;
                s0_border <= on_box_border(in_x, in_y, 14'd788, 14'd802, 14'd52, 14'd68);
            end else if (in_oscb_next) begin
                s0_elem   <= ELEM_OSCB_NEXT;
                s0_border <= on_box_border(in_x, in_y, 14'd810, 14'd824, 14'd52, 14'd68);
            end else if (in_oscb_bar) begin
                s0_elem   <= ELEM_OSCB_BAR;
                s0_border <= on_box_border(in_x, in_y, 14'd474, 14'd782, 14'd52, 14'd68);
            end
            // Filter
            else if (in_flt_pwr) begin
                s0_elem   <= ELEM_FLT_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd884, 14'd52, 14'd68);
            end else if (in_flt_prev) begin
                s0_elem   <= ELEM_FLT_PREV;
                s0_border <= on_box_border(in_x, in_y, 14'd1204, 14'd1218, 14'd52, 14'd68);
            end else if (in_flt_next) begin
                s0_elem   <= ELEM_FLT_NEXT;
                s0_border <= on_box_border(in_x, in_y, 14'd1226, 14'd1240, 14'd52, 14'd68);
            end else if (in_flt_bar) begin
                s0_elem   <= ELEM_FLT_BAR;
                s0_border <= on_box_border(in_x, in_y, 14'd890, 14'd1198, 14'd52, 14'd68);
            end else begin
                s0_hit <= 1'b0;
            end
        end

        // Band 3: Steppers (OCT, SEMI, FINE) (Y: 74..96)
        else if (in_y >= 14'd74 && in_y <= 14'd96) begin
            // OSC A
            if (in_osca_oct_m) begin
                s0_elem   <= ELEM_OSCA_OCT_M;
                s0_border <= on_box_border(in_x, in_y, 14'd36, 14'd52, 14'd74, 14'd96);
            end else if (in_osca_oct_p) begin
                s0_elem   <= ELEM_OSCA_OCT_P;
                s0_border <= on_box_border(in_x, in_y, 14'd104, 14'd120, 14'd74, 14'd96);
            end else if (in_osca_oct_b) begin
                s0_elem   <= ELEM_OSCA_OCT_B;
                s0_border <= on_box_border(in_x, in_y, 14'd54, 14'd102, 14'd74, 14'd96);
            end else if (in_osca_sem_m) begin
                s0_elem   <= ELEM_OSCA_SEM_M;
                s0_border <= on_box_border(in_x, in_y, 14'd130, 14'd146, 14'd74, 14'd96);
            end else if (in_osca_sem_p) begin
                s0_elem   <= ELEM_OSCA_SEM_P;
                s0_border <= on_box_border(in_x, in_y, 14'd198, 14'd214, 14'd74, 14'd96);
            end else if (in_osca_sem_b) begin
                s0_elem   <= ELEM_OSCA_SEM_B;
                s0_border <= on_box_border(in_x, in_y, 14'd148, 14'd196, 14'd74, 14'd96);
            end else if (in_osca_fin_m) begin
                s0_elem   <= ELEM_OSCA_FIN_M;
                s0_border <= on_box_border(in_x, in_y, 14'd224, 14'd240, 14'd74, 14'd96);
            end else if (in_osca_fin_p) begin
                s0_elem   <= ELEM_OSCA_FIN_P;
                s0_border <= on_box_border(in_x, in_y, 14'd292, 14'd308, 14'd74, 14'd96);
            end else if (in_osca_fin_b) begin
                s0_elem   <= ELEM_OSCA_FIN_B;
                s0_border <= on_box_border(in_x, in_y, 14'd242, 14'd290, 14'd74, 14'd96);
            end
            // OSC B
            else if (in_oscb_oct_m) begin
                s0_elem   <= ELEM_OSCB_OCT_M;
                s0_border <= on_box_border(in_x, in_y, 14'd452, 14'd468, 14'd74, 14'd96);
            end else if (in_oscb_oct_p) begin
                s0_elem   <= ELEM_OSCB_OCT_P;
                s0_border <= on_box_border(in_x, in_y, 14'd520, 14'd536, 14'd74, 14'd96);
            end else if (in_oscb_oct_b) begin
                s0_elem   <= ELEM_OSCB_OCT_B;
                s0_border <= on_box_border(in_x, in_y, 14'd470, 14'd518, 14'd74, 14'd96);
            end else if (in_oscb_sem_m) begin
                s0_elem   <= ELEM_OSCB_SEM_M;
                s0_border <= on_box_border(in_x, in_y, 14'd546, 14'd562, 14'd74, 14'd96);
            end else if (in_oscb_sem_p) begin
                s0_elem   <= ELEM_OSCB_SEM_P;
                s0_border <= on_box_border(in_x, in_y, 14'd614, 14'd630, 14'd74, 14'd96);
            end else if (in_oscb_sem_b) begin
                s0_elem   <= ELEM_OSCB_SEM_B;
                s0_border <= on_box_border(in_x, in_y, 14'd564, 14'd612, 14'd74, 14'd96);
            end else if (in_oscb_fin_m) begin
                s0_elem   <= ELEM_OSCB_FIN_M;
                s0_border <= on_box_border(in_x, in_y, 14'd640, 14'd656, 14'd74, 14'd96);
            end else if (in_oscb_fin_p) begin
                s0_elem   <= ELEM_OSCB_FIN_P;
                s0_border <= on_box_border(in_x, in_y, 14'd708, 14'd724, 14'd74, 14'd96);
            end else if (in_oscb_fin_b) begin
                s0_elem   <= ELEM_OSCB_FIN_B;
                s0_border <= on_box_border(in_x, in_y, 14'd658, 14'd706, 14'd74, 14'd96);
            end else begin
                s0_hit <= 1'b0;
            end
        end

        // Band 4: Filter Checkboxes [A], [B], [N], [S], [K] (Y: 248..352)
        else if (in_y >= 14'd248 && in_y <= 14'd352) begin
            if (in_flt_chk_a) begin
                s0_elem   <= ELEM_FLT_CHK_A;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd248, 14'd264);
            end else if (in_flt_chk_b) begin
                s0_elem   <= ELEM_FLT_CHK_B;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd270, 14'd286);
            end else if (in_flt_chk_n) begin
                s0_elem   <= ELEM_FLT_CHK_N;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd292, 14'd308);
            end else if (in_flt_chk_s) begin
                s0_elem   <= ELEM_FLT_CHK_S;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd314, 14'd330);
            end else if (in_flt_chk_k) begin
                s0_elem   <= ELEM_FLT_CHK_K;
                s0_border <= on_box_border(in_x, in_y, 14'd868, 14'd896, 14'd336, 14'd352);
            end else begin
                s0_hit <= 1'b0;
            end
        end

        // Band 5: Envelope Tabs (Y: 372..396)
        else if (in_y >= 14'd372 && in_y <= 14'd396) begin
            if (in_env_tab1) begin
                s0_elem   <= ELEM_ENV_TAB1;
                s0_border <= on_box_border(in_x, in_y, 14'd36, 14'd120, 14'd372, 14'd396);
            end else if (in_env_tab2) begin
                s0_elem   <= ELEM_ENV_TAB2;
                s0_border <= on_box_border(in_x, in_y, 14'd126, 14'd210, 14'd372, 14'd396);
            end else if (in_env_tab3) begin
                s0_elem   <= ELEM_ENV_TAB3;
                s0_border <= on_box_border(in_x, in_y, 14'd216, 14'd300, 14'd372, 14'd396);
            end else begin
                s0_hit <= 1'b0;
            end
        end

        // Band 6: Modulation Matrix Slot Bypass Buttons (Y: 412..530)
        else if (in_y >= 14'd412 && in_y <= 14'd530) begin
            if (in_slot1_pwr) begin
                s0_elem   <= ELEM_SLOT1_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd412, 14'd428);
            end else if (in_slot2_pwr) begin
                s0_elem   <= ELEM_SLOT2_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd446, 14'd462);
            end else if (in_slot3_pwr) begin
                s0_elem   <= ELEM_SLOT3_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd480, 14'd496);
            end else if (in_slot4_pwr) begin
                s0_elem   <= ELEM_SLOT4_PWR;
                s0_border <= on_box_border(in_x, in_y, 14'd808, 14'd824, 14'd514, 14'd530);
            end else begin
                s0_hit <= 1'b0;
            end
        end

        else begin
            s0_hit <= 1'b0;
        end
    end

    // --------------------------------------------------------------------------
    // Stage 1: Procedural Glyphs & Color Shading (Cycle 2)
    // --------------------------------------------------------------------------
    // Multiplier-free geometric power icon centered at (xc, yc=60)
    function is_power_glyph;
        input [13:0] px, py, xc;
        reg [13:0] dx_raw, dy_raw;
        reg [3:0] dx, dy;
        begin
            dx_raw = (px >= xc) ? (px - xc) : (xc - px);
            dy_raw = (py >= 14'd60) ? (py - 14'd60) : (14'd60 - py);
            dx = (dx_raw > 14'd8) ? 4'd8 : dx_raw[3:0];
            dy = (dy_raw > 14'd8) ? 4'd8 : dy_raw[3:0];
            is_power_glyph = ((dx <= 4'd4) && (dy <= 4'd4) &&
                              ((dx + dy) >= 4'd3) && ((dx + dy) <= 4'd5) &&
                              ((py > 14'd58) || (dx > 4'd1))) ||
                             ((px == xc) && (py >= 14'd56) && (py <= 14'd60));
        end
    endfunction

    // Chevron arrow <
    function is_arrow_left;
        input [13:0] px, py, xc;
        reg [13:0] dx, dy;
        begin
            dx = (xc >= px) ? (xc - px) : 14'd99;
            dy = (py >= 14'd60) ? (py - 14'd60) : (14'd60 - py);
            is_arrow_left = ((dx == dy) || (dx == (dy + 14'd1))) && (dx >= 14'd1) && (dx <= 14'd5);
        end
    endfunction

    // Chevron arrow >
    function is_arrow_right;
        input [13:0] px, py, xc;
        reg [13:0] dx, dy;
        begin
            dx = (px >= xc) ? (px - xc) : 14'd99;
            dy = (py >= 14'd60) ? (py - 14'd60) : (14'd60 - py);
            is_arrow_right = ((dx == dy) || (dx == (dy + 14'd1))) && (dx >= 14'd1) && (dx <= 14'd5);
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

    // Readable text in the existing hit boxes; interaction geometry is unchanged.
    wire [5:0] caption_elem = in_env_tab1 ? ELEM_ENV_TAB1 :
        in_env_tab2 ? ELEM_ENV_TAB2 : in_env_tab3 ? ELEM_ENV_TAB3 :
        in_osca_bar ? ELEM_OSCA_BAR : in_oscb_bar ? ELEM_OSCB_BAR :
        in_flt_bar ? ELEM_FLT_BAR : in_flt_chk_a ? ELEM_FLT_CHK_A :
        in_flt_chk_b ? ELEM_FLT_CHK_B : in_flt_chk_n ? ELEM_FLT_CHK_N :
        in_flt_chk_s ? ELEM_FLT_CHK_S : in_flt_chk_k ? ELEM_FLT_CHK_K : ELEM_NONE;
    reg [47:0] caption;
    reg [13:0] caption_x, caption_y;
    reg caption_on;
    reg [5:0] caption_ch;
    // Constant bounding boxes below guard these modular glyph coordinates.
    // No full-width subtract/compare chain is needed at the pixel rate.
    wire [5:0] caption_dx = in_x[5:0]-caption_x[5:0];
    wire [3:0] caption_dy = in_y[3:0]-caption_y[3:0];
    reg caption_area;
    always @(*) begin
        caption_area=0;
        case(caption_elem)
            ELEM_ENV_TAB1: caption_area=in_x>=52 && in_x<116 && in_y>=380 && in_y<390;
            ELEM_ENV_TAB2: caption_area=in_x>=142 && in_x<206 && in_y>=380 && in_y<390;
            ELEM_ENV_TAB3: caption_area=in_x>=232 && in_x<296 && in_y>=380 && in_y<390;
            ELEM_OSCA_BAR: caption_area=in_x>=70 && in_x<134 && in_y>=56 && in_y<66;
            ELEM_OSCB_BAR: caption_area=in_x>=486 && in_x<550 && in_y>=56 && in_y<66;
            ELEM_FLT_BAR: caption_area=in_x>=902 && in_x<966 && in_y>=56 && in_y<66;
            ELEM_FLT_CHK_A: caption_area=in_x>=886 && in_x<950 && in_y>=252 && in_y<262;
            ELEM_FLT_CHK_B: caption_area=in_x>=886 && in_x<950 && in_y>=274 && in_y<284;
            ELEM_FLT_CHK_N: caption_area=in_x>=886 && in_x<950 && in_y>=296 && in_y<306;
            ELEM_FLT_CHK_S: caption_area=in_x>=886 && in_x<950 && in_y>=318 && in_y<328;
            ELEM_FLT_CHK_K: caption_area=in_x>=886 && in_x<950 && in_y>=340 && in_y<350;
        endcase
    end
    always @(*) begin
        caption=48'd0; caption_x=0; caption_y=0; caption_on=1'b1;
        case(caption_elem)
            ELEM_ENV_TAB1, ELEM_ENV_TAB2, ELEM_ENV_TAB3: begin
                caption_x = caption_elem==ELEM_ENV_TAB1 ? 14'd52 : caption_elem==ELEM_ENV_TAB2 ? 14'd142 : 14'd232;
                caption_y = 14'd380;
                caption = {`CH_E,`CH_N,`CH_V,`CH_SPACE,
                    (caption_elem==ELEM_ENV_TAB1 ? `CH_1 : caption_elem==ELEM_ENV_TAB2 ? `CH_2 : `CH_3),18'd0};
            end
            ELEM_OSCA_BAR, ELEM_OSCB_BAR: begin
                caption_x = caption_elem==ELEM_OSCA_BAR ? 14'd70 : 14'd486;
                caption_y = 14'd56;
                case(caption_elem==ELEM_OSCA_BAR ? val_osca_wave : val_oscb_wave)
                    0: caption={`CH_S,`CH_I,`CH_N,`CH_E,24'd0};
                    1: caption={`CH_S,`CH_A,`CH_W,30'd0};
                    2: caption={`CH_P,`CH_U,`CH_L,`CH_S,`CH_E,18'd0};
                    3: caption={`CH_T,`CH_R,`CH_I,`CH_A,`CH_N,`CH_G,`CH_L,`CH_E};
                endcase
            end
            ELEM_FLT_BAR: begin
                caption_x=14'd902; caption_y=14'd56;
                case(val_flt_type)
                    0: caption={`CH_L,`CH_O,`CH_W,`CH_P,`CH_A,`CH_S,`CH_S,6'd0};
                    1: caption={`CH_H,`CH_I,`CH_G,`CH_H,`CH_P,`CH_A,`CH_S,`CH_S};
                    2: caption={`CH_B,`CH_A,`CH_N,`CH_D,`CH_P,`CH_A,`CH_S,`CH_S};
                    3: caption={`CH_N,`CH_O,`CH_T,`CH_C,`CH_H,18'd0};
                endcase
            end
            ELEM_FLT_CHK_A, ELEM_FLT_CHK_B, ELEM_FLT_CHK_N, ELEM_FLT_CHK_S, ELEM_FLT_CHK_K: begin
                caption_x=14'd886;
                case(caption_elem)
                    ELEM_FLT_CHK_A: begin caption={`CH_A,42'd0}; caption_y=14'd252; end
                    ELEM_FLT_CHK_B: begin caption={`CH_B,42'd0}; caption_y=14'd274; end
                    ELEM_FLT_CHK_N: begin caption={`CH_N,42'd0}; caption_y=14'd296; end
                    ELEM_FLT_CHK_S: begin caption={`CH_S,42'd0}; caption_y=14'd318; end
                    ELEM_FLT_CHK_K: begin caption={`CH_K,42'd0}; caption_y=14'd340; end
                endcase
            end
            default: caption_on=1'b0;
        endcase
        case(caption_dx[5:3])
            0: caption_ch=caption[47:42];
            1: caption_ch=caption[41:36];
            2: caption_ch=caption[35:30];
            3: caption_ch=caption[29:24];
            4: caption_ch=caption[23:18];
            5: caption_ch=caption[17:12];
            6: caption_ch=caption[11:6];
            7: caption_ch=caption[5:0];
        endcase
    end
    wire caption_valid_raw = caption_on && caption_area && caption_dx[2:0]<3'd7;
    reg caption_valid;
    reg [5:0] caption_ch_reg;
    reg [2:0] caption_rx_reg;
    reg [3:0] caption_ry_reg;
    always @(posedge clk) begin
        caption_valid <= caption_valid_raw;
        caption_ch_reg <= caption_ch;
        caption_rx_reg <= caption_dx[2:0];
        caption_ry_reg <= caption_dy;
    end
    wire [1:0] caption_coverage = caption_valid ?
        get_font_7x10(caption_ch_reg, caption_rx_reg, caption_ry_reg) : 2'd0;

    always @(*) begin
        rgb_out = 24'h0;

        case (s0_elem)
            // Power Buttons
            ELEM_OSCA_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_POWER) ? 24'hFFFFFF :
                              (val_osca_power ? `COLOR_TEXT_ACCENT : `COLOR_BTN_BORDER);
                else if (is_power_glyph(s0_x, s0_y, 14'd44))
                    rgb_out = val_osca_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    rgb_out = val_osca_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_POWER) ? 24'hFFFFFF :
                              (val_oscb_power ? `COLOR_OSCB_LINE : `COLOR_BTN_BORDER);
                else if (is_power_glyph(s0_x, s0_y, 14'd460))
                    rgb_out = val_oscb_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    rgb_out = val_oscb_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_POWER) ? 24'hFFFFFF :
                              (val_flt_power ? `COLOR_FLT_LINE : `COLOR_BTN_BORDER);
                else if (is_power_glyph(s0_x, s0_y, 14'd876))
                    rgb_out = val_flt_power ? 24'hFFFFFF : `COLOR_BTN_IDLE_ICON;
                else
                    rgb_out = val_flt_power ? `COLOR_BTN_ACTIVE_BG : `COLOR_BTN_IDLE_BG;
            end

            // Preset Selectors & Waves
            ELEM_OSCA_PREV: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(s0_x, s0_y, 14'd380))
                    rgb_out = `COLOR_TEXT_ACCENT;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCA_NEXT: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCA_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(s0_x, s0_y, 14'd400))
                    rgb_out = `COLOR_TEXT_ACCENT;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCA_BAR: begin
                if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else if (s0_y >= 14'd58 && s0_y <= 14'd62 &&
                         ((s0_x >= 14'd278 && s0_x <= 14'd282) ||
                          (s0_x >= 14'd290 && s0_x <= 14'd294) ||
                          (s0_x >= 14'd302 && s0_x <= 14'd306) ||
                          (s0_x >= 14'd314 && s0_x <= 14'd318))) begin
                    if ((val_osca_wave == 2'd0 && s0_x <= 14'd282) ||
                        (val_osca_wave == 2'd1 && s0_x >= 14'd290 && s0_x <= 14'd294) ||
                        (val_osca_wave == 2'd2 && s0_x >= 14'd302 && s0_x <= 14'd306) ||
                        (val_osca_wave == 2'd3 && s0_x >= 14'd314))
                        rgb_out = `COLOR_TEXT_ACCENT;
                    else
                        rgb_out = 24'h323E50;
                end else
                    rgb_out = `COLOR_BADGE_BG;
            end

            ELEM_OSCB_PREV: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(s0_x, s0_y, 14'd796))
                    rgb_out = `COLOR_OSCB_LINE;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_NEXT: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_OSCB_WAVE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(s0_x, s0_y, 14'd816))
                    rgb_out = `COLOR_OSCB_LINE;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_OSCB_BAR: begin
                if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else if (s0_y >= 14'd58 && s0_y <= 14'd62 &&
                         ((s0_x >= 14'd696 && s0_x <= 14'd700) ||
                          (s0_x >= 14'd708 && s0_x <= 14'd712) ||
                          (s0_x >= 14'd720 && s0_x <= 14'd724) ||
                          (s0_x >= 14'd732 && s0_x <= 14'd736))) begin
                    if ((val_oscb_wave == 2'd0 && s0_x <= 14'd700) ||
                        (val_oscb_wave == 2'd1 && s0_x >= 14'd708 && s0_x <= 14'd712) ||
                        (val_oscb_wave == 2'd2 && s0_x >= 14'd720 && s0_x <= 14'd724) ||
                        (val_oscb_wave == 2'd3 && s0_x >= 14'd732))
                        rgb_out = `COLOR_OSCB_LINE;
                    else
                        rgb_out = 24'h323E50;
                end else
                    rgb_out = `COLOR_BADGE_BG;
            end

            ELEM_FLT_PREV: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_TYPE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_left(s0_x, s0_y, 14'd1212))
                    rgb_out = `COLOR_FLT_LINE;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_NEXT: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_TYPE) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (is_arrow_right(s0_x, s0_y, 14'd1232))
                    rgb_out = `COLOR_FLT_LINE;
                else
                    rgb_out = `COLOR_BTN_IDLE_BG;
            end

            ELEM_FLT_BAR: begin
                if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else if (s0_y >= 14'd58 && s0_y <= 14'd62 &&
                         ((s0_x >= 14'd1112 && s0_x <= 14'd1116) ||
                          (s0_x >= 14'd1124 && s0_x <= 14'd1128) ||
                          (s0_x >= 14'd1136 && s0_x <= 14'd1140) ||
                          (s0_x >= 14'd1148 && s0_x <= 14'd1152))) begin
                    if ((val_flt_type == 2'd0 && s0_x <= 14'd1116) ||
                        (val_flt_type == 2'd1 && s0_x >= 14'd1124 && s0_x <= 14'd1128) ||
                        (val_flt_type == 2'd2 && s0_x >= 14'd1136 && s0_x <= 14'd1140) ||
                        (val_flt_type == 2'd3 && s0_x >= 14'd1148))
                        rgb_out = `COLOR_FLT_LINE;
                    else
                        rgb_out = 24'h323E50;
                end else
                    rgb_out = `COLOR_BADGE_BG;
            end

            // Stepper Minus Buttons [-]
            ELEM_OSCA_OCT_M, ELEM_OSCA_SEM_M, ELEM_OSCA_FIN_M,
            ELEM_OSCB_OCT_M, ELEM_OSCB_SEM_M, ELEM_OSCB_FIN_M: begin
                if (s0_border) begin
                    if (btn_flash_active &&
                        ((s0_elem == ELEM_OSCA_OCT_M && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (s0_elem == ELEM_OSCA_SEM_M && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (s0_elem == ELEM_OSCA_FIN_M && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (s0_elem == ELEM_OSCB_OCT_M && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (s0_elem == ELEM_OSCB_SEM_M && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (s0_elem == ELEM_OSCB_FIN_M && active_btn_id == `PARAM_ID_OSCB_FINE)))
                        rgb_out = 24'hFFFFFF;
                    else
                        rgb_out = `COLOR_BTN_BORDER;
                end else if (s0_y >= 14'd84 && s0_y <= 14'd86 &&
                    ((s0_elem == ELEM_OSCA_OCT_M && s0_x >= 14'd40  && s0_x <= 14'd48)  ||
                     (s0_elem == ELEM_OSCA_SEM_M && s0_x >= 14'd134 && s0_x <= 14'd142) ||
                     (s0_elem == ELEM_OSCA_FIN_M && s0_x >= 14'd228 && s0_x <= 14'd236) ||
                     (s0_elem == ELEM_OSCB_OCT_M && s0_x >= 14'd456 && s0_x <= 14'd464) ||
                     (s0_elem == ELEM_OSCB_SEM_M && s0_x >= 14'd550 && s0_x <= 14'd558) ||
                     (s0_elem == ELEM_OSCB_FIN_M && s0_x >= 14'd644 && s0_x <= 14'd652)))
                    rgb_out = 24'hFFFFFF;
                else
                    rgb_out = (btn_flash_active &&
                        ((s0_elem == ELEM_OSCA_OCT_M && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (s0_elem == ELEM_OSCA_SEM_M && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (s0_elem == ELEM_OSCA_FIN_M && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (s0_elem == ELEM_OSCB_OCT_M && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (s0_elem == ELEM_OSCB_SEM_M && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (s0_elem == ELEM_OSCB_FIN_M && active_btn_id == `PARAM_ID_OSCB_FINE))) ? `COLOR_BTN_ACTIVE_BG : 24'h222A38;
            end

            // Stepper Plus Buttons [+]
            ELEM_OSCA_OCT_P, ELEM_OSCA_SEM_P, ELEM_OSCA_FIN_P,
            ELEM_OSCB_OCT_P, ELEM_OSCB_SEM_P, ELEM_OSCB_FIN_P: begin
                if (s0_border) begin
                    if (btn_flash_active &&
                        ((s0_elem == ELEM_OSCA_OCT_P && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (s0_elem == ELEM_OSCA_SEM_P && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (s0_elem == ELEM_OSCA_FIN_P && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (s0_elem == ELEM_OSCB_OCT_P && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (s0_elem == ELEM_OSCB_SEM_P && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (s0_elem == ELEM_OSCB_FIN_P && active_btn_id == `PARAM_ID_OSCB_FINE)))
                        rgb_out = 24'hFFFFFF;
                    else
                        rgb_out = `COLOR_BTN_BORDER;
                end else if ((s0_y >= 14'd84 && s0_y <= 14'd86 &&
                     ((s0_elem == ELEM_OSCA_OCT_P && s0_x >= 14'd108 && s0_x <= 14'd116) ||
                      (s0_elem == ELEM_OSCA_SEM_P && s0_x >= 14'd202 && s0_x <= 14'd210) ||
                      (s0_elem == ELEM_OSCA_FIN_P && s0_x >= 14'd296 && s0_x <= 14'd304) ||
                      (s0_elem == ELEM_OSCB_OCT_P && s0_x >= 14'd524 && s0_x <= 14'd532) ||
                      (s0_elem == ELEM_OSCB_SEM_P && s0_x >= 14'd618 && s0_x <= 14'd626) ||
                      (s0_elem == ELEM_OSCB_FIN_P && s0_x >= 14'd712 && s0_x <= 14'd720))) ||
                    (s0_y >= 14'd80 && s0_y <= 14'd90 &&
                     ((s0_elem == ELEM_OSCA_OCT_P && s0_x >= 14'd111 && s0_x <= 14'd113) ||
                      (s0_elem == ELEM_OSCA_SEM_P && s0_x >= 14'd205 && s0_x <= 14'd207) ||
                      (s0_elem == ELEM_OSCA_FIN_P && s0_x >= 14'd299 && s0_x <= 14'd301) ||
                      (s0_elem == ELEM_OSCB_OCT_P && s0_x >= 14'd527 && s0_x <= 14'd529) ||
                      (s0_elem == ELEM_OSCB_SEM_P && s0_x >= 14'd621 && s0_x <= 14'd623) ||
                      (s0_elem == ELEM_OSCB_FIN_P && s0_x >= 14'd715 && s0_x <= 14'd717))))
                    rgb_out = 24'hFFFFFF;
                else
                    rgb_out = (btn_flash_active &&
                        ((s0_elem == ELEM_OSCA_OCT_P && active_btn_id == `PARAM_ID_OSCA_OCT)  ||
                         (s0_elem == ELEM_OSCA_SEM_P && active_btn_id == `PARAM_ID_OSCA_SEMI) ||
                         (s0_elem == ELEM_OSCA_FIN_P && active_btn_id == `PARAM_ID_OSCA_FINE) ||
                         (s0_elem == ELEM_OSCB_OCT_P && active_btn_id == `PARAM_ID_OSCB_OCT)  ||
                         (s0_elem == ELEM_OSCB_SEM_P && active_btn_id == `PARAM_ID_OSCB_SEMI) ||
                         (s0_elem == ELEM_OSCB_FIN_P && active_btn_id == `PARAM_ID_OSCB_FINE))) ? `COLOR_BTN_ACTIVE_BG : 24'h222A38;
            end

            // Stepper Value Display Badges (Middle with Bipolar Level Meters)
            ELEM_OSCA_OCT_B, ELEM_OSCA_SEM_B, ELEM_OSCA_FIN_B,
            ELEM_OSCB_OCT_B, ELEM_OSCB_SEM_B, ELEM_OSCB_FIN_B: begin
                if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else if (s0_y >= 14'd78 && s0_y <= 14'd92 &&
                    (s0_x == 14'd78 || s0_x == 14'd172 || s0_x == 14'd266 ||
                     s0_x == 14'd494 || s0_x == 14'd588 || s0_x == 14'd682))
                    rgb_out = 24'hFFFFFF;
                else if (s0_y >= 14'd83 && s0_y <= 14'd87) begin
                    // OSC A OCT (Center 78)
                    if (s0_elem == ELEM_OSCA_OCT_B && (s0_x >= oct_a_lo && s0_x <= oct_a_hi))
                        rgb_out = `COLOR_TEXT_ACCENT;
                    // OSC A SEMI (Center 172)
                    else if (s0_elem == ELEM_OSCA_SEM_B && (s0_x >= sem_a_lo && s0_x <= sem_a_hi))
                        rgb_out = `COLOR_TEXT_ACCENT;
                    // OSC A FINE (Center 266)
                    else if (s0_elem == ELEM_OSCA_FIN_B && (s0_x >= fin_a_lo && s0_x <= fin_a_hi))
                        rgb_out = `COLOR_TEXT_ACCENT;
                    // OSC B OCT (Center 494)
                    else if (s0_elem == ELEM_OSCB_OCT_B && (s0_x >= oct_b_lo && s0_x <= oct_b_hi))
                        rgb_out = `COLOR_OSCB_LINE;
                    // OSC B SEMI (Center 588)
                    else if (s0_elem == ELEM_OSCB_SEM_B && (s0_x >= sem_b_lo && s0_x <= sem_b_hi))
                        rgb_out = `COLOR_OSCB_LINE;
                    // OSC B FINE (Center 682)
                    else if (s0_elem == ELEM_OSCB_FIN_B && (s0_x >= fin_b_lo && s0_x <= fin_b_hi))
                        rgb_out = `COLOR_OSCB_LINE;
                    else
                        rgb_out = `COLOR_BADGE_BG;
                end else
                    rgb_out = `COLOR_BADGE_BG;
            end

            // Filter Routing Checkboxes [A], [B], [N], [S], [K]
            ELEM_FLT_CHK_A: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_A) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (s0_x <= 14'd882)
                    rgb_out = val_flt_route_a ? `COLOR_TEXT_ACCENT : `COLOR_BTN_IDLE_BG;
                else
                    rgb_out = 24'h141E2C;
            end

            ELEM_FLT_CHK_B: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_B) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (s0_x <= 14'd882)
                    rgb_out = val_flt_route_b ? `COLOR_OSCB_LINE : `COLOR_BTN_IDLE_BG;
                else
                    rgb_out = 24'h141E2C;
            end

            ELEM_FLT_CHK_N: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_N) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (s0_x <= 14'd882)
                    rgb_out = val_flt_route_n ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    rgb_out = 24'h141E2C;
            end

            ELEM_FLT_CHK_S: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_ROUTE_S) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (s0_x <= 14'd882)
                    rgb_out = val_flt_route_s ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    rgb_out = 24'h141E2C;
            end

            ELEM_FLT_CHK_K: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_FLT_KEYTRACK) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else if (s0_x <= 14'd882)
                    rgb_out = val_flt_keytrack ? 24'hD0D8E8 : `COLOR_BTN_IDLE_BG;
                else
                    rgb_out = 24'h141E2C;
            end

            // Envelope Modern Tabs
            ELEM_ENV_TAB1: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd0)
                    rgb_out = 24'hFFFFFF;
                else if (val_env_tab == 2'd0 && s0_y <= 14'd374)
                    rgb_out = `COLOR_TEXT_ACCENT;
                else if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else
                    rgb_out = (val_env_tab == 2'd0) ? 24'h283850 : 24'h141822;
            end

            ELEM_ENV_TAB2: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd1)
                    rgb_out = 24'hFFFFFF;
                else if (val_env_tab == 2'd1 && s0_y <= 14'd374)
                    rgb_out = `COLOR_TEXT_ACCENT;
                else if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else
                    rgb_out = (val_env_tab == 2'd1) ? 24'h283850 : 24'h141822;
            end

            ELEM_ENV_TAB3: begin
                if (btn_flash_active && active_btn_id == `PARAM_ID_ENV_TAB && val_env_tab == 2'd2)
                    rgb_out = 24'hFFFFFF;
                else if (val_env_tab == 2'd2 && s0_y <= 14'd374)
                    rgb_out = `COLOR_TEXT_ACCENT;
                else if (s0_border)
                    rgb_out = `COLOR_BTN_BORDER;
                else
                    rgb_out = (val_env_tab == 2'd2) ? 24'h283850 : 24'h141822;
            end

            // Matrix Slot Bypass LED Switches
            ELEM_SLOT1_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT1_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    rgb_out = !val_slot_bypass[0] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT2_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT2_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    rgb_out = !val_slot_bypass[1] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT3_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT3_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    rgb_out = !val_slot_bypass[2] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            ELEM_SLOT4_PWR: begin
                if (s0_border)
                    rgb_out = (btn_flash_active && active_btn_id == `PARAM_ID_SLOT4_BYPASS) ? 24'hFFFFFF : `COLOR_BTN_BORDER;
                else
                    rgb_out = !val_slot_bypass[3] ? `COLOR_TEXT_ACCENT : 24'h804020;
            end

            // Top Bar HUD Indicator Banner
            ELEM_TOP_HUD: begin
                if (s0_border)
                    rgb_out = (selected_param_id != `PARAM_ID_NONE) ? `COLOR_TEXT_ACCENT : `COLOR_BTN_BORDER;
                else if (selected_param_id != `PARAM_ID_NONE)
                    rgb_out = 24'h183454;
                else
                    rgb_out = `COLOR_BADGE_BG;
            end

            default: rgb_out = 24'h0;
        endcase
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
