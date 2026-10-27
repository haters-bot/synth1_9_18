`include "params.vh"
// ==============================================================================
// Module: ui_touch_hub_top.v
// Description: Master Top-Level for Teammate 2 (UI Touch Hub)
//              Sipeed Tang Mega 138K Dock (GW5AST-LV138PG484AC1/I0)
// Features:
//   1. 100% Procedural Vector UI (1280x720@50.5Hz/60Hz HDMI Native)
//      - Zero ROM Bitmaps, Zero BSRAM bloat, Zero color quantization noise
//      - Dynamic 2D Wavetables (OSC A & B) deforming with WT POS
//      - Dynamic Filter resonance curve with Q hump and cutoff roll-off
//      - Dynamic ADSR envelope curve with drag handles and time markers
//      - 30 rotary knobs with metallic bezels, 270-deg arc gauges, glowing needles
//      - 24-key full piano keyboard with instantaneous touch glow feedback
//   2. Screen Touch Intake (USB/UART 0x5454 packet parser with 10ms watchdog)
//   3. Teammate 1 Physical Knobs SPI Interface with digital hysteresis
//   4. Parameter Merger coordinating touch & hardware knobs
//   5. Teammate 3 Audio Engine UART MIDI Protocol Transmitter (Ch1 Notes, Ch16 CC)
// ==============================================================================

module ui_touch_hub_top #(
    parameter DEBUG_TOUCH_LOG=0,
    parameter DEBUG_KNOB_ASCII=1
)(
    input  wire        clk,             // 板载 50MHz 有源晶振 (V22)
    input  wire        rst_n,           // 板载复位按键 S2 (AA13, 低有效)

    // 板载 USB-A Host 接口 (J18, 直连便携屏 USB 触控线)
    inout  wire        usb_dp,          // M15: USB-A J18 D+ (Host Port 1)
    inout  wire        usb_dm,          // M16: USB-A J18 D- (Host Port 1)

    // 便携屏触控串口/USB 桥接输入
    input  wire        touch_uart_rx,     // V14 (LVCMOS33)
    input  wire        touch_uart_rx_y14, // Y14 (LVCMOS33, 辅助/备用触控串口)

    // 板载 CH569 USB Host MCU 触控接口 (连接便携屏 USB 触控线)
    input  wire        ch569_htclk,       // L20: CH569 HSPI 时钟
    input  wire        ch569_htreq,       // N20: CH569 HSPI 请求
    input  wire        ch569_htvld,       // L15: CH569 HSPI 数据有效
    output wire        ch569_htrdy,       // J22: CH569 HSPI 接收就绪
    input  wire [15:0] hspi_hd,           // G17..L16: CH569 HSPI 16位并行数据

    // 队友 1 (硬件面板组) 双 TXE8148 / 32 个 EC11 接口
    output wire        knob_2cs_n,
    output wire        knob_1cs_n,
    output wire        knob_sclk,
    output wire        knob_sdi,
    input  wire        knob_sdo,
    input  wire        knob_int_n,
    output wire        knob_reset_n,

    // U15: board USB-UART monitor output (normal MIDI or diagnostic trace).
    output wire        midi_uart_tx,
    // PMOD1 IO2/AB21: dedicated 3.3V UART TX to audio-board J8 pin 9.
    output wire        audio_link_tx,

    // Audio-board I2S visualization return (audio board VIS_* pins).
    // UI board inputs: R19=BCLK, U21=LRC, R17=DIN.
    input  wire        audio_vis_bclk,
    input  wire        audio_vis_lrc,
    input  wire        audio_vis_din,

    // External debug UART on the user header: C14=TX, E13=RX (3.3V TTL).
    // TX reports knob/link events at 115200 8N1; RX is reserved for commands.
    output wire        debug_uart_tx,
    input  wire        debug_uart_rx,

    // 板载状态指示灯
    output wire [1:0]  led,             // T18: PLL Lock, R18: Heartbeat

    // 板载标准 HDMI Type-A 接口 (J29, GW5AST-138B Bank 3.3V)
    output wire        tmds_clk_p_0,    // G15 (P), G16 (N)
    output wire        tmds_clk_n_0,
    output wire [2:0]  tmds_d_p_0,      // D0: J14/H14, D1: J15/H15, D2: K17/J17
    output wire [2:0]  tmds_d_n_0
);

    // --------------------------------------------------------------------------
    // 1. PLL 时钟生成 (50MHz 像素时钟 + 250MHz 5倍位时钟)
    // --------------------------------------------------------------------------
    wire clk_pixel;
    wire clk_5x_bit;
    wire pll_lock;

    Gowin_PLL u_pll (
        .lock    (pll_lock),
        .clkout0 (clk_pixel),
        .clkout1 (clk_5x_bit),
        .clkin   (clk)
    );

    // 1b. USB Host 60MHz PLL (50MHz -> 60MHz)
    wire clk_usb;
    wire pll_usb_lock;

    Gowin_PLL_USB u_pll_usb (
        .lock    (pll_usb_lock),
        .clkout0 (clk_usb),
        .clkin   (clk)
    );

    // 异步复位同步释放
    wire sys_rst_n_sync;
    Reset_Sync u_rst_sync (
        .clk       (clk_pixel),
        .ext_reset (rst_n & pll_lock & pll_usb_lock),
        .resetn    (sys_rst_n_sync)
    );

    // --------------------------------------------------------------------------
    // 2. 标准 720p (1280x720@50.5Hz) CEA 视频时序生成
    // --------------------------------------------------------------------------
    wire        raw_vsync;
    wire        raw_hsync;
    wire        raw_den;
    wire [13:0] pixel_x;
    wire [13:0] pixel_y;

    video_timing_ctrl #(
        .video_hlength   (1650),
        .video_vlength   (750),
        .video_hsync_pol (1),
        .video_hsync_len (40),
        .video_hbp_len   (220),
        .video_h_visible (1280),
        .video_vsync_pol (1),
        .video_vsync_len (5),
        .video_vbp_len   (20),
        .video_v_visible (720)
    ) u_timing (
        .pixel_clock     (clk_pixel),
        .reset           (~sys_rst_n_sync),
        .ext_sync        (1'b0),
        .timing_h_pos    (),
        .timing_v_pos    (),
        .pixel_x         (pixel_x),
        .pixel_y         (pixel_y),
        .video_vsync     (raw_vsync),
        .video_hsync     (raw_hsync),
        .video_den       (raw_den),
        .video_line_start()
    );

    // --------------------------------------------------------------------------
    // 3. 屏幕触控数据流接收与碰撞判决 (Touch Intake)
    // --------------------------------------------------------------------------
    wire        touch_valid;
    wire [15:0] touch_x, touch_y;
    wire        touch_state;

    wire active_touch_rx = touch_uart_rx & touch_uart_rx_y14;

    uart_touch_rx #(
        .CLK_FREQ (50000000),
        .BAUD     (115200)
    ) u_touch_rx (
        .clk         (clk_pixel),
        .rst_n       (sys_rst_n_sync),
        .uart_rx     (active_touch_rx),
        .touch_valid (touch_valid),
        .touch_x     (touch_x),
        .touch_y     (touch_y),
        .touch_state (touch_state)
    );

    wire        hspi_touch_valid;
    wire [15:0] hspi_touch_x, hspi_touch_y;
    wire        hspi_touch_state;

    hspi_touch_rx u_hspi_rx (
        .hspi_clk    (ch569_htclk),
        .rst_n       (rst_n),
        .hspi_req    (ch569_htreq),
        .hspi_vld    (ch569_htvld),
        .hspi_data   (hspi_hd),
        .hspi_rdy    (ch569_htrdy),
        .pixel_clk   (clk_pixel),
        .pixel_rst_n (sys_rst_n_sync),
        .touch_valid (hspi_touch_valid),
        .touch_x     (hspi_touch_x),
        .touch_y     (hspi_touch_y),
        .touch_state (hspi_touch_state)
    );

    // 板载 USB-A Host 接口触控接收引擎 (直连便携屏 USB 触控线, J18 M15/M16)
    wire        usb_touch_valid;
    wire [15:0] usb_touch_x;
    wire [15:0] usb_touch_y;
    wire        usb_touch_state;
    wire        usb_connected;
    wire [1:0]  usb_dev_type;
    wire        usb_conn_err;
    wire        touch_activity;
    wire [63:0] usb_dbg_report;
    wire [63:0] usb_dbg_regs;
    wire [7:0]  usb_dbg_pkt_cnt;

    usb_touch_intake u_usb_touch_intake (
        .clk_usb        (clk_usb),
        .rst_usb_n      (rst_n & pll_usb_lock),
        .usb_dp         (usb_dp),
        .usb_dm         (usb_dm),
        .clk_pixel      (clk_pixel),
        .pixel_rst_n    (sys_rst_n_sync),
        .touch_valid    (usb_touch_valid),
        .touch_x        (usb_touch_x),
        .touch_y        (usb_touch_y),
        .touch_state    (usb_touch_state),
        .usb_connected  (usb_connected),
        .usb_dev_type   (usb_dev_type),
        .usb_conn_err   (usb_conn_err),
        .touch_activity (touch_activity),
        .dbg_report     (usb_dbg_report),
        .dbg_regs       (usb_dbg_regs),
        .dbg_pkt_cnt    (usb_dbg_pkt_cnt)
    );

    // Merge Touch Streams (Triple-Intake: Board USB-A Host J18 + CH569 HSPI + Debug UART)
    reg        latched_touch_state;
    reg [15:0] latched_touch_x;
    reg [15:0] latched_touch_y;

    always @(posedge clk_pixel or negedge sys_rst_n_sync) begin
        if (!sys_rst_n_sync) begin
            latched_touch_state <= 1'b0;
            latched_touch_x     <= 16'd0;
            latched_touch_y     <= 16'd0;
        end else if (usb_touch_valid) begin
            latched_touch_state <= usb_touch_state;
            latched_touch_x     <= usb_touch_x;
            latched_touch_y     <= usb_touch_y;
        end else if (hspi_touch_valid) begin
            latched_touch_state <= hspi_touch_state;
            latched_touch_x     <= hspi_touch_x;
            latched_touch_y     <= hspi_touch_y;
        end else if (touch_valid) begin
            latched_touch_state <= touch_state;
            latched_touch_x     <= touch_x;
            latched_touch_y     <= touch_y;
        end
    end

    wire        merged_touch_valid = usb_touch_valid | hspi_touch_valid | touch_valid;
    wire [15:0] merged_touch_x     = usb_touch_valid  ? usb_touch_x :
                                     hspi_touch_valid ? hspi_touch_x :
                                     touch_valid      ? touch_x : latched_touch_x;
    wire [15:0] merged_touch_y     = usb_touch_valid  ? usb_touch_y :
                                     hspi_touch_valid ? hspi_touch_y :
                                     touch_valid      ? touch_y : latched_touch_y;
    wire        merged_touch_state = usb_touch_valid  ? usb_touch_state :
                                     hspi_touch_valid ? hspi_touch_state :
                                     touch_valid      ? touch_state : latched_touch_state;

    wire [7:0]  selected_param_id;
    wire        selected_valid;
    wire        touch_delta_valid;
    wire signed [7:0] touch_delta_val;
    wire        btn_tap_valid;
    wire [7:0]  btn_tap_id;
    wire [1:0]  btn_tap_action;

    wire [63:0] touch_diag_coords;
    wire [15:0] touch_diag_count;
    wire touch_diag_mode;
    wire binding_capture;
    wire fx_event_valid,route_event_valid;
    wire [7:0] fx_event_id,route_event_target;
    wire [6:0] fx_event_value;
    wire [132:0] fx_parameter_snapshot;
    wire fx_touch_focus_valid;
    wire [7:0] fx_touch_focus_id;
    wire [1:0] route_event_source;
    wire signed [7:0] route_event_depth;
    // LFO Protocol V2 snapshots and SysEx injection (lfo_sysex_tx <-> midi_uart_tx)
    wire [146:0] lfo_node_snapshot;
    wire [8:0]   lfo_rate_snapshot;
    wire [2:0]   lfo_step_snapshot, lfo_once_snapshot;
    wire [105:0] route_source_snapshot;
    wire [423:0] route_depth_snapshot;
    wire        sysex_req;
    wire [47:0] sysex_msgs;
    wire        sysex_accept;
    wire ui_touch_valid, ui_touch_down;
    wire [13:0] ui_touch_x, ui_touch_y;
    wire curve_capture,curve_focus_valid;
    wire [7:0] curve_focus_id;
    wire curve_update_valid,curve_update_filter;
    wire [1:0] curve_update_tab;
    wire [4:0] curve_update_mask;
    wire [34:0] curve_update_values;
    wire [34:0] display_env_values;
    wire navigation_capture,navigation_delta_valid;
    wire [7:0] navigation_delta_id;
    wire signed [7:0] navigation_delta_value;
    wire midi_tx_busy;
    touch_event_router u_touch_router (
        .curve_capture_active(curve_capture | binding_capture | navigation_capture),.curve_focus_valid(curve_focus_valid),.curve_focus_id(curve_focus_id),
        .ui_touch_valid(ui_touch_valid), .ui_touch_down(ui_touch_down),
        .ui_touch_x(ui_touch_x), .ui_touch_y(ui_touch_y),
        .diag_contact_coords (touch_diag_coords),
        .diag_contact_count  (touch_diag_count),
        .diag_mode_64k       (touch_diag_mode),
        .clk                  (clk_pixel),
        .rst_n                (sys_rst_n_sync),
        .touch_valid          (merged_touch_valid),
        .raw_touch_x          (merged_touch_x),
        .raw_touch_y          (merged_touch_y),
        .touch_state          (merged_touch_state),
        .selected_param_id    (selected_param_id),
        .selected_valid       (selected_valid),
        .param_delta_valid    (touch_delta_valid),
        .param_delta_val      (touch_delta_val),
        .btn_tap_valid        (btn_tap_valid),
        .btn_tap_id           (btn_tap_id),
        .btn_tap_action       (btn_tap_action),
        .touch_key_white_mask (),
        .touch_key_black_mask (),
        .touch_note_on        (),
        .touch_note_off       (),
        .touch_note_number    ()
    );

    // --------------------------------------------------------------------------
    // 4. 队友 1 物理旋钮 SPI 接收引擎 (Knob SPI Intake)
    // --------------------------------------------------------------------------
    wire        spi_param_valid;
    wire [7:0]  spi_param_id;
    wire [6:0]  spi_param_val;
    wire        spi_param_cw;
    wire        spi_link_valid;
    wire        spi_link_chip;
    wire        spi_link_up;

    wire        knob_select_valid;
    wire [7:0]  knob_select_id;
    wire [1:0]  knob_select_action;

    knob_spi_rx #(
        .CLK_HZ(50000000), .SPI_HZ(1000000), .RESET_HOLD_CYCLES(100000),
        .SWITCH_DEBOUNCE_SCANS(5)
    ) u_knob_spi (
        .clk          (clk_pixel),
        .rst_n        (sys_rst_n_sync),
        .spi_sdo      (knob_sdo),
        .spi_int_n    (knob_int_n),
        .spi_2cs_n    (knob_2cs_n),
        .spi_1cs_n    (knob_1cs_n),
        .spi_sclk     (knob_sclk),
        .spi_sdi      (knob_sdi),
        .panel_reset_n(knob_reset_n),
        .param_valid  (spi_param_valid),
        .param_id     (spi_param_id),
        .param_val    (spi_param_val),
        .param_cw     (spi_param_cw),
        .select_valid (knob_select_valid),
        .select_id    (knob_select_id),
        .select_action(knob_select_action),
        .spi_link_valid(spi_link_valid),
        .spi_link_chip(spi_link_chip),
        .spi_link_up(spi_link_up)
    );

    wire [63:0] user_knob_steps;
    wire signed [7:0] physical_delta;
    wire [7:0] display_focus_id;
    knob_ui_control u_knob_control(.clk(clk_pixel),.rst_n(sys_rst_n_sync),
        .motion_valid(spi_param_valid),.motion_cw(spi_param_cw),.motion_id(spi_param_id),
        .button_valid(knob_select_valid),.button_id(knob_select_id),.button_action(knob_select_action),
        .fx_touch_focus_valid(fx_touch_focus_valid),.fx_touch_focus_id(fx_touch_focus_id),
        .touch_focus_valid(selected_valid && !navigation_capture && !binding_capture),.touch_focus_id(selected_param_id),.touch_down(ui_touch_down),
        .steps(user_knob_steps),.delta(physical_delta),.focus_id(display_focus_id));

    // --------------------------------------------------------------------------
    // 5. 参数合并中枢 (Param Merger)
    // --------------------------------------------------------------------------
    wire [6:0]  val_macro1, val_macro2, val_macro3, val_macro4, val_master_vol;
    wire [6:0]  val_osca_unison, val_osca_detune, val_osca_blend, val_osca_phase, val_osca_rand;
    wire [6:0]  val_osca_wt_pos, val_osca_warp, val_osca_pan, val_osca_vol;
    wire [6:0]  val_oscb_unison, val_oscb_detune, val_oscb_blend, val_oscb_phase, val_oscb_rand;
    wire [6:0]  val_oscb_wt_pos, val_oscb_warp, val_oscb_pan, val_oscb_vol;
    wire [6:0]  val_flt_cutoff, val_flt_res, val_flt_pan, val_flt_drive, val_flt_fat, val_flt_mix;
    wire [6:0]  val_env_attack, val_env_hold, val_env_decay, val_env_sustain, val_env_release;
    wire [6:0]  val_fx_reverb, val_fx_delay, val_fx_chorus, val_portamento;

    wire        val_osca_power, val_oscb_power, val_flt_power;
    wire [1:0]  val_osca_wave, val_oscb_wave;
    wire [3:0]  val_osca_oct, val_oscb_oct;
    wire [4:0]  val_osca_semi, val_oscb_semi;
    wire [6:0]  val_osca_fine, val_oscb_fine;
    wire [1:0]  val_flt_type;
    wire        val_flt_route_a, val_flt_route_b, val_flt_route_n, val_flt_route_s, val_flt_keytrack;
    wire [1:0]  val_env_tab;
    wire [3:0]  val_slot_bypass;
    wire [7:0]  active_btn_id;
    wire        btn_flash_active;

    wire        midi_cc_req;
    wire [7:0]  midi_cc_param_id;
    wire [6:0]  midi_cc_val;

    // A physical detent applies its configured step to the shared static bank.
    wire physical_fx = spi_param_id==`PARAM_ID_FX_REVERB || spi_param_id==`PARAM_ID_FX_DELAY;
    wire [7:0] physical_fx_id = spi_param_id==`PARAM_ID_FX_REVERB ? 8'h66 : 8'h60;
    wire [6:0] physical_fx_base = spi_param_id==`PARAM_ID_FX_REVERB ? fx_parameter_snapshot[42+:7] : fx_parameter_snapshot[0+:7];
    wire signed [8:0] physical_fx_sum = $signed({2'b0,physical_fx_base}) + $signed(physical_delta);
    wire [6:0] physical_fx_value = physical_fx_sum<0 ? 7'd0 : physical_fx_sum>127 ? 7'd127 : physical_fx_sum[6:0];
    // Other controls use the existing merger
    // used by touch. Preserve existing navigation/touch priority on collisions.
    wire        merged_delta_valid = navigation_delta_valid | touch_delta_valid | (spi_param_valid && !physical_fx);
    wire [7:0]  merged_delta_id = navigation_delta_valid ? navigation_delta_id :
                                  touch_delta_valid ? selected_param_id : spi_param_id;
    wire signed [7:0] merged_delta_value = navigation_delta_valid ? navigation_delta_value :
                                           touch_delta_valid ? touch_delta_val :
                                           physical_delta;

    curve_touch_editor #(.USE_DISPLAY_GEOMETRY(1)) u_curve_editor (
        .clk(clk_pixel),.rst_n(sys_rst_n_sync),
        .touch_valid(ui_touch_valid),.touch_down(ui_touch_down && !binding_capture && !navigation_capture),.touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .cutoff(val_flt_cutoff),.resonance(val_flt_res),.filter_type(val_flt_type),.env_tab(val_env_tab),
        .attack(val_env_attack),.hold(val_env_hold),.decay(val_env_decay),
        .sustain(val_env_sustain),.release_v(val_env_release),
        .display_env_values(display_env_values),
        .capture_active(curve_capture),.focus_valid(curve_focus_valid),.focus_id(curve_focus_id),
        .update_valid(curve_update_valid),.update_filter(curve_update_filter),
        .update_tab(curve_update_tab),.update_mask(curve_update_mask),.update_values(curve_update_values)
    );

    param_merger u_param_merger (
        .curve_update_valid(curve_update_valid),.curve_update_filter(curve_update_filter),
        .curve_update_tab(curve_update_tab),.curve_update_mask(curve_update_mask),
        .curve_update_values(curve_update_values),.midi_tx_busy(midi_tx_busy),
        .clk               (clk_pixel),
        .rst_n             (sys_rst_n_sync),
        .touch_delta_valid (merged_delta_valid),
        .touch_selected_id (merged_delta_id),
        .touch_delta_val   (merged_delta_value),
        .btn_tap_valid     (btn_tap_valid),
        .btn_tap_id        (btn_tap_id),
        .btn_tap_action    (btn_tap_action),
        .spi_param_valid   (1'b0),
        .spi_param_id      (spi_param_id),
        .spi_param_val     (spi_param_val),
        .val_macro1        (val_macro1),
        .val_macro2        (val_macro2),
        .val_macro3        (val_macro3),
        .val_macro4        (val_macro4),
        .val_master_vol    (val_master_vol),
        .val_osca_unison   (val_osca_unison),
        .val_osca_detune   (val_osca_detune),
        .val_osca_blend    (val_osca_blend),
        .val_osca_phase    (val_osca_phase),
        .val_osca_rand     (val_osca_rand),
        .val_osca_wt_pos   (val_osca_wt_pos),
        .val_osca_warp     (val_osca_warp),
        .val_osca_pan      (val_osca_pan),
        .val_osca_vol      (val_osca_vol),
        .val_oscb_unison   (val_oscb_unison),
        .val_oscb_detune   (val_oscb_detune),
        .val_oscb_blend    (val_oscb_blend),
        .val_oscb_phase    (val_oscb_phase),
        .val_oscb_rand     (val_oscb_rand),
        .val_oscb_wt_pos   (val_oscb_wt_pos),
        .val_oscb_warp     (val_oscb_warp),
        .val_oscb_pan      (val_oscb_pan),
        .val_oscb_vol      (val_oscb_vol),
        .val_flt_cutoff    (val_flt_cutoff),
        .val_flt_res       (val_flt_res),
        .val_flt_pan       (val_flt_pan),
        .val_flt_drive     (val_flt_drive),
        .val_flt_fat       (val_flt_fat),
        .val_flt_mix       (val_flt_mix),
        .val_env_attack    (val_env_attack),
        .val_env_hold      (val_env_hold),
        .val_env_decay     (val_env_decay),
        .val_env_sustain   (val_env_sustain),
        .val_env_release   (val_env_release),
        .val_fx_reverb     (val_fx_reverb),
        .val_fx_delay      (val_fx_delay),
        .val_fx_chorus     (val_fx_chorus),
        .val_portamento    (val_portamento),
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
        .active_btn_id     (active_btn_id),
        .btn_flash_active  (btn_flash_active),
        .midi_cc_req       (midi_cc_req),
        .midi_cc_param_id  (midi_cc_param_id),
        .midi_cc_val       (midi_cc_val)
    );

    // --------------------------------------------------------------------------
    // 6. 纯硬件 1280x720 矢量图形光栅化流水线 (UI Vector Engine)
    // --------------------------------------------------------------------------
    wire        render_hsync;
    wire        render_vsync;
    wire        render_den;
    wire [23:0] render_pixel;
    wire [59:0] trace_lfo_state;
    wire signed [15:0] audio_vis_sample;
    wire audio_vis_sample_valid;
    wire signed [15:0] audio_vis_right_sample;
    wire audio_vis_stereo_valid;
    wire audio_vis_link_up;

    i2s_visual_rx #(
        .LINK_TIMEOUT_CYCLES(12_500_000) // 250 ms without BCLK = disconnected
    ) u_audio_vis_rx (
        .clk       (clk_pixel),
        .rst_n     (sys_rst_n_sync),
        .i2s_bclk  (audio_vis_bclk),
        .i2s_lrc   (audio_vis_lrc),
        .i2s_din   (audio_vis_din),
        .sample    (audio_vis_sample),
        .sample_valid(audio_vis_sample_valid),
        .sample_right(audio_vis_right_sample),
        .stereo_valid(audio_vis_stereo_valid),
        .link_up   (audio_vis_link_up)
    );

    ui_top_renderer u_render (
        .navigation_capture(navigation_capture),.navigation_delta_valid(navigation_delta_valid),
        .navigation_delta_id(navigation_delta_id),.navigation_delta_value(navigation_delta_value),
        .display_env_snapshot(display_env_values),
        .external_param_valid(spi_param_valid && physical_fx),.external_param_id(physical_fx_id),.external_param_value(physical_fx_value),
        .fx_parameter_snapshot(fx_parameter_snapshot),.fx_touch_focus_valid(fx_touch_focus_valid),.fx_touch_focus_id(fx_touch_focus_id),
        .binding_capture(binding_capture),
        .fx_event_valid(fx_event_valid),.fx_event_id(fx_event_id),.fx_event_value(fx_event_value),
        .route_event_valid(route_event_valid),.route_event_target(route_event_target),
        .route_event_source(route_event_source),.route_event_depth(route_event_depth),
        .lfo_node_snapshot(lfo_node_snapshot),.lfo_rate_snapshot(lfo_rate_snapshot),
        .lfo_step_snapshot(lfo_step_snapshot),.lfo_once_snapshot(lfo_once_snapshot),
        .route_source_snapshot(route_source_snapshot),.route_depth_snapshot(route_depth_snapshot),
        .trace_lfo_state(trace_lfo_state),
        .ui_touch_valid(ui_touch_valid), .ui_touch_down(ui_touch_down),
        .ui_touch_x(ui_touch_x), .ui_touch_y(ui_touch_y),
        .touch_diag_coords (touch_diag_coords),
        .touch_diag_count  (touch_diag_count),
        .touch_diag_mode   (touch_diag_mode),
        .clk               (clk_pixel),
        .rst_n             (sys_rst_n_sync),
        .in_hsync          (raw_hsync),
        .in_vsync          (raw_vsync),
        .in_den            (raw_den),
        .in_pixel_x        (pixel_x),
        .in_pixel_y        (pixel_y),
        .val_macro1        (val_macro1),
        .val_macro2        (val_macro2),
        .val_macro3        (val_macro3),
        .val_macro4        (val_macro4),
        .val_master_vol    (val_master_vol),
        .val_osca_unison   (val_osca_unison),
        .val_osca_detune   (val_osca_detune),
        .val_osca_blend    (val_osca_blend),
        .val_osca_phase    (val_osca_phase),
        .val_osca_rand     (val_osca_rand),
        .val_osca_wt_pos   (val_osca_wt_pos),
        .val_osca_warp     (val_osca_warp),
        .val_osca_pan      (val_osca_pan),
        .val_osca_vol      (val_osca_vol),
        .val_oscb_unison   (val_oscb_unison),
        .val_oscb_detune   (val_oscb_detune),
        .val_oscb_blend    (val_oscb_blend),
        .val_oscb_phase    (val_oscb_phase),
        .val_oscb_rand     (val_oscb_rand),
        .val_oscb_wt_pos   (val_oscb_wt_pos),
        .val_oscb_warp     (val_oscb_warp),
        .val_oscb_pan      (val_oscb_pan),
        .val_oscb_vol      (val_oscb_vol),
        .val_flt_cutoff    (val_flt_cutoff),
        .val_flt_res       (val_flt_res),
        .val_flt_pan       (val_flt_pan),
        .val_flt_drive     (val_flt_drive),
        .val_flt_fat       (val_flt_fat),
        .val_flt_mix       (val_flt_mix),
        .val_env_attack    (val_env_attack),
        .val_env_hold      (val_env_hold),
        .val_env_decay     (val_env_decay),
        .val_env_sustain   (val_env_sustain),
        .val_env_release   (val_env_release),
        .val_fx_reverb     (val_fx_reverb),
        .val_fx_delay      (val_fx_delay),
        .val_fx_chorus     (val_fx_chorus),
        .val_portamento    (val_portamento),
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
        .active_btn_id     (active_btn_id),
        .btn_flash_active  (btn_flash_active),
        .selected_param_id (display_focus_id),
        .user_knob_steps(user_knob_steps),
        .usb_connected     (usb_connected),
        .usb_conn_err      (usb_conn_err),
        .usb_dev_type      (usb_dev_type),
        .usb_raw_x         (usb_touch_x),
        .usb_raw_y         (usb_touch_y),
        .usb_raw_down      (usb_touch_state),
        .usb_dbg_report    (usb_dbg_report),
        .usb_dbg_regs      (usb_dbg_regs),
        .usb_dbg_pkt_cnt   (usb_dbg_pkt_cnt),
        .audio_sample_valid(audio_vis_sample_valid),
        .audio_sample     (audio_vis_sample),
        .audio_right_sample(audio_vis_right_sample),
        .audio_stereo_valid(audio_vis_stereo_valid),
        .audio_link_up     (audio_vis_link_up),
        .out_hsync         (render_hsync),
        .out_vsync         (render_vsync),
        .out_den           (render_den),
        .out_pixel_data    (render_pixel)
    );

    // --------------------------------------------------------------------------
    // 7. HDMI / DVI-TX 发射 PHY (OSER10 + ELVDS_OBUF)
    // --------------------------------------------------------------------------
    dvi_tx_top u_dvi_tx (
        .pixel_clock     (clk_pixel),
        .ddr_bit_clock   (clk_5x_bit),
        .reset           (~sys_rst_n_sync),
        .phy_reset       (~(rst_n & pll_lock & pll_usb_lock)),
        .den             (render_den),
        .hsync           (render_hsync),
        .vsync           (render_vsync),
        .pixel_data      (render_pixel),
        .tmds_clk        ({tmds_clk_p_0, tmds_clk_n_0}),
        .tmds_d0         ({tmds_d_p_0[0], tmds_d_n_0[0]}),
        .tmds_d1         ({tmds_d_p_0[1], tmds_d_n_0[1]}),
        .tmds_d2         ({tmds_d_p_0[2], tmds_d_n_0[2]})
    );

    // --------------------------------------------------------------------------
    // 8. 队友 3 音频引擎 UART MIDI 协议发送器 (31250 baud)
    // --------------------------------------------------------------------------
    wire audio_midi_tx;
    // LFO Protocol V2: snapshot the LFO UI after it falls quiet and stream the
    // configuration as 6-byte SysEx frames; static CC values keep flowing as-is.
    lfo_sysex_tx #(
        .HOLD_CYCLES       (1_000_000), // 20 ms edit-quiet window @ 50 MHz
        .FIRST_HOLD_CYCLES (300_000)    // initial full sync after 6 ms
    ) u_lfo_sysex (
        .clk         (clk_pixel),
        .rst_n       (sys_rst_n_sync),
        .cfg_nodes   (lfo_node_snapshot),
        .cfg_rates   (lfo_rate_snapshot),
        .cfg_steps   (lfo_step_snapshot),
        .cfg_once    (lfo_once_snapshot),
        .cfg_sources (route_source_snapshot),
        .cfg_depths  (route_depth_snapshot),
        .tx_accept   (sysex_accept),
        .sysex_req   (sysex_req),
        .sysex_msgs  (sysex_msgs),
        .busy        ()
    );
    midi_uart_tx #(
        .CLK_FREQ (50000000),
        .BAUD     (31250)
    ) u_midi_tx (
        .clk           (clk_pixel),
        .rst_n         (sys_rst_n_sync),
        .note_on_req   (1'b0),
        .note_off_req  (1'b0),
        .note_number   (7'd0),
        .note_velocity (7'd100),
        .cc_req        (midi_cc_req),
        .cc_param_id   (midi_cc_param_id),
        .cc_val        (midi_cc_val),
        .sysex_req     (sysex_req),
        .sysex_msgs    (sysex_msgs),
        .sysex_accept  (sysex_accept),
        .uart_tx       (audio_midi_tx),
        .tx_busy       (midi_tx_busy)
    );

    // Diagnostic UI trace remains independently selectable. Both normal and
    // diagnostic builds keep MIDI on U15 and knob text on C14 by default.
    generate if(DEBUG_TOUCH_LOG) begin: g_trace
        assign audio_link_tx=1'b1;
        assign midi_uart_tx=audio_midi_tx;
    end else begin: g_midi
        assign midi_uart_tx=audio_midi_tx;
        assign audio_link_tx=audio_midi_tx;
    end endgenerate

    generate if(DEBUG_KNOB_ASCII) begin: g_knob_ascii
        knob_ascii_trace #(.FIFO_BITS(7)) u_knob_trace(
            .clk(clk_pixel),.rst_n(sys_rst_n_sync),
            .knob_valid(spi_param_valid),.knob_id(spi_param_id),.knob_cw(spi_param_cw),
            .button_valid(knob_select_valid),.button_id(knob_select_id),.button_action(knob_select_action),
            .link_valid(spi_link_valid),.link_chip(spi_link_chip),.link_up(spi_link_up),
            .uart_tx(debug_uart_tx)
        );
    end else begin: g_debug_uart_mirror
        assign debug_uart_tx=midi_uart_tx;
    end endgenerate
    // --------------------------------------------------------------------------
    // 9. 心跳与系统状态指示
    // --------------------------------------------------------------------------
    reg [26:0] heartbeat_cnt;
    always @(posedge clk_pixel or negedge sys_rst_n_sync) begin
        if (!sys_rst_n_sync)
            heartbeat_cnt <= 27'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 27'd1;
    end

    assign led[0] = pll_lock & pll_usb_lock;           // LED0: 常亮 = HDMI 视频 PLL 与 USB 触控 PLL 双硬件锁定
    assign led[1] = heartbeat_cnt[26] ^ touch_activity; // LED1: 1Hz 闪烁心跳 + 触控交互跳变指示

endmodule

// 同步复位辅助模块
module Reset_Sync (
    input  wire clk,
    input  wire ext_reset,
    output wire resetn
);
    reg [3:0] reset_cnt = 4'd0;
    always @(posedge clk or negedge ext_reset) begin
        if (!ext_reset)
            reset_cnt <= 4'b0;
        else
            reset_cnt <= reset_cnt + !resetn;
    end
    assign resetn = &reset_cnt;
endmodule
