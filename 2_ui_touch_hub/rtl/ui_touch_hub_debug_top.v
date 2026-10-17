// Diagnostic top: U15 outputs binary trace at 115200, not audio MIDI.
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

    // 队友 1 (硬件面板组) 物理旋钮 SPI 接口
    input  wire        knob_spi_cs_n,   // U14 (LVCMOS33)
    input  wire        knob_spi_sclk,   // U15 (LVCMOS33)
    input  wire        knob_spi_mosi,   // V15 (LVCMOS33)

    // U15: normal build MIDI 31250; diagnostic build trace 115200.
    output wire        midi_uart_tx,

    // 板载状态指示灯
    output wire [1:0]  led,             // T18: PLL Lock, R18: Heartbeat

    // 板载标准 HDMI Type-A 接口 (J29, GW5AST-138B Bank 3.3V)
    output wire        tmds_clk_p_0,    // G15 (P), G16 (N)
    output wire        tmds_clk_n_0,
    output wire [2:0]  tmds_d_p_0,      // D0: J14/H14, D1: J15/H15, D2: K17/J17
    output wire [2:0]  tmds_d_n_0

);
ui_touch_hub_top #(.DEBUG_TOUCH_LOG(1)) u_hub(
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
    .knob_spi_cs_n(knob_spi_cs_n),
    .knob_spi_sclk(knob_spi_sclk),
    .knob_spi_mosi(knob_spi_mosi),
    .midi_uart_tx(midi_uart_tx),
    .led(led),
    .tmds_clk_p_0(tmds_clk_p_0),
    .tmds_clk_n_0(tmds_clk_n_0),
    .tmds_d_p_0(tmds_d_p_0),
    .tmds_d_n_0(tmds_d_n_0)
);
endmodule
