// ==============================================================================
// Module: param_merger.v
// Description: Two-Way Parameter Fusion & Dispute Arbiter
//              - Intake 1: Absolute SPI parameters from Teammate 1 (Hardware knobs)
//              - Intake 2: Incremental relative drag deltas from Touch Event Router
//              - Intake 3: Instant Button Tap & Toggle events
//              - Output: Glitch-free synchronous parameter bank with saturation clamps
//              - MIDI Dispatch: Fires 1-cycle strobe and CC payload to midi_uart_tx
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`include "params.vh"

module param_merger #(parameter PRESET_ENABLE=0)(
    input wire preset_load,preset_busy,
    input wire [517:0] preset_values,
    input  wire        clk,
    input  wire        rst_n,

    // Intake 1: Hardware Knob SPI Absolute Bus (Teammate 1)
    input  wire        spi_param_valid,
    input  wire [7:0]  spi_param_id,
    input  wire [6:0]  spi_param_val,

    // Intake 2: On-Screen Touch Incremental Drag Bus
    input  wire        touch_delta_valid,
    input  wire [7:0]  touch_selected_id,
    input  wire signed [7:0] touch_delta_val,

    // Absolute curve transactions, latched so concurrent SPI cannot lose them.
    input wire curve_update_valid,curve_update_filter,
    input wire [1:0] curve_update_tab,
    input wire [4:0] curve_update_mask,
    input wire [34:0] curve_update_values,
    input wire midi_tx_busy,

    // Intake 3: On-Screen Button Tap & Toggle Events
    input  wire        btn_tap_valid,
    input  wire [7:0]  btn_tap_id,
    input  wire [1:0]  btn_tap_action,

    // Continuous Parameter Outputs (7-bit, 0..127)
    output reg  [6:0]  val_macro1,
    output reg  [6:0]  val_macro2,
    output reg  [6:0]  val_macro3,
    output reg  [6:0]  val_macro4,
    output reg  [6:0]  val_master_vol,

    output reg  [6:0]  val_osca_unison,
    output reg  [6:0]  val_osca_detune,
    output reg  [6:0]  val_osca_blend,
    output reg  [6:0]  val_osca_phase,
    output reg  [6:0]  val_osca_rand,
    output reg  [6:0]  val_osca_wt_pos,
    output reg  [6:0]  val_osca_warp,
    output reg  [6:0]  val_osca_pan,
    output reg  [6:0]  val_osca_vol,

    output reg  [6:0]  val_oscb_unison,
    output reg  [6:0]  val_oscb_detune,
    output reg  [6:0]  val_oscb_blend,
    output reg  [6:0]  val_oscb_phase,
    output reg  [6:0]  val_oscb_rand,
    output reg  [6:0]  val_oscb_wt_pos,
    output reg  [6:0]  val_oscb_warp,
    output reg  [6:0]  val_oscb_pan,
    output reg  [6:0]  val_oscb_vol,

    output reg  [6:0]  val_flt_cutoff,
    output reg  [6:0]  val_flt_res,
    output reg  [6:0]  val_flt_pan,
    output reg  [6:0]  val_flt_drive,
    output reg  [6:0]  val_flt_fat,
    output reg  [6:0]  val_flt_mix,

    output wire [6:0]  val_env_attack,
    output wire [6:0]  val_env_hold,
    output wire [6:0]  val_env_decay,
    output wire [6:0]  val_env_sustain,
    output wire [6:0]  val_env_release,

    output reg  [6:0]  val_fx_reverb,
    output reg  [6:0]  val_fx_delay,
    output reg  [6:0]  val_fx_chorus,
    output reg  [6:0]  val_portamento,

    // Button & Switch Discrete State Outputs
    output reg         val_osca_power,
    output reg         val_oscb_power,
    output reg         val_flt_power,
    output reg  [2:0]  val_osca_wave,
    output reg  [2:0]  val_oscb_wave,
    output reg  [3:0]  val_osca_oct,
    output reg  [4:0]  val_osca_semi,
    output reg  [6:0]  val_osca_fine,
    output reg  [3:0]  val_oscb_oct,
    output reg  [4:0]  val_oscb_semi,
    output reg  [6:0]  val_oscb_fine,
    output reg  [1:0]  val_flt_type,
    output reg         val_flt_route_a,
    output reg         val_flt_route_b,
    output reg         val_flt_route_n,
    output reg         val_flt_route_s,
    output reg         val_flt_keytrack,
    output reg  [1:0]  val_env_tab,
    output reg  [3:0]  val_slot_bypass,

    // Button tactile feedback outputs
    output reg  [7:0]  active_btn_id,
    output reg         btn_flash_active,

    // MIDI UART CC Command Dispatch
    output reg         midi_cc_req,
    output reg  [7:0]  midi_cc_param_id,
    output reg  [6:0]  midi_cc_val,
    output wire [237:0] static_cc_values
);
    // Capture all event buses together before arbitration. This breaks the
    // shared UI-ID decode path without changing same-cycle source priority.
    // MIDI busy remains live backpressure; events gain one clock of latency.
    reg  event_spi_param_valid /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [7:0] event_spi_param_id /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [6:0] event_spi_param_val /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [1:0] event_spi_env_tab;
    reg  event_touch_delta_valid /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [7:0] event_touch_selected_id /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg signed [7:0] event_touch_delta_val /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [1:0] event_touch_env_tab;
    reg  event_curve_update_valid /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg  event_curve_update_filter /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [1:0] event_curve_update_tab /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [4:0] event_curve_update_mask /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [34:0] event_curve_update_values /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg  event_btn_tap_valid /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [7:0] event_btn_tap_id /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    reg [1:0] event_btn_tap_action /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            event_spi_param_valid<=0;
            event_spi_param_id<=0;
            event_spi_param_val<=0;
            event_spi_env_tab<=0;
            event_touch_delta_valid<=0;
            event_touch_selected_id<=0;
            event_touch_delta_val<=0;
            event_touch_env_tab<=0;
            event_curve_update_valid<=0;
            event_curve_update_filter<=0;
            event_curve_update_tab<=0;
            event_curve_update_mask<=0;
            event_curve_update_values<=0;
            event_btn_tap_valid<=0;
            event_btn_tap_id<=0;
            event_btn_tap_action<=0;
        end else begin
            event_spi_param_valid<=spi_param_valid && !(PRESET_ENABLE && preset_busy);
            event_spi_param_id<=((spi_param_id>=`PARAM_ID_ENV1_ATTACK && spi_param_id<=`PARAM_ID_ENV1_RELEASE && val_env_tab==2'd1) ? (spi_param_id+8'h18) : spi_param_id);
            event_spi_env_tab<=(spi_param_id>=`PARAM_ID_ENV2_ATTACK && spi_param_id<=`PARAM_ID_ENV2_RELEASE) ? 2'd1 : val_env_tab;
            event_spi_param_val<=spi_param_val;
            event_touch_delta_valid<=touch_delta_valid && !(PRESET_ENABLE && preset_busy);
            event_touch_selected_id<=((touch_selected_id>=`PARAM_ID_ENV1_ATTACK && touch_selected_id<=`PARAM_ID_ENV1_RELEASE && val_env_tab==2'd1) ? (touch_selected_id+8'h18) : touch_selected_id);
            event_touch_env_tab<=(touch_selected_id>=`PARAM_ID_ENV2_ATTACK && touch_selected_id<=`PARAM_ID_ENV2_RELEASE) ? 2'd1 : val_env_tab;
            event_touch_delta_val<=touch_delta_val;
            event_curve_update_valid<=curve_update_valid && !(PRESET_ENABLE && preset_busy);
            event_curve_update_filter<=curve_update_filter;
            event_curve_update_tab<=curve_update_tab;
            event_curve_update_mask<=curve_update_mask;
            event_curve_update_values<=curve_update_values;
            event_btn_tap_valid<=btn_tap_valid && !(PRESET_ENABLE && preset_busy);
            event_btn_tap_id<=btn_tap_id;
            event_btn_tap_action<=btn_tap_action;
        end
    end


    // 7-Bit Saturation Clamp
    function [6:0] clamp7;
        input signed [9:0] raw_val;
        begin
            if (raw_val < 10'sd0)
                clamp7 = 7'd0;
            else if (raw_val > 10'sd127)
                clamp7 = 7'd127;
            else
                clamp7 = raw_val[6:0];
        end
    endfunction

    // Unison Voice Clamp (1..8)
    function [6:0] clamp_unison;
        input signed [9:0] raw_val;
        begin
            if (raw_val < 10'sd1)
                clamp_unison = 7'd1;
            else if (raw_val > 10'sd8)
                clamp_unison = 7'd8;
            else
                clamp_unison = raw_val[6:0];
        end
    endfunction

    reg [6:0] new_v;
    reg [23:0] flash_timer;
    reg [6:0] env_a[0:2],env_h[0:2],env_d[0:2],env_s[0:2],env_r[0:2];
    assign val_env_attack=env_a[val_env_tab];
    assign val_env_hold=env_h[val_env_tab];
    assign val_env_decay=env_d[val_env_tab];
    assign val_env_sustain=env_s[val_env_tab];
    assign val_env_release=env_r[val_env_tab];
    // Authoritative live bank: ENV1/2 are exported independently of visible tab.
    assign static_cc_values[0+:7]=val_master_vol; // MASTER_VOL
    assign static_cc_values[7+:7]=val_flt_pan; // FLT_PAN
    assign static_cc_values[14+:7]=(val_osca_power ? 7'd127 : 7'd0); // OSCA_POWER
    assign static_cc_values[21+:7]={4'd0,val_osca_wave}; // OSCA_WAVE
    assign static_cc_values[28+:7]=val_osca_unison; // OSCA_UNISON
    assign static_cc_values[35+:7]=val_osca_detune; // OSCA_DETUNE
    assign static_cc_values[42+:7]=val_osca_phase; // OSCA_PHASE
    assign static_cc_values[49+:7]=val_osca_rand; // OSCA_RAND
    assign static_cc_values[56+:7]=val_osca_wt_pos; // OSCA_WT_POS
    assign static_cc_values[63+:7]=val_osca_warp; // OSCA_WARP
    assign static_cc_values[70+:7]=val_osca_pan; // OSCA_PAN
    assign static_cc_values[77+:7]=val_osca_vol; // OSCA_VOL
    assign static_cc_values[84+:7]=(val_oscb_power ? 7'd127 : 7'd0); // OSCB_POWER
    assign static_cc_values[91+:7]={4'd0,val_oscb_wave}; // OSCB_WAVE
    assign static_cc_values[98+:7]=val_oscb_unison; // OSCB_UNISON
    assign static_cc_values[105+:7]=val_oscb_detune; // OSCB_DETUNE
    assign static_cc_values[112+:7]=val_oscb_phase; // OSCB_PHASE
    assign static_cc_values[119+:7]=val_oscb_rand; // OSCB_RAND
    assign static_cc_values[126+:7]=val_oscb_wt_pos; // OSCB_WT_POS
    assign static_cc_values[133+:7]=val_oscb_warp; // OSCB_WARP
    assign static_cc_values[140+:7]=val_oscb_pan; // OSCB_PAN
    assign static_cc_values[147+:7]=val_oscb_vol; // OSCB_VOL
    assign static_cc_values[154+:7]=(val_flt_power ? {5'd0,val_flt_type}+7'd1 : 7'd0); // FLT_TYPE
    assign static_cc_values[161+:7]=val_flt_cutoff; // FLT_CUTOFF
    assign static_cc_values[168+:7]=val_flt_res; // FLT_RES
    assign static_cc_values[175+:7]=val_flt_mix; // FLT_MIX
    assign static_cc_values[182+:7]=env_a[0]; // ENV1_ATTACK
    assign static_cc_values[189+:7]=env_d[0]; // ENV1_DECAY
    assign static_cc_values[196+:7]=env_s[0]; // ENV1_SUSTAIN
    assign static_cc_values[203+:7]=env_r[0]; // ENV1_RELEASE
    assign static_cc_values[210+:7]=env_a[1]; // ENV2_ATTACK
    assign static_cc_values[217+:7]=env_d[1]; // ENV2_DECAY
    assign static_cc_values[224+:7]=env_s[1]; // ENV2_SUSTAIN
    assign static_cc_values[231+:7]=env_r[1]; // ENV2_RELEASE
    reg curve_pending,curve_filter;
    reg [1:0] curve_tab;
    reg [4:0] curve_mask;
    reg [34:0] curve_values;
    // Filter C/R, ENV1 A/reserved/D/S/R, ENV2 A/D/S/R. Hold is local.
    reg [10:0] curve_midi_pending;
    integer env_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Top Bar
            val_macro1       <= 7'd64;
            val_macro2       <= 7'd64;
            val_macro3       <= 7'd64;
            val_macro4       <= 7'd64;
            val_master_vol   <= 7'd100;

            // OSC A
            val_osca_unison  <= 7'd1;
            val_osca_detune  <= 7'd64;
            val_osca_blend   <= 7'd64;
            val_osca_phase   <= 7'd0;
            val_osca_rand    <= 7'd64;
            val_osca_wt_pos  <= 7'd0;
            val_osca_warp    <= 7'd64;
            val_osca_pan     <= 7'd64;
            val_osca_vol     <= 7'd100;

            // OSC B
            val_oscb_unison  <= 7'd1;
            val_oscb_detune  <= 7'd64;
            val_oscb_blend   <= 7'd64;
            val_oscb_phase   <= 7'd0;
            val_oscb_rand    <= 7'd64;
            val_oscb_wt_pos  <= 7'd64;
            val_oscb_warp    <= 7'd64;
            val_oscb_pan     <= 7'd64;
            val_oscb_vol     <= 7'd100;

            // Filter
            val_flt_cutoff   <= 7'd80;
            val_flt_res      <= 7'd32;
            val_flt_pan      <= 7'd64;
            val_flt_drive    <= 7'd0;
            val_flt_fat      <= 7'd0;
            val_flt_mix      <= 7'd127;

            // Envelope 1
            for(env_i=0;env_i<3;env_i=env_i+1) begin
                env_a[env_i]<=7'd10;env_h[env_i]<=7'd0;env_d[env_i]<=7'd40;
                env_s[env_i]<=7'd90;env_r[env_i]<=7'd35;
            end
            curve_pending<=0;curve_filter<=0;curve_tab<=0;curve_mask<=0;curve_values<=0;
            curve_midi_pending<=0;

            // FX Matrix
            val_fx_reverb    <= 7'd20;
            val_fx_delay     <= 7'd0;
            val_fx_chorus    <= 7'd0;
            val_portamento   <= 7'd0;

            // Discrete Button & Switch States
            val_osca_power   <= 1'b1;
            val_oscb_power   <= 1'b1;
            val_flt_power    <= 1'b1;
            val_osca_wave    <= 2'd0;
            val_oscb_wave    <= 2'd1;
            val_osca_oct     <= 4'd4;  // Center: 0 Octave
            val_osca_semi    <= 5'd12; // Center: 0 Semitone
            val_osca_fine    <= 7'd64; // Center: 0 Fine
            val_oscb_oct     <= 4'd4;
            val_oscb_semi    <= 5'd12;
            val_oscb_fine    <= 7'd64;
            val_flt_type     <= 2'd0;
            val_flt_route_a  <= 1'b1;
            val_flt_route_b  <= 1'b0;
            val_flt_route_n  <= 1'b0;
            val_flt_route_s  <= 1'b0;
            val_flt_keytrack <= 1'b0;
            val_env_tab      <= 2'd0;
            val_slot_bypass  <= 4'b0000;

            active_btn_id    <= `PARAM_ID_NONE;
            btn_flash_active <= 1'b0;
            flash_timer      <= 24'd0;

            midi_cc_req      <= 1'b0;
            midi_cc_param_id <= 8'd0;
            midi_cc_val      <= 7'd0;
        end else if(PRESET_ENABLE && preset_load)begin
            val_master_vol<=preset_values[0+:7];
            val_flt_pan<=preset_values[7+:7];
            val_osca_unison<=preset_values[28+:7];
            val_osca_detune<=preset_values[35+:7];
            val_osca_phase<=preset_values[42+:7];
            val_osca_rand<=preset_values[49+:7];
            val_osca_wt_pos<=preset_values[56+:7];
            val_osca_warp<=preset_values[63+:7];
            val_osca_pan<=preset_values[70+:7];
            val_osca_vol<=preset_values[77+:7];
            val_oscb_unison<=preset_values[98+:7];
            val_oscb_detune<=preset_values[105+:7];
            val_oscb_phase<=preset_values[112+:7];
            val_oscb_rand<=preset_values[119+:7];
            val_oscb_wt_pos<=preset_values[126+:7];
            val_oscb_warp<=preset_values[133+:7];
            val_oscb_pan<=preset_values[140+:7];
            val_oscb_vol<=preset_values[147+:7];
            val_flt_cutoff<=preset_values[161+:7];
            val_flt_res<=preset_values[168+:7];
            val_flt_mix<=preset_values[175+:7];
            env_a[0]<=preset_values[182+:7];
            env_d[0]<=preset_values[189+:7];
            env_s[0]<=preset_values[196+:7];
            env_r[0]<=preset_values[203+:7];
            env_a[1]<=preset_values[210+:7];
            env_d[1]<=preset_values[217+:7];
            env_s[1]<=preset_values[224+:7];
            env_r[1]<=preset_values[231+:7];
            val_osca_power<=preset_values[14+:7]!=0;
            val_oscb_power<=preset_values[84+:7]!=0;
            val_osca_wave<=preset_values[21+:3];val_oscb_wave<=preset_values[91+:3];
            val_flt_power<=preset_values[154+:7]!=0;
            val_flt_type<=preset_values[154+:7]==0 ? 0 : preset_values[154+:7]-7'd1;
            env_h[0]<=0;env_h[1]<=0;
            curve_pending<=0;curve_midi_pending<=0;midi_cc_req<=0;btn_flash_active<=0;
        end else if(PRESET_ENABLE && preset_busy)begin
            midi_cc_req<=0;curve_pending<=0;curve_midi_pending<=0;
        end else begin
            midi_cc_req <= 1'b0;
            if(event_curve_update_valid) begin
                curve_pending<=1;curve_filter<=event_curve_update_filter;
                curve_tab<=event_curve_update_tab;curve_mask<=event_curve_update_mask;
                curve_values<=event_curve_update_values;
            end

            // Flash feedback countdown (~160ms @ 62.5MHz)
            if (flash_timer != 24'd0) begin
                flash_timer <= flash_timer - 24'd1;
            end else begin
                btn_flash_active <= 1'b0;
            end

            // ------------------------------------------------------------------
            // 1. Process Button Tap / Toggle Events (Highest Priority)
            // ------------------------------------------------------------------
            if (event_btn_tap_valid) begin
                midi_cc_req      <= 1'b1;
                midi_cc_param_id <= event_btn_tap_id;
                active_btn_id    <= event_btn_tap_id;
                btn_flash_active <= 1'b1;
                flash_timer      <= 24'd10_000_000;

                case (event_btn_tap_id)
                    `PARAM_ID_OSCA_POWER: begin
                        val_osca_power <= ~val_osca_power;
                        midi_cc_val    <= ~val_osca_power ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_OSCB_POWER: begin
                        val_oscb_power <= ~val_oscb_power;
                        midi_cc_val    <= ~val_oscb_power ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_FLT_POWER: begin
                        val_flt_power <= ~val_flt_power;
                        // Audio CC42 uses 0=bypass and 1..4 for the four UI modes.
                        midi_cc_val   <= ~val_flt_power
                                       ? ({5'd0, val_flt_type} + 7'd1)
                                       : 7'd0;
                    end

                    `PARAM_ID_OSCA_WAVE: begin
                        // Five sources: sine/saw/pulse/triangle/SD. Explicit wrap.
                        new_v = event_btn_tap_action==2'd2 ?
                            (val_osca_wave==0 ? 7'd4 : {4'd0,val_osca_wave}-7'd1) :
                            (val_osca_wave==4 ? 7'd0 : {4'd0,val_osca_wave}+7'd1);
                        val_osca_wave<=new_v[2:0];midi_cc_val<=new_v;
                    end
                    `PARAM_ID_OSCB_WAVE: begin
                        // Five sources: sine/saw/pulse/triangle/SD. Explicit wrap.
                        new_v = event_btn_tap_action==2'd2 ?
                            (val_oscb_wave==0 ? 7'd4 : {4'd0,val_oscb_wave}-7'd1) :
                            (val_oscb_wave==4 ? 7'd0 : {4'd0,val_oscb_wave}+7'd1);
                        val_oscb_wave<=new_v[2:0];midi_cc_val<=new_v;
                    end

                    `PARAM_ID_OSCA_OCT: begin
                        if (event_btn_tap_action == 2'd1 && val_osca_oct < 4'd8) begin
                            val_osca_oct <= val_osca_oct + 4'd1;
                            midi_cc_val  <= {3'd0, val_osca_oct + 4'd1};
                        end else if (event_btn_tap_action == 2'd2 && val_osca_oct > 4'd0) begin
                            val_osca_oct <= val_osca_oct - 4'd1;
                            midi_cc_val  <= {3'd0, val_osca_oct - 4'd1};
                        end else begin
                            midi_cc_val  <= {3'd0, val_osca_oct};
                        end
                    end
                    `PARAM_ID_OSCA_SEMI: begin
                        if (event_btn_tap_action == 2'd1 && val_osca_semi < 5'd24) begin
                            val_osca_semi <= val_osca_semi + 5'd1;
                            midi_cc_val   <= {2'd0, val_osca_semi + 5'd1};
                        end else if (event_btn_tap_action == 2'd2 && val_osca_semi > 5'd0) begin
                            val_osca_semi <= val_osca_semi - 5'd1;
                            midi_cc_val   <= {2'd0, val_osca_semi - 5'd1};
                        end else begin
                            midi_cc_val   <= {2'd0, val_osca_semi};
                        end
                    end
                    `PARAM_ID_OSCA_FINE: begin
                        if (event_btn_tap_action == 2'd1 && val_osca_fine < 7'd127) begin
                            val_osca_fine <= val_osca_fine + 7'd1;
                            midi_cc_val   <= val_osca_fine + 7'd1;
                        end else if (event_btn_tap_action == 2'd2 && val_osca_fine > 7'd0) begin
                            val_osca_fine <= val_osca_fine - 7'd1;
                            midi_cc_val   <= val_osca_fine - 7'd1;
                        end else begin
                            midi_cc_val   <= val_osca_fine;
                        end
                    end

                    `PARAM_ID_OSCB_OCT: begin
                        if (event_btn_tap_action == 2'd1 && val_oscb_oct < 4'd8) begin
                            val_oscb_oct <= val_oscb_oct + 4'd1;
                            midi_cc_val  <= {3'd0, val_oscb_oct + 4'd1};
                        end else if (event_btn_tap_action == 2'd2 && val_oscb_oct > 4'd0) begin
                            val_oscb_oct <= val_oscb_oct - 4'd1;
                            midi_cc_val  <= {3'd0, val_oscb_oct - 4'd1};
                        end else begin
                            midi_cc_val  <= {3'd0, val_oscb_oct};
                        end
                    end
                    `PARAM_ID_OSCB_SEMI: begin
                        if (event_btn_tap_action == 2'd1 && val_oscb_semi < 5'd24) begin
                            val_oscb_semi <= val_oscb_semi + 5'd1;
                            midi_cc_val   <= {2'd0, val_oscb_semi + 5'd1};
                        end else if (event_btn_tap_action == 2'd2 && val_oscb_semi > 5'd0) begin
                            val_oscb_semi <= val_oscb_semi - 5'd1;
                            midi_cc_val   <= {2'd0, val_oscb_semi - 5'd1};
                        end else begin
                            midi_cc_val   <= {2'd0, val_oscb_semi};
                        end
                    end
                    `PARAM_ID_OSCB_FINE: begin
                        if (event_btn_tap_action == 2'd1 && val_oscb_fine < 7'd127) begin
                            val_oscb_fine <= val_oscb_fine + 7'd1;
                            midi_cc_val   <= val_oscb_fine + 7'd1;
                        end else if (event_btn_tap_action == 2'd2 && val_oscb_fine > 7'd0) begin
                            val_oscb_fine <= val_oscb_fine - 7'd1;
                            midi_cc_val   <= val_oscb_fine - 7'd1;
                        end else begin
                            midi_cc_val   <= val_oscb_fine;
                        end
                    end

                    `PARAM_ID_FLT_ROUTE_A: begin
                        val_flt_route_a <= ~val_flt_route_a;
                        midi_cc_val     <= ~val_flt_route_a ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_FLT_ROUTE_B: begin
                        val_flt_route_b <= ~val_flt_route_b;
                        midi_cc_val     <= ~val_flt_route_b ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_FLT_ROUTE_N: begin
                        val_flt_route_n <= ~val_flt_route_n;
                        midi_cc_val     <= ~val_flt_route_n ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_FLT_ROUTE_S: begin
                        val_flt_route_s <= ~val_flt_route_s;
                        midi_cc_val     <= ~val_flt_route_s ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_FLT_KEYTRACK: begin
                        val_flt_keytrack <= ~val_flt_keytrack;
                        midi_cc_val      <= ~val_flt_keytrack ? 7'd127 : 7'd0;
                    end

                    `PARAM_ID_FLT_TYPE: begin
                        if (event_btn_tap_action == 2'd2) begin
                            val_flt_type <= val_flt_type - 2'd1;
                            midi_cc_val  <= val_flt_power
                                           ? ({5'd0, val_flt_type - 2'd1} + 7'd1)
                                           : 7'd0;
                        end else begin
                            val_flt_type <= val_flt_type + 2'd1;
                            midi_cc_val  <= val_flt_power
                                           ? ({5'd0, val_flt_type + 2'd1} + 7'd1)
                                           : 7'd0;
                        end
                    end

                    `PARAM_ID_ENV_TAB: begin
                        if(event_btn_tap_action<3) val_env_tab <= event_btn_tap_action;
                        midi_cc_val <= {5'd0, event_btn_tap_action};
                        midi_cc_req <= 0; // Local selection has no defined audio CC.
                    end

                    `PARAM_ID_SLOT1_BYPASS: begin
                        val_slot_bypass[0] <= ~val_slot_bypass[0];
                        midi_cc_val        <= ~val_slot_bypass[0] ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_SLOT2_BYPASS: begin
                        val_slot_bypass[1] <= ~val_slot_bypass[1];
                        midi_cc_val        <= ~val_slot_bypass[1] ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_SLOT3_BYPASS: begin
                        val_slot_bypass[2] <= ~val_slot_bypass[2];
                        midi_cc_val        <= ~val_slot_bypass[2] ? 7'd127 : 7'd0;
                    end
                    `PARAM_ID_SLOT4_BYPASS: begin
                        val_slot_bypass[3] <= ~val_slot_bypass[3];
                        midi_cc_val        <= ~val_slot_bypass[3] ? 7'd127 : 7'd0;
                    end

                    default: midi_cc_req <= 1'b0;
                endcase
            end

            // ------------------------------------------------------------------
            // 2. Process Absolute Update from Teammate 1 (SPI Knobs)
            // ------------------------------------------------------------------
            else if (event_spi_param_valid) begin
                midi_cc_req      <= 1'b1;
                midi_cc_param_id <= event_spi_param_id;
                midi_cc_val      <= event_spi_param_val;
                if((event_spi_param_id>=`PARAM_ID_ENV1_ATTACK && event_spi_param_id<=`PARAM_ID_ENV1_RELEASE) ||
                   (event_spi_param_id>=`PARAM_ID_ENV2_ATTACK && event_spi_param_id<=`PARAM_ID_ENV2_RELEASE))
                    midi_cc_req<=0;

                case (event_spi_param_id)
                    `PARAM_ID_MACRO1:       val_macro1       <= event_spi_param_val;
                    `PARAM_ID_MACRO2:       val_macro2       <= event_spi_param_val;
                    `PARAM_ID_MACRO3:       val_macro3       <= event_spi_param_val;
                    `PARAM_ID_MACRO4:       val_macro4       <= event_spi_param_val;
                    `PARAM_ID_MASTER_VOL:   val_master_vol   <= event_spi_param_val;

                    `PARAM_ID_OSCA_UNISON:  begin
                        val_osca_unison <= clamp_unison({3'b000, event_spi_param_val});
                        midi_cc_val     <= clamp_unison({3'b000, event_spi_param_val});
                    end
                    `PARAM_ID_OSCA_DETUNE:  val_osca_detune  <= event_spi_param_val;
                    `PARAM_ID_OSCA_FINE:    val_osca_fine    <= event_spi_param_val;
                    `PARAM_ID_OSCA_BLEND:   val_osca_blend   <= event_spi_param_val;
                    `PARAM_ID_OSCA_PHASE:   val_osca_phase   <= event_spi_param_val;
                    `PARAM_ID_OSCA_RAND:    val_osca_rand    <= event_spi_param_val;
                    `PARAM_ID_OSCA_WT_POS:  val_osca_wt_pos  <= event_spi_param_val;
                    `PARAM_ID_OSCA_WARP:    val_osca_warp    <= event_spi_param_val;
                    `PARAM_ID_OSCA_PAN:     val_osca_pan     <= event_spi_param_val;
                    `PARAM_ID_OSCA_VOL:     val_osca_vol     <= event_spi_param_val;

                    `PARAM_ID_OSCB_UNISON:  begin
                        val_oscb_unison <= clamp_unison({3'b000, event_spi_param_val});
                        midi_cc_val     <= clamp_unison({3'b000, event_spi_param_val});
                    end
                    `PARAM_ID_OSCB_DETUNE:  val_oscb_detune  <= event_spi_param_val;
                    `PARAM_ID_OSCB_FINE:    val_oscb_fine    <= event_spi_param_val;
                    `PARAM_ID_OSCB_BLEND:   val_oscb_blend   <= event_spi_param_val;
                    `PARAM_ID_OSCB_PHASE:   val_oscb_phase   <= event_spi_param_val;
                    `PARAM_ID_OSCB_RAND:    val_oscb_rand    <= event_spi_param_val;
                    `PARAM_ID_OSCB_WT_POS:  val_oscb_wt_pos  <= event_spi_param_val;
                    `PARAM_ID_OSCB_WARP:    val_oscb_warp    <= event_spi_param_val;
                    `PARAM_ID_OSCB_PAN:     val_oscb_pan     <= event_spi_param_val;
                    `PARAM_ID_OSCB_VOL:     val_oscb_vol     <= event_spi_param_val;

                    `PARAM_ID_FLT_CUTOFF:   val_flt_cutoff   <= event_spi_param_val;
                    `PARAM_ID_FLT_RES:      val_flt_res      <= event_spi_param_val;
                    `PARAM_ID_FLT_PAN:      val_flt_pan      <= event_spi_param_val;
                    `PARAM_ID_FLT_DRIVE:    val_flt_drive    <= event_spi_param_val;
                    `PARAM_ID_FLT_FAT:      val_flt_fat      <= event_spi_param_val;
                    `PARAM_ID_FLT_MIX:      val_flt_mix      <= event_spi_param_val;

                    `PARAM_ID_ENV1_ATTACK, `PARAM_ID_ENV2_ATTACK: begin
                        env_a[event_spi_env_tab]<=event_spi_param_val;
                        if(event_spi_env_tab==0) curve_midi_pending[2]<=1;
                        else if(event_spi_env_tab==1) curve_midi_pending[7]<=1;
                    end
                    `PARAM_ID_ENV1_HOLD, `PARAM_ID_ENV2_HOLD: begin
                        env_h[event_spi_env_tab]<=event_spi_param_val;
                    end
                    `PARAM_ID_ENV1_DECAY, `PARAM_ID_ENV2_DECAY: begin
                        env_d[event_spi_env_tab]<=event_spi_param_val;
                        if(event_spi_env_tab==0) curve_midi_pending[4]<=1;
                        else if(event_spi_env_tab==1) curve_midi_pending[8]<=1;
                    end
                    `PARAM_ID_ENV1_SUSTAIN, `PARAM_ID_ENV2_SUSTAIN: begin
                        env_s[event_spi_env_tab]<=event_spi_param_val;
                        if(event_spi_env_tab==0) curve_midi_pending[5]<=1;
                        else if(event_spi_env_tab==1) curve_midi_pending[9]<=1;
                    end
                    `PARAM_ID_ENV1_RELEASE, `PARAM_ID_ENV2_RELEASE: begin
                        env_r[event_spi_env_tab]<=event_spi_param_val;
                        if(event_spi_env_tab==0) curve_midi_pending[6]<=1;
                        else if(event_spi_env_tab==1) curve_midi_pending[10]<=1;
                    end

                    `PARAM_ID_FX_REVERB:    val_fx_reverb    <= event_spi_param_val;
                    `PARAM_ID_FX_DELAY:     val_fx_delay     <= event_spi_param_val;
                    `PARAM_ID_FX_CHORUS:    val_fx_chorus    <= event_spi_param_val;
                    `PARAM_ID_PORTAMENTO:   val_portamento   <= event_spi_param_val;

                    default: midi_cc_req <= 1'b0;
                endcase
            end

            // ------------------------------------------------------------------
            // 3. Commit an absolute curve transaction atomically.
            // The captured bank is independent of subsequent page switches.
            // ENV1/2 coalesce into separate audio queues; ENV3 stays local.
            // ------------------------------------------------------------------
            else if(curve_pending) begin
                curve_pending<=event_curve_update_valid;
                if(curve_filter) begin
                    if(curve_mask[0] && val_flt_cutoff!=curve_values[6:0]) begin
                        val_flt_cutoff<=curve_values[6:0];curve_midi_pending[0]<=1;
                    end
                    if(curve_mask[1] && val_flt_res!=curve_values[13:7]) begin
                        val_flt_res<=curve_values[13:7];curve_midi_pending[1]<=1;
                    end
                end else if(curve_tab<3) begin
                    if(curve_mask[0] && env_a[curve_tab]!=curve_values[6:0]) begin
                        env_a[curve_tab]<=curve_values[6:0];
                        if(curve_tab==0) curve_midi_pending[2]<=1;
                        else if(curve_tab==1) curve_midi_pending[7]<=1;
                    end
                    if(curve_mask[1] && env_h[curve_tab]!=curve_values[13:7]) begin
                        env_h[curve_tab]<=curve_values[13:7];
                    end
                    if(curve_mask[2] && env_d[curve_tab]!=curve_values[20:14]) begin
                        env_d[curve_tab]<=curve_values[20:14];
                        if(curve_tab==0) curve_midi_pending[4]<=1;
                        else if(curve_tab==1) curve_midi_pending[8]<=1;
                    end
                    if(curve_mask[3] && env_s[curve_tab]!=curve_values[27:21]) begin
                        env_s[curve_tab]<=curve_values[27:21];
                        if(curve_tab==0) curve_midi_pending[5]<=1;
                        else if(curve_tab==1) curve_midi_pending[9]<=1;
                    end
                    if(curve_mask[4] && env_r[curve_tab]!=curve_values[34:28]) begin
                        env_r[curve_tab]<=curve_values[34:28];
                        if(curve_tab==0) curve_midi_pending[6]<=1;
                        else if(curve_tab==1) curve_midi_pending[10]<=1;
                    end
                end
            end

            // ------------------------------------------------------------------
            // 4. Process Incremental Delta from Screen Touch Drag (All 32 Knobs)
            // ------------------------------------------------------------------
            else if (event_touch_delta_valid && (event_touch_selected_id != `PARAM_ID_NONE)) begin
                midi_cc_req      <= 1'b1;
                midi_cc_param_id <= event_touch_selected_id;
                if((event_touch_selected_id>=`PARAM_ID_ENV1_ATTACK && event_touch_selected_id<=`PARAM_ID_ENV1_RELEASE) ||
                   (event_touch_selected_id>=`PARAM_ID_ENV2_ATTACK && event_touch_selected_id<=`PARAM_ID_ENV2_RELEASE))
                    midi_cc_req<=0;

                case (event_touch_selected_id)
                    // Top Deck
                    `PARAM_ID_MACRO1: begin
                        new_v = clamp7($signed({3'b000, val_macro1}) + event_touch_delta_val);
                        val_macro1 <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_MACRO2: begin
                        new_v = clamp7($signed({3'b000, val_macro2}) + event_touch_delta_val);
                        val_macro2 <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_MACRO3: begin
                        new_v = clamp7($signed({3'b000, val_macro3}) + event_touch_delta_val);
                        val_macro3 <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_MACRO4: begin
                        new_v = clamp7($signed({3'b000, val_macro4}) + event_touch_delta_val);
                        val_macro4 <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_MASTER_VOL: begin
                        new_v = clamp7($signed({3'b000, val_master_vol}) + event_touch_delta_val);
                        val_master_vol <= new_v; midi_cc_val <= new_v;
                    end

                    // OSC A
                    `PARAM_ID_OSCA_UNISON: begin
                        new_v = clamp_unison($signed({3'b000, val_osca_unison}) + event_touch_delta_val);
                        val_osca_unison <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_DETUNE: begin
                        new_v = clamp7($signed({3'b000, val_osca_detune}) + event_touch_delta_val);
                        val_osca_detune <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_FINE: begin
                        new_v = clamp7($signed({3'b000, val_osca_fine}) + event_touch_delta_val);
                        val_osca_fine <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_BLEND: begin
                        new_v = clamp7($signed({3'b000, val_osca_blend}) + event_touch_delta_val);
                        val_osca_blend <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_PHASE: begin
                        new_v = clamp7($signed({3'b000, val_osca_phase}) + event_touch_delta_val);
                        val_osca_phase <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_RAND: begin
                        new_v = clamp7($signed({3'b000, val_osca_rand}) + event_touch_delta_val);
                        val_osca_rand <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_WT_POS: begin
                        new_v = clamp7($signed({3'b000, val_osca_wt_pos}) + event_touch_delta_val);
                        val_osca_wt_pos <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_WARP: begin
                        new_v = clamp7($signed({3'b000, val_osca_warp}) + event_touch_delta_val);
                        val_osca_warp <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_PAN: begin
                        new_v = clamp7($signed({3'b000, val_osca_pan}) + event_touch_delta_val);
                        val_osca_pan <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCA_VOL: begin
                        new_v = clamp7($signed({3'b000, val_osca_vol}) + event_touch_delta_val);
                        val_osca_vol <= new_v; midi_cc_val <= new_v;
                    end

                    // OSC B
                    `PARAM_ID_OSCB_UNISON: begin
                        new_v = clamp_unison($signed({3'b000, val_oscb_unison}) + event_touch_delta_val);
                        val_oscb_unison <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_DETUNE: begin
                        new_v = clamp7($signed({3'b000, val_oscb_detune}) + event_touch_delta_val);
                        val_oscb_detune <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_FINE: begin
                        new_v = clamp7($signed({3'b000, val_oscb_fine}) + event_touch_delta_val);
                        val_oscb_fine <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_BLEND: begin
                        new_v = clamp7($signed({3'b000, val_oscb_blend}) + event_touch_delta_val);
                        val_oscb_blend <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_PHASE: begin
                        new_v = clamp7($signed({3'b000, val_oscb_phase}) + event_touch_delta_val);
                        val_oscb_phase <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_RAND: begin
                        new_v = clamp7($signed({3'b000, val_oscb_rand}) + event_touch_delta_val);
                        val_oscb_rand <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_WT_POS: begin
                        new_v = clamp7($signed({3'b000, val_oscb_wt_pos}) + event_touch_delta_val);
                        val_oscb_wt_pos <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_WARP: begin
                        new_v = clamp7($signed({3'b000, val_oscb_warp}) + event_touch_delta_val);
                        val_oscb_warp <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_PAN: begin
                        new_v = clamp7($signed({3'b000, val_oscb_pan}) + event_touch_delta_val);
                        val_oscb_pan <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_OSCB_VOL: begin
                        new_v = clamp7($signed({3'b000, val_oscb_vol}) + event_touch_delta_val);
                        val_oscb_vol <= new_v; midi_cc_val <= new_v;
                    end

                    // Filter
                    `PARAM_ID_FLT_CUTOFF: begin
                        new_v = clamp7($signed({3'b000, val_flt_cutoff}) + event_touch_delta_val);
                        val_flt_cutoff <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FLT_RES: begin
                        new_v = clamp7($signed({3'b000, val_flt_res}) + event_touch_delta_val);
                        val_flt_res <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FLT_PAN: begin
                        new_v = clamp7($signed({3'b000, val_flt_pan}) + event_touch_delta_val);
                        val_flt_pan <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FLT_DRIVE: begin
                        new_v = clamp7($signed({3'b000, val_flt_drive}) + event_touch_delta_val);
                        val_flt_drive <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FLT_FAT: begin
                        new_v = clamp7($signed({3'b000, val_flt_fat}) + event_touch_delta_val);
                        val_flt_fat <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FLT_MIX: begin
                        new_v = clamp7($signed({3'b000, val_flt_mix}) + event_touch_delta_val);
                        val_flt_mix <= new_v; midi_cc_val <= new_v;
                    end

                    // Envelope 1
                    `PARAM_ID_ENV1_ATTACK, `PARAM_ID_ENV2_ATTACK: begin
                        new_v = clamp7($signed({3'b000, env_a[event_touch_env_tab]}) + event_touch_delta_val);
                        env_a[event_touch_env_tab] <= new_v;
                        midi_cc_req<=0;
                        if(event_touch_env_tab==0) curve_midi_pending[2]<=1;
                        else if(event_touch_env_tab==1) curve_midi_pending[7]<=1;
                    end
                    `PARAM_ID_ENV1_HOLD, `PARAM_ID_ENV2_HOLD: begin
                        new_v = clamp7($signed({3'b000, env_h[event_touch_env_tab]}) + event_touch_delta_val);
                        env_h[event_touch_env_tab] <= new_v;
                        midi_cc_req<=0;

                    end
                    `PARAM_ID_ENV1_DECAY, `PARAM_ID_ENV2_DECAY: begin
                        new_v = clamp7($signed({3'b000, env_d[event_touch_env_tab]}) + event_touch_delta_val);
                        env_d[event_touch_env_tab] <= new_v;
                        midi_cc_req<=0;
                        if(event_touch_env_tab==0) curve_midi_pending[4]<=1;
                        else if(event_touch_env_tab==1) curve_midi_pending[8]<=1;
                    end
                    `PARAM_ID_ENV1_SUSTAIN, `PARAM_ID_ENV2_SUSTAIN: begin
                        new_v = clamp7($signed({3'b000, env_s[event_touch_env_tab]}) + event_touch_delta_val);
                        env_s[event_touch_env_tab] <= new_v;
                        midi_cc_req<=0;
                        if(event_touch_env_tab==0) curve_midi_pending[5]<=1;
                        else if(event_touch_env_tab==1) curve_midi_pending[9]<=1;
                    end
                    `PARAM_ID_ENV1_RELEASE, `PARAM_ID_ENV2_RELEASE: begin
                        new_v = clamp7($signed({3'b000, env_r[event_touch_env_tab]}) + event_touch_delta_val);
                        env_r[event_touch_env_tab] <= new_v;
                        midi_cc_req<=0;
                        if(event_touch_env_tab==0) curve_midi_pending[6]<=1;
                        else if(event_touch_env_tab==1) curve_midi_pending[10]<=1;
                    end

                    // Master FX
                    `PARAM_ID_FX_REVERB: begin
                        new_v = clamp7($signed({3'b000, val_fx_reverb}) + event_touch_delta_val);
                        val_fx_reverb <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FX_DELAY: begin
                        new_v = clamp7($signed({3'b000, val_fx_delay}) + event_touch_delta_val);
                        val_fx_delay <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_FX_CHORUS: begin
                        new_v = clamp7($signed({3'b000, val_fx_chorus}) + event_touch_delta_val);
                        val_fx_chorus <= new_v; midi_cc_val <= new_v;
                    end
                    `PARAM_ID_PORTAMENTO: begin
                        new_v = clamp7($signed({3'b000, val_portamento}) + event_touch_delta_val);
                        val_portamento <= new_v; midi_cc_val <= new_v;
                    end

                    default: midi_cc_req <= 1'b0;
                endcase
            end
            // One queued curve CC at a time, with a registered push guard.
            else if(!midi_tx_busy && !midi_cc_req) begin
                if(curve_midi_pending[0]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_FLT_CUTOFF;
                    midi_cc_val<=val_flt_cutoff;curve_midi_pending[0]<=0;
                end else if(curve_midi_pending[1]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_FLT_RES;
                    midi_cc_val<=val_flt_res;curve_midi_pending[1]<=0;
                end else if(curve_midi_pending[2]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV1_ATTACK;
                    midi_cc_val<=env_a[0];curve_midi_pending[2]<=0;
                end else if(curve_midi_pending[3]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV1_HOLD;
                    midi_cc_val<=env_h[0];curve_midi_pending[3]<=0;
                end else if(curve_midi_pending[4]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV1_DECAY;
                    midi_cc_val<=env_d[0];curve_midi_pending[4]<=0;
                end else if(curve_midi_pending[5]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV1_SUSTAIN;
                    midi_cc_val<=env_s[0];curve_midi_pending[5]<=0;
                end else if(curve_midi_pending[6]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV1_RELEASE;
                    midi_cc_val<=env_r[0];curve_midi_pending[6]<=0;
                end else if(curve_midi_pending[7]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV2_ATTACK;
                    midi_cc_val<=env_a[1];curve_midi_pending[7]<=0;
                end else if(curve_midi_pending[8]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV2_DECAY;
                    midi_cc_val<=env_d[1];curve_midi_pending[8]<=0;
                end else if(curve_midi_pending[9]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV2_SUSTAIN;
                    midi_cc_val<=env_s[1];curve_midi_pending[9]<=0;
                end else if(curve_midi_pending[10]) begin
                    midi_cc_req<=1;midi_cc_param_id<=`PARAM_ID_ENV2_RELEASE;
                    midi_cc_val<=env_r[1];curve_midi_pending[10]<=0;
                end
            end
        end
    end

endmodule
