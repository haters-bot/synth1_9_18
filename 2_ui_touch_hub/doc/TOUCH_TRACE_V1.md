# 点击日志第一期：独立诊断固件

## 1. 怎么接、怎么看

使用板卡当前用于下载/调试的 DEBUG USB 到工程机，不占用屏幕触控 USB。
本地 Dock 31002 原理图第 8/21 页显示 USB-JTAG/UART 桥为 **BL616**，FPGA_UART.TX 经 R58 接桥接 RX；
旧文档笼统称 FT2232 不可当作此板已核实事实。2026-10-18 工程机枚举为
COM5（0403:6010，序号 2025030317A）与 COM6（0403:6010，2025030317B）。
USB 呈现的 VID/PID 不能单独证明桥接物理芯片为 FT2232；Sipeed 调试固件可模拟此接口。
当前工程以 `constraints/ui_touch_hub.cst` 为准：UART TX U15，RX V14。
因此不需要假定一个尚未接线的新 GPIO；COM 编号必须现场枚举。

两种固件用途明确分开：

| 工程 | U15 输出 | 用途 |
|---|---|---|
| `2_ui_touch_hub.gprj` / `build.tcl` | 原 MIDI，31250 8N1 | 保留当前音频输出行为 |
| `2_ui_touch_hub_debug.gprj` / `build_debug.tcl` | 点击日志，115200 8N1 | 本轮自测诊断；同一引脚暂停对外发送 MIDI |

诊断顶层仅以参数 `DEBUG_TOUCH_LOG=1` 包装原顶层。内部原 MIDI/FIFO/busy 继续运行，
只选择不同的外部 TX 驱动；日志没有反馈线、阻塞线或 UI 控制写入。
**诊断固件不能接到下游 MIDI 接收器当作有效音频控制。后续三人联调前切回普通固件或落实独立日志口。**

工程机操作：

```powershell
python -m pip install pyserial
python tools/touch_trace_monitor.py --list
python tools/touch_trace_monitor.py --port COM6 --seconds 60
```

COM6 已收到真实有效状态帧，确认是本次 UART；不要打开可能用于 JTAG 的 COM5。
日志工具不向 FPGA 发字节，关闭 RTS/DTR，默认保持 115200。
终端打印可读记录，同时新建 `impl/touch_logs/touch_时间.jsonl` 和同名 `.bin`，不覆盖已有抓取。
指定其他输出：`--output D:\gaoyun_deploy\touch_本次.jsonl`；只要路径尚不存在即可。
离线复查：`python tools/touch_trace_monitor.py --decode 完整路径.bin`，无需 pyserial。

首次应依次点击 ENV2、空白区、Filter、ENV/LFO 曲线并松手，保留原始抓取。
用屏幕响应和日志比对才能称为实机通过；仿真示例不能代替真实点击日志。

主力机可直接采集工程机串口并取回原始文件，先完成烧录，再运行（均使用 HTTP 8899）：

```powershell
python tools/capture_remote_trace.py --port COM6 --seconds 30 --label first_clicks
```

工程机与主力机都保留原始 bin、JSONL；本地另外保留 console.log、哈希与采集 manifest。
串口开启时可能先读出桥接器/驱动缓存的旧记录。`received_at` 是 PC 接收时间，`board_ms` 是事件时间，
不能把初始批量收到的缓存记录当作此刻发生的操作。工具保留原始数据，不自动清空缓存。
应同时查看 `sequence_gap_total`、`bad_frames` 和 `board_dropped`；板端未丢包不代表传输链路无丢失。

## 2. 第一期字段与含义

- `touch`：来源 USB/HSPI/UART、按下/移动/松手、原始 16 位 X/Y、缩放后的 1280×720 坐标。
- `button`：真实 router 事件的内部参数 ID/名称、动作码。ENV 页签动作 0/1/2，其他按钮动作依 RTL 解释。
- `delta`：旋钮相对拖动的有符号增量。
- `parameter_request`：参数中枢发出的 ID/7 位值，**只是内部发送请求，不能当成音频已收到、已接受或已生效**。
- `curve`：FILTER/ENV、目标页签、字段掩码和五个字段值；仅 mask 对应字段有效。FILTER 前两字段为 Cutoff/Res；ENV 为 A/H/D/S/R。
- `spi`：接收草案解码出的 ID 和值，不代表已和物理队友联调。
- `context`：保留的选中控件与当前值、ENV 页签、按钮状态位。**focus 是上次选中的控件，不等于本次点击命中**；空白区点击仍记录坐标。
- `lfo_snapshot`：本地页签、速率档、模式、预设、七点值；不记录自动走动的相位，避免日志被预览动画淹没。
- `sequence / board_ms / dropped_records`：从复位起的序号、毫秒、硬件缓冲丢弃总数；PC 另加接收时间。

