# 96 kHz全局滤波器

## 1. 数据位置

```text
双振荡器TDM混音（768 kHz）
        |
8倍降采样FIR（768 kHz -> 96 kHz）
        |
global_filter（96 kHz）
   |-- global_svf_filter
   `-- global_comb_filter
        |
I2S发送器（96 kHz）
```

全局滤波器与振荡器使用同一个`50 MHz`系统时钟，没有新增时钟域。`in_valid`来自FIR
输出，相邻有效输入约间隔`50 MHz / 96 kHz = 520.8`拍。

## 2. 模式与公共参数

| 模式 | 名称 | 实现 |
|---:|---|---|
| 0 | 旁路 | SVF精确传递输入 |
| 1 | 低通 | SVF Low输出 |
| 2 | 高通 | SVF High输出 |
| 3 | 带通 | SVF Band输出 |
| 4 | 陷波 | SVF Low + High |
| 5 | 梳状+ | 正反馈延迟线 |
| 6 | 梳状- | 负反馈延迟线 |

公共接口：

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `sample_in` | signed 16 | FIR输出PCM |
| `in_valid` | 1 | 输入样本有效脉冲 |
| `in_ready` | 1 | 可以接受新样本 |
| `filter_mode` | 3 | 上表中的滤波模式 |
| `cutoff_control` | 7 | SVF截止频率或Comb延迟频率 |
| `resonance_control` | 7 | SVF共振或Comb反馈量 |
| `mix_control` | 7 | 0全干声，127全湿声 |
| `sample_out` | signed 16 | 饱和后的PCM输出 |
| `out_valid` | 1 | 输出样本更新脉冲 |
| `input_overrun` | 1 | 忙时再次输入的粘滞错误标志 |

复位后模式为旁路，Cutoff为127，Resonance为0，Mix为127。旁路的湿声与输入逐位相同，
因此默认音频仍为原始信号。

## 3. 基础SVF

一次内部迭代使用：

```text
low  = low + f * band
high = input - low - damping * band
band = band + f * high
```

每个96 kHz外部样本执行两次迭代，相当于使用保持不变的输入在192 kHz下更新两次状态。
Cutoff采用16级/倍频程映射，端点约为`69.9 Hz`和`17.4 kHz`；Resonance把阻尼系数
从约`2.0`降低到`0.125`。低通、高通、带通和陷波共享同一组状态。

状态使用40位有符号、16位小数格式；系数使用18位`Q2.16`。一次输入约用14个
`50 MHz`周期，统一外壳再增加约1拍输出延迟。

## 4. Comb延迟线

Comb同时使用固定前馈和可调反馈结构：

```text
d = damp(delay[n-D])
delay[n] = sat(x[n] +/- Resonance * d)
wet[n]   = sat(x[n] +/- 0.5 * d)
```

- 延迟线深度：`2048 x 16 bit`，约`32 Kibit / 4 KiB`；
- 存储写有BSRAM推断属性，最终映射结果仍需以综合报告为准；
- 延迟长度：8～2047个96 kHz样本，约`83.3 us～21.32 ms`；
- 基础梳齿频率约为`96 kHz / D`，对应约`12 kHz～46.9 Hz`；
- Cutoff使用16级/倍频程的只移位映射，不在音频路径中使用除法器；
- 固定0.5倍前馈延迟负责形成基础梳齿，所以Resonance=0时Cutoff仍会改变音色；
- Resonance控制反馈峰值的锐度，127时反馈系数约为`0.981`，不会设置为1；
- 反馈路径使用固定1/4更新量的一阶低通阻尼；
- 写回BRAM前饱和到signed 16-bit，阻止二进制回绕；
- 上电不清空整块RAM，而用已写样本计数屏蔽未初始化区域，保留BSRAM推断条件。

Comb状态机按`读取 -> 阻尼 -> 反馈乘法 -> 写回`执行，统一外壳输出约在接受输入后的
5拍出现，远小于约521拍的样本间隔。第一版使用整数延迟，所以高频处的频率步进较粗，
暂未实现分数延迟插值和音频速率延迟调制。

## 5. Dry/Wet Mix

统一外壳在滤波核心之后执行：

```text
output = dry + (wet - dry) * Mix / 128
```

`Mix=0`和`Mix=127`具有专门旁路，分别逐位输出Dry和Wet，避免端点留下量化残差。
中间值使用一个有符号乘法和算术右移，结果饱和到16位。

Cutoff、Resonance和Mix都在顶层以96 kHz速率每次移动一级，完整0～127行程约
`1.32 ms`。切换模式时，顶层先把当前Mix降到0，再提交新模式并恢复目标Mix；最坏
完整切换约`2.65 ms`，避免两个不同滤波状态直接跳变。

## 6. MIDI控制

```text
CC42：Filter Mode，0～6
CC43：Filter Cutoff，0～127
CC44：Filter Resonance，0～127
CC45：Filter Mix，0～127
```

控制消息通过MIDI通道16发送。上位机连接串口后会发送四个滤波器参数的当前值。

## 7. RTL验证

`sim/run_global_filter_test.do`依次验证SVF核心和统一外壳：

- 正、负PCM旁路逐位通过；
- 低通直流收敛，高通和带通拒绝直流；
- 陷波保留直流；
- 低通抑制逐样本翻转信号，高通保留该信号；
- Mix=0、Mix=127端点和中间混合比例；
- Cutoff=0、64、127分别映射为2047、127、8点Comb延迟；
- Resonance=0时仍存在前馈梳状响应；
- 8点延迟下Comb+首个延迟项为正，Comb-首个延迟项为负；
- 正常输入节奏下没有`input_overrun`；
- SVF忙时重复输入会置位粘滞错误标志。

顶层回归另外验证CC42～45通过UART和MIDI解析后进入正确的目标寄存器。

## 8. 上板检查

1. 使用旁路确认声音与改动前一致；
2. 选择低通、Resonance=0、Mix=127，缓慢扫动Cutoff；
3. 分别验证高通、带通和陷波；
4. 固定中等Cutoff，逐渐提高Resonance；
5. 选择Comb+，先设Resonance=32、Mix=64，再扫动Cutoff；
6. 逐步提高Comb Resonance，确认没有持续溢出或异常啸叫；
7. 比较Comb+和Comb-的峰谷位置及音色差异；
8. 综合后确认2048×16延迟线确实映射到BSRAM，并检查DSP数量、WNS/TNS和警告；
9. 片上调试观察`fir_output_valid`、`global_filter_output_valid`、
   `global_filter_input_ready`和`global_filter_input_overrun`。

## 9. 已知限制

- Comb当前只有整数延迟，快速扫Cutoff可能产生台阶和咔哒声；
- Comb阻尼为固定值，尚未开放独立Damping参数；
- Comb是混音后的全局效果，各复音共享同一条延迟反馈路径；
- SVF和Comb的高反馈输出使用硬饱和，尚未加入模拟软削波；
- SVF截止刻度和Comb频率刻度是近似映射；
- 尚未完成本版本的高云综合、资源映射、布局布线和上板听感验证。
