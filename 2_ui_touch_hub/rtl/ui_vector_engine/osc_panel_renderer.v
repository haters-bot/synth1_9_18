// ==============================================================================
// Module: osc_panel_renderer.v
// Description: Procedural 2D Wavetable Window Renderer for OSC A & OSC B
//              - Supports 4 Waveform Archetypes: Sine, Saw, Pulse/PWM, Triangle
//              - Real-time morphing with wt_pos
//              - Interactive Power On/Off visual state (dim muted line when off)
//              - Glowing neon outline, subtle coordinate grid, and translucent fill
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "pixel_coverage.vh"

module osc_panel_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Video beam coordinates
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // OSC Parameters
    input  wire        val_osca_power,
    input  wire        val_oscb_power,
    input  wire [1:0]  val_osca_wave,
    input  wire [1:0]  val_oscb_wave,
    input  wire [6:0]  wt_pos_a,
    input  wire [6:0]  wt_pos_b,

    // Outputs
    output reg         out_hit_osca,
    output reg  [23:0] out_osca_rgb,
    output reg         out_hit_oscb,
    output reg  [23:0] out_oscb_rgb
);

    // --------------------------------------------------------------------------
    // Stage 0: Window Detection & Phase Generation
    // --------------------------------------------------------------------------
    reg        s0_in_osca_win;
    reg        s0_in_oscb_win;
    reg [8:0]  s0_phase_a;
    reg [8:0]  s0_phase_b;
    reg [6:0]  s0_wt_a, s0_wt_b;
    reg [1:0]  s0_wave_a, s0_wave_b;
    reg        s0_pwr_a, s0_pwr_b;
    reg [13:0] s0_x, s0_y;

    wire in_osca_box = (in_x >= `OSCA_WIN_X0) && (in_x <= `OSCA_WIN_X1) &&
                       (in_y >= `OSCA_WIN_Y0) && (in_y <= `OSCA_WIN_Y1);
    wire in_oscb_box = (in_x >= `OSCB_WIN_X0) && (in_x <= `OSCB_WIN_X1) &&
                       (in_y >= `OSCB_WIN_Y0) && (in_y <= `OSCB_WIN_Y1);

    wire [13:0] rel_x_a = in_x - `OSCA_WIN_X0;
    wire [13:0] rel_x_b = in_x - `OSCB_WIN_X0;

    // Phase: 2 cycles across 376 pixels -> Phase = (rel_x * 512) / 376 approx (rel_x * 348) >> 8
    wire [21:0] p_calc_a = rel_x_a * 9'd348;
    wire [21:0] p_calc_b = rel_x_b * 9'd348;

    always @(posedge clk) begin
        s0_x           <= in_x;
        s0_y           <= in_y;
        s0_in_osca_win <= in_osca_box;
        s0_in_oscb_win <= in_oscb_box;
        s0_phase_a     <= p_calc_a[16:8];
        s0_phase_b     <= p_calc_b[16:8];
        s0_wt_a        <= wt_pos_a;
        s0_wt_b        <= wt_pos_b;
        s0_wave_a      <= val_osca_wave;
        s0_wave_b      <= val_oscb_wave;
        s0_pwr_a       <= val_osca_power;
        s0_pwr_b       <= val_oscb_power;
    end

    // Sine Table Lookups
    wire [7:0] sine_a, sine_b;
    sine_table u_sine_a (
        .clk      (clk),
        .phase    (s0_phase_a[7:0]),
        .sine_out (sine_a)
    );
    sine_table u_sine_b (
        .clk      (clk),
        .phase    (s0_phase_b[7:0]),
        .sine_out (sine_b)
    );

    // --------------------------------------------------------------------------
    // Stage 1: Multi-Waveform Synthesis & Morphing
    // --------------------------------------------------------------------------
    reg        s1_in_osca;
    reg        s1_in_oscb;
    reg [13:0] s1_x, s1_y;
    reg signed [8:0] s1_off_a, s1_off_b;
    reg        s1_pwr_a, s1_pwr_b;
    reg        s1_grid_a, s1_grid_b;

    // A. OSC A Wave Archetypes
    wire [7:0] saw_a = s0_phase_a[7:0];
    wire [7:0] tri_a = (saw_a < 8'd128) ? (saw_a << 1) : (8'd255 - ((saw_a - 8'd128) << 1));
    wire [7:0] pw_thresh_a = 8'd96 + {1'b0, s0_wt_a};
    wire signed [8:0] s_off_a   = {1'b0, sine_a} - 9'd128;
    wire signed [8:0] saw_off_a = {1'b0, saw_a} - 9'd128;
    wire signed [8:0] sq_off_a  = (saw_a < pw_thresh_a) ? 9'sd100 : -9'sd100;
    wire signed [8:0] tri_off_a = {1'b0, tri_a} - 9'd128;

    // Morph Sine with fold
    wire signed [15:0] blend_sine_a = (s_off_a * $signed({1'b0, 7'd127 - s0_wt_a})) +
                                      (saw_off_a * $signed({1'b0, s0_wt_a}));
    wire signed [8:0] morph_sine_a = blend_sine_a[14:7];

    reg signed [8:0] chosen_off_a;
    always @(*) begin
        case (s0_wave_a)
            2'd0: chosen_off_a = morph_sine_a;
            2'd1: chosen_off_a = saw_off_a;
            2'd2: chosen_off_a = sq_off_a;
            2'd3: chosen_off_a = tri_off_a;
        endcase
    end

    // B. OSC B Wave Archetypes
    wire [7:0] saw_b = s0_phase_b[7:0];
    wire [7:0] tri_b = (saw_b < 8'd128) ? (saw_b << 1) : (8'd255 - ((saw_b - 8'd128) << 1));
    wire [7:0] pw_thresh_b = 8'd96 + {1'b0, s0_wt_b};
    wire signed [8:0] s_off_b   = {1'b0, sine_b} - 9'd128;
    wire signed [8:0] saw_off_b = {1'b0, saw_b} - 9'd128;
    wire signed [8:0] sq_off_b  = (saw_b < pw_thresh_b) ? 9'sd100 : -9'sd100;
    wire signed [8:0] tri_off_b = {1'b0, tri_b} - 9'd128;

    wire signed [15:0] blend_sine_b = (s_off_b * $signed({1'b0, 7'd127 - s0_wt_b})) +
                                      (saw_off_b * $signed({1'b0, s0_wt_b}));
    wire signed [8:0] morph_sine_b = blend_sine_b[14:7];

    reg signed [8:0] chosen_off_b;
    always @(*) begin
        case (s0_wave_b)
            2'd0: chosen_off_b = morph_sine_b;
            2'd1: chosen_off_b = saw_off_b;
            2'd2: chosen_off_b = sq_off_b;
            2'd3: chosen_off_b = tri_off_b;
        endcase
    end
    // Keep the historical signed arithmetic exactly: 6'sd46 is -18 and
    // 8'sd128 is -128, hence trunc_toward_zero(offset * 18 / 128).
    // Split morphing and raster scaling across the existing two stages.
    function signed [13:0] display_deviation;
        input signed [8:0] offset;
        reg signed [13:0] scaled;
        begin
            scaled = ({{5{offset[8]}},offset} <<< 4) +
                     ({{5{offset[8]}},offset} <<< 1);
            display_deviation = (scaled < 0) ? -((-scaled) >>> 7) : (scaled >>> 7);
        end
    endfunction
    wire [13:0] s1_target_ya = s1_pwr_a ? (`OSCA_WIN_CY-display_deviation(s1_off_a)) : `OSCA_WIN_CY;
    wire [13:0] s1_target_yb = s1_pwr_b ? (`OSCB_WIN_CY-display_deviation(s1_off_b)) : `OSCB_WIN_CY;

    always @(posedge clk) begin
        s1_x       <= s0_x;
        s1_y       <= s0_y;
        s1_in_osca <= s0_in_osca_win;
        s1_in_oscb <= s0_in_oscb_win;
        s1_pwr_a   <= s0_pwr_a;
        s1_pwr_b   <= s0_pwr_b;

        s1_off_a <= chosen_off_a;
        s1_off_b <= chosen_off_b;

        s1_grid_a <= (s0_y == `OSCA_WIN_CY) || (s0_x[4:0] == 5'd0 && s0_y[4:0] == 5'd0);
        s1_grid_b <= (s0_y == `OSCB_WIN_CY) || (s0_x[4:0] == 5'd0 && s0_y[4:0] == 5'd0);
    end

    // --------------------------------------------------------------------------
    // Stage 2: Geometric Hit & Multi-Layer Pixel Compositing
    // --------------------------------------------------------------------------
    function signed [15:0] display_deviation_q2;
        input signed [8:0] offset;
        reg signed [15:0] scaled;
        begin
            scaled=({{7{offset[8]}},offset}<<<4)+({{7{offset[8]}},offset}<<<1);
            display_deviation_q2=scaled<0 ? -((-scaled)>>>5) : scaled>>>5;
        end
    endfunction
    wire [15:0] target_a_q2=(`OSCA_WIN_CY<<2)-(s1_pwr_a ? display_deviation_q2(s1_off_a) : 16'd0);
    wire [15:0] target_b_q2=(`OSCB_WIN_CY<<2)-(s1_pwr_b ? display_deviation_q2(s1_off_b) : 16'd0);
    wire [2:0] alpha_a=curve_alpha_q4(s1_y,target_a_q2,5'd3);
    wire [2:0] alpha_b=curve_alpha_q4(s1_y,target_b_q2,5'd3);
    wire fill_a=s1_pwr_a && (((s1_y<=`OSCA_WIN_CY) && (s1_y>=s1_target_ya)) ||
                            ((s1_y>=`OSCA_WIN_CY) && (s1_y<=s1_target_ya)));
    wire fill_b=s1_pwr_b && (((s1_y<=`OSCB_WIN_CY) && (s1_y>=s1_target_yb)) ||
                            ((s1_y>=`OSCB_WIN_CY) && (s1_y<=s1_target_yb)));
    wire [23:0] bg_a=fill_a ? `COLOR_OSCA_FILL : s1_grid_a ?
        (s1_y==`OSCA_WIN_CY ? `COLOR_GRID_AXIS : `COLOR_GRID_SUBTLE) : 24'h0C0E14;
    wire [23:0] bg_b=fill_b ? `COLOR_OSCB_FILL : s1_grid_b ?
        (s1_y==`OSCB_WIN_CY ? `COLOR_GRID_AXIS : `COLOR_GRID_SUBTLE) : 24'h0C0E14;
    // Stage three registers coverage and background before RGB arithmetic.
    reg hit_a2,hit_b2,border_a2,border_b2;
    reg [23:0] bg_a2,bg_b2,fg_a2,fg_b2;
    reg [2:0] alpha_a2,alpha_b2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hit_a2<=0;hit_b2<=0;border_a2<=0;border_b2<=0;
            bg_a2<=0;bg_b2<=0;fg_a2<=0;fg_b2<=0;alpha_a2<=0;alpha_b2<=0;
        end else begin
            hit_a2<=s1_in_osca;hit_b2<=s1_in_oscb;
            border_a2<=s1_x==`OSCA_WIN_X0 || s1_x==`OSCA_WIN_X1 ||
                       s1_y==`OSCA_WIN_Y0 || s1_y==`OSCA_WIN_Y1;
            border_b2<=s1_x==`OSCB_WIN_X0 || s1_x==`OSCB_WIN_X1 ||
                       s1_y==`OSCB_WIN_Y0 || s1_y==`OSCB_WIN_Y1;
            bg_a2<=bg_a;bg_b2<=bg_b;alpha_a2<=alpha_a;alpha_b2<=alpha_b;
            fg_a2<=s1_pwr_a ? `COLOR_OSCA_LINE : 24'h222A38;
            fg_b2<=s1_pwr_b ? `COLOR_OSCB_LINE : 24'h222A38;
        end
    end
    // Stage four performs only registered color blending and border selection.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_hit_osca<=0;out_hit_oscb<=0;out_osca_rgb<=0;out_oscb_rgb<=0;
        end else begin
            out_hit_osca<=hit_a2;out_hit_oscb<=hit_b2;
            out_osca_rgb<=!hit_a2 ? 24'd0 : border_a2 ? `COLOR_PANEL_BORDER :
                blend_rgb_q4(fg_a2,bg_a2,alpha_a2);
            out_oscb_rgb<=!hit_b2 ? 24'd0 : border_b2 ? `COLOR_PANEL_BORDER :
                blend_rgb_q4(fg_b2,bg_b2,alpha_b2);
        end
    end
endmodule
