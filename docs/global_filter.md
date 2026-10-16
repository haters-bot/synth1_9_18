# 96 kHz全局状态变量滤波器

## 1. 数据位置

```text
双振荡器TDM混音（768 kHz）
        |
8倍降采样FIR（768 kHz -> 96 kHz）
        |
global_svf_filter（96 kHz）
        |
I2S发送器（96 kHz）
```

滤波器与振荡器使用同一个`50 MHz`系统时钟，不存在跨时钟域。`in_valid`来自FIR输出，
相邻有效输入约间隔`50 MHz / 96 kHz = 520.8`拍。

## 2. 接口与默认状态

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `sample_in` | signed 16 | FIR输出PCM |
| `in_valid` | 1 | 输入样本有效脉冲 |
| `in_ready` | 1 | 状态机可接受新样本 |
| `filter_mode` | 2 | 0旁路、1低通、2高通、3带通 |
| `cutoff_control` | 7 | 约70 Hz～17.4 kHz |
| `resonance_control` | 7 | 0低共振、127高共振 |
| `sample_out` | signed 16 | 饱和后的PCM输出 |
| `out_valid` | 1 | 输出样本更新脉冲 |
| `input_overrun` | 1 | 忙时再次输入的粘滞错误标志 |

复位后模式为旁路，Cutoff为127，Resonance为0，滤波状态清零。旁路仍更新内部状态，
所以再次启用滤波器时不会从静止状态重新建立低通积分值。

## 3. 算法

一次内部迭代使用：

```text
low  = low + f * band
high = input - low - damping * band
band = band + f * high
```

每个96 kHz外部采样执行两次迭代，相当于使用保持不变的输入在192 kHz下更新两次状态。
这样最大Cutoff时的积分系数仍保持较小，提高高频和高共振设置下的稳定余量。

Cutoff采用16级/倍频程映射：

```text
f = 2 * sin(pi * Fc / 192 kHz)
```

低4位从16个基准系数中选择倍频程内位置，高3位通过左移选择倍频程。实际端点约为
`69.9 Hz`和`17.4 kHz`。Resonance控制阻尼系数从约`2.0`下降到`0.125`。

## 4. 定点格式与饱和

- 输入和输出：signed 16-bit PCM；
- `low`、`band`、`high`：40位有符号、16位小数，可记为`Q24.16`；
- Cutoff与阻尼系数：18位无符号`Q2.16`；
- 乘积：59位有符号，算术右移16位后回到状态格式；
- 内部状态保留约8位超过16-bit PCM满量程的余量；
- 输出右移16位后饱和到`-32768～32767`。

当前乘法缩放和输出转换采用截断，没有加入舍入偏置。

## 5. 状态机时序

三个乘法运算共用一个逻辑乘法器：

```text
LOW_MUL -> LOW_UPDATE
         -> DAMP_MUL -> HIGH_UPDATE
         -> BAND_MUL -> BAND_UPDATE -> COMMIT
```

上述流程执行两次，所以从接受输入到`out_valid`约为14个`50 MHz`周期，即约`280 ns`。
这小于96 kHz样本间隔`10.42 us`的3%。逻辑乘法器为`40×19 bit`，综合器可能用多个
Gowin DSP块实现，实际DSP数量、最高频率和关键路径必须以综合及布局布线报告为准。

## 6. MIDI控制

```text
CC42：Filter Mode，0～3
CC43：Filter Cutoff，0～127
CC44：Filter Resonance，0～127
```

Cutoff和Resonance目标值在顶层以96 kHz速率每次移动一级，完整0～127行程约1.32 ms。
模式目前直接切换，没有输出交叉淡化。

## 7. 已验证项目

`sim/run_global_filter_test.do`覆盖：

- 正、负PCM旁路精确通过；
- 输出延迟不超过20拍；
- 低通对直流收敛；
- 高通和带通抑制直流；
- 低截止低通抑制逐样本翻转信号；
- 高通保留逐样本翻转信号；
- 正常输入节奏下无`input_overrun`；
- 忙期间重复输入会置位粘滞`input_overrun`。

顶层回归另外验证CC42～44通过UART和MIDI解析后写入正确的参数寄存器。

## 8. 上板检查

1. 先使用旁路，确认声音与加入滤波器前一致；
2. 选择低通，Resonance设为0，从Cutoff 127缓慢扫到0；
3. 固定中等Cutoff，再逐渐提高Resonance；
4. 测试高通和带通的直流抑制与音量变化；
5. 片上调试优先观察`fir_output_valid`、`global_filter_output_valid`、
   `global_filter_input_ready`和`global_filter_input_overrun`；
6. 综合后检查共享乘法器是否映射到DSP，并重新检查50 MHz setup时序。

## 9. 已知限制

- 模式切换可能产生短促电平跳变；
- 高Resonance可能使输出进入16位饱和，当前没有非线性软削波；
- 截止频率是近似指数映射，不是校准后的模拟滤波器刻度；
- 尚未完成上板听感、资源映射和布局布线验证。
