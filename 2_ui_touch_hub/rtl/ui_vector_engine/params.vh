// ==============================================================================
// File: params.vh
// Description: Global Parameters, 1280x720 Geometry Definitions & Colors
//              Full Serum-style Synthesizer Console Layout (No Piano Keyboard)
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

`ifndef PARAMS_VH
`define PARAMS_VH

// ------------------------------------------------------------------------------
// 1. Frame & Canvas Constants
// ------------------------------------------------------------------------------
`define CANVAS_W              14'd1280
`define CANVAS_H              14'd720
`define PIXEL_CLK_HZ          50000000

`define TOUCH_FRAME_HEADER    16'h5454
`define MIDI_BAUD_DIV_31250   16'd1600 // 50MHz / 31250 = 1600

// ------------------------------------------------------------------------------
// 2. Parameter IDs (8-bit)
// ------------------------------------------------------------------------------
`define PARAM_ID_NONE         8'h00

// Top Deck (Macro & Master)
`define PARAM_ID_MACRO1       8'h01
`define PARAM_ID_MACRO2       8'h02
`define PARAM_ID_MACRO3       8'h03
`define PARAM_ID_MACRO4       8'h04
`define PARAM_ID_MASTER_VOL   8'h05
`define PARAM_ID_HUD_DEC      8'h06
`define PARAM_ID_HUD_INC      8'h07
`define PARAM_ID_HUD_SLIDER   8'h08

// Power / Bypass Toggle Buttons
`define PARAM_ID_OSCA_POWER   8'h0A
`define PARAM_ID_OSCB_POWER   8'h0B
`define PARAM_ID_FLT_POWER    8'h0C

// Preset / Model Selector Buttons
`define PARAM_ID_OSCA_WAVE    8'h0E
`define PARAM_ID_OSCB_WAVE    8'h0F
`define PARAM_ID_FLT_TYPE     8'h3B
`define PARAM_ID_ENV_TAB      8'h45

// OSC A
`define PARAM_ID_OSCA_OCT     8'h10
`define PARAM_ID_OSCA_SEMI    8'h11
`define PARAM_ID_OSCA_FINE    8'h12
`define PARAM_ID_OSCA_UNISON  8'h13 // CC23
`define PARAM_ID_OSCA_DETUNE  8'h14 // CC22
`define PARAM_ID_OSCA_BLEND   8'h15
`define PARAM_ID_OSCA_PHASE   8'h16
`define PARAM_ID_OSCA_WT_POS  8'h17 // CC20
`define PARAM_ID_OSCA_WARP    8'h18 // CC21
`define PARAM_ID_OSCA_PAN     8'h19 // CC91: OSC A pan
`define PARAM_ID_OSCA_VOL     8'h1A
`define PARAM_ID_OSCA_RAND    8'h1B

// OSC B
`define PARAM_ID_OSCB_OCT     8'h20
`define PARAM_ID_OSCB_SEMI    8'h21
`define PARAM_ID_OSCB_FINE    8'h22
`define PARAM_ID_OSCB_UNISON  8'h23
`define PARAM_ID_OSCB_DETUNE  8'h24
`define PARAM_ID_OSCB_BLEND   8'h25
`define PARAM_ID_OSCB_PHASE   8'h26
`define PARAM_ID_OSCB_WT_POS  8'h27
`define PARAM_ID_OSCB_WARP    8'h28
`define PARAM_ID_OSCB_PAN     8'h29
`define PARAM_ID_OSCB_VOL     8'h2A
`define PARAM_ID_OSCB_RAND    8'h2B

// Filter
`define PARAM_ID_FLT_CUTOFF   8'h30 // CC74
`define PARAM_ID_FLT_RES      8'h31 // CC71
`define PARAM_ID_FLT_PAN      8'h32 // K27 now MASTER PAN / CC10; stable legacy ID
`define PARAM_ID_FLT_DRIVE    8'h33
`define PARAM_ID_FLT_FAT      8'h34
`define PARAM_ID_FLT_MIX      8'h35

// Filter Routing Checkboxes
`define PARAM_ID_FLT_ROUTE_A  8'h36
`define PARAM_ID_FLT_ROUTE_B  8'h37
`define PARAM_ID_FLT_ROUTE_N  8'h38
`define PARAM_ID_FLT_ROUTE_S  8'h39
`define PARAM_ID_FLT_KEYTRACK 8'h3A

// Envelope 1 (ADSR)
`define PARAM_ID_ENV1_ATTACK  8'h40 // CC73
`define PARAM_ID_ENV1_HOLD    8'h41
`define PARAM_ID_ENV1_DECAY   8'h42 // CC75
`define PARAM_ID_ENV1_SUSTAIN 8'h43 // CC76
`define PARAM_ID_ENV1_RELEASE 8'h44 // CC72

// FX Matrix / Voicing
`define PARAM_ID_FX_REVERB    8'h50
`define PARAM_ID_FX_DELAY     8'h51
`define PARAM_ID_FX_CHORUS    8'h52
`define PARAM_ID_PORTAMENTO   8'h53
`define PARAM_ID_SLOT1_BYPASS 8'h54
`define PARAM_ID_SLOT2_BYPASS 8'h55
`define PARAM_ID_SLOT3_BYPASS 8'h56
`define PARAM_ID_SLOT4_BYPASS 8'h57

// ------------------------------------------------------------------------------
// 3. Panel Bounding Boxes (1280x720 Canvas Coordinates)
// ------------------------------------------------------------------------------
// Header Bar
`define TOP_BAR_Y0            14'd0
`define TOP_BAR_Y1            14'd42

// OSC A Panel
`define OSCA_PANEL_X0         14'd24
`define OSCA_PANEL_X1         14'd424
`define OSCA_PANEL_Y0         14'd46
`define OSCA_PANEL_Y1         14'd360
`define OSCA_WIN_X0           14'd36
`define OSCA_WIN_X1           14'd412
`define OSCA_WIN_Y0           14'd104
`define OSCA_WIN_Y1           14'd236
`define OSCA_WIN_CY           14'd170

