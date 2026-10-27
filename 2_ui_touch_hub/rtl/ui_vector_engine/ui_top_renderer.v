// ==============================================================================
// Module: ui_top_renderer.v
// Description: Master Procedural Vector UI Compositor for 1280x720@60Hz
//              - Full Serum-style Synthesizer Console Layout (Zero Piano Keyboard)
//              - Combines procedural panels, wavetable scopes, filter curve,
//              - ADSR dynamic envelope, rotary knobs, buttons, and switches.
//              - ZERO ROM BITMAPS - ZERO ARTIFACTS - ZERO NOISE.
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

`include "params.vh"
`include "font_3x5.vh"

module ui_top_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Timing Inputs (from video_timing_ctrl)
    input  wire        in_hsync,
    input  wire        in_vsync,
    input  wire        in_den,
    input  wire [13:0] in_pixel_x,
    input  wire [13:0] in_pixel_y,

    // Continuous Synthesis Parameters (from param_merger)
    input  wire [6:0]  val_macro1, val_macro2, val_macro3, val_macro4, val_master_vol,
    input  wire [6:0]  val_osca_unison, val_osca_detune, val_osca_blend, val_osca_phase, val_osca_rand,
    input  wire [6:0]  val_osca_wt_pos, val_osca_warp, val_osca_pan, val_osca_vol,
    input  wire [6:0]  val_oscb_unison, val_oscb_detune, val_oscb_blend, val_oscb_phase, val_oscb_rand,
    input  wire [6:0]  val_oscb_wt_pos, val_oscb_warp, val_oscb_pan, val_oscb_vol,
    input  wire [6:0]  val_flt_cutoff, val_flt_res, val_flt_pan, val_flt_drive, val_flt_fat, val_flt_mix,
    input  wire [6:0]  val_env_attack, val_env_hold, val_env_decay, val_env_sustain, val_env_release,
    input  wire [6:0]  val_fx_reverb, val_fx_delay, val_fx_chorus, val_portamento,

    // Discrete Button / Switch States (from param_merger)
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
    input  wire [7:0]  active_btn_id,
    input  wire        btn_flash_active,

    // Selected/Touched Parameter Highlight ID
    input  wire [7:0]  selected_param_id,

    // USB Hardware Telemetry Inputs
    input  wire        usb_connected,
    input  wire        usb_conn_err,
    input  wire [1:0]  usb_dev_type,
    input  wire [15:0] usb_raw_x,
    input  wire [15:0] usb_raw_y,
    input  wire        usb_raw_down,
    input  wire [63:0] usb_dbg_report,
    input  wire [63:0] usb_dbg_regs,
    input  wire [7:0]  usb_dbg_pkt_cnt,
    input  wire [63:0] touch_diag_coords,
    input  wire [15:0] touch_diag_count,
    input  wire       touch_diag_mode,
    input  wire       ui_touch_valid, ui_touch_down,
    input  wire [13:0] ui_touch_x, ui_touch_y,

    // Audio-board I2S monitor samples in the UI pixel clock domain.
    input  wire        audio_sample_valid,
    input  wire signed [15:0] audio_sample,
    input  wire signed [15:0] audio_right_sample,
    input  wire        audio_stereo_valid,
    input  wire        audio_link_up,

    // Reserved logical adapter; same clock, one-cycle normalized parameter events.
    input wire external_param_valid,
    input wire [7:0] external_param_id,
    input wire [6:0] external_param_value,
    output wire binding_capture,
    output wire navigation_capture,
    output wire navigation_delta_valid,
    output wire [7:0] navigation_delta_id,
    output wire signed [7:0] navigation_delta_value,
    output wire fx_event_valid,
    output wire [7:0] fx_event_id,
    output wire [6:0] fx_event_value,
    output wire route_event_valid,
    output wire [7:0] route_event_target,
    output wire [1:0] route_event_source,
    output wire signed [7:0] route_event_depth,
    output wire [132:0] fx_parameter_snapshot,
    output wire [10:0] fx_switch_snapshot,
    output wire [146:0] lfo_node_snapshot,
    output wire [8:0] lfo_rate_snapshot,
    output wire [2:0] lfo_step_snapshot,
    output wire [2:0] lfo_once_snapshot,
    output wire [105:0] route_source_snapshot,
    output wire [423:0] route_depth_snapshot,
    // Hit geometry follows the visible envelope; editing still writes base values.
    output wire [34:0] display_env_snapshot,
    // Observation only; phase/running are intentionally excluded (no log flood).
    output wire [59:0] trace_lfo_state,

    // Timing & Video Outputs (to dvi_tx_top)
    output reg         out_hsync,
    output reg         out_vsync,
    output reg         out_den,
    output reg  [23:0] out_pixel_data
);
    reg [7:0] hud_selected_id /* synthesis syn_preserve=1 syn_keep=1 */;
    always @(posedge clk) hud_selected_id<=selected_param_id;


    // --------------------------------------------------------------------------
    // 1. Pipeline Delay Line for Sync Signals (3 Cycles)
    // --------------------------------------------------------------------------
    // One entry stage with a preserved local copy per renderer limits the
    // shared timing counter's fanout and cross-panel comparator sharing.
    // All layers and sync gain one cycle: total latency is seven clocks.
    wire [13:0] raster_x[0:10],raster_y[0:10];
    genvar raster_unit;
    generate for(raster_unit=0;raster_unit<11;raster_unit=raster_unit+1) begin: raster_entry
        reg [13:0] local_x /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
        reg [13:0] local_y /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
        always @(posedge clk) begin
            local_x<=in_pixel_x;local_y<=in_pixel_y;
        end
        assign raster_x[raster_unit]=local_x;
        assign raster_y[raster_unit]=local_y;
    end endgenerate
    reg raster_hsync,raster_vsync,raster_den;
    reg previous_vsync;
    wire [1:0] navigation_view;
    wire [7:0] settings_section_id;
    wire show_diagnostics;
    wire navigation_hit;
    wire [23:0] navigation_rgb;
    wire synth_touch_down=ui_touch_down && !navigation_capture;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)previous_vsync<=0;else previous_vsync<=in_vsync;
    ui_navigation_state u_navigation(.clk(clk),.rst_n(rst_n),
        .frame_start(in_vsync && !previous_vsync),
        .touch_valid(ui_touch_valid),.touch_down(ui_touch_down),.touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .view(navigation_view),.settings_section_id(settings_section_id),.capture_active(navigation_capture),.show_diagnostics(show_diagnostics),
        .delta_valid(navigation_delta_valid),.delta_id(navigation_delta_id),.delta_value(navigation_delta_value));
    ui_navigation_renderer u_navigation_render(.clk(clk),.rst_n(rst_n),
        .in_x(raster_x[10]),.in_y(raster_y[10]),.view(navigation_view),.settings_section_id(settings_section_id),
        .show_diagnostics(show_diagnostics),.usb_connected(usb_connected),.usb_error(usb_conn_err),
        .macro_values({val_macro4,val_macro3,val_macro2,val_macro1}),
        .audio_sample_valid(audio_sample_valid),.audio_sample(audio_sample),.audio_link_up(audio_link_up),
        .audio_right_sample(audio_right_sample),.audio_stereo_valid(audio_stereo_valid),
        .out_hit(navigation_hit),.out_rgb(navigation_rgb));
    always @(posedge clk) begin
        raster_hsync<=in_hsync;raster_vsync<=in_vsync;raster_den<=in_den;
    end
    reg [2:0] pipe_hsync, pipe_vsync, pipe_den;
    reg [13:0] p_x1 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] p_x2 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] p_x3;
    reg [13:0] p_y1 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] p_y2 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] p_y3;

    always @(posedge clk) begin
        pipe_hsync <= {pipe_hsync[1:0], raster_hsync};
        pipe_vsync <= {pipe_vsync[1:0], raster_vsync};
        pipe_den   <= {pipe_den[1:0],   raster_den};

        p_x1 <= raster_x[0]; p_x2 <= p_x1; p_x3 <= p_x2;
        p_y1 <= raster_y[0]; p_y2 <= p_y1; p_y3 <= p_y2;
    end

    // --------------------------------------------------------------------------
    // 2. Sub-module Instantiations
    // --------------------------------------------------------------------------


    wire [132:0] fx_values;
    wire [10:0] fx_switches;
    wire [105:0] mod_sources;
    wire [423:0] mod_depths;
    wire [370:0] mod_base,mod_preview;
    wire mod_armed,mod_dragging;
    wire [5:0] mod_hover,mod_selected;
    wire [146:0] lfo_all_nodes;
    wire [48:0] lfo_nodes;
    wire [1:0] lfo_tab,lfo_preset;
    wire [8:0] lfo_phase;
    wire [8:0] lfo_all_rates;
    wire [2:0] lfo_all_steps;
    wire [2:0] lfo_all_once;
    wire [12:0] lfo_curve_q6;
    wire [8:0] lfo_raster_index=raster_x[9]<832 ? 0 : raster_x[9]>1216 ? 384 : raster_x[9]-832;
    wire hit_fx_strip,hit_mod;
    wire [23:0] fx_strip_rgb,mod_rgb;
    assign fx_parameter_snapshot=fx_values;
    assign fx_switch_snapshot=fx_switches;
    assign lfo_node_snapshot=lfo_all_nodes;
    assign lfo_rate_snapshot=lfo_all_rates;
    assign lfo_step_snapshot=lfo_all_steps;
    assign lfo_once_snapshot=lfo_all_once;
    assign route_source_snapshot=mod_sources;
    assign route_depth_snapshot=mod_depths;
    assign display_env_snapshot=mod_preview[203+:35];
    assign mod_base[0+:7]=val_macro1;
    assign mod_base[7+:7]=val_macro2;
    assign mod_base[14+:7]=val_macro3;
    assign mod_base[21+:7]=val_macro4;
    assign mod_base[28+:7]=val_master_vol;
    assign mod_base[35+:7]=val_osca_unison;
    assign mod_base[42+:7]=val_osca_detune;
    assign mod_base[49+:7]=val_osca_blend;
    assign mod_base[56+:7]=val_osca_phase;
    assign mod_base[63+:7]=val_osca_rand;
    assign mod_base[70+:7]=val_osca_wt_pos;
    assign mod_base[77+:7]=val_osca_warp;
    assign mod_base[84+:7]=val_osca_pan;
    assign mod_base[91+:7]=val_osca_vol;
    assign mod_base[98+:7]=val_oscb_unison;
    assign mod_base[105+:7]=val_oscb_detune;
    assign mod_base[112+:7]=val_oscb_blend;
    assign mod_base[119+:7]=val_oscb_phase;
    assign mod_base[126+:7]=val_oscb_rand;
    assign mod_base[133+:7]=val_oscb_wt_pos;
    assign mod_base[140+:7]=val_oscb_warp;
    assign mod_base[147+:7]=val_oscb_pan;
    assign mod_base[154+:7]=val_oscb_vol;
    assign mod_base[161+:7]=val_flt_cutoff;
    assign mod_base[168+:7]=val_flt_res;
    assign mod_base[175+:7]=val_flt_pan;
    assign mod_base[182+:7]=val_flt_drive;
    assign mod_base[189+:7]=val_flt_fat;
    assign mod_base[196+:7]=val_flt_mix;
    assign mod_base[203+:7]=val_env_attack;
    assign mod_base[210+:7]=val_env_hold;
    assign mod_base[217+:7]=val_env_decay;
    assign mod_base[224+:7]=val_env_sustain;
    assign mod_base[231+:7]=val_env_release;
    assign mod_base[238+:133]=fx_values;

    fx_editor_state u_fx_state(.clk(clk),.rst_n(rst_n),
        .touch_valid(ui_touch_valid),.touch_down(synth_touch_down && !binding_capture),
        .touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .external_valid(external_param_valid),.external_id(external_param_id),.external_value(external_param_value),
        .values(fx_values),.switches(fx_switches),
        .event_valid(fx_event_valid),.event_id(fx_event_id),.event_value(fx_event_value));
    lfo_binding_state #(.ENABLE_CANCEL(1)) u_binding(.clk(clk),.rst_n(rst_n),
        .cancel(navigation_capture),
        .touch_valid(ui_touch_valid),.touch_down(synth_touch_down),.touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .active_tab(lfo_tab),.armed(mod_armed),.dragging(mod_dragging),.capture_active(binding_capture),
        .selected_target(mod_selected),.hover_target(mod_hover),.sources(mod_sources),.depths(mod_depths),
        .event_valid(route_event_valid),.event_target(route_event_target),
        .event_source(route_event_source),.event_depth(route_event_depth));
    modulation_preview u_mod_preview(.clk(clk),.rst_n(rst_n),
        .nodes(lfo_all_nodes),.rates(lfo_all_rates),.stepped(lfo_all_steps),
        .active_tab(lfo_tab),.active_phase(lfo_phase),.raster_index(lfo_raster_index),
        .sources(mod_sources),.depths(mod_depths),.base_values(mod_base),
        .preview_values(mod_preview),.raster_q6(lfo_curve_q6));
    fx_strip_renderer u_fx_strip(.clk(clk),.rst_n(rst_n),.in_x(raster_x[1]),.in_y(raster_y[1]),
        .values(mod_preview[238+:133]),.switches(fx_switches),.out_hit(hit_fx_strip),.out_rgb(fx_strip_rgb));
    modulation_overlay u_mod_overlay(.clk(clk),.rst_n(rst_n),.in_x(raster_x[2]),.in_y(raster_y[2]),
        .sources(mod_sources),.depths(mod_depths),.preview_values(mod_preview),
        .armed(mod_armed),.dragging(mod_dragging),.hover_target(mod_hover),.selected_target(mod_selected),
        .touch_x(ui_touch_x),.touch_y(ui_touch_y),.curve_nodes(lfo_nodes),
        .active_tab(lfo_tab),.out_hit(hit_mod),.out_rgb(mod_rgb));

    // A. Procedural Knobs (32 rotary knobs)
    wire        hit_knob;
    wire [23:0] knob_rgb;
    knob_vector_unit u_knobs (
        .clk               (clk),
        .rst_n             (rst_n),
        .in_x              (raster_x[3]),
        .in_y              (raster_y[3]),
        .val_macro1        (mod_preview[0+:7]),
        .val_macro2        (mod_preview[7+:7]),
        .val_macro3        (mod_preview[14+:7]),
        .val_macro4        (mod_preview[21+:7]),
        .val_master_vol    (mod_preview[28+:7]),
        .val_osca_unison   (mod_preview[35+:7]),
        .val_osca_detune   (mod_preview[42+:7]),
        .val_osca_blend    (mod_preview[49+:7]),
        .val_osca_phase    (mod_preview[56+:7]),
        .val_osca_rand     (mod_preview[63+:7]),
        .val_osca_wt_pos   (mod_preview[70+:7]),
        .val_osca_warp     (mod_preview[77+:7]),
        .val_osca_pan      (mod_preview[84+:7]),
        .val_osca_vol      (mod_preview[91+:7]),
        .val_oscb_unison   (mod_preview[98+:7]),
        .val_oscb_detune   (mod_preview[105+:7]),
        .val_oscb_blend    (mod_preview[112+:7]),
        .val_oscb_phase    (mod_preview[119+:7]),
        .val_oscb_rand     (mod_preview[126+:7]),
        .val_oscb_wt_pos   (mod_preview[133+:7]),
        .val_oscb_warp     (mod_preview[140+:7]),
        .val_oscb_pan      (mod_preview[147+:7]),
        .val_oscb_vol      (mod_preview[154+:7]),
        .val_flt_cutoff    (mod_preview[161+:7]),
        .val_flt_res       (mod_preview[168+:7]),
        .val_flt_pan       (mod_preview[175+:7]),
        .val_flt_drive     (mod_preview[182+:7]),
        .val_flt_fat       (mod_preview[189+:7]),
        .val_flt_mix       (mod_preview[196+:7]),
        .val_env_attack    (mod_preview[203+:7]),
        .val_env_hold      (mod_preview[210+:7]),
        .val_env_decay     (mod_preview[217+:7]),
        .val_env_sustain   (mod_preview[224+:7]),
        .val_env_release   (mod_preview[231+:7]),
        .val_fx_reverb     (val_fx_reverb),
        .val_fx_delay      (val_fx_delay),
        .val_fx_chorus     (val_fx_chorus),
        .val_portamento    (val_portamento),
        .selected_param_id (hud_selected_id),
        .out_hit_knob      (hit_knob),
        .out_knob_rgb      (knob_rgb)
    );

    // B. Procedural Buttons, Switches & Checkboxes
    wire        hit_btn;
    wire [23:0] btn_rgb;
    button_vector_unit u_buttons (
        .clk               (clk),
        .rst_n             (rst_n),
        .in_x              (raster_x[4]),
        .in_y              (raster_y[4]),
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
        .selected_param_id (hud_selected_id),
        .active_btn_id     (active_btn_id),
        .btn_flash_active  (btn_flash_active),
        .out_hit_btn       (hit_btn),
        .out_btn_rgb       (btn_rgb)
    );

    // C. OSC A & OSC B Dynamic Wavetables
    wire        hit_osca, hit_oscb;
    wire [23:0] osca_rgb, oscb_rgb;
    osc_panel_renderer u_osc_scope (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_x           (raster_x[5]),
        .in_y           (raster_y[5]),
        .val_osca_power (val_osca_power),
        .val_oscb_power (val_oscb_power),
        .val_osca_wave  (val_osca_wave),
        .val_oscb_wave  (val_oscb_wave),
        .wt_pos_a       (mod_preview[70+:7]),
        .wt_pos_b       (mod_preview[133+:7]),
        .out_hit_osca   (hit_osca),
        .out_osca_rgb   (osca_rgb),
        .out_hit_oscb   (hit_oscb),
        .out_oscb_rgb   (oscb_rgb)
    );

    // D. Filter Frequency Response Curve Scope
    wire        hit_flt;
    wire [23:0] flt_rgb;
    filter_panel_renderer u_flt_scope (
        .clk           (clk),
        .rst_n         (rst_n),
        .in_x          (raster_x[6]),
        .in_y          (raster_y[6]),
        .val_flt_power (val_flt_power),
        .val_flt_type  (val_flt_type),
        .flt_cutoff    (mod_preview[161+:7]),
        .flt_res       (mod_preview[168+:7]),
        .out_hit_flt   (hit_flt),
        .out_flt_rgb   (flt_rgb)
    );

    // E. Expanded ADSR Dynamic Envelope Scope
    wire        hit_env;
    wire [23:0] env_rgb;
    env_panel_renderer u_env_scope (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_x        (raster_x[7]),
        .in_y        (raster_y[7]),
        .val_env_tab (val_env_tab),
        .env_attack  (mod_preview[203+:7]),
        .env_hold    (mod_preview[210+:7]),
        .env_decay   (mod_preview[217+:7]),
        .env_sustain (mod_preview[224+:7]),
        .env_release (mod_preview[231+:7]),
        .out_hit_env (hit_env),
        .out_env_rgb (env_rgb)
    );

    // F. Local LFO editor; independent state, no audio/MIDI modulation yet.
    wire        hit_fx;
    wire [23:0] fx_rgb;
    wire hit_curve_hint;
    wire [23:0] curve_hint_rgb;
    curve_hint_renderer u_curve_hints(
        .clk(clk),.rst_n(rst_n),.in_x(raster_x[8]),.in_y(raster_y[8]),.env_tab(val_env_tab),
        .out_hit(hit_curve_hint),.out_rgb(curve_hint_rgb)
    );
    wire [2:0] lfo_rate;
    wire lfo_once, lfo_stepped, lfo_running;
    assign trace_lfo_state={lfo_tab,lfo_preset,lfo_rate,lfo_once,lfo_stepped,2'b0,lfo_nodes};
    lfo_editor_state u_lfo_state (
        .clk(clk), .rst_n(rst_n),
        .touch_valid(ui_touch_valid), .touch_down(synth_touch_down && !binding_capture),
        .touch_x(ui_touch_x), .touch_y(ui_touch_y),
        .active_tab(lfo_tab), .nodes(lfo_nodes), .rate(lfo_rate),
        .once_mode(lfo_once), .stepped(lfo_stepped), .preset(lfo_preset),
        .all_nodes(lfo_all_nodes),.all_rates(lfo_all_rates),.all_stepped(lfo_all_steps),.all_once(lfo_all_once),
        .phase(lfo_phase), .running(lfo_running)
    );
    lfo_panel_renderer u_lfo_panel (
        .clk(clk), .rst_n(rst_n), .in_x(raster_x[9]), .in_y(raster_y[9]),
        .active_tab(lfo_tab), .nodes(lfo_nodes), .rate(lfo_rate),
        .once_mode(lfo_once), .stepped(lfo_stepped), .preset(lfo_preset),
        .curve_q6(lfo_curve_q6), .phase(lfo_phase), .running(lfo_running), .out_hit(hit_fx), .out_rgb(fx_rgb)
    );

    // --------------------------------------------------------------------------
    // 3. Procedural Background Panels & Architectural Framing (Stage 2)
    // --------------------------------------------------------------------------
    reg        is_panel_body;
    reg        is_panel_border;
    reg        is_panel_header;
    reg [23:0] decor_rgb;

    // Helper: Bounding Box Hit
    function in_rect;
        input [13:0] x, y, x0, x1, y0, y1;
        begin
            in_rect = (x >= x0) && (x <= x1) && (y >= y0) && (y <= y1);
        end
    endfunction

    // Helper: 1px Border Hit
    function on_border;
        input [13:0] x, y, x0, x1, y0, y1;
        begin
            on_border = (((x == x0) || (x == x1)) && (y >= y0 && y <= y1)) ||
                        (((y == y0) || (y == y1)) && (x >= x0 && x <= x1));
        end
    endfunction

    wire in_osca_p = in_rect(p_x2, p_y2, `OSCA_PANEL_X0, `OSCA_PANEL_X1, `OSCA_PANEL_Y0, `OSCA_PANEL_Y1);
    wire in_oscb_p = in_rect(p_x2, p_y2, `OSCB_PANEL_X0, `OSCB_PANEL_X1, `OSCB_PANEL_Y0, `OSCB_PANEL_Y1);
    wire in_flt_p  = in_rect(p_x2, p_y2, `FLT_PANEL_X0,  `FLT_PANEL_X1,  `FLT_PANEL_Y0,  `FLT_PANEL_Y1);
    wire in_env_p  = in_rect(p_x2, p_y2, `ENV_PANEL_X0,  `ENV_PANEL_X1,  `ENV_PANEL_Y0,  `ENV_PANEL_Y1);
    wire in_fx_p   = in_rect(p_x2, p_y2, `FX_PANEL_X0,   `FX_PANEL_X1,   `FX_PANEL_Y0,   `FX_PANEL_Y1);

    wire on_osca_b = on_border(p_x2, p_y2, `OSCA_PANEL_X0, `OSCA_PANEL_X1, `OSCA_PANEL_Y0, `OSCA_PANEL_Y1);
    wire on_oscb_b = on_border(p_x2, p_y2, `OSCB_PANEL_X0, `OSCB_PANEL_X1, `OSCB_PANEL_Y0, `OSCB_PANEL_Y1);
    wire on_flt_b  = on_border(p_x2, p_y2, `FLT_PANEL_X0,  `FLT_PANEL_X1,  `FLT_PANEL_Y0,  `FLT_PANEL_Y1);
    wire on_env_b  = on_border(p_x2, p_y2, `ENV_PANEL_X0,  `ENV_PANEL_X1,  `ENV_PANEL_Y0,  `ENV_PANEL_Y1);
    wire on_fx_b   = on_border(p_x2, p_y2, `FX_PANEL_X0,   `FX_PANEL_X1,   `FX_PANEL_Y0,   `FX_PANEL_Y1);

    // Header Strips (Height 26px inside each panel)
    wire on_hdr_osca = in_rect(p_x2, p_y2, `OSCA_PANEL_X0, `OSCA_PANEL_X1, `OSCA_PANEL_Y0, `OSCA_PANEL_Y0 + 14'd26);
    wire on_hdr_oscb = in_rect(p_x2, p_y2, `OSCB_PANEL_X0, `OSCB_PANEL_X1, `OSCB_PANEL_Y0, `OSCB_PANEL_Y0 + 14'd26);
    wire on_hdr_flt  = in_rect(p_x2, p_y2, `FLT_PANEL_X0,  `FLT_PANEL_X1,  `FLT_PANEL_Y0,  `FLT_PANEL_Y0 + 14'd26);
    wire on_hdr_env  = in_rect(p_x2, p_y2, `ENV_PANEL_X0,  `ENV_PANEL_X1,  `ENV_PANEL_Y0,  `ENV_PANEL_Y0 + 14'd26);
    wire on_hdr_fx   = in_rect(p_x2, p_y2, `FX_PANEL_X0,   `FX_PANEL_X1,   `FX_PANEL_Y0,   `FX_PANEL_Y0 + 14'd26);

    // Sub-header inside FX panel for "MASTER FX & VOICING" (Y: 566..588)
    wire on_sub_fx   = in_rect(p_x2, p_y2, `FX_PANEL_X0 + 14'd4, `FX_PANEL_X1 - 14'd4, 14'd566, 14'd588);

    // --------------------------------------------------------------------------
    // Live Parameter HUD Value Multiplexer (Header Bar Display)
    // --------------------------------------------------------------------------
    reg [6:0] sel_val_comb;
    reg [6:0] sel_val;
    always @(*) begin
        case (hud_selected_id)
            `PARAM_ID_MACRO1:       sel_val_comb = val_macro1;
            `PARAM_ID_MACRO2:       sel_val_comb = val_macro2;
            `PARAM_ID_MACRO3:       sel_val_comb = val_macro3;
            `PARAM_ID_MACRO4:       sel_val_comb = val_macro4;
            `PARAM_ID_MASTER_VOL:   sel_val_comb = val_master_vol;
            `PARAM_ID_OSCA_UNISON:  sel_val_comb = val_osca_unison;
            `PARAM_ID_OSCA_DETUNE:  sel_val_comb = val_osca_detune;
            `PARAM_ID_OSCA_BLEND:   sel_val_comb = val_osca_blend;
            `PARAM_ID_OSCA_PHASE:   sel_val_comb = val_osca_phase;
            `PARAM_ID_OSCA_RAND:    sel_val_comb = val_osca_rand;
            `PARAM_ID_OSCA_WT_POS:  sel_val_comb = val_osca_wt_pos;
            `PARAM_ID_OSCA_WARP:    sel_val_comb = val_osca_warp;
            `PARAM_ID_OSCA_PAN:     sel_val_comb = val_osca_pan;
            `PARAM_ID_OSCA_VOL:     sel_val_comb = val_osca_vol;
            `PARAM_ID_OSCB_UNISON:  sel_val_comb = val_oscb_unison;
            `PARAM_ID_OSCB_DETUNE:  sel_val_comb = val_oscb_detune;
            `PARAM_ID_OSCB_BLEND:   sel_val_comb = val_oscb_blend;
            `PARAM_ID_OSCB_PHASE:   sel_val_comb = val_oscb_phase;
            `PARAM_ID_OSCB_RAND:    sel_val_comb = val_oscb_rand;
            `PARAM_ID_OSCB_WT_POS:  sel_val_comb = val_oscb_wt_pos;
            `PARAM_ID_OSCB_WARP:    sel_val_comb = val_oscb_warp;
            `PARAM_ID_OSCB_PAN:     sel_val_comb = val_oscb_pan;
            `PARAM_ID_OSCB_VOL:     sel_val_comb = val_oscb_vol;
            `PARAM_ID_FLT_CUTOFF:   sel_val_comb = val_flt_cutoff;
            `PARAM_ID_FLT_RES:      sel_val_comb = val_flt_res;
            `PARAM_ID_FLT_PAN:      sel_val_comb = val_flt_pan;
            `PARAM_ID_FLT_DRIVE:    sel_val_comb = val_flt_drive;
            `PARAM_ID_FLT_FAT:      sel_val_comb = val_flt_fat;
            `PARAM_ID_FLT_MIX:      sel_val_comb = val_flt_mix;
            `PARAM_ID_ENV1_ATTACK:  sel_val_comb = val_env_attack;
            `PARAM_ID_ENV1_HOLD:    sel_val_comb = val_env_hold;
            `PARAM_ID_ENV1_DECAY:   sel_val_comb = val_env_decay;
            `PARAM_ID_ENV1_SUSTAIN: sel_val_comb = val_env_sustain;
            `PARAM_ID_ENV1_RELEASE: sel_val_comb = val_env_release;
            `PARAM_ID_FX_REVERB:    sel_val_comb = val_fx_reverb;
            `PARAM_ID_FX_DELAY:     sel_val_comb = val_fx_delay;
            `PARAM_ID_FX_CHORUS:    sel_val_comb = val_fx_chorus;
            `PARAM_ID_PORTAMENTO:   sel_val_comb = val_portamento;
            `PARAM_ID_OSCA_OCT:     sel_val_comb = {3'b000, val_osca_oct};
            `PARAM_ID_OSCA_SEMI:    sel_val_comb = {2'b00, val_osca_semi};
            `PARAM_ID_OSCA_FINE:    sel_val_comb = val_osca_fine;
            `PARAM_ID_OSCB_OCT:     sel_val_comb = {3'b000, val_oscb_oct};
            `PARAM_ID_OSCB_SEMI:    sel_val_comb = {2'b00, val_oscb_semi};
            `PARAM_ID_OSCB_FINE:    sel_val_comb = val_oscb_fine;
            `PARAM_ID_OSCA_WAVE:    sel_val_comb = {5'd0, val_osca_wave};
            `PARAM_ID_OSCB_WAVE:    sel_val_comb = {5'd0, val_oscb_wave};
            `PARAM_ID_FLT_TYPE:     sel_val_comb = {5'd0, val_flt_type};
            `PARAM_ID_ENV_TAB:      sel_val_comb = {5'd0, val_env_tab};
            default:                sel_val_comb = 7'd64;
        endcase
    end

    // Keep control selection outside pixel-rate arithmetic.
    always @(posedge clk) sel_val <= sel_val_comb;

    // --------------------------------------------------------------------------
    // Pre-computed Parameter & BCD Digit Decomposition (Pipelined Stage)
    // --------------------------------------------------------------------------
    wire [3:0] comb_d100   = (sel_val >= 7'd100) ? 4'd1 : 4'd0;
    wire [6:0] comb_rem100 = (sel_val >= 7'd100) ? (sel_val - 7'd100) : sel_val;
    reg  [3:0] comb_d10;
    reg  [3:0] comb_d1;
    always @(*) begin
        if      (comb_rem100 >= 7'd90) begin comb_d10 = 4'd9; comb_d1 = comb_rem100[3:0] - 4'd10; end
        else if (comb_rem100 >= 7'd80) begin comb_d10 = 4'd8; comb_d1 = comb_rem100[3:0];         end
        else if (comb_rem100 >= 7'd70) begin comb_d10 = 4'd7; comb_d1 = comb_rem100[3:0] - 4'd6;  end
        else if (comb_rem100 >= 7'd60) begin comb_d10 = 4'd6; comb_d1 = comb_rem100[3:0] - 4'd12; end
        else if (comb_rem100 >= 7'd50) begin comb_d10 = 4'd5; comb_d1 = comb_rem100[3:0] - 4'd2;  end
        else if (comb_rem100 >= 7'd40) begin comb_d10 = 4'd4; comb_d1 = comb_rem100[3:0] - 4'd8;  end
        else if (comb_rem100 >= 7'd30) begin comb_d10 = 4'd3; comb_d1 = comb_rem100[3:0] - 4'd14; end
        else if (comb_rem100 >= 7'd20) begin comb_d10 = 4'd2; comb_d1 = comb_rem100[3:0] - 4'd4;  end
        else if (comb_rem100 >= 7'd10) begin comb_d10 = 4'd1; comb_d1 = comb_rem100[3:0] - 4'd10; end
        else                           begin comb_d10 = 4'd0; comb_d1 = comb_rem100[3:0];         end
    end

    reg [17:0] reg_hud_label;
    reg [13:0] reg_slider_pos_x;
    reg        reg_param_selected;
    reg [5:0]  reg_ch_hud_d100;
    reg [5:0]  reg_ch_hud_d10;
    reg [5:0]  reg_ch_hud_d1;

    always @(posedge clk) begin
        reg_hud_label      <= get_param_label3(hud_selected_id);
        reg_slider_pos_x   <= 14'd544 + ((sel_val * 14'd192) >> 7);
        reg_param_selected <= (hud_selected_id != `PARAM_ID_NONE);
        reg_ch_hud_d100    <= (hud_selected_id == `PARAM_ID_NONE) ? `CH_MINUS :
                              (comb_d100 == 4'd0) ? `CH_SPACE : (`CH_0 + comb_d100);
        reg_ch_hud_d10     <= (hud_selected_id == `PARAM_ID_NONE) ? `CH_MINUS :
                              (comb_d100 == 4'd0 && comb_d10 == 4'd0) ? `CH_SPACE : (`CH_0 + comb_d10);
        reg_ch_hud_d1      <= (hud_selected_id == `PARAM_ID_NONE) ? `CH_MINUS : (`CH_0 + comb_d1);
    end

    // --------------------------------------------------------------------------
    // Top Universal HUD Adjustment Bar Geometry (X: 430..836, Y: 12..32)
    // --------------------------------------------------------------------------
    // 1. Parameter 3-Letter Label Badge (X: 430..496, Y: 12..32)
    wire in_hud_lbl_box = (p_x2 >= 14'd430 && p_x2 <= 14'd496 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_hud_lbl_bdr = in_hud_lbl_box && (p_x2 == 14'd430 || p_x2 == 14'd496 || p_y2 == 14'd12 || p_y2 == 14'd32);

    wire font_hud_y_valid = (p_y2 >= 14'd17 && p_y2 <= 14'd26);
    wire [3:0] hud_ry_sub = p_y2[3:0] - 4'd1;
    wire [2:0] font_hud_ry = hud_ry_sub[3:1];

    // Decode characters on the control side. The pixel path selects a row/bit
    // of a cached 3x5 bitmap rather than decoding the full alphabet six times.
    reg [14:0] hud_glyph[0:5];
    wire [35:0] hud_chars={reg_hud_label,reg_ch_hud_d100,reg_ch_hud_d10,reg_ch_hud_d1};
    genvar hg,hp;
    generate for(hg=0;hg<6;hg=hg+1) begin: hud_glyph_cache
        for(hp=0;hp<15;hp=hp+1) begin: bits_cache
            always @(posedge clk)
                hud_glyph[hg][14-hp]<=get_font_3x5(hud_chars[(5-hg)*6+:6],hp%3,hp/3);
        end
    end endgenerate
    function hud_bitmap_pixel;
        input [14:0] bitmap;
        input [1:0] rx;
        input [2:0] ry;
        reg [2:0] row;
        begin
            case(ry)
                0:row=bitmap[14:12];1:row=bitmap[11:9];2:row=bitmap[8:6];
                3:row=bitmap[5:3];4:row=bitmap[2:0];default:row=0;
            endcase
            hud_bitmap_pixel=rx<3 ? row[2-rx] : 1'b0;
        end
    endfunction

    reg hud_lbl_pixel;
    always @(*) begin
        hud_lbl_pixel = 1'b0;
        if (font_hud_y_valid) begin
            if      (p_x2 >= 14'd450 && p_x2 <= 14'd455) hud_lbl_pixel = hud_bitmap_pixel(hud_glyph[0], (p_x2 - 14'd450) >> 1, font_hud_ry);
            else if (p_x2 >= 14'd460 && p_x2 <= 14'd465) hud_lbl_pixel = hud_bitmap_pixel(hud_glyph[1], (p_x2 - 14'd460) >> 1, font_hud_ry);
            else if (p_x2 >= 14'd470 && p_x2 <= 14'd475) hud_lbl_pixel = hud_bitmap_pixel(hud_glyph[2], (p_x2 - 14'd470) >> 1, font_hud_ry);
        end
    end

    // 2. Step Decrement [-] Button (X: 504..532, Y: 12..32)
    wire in_hud_dec_box = (p_x2 >= 14'd504 && p_x2 <= 14'd532 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_hud_dec_bdr = in_hud_dec_box && (p_x2 == 14'd504 || p_x2 == 14'd532 || p_y2 == 14'd12 || p_y2 == 14'd32);
    wire on_hud_dec_icon = (p_x2 >= 14'd513 && p_x2 <= 14'd523 && p_y2 >= 14'd21 && p_y2 <= 14'd23);

    // 3. 200px Slider Track (X: 540..740, Y: 12..32)
    wire in_hud_sld_box = (p_x2 >= 14'd540 && p_x2 <= 14'd740 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_hud_sld_bdr = in_hud_sld_box && (p_x2 == 14'd540 || p_x2 == 14'd740 || p_y2 == 14'd12 || p_y2 == 14'd32);
    wire on_hud_sld_center = (p_x2 == 14'd640 && p_y2 >= 14'd14 && p_y2 <= 14'd30);
    wire in_hud_sld_fill = (p_x2 >= 14'd544 && p_x2 <= reg_slider_pos_x && p_y2 >= 14'd17 && p_y2 <= 14'd27);
    wire in_hud_thumb_box = (p_x2 >= (reg_slider_pos_x - 14'd3) && p_x2 <= (reg_slider_pos_x + 14'd3) && p_y2 >= 14'd14 && p_y2 <= 14'd30);
    wire on_hud_thumb_bdr = in_hud_thumb_box && (p_x2 == (reg_slider_pos_x - 14'd3) || p_x2 == (reg_slider_pos_x + 14'd3) || p_y2 == 14'd14 || p_y2 == 14'd30);
    wire on_hud_thumb_needle = (p_x2 == reg_slider_pos_x && p_y2 >= 14'd15 && p_y2 <= 14'd29);

    // 4. Step Increment [+] Button (X: 748..776, Y: 12..32)
    wire in_hud_inc_box = (p_x2 >= 14'd748 && p_x2 <= 14'd776 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_hud_inc_bdr = in_hud_inc_box && (p_x2 == 14'd748 || p_x2 == 14'd776 || p_y2 == 14'd12 || p_y2 == 14'd32);
    wire on_hud_inc_icon = (p_x2 >= 14'd757 && p_x2 <= 14'd767 && p_y2 >= 14'd21 && p_y2 <= 14'd23) ||
                           (p_x2 >= 14'd761 && p_x2 <= 14'd763 && p_y2 >= 14'd17 && p_y2 <= 14'd27);

    // 5. 3-Digit Numeric Value Readout (0~127, X: 784..836, Y: 12..32)
    wire in_hud_num_box = (p_x2 >= 14'd784 && p_x2 <= 14'd836 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_hud_num_bdr = in_hud_num_box && (p_x2 == 14'd784 || p_x2 == 14'd836 || p_y2 == 14'd12 || p_y2 == 14'd32);

    reg hud_num_pixel;
    always @(*) begin
        hud_num_pixel = 1'b0;
        if (font_hud_y_valid) begin
            if      (p_x2 >= 14'd798 && p_x2 <= 14'd803) hud_num_pixel = hud_bitmap_pixel(hud_glyph[3], (p_x2 - 14'd798) >> 1, font_hud_ry);
            else if (p_x2 >= 14'd807 && p_x2 <= 14'd812) hud_num_pixel = hud_bitmap_pixel(hud_glyph[4], (p_x2 - 14'd807) >> 1, font_hud_ry);
            else if (p_x2 >= 14'd816 && p_x2 <= 14'd821) hud_num_pixel = hud_bitmap_pixel(hud_glyph[5], (p_x2 - 14'd816) >> 1, font_hud_ry);
        end
    end

    // --------------------------------------------------------------------------
    // Real-Time USB Hardware Telemetry Diagnostic Pill (X: 844..1136, Y: 12..32)
    // --------------------------------------------------------------------------
    function [5:0] hex2ch;
        input [3:0] nibble;
        begin
            case (nibble)
                4'h0: hex2ch = `CH_0;
                4'h1: hex2ch = `CH_1;
                4'h2: hex2ch = `CH_2;
                4'h3: hex2ch = `CH_3;
                4'h4: hex2ch = `CH_4;
                4'h5: hex2ch = `CH_5;
                4'h6: hex2ch = `CH_6;
                4'h7: hex2ch = `CH_7;
                4'h8: hex2ch = `CH_8;
                4'h9: hex2ch = `CH_9;
                4'hA: hex2ch = `CH_A;
                4'hB: hex2ch = `CH_B;
                4'hC: hex2ch = `CH_C;
                4'hD: hex2ch = `CH_D;
                4'hE: hex2ch = `CH_E;
                4'hF: hex2ch = `CH_F;
            endcase
        end
    endfunction

    wire in_diag_box = (p_x2 >= 14'd844 && p_x2 <= 14'd1136 && p_y2 >= 14'd12 && p_y2 <= 14'd32);
    wire on_diag_bdr = in_diag_box && (p_x2 == 14'd844 || p_x2 == 14'd1136 || p_y2 == 14'd12 || p_y2 == 14'd32);

    wire [7:0] diag_col = (p_x2 - 14'd848) >> 2;
    wire [1:0] diag_rx  = (p_x2 - 14'd848) & 2'b11;
    wire [2:0] diag_ry1 = (p_y2 >= 14'd14 && p_y2 <= 14'd18) ? (p_y2[3:0] - 4'd14) : 3'd0;
    wire [2:0] diag_ry2 = (p_y2 >= 14'd23 && p_y2 <= 14'd27) ? (p_y2[4:0] - 5'd23) : 3'd0;

    wire [15:0] diag_vid = {usb_dbg_regs[15:8], usb_dbg_regs[7:0]};
    wire [15:0] diag_pid = {usb_dbg_regs[31:24], usb_dbg_regs[23:16]};

    reg [5:0] l1_ch;
    reg [23:0] l1_fg;
    always @(*) begin
        l1_ch = `CH_SPACE;
        l1_fg = 24'h00FFFF;
        case (diag_col)
            8'd0: l1_ch = `CH_U;
            8'd1: l1_ch = `CH_S;
            8'd2: l1_ch = `CH_B;
            8'd3: l1_ch = `CH_COLON;
            8'd4: begin
                l1_ch = usb_conn_err ? `CH_E : usb_connected ? `CH_O : `CH_O;
                l1_fg = usb_conn_err ? 24'hFF4040 : usb_connected ? 24'h20E080 : 24'h708090;
            end
            8'd5: begin
                l1_ch = usb_conn_err ? `CH_R : usb_connected ? `CH_K : `CH_F;
                l1_fg = usb_conn_err ? 24'hFF4040 : usb_connected ? 24'h20E080 : 24'h708090;
            end
            8'd6: begin
                l1_ch = usb_conn_err ? `CH_R : `CH_SPACE;
                l1_fg = usb_conn_err ? 24'hFF4040 : 24'h20E080;
            end
            8'd8:  l1_ch = `CH_T;
            8'd9:  l1_ch = (usb_dev_type == 2'd3) ? `CH_C : (usb_dev_type == 2'd2) ? `CH_M : `CH_N;
            8'd10: l1_ch = (usb_dev_type == 2'd3) ? `CH_H : (usb_dev_type == 2'd2) ? `CH_S : `CH_O;
            8'd12: l1_ch = `CH_V;
            8'd13: l1_ch = hex2ch(diag_vid[15:12]);
            8'd14: l1_ch = hex2ch(diag_vid[11:8]);
            8'd15: l1_ch = hex2ch(diag_vid[7:4]);
            8'd16: l1_ch = hex2ch(diag_vid[3:0]);
            8'd18: l1_ch = `CH_P;
            8'd19: l1_ch = hex2ch(diag_pid[15:12]);
            8'd20: l1_ch = hex2ch(diag_pid[11:8]);
            8'd21: l1_ch = hex2ch(diag_pid[7:4]);
            8'd22: l1_ch = hex2ch(diag_pid[3:0]);
            8'd24: l1_ch = `CH_P;
            8'd25: l1_ch = `CH_K;
            8'd26: l1_ch = `CH_COLON;
            8'd27: begin l1_ch = hex2ch(usb_dbg_pkt_cnt[7:4]); l1_fg = 24'hFFFF00; end
            8'd28: begin l1_ch = hex2ch(usb_dbg_pkt_cnt[3:0]); l1_fg = 24'hFFFF00; end
            default: l1_ch = `CH_SPACE;
        endcase
    end

    wire [7:0] dbg_b0 = usb_dbg_report[7:0];
    wire [7:0] dbg_b1 = usb_dbg_report[15:8];
    wire [7:0] dbg_b2 = usb_dbg_report[23:16];
    wire [7:0] dbg_b3 = usb_dbg_report[31:24];
    wire [7:0] dbg_b4 = usb_dbg_report[39:32];
    wire [7:0] dbg_b5 = usb_dbg_report[47:40];
    wire [7:0] dbg_b6 = usb_dbg_report[55:48];

    reg [5:0] l2_ch;
    reg [23:0] l2_fg;
    always @(*) begin
        l2_ch = `CH_SPACE;
        l2_fg = 24'hB0C8E0;
        case (diag_col)
            8'd0: l2_ch = `CH_D;
            8'd1: l2_ch = `CH_COLON;
            8'd2: l2_ch = hex2ch(dbg_b0[7:4]);
            8'd3: l2_ch = hex2ch(dbg_b0[3:0]);
            8'd4: begin l2_ch = hex2ch(dbg_b1[7:4]); l2_fg = usb_raw_down ? 24'h00FFFF : 24'h708090; end
            8'd5: begin l2_ch = hex2ch(dbg_b1[3:0]); l2_fg = usb_raw_down ? 24'h00FFFF : 24'h708090; end
            8'd6: l2_ch = hex2ch(dbg_b2[7:4]);
            8'd7: l2_ch = hex2ch(dbg_b2[3:0]);
            8'd8: l2_ch = hex2ch(dbg_b3[7:4]);
            8'd9: l2_ch = hex2ch(dbg_b3[3:0]);
            8'd10: l2_ch = hex2ch(dbg_b4[7:4]);
            8'd11: l2_ch = hex2ch(dbg_b4[3:0]);
            8'd12: l2_ch = hex2ch(dbg_b5[7:4]);
            8'd13: l2_ch = hex2ch(dbg_b5[3:0]);
            8'd14: l2_ch = hex2ch(dbg_b6[7:4]);
            8'd15: l2_ch = hex2ch(dbg_b6[3:0]);
            8'd17: l2_ch = `CH_X;
            8'd18: l2_ch = hex2ch(usb_raw_x[15:12]);
            8'd19: l2_ch = hex2ch(usb_raw_x[11:8]);
            8'd20: l2_ch = hex2ch(usb_raw_x[7:4]);
            8'd21: l2_ch = hex2ch(usb_raw_x[3:0]);
            8'd23: l2_ch = `CH_Y;
            8'd24: l2_ch = hex2ch(usb_raw_y[15:12]);
            8'd25: l2_ch = hex2ch(usb_raw_y[11:8]);
            8'd26: l2_ch = hex2ch(usb_raw_y[7:4]);
            8'd27: l2_ch = hex2ch(usb_raw_y[3:0]);
            8'd29: l2_ch = `CH_D;
            8'd30: begin
                l2_ch = usb_raw_down ? `CH_1 : `CH_0;
                l2_fg = usb_raw_down ? 24'hFFFF00 : 24'h506070;
            end
            default: l2_ch = `CH_SPACE;
        endcase
    end

    wire diag_l1_hit = (p_x2 >= 14'd848 && p_x2 <= 14'd1130 && p_y2 >= 14'd14 && p_y2 <= 14'd18 && diag_rx < 2'd3);
    wire diag_l2_hit = (p_x2 >= 14'd848 && p_x2 <= 14'd1130 && p_y2 >= 14'd23 && p_y2 <= 14'd27 && diag_rx < 2'd3);

    wire diag_l1_px = diag_l1_hit ? get_font_3x5(l1_ch, diag_rx, diag_ry1) : 1'b0;
    wire diag_l2_px = diag_l2_hit ? get_font_3x5(l2_ch, diag_rx, diag_ry2) : 1'b0;

    reg [23:0] diag_box_rgb;
    always @(*) begin
        if (diag_l1_px)
            diag_box_rgb = l1_fg;
        else if (diag_l2_px)
            diag_box_rgb = l2_fg;
        else if (on_diag_bdr)
            diag_box_rgb = usb_connected ? 24'h00A0D0 : `COLOR_PANEL_BORDER;
        else
            diag_box_rgb = 24'h0E1622;
    end

    reg        hit_hud;
    reg [23:0] hud_rgb;

    always @(posedge clk) begin
        is_panel_body   <= in_osca_p || in_oscb_p || in_flt_p || in_env_p || in_fx_p;
        is_panel_border <= on_osca_b || on_oscb_b || on_flt_b || on_env_b || on_fx_b;
        is_panel_header <= on_hdr_osca || on_hdr_oscb || on_hdr_flt || on_hdr_env || on_hdr_fx || on_sub_fx;

        // Header Decors / Brand Elements
        decor_rgb <= `COLOR_PANEL_BG;
        // Top Bar SERUM Brand Logo (X=36..130, Y=14..28)
        if (p_y2 >= 14'd14 && p_y2 <= 14'd28 && p_y2[1] && p_x2 >= 14'd36 && p_x2 <= 14'd130) begin
            decor_rgb <= 24'hD0D8E8;
        end
        // Top Bar Cyan Accent Line
        else if (p_y2 == 14'd42 && p_x2 >= 14'd24 && p_x2 <= 14'd1256) begin
            decor_rgb <= `COLOR_KNOB_ARC;
        end

        // Top Universal HUD Adjustment Bar Compositor (X: 430..836, Y: 12..32)
        hit_hud <= 1'b0;
        hud_rgb <= `COLOR_PANEL_BG;

        if (in_hud_lbl_box) begin
            hit_hud <= 1'b1;
            if (hud_lbl_pixel)
                hud_rgb <= reg_param_selected ? 24'h00FFFF : 24'h8090A0;
            else if (on_hud_lbl_bdr)
                hud_rgb <= reg_param_selected ? 24'h00D0FF : `COLOR_PANEL_BORDER;
            else
                hud_rgb <= 24'h101720;
        end
        else if (in_hud_dec_box) begin
            hit_hud <= 1'b1;
            if (on_hud_dec_icon)
                hud_rgb <= 24'hFFFFFF;
            else if (on_hud_dec_bdr)
                hud_rgb <= (active_btn_id == `PARAM_ID_HUD_DEC && btn_flash_active) ? 24'h00FFFF : `COLOR_PANEL_BORDER;
            else
                hud_rgb <= (active_btn_id == `PARAM_ID_HUD_DEC && btn_flash_active) ? 24'h204060 : 24'h141D28;
        end
        else if (in_hud_sld_box) begin
            hit_hud <= 1'b1;
            if (on_hud_thumb_bdr)
                hud_rgb <= 24'hFFFFFF;
            else if (on_hud_thumb_needle)
                hud_rgb <= 24'h00D0FF;
            else if (in_hud_thumb_box)
                hud_rgb <= 24'hE0E8F0;
            else if (on_hud_sld_center)
                hud_rgb <= 24'hFFFFFF;
            else if (in_hud_sld_fill)
                hud_rgb <= `COLOR_KNOB_ARC;
            else if (on_hud_sld_bdr)
                hud_rgb <= reg_param_selected ? `COLOR_KNOB_SEL_GLOW : `COLOR_PANEL_BORDER;
            else
                hud_rgb <= 24'h141D28;
        end
        else if (in_hud_inc_box) begin
            hit_hud <= 1'b1;
            if (on_hud_inc_icon)
                hud_rgb <= 24'hFFFFFF;
            else if (on_hud_inc_bdr)
                hud_rgb <= (active_btn_id == `PARAM_ID_HUD_INC && btn_flash_active) ? 24'h00FFFF : `COLOR_PANEL_BORDER;
            else
                hud_rgb <= (active_btn_id == `PARAM_ID_HUD_INC && btn_flash_active) ? 24'h204060 : 24'h141D28;
        end
        else if (in_hud_num_box) begin
            hit_hud <= 1'b1;
            if (hud_num_pixel)
                hud_rgb <= 24'h00FFFF;
            else if (on_hud_num_bdr)
                hud_rgb <= `COLOR_PANEL_BORDER;
            else
                hud_rgb <= 24'h101720;
        end
        else if (in_diag_box) begin
            hit_hud <= 1'b1;
            hud_rgb <= diag_box_rgb;
        end
    end

    // --------------------------------------------------------------------------
    // 4. Final Compositing Multi-Layer Priority Multiplexer
    // --------------------------------------------------------------------------
    reg [23:0] pixel_mux;

    // R15I: native coverage captions / values and fractional curve edges.
    // Updating these observation inputs never feeds back into touch handling.
    wire in_contact_diag_raw = show_diagnostics && p_y2 >= 14'd694 && p_y2 <= 14'd719;
    wire [7:0] contact_col = (p_x2 - 14'd64) >> 4;
    wire [1:0] contact_rx = (p_x2 - 14'd64) >> 2;
    wire [2:0] contact_ry = (p_y2 - 14'd696) >> 2;
    reg [5:0] contact_ch;
    always @(*) begin
        contact_ch = `CH_SPACE;
        case (contact_col)
            0: contact_ch = `CH_R;
            1: contact_ch = `CH_1;
            2: contact_ch = `CH_6;
            3: contact_ch = `CH_A;
            5: contact_ch = `CH_C;
            6: contact_ch = `CH_COLON;
            7: contact_ch = hex2ch(touch_diag_count[15:12]);
            8: contact_ch = hex2ch(touch_diag_count[11:8]);
            9: contact_ch = hex2ch(touch_diag_count[7:4]);
            10: contact_ch = hex2ch(touch_diag_count[3:0]);
            12: contact_ch = `CH_X;
            13: contact_ch = `CH_COLON;
            14: contact_ch = hex2ch(touch_diag_coords[63:60]);
            15: contact_ch = hex2ch(touch_diag_coords[59:56]);
            16: contact_ch = hex2ch(touch_diag_coords[55:52]);
            17: contact_ch = hex2ch(touch_diag_coords[51:48]);
            19: contact_ch = `CH_Y;
            20: contact_ch = `CH_COLON;
            21: contact_ch = hex2ch(touch_diag_coords[47:44]);
            22: contact_ch = hex2ch(touch_diag_coords[43:40]);
            23: contact_ch = hex2ch(touch_diag_coords[39:36]);
            24: contact_ch = hex2ch(touch_diag_coords[35:32]);
            26: contact_ch = `CH_U;
            27: contact_ch = `CH_COLON;
            28: contact_ch = hex2ch(touch_diag_coords[31:28]);
            29: contact_ch = hex2ch(touch_diag_coords[27:24]);
            30: contact_ch = hex2ch(touch_diag_coords[23:20]);
            31: contact_ch = hex2ch(touch_diag_coords[19:16]);
            33: contact_ch = `CH_V;
            34: contact_ch = `CH_COLON;
            35: contact_ch = hex2ch(touch_diag_coords[15:12]);
            36: contact_ch = hex2ch(touch_diag_coords[11:8]);
            37: contact_ch = hex2ch(touch_diag_coords[7:4]);
            38: contact_ch = hex2ch(touch_diag_coords[3:0]);
            40: contact_ch = `CH_M;
            41: contact_ch = `CH_COLON;
            42: contact_ch = touch_diag_mode ? `CH_1 : `CH_0;
        endcase
    end
    wire contact_text_raw = p_x2 >= 14'd64 && p_x2 < 14'd752 &&
        p_y2 >= 14'd696 && p_y2 <= 14'd715 && contact_rx < 2'd3 &&
        get_font_3x5(contact_ch, contact_rx, contact_ry);
    wire [13:0] contact_x = touch_diag_coords[29:16];
    wire [13:0] contact_y = touch_diag_coords[13:0];
    wire [13:0] contact_dx = p_x2 > contact_x ? p_x2-contact_x : contact_x-p_x2;
    wire [13:0] contact_dy = p_y2 > contact_y ? p_y2-contact_y : contact_y-p_y2;
    wire contact_cross_raw = show_diagnostics && touch_diag_count != 16'd0 &&
        ((contact_dx <= 14'd12 && contact_dy <= 14'd1) ||
         (contact_dy <= 14'd12 && contact_dx <= 14'd1));

    // Evaluate diagnostics in parallel with the other stage-three renderers.
    reg in_contact_diag, contact_text_px, contact_cross;
    always @(posedge clk) begin
        in_contact_diag <= in_contact_diag_raw;
        contact_text_px <= contact_text_raw;
        contact_cross <= contact_cross_raw;
    end

    always @(*) begin
        // Priority 1: Interactive Buttons, Switches & Checkboxes
        if (in_contact_diag) begin
            pixel_mux = contact_text_px ? 24'hFFFF40 : 24'h081020;
        end else if (contact_cross) begin
            pixel_mux = 24'hFF40FF;
        end else if (hit_curve_hint) begin
            pixel_mux=curve_hint_rgb;
        end else if (hit_fx) begin
            pixel_mux = fx_rgb; // Own all lower-right pixels, including old FX knobs.
        end else if (hit_btn) begin
            pixel_mux = btn_rgb;
        end
        // Priority 3: Top Universal HUD Adjustment Bar
        // R17 navigation covers the entire legacy HUD rectangle in every
        // view. Disable this unreachable drawing path explicitly so its
        // cached-font/pixel mux cannot consume routed timing resources.
        else if (1'b0 && hit_hud) begin
            pixel_mux = hud_rgb;
        end
        // Priority 4: Scopes & Dynamic Curves
        else if (hit_flt) begin
            pixel_mux = flt_rgb;
        end else if (hit_fx) begin
            pixel_mux = fx_rgb;
        end
        // Priority 5: Brand & Accent Lines
        else if (decor_rgb != `COLOR_PANEL_BG) begin
            pixel_mux = decor_rgb;
        end
        // Priority 6: Panel Metal Borders & 1px Bevel Lines
        else if (is_panel_border) begin
            pixel_mux = `COLOR_PANEL_BORDER;
        end
        // Priority 7: Module Header Strips
        else if (is_panel_header) begin
            pixel_mux = `COLOR_PANEL_HEADER;
        end
        // Priority 8: Panel Recessed Bodies
        else if (is_panel_body) begin
            pixel_mux = `COLOR_PANEL_BG;
        end
        // Priority 9: Global Obsidian Workstation Background
        else begin
            pixel_mux = `COLOR_BG;
        end
    end

    // --------------------------------------------------------------------------
    // 5. Video Output Registers
    // --------------------------------------------------------------------------
    // Old layers reach pixel_mux in three stages. Register that composition
    // at stage four, insert knobs/OSC/ENV (four stages) at stage five, then combine
    // with the five-stage FX/modulation layers in the final output register.
    reg [23:0] base_pixel,base_pixel0;
    reg base_diagnostic,base_diagnostic0;
    reg top_hit0,hud_hit0,filter_hit0;
    reg hsync_extra,vsync_extra,den_extra,hsync_extra0,vsync_extra0,den_extra0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            base_pixel<=0;base_diagnostic<=0;hsync_extra<=0;vsync_extra<=0;den_extra<=0;
            base_pixel0<=0;base_diagnostic0<=0;hsync_extra0<=0;vsync_extra0<=0;den_extra0<=0;
            top_hit0<=0;hud_hit0<=0;filter_hit0<=0;
        end else begin
            base_pixel0<=pixel_mux;
            top_hit0<=in_contact_diag || contact_cross || hit_curve_hint || hit_fx || hit_btn;
            hud_hit0<=1'b0;filter_hit0<=hit_flt;
            if(top_hit0) base_pixel<=base_pixel0;
            else if(hit_knob) base_pixel<=knob_rgb;
            else if(hud_hit0) base_pixel<=base_pixel0;
            else if(hit_osca) base_pixel<=osca_rgb;
            else if(hit_oscb) base_pixel<=oscb_rgb;
            else if(filter_hit0) base_pixel<=base_pixel0;
            else if(hit_env) base_pixel<=env_rgb;
            else base_pixel<=base_pixel0;
            base_diagnostic0<=in_contact_diag || contact_cross;
            base_diagnostic<=base_diagnostic0;
            hsync_extra0<=pipe_hsync[2];vsync_extra0<=pipe_vsync[2];den_extra0<=pipe_den[2];
            hsync_extra<=hsync_extra0;vsync_extra<=vsync_extra0;den_extra<=den_extra0;
        end
    end
    wire [23:0] composed_pixel=navigation_hit ? navigation_rgb : base_diagnostic ? base_pixel :
        hit_mod ? mod_rgb : hit_fx_strip ? fx_strip_rgb : base_pixel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_hsync      <= 1'b0;
            out_vsync      <= 1'b0;
            out_den        <= 1'b0;
            out_pixel_data <= 24'h0;
        end else begin
            out_hsync      <= hsync_extra;
            out_vsync      <= vsync_extra;
            out_den        <= den_extra;
            out_pixel_data <= den_extra ? composed_pixel : 24'h000000;
        end
    end

endmodule
