// ==============================================================================
// Module: touch_event_router.v
// Description: Multi-Touch Collision Detector & Gesture Event Router
//              - 100% Full Coverage of All 32 Synthesizer Knobs
//              - 100% Full Coverage of All Buttons, Switches & Checkboxes
//              - Combined 2D Drag Vector (dx - dy) for Natural Rotary Feel
//              - Instant Touch Tap Detection & Toggle Action Dispatch
//              - Zero Piano Keyboard Bloat
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"

module touch_event_router (
    input  wire        clk,
    input  wire        rst_n,

    // Touch Input Packet (from uart_touch_rx)
    input  wire        touch_valid,
    input  wire [15:0] raw_touch_x,
    input  wire [15:0] raw_touch_y,
    input  wire        touch_state,
    input  wire        curve_capture_active, curve_focus_valid,
    input  wire [7:0]  curve_focus_id,

    // Selected Control Feedback
    output reg  [7:0]  selected_param_id,
    output reg         selected_valid,

    // Parameter Delta Adjustment (to param_merger)
    output reg         param_delta_valid,
    output reg signed [7:0] param_delta_val,

    // Button Tap Event (to param_merger)
    output reg         btn_tap_valid,
    output reg  [7:0]  btn_tap_id,
    output reg  [1:0]  btn_tap_action, // 0: toggle, 1: inc/next, 2: dec/prev

    // Observation only: most recent pressed packet, retained after release.
    output reg [63:0]  diag_contact_coords, // raw X, raw Y, mapped X, mapped Y
    output reg [15:0]  diag_contact_count,
    output wire       diag_mode_64k,

    // Shared normalized packets for the independent local LFO editor.
    output wire ui_touch_valid, ui_touch_down,
    output wire [13:0] ui_touch_x, ui_touch_y,

    // Reserved / Dummy note ports (maintained for pinout compatibility)
    output wire [13:0] touch_key_white_mask,
    output wire [9:0]  touch_key_black_mask,
    output wire        touch_note_on,
    output wire        touch_note_off,
    output wire [6:0]  touch_note_number
);

    assign touch_key_white_mask = 14'd0;
    assign touch_key_black_mask = 10'd0;
    assign touch_note_on        = 1'b0;
    assign touch_note_off       = 1'b0;
    assign touch_note_number    = 7'd0;

    // --------------------------------------------------------------------------
    // Stage 0: Input Latch, Dynamic Coordinate Normalization & Clamping
    // --------------------------------------------------------------------------
    reg        s0_valid;
    reg        s0_state;
    reg [13:0] s0_tx;
    reg [13:0] s0_ty;

    assign ui_touch_valid = s0_valid;
    assign ui_touch_down = s0_state;
    assign ui_touch_x = s0_tx;
    assign ui_touch_y = s0_ty;

    reg is_mode_64k;
    assign diag_mode_64k = is_mode_64k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_mode_64k <= 1'b0;
        end else if (touch_valid && (raw_touch_x[15] || raw_touch_y[15])) begin
            is_mode_64k <= 1'b1;
        end
    end

    // Panel measured on hardware: X 0..16384, Y 0..9600.
    // Default panel mode: X * 5120 >> 16, Y * 4915 >> 16 (1280x720)
    // Auto 64k mode (0..65535):   X * 1280 >> 16, Y * 720  >> 16 (1280x720)
    wire [31:0] scaled_x = is_mode_64k ? (raw_touch_x * 32'd1280) : (raw_touch_x * 32'd5120);
    wire [31:0] scaled_y = is_mode_64k ? (raw_touch_y * 32'd720)  : (raw_touch_y * 32'd4915);

    wire [13:0] norm_x = scaled_x[31:16];
    wire [13:0] norm_y = scaled_y[31:16];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diag_contact_coords <= 64'd0;
            diag_contact_count <= 16'd0;
        end else if (touch_valid && touch_state) begin
            diag_contact_coords <= {raw_touch_x, raw_touch_y,
                2'b00, ((norm_x > 14'd1279) ? 14'd1279 : norm_x),
                2'b00, ((norm_y > 14'd719) ? 14'd719 : norm_y)};
            diag_contact_count <= diag_contact_count + 16'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid <= 1'b0;
            s0_state <= 1'b0;
            s0_tx    <= 14'd0;
            s0_ty    <= 14'd0;
        end else begin
            s0_valid <= touch_valid;
            s0_state <= touch_state;
            s0_tx    <= (norm_x > 14'd1279) ? 14'd1279 : norm_x;
            s0_ty    <= (norm_y > 14'd719)  ? 14'd719  : norm_y;
        end
    end

    // Shared row dy metrics (single absolute difference per row, saving ~30 subtractors)
    wire [13:0] dy_r0 = (s0_ty >= 14'd22)  ? (s0_ty - 14'd22)  : (14'd22 - s0_ty);
    wire [13:0] dy_r1 = (s0_ty >= 14'd268) ? (s0_ty - 14'd268) : (14'd268 - s0_ty);
    wire [13:0] dy_r2 = (s0_ty >= 14'd326) ? (s0_ty - 14'd326) : (14'd326 - s0_ty);
    wire [13:0] dy_r3 = (s0_ty >= 14'd652) ? (s0_ty - 14'd652) : (14'd652 - s0_ty);

    function is_knob_x_hit;
        input [13:0] px, kx, dy;
        reg [13:0] dx;
        begin
            dx = (px >= kx) ? (px - kx) : (kx - px);
            is_knob_x_hit = (dx <= 14'd42) && (dy <= 14'd42);
        end
    endfunction

    // Box hit helper for buttons
    function is_box_hit;
        input [13:0] px, py, x0, x1, y0, y1;
        begin
            is_box_hit = (px >= x0) && (px <= x1) && (py >= y0) && (py <= y1);
        end
    endfunction

    // --------------------------------------------------------------------------
    // Stage 1: Spatial Partitioning Collision Detection
    // --------------------------------------------------------------------------
    reg        s1_valid;
    reg        s1_state;
    reg [13:0] s1_tx, s1_ty;
    reg        s1_is_knob;
    reg [7:0]  s1_knob_id;
    reg        s1_is_btn;
    reg [7:0]  s1_btn_id;
    reg [1:0]  s1_btn_act;

    reg        comb_is_knob;
    reg [7:0]  comb_knob_id;
    reg        comb_is_btn;
    reg [7:0]  comb_btn_id;
    reg [1:0]  comb_btn_act;

    always @(*) begin
        comb_is_knob = 1'b0;
        comb_knob_id = `PARAM_ID_NONE;
        comb_is_btn  = 1'b0;
        comb_btn_id  = `PARAM_ID_NONE;
        comb_btn_act = 2'd0;

        // --- ROW 0: Top Deck Header Knobs & Buttons (Y in 4..42) ---
        if (s0_tx >= 14'd796 && s0_tx <= 14'd1256 &&
            s0_ty >= 14'd368 && s0_ty <= 14'd693) begin
            // R15G: this entire area is owned by lfo_editor_state. Legacy
            // FX hit boxes below remain for history but cannot emit MIDI here.
        end else if (s0_ty >= 14'd4 && s0_ty <= 14'd42) begin
            if (is_knob_x_hit(s0_tx, 14'd200, dy_r0)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_MACRO1;
            end else if (is_knob_x_hit(s0_tx, 14'd260, dy_r0)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_MACRO2;
            end else if (is_knob_x_hit(s0_tx, 14'd320, dy_r0)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_MACRO3;
            end else if (is_knob_x_hit(s0_tx, 14'd380, dy_r0)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_MACRO4;
            end else if (is_knob_x_hit(s0_tx, 14'd1182, dy_r0)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_MASTER_VOL;
            end
            // Top Universal HUD Adjustment Bar:
            // [-] Step Dec Button: X in 500..536
            else if (s0_tx >= 14'd500 && s0_tx <= 14'd536) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_HUD_DEC; comb_btn_act = 2'd2;
            end
            // Slider Track: X in 540..740
            else if (s0_tx >= 14'd540 && s0_tx <= 14'd740) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_HUD_SLIDER;
            end
            // [+] Step Inc Button: X in 744..780
            else if (s0_tx >= 14'd744 && s0_tx <= 14'd780) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_HUD_INC; comb_btn_act = 2'd1;
            end
        end

        // --- POWER BUTTONS & PRESET ARROWS (Y in 44..74) ---
        else if (s0_ty >= 14'd44 && s0_ty <= 14'd74) begin
            // OSC A Power (X: 24..60)
            if (is_box_hit(s0_tx, s0_ty, 14'd24, 14'd60, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_POWER; comb_btn_act = 2'd0;
            end
            // OSC A Waveform Prev / Next / Bar
            else if (is_box_hit(s0_tx, s0_ty, 14'd360, 14'd390, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_WAVE; comb_btn_act = 2'd2; // prev
            end else if (is_box_hit(s0_tx, s0_ty, 14'd390, 14'd420, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_WAVE; comb_btn_act = 2'd1; // next
            end else if (is_box_hit(s0_tx, s0_ty, 14'd62, 14'd360, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_WAVE; comb_btn_act = 2'd0; // cycle
            end
            // OSC B Power (X: 438..474)
            else if (is_box_hit(s0_tx, s0_ty, 14'd438, 14'd474, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_POWER; comb_btn_act = 2'd0;
            end
            // OSC B Waveform Prev / Next / Bar
            else if (is_box_hit(s0_tx, s0_ty, 14'd776, 14'd806, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_WAVE; comb_btn_act = 2'd2;
            end else if (is_box_hit(s0_tx, s0_ty, 14'd806, 14'd836, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_WAVE; comb_btn_act = 2'd1;
            end else if (is_box_hit(s0_tx, s0_ty, 14'd476, 14'd776, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_WAVE; comb_btn_act = 2'd0;
            end
            // Filter Power (X: 854..890)
            else if (is_box_hit(s0_tx, s0_ty, 14'd854, 14'd890, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_FLT_POWER; comb_btn_act = 2'd0;
            end
            // Filter Type Prev / Next / Bar
            else if (is_box_hit(s0_tx, s0_ty, 14'd1194, 14'd1222, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_FLT_TYPE; comb_btn_act = 2'd2;
            end else if (is_box_hit(s0_tx, s0_ty, 14'd1222, 14'd1250, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_FLT_TYPE; comb_btn_act = 2'd1;
            end else if (is_box_hit(s0_tx, s0_ty, 14'd892, 14'd1194, 14'd44, 14'd74)) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_FLT_TYPE; comb_btn_act = 2'd0;
            end
        end

        // --- STEPPERS: OCT, SEMI & FINE (Y in 70..104) ---
        else if (s0_ty >= 14'd70 && s0_ty <= 14'd104) begin
            // OSC A OCT (X: 28..126)
            if (s0_tx >= 14'd28 && s0_tx <= 14'd126) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_OCT;
                comb_btn_act = (s0_tx < 14'd77) ? 2'd2 : 2'd1;
            end
            // OSC A SEMI (X: 124..220)
            else if (s0_tx >= 14'd124 && s0_tx <= 14'd220) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_SEMI;
                comb_btn_act = (s0_tx < 14'd172) ? 2'd2 : 2'd1;
            end
            // OSC A FINE (X: 220..316)
            else if (s0_tx >= 14'd220 && s0_tx <= 14'd316) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCA_FINE;
                comb_btn_act = (s0_tx < 14'd268) ? 2'd2 : 2'd1;
            end
            // OSC B OCT (X: 444..542)
            else if (s0_tx >= 14'd444 && s0_tx <= 14'd542) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_OCT;
                comb_btn_act = (s0_tx < 14'd493) ? 2'd2 : 2'd1;
            end
            // OSC B SEMI (X: 540..636)
            else if (s0_tx >= 14'd540 && s0_tx <= 14'd636) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_SEMI;
                comb_btn_act = (s0_tx < 14'd588) ? 2'd2 : 2'd1;
            end
            // OSC B FINE (X: 636..732)
            else if (s0_tx >= 14'd636 && s0_tx <= 14'd732) begin
                comb_is_btn = 1'b1; comb_btn_id = `PARAM_ID_OSCB_FINE;
                comb_btn_act = (s0_tx < 14'd684) ? 2'd2 : 2'd1;
            end
        end

        // --- SCOPES & DYNAMIC WINDOWS (Y in 104..240) ---
        else if (s0_ty >= 14'd104 && s0_ty <= 14'd240) begin
            // OSC A 2D Wavetable Scope (X: 36..412) -> Interactive Touch Scrubs WT POS A
            if (s0_tx >= 14'd36 && s0_tx <= 14'd412) begin
                comb_is_knob = 1'b1;
                comb_knob_id = `PARAM_ID_OSCA_WT_POS;
            end
            // OSC B 2D Wavetable Scope (X: 452..828) -> Interactive Touch Scrubs WT POS B
            else if (s0_tx >= 14'd452 && s0_tx <= 14'd828) begin
                comb_is_knob = 1'b1;
                comb_knob_id = `PARAM_ID_OSCB_WT_POS;
            end
            // Filter Frequency Response Scope (X: 868..1244) -> Interactive Touch Sweeps Cutoff
            else if (s0_tx >= 14'd868 && s0_tx <= 14'd1244) begin
                // Direct XY manipulation is owned by curve_touch_editor.
            end
        end

        // --- FILTER ROUTING CHECKBOXES [A], [B], [N], [S], [K] (Y in 244..358, X in 850..920) ---
        else if (s0_tx >= 14'd850 && s0_tx <= 14'd920 && s0_ty >= 14'd244 && s0_ty <= 14'd358) begin
            comb_is_btn  = 1'b1;
            comb_btn_act = 2'd0;
            if (s0_ty < 14'd267)
                comb_btn_id = `PARAM_ID_FLT_ROUTE_A;
            else if (s0_ty < 14'd289)
                comb_btn_id = `PARAM_ID_FLT_ROUTE_B;
            else if (s0_ty < 14'd311)
                comb_btn_id = `PARAM_ID_FLT_ROUTE_N;
            else if (s0_ty < 14'd333)
                comb_btn_id = `PARAM_ID_FLT_ROUTE_S;
            else
                comb_btn_id = `PARAM_ID_FLT_KEYTRACK;
        end

        // --- ROW 1: OSC A/B & Filter Knobs Row 1 (Y in 242..294) ---
        else if (s0_ty >= 14'd242 && s0_ty <= 14'd294) begin
            // OSC A
            if (is_knob_x_hit(s0_tx, 14'd64, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_UNISON;
            end else if (is_knob_x_hit(s0_tx, 14'd134, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_DETUNE;
            end else if (is_knob_x_hit(s0_tx, 14'd204, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_BLEND;
            end else if (is_knob_x_hit(s0_tx, 14'd274, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_PHASE;
            end else if (is_knob_x_hit(s0_tx, 14'd344, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_RAND;
            end
            // OSC B
            else if (is_knob_x_hit(s0_tx, 14'd480, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_UNISON;
            end else if (is_knob_x_hit(s0_tx, 14'd550, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_DETUNE;
            end else if (is_knob_x_hit(s0_tx, 14'd620, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_BLEND;
            end else if (is_knob_x_hit(s0_tx, 14'd690, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_PHASE;
            end else if (is_knob_x_hit(s0_tx, 14'd760, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_RAND;
            end
            // Filter Knobs
            else if (is_knob_x_hit(s0_tx, 14'd950, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_CUTOFF;
            end else if (is_knob_x_hit(s0_tx, 14'd1040, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_RES;
            end else if (is_knob_x_hit(s0_tx, 14'd1130, dy_r1)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_PAN;
            end
        end

        // --- ROW 2: OSC A/B & Filter Knobs Row 2 (Y in 300..356) ---
        else if (s0_ty >= 14'd300 && s0_ty <= 14'd356) begin
            // OSC A
            if (is_knob_x_hit(s0_tx, 14'd84, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_WT_POS;
            end else if (is_knob_x_hit(s0_tx, 14'd164, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_WARP;
            end else if (is_knob_x_hit(s0_tx, 14'd264, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_PAN;
            end else if (is_knob_x_hit(s0_tx, 14'd344, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCA_VOL;
            end
            // OSC B
            else if (is_knob_x_hit(s0_tx, 14'd500, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_WT_POS;
            end else if (is_knob_x_hit(s0_tx, 14'd580, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_WARP;
            end else if (is_knob_x_hit(s0_tx, 14'd680, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_PAN;
            end else if (is_knob_x_hit(s0_tx, 14'd760, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_OSCB_VOL;
            end
            // Filter Knobs
            else if (is_knob_x_hit(s0_tx, 14'd950, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_DRIVE;
            end else if (is_knob_x_hit(s0_tx, 14'd1040, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_FAT;
            end else if (is_knob_x_hit(s0_tx, 14'd1130, dy_r2)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FLT_MIX;
            end
        end

        // --- ENVELOPE TABS (Y in 365..402) ---
        else if (s0_ty >= 14'd365 && s0_ty <= 14'd402 && s0_tx >= 14'd28 && s0_tx <= 14'd310) begin
            comb_is_btn = 1'b1;
            comb_btn_id = `PARAM_ID_ENV_TAB;
            if (s0_tx < 14'd123)
                comb_btn_act = 2'd0; // ENV 1
            else if (s0_tx < 14'd213)
                comb_btn_act = 2'd1; // ENV 2
            else
                comb_btn_act = 2'd2; // ENV 3
        end

        // --- Retired matrix mapping, preserved for historical reference only ---
        else if (1'b0 && s0_ty >= 14'd404 && s0_ty <= 14'd546 && s0_tx >= 14'd790 && s0_tx <= 14'd1250) begin
            if (s0_tx <= 14'd840) begin
                // Bypass Buttons
                comb_is_btn  = 1'b1;
                comb_btn_act = 2'd0;
                if (s0_ty < 14'd438)
                    comb_btn_id = `PARAM_ID_SLOT1_BYPASS;
                else if (s0_ty < 14'd472)
                    comb_btn_id = `PARAM_ID_SLOT2_BYPASS;
                else if (s0_ty < 14'd506)
                    comb_btn_id = `PARAM_ID_SLOT3_BYPASS;
                else
                    comb_btn_id = `PARAM_ID_SLOT4_BYPASS;
            end else begin
                // Modulation Amount Knobs / Sliders
                comb_is_knob = 1'b1;
                if (s0_ty < 14'd438)
                    comb_knob_id = `PARAM_ID_FX_REVERB;
                else if (s0_ty < 14'd472)
                    comb_knob_id = `PARAM_ID_FX_DELAY;
                else if (s0_ty < 14'd506)
                    comb_knob_id = `PARAM_ID_FX_CHORUS;
                else
                    comb_knob_id = `PARAM_ID_PORTAMENTO;
            end
        end

        // --- DYNAMIC ADSR ENVELOPE SCOPE (X in 28..780, Y in 404..610) ---
        else if (s0_ty >= 14'd404 && s0_ty <= 14'd610 && s0_tx >= 14'd28 && s0_tx <= 14'd780) begin
            comb_is_knob = 1'b0; // Retired fixed-zone mapping; direct nodes own this scope.
            if (s0_tx < 14'd210)
                comb_knob_id = `PARAM_ID_ENV1_ATTACK;
            else if (s0_tx < 14'd380)
                comb_knob_id = `PARAM_ID_ENV1_DECAY;
            else if (s0_tx < 14'd560)
                comb_knob_id = `PARAM_ID_ENV1_SUSTAIN;
            else
                comb_knob_id = `PARAM_ID_ENV1_RELEASE;
        end

        // --- ROW 3: Expanded Lower Deck Knobs (Y in 624..680, CY = 652) ---
        else if (s0_ty >= 14'd624 && s0_ty <= 14'd680) begin
            // Envelope 1
            if (is_knob_x_hit(s0_tx, 14'd100, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_ENV1_ATTACK;
            end else if (is_knob_x_hit(s0_tx, 14'd230, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_ENV1_HOLD;
            end else if (is_knob_x_hit(s0_tx, 14'd360, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_ENV1_DECAY;
            end else if (is_knob_x_hit(s0_tx, 14'd490, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_ENV1_SUSTAIN;
            end else if (is_knob_x_hit(s0_tx, 14'd620, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_ENV1_RELEASE;
            end
            // Master FX
            else if (is_knob_x_hit(s0_tx, 14'd860, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FX_REVERB;
            end else if (is_knob_x_hit(s0_tx, 14'd960, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FX_DELAY;
            end else if (is_knob_x_hit(s0_tx, 14'd1060, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_FX_CHORUS;
            end else if (is_knob_x_hit(s0_tx, 14'd1160, dy_r3)) begin
                comb_is_knob = 1'b1; comb_knob_id = `PARAM_ID_PORTAMENTO;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_state   <= 1'b0;
            s1_tx      <= 14'd0;
            s1_ty      <= 14'd0;
            s1_is_knob <= 1'b0;
            s1_knob_id <= `PARAM_ID_NONE;
            s1_is_btn  <= 1'b0;
            s1_btn_id  <= `PARAM_ID_NONE;
            s1_btn_act <= 2'd0;
        end else begin
            s1_valid   <= s0_valid;
            s1_state   <= s0_state;
            s1_tx      <= s0_tx;
            s1_ty      <= s0_ty;
            s1_is_knob <= comb_is_knob;
            s1_knob_id <= comb_knob_id;
            s1_is_btn  <= comb_is_btn;
            s1_btn_id  <= comb_btn_id;
            s1_btn_act <= comb_btn_act;
        end
    end

    // --------------------------------------------------------------------------
    // Stage 2: Event FSM & Output Dispatcher
    // --------------------------------------------------------------------------
    reg        finger_down;
    reg [13:0] last_touch_x;
    reg [13:0] last_touch_y;
    reg [7:0]  active_knob_id;
    reg        knob_is_dragging;
    reg signed [13:0] drag_acc;
    reg        btn_latched;
    reg [7:0]  latched_btn_id;
    reg [1:0]  latched_btn_act;
    reg [25:0] btn_repeat_timer;
    reg [23:0] silence_watchdog;

    wire signed [13:0] cur_drag_acc = drag_acc + 
                        ($signed({1'b0, last_touch_y}) - $signed({1'b0, s1_ty})) +
                        ($signed({1'b0, s1_tx}) - $signed({1'b0, last_touch_x}));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selected_param_id <= `PARAM_ID_FLT_CUTOFF; // Default to Filter Cutoff on boot
            selected_valid    <= 1'b1;
            param_delta_valid <= 1'b0;
            param_delta_val   <= 8'sd0;
            btn_tap_valid     <= 1'b0;
            btn_tap_id        <= `PARAM_ID_NONE;
            btn_tap_action    <= 2'd0;
            finger_down       <= 1'b0;
            last_touch_x      <= 14'd0;
            last_touch_y      <= 14'd0;
            active_knob_id    <= `PARAM_ID_NONE;
            knob_is_dragging  <= 1'b0;
            drag_acc          <= 14'sd0;
            btn_latched       <= 1'b0;
            latched_btn_id    <= `PARAM_ID_NONE;
            latched_btn_act   <= 2'd0;
            btn_repeat_timer  <= 26'd0;
            silence_watchdog  <= 24'd0;
        end else begin
            param_delta_valid <= 1'b0;
            param_delta_val   <= 8'sd0;
            btn_tap_valid     <= 1'b0;

            // Silence watchdog: if no packet arrives for 50ms (3,125,000 cycles), release finger
            if (silence_watchdog < 24'd3_125_000) begin
                silence_watchdog <= silence_watchdog + 24'd1;
            end else begin
                finger_down      <= 1'b0;
                knob_is_dragging <= 1'b0;
                btn_latched      <= 1'b0;
                latched_btn_id   <= `PARAM_ID_NONE;
                latched_btn_act  <= 2'd0;
                btn_repeat_timer <= 26'd0;
                drag_acc         <= 14'sd0;
            end

            if (s1_valid) begin
                if(curve_capture_active) begin
                    // The dedicated editor owns this gesture.
                end else begin
                silence_watchdog <= 24'd0; // Reset watchdog on fresh packet

                // Touch Down / Contact Active
                if (s1_state) begin
                    if (!finger_down) begin
                        // Finger just landed on screen!
                        finger_down      <= 1'b1;
                        last_touch_x     <= s1_tx;
                        last_touch_y     <= s1_ty;
                        drag_acc         <= 14'sd0;
                        btn_repeat_timer <= 26'd0;

                        if (s1_is_btn) begin
                            if (s1_btn_id == `PARAM_ID_HUD_DEC) begin
                                if (selected_param_id != `PARAM_ID_NONE) begin
                                    param_delta_valid <= 1'b1;
                                    param_delta_val   <= -8'sd1;
                                end
                                btn_latched      <= 1'b1;
                                latched_btn_id   <= `PARAM_ID_HUD_DEC;
                                knob_is_dragging <= 1'b0;
                                active_knob_id   <= `PARAM_ID_NONE;
                            end else if (s1_btn_id == `PARAM_ID_HUD_INC) begin
                                if (selected_param_id != `PARAM_ID_NONE) begin
                                    param_delta_valid <= 1'b1;
                                    param_delta_val   <= 8'sd1;
                                end
                                btn_latched      <= 1'b1;
                                latched_btn_id   <= `PARAM_ID_HUD_INC;
                                knob_is_dragging <= 1'b0;
                                active_knob_id   <= `PARAM_ID_NONE;
                            end else begin
                                btn_tap_valid     <= 1'b1;
                                btn_tap_id        <= s1_btn_id;
                                btn_tap_action    <= s1_btn_act;
                                btn_latched       <= 1'b1;
                                latched_btn_id    <= s1_btn_id;
                                latched_btn_act   <= s1_btn_act;
                                selected_param_id <= s1_btn_id;
                                selected_valid    <= 1'b1;
                                knob_is_dragging  <= 1'b0;
                                active_knob_id    <= `PARAM_ID_NONE;
                            end
                        end else if (s1_is_knob) begin
                            if (s1_knob_id == `PARAM_ID_HUD_SLIDER) begin
                                if (selected_param_id != `PARAM_ID_NONE) begin
                                    active_knob_id   <= selected_param_id;
                                    knob_is_dragging <= 1'b1;
                                end
                            end else begin
                                active_knob_id    <= s1_knob_id;
                                selected_param_id <= s1_knob_id;
                                selected_valid    <= 1'b1;
                                knob_is_dragging  <= 1'b1;
                            end
                            btn_latched       <= 1'b0;
                            latched_btn_id    <= `PARAM_ID_NONE;
                        end else begin
                            knob_is_dragging  <= 1'b0;
                            btn_latched       <= 1'b0;
                            latched_btn_id    <= `PARAM_ID_NONE;
                        end
                    end else begin
                        // Finger is still on screen (Moving / Dragging / Holding)
                        if (s1_is_btn) begin
                            // 1. Instant activation if entering button or moving to different button / tab
                            if (!btn_latched || (s1_btn_id != latched_btn_id) ||
                                ((s1_btn_id == `PARAM_ID_ENV_TAB || s1_btn_id == `PARAM_ID_OSCA_WAVE || s1_btn_id == `PARAM_ID_OSCB_WAVE || s1_btn_id == `PARAM_ID_FLT_TYPE) && (s1_btn_act != latched_btn_act))) begin
                                if (s1_btn_id == `PARAM_ID_HUD_DEC) begin
                                    if (selected_param_id != `PARAM_ID_NONE) begin
                                        param_delta_valid <= 1'b1;
                                        param_delta_val   <= -8'sd1;
                                    end
                                end else if (s1_btn_id == `PARAM_ID_HUD_INC) begin
                                    if (selected_param_id != `PARAM_ID_NONE) begin
                                        param_delta_valid <= 1'b1;
                                        param_delta_val   <= 8'sd1;
                                    end
                                end else begin
                                    btn_tap_valid     <= 1'b1;
                                    btn_tap_id        <= s1_btn_id;
                                    btn_tap_action    <= s1_btn_act;
                                    selected_param_id <= s1_btn_id;
                                    selected_valid    <= 1'b1;
                                end
                                btn_latched       <= 1'b1;
                                latched_btn_id    <= s1_btn_id;
                                latched_btn_act   <= s1_btn_act;
                                knob_is_dragging  <= 1'b0;
                                active_knob_id    <= `PARAM_ID_NONE;
                                btn_repeat_timer  <= 26'd0;
                            end
                            // 2. Stepper & HUD Button Hold-to-Repeat check
                            else if (s1_btn_id == `PARAM_ID_HUD_DEC || s1_btn_id == `PARAM_ID_HUD_INC) begin
                                if (btn_repeat_timer >= 26'd18_750_000) begin
                                    if (selected_param_id != `PARAM_ID_NONE) begin
                                        param_delta_valid <= 1'b1;
                                        param_delta_val   <= (s1_btn_id == `PARAM_ID_HUD_INC) ? 8'sd1 : -8'sd1;
                                    end
                                    btn_repeat_timer <= 26'd12_500_000;
                                end else begin
                                    btn_repeat_timer <= btn_repeat_timer + 26'd625_000;
                                end
                            end
                            else if (s1_btn_id == `PARAM_ID_OSCA_OCT  || s1_btn_id == `PARAM_ID_OSCA_SEMI || s1_btn_id == `PARAM_ID_OSCA_FINE ||
                                     s1_btn_id == `PARAM_ID_OSCB_OCT  || s1_btn_id == `PARAM_ID_OSCB_SEMI || s1_btn_id == `PARAM_ID_OSCB_FINE) begin
                                if (btn_repeat_timer >= 26'd25_000_000) begin
                                    btn_tap_valid    <= 1'b1;
                                    btn_tap_id       <= s1_btn_id;
                                    btn_tap_action   <= s1_btn_act;
                                    btn_repeat_timer <= 26'd18_750_000;
                                end else begin
                                    btn_repeat_timer <= btn_repeat_timer + 26'd625_000;
                                end
                            end
                        end else if (knob_is_dragging && (active_knob_id != `PARAM_ID_NONE)) begin
                            last_touch_x <= s1_tx;
                            last_touch_y <= s1_ty;

                            if (cur_drag_acc >= 14'sd2) begin
                                param_delta_valid <= 1'b1;
                                param_delta_val   <= (cur_drag_acc >= 14'sd20) ? 8'sd8 :
                                                     (cur_drag_acc >= 14'sd10) ? 8'sd4 :
                                                     (cur_drag_acc >= 14'sd5)  ? 8'sd2 : 8'sd1;
                                drag_acc          <= 14'sd0;
                            end else if (cur_drag_acc <= -14'sd2) begin
                                param_delta_valid <= 1'b1;
                                param_delta_val   <= (cur_drag_acc <= -14'sd20) ? -8'sd8 :
                                                     (cur_drag_acc <= -14'sd10) ? -8'sd4 :
                                                     (cur_drag_acc <= -14'sd5)  ? -8'sd2 : -8'sd1;
                                drag_acc          <= 14'sd0;
                            end else begin
                                drag_acc          <= cur_drag_acc;
                            end
                        end
                    end
                end else begin
                    // Finger explicitly lifted (!s1_state)
                    finger_down      <= 1'b0;
                    knob_is_dragging <= 1'b0;
                    btn_latched      <= 1'b0;
                    latched_btn_id   <= `PARAM_ID_NONE;
                    latched_btn_act  <= 2'd0;
                    btn_repeat_timer <= 26'd0;
                    drag_acc         <= 14'sd0;
                end
            end
                end
            // A captured curve owns the entire contact, including excursions
            // over buttons/tabs. Reset the generic FSM for the next gesture.
            if(curve_capture_active) begin
                finger_down<=0;knob_is_dragging<=0;btn_latched<=0;
                param_delta_valid<=0;btn_tap_valid<=0;
                latched_btn_id<=`PARAM_ID_NONE;active_knob_id<=`PARAM_ID_NONE;
                drag_acc<=0;btn_repeat_timer<=0;
            end
            if(curve_focus_valid) begin
                selected_param_id<=curve_focus_id;selected_valid<=1;
            end
        end
    end

endmodule
