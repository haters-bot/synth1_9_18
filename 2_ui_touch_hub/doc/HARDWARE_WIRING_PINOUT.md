# Tang Mega 138K Dock 硬件接线与引脚分配规范 (UI Touch Hub)

> **开发板型号**：Sipeed Tang Mega 138K Dock (`GW5AST-LV138PG484AC1/I0`)  
> **电气标准**：所有外部 GPIO 排针通信电平必须严格为 **3.3V LVCMOS**，严禁直连 5V。

---

## 一、 板载核心外设与接口连接

### 1. 便携屏与人机交互物理接线
- **HDMI 高清视频线**：
  - 连接便携显示器的 HDMI 输入口至 Tang Mega 138K Dock 顶部的 **标准 HDMI Type-A 母座 (J29)**；
  - 输出信号由高云 3.3V Bank 差分对原生输出，已内建 TMDS 差分驱动。
- **触摸屏 USB 线**：
  - 便携显示器的触摸输出通常为 Type-C 或 Micro-USB，使用标配线缆直插 Tang Mega 138K 底板顶部的 **USB 接口**；
  - 说明：底板顶部仅有一个标准 USB-A Host 接口，用户已按硬件图纸正确插入该接口，系统内部直通，无需再次向用户确认接口编号。

### 2. 状态指示与时钟复位
| 信号名 | 物理引脚 | IO 标准 | 方向 | 硬件位置与功能说明 |
| :--- | :--- | :--- | :--- | :--- |
| `clk` | **`V22`** | LVCMOS33 | Input | 板载 50MHz 有源晶振主时钟输入 |
| `rst_n` | **`AA13`** | LVCMOS33 | Input | 板载按键 S2 (低电平系统复位，带弱上拉) |
| `led[0]` | **`T18`** | LVCMOS33 | Output | 板载 LED0：常亮表示 PLL 硬件成功锁频 (Lock) |
| `led[1]` | **`R18`** | LVCMOS33 | Output | 板载 LED1：1Hz 周期闪烁表示 720p 视频渲染与时钟流水线正常运转 |

---

## 二、 HDMI / DVI-TX 差分高速输出引脚 (J29)

本约束严格基于 Sipeed 官方原理图 `Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf` 第 14 页 HDMI 接口定义：

| 信号名称 | 差分 P 端引脚 | 差分 N 端引脚 | IO 标准 | 描述 |
| :--- | :--- | :--- | :--- | :--- |
| `tmds_clk_p_0` / `_n` | **`G15`** | **`G16`** | LVCMOS33D | 720p 像素时钟差分对 (62.5MHz) |
| `tmds_d_p_0[0]` / `_n` | **`J14`** | **`H14`** | LVCMOS33D | TMDS 数据通道 0 差分对 (蓝色分量 + HSync/VSync) |
| `tmds_d_p_0[1]` / `_n` | **`J15`** | **`H15`** | LVCMOS33D | TMDS 数据通道 1 差分对 (绿色分量) |
| `tmds_d_p_0[2]` / `_n` | **`K17`** | **`J17`** | LVCMOS33D | TMDS 数据通道 2 差分对 (红色分量) |

---

## 三、 三人团队外部硬件跨板互联引脚 (PMOD / GPIO)

```
        Tang Mega 138K Dock 排针扩展口
        ┌──────────────────────────────────┐
        │  [PMOD 1]     [PMOD 2]   [40P Header]
        │    │             │              │
        │    ▼             ▼              ▼
        │ (队友1 SPI)  (队友3 UART)   (调试串口)
        └──────────────────────────────────┘
```

### 1. 队友 1 (硬件面板) 双 TXE8148 / 32 个 EC11
键盘板原理图把 Type-C 的 VCC 网络标为 `3.3V-IN`，因此该 Type-C 口按 **3.3 V 供电入口**使用。FPGA 只连接下面 7 根逻辑信号和公共地；FPGA 不驱动键盘板 VCC。不要把 5 V 直接接到该口。