// OSC B Panel
`define OSCB_PANEL_X0         14'd440
`define OSCB_PANEL_X1         14'd840
`define OSCB_PANEL_Y0         14'd46
`define OSCB_PANEL_Y1         14'd360
`define OSCB_WIN_X0           14'd452
`define OSCB_WIN_X1           14'd828
`define OSCB_WIN_Y0           14'd104
`define OSCB_WIN_Y1           14'd236
`define OSCB_WIN_CY           14'd170

// Filter Panel
`define FLT_PANEL_X0          14'd856
`define FLT_PANEL_X1          14'd1256
`define FLT_PANEL_Y0          14'd46
`define FLT_PANEL_Y1          14'd360
`define FLT_WIN_X0            14'd868
`define FLT_WIN_X1            14'd1244
`define FLT_WIN_Y0            14'd104
`define FLT_WIN_Y1            14'd236
`define FLT_WIN_CY            14'd170

// Envelope & Modulation Panel (Expanded full lower left area: Y = 368..708)
`define ENV_PANEL_X0          14'd24
`define ENV_PANEL_X1          14'd402
`define ENV_PANEL_Y0          14'd368
`define ENV_PANEL_Y1          14'd708
`define ENV_WIN_X0            14'd36
`define ENV_WIN_X1            14'd390
`define ENV_WIN_Y0            14'd404
`define ENV_WIN_Y1            14'd580
`define ENV_BASE_Y            14'd568
`define ENV_PEAK_Y            14'd424

// Shared forward geometry for drawing AND direct manipulation.
`define ENV_LEN_A(v) (16'd10+(({9'd0,v}*16'd65)>>7))
`define ENV_LEN_H(v) (({9'd0,v}*16'd30)>>7)
`define ENV_LEN_D(v) (16'd12+(({9'd0,v}*16'd80)>>7))
`define ENV_LEN_R(v) (16'd12+(({9'd0,v}*16'd80)>>7))
`define ENV_SUS_HEIGHT(v) (({9'd0,v}*16'd144)>>7)

// FX & Modulation Matrix Panel (Expanded full lower right area: Y = 368..708)
`define FX_PANEL_X0           14'd796
`define FX_PANEL_X1           14'd1256
`define FX_PANEL_Y0           14'd368
`define FX_PANEL_Y1           14'd708
`define FX_WIN_X0             14'd808
`define FX_WIN_X1             14'd1244
`define FX_WIN_Y0             14'd404
`define FX_WIN_Y1             14'd552

// ------------------------------------------------------------------------------
// 4. Color Definitions (24-bit RGB)
// ------------------------------------------------------------------------------
`define COLOR_BG              24'h101318
`define COLOR_PANEL_BG        24'h181C24
`define COLOR_PANEL_BORDER    24'h2A3140
`define COLOR_PANEL_HEADER    24'h222834
`define COLOR_PANEL_BEVEL     24'h384256

`define COLOR_GRID_SUBTLE     24'h141D26
`define COLOR_GRID_AXIS       24'h223040

`define COLOR_OSCA_LINE       24'h76EA12
`define COLOR_OSCA_GLOW       24'h368406
`define COLOR_OSCA_FILL       24'h142806

`define COLOR_OSCB_LINE       24'h2AD8EC
`define COLOR_OSCB_GLOW       24'h157482
`define COLOR_OSCB_FILL       24'h082530

`define COLOR_FLT_LINE        24'h3884F8
`define COLOR_FLT_FILL        24'h0E2448
`define COLOR_FLT_NODE        24'hFFFFFF

`define COLOR_ENV_LINE        24'h44C4F8
`define COLOR_ENV_FILL        24'h102640
`define COLOR_ENV_NODE        24'hFFFFFF

`define COLOR_KNOB_BEZEL      24'h323A4A
`define COLOR_KNOB_BODY       24'h1A1E26
`define COLOR_KNOB_NEEDLE     24'hFFFFFF
`define COLOR_KNOB_ARC        24'h38E8FF
`define COLOR_KNOB_SEL_GLOW   24'h00FFFF

`define COLOR_BTN_ACTIVE_BG   24'h1B4670
`define COLOR_BTN_ACTIVE_ICON 24'h38E8FF
`define COLOR_BTN_IDLE_BG     24'h161A22
`define COLOR_BTN_IDLE_ICON   24'h4A586E
`define COLOR_BTN_BORDER      24'h2A3648
`define COLOR_BADGE_BG        24'h121620
`define COLOR_TEXT_DIM        24'h607288
`define COLOR_TEXT_BRIGHT     24'hE0E8F0
`define COLOR_TEXT_ACCENT     24'h38E8FF

`endif // PARAMS_VH
