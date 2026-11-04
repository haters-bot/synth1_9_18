# TXE8148 双芯片与 32 个 EC11 接入说明

## 当前实现（2026-10-27）

`rtl/knob_spi_intake/knob_spi_rx.v` 已从旧的“16 通道 ADC 帧接收器”改为双 TXE8148 轮询接收器：

- SPI mode 0，MSB first，当前工程 1 MHz；
- 两颗芯片使用独立 `1CS#` / `2CS#`，共享 `SCLK`、`SDI`、`SDO`；
- 每颗芯片连续读取输入端口寄存器 `0x20..0x25`；
- 第一颗芯片提供 EC11 1..16，第二颗芯片提供 EC11 17..32；
- 按已验证的 STM32F103 参考工程映射：每个 EC11 使用连续三个输入位 `A=3*k, B=3*k+1, SW=3*k+2`；
- A/B 使用四状态正交解码，每四个有效相位沿产生一个 CW/CCW detent 事件；事件通过参数中枢以当前 UI 参数为基准增减 1，避免独立的物理旋钮 shadow value 覆盖屏幕值；
- SW 按主动低处理并做扫描去抖，PRESS/RELEASE 事件保留给 C14 诊断日志；目前不改变 UI 持久选择状态；
- 首次完整扫描只建立基线，不产生误触发。

每次读帧为 `0x82, {port[2:0], 4'b0}, 0x00`，Mode 0、MSB first；状态字节用于检测芯片连接，端口数据保存在每个芯片的六个 8 位输入寄存器中。接收器在 CS/SCLK 位级状态机中明确产生每一位的低/高相位。

## GPIO 与旋钮映射

对于芯片内从0开始的旋钮编号 `k=0..15`：

```text
A  = GPIO[3*k]
B  = GPIO[3*k + 1]
SW = GPIO[3*k + 2]
```

因此 U1/K01=`P0.0/P0.1/P0.2`，K02=`P0.3/P0.4/P0.5`，K16=`P5.5/P5.6/P5.7`。U2 重复同一布局，对应 K17..K32。该映射与已在 UI 板上验证的独立探针、STM32 参考固件一致；不使用旧的分 bank A/B/SW 解码规则。

## UI 参数映射

四个实体区域与 UI 的关系固定为：左上 = OSC A，左下 = ENV/Global，右上 = OSC B，右下 = Filter/FX。旋钮按每块 8 个连续编号，映射集中在 `map_knob_to_param_id`。

| 实体区域 | 旋钮编号 | UI 参数关系 |
|---|---:|---|
| 左上 / Upper-left | 1..8 | OSC A：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 左下 / Lower-left | 9..16 | ENV：Attack、Hold、Decay、Sustain、Release；Master、Macro 1、Macro 2 |
| 右上 / Upper-right | 17..24 | OSC B：WT Pos、Warp、Pan、Vol、Unison、Detune、Blend、Phase |
| 右下 / Lower-right | 25..32 | Filter：Cutoff、Res、Pan、Drive、Fat、Mix；Reverb、Delay |

旋转某个实体 EC11 后，事件使用该旋钮映射的参数 ID，并作为当前参数的 `+1/-1` 增量送入与触摸相同的参数中枢；参数寄存器驱动屏幕旋钮与其数值显示。实体按压只保留 PRESS/RELEASE 观察事件，暂不绑定 UI 持久选中态。


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
