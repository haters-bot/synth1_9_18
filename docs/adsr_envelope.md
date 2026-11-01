# 时分复用ADSR包络

## 1. 职责划分

控制单片机负责用户界面、音色预置以及A/D/S/R参数选择，只向FPGA发送四个7位
控制值。FPGA继续接收Note On/Off，并为每个TDM槽位保存独立包络状态。

```text
控制MCU或测试上位机
    │  CC24～CC27
    v
synth_control_router
    │  attack/decay/sustain/release_control
    v
adsr_parameter_mapper
    │  32位阶段步进和16位Sustain电平
    v
oscillator_tdm_bank
    v
每槽位ADSR状态机
```

以后把控制输入换成独立UART或SPI时，只需要把新接口连接到同一组参数寄存器，
不需要搬动声部分配器和包络状态机。

## 2. 控制协议

测试阶段仍使用MIDI通道16的Control Change：

| 参数 | CC | 范围 | 复位值 | 默认效果 |
|---|---:|---:|---:|---:|
| Attack | 24 | 0～127 | 27 | 约9.85 ms |
| Decay | 25 | 0～127 | 54 | 约102.4 ms |
| Sustain | 26 | 0～127 | 89 | 约70.1% |
| Release | 27 | 0～127 | 67 | 约315.1 ms |

A、D、R使用近似指数时间刻度，每增加8个控制值，时间约翻倍：

| 控制值 | 阶段时间 |
|---:|---:|
| 0 | 1 ms |
| 8 | 2 ms |
| 16 | 4 ms |
| 24 | 8 ms |
| 32 | 16 ms |
| 48 | 64 ms |
| 64 | 256 ms |
| 80 | 1.024 s |
| 96 | 4.096 s |
| 112 | 16.385 s |
| 127 | 约58.25 s |

相邻8个整数点在对应的时间倍频程内进一步细分。时间表是近似指数映射，不承诺每个
中间值恰好落在十进制整毫秒。

Sustain线性映射到16位无符号幅度。控制值127对应`16'hFFFF`，其余控制值使用
`control × 516`近似映射。

## 3. 包络更新时序

- 内部振荡器采样率：`768 kHz`
- `ENVELOPE_UPDATE_DIV`：`16`
- 包络更新率：`48 kHz`
- 每次包络更新间隔：约`20.833 us`

一次包络更新请求会保持整个TDM批次，使该物理引擎中的所有槽位在同一个内部音频
采样内各更新一次。波形读取流水线仍保持每拍发出、每拍提交一个槽位。

## 4. 每槽位状态

每个逻辑振荡器槽位保存：

- `gate_state`：琴键是否仍按下；
- `envelope_stage`：IDLE、ATTACK、DECAY、SUSTAIN或RELEASE；
- `envelope_level[15:0]`：当前Q0.16包络电平；
- `envelope_phase[31:0]`：当前阶段的归一化进度；
- `release_start_level[15:0]`：进入Release瞬间的电平；
- `velocity_envelope_level[15:0]`：乘入MIDI力度后的包络增益。

32位阶段进度解决了旧版16位整数步进最长只能表示约1.365秒的问题。

## 5. 阶段算法

`adsr_parameter_mapper`按48 kHz更新率生成阶段步进：

```text
phase_step ≈ 2^32 / (阶段时间 × 48000)
```

### Attack

```text
phase += attack_phase_step
p = phase / 2^32
level = 2p - p^2
```

这条固定缓出曲线起音较快，但接近满幅时斜率逐渐降为0，减少线性Attack直接切换到
Decay时形成的第二个明显瞬态。进度完成后把电平钳位到满幅，清零阶段进度并进入
Decay。

### Decay

```text
phase += decay_phase_step
p = phase / 2^32
level = 65535 - (65535 - sustain_level) × p^2
```

Decay开始处的斜率为0，与Attack末端平滑连接；随后逐渐下降到Sustain。进度完成后进入
Sustain。

### Sustain

Gate保持有效时，包络保持在`sustain_level`。顶层让Sustain控制值在96 kHz边界每次
最多移动一级，因此从0跳到127的完整平滑时间约为1.32 ms。

当Sustain为0时，按住琴键也会在Decay结束后变为静音，但槽位仍保持Gate有效，直到
收到Note Off。这与标准ADSR语义一致。

### Release

Note Off会保存当前电平并清零阶段进度：

```text
release_start_level = current_level
phase = 0
```

随后执行：

```text
phase += release_phase_step
p = phase / 2^32
level = release_start_level × (1 - p)^2
```

因此无论Note Off发生在Attack、Decay还是Sustain，Release阶段时间都由CC27决定。
Release尾部的斜率逐渐降为0，减少接近静音时的硬折点。Release完成后电平归零，核心
产生`task_idle_valid`脉冲，任务调度器才回收槽位。

## 6. 力度与音频乘法

MIDI力度先作用于包络：

```text
velocity_envelope = envelope_level × velocity / 128
```

然后与16位有符号波形相乘：

```text
PCM16 × unsigned Q0.16 → signed 34 bit → 舍入并右移16位 → PCM16
```

力度127单独保持满幅。力度缩放后的包络寄存一拍，再参与波形乘法，避免两个乘法器
在同一条组合路径上级联。

## 7. 曲线实现边界

当前Attack、Decay和Release采用一组固定二次曲线。A/D/R时间、Sustain电平、MIDI
协议和每槽位状态机语义没有改变；它只改变阶段内部的幅度轨迹。参数
`CURVED_ENVELOPE_ENABLE=0`可恢复旧线性轨迹，用于A/B验证。

平方计算位于已有相邻寄存器级之间，Decay和Release仍复用原有16×16阶段插值乘法器，
没有增加TDM调度流水线级数。运算器只在共享的物理引擎数据路径中出现，不会为32个
逻辑槽位各复制一套；实际DSP映射和50 MHz时序仍需以Gowin综合、布局布线报告为准。

这一版没有开放Serum式可调曲率。以后可以把固定二次曲线替换为曲线LUT，同时保持
现有协议和状态存储不变。

## 8. 已验证行为

- 默认A/D/S/R控制值到定点参数的映射；
- Attack在1/4、1/2和3/4进度处的固定平滑曲线电平；
- Decay和Release的固定平滑曲线电平与最终阶段切换；
- Sustain为0时，琴键保持按下但声音在Decay后归零；
- Note Off后Release完成并归还槽位；
- 通道16的CC24～27正确进入参数寄存器；
- 原有1引擎×32槽位调度、释放和超时回归；
- 顶层UART MIDI、Unison、Detune、波表和最终静音回归。

本次只运行RTL编译和ModelSim功能仿真，没有自动运行Gowin综合或布局布线。
