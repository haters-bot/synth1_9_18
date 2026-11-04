// ==============================================================================
// Module: filter_panel_renderer.v
// Description: Procedural Frequency Response Curve Renderer for Synth Filter
//              - Supports 4 Filter Modes: Lowpass (LP), Highpass (HP),
//                Bandpass (BP), and Notch (BR)
//              - Dynamic cutoff frequency sweep and resonance Q peak hump
//              - Interactive Power Bypass visual state (flat bypass line when off)
//              - Glowing node cursor, logarithmic grid, and translucent area fill
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "pixel_coverage.vh"

module filter_panel_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Video beam coordinates
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // Filter Parameters
    input  wire        val_flt_power,
    input  wire [1:0]  val_flt_type,
    input  wire [6:0]  flt_cutoff,
    input  wire [6:0]  flt_res,

    // Outputs
    output reg         out_hit_flt,
    output reg  [23:0] out_flt_rgb
);

    // --------------------------------------------------------------------------
    // Stage 0: Window Detection & Cutoff/Resonance Position Mapping
    // --------------------------------------------------------------------------
    reg        s0_in_win;
    reg [13:0] s0_x, s0_y;
    reg [13:0] s0_x_cut;
    reg [5:0]  s0_h_peak;
    reg [1:0]  s0_type;
    reg        s0_pwr;
    reg [13:0] cut_x_cached;
    reg signed [13:0] s0_dx_cut;

    wire in_box = (in_x >= `FLT_WIN_X0) && (in_x <= `FLT_WIN_X1) &&
                  (in_y >= `FLT_WIN_Y0) && (in_y <= `FLT_WIN_Y1);

    // Cutoff X range: 868 + 30 .. 868 + 310 (X_cut in 898 .. 1178)
    wire [13:0] calc_x_cut = `FLT_WIN_X0 + 16'd30 + ({9'd0, flt_cutoff} * 16'd280 >> 7);
    // Peak height: 0 .. 44 pixels
    wire [5:0]  calc_h_peak = ({9'd0,flt_res} * 16'd44) >> 7;

    always @(posedge clk) begin
        // Cutoff changes at control rate. Cache it before raster subtraction,
        // then carry the matching cutoff and delta together through stage zero.
        cut_x_cached <= calc_x_cut;
        s0_x      <= in_x;
        s0_y      <= in_y;
        s0_in_win <= in_box;
        s0_x_cut  <= cut_x_cached;
        s0_dx_cut <= $signed(in_x-cut_x_cached);
        s0_h_peak <= calc_h_peak;
        s0_type   <= val_flt_type;
        s0_pwr    <= val_flt_power;
    end

    // --------------------------------------------------------------------------
    // Stage 1: Frequency Response Curve Piecewise Interpolation (LP, HP, BP, Notch)
    // --------------------------------------------------------------------------
    localparam FLT_BASE_Y = 14'd222;
    localparam FLT_PASS_Y = 14'd162;

    reg        s1_in_win;
    reg [13:0] s1_x, s1_y;
    reg [13:0] s1_target_y;
    reg        s1_hit_node;
    reg        s1_grid;
    reg        s1_pwr;

    wire signed [13:0] dx_cut = s0_dx_cut;
    wire [13:0] peak_y = FLT_PASS_Y - {8'd0, s0_h_peak};
    wire [13:0] dip_y  = FLT_PASS_Y + {8'd0, s0_h_peak};
    // These coordinates are used only inside their bounded ramp segments.
    // Narrow before multiplication rather than sending 14 raster bits through
    // a multiplier/divider chain.
    wire [6:0] ramp_right = dx_cut[6:0];
    wire [5:0] ramp_48 = 6'd48 + dx_cut[5:0];
    wire [6:0] ramp_64 = 7'd64 + dx_cut[6:0];
    wire [5:0] ramp_56 = 6'd56 + dx_cut[5:0];
    wire [5:0] ramp_40 = 6'd40 + dx_cut[5:0];

    reg [15:0] curve_q2;
    wire [13:0] curve_y=curve_q2[15:2];
    reg [15:0] s1_target_q2;
    wire [15:0] pass_q2={FLT_PASS_Y,2'b0};
    wire [15:0] base_q2={FLT_BASE_Y,2'b0};
    wire [15:0] peak_q2={peak_y,2'b0};
    wire [15:0] dip_q2={dip_y,2'b0};
    wire [15:0] height_q2={8'd0,s0_h_peak,2'b0};
    // Exact bounded reciprocal division, keeping Gowin's pixel path away
    // from its generic full-width divide-by-constant expansion.
    function [8:0] div48;
        input [13:0] numerator;
        reg [27:0] product;
        begin product=numerator*14'd10923;div48=product[27:19];end
    endfunction
    function [9:0] div56;
        input [14:0] numerator;
        reg [29:0] product;
        begin product=numerator*15'd18725;div56=product[29:20];end
    endfunction
    function [7:0] div40;
        input [12:0] numerator;
        reg [25:0] product;
        begin product=numerator*13'd6554;div40=product[25:18];end
    endfunction
    always @(*) begin
        if (!s0_pwr) begin
            // Filter bypassed: Flat line
            curve_q2 = pass_q2;
        end else begin
            case (s0_type)
                // 0: Lowpass (LP)
                2'd0: begin
                    if (dx_cut < -14'sd48)
                        curve_q2 = pass_q2;
                    else if (dx_cut <= 0)
                        curve_q2 = pass_q2 - div48(height_q2 * ramp_48);
                    else if (dx_cut <= 14'sd64)
                        curve_q2 = peak_q2 + (((base_q2 - peak_q2) * ramp_right) / 14'd64);
                    else
                        curve_q2 = base_q2;
                end

                // 1: Highpass (HP)
                2'd1: begin
                    if (dx_cut < -14'sd64)
                        curve_q2 = base_q2;
                    else if (dx_cut <= 0)
                        curve_q2 = base_q2 - (((base_q2 - peak_q2) * ramp_64) / 14'd64);
                    else if (dx_cut <= 14'sd48)
                        curve_q2 = peak_q2 + div48(height_q2 * ramp_right);
                    else
                        curve_q2 = pass_q2;
                end

                // 2: Bandpass (BP)
                2'd2: begin
                    if (dx_cut < -14'sd56)
                        curve_q2 = base_q2;
                    else if (dx_cut <= 0)
                        curve_q2 = base_q2 - div56((base_q2 - peak_q2) * ramp_56);
                    else if (dx_cut <= 14'sd56)
                        curve_q2 = peak_q2 + div56((base_q2 - peak_q2) * ramp_right);
                    else
                        curve_q2 = base_q2;
                end

                // 3: Notch / Band Reject (BR)
                2'd3: begin
                    if (dx_cut < -14'sd40)
                        curve_q2 = pass_q2;
                    else if (dx_cut <= 0)
                        curve_q2 = pass_q2 + div40(height_q2 * ramp_40);
                    else if (dx_cut <= 14'sd40)
                        curve_q2 = dip_q2 - div40(height_q2 * ramp_right);
                    else
                        curve_q2 = pass_q2;
                end
            endcase
        end
    end

    // Cursor Node (Circular handle at cutoff)
    wire [13:0] ndx = (s0_x >= s0_x_cut) ? (s0_x - s0_x_cut) : (s0_x_cut - s0_x);
    wire [13:0] node_y = s0_type==3 ? dip_y : peak_y;
    wire [13:0] ndy = (s0_y >= node_y) ? (s0_y - node_y) : (node_y - s0_y);
    wire node_hit = s0_pwr && ((ndx <= 2 && ndy <= 4) ||
        (ndx == 3 && ndy <= 3) || (ndx == 4 && ndy <= 2));

    always @(posedge clk) begin
        s1_x        <= s0_x;
        s1_y        <= s0_y;
        s1_in_win   <= s0_in_win;
        s1_target_y <= curve_y;
        s1_target_q2 <= curve_q2;
        s1_hit_node <= node_hit;
        s1_pwr      <= s0_pwr;

        // Subtle logarithmic gridlines
        s1_grid <= (s0_y == FLT_PASS_Y) || (s0_x == s0_x_cut) ||
                   (s0_x == `FLT_WIN_X0 + 14'd120) || (s0_x == `FLT_WIN_X0 + 14'd240);
    end

    // --------------------------------------------------------------------------
    // Stage 2: Geometric Hit & Multi-Layer Pixel Compositing
    // --------------------------------------------------------------------------
    wire [2:0] stroke_alpha=curve_alpha_q4(s1_y,s1_target_q2,5'd3);
    wire [23:0] curve_bg=(s1_pwr && s1_y>=s1_target_y && s1_y<=FLT_BASE_Y) ? `COLOR_FLT_FILL :
        s1_grid ? `COLOR_GRID_SUBTLE : 24'h0C0E14;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hit_flt <= 1'b0;
            out_flt_rgb <= 24'h0;
        end else begin
            out_hit_flt <= 1'b0;
            out_flt_rgb <= 24'h0;

            if (s1_in_win) begin
                out_hit_flt <= 1'b1;

                // Priority 1: Window Bevel Frame
                if ((s1_x == `FLT_WIN_X0) || (s1_x == `FLT_WIN_X1) ||
                    (s1_y == `FLT_WIN_Y0) || (s1_y == `FLT_WIN_Y1)) begin
                    out_flt_rgb <= `COLOR_PANEL_BORDER;
                end
                // Priority 2: Cutoff Node Handle
                else if (s1_hit_node) begin
                    out_flt_rgb <= `COLOR_FLT_NODE;
                end
                // Priority 3: Frequency Curve Line (2px)
                else if (stroke_alpha!=0) begin
                    out_flt_rgb <= blend_rgb_q4(s1_pwr ? `COLOR_FLT_LINE : 24'h382A22,curve_bg,stroke_alpha);
                end
                // Priority 4: Translucent Passband Fill
                else if (s1_pwr && (s1_y >= s1_target_y) && (s1_y <= FLT_BASE_Y)) begin
                    out_flt_rgb <= `COLOR_FLT_FILL;
                end
                // Priority 5: Grid lines
                else if (s1_grid) begin
                    out_flt_rgb <= `COLOR_GRID_SUBTLE;
                end
                // Window background
                else begin
                    out_flt_rgb <= 24'h0C0E14;
                end
            end
        end
    end

endmodule
