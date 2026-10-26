# TXE8148 双芯片与 32 个 EC11 接入说明

## 当前实现

`rtl/knob_spi_intake/knob_spi_rx.v` 已从旧的“16 通道 ADC 帧接收器”改为双 TXE8148 轮询接收器：

- SPI mode 0，MSB first，当前工程约 1.7 MHz；
- 两颗芯片使用独立 `1CS#` / `2CS#`，共享 `SCLK`、`SDI`、`SDO`；
- 每颗芯片连续读取输入端口寄存器 `0x20..0x25`；
- 第一颗芯片提供 EC11 1..16，第二颗芯片提供 EC11 17..32；
- 每个旋钮按 `A、B、SW` 三个 GPIO 顺序解码；
- A/B 使用四状态正交解码，旋钮值为 0..127，初值 64；
- SW 按主动低处理，按下选择该旋钮对应的 UI 参数；释放只结束实体按键事件，不重复触发参数动作；
- 首次完整扫描只建立基线，不产生误触发。

TXE8148 的 SPI 读帧为 `0x82, {port[2:0], 4'b0}, 0x00`。读回的前 16 位是状态和填充，最后 8 位是目标输入端口寄存器。芯片规定 SPI 时钟最高 10 MHz，本工程使用约 1.7 MHz，留出同步和连线裕量。

## GPIO 与旋钮映射

对于芯片内的旋钮编号 `k=0..15`：

```text
A  = GPIO[3*k + 0]
B  = GPIO[3*k + 1]
SW = GPIO[3*k + 2]
```

因此旋钮 1 是 `P0.0/P0.1/P0.2`，旋钮 2 是 `P0.3/P0.4/P0.5`，旋钮 16 是 `P5.5/P5.6/P5.7`。第二颗芯片重复同一布局，对应旋钮 17..32。

## UI 参数映射

四个实体区域与 UI 的关系固定为：左上 = OSC A，左下 = ENV/Global，右上 = OSC B，右下 = Filter/FX。旋钮按每块 8 个连续编号，映射集中在 `map_knob_to_param_id`。

| 实体区域 | 旋钮编号 | UI 参数关系 |
|---|---:|---|
| 左上 / Upper-left | 1..8 | OSC A：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 左下 / Lower-left | 9..16 | ENV：Attack、Hold、Decay、Sustain、Release；Master、Macro 1、Macro 2 |
| 右上 / Upper-right | 17..24 | OSC B：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 右下 / Lower-right | 25..32 | Filter：Cutoff、Res、Pan、Drive、Fat、Mix；Reverb、Delay |

按下某个实体 EC11 的 SW 后，UI 会把该参数设为当前选中项；随后旋转该实体旋钮改变这个参数。触摸屏点选同一个 UI 旋钮时使用同一个参数 ID，因此两种输入可以交替操作同一参数。当前版本把“按下”定义为选择/聚焦，不把“释放”重复发送成一次新的参数动作。


## 供电和电平边界

键盘板 Type-C 可以作为 5 V 输入，前提是该接口确实接入键盘板的 5 V 电源入口，并由键盘板稳压到 TXE8148 所需电压。FPGA 侧不使用 `E16` 给键盘板供电。

TXE8148 若直接以 5 V 工作，必须确认：

1. 键盘板的 `SDO` 已降到 FPGA 可承受的 3.3 V 电平；
2. FPGA 输出的 3.3 V `SDI/SCLK/CS/RESET` 满足 TXE8148 在实际供电电压下的输入高电平要求；
3. 两块板共地，且 RESET、INT# 的有效电平与原理图一致。

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