DOWN/MOVE/UP 由 PC 根据已接收到的触摸状态推导。如果从手势中途开始采集或发生丢包，不能把推导手势数量当绝对硬件点击计数。
USB 看门狗补出的抬手同样属于触摸流事件，本期不另标“物理松手/看门狗释放”。
HUD 的 +/- 可能产生 delta 而非 button，LFO 控件由独立状态机编辑，以 touch + LFO 状态变化分析。

## 3. 二进制格式（版本 1）

每帧固定 64 字节，多字节字段 little endian。

| 偏移 | 内容 |
|---|---|
| 0..1 | 55 AA 同步头 |
| 2 | 版本 01 |
| 3 | 事件位：touch、button、delta、parameter_request、curve、spi、lfo、status（bit0..7） |
| 4..7 / 8..11 / 12..15 | 32 位 sequence / 第一个批内事件的 board_ms / dropped_records |
| 16 / 17 | touch_down / source（1 USB，2 HSPI，3 UART） |
| 18..25 | raw_x / raw_y / mapped_x / mapped_y，各16位 |
| 26..29 | focus_id / button_id / action / signed delta |
| 30..33 | 参数请求 ID/value / SPI ID/value |
| 34 / 35 / 36..40 | curve filter(bit2)+tab(bit1..0) / mask / 五个7位值各占1字节 |
| 41..44 | ENV tab / LFO tab / rate_index / preset(bit3..2)+stepped(bit1)+once(bit0) |
| 45..51 | 七点 LFO，各1字节 |
| 52 / 53 / 54..57 / 58 | focus_known / focus_value / 32位button_state / value_valid |
| 59..62 | 保留为0 |
| 63 | 前63字节逐字节 XOR；这是轻量误码检测，**不是 CRC** |

tab在线路上从0开始，PC显示从1开始。button_state bit0/1/2=A/B/Filter开关，
bit3..4 A波形、5..6 B波形、7..8滤波类型、9..12路由A/B/N/S、13 keytrack、14..17 slot_bypass。

同一输入在路由和中枢经过数拍传播，16 个像素时钟窗口内合并成一帧，各事件类别独立保留。
窗口内同类事件重复则保留最后一个字段值；时间为首事件，状态快照为入队时，不是逐周期逻辑分析仪。
32 帧 FIFO，不对 UI 施加背压。满时丢弃新日志并计数，下一帧和每秒 status 可见；序号空洞也提示丢失。
115200 8N1 理论约 180 帧/秒；不能保证任何事件洪峰下日志无损。普通点击应无丢失，实机仍须验证。
XOR 无法检测所有错误，必要时可在后续版本扩展 CRC 和设备/固件身份字段。

## 4. 已完成验证与尚未完成事项

`python tools/test_touch_trace.py`：完整源码编译；独立从 UART 引脚波形解码，核对同时发生的多类事件、
批边界事件、负增量、坐标、曲线与 LFO 值、FIFO 超载计数、每秒状态、PC 碎片输入与坏包恢复。
额外沿用原 curve / LFO / pixel / RTL preview 回归。

SSH 已恢复并完成端口枚举。诊断工程 PnR 正常 exit 0；像素域目标 62.5 MHz，
Fmax 57.876 MHz，最差 setup -1.278 ns，setup 违规端点共 96，hold 违规 0，仍未时序收敛。
构建、部署和实际采集结果见 `CODEX_TOUCH_TRACE_HANDOFF_2026-10-18.md`。

旧 `sim/tb_usb_touch_intake.v` 对应回退前的另一套 HID 解码格式，与已验收 R15I 不兼容，
本轮运行在首包失败（实际 X=19747/Y=33，旧断言期待 9163/8525）。本轮 USB 修改仅移动
`u_dev_conn` 声明以消除 ModelSim 重复声明，不改解码行为。不要为通过旧断言改坏已实测校准。

资料来源：Sipeed 官方 Tang Mega 页面说明 DEBUG USB 提供 JTAG/UART，
https://wiki.sipeed.com/hardware/zh/tang/tang-mega-138k/mega-138k.html ；
调试器固件说明列出 BL616/BL702 与调试器更新信息，
https://wiki.sipeed.com/hardware/zh/tang/common-doc/update_debugger.html 。本轮未更新调试器固件。
