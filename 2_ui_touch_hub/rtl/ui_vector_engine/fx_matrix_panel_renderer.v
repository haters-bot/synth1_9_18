// ==============================================================================
// Module: fx_matrix_panel_renderer.v
// Description: Procedural Modulation Matrix & FX Visualizer Panel
//              Renders 4 Modulation Matrix Routing Slots with Source Indicators,
//              Bipolar Glow Modulation Amount Bars (-100% .. +100%),
//              Destination Badges, Grid Slots, and Slot Bypass States.
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"

module fx_matrix_panel_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Video beam coordinates
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // Slot bypass flags (1: Bypassed/Muted, 0: Active)
    input  wire [3:0]  val_slot_bypass,

    // Modulation Amounts for 4 slots (0..127, 64 is bipolar center 0%)
    input  wire [6:0]  mod_amt1,
    input  wire [6:0]  mod_amt2,
    input  wire [6:0]  mod_amt3,
    input  wire [6:0]  mod_amt4,

    // Outputs
    output reg         out_hit_fx,
    output reg  [23:0] out_fx_rgb
);

    // --------------------------------------------------------------------------
    // Geometry Constants
    // --------------------------------------------------------------------------
    localparam BAR_X_MIN    = 14'd890;
    localparam BAR_X_CTR    = 14'd1020; // 0% center
    localparam BAR_X_MAX    = 14'd1150; // Max span = 130px each side

    localparam C_SLOT_BG    = 24'h121620;
    localparam C_SLOT_BDR   = 24'h263042;
    localparam C_CTR_LINE   = 24'h4A5872;
    localparam C_SRC_BADGE  = 24'h28425C;
    localparam C_DST_BADGE  = 24'h1C384A;
    localparam C_POS_GLOW   = 24'h38E8FF; // Bright Cyan for positive modulation
    localparam C_NEG_GLOW   = 24'hFF6B4A; // Warm Coral for negative modulation

    // --------------------------------------------------------------------------
    // Stage 0: Window and Slot Detection
    // --------------------------------------------------------------------------
    reg        s0_in_win;
    reg [13:0] s0_x, s0_y;
    reg [1:0]  s0_slot_idx;
    reg        s0_in_slot;
    reg        s0_slot_byp;
    reg [6:0]  s0_cur_amt;

    wire in_box = (in_x >= `FX_WIN_X0) && (in_x <= `FX_WIN_X1) &&
                  (in_y >= `FX_WIN_Y0) && (in_y <= `FX_WIN_Y1);

    always @(posedge clk) begin
        s0_x      <= in_x;
        s0_y      <= in_y;
        s0_in_win <= in_box;

        s0_in_slot  <= 1'b0;
        s0_slot_idx <= 2'd0;
        s0_slot_byp <= 1'b0;
        s0_cur_amt  <= 7'd64;

        // Slot 0: Y 408..434
        if (in_y >= 14'd408 && in_y <= 14'd434) begin
            s0_in_slot  <= 1'b1;
            s0_slot_idx <= 2'd0;
            s0_slot_byp <= val_slot_bypass[0];
            s0_cur_amt  <= mod_amt1;
        end
        // Slot 1: Y 442..468
        else if (in_y >= 14'd442 && in_y <= 14'd468) begin
            s0_in_slot  <= 1'b1;
            s0_slot_idx <= 2'd1;
            s0_slot_byp <= val_slot_bypass[1];
            s0_cur_amt  <= mod_amt2;
        end
        // Slot 2: Y 476..502
        else if (in_y >= 14'd476 && in_y <= 14'd502) begin
            s0_in_slot  <= 1'b1;
            s0_slot_idx <= 2'd2;
            s0_slot_byp <= val_slot_bypass[2];
            s0_cur_amt  <= mod_amt3;
        end
        // Slot 3: Y 510..536
        else if (in_y >= 14'd510 && in_y <= 14'd536) begin
            s0_in_slot  <= 1'b1;
            s0_slot_idx <= 2'd3;
            s0_slot_byp <= val_slot_bypass[3];
            s0_cur_amt  <= mod_amt4;
        end
    end

    // --------------------------------------------------------------------------
    // Stage 1: Bipolar Bar Endpoint & Badge Hit Calculation
    // --------------------------------------------------------------------------
    reg        s1_in_win;
    reg [13:0] s1_x, s1_y;
    reg        s1_in_slot;
    reg        s1_slot_byp;
    reg [1:0]  s1_slot_idx;

    reg        s1_hit_src_badge;
    reg        s1_hit_dst_badge;
    reg        s1_hit_bar_active;
    reg        s1_bar_is_pos;
    reg        s1_hit_ctr_axis;
    reg        s1_hit_slot_bdr;

    wire signed [7:0] delta_amt = {1'b0, s0_cur_amt} - 8'd64; // -64 .. +63
    wire [13:0] abs_span = (delta_amt >= 0) ? 
                           ({6'd0, delta_amt[6:0]} * 8'd130 >> 6) : 
                           ({6'd0, (~delta_amt[6:0] + 1'b1)} * 8'd130 >> 6);

    wire [13:0] bar_end_x = (delta_amt >= 0) ? (BAR_X_CTR + abs_span) : (BAR_X_CTR - abs_span);

    always @(posedge clk) begin
        s1_x        <= s0_x;
        s1_y        <= s0_y;
        s1_in_win   <= s0_in_win;
        s1_in_slot  <= s0_in_slot;
        s1_slot_byp <= s0_slot_byp;
        s1_slot_idx <= s0_slot_idx;

        // Source badge: X 818 .. 876
        s1_hit_src_badge <= (s0_x >= 14'd818) && (s0_x <= 14'd876);
        // Destination badge: X 1164 .. 1234
        s1_hit_dst_badge <= (s0_x >= 14'd1164) && (s0_x <= 14'd1234);

        // Center Axis Line: X = 1020
        s1_hit_ctr_axis <= (s0_x == BAR_X_CTR);

        // Bipolar Bar Active Span
        s1_bar_is_pos     <= (delta_amt >= 0);
        s1_hit_bar_active <= 1'b0;
        if (delta_amt >= 0) begin
            if (s0_x >= BAR_X_CTR && s0_x <= bar_end_x && s0_x <= BAR_X_MAX)
                s1_hit_bar_active <= 1'b1;
        end else begin
            if (s0_x <= BAR_X_CTR && s0_x >= bar_end_x && s0_x >= BAR_X_MIN)
                s1_hit_bar_active <= 1'b1;
        end

        // Slot 1px Border
        s1_hit_slot_bdr <= (s0_x == 14'd812) || (s0_x == 14'd1240);
    end

    // --------------------------------------------------------------------------
    // Stage 2: Geometric Hit & Multi-Layer Pixel Compositing
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hit_fx <= 1'b0;
            out_fx_rgb <= 24'h0;
        end else begin
            out_hit_fx <= 1'b0;
            out_fx_rgb <= 24'h0;

            if (s1_in_win) begin
                out_hit_fx <= 1'b1;

                // Priority 1: Window Bevel Frame
                if ((s1_x == `FX_WIN_X0) || (s1_x == `FX_WIN_X1) ||
                    (s1_y == `FX_WIN_Y0) || (s1_y == `FX_WIN_Y1)) begin
                    out_fx_rgb <= `COLOR_PANEL_BORDER;
                end
                // Inside an active slot row
                else if (s1_in_slot) begin
                    // Priority 2: Source Badge
                    if (s1_hit_src_badge) begin
                        out_fx_rgb <= s1_slot_byp ? 24'h1A222C : C_SRC_BADGE;
                    end
                    // Priority 3: Destination Badge
                    else if (s1_hit_dst_badge) begin
                        out_fx_rgb <= s1_slot_byp ? 24'h141C24 : C_DST_BADGE;
                    end
                    // Priority 4: Active Modulation Glow Bar
                    else if (s1_hit_bar_active) begin
                        out_fx_rgb <= s1_slot_byp ? 24'h382A22 : (s1_bar_is_pos ? C_POS_GLOW : C_NEG_GLOW);
                    end
                    // Priority 5: Zero Center Axis
                    else if (s1_hit_ctr_axis) begin
                        out_fx_rgb <= C_CTR_LINE;
                    end
                    // Priority 6: Modulation Track Rails
                    else if (s1_x >= BAR_X_MIN && s1_x <= BAR_X_MAX) begin
                        out_fx_rgb <= (s1_y[0]) ? 24'h161E2A : 24'h1A2434;
                    end
                    // Slot Base Background
                    else begin
                        out_fx_rgb <= C_SLOT_BG;
                    end
                end
                // Inter-slot gap background
                else begin
                    out_fx_rgb <= 24'h0A0C12;
                end
            end
        end
    end

endmodule
