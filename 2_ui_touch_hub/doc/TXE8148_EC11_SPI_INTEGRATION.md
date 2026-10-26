# TXE8148 双芯片与 32 个 EC11 接入说明

## 当前实现

`rtl/knob_spi_intake/knob_spi_rx.v` 已从旧的“16 通道 ADC 帧接收器”改为双 TXE8148 轮询接收器：

- SPI mode 0，MSB first，当前工程约 1.7 MHz；
- 两颗芯片使用独立 `1CS#` / `2CS#`，共享 `SCLK`、`SDI`、`SDO`；
- 每颗芯片连续读取输入端口寄存器 `0x20..0x25`；
- 第一颗芯片提供 EC11 1..16，第二颗芯片提供 EC11 17..32；
- PCB 按端口 bank 接线：P0/P1 为 32 路 A，P2/P3 为 32 路 B，P4/P5 为 32 路 SW；不能按 A/B/SW 三个连续 GPIO 解码；
- A/B 使用四状态正交解码，旋钮值为 0..127，初值 64；
- SW 按主动低处理，按下在接收器内形成该旋钮对应的选择事件；释放不重复触发参数动作。当前选择事件尚未接入全局 UI 持久高亮；
- 首次完整扫描只建立基线，不产生误触发。

TXE8148 的 SPI 读帧为 `0x82, {port[2:0], 4'b0}, 0x00`。读回的前 16 位是状态和填充，最后 8 位是目标输入端口寄存器。芯片规定 SPI 时钟最高 10 MHz，本工程使用约 1.7 MHz，留出同步和连线裕量。

## GPIO 与旋钮映射

对于芯片内的旋钮编号 `k=0..15`：

```text
A  = GPIO[k]
B  = GPIO[16 + k]
SW = GPIO[32 + k]
```

因此第一颗芯片的旋钮 1 是 `P0.0/P2.0/P4.0`，旋钮 9 是 `P1.0/P3.0/P5.0`，旋钮 16 是 `P1.7/P3.7/P5.7`。第二颗芯片重复同一布局，对应旋钮 17..32。

## UI 参数映射

四个实体区域与 UI 的关系固定为：左上 = OSC A，左下 = ENV/Global，右上 = OSC B，右下 = Filter/FX。旋钮按每块 8 个连续编号，映射集中在 `map_knob_to_param_id`。

| 实体区域 | 旋钮编号 | UI 参数关系 |
|---|---:|---|
| 左上 / Upper-left | 1..8 | OSC A：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 左下 / Lower-left | 9..16 | ENV：Attack、Hold、Decay、Sustain、Release；Master、Macro 1、Macro 2 |
| 右上 / Upper-right | 17..24 | OSC B：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 右下 / Lower-right | 25..32 | Filter：Cutoff、Res、Pan、Drive、Fat、Mix；Reverb、Delay |

旋转某个实体 EC11 后，参数事件使用该旋钮映射的参数 ID；触摸屏点选同一个 UI 旋钮时使用同一个参数 ID，因此两种输入可以交替操作同一参数。实体按压目前只在 SPI 接收器内部形成选择事件，尚未接入全局 UI 持久选中态；释放不重复发送新的参数动作。


## 供电和电平边界

键盘板原理图把 Type-C VCC 网络标为 `3.3V-IN`，因此 Type-C 只能接 3.3 V。FPGA 侧不使用 `E16` 给键盘板供电，不能把 5 V 直接送入该 VCC 网络。

必须确认：

1. 键盘板实际 VCC 为 3.3 V；
2. 两块板共地，且 RESET、INT# 的有效电平与原理图一致；
3. `SDO`、`SDI/SCLK/CS/RESET` 都处于 FPGA 可承受的 3.3 V 电平范围。

在没有确认电平转换前，不允许把 5 V `SDO` 直接接到 FPGA `D17`。

## FPGA 引脚

| 信号 | FPGA 引脚 | 方向 |
|---|---:|---|
| `2CS#` | A15 | FPGA 输出 |
| `1CS#` | B20 | FPGA 输出 |
| `SCLK` | B21 | FPGA 输出 |
| `SDI` | B17 | FPGA 输出 |
| `SDO` | D17 | FPGA 输入 |
| `INT#` | A18 | FPGA 输入 |
| `RESET` | D14 | FPGA 输出 |

`E16` 没有写入 FPGA 约束文件；它不是键盘板供电接口。键盘板供电走独立 Type-C 入口。
