// Diagnostic top: C14 outputs physical knob/link ASCII; U15 remains MIDI.
module ui_touch_hub_debug_top (

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

    // U15: normal build MIDI 31250; diagnostic build trace 115200.
    output wire        midi_uart_tx,

    // Audio-board I2S visualization return: R19/U21/R17 on the UI board.
    input  wire        audio_vis_bclk,
    input  wire        audio_vis_lrc,
    input  wire        audio_vis_din,

    // External debug UART: C14=TX, E13=RX (3.3V TTL).
    output wire        debug_uart_tx,
    input  wire        debug_uart_rx,

    // 板载状态指示灯
    output wire [1:0]  led,             // T18: PLL Lock, R18: Heartbeat

    // 板载标准 HDMI Type-A 接口 (J29, GW5AST-138B Bank 3.3V)
    output wire        tmds_clk_p_0,    // G15 (P), G16 (N)
    output wire        tmds_clk_n_0,
    output wire [2:0]  tmds_d_p_0,      // D0: J14/H14, D1: J15/H15, D2: K17/J17
    output wire [2:0]  tmds_d_n_0,
    output wire        audio_link_tx

);
ui_touch_hub_top #(.DEBUG_TOUCH_LOG(0),.DEBUG_KNOB_ASCII(1)) u_hub(
    .clk(clk),
    .rst_n(rst_n),
    .usb_dp(usb_dp),
    .usb_dm(usb_dm),
    .touch_uart_rx(touch_uart_rx),
    .touch_uart_rx_y14(touch_uart_rx_y14),
    .ch569_htclk(ch569_htclk),
    .ch569_htreq(ch569_htreq),
    .ch569_htvld(ch569_htvld),
    .ch569_htrdy(ch569_htrdy),
    .hspi_hd(hspi_hd),
    .knob_2cs_n(knob_2cs_n),
    .knob_1cs_n(knob_1cs_n),
    .knob_sclk(knob_sclk),
    .knob_sdi(knob_sdi),
    .knob_sdo(knob_sdo),
    .knob_int_n(knob_int_n),
    .knob_reset_n(knob_reset_n),
    .midi_uart_tx(midi_uart_tx),
    .audio_vis_bclk(audio_vis_bclk),
    .audio_vis_lrc(audio_vis_lrc),
    .audio_vis_din(audio_vis_din),
    .audio_link_tx(audio_link_tx),
    .debug_uart_tx(debug_uart_tx),
    .debug_uart_rx(debug_uart_rx),
    .led(led),
    .tmds_clk_p_0(tmds_clk_p_0),
    .tmds_clk_n_0(tmds_clk_n_0),
    .tmds_d_p_0(tmds_d_p_0),
    .tmds_d_n_0(tmds_d_n_0)
);
endmodule
