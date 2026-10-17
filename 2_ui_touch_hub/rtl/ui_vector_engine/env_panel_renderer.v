// ==============================================================================
// Module: env_panel_renderer.v
// Description: Procedural ADSR Dynamic Envelope Window Renderer
//              Dynamic Attack, Hold, Decay, Sustain level, and Release curves,
//              interactive control handles (nodes), cobalt fill, and grid ticks.
//              Optimized with background iterative slope engine to achieve
//              zero-latency pixel-rate pipeline timing (0 division in pixel path).
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "pixel_coverage.vh"

module env_panel_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Video beam coordinates
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,

    // Envelope Parameters
    input  wire [1:0]  val_env_tab,
    input  wire [6:0]  env_attack,
    input  wire [6:0]  env_hold,
    input  wire [6:0]  env_decay,
    input  wire [6:0]  env_sustain,
    input  wire [6:0]  env_release,

    // Outputs
    output reg         out_hit_env,
    output reg  [23:0] out_env_rgb
);

    // --------------------------------------------------------------------------
    // Stage 0: Window Detection & Segment Endpoint Pre-computation
    // --------------------------------------------------------------------------
    reg        s0_in_win;
    reg [13:0] s0_x, s0_y;
    reg [13:0] s0_rel_x;
    reg [13:0] s0_pt_a, s0_pt_h, s0_pt_d, s0_pt_s, s0_pt_r;
    reg [13:0] s0_y_sus;
    reg [13:0] s0_h_dec, s0_h_rel;

    wire in_box = (in_x >= `ENV_WIN_X0) && (in_x <= `ENV_WIN_X1) &&
                  (in_y >= `ENV_WIN_Y0) && (in_y <= `ENV_WIN_Y1);

    // Segment Lengths (Dynamic based on parameters)
    wire [13:0] len_a = `ENV_LEN_A(env_attack);
    wire [13:0] len_h = `ENV_LEN_H(env_hold);
    wire [13:0] len_d = `ENV_LEN_D(env_decay);
    wire [13:0] len_s = 14'd120;
    wire [13:0] len_r = `ENV_LEN_R(env_release);

    // Sustain level: 424 (100%) to 568 (0%) - Delta = 144px
    reg [1:0]  s0_tab;

    wire [13:0] calc_y_sus = `ENV_BASE_Y - `ENV_SUS_HEIGHT(env_sustain);

    always @(posedge clk) begin
        s0_x       <= in_x;
        s0_y       <= in_y;
        s0_in_win  <= in_box;
        s0_rel_x   <= (in_x >= `ENV_WIN_X0) ? (in_x - `ENV_WIN_X0) : 14'd0;
        s0_tab     <= val_env_tab;

        s0_pt_a    <= len_a;
        s0_pt_h    <= len_a + len_h;
        s0_pt_d    <= len_a + len_h + len_d;
        s0_pt_s    <= len_a + len_h + len_d + len_s;
        s0_pt_r    <= len_a + len_h + len_d + len_s + len_r;

        s0_y_sus   <= calc_y_sus;
        s0_h_dec   <= (calc_y_sus > `ENV_PEAK_Y) ? (calc_y_sus - `ENV_PEAK_Y) : 14'd0;
        s0_h_rel   <= (`ENV_BASE_Y > calc_y_sus) ? (`ENV_BASE_Y - calc_y_sus) : 14'd0;
    end

    // --------------------------------------------------------------------------
    // Background Quasi-Static Slope Divider Engine
    // Avoids unpipelined per-pixel hardware division by computing fixed-point slopes
    // in the background at ~1MHz update rate with a 20-bit restoring divider.
    // --------------------------------------------------------------------------
    reg [1:0]  calc_target; // 0: slope_a, 1: slope_d, 2: slope_r
    reg [4:0]  div_step;
    reg [14:0] div_acc;
    reg [19:0] div_quot;
    reg [19:0] div_num;
    reg [13:0] div_den;

    reg [15:0] reg_slope_a;
    reg [15:0] reg_slope_d;
    reg [15:0] reg_slope_r;

    wire [15:0] trial_acc = (div_step >= 5'd1 && div_step <= 5'd20) ?
                            {div_acc[14:0], div_num[20 - div_step]} : 16'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_target <= 2'd0;
            div_step    <= 5'd0;
            div_acc     <= 15'd0;
            div_quot    <= 20'd0;
            div_num     <= 20'd0;
            div_den     <= 14'd1;
            reg_slope_a <= 16'd4100;
            reg_slope_d <= 16'd2048;
            reg_slope_r <= 16'd2048;
        end else begin
            if (div_step == 5'd0) begin
                div_acc  <= 15'd0;
                div_quot <= 20'd0;
                div_step <= 5'd1;
                case (calc_target)
                    2'd0: begin
                        div_num <= 20'd144 << 12;
                        div_den <= (len_a != 14'd0) ? len_a : 14'd1;
                    end
                    2'd1: begin
                        div_num <= {6'd0, s0_h_dec} << 12;
                        div_den <= (len_d != 14'd0) ? len_d : 14'd1;
                    end
                    default: begin
                        div_num <= {6'd0, s0_h_rel} << 12;
                        div_den <= (len_r != 14'd0) ? len_r : 14'd1;
                    end
                endcase
            end else if (div_step <= 5'd20) begin
                if (trial_acc >= {2'b00, div_den}) begin
                    div_acc  <= trial_acc[14:0] - {1'b0, div_den};
                    div_quot <= {div_quot[18:0], 1'b1};
                end else begin
                    div_acc  <= trial_acc[14:0];
                    div_quot <= {div_quot[18:0], 1'b0};
                end
                div_step <= div_step + 5'd1;
            end else begin
                div_step <= 5'd0;
                case (calc_target)
                    2'd0: begin
                        reg_slope_a <= div_quot[15:0];
                        calc_target <= 2'd1;
                    end
                    2'd1: begin
                        reg_slope_d <= div_quot[15:0];
                        calc_target <= 2'd2;
                    end
                    default: begin
                        reg_slope_r <= div_quot[15:0];
                        calc_target <= 2'd0;
                    end
                endcase
            end
        end
    end

    // --------------------------------------------------------------------------
    // Stage 1: Pipelined Segment Height Calculation (Pure Multiplier/DSP)
    // --------------------------------------------------------------------------
    reg        s1_in_win;
    reg [13:0] s1_x, s1_y;
    reg [13:0] s1_target_y;
    reg        s1_hit_node;
    reg        s1_grid;

    // Fixed-point piecewise linear evaluations (14-bit x 16-bit DSP multiplies)
    wire [29:0] dy_a = (s0_rel_x * reg_slope_a);
    wire [29:0] dy_d = ((s0_rel_x >= s0_pt_h) ? (s0_rel_x - s0_pt_h) : 14'd0) * reg_slope_d;
    wire [29:0] dy_r = ((s0_rel_x >= s0_pt_s) ? (s0_rel_x - s0_pt_s) : 14'd0) * reg_slope_r;

    reg [13:0] calc_y;
    reg [15:0] calc_y_q2;
    reg [4:0] calc_half_width;
    reg [15:0] s1_target_q2;
    reg [4:0] s1_half_width;
    // Keep quarter-pixel geometry instead of rounding every column to a row.
    always @(*) begin
        calc_half_width=5'd3;
        if(s0_rel_x<=s0_pt_a) begin
            calc_y_q2=(`ENV_BASE_Y<<2)-dy_a[25:10];
            if(reg_slope_a[15:11]>3) calc_half_width=reg_slope_a[15:11];
        end else if(s0_rel_x<=s0_pt_h) calc_y_q2=`ENV_PEAK_Y<<2;
        else if(s0_rel_x<=s0_pt_d) begin
            calc_y_q2=(`ENV_PEAK_Y<<2)+dy_d[25:10];
            if(reg_slope_d[15:11]>3) calc_half_width=reg_slope_d[15:11];
        end else if(s0_rel_x<=s0_pt_s) calc_y_q2={s0_y_sus,2'b0};
        else if(s0_rel_x<=s0_pt_r) begin
            calc_y_q2={s0_y_sus,2'b0}+dy_r[25:10];
            if(reg_slope_r[15:11]>3) calc_half_width=reg_slope_r[15:11];
        end else calc_y_q2=`ENV_BASE_Y<<2;
    end
    always @(*) begin
        if (s0_rel_x <= s0_pt_a) begin
            // Attack Ramp: from ENV_BASE_Y up to ENV_PEAK_Y
            calc_y = `ENV_BASE_Y - dy_a[25:12];
        end else if (s0_rel_x <= s0_pt_h) begin
            // Hold Line: flat at ENV_PEAK_Y
            calc_y = `ENV_PEAK_Y;
        end else if (s0_rel_x <= s0_pt_d) begin
            // Decay Ramp: from ENV_PEAK_Y down to y_sus
            calc_y = `ENV_PEAK_Y + dy_d[25:12];
        end else if (s0_rel_x <= s0_pt_s) begin
            // Sustain Line: flat at y_sus
            calc_y = s0_y_sus;
        end else if (s0_rel_x <= s0_pt_r) begin
            // Release Ramp: from y_sus down to ENV_BASE_Y
            calc_y = s0_y_sus + dy_r[25:12];
        end else begin
            calc_y = `ENV_BASE_Y;
        end
    end

    // Node Handles: Origin, Attack Peak, Sustain Point, Release End
    function is_near_node;
        input [13:0] x, y, nx, ny;
        reg [13:0] dx, dy;
        begin
            dx = (x >= nx) ? (x - nx) : (nx - x);
            dy = (y >= ny) ? (y - ny) : (ny - y);
            // Exact radius-five disc, with no multiply on the raster path.
            is_near_node = (dx == 0 && dy <= 5) ||
                (dx >= 1 && dx <= 3 && dy <= 4) ||
                (dx == 4 && dy <= 3) || (dx == 5 && dy == 0);
        end
    endfunction

    wire near_n0 = is_near_node(s0_x, s0_y, `ENV_WIN_X0, `ENV_BASE_Y);
    wire near_n1 = is_near_node(s0_x, s0_y, `ENV_WIN_X0 + s0_pt_a, `ENV_PEAK_Y);
    wire near_n2 = is_near_node(s0_x, s0_y, `ENV_WIN_X0 + s0_pt_d, s0_y_sus);
    wire near_n3 = is_near_node(s0_x, s0_y, `ENV_WIN_X0 + s0_pt_r, `ENV_BASE_Y);
    // Hold handle is raised twelve pixels to remain separate at HOLD=0.
    wire near_hold = is_near_node(s0_x,s0_y,`ENV_WIN_X0+s0_pt_h,`ENV_PEAK_Y-14'd12);
    wire near_sustain = is_near_node(s0_x,s0_y,`ENV_WIN_X0+s0_pt_s,s0_y_sus);
    wire hold_stem = s0_x==`ENV_WIN_X0+s0_pt_h && s0_y>=`ENV_PEAK_Y-14'd12 && s0_y<=`ENV_PEAK_Y;

    reg [1:0]  s1_tab;

    always @(posedge clk) begin
        s1_x        <= s0_x;
        s1_y        <= s0_y;
        s1_in_win   <= s0_in_win;
        s1_tab      <= s0_tab;
        s1_target_y <= calc_y;
        s1_target_q2 <= calc_y_q2;
        s1_half_width <= calc_half_width;
        s1_hit_node <= (near_n0 || near_n1 || near_n2 || near_n3 || near_hold || near_sustain || hold_stem);

        // Time Grid Ticks (1s, 2s, 3s vertical marks)
        s1_grid <= (s0_x == `ENV_WIN_X0 + 14'd180) ||
                   (s0_x == `ENV_WIN_X0 + 14'd360) ||
                   (s0_x == `ENV_WIN_X0 + 14'd540);
    end

    // --------------------------------------------------------------------------
    // Stage 2: Geometric Hit & Multi-Layer Pixel Compositing
    // --------------------------------------------------------------------------
    wire [23:0] env_stroke_color = (s1_tab == 2'd1) ? 24'h20E8A0 : // Tab 1: Emerald
                                   (s1_tab == 2'd2) ? 24'hFFA834 : // Tab 2: Amber
                                                      24'h38B0FF;  // Tab 0: Cobalt

    wire [23:0] env_fill_color   = (s1_tab == 2'd1) ? 24'h0C281E :
                                   (s1_tab == 2'd2) ? 24'h281E0C :
                                                      `COLOR_ENV_FILL;
    wire [2:0] stroke_alpha=curve_alpha_q4(s1_y,s1_target_q2,s1_half_width);
    wire [23:0] curve_bg=(s1_y>=s1_target_y && s1_y<=`ENV_BASE_Y) ? env_fill_color :
        s1_grid ? `COLOR_GRID_SUBTLE : 24'h0B0E14;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hit_env <= 1'b0;
            out_env_rgb <= 24'h0;
        end else begin
            out_hit_env <= 1'b0;
            out_env_rgb <= 24'h0;

            if (s1_in_win) begin
                out_hit_env <= 1'b1;

                // Priority 1: Window Bevel Frame
                if ((s1_x == `ENV_WIN_X0) || (s1_x == `ENV_WIN_X1) ||
                    (s1_y == `ENV_WIN_Y0) || (s1_y == `ENV_WIN_Y1)) begin
                    out_env_rgb <= `COLOR_PANEL_BORDER;
                end
                // Priority 2: Control Handle Nodes (White Circles)
                else if (s1_hit_node) begin
                    out_env_rgb <= `COLOR_ENV_NODE;
                end
                // Priority 3: ADSR Curve Stroke (2px Neon Line)
                else if (stroke_alpha!=0) begin
                    out_env_rgb <= blend_rgb_q4(env_stroke_color,curve_bg,stroke_alpha);
                end
                // Priority 4: Translucent Fill Under Curve
                else if ((s1_y >= s1_target_y) && (s1_y <= `ENV_BASE_Y)) begin
                    out_env_rgb <= env_fill_color;
                end
                // Priority 5: Time Grid Ticks
                else if (s1_grid) begin
                    out_env_rgb <= `COLOR_GRID_SUBTLE;
                end
                // Window dark background
                else begin
                    out_env_rgb <= 24'h0B0E14;
                end
            end
        end
    end

endmodule