| 面板信号 | Tang Mega FPGA 引脚 | FPGA 方向 | 说明 |
| :--- | :--- | :--- | :--- |
| `2CS#` | **`A15`** | Output | 第二颗 TXE8148 片选，低有效，旋钮 17..32 |
| `1CS#` | **`B20`** | Output | 第一颗 TXE8148 片选，低有效，旋钮 1..16 |
| `SCLK` | **`B21`** | Output | SPI mode 0，当前工程约 1.7 MHz |
| `SDI` | **`B17`** | Output | MSB first，读命令发送端 |
| `SDO` | **`D17`** | Input | 两颗 TXE8148 的共享输出 |
| `INT#` | **`A18`** | Input | 当前版本同步采样但仍采用轮询读取 |
| `RESET` | **`D14`** | Output | 上电低电平保持约 1 ms，之后释放 |
| `VCC` | 独立 Type-C 3.3 V 输入 | — | 原理图网络为 `3.3V-IN -> VCC`；不接 FPGA I/O，禁止直接接 5 V |
| `GND` | GND | — | 两板公共地，必须连接 |

TXE8148 的 48 个 GPIO 在本 PCB 上按端口分成三个 16 路 bank，而不是按单个 EC11 交错排列：`P0/P1 -> A`、`P2/P3 -> B`、`P4/P5 -> SW`。第一颗芯片的 16 路 bank 对应旋钮 1..16，第二颗芯片对应旋钮 17..32；例如第一颗的旋钮 1 使用 `P0.0`、`P2.0`、`P4.0`，旋钮 9 使用 `P1.0`、`P3.0`、`P5.0`。`SW` 按主动低处理。

实体四区和 UI 的关系为：左上/Upper-left → OSC A，左下/Lower-left → ENV/Global，右上/Upper-right → OSC B，右下/Lower-right → Filter/FX。旋转事件修改对应参数；当前实体按压事件已在接收器内识别，但尚未接入全局 UI 持久选中态。

FPGA 侧 I/O 使用 3.3 V LVCMOS。PCB 原理图显示 TXE8148 与 Type-C VCC 共用 `3.3V-IN`；因此必须使用 3.3 V 供电并共地，不能用 5 V 代替。

### 2. 音频引擎跨板 UART MIDI 控制链路（独立GPIO）
不要将UI的UART输出接到音频板V14：V14同时连接板载USB-JTAG/USB-UART桥的TX网络。两边使用专用PMOD1 IO2；互连前确认没有接DVP摄像头或SDRAM1扩展设备。
| 信号名称 | 物理引脚 | IO 标准 | 方向 | 接口协议与说明 |
| :--- | :--- | :--- | :--- | :--- |
| UI `audio_link_tx` | **`AB21` / PMOD1 IO2 / J8 pin 9** | LVCMOS33 | Output | 31250 baud MIDI，接音频板J8 pin 9 |
| Audio `midi_gpio_rx` | **`AB21` / PMOD1 IO2 / J8 pin 9** | LVCMOS33 | Input | 专用跨板接收；音频V14调试UART保留 |
| 公共地 | **J8 pin 3或4** | GND | — | 两板共地；不要跨接3.3V电源 |

UI板U15继续作为板载USB-UART监视端，不再承载跨板物理连线。音频端两个UART RX在逻辑上合并；第一阶段同一时刻只能有一个发送源活动。两个TX不做电气并联。

### 3. PC 触控调试中继接口 (Debug Touch RX)
若使用 USB 虚拟串口/HID 转发触控坐标包 (`0x54, 0x54, X, Y, State`)：
| 信号名称 | 推荐引脚 | IO 标准 | 方向 | 接口协议与说明 |
| :--- | :--- | :--- | :--- | :--- |
| `touch_uart_rx` | **`V14`** | LVCMOS33 | Input | 115200 波特率触控包接收输入 (板载 FT2232 双通道 UART B) |
