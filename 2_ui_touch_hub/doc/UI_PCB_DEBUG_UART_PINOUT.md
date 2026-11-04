# UI 板 ↔ 32 旋钮 PCB 调试 UART

## 2026-10-30 最新候选：蓝牙改用 F14 / F16

用户确认F14空闲并要求与F16靠近接线，现约束为 `phone_uart_tx=F14`（J13第29脚）→模块RXD；模块TXD→`phone_uart_rx=F16`（J13第32脚）。F16为Bank2 IOR13A/SDRAM0_RAS，官方Rev1.3原理图第7/19页核对且与现有CST无冲突。E13不再用于蓝牙。灯带仍F13，C14仍调试TX。新约束待统一构建/审计/部署，不能当作板上旧固件已生效。STATE/EN留空，底板VCC须按实物额定；详见 `HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md`。下方E13内容为历史。

## 2026-10-30 新候选：灯带 DIN 改为 F13 直连

用户确认 F13 空闲并允许使用。当前新候选约束 `performance_led_data=F13`，不再走 J16/U15/J24，直接发 24 像素，无黑色前缀。**此条是待审计/待部署候选；板上 14:03 旧固件仍输出 J16，尚不会从 F13 发数据。**

- 灯带 **DIN ← UI F13**。官方 Dock 31005 Rev1.3 第7页：F13=Bank2 IOR11A/SDRAM0_DM1；第19页：经 R70（0 Ω）到 SDRAM0_EXIO1/J13 第30脚，R71 下拉为不装。若实物排针已标 F13，按该标识接线；不要猜排针正反方向。未安装 SDRAM0 扩展卡才能复用该线；此接口不是本项目的板载 DDR3。
- FPGA 数据输出为 3.3V。5V WS2812 灯带是否识别取决于实物 VIH 规格；不能承诺直连稳定。需要时用 5V 供电的 74AHCT125 等电平转换，再到 DIN；**不得把 5V 反送 F13**。
- 灯带 GND 与 UI GND 共地，VCC 接符合灯带规格的供电。改线先断电；独立 5V 供电避免回灌板卡。使用 J24 的供电仍受其 0.45A 上限约束，数据则走 F13。
- 保留低亮度与白键映射。E16 不改，C14/E13 调试 UART 不改。
- 原理图本地源：`D:/github/gaoyun/hardware_docs/02_Schematic/DOCK/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf`；截图证据 `impl/stereo_pan_pin_review_20261030/`。

## 历史/当前板上旧固件：Tang Mega NEO Dock 板载 aRGB 接口

已核对 `Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf`（原理图 Rev 1.3）：

- FPGA 封装脚 `J16` 驱动板载 `U15` WS2812B 的 DIN；`U15` 的 DOUT 连到 aRGB 插座 `J24` 第 3 脚 `WS2812_DOUT`。
- `J24` 第 1 脚为 GND，第 2 脚未连接，第 4 脚为 `LED_Connector_5V`。该路 5 V 开关电源标注最大 0.45 A。
- 外接 24 灯灯带应连接在 `J24` 第 3 脚之后；FPGA 每帧先发送给板载 U15 一个黑色像素，再发送 24 个外接像素。不要将灯带接在 C14。
- 当前演奏数据输出约束在 FPGA J16，C14 保持下方的调试 UART。演奏颜色降低了最大占空比，避免 24 灯同时点亮超过 J24 供电能力；若使用独立电源，仍须共地且避免向板卡 5 V 轨反向供电。

## 引脚分配

| UI 板 FPGA 引脚 | 信号 | USB-TTL 端 | 说明 |
|---|---|---|---|
| `C14` | `debug_uart_tx` | RXD | UI 板输出调试/监视字节 |
| `E13` | `debug_uart_rx` | TXD | 预留的主机输入，当前版本不解析命令 |
| 任意 GND | 公共地 | GND | 必须连接 |

电气标准为 **3.3 V TTL、8N1**。调试构建的输出波特率为 115200；普通构建输出的是现有 MIDI 发送流（31250 baud）。禁止接 RS-232 电平或 5 V USB-TTL。

`C14` 的输出与板载 `U15` 监视输出保持同一数据流副本；它不占用 UI 到音频板的 `AB21` UART，也不改变旋钮板的 SPI 接线。`E13` 已锁定为输入脚，后续可增加主机命令或回读协议。

连接顺序：

```text
UI C14 (TX)  -> USB-TTL RXD
UI E13 (RX)  <- USB-TTL TXD
UI GND       -> USB-TTL GND
```
