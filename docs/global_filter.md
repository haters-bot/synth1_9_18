# 96 kHz全局滤波器

## 1. 数据位置

```text
双振荡器TDM混音（768 kHz）
        |
8倍降采样FIR（768 kHz -> 96 kHz）
        |
global_filter（96 kHz）
   `-- global_svf_filter
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
| 5～7 | 保留 | 回退至旁路 |

公共接口：

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `sample_in` | signed 16 | FIR输出PCM |
| `in_valid` | 1 | 输入样本有效脉冲 |
| `in_ready` | 1 | 可以接受新样本 |
| `filter_mode` | 3 | 上表中的滤波模式 |
| `cutoff_control_q8` | 15 | Q7.8格式；SVF使用整数部分 |
| `resonance_control` | 7 | SVF共振 |
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

## 4. 已移除梳状滤波

全局梳状滤波器已移除。历史模式5、6以及其他未定义模式回退至旁路。

## 5. Dry/Wet Mix

统一外壳在滤波核心之后执行：

```text
output = dry + (wet - dry) * Mix / 128
```

`Mix=0`和`Mix=127`具有专门旁路，分别逐位输出Dry和Wet，避免端点留下量化残差。
中间值使用一个有符号乘法和算术右移，结果饱和到16位。

Cutoff在顶层以Q7.8保存。每次收到新目标后，顶层在512个96 kHz样本内线性插值，
过渡时间约`5.33 ms`。商和余数通过Bresenham方法分配，不需要乘法器或除法器；
中途收到新目标时从当前值重新起步。
Resonance和Mix仍以每个样本一级平滑，完整行程约`1.32 ms`。切换模式时，顶层先把
当前Mix降到0，再提交新模式并恢复目标Mix；最坏完整切换约`2.65 ms`。

## 6. MIDI控制

```text
CC42：Filter Mode，0～4（5～127回退旁路）
CC43：Filter Cutoff，0～127
CC44：Filter Resonance，0～127
CC45：Filter Mix，0～127
CC48：Master Level，0～127
```

控制消息通过MIDI通道16发送。上位机连接串口后会发送滤波器参数和Master Level的当前值。
静态Cutoff继续使用CC43；通用LFO通过SysEx发送三点、两段曲率、速率以及8条
调制路由，曲线随后由FPGA以96 kHz实时生成。每条路由具有独立的双极性Depth，
可把同一个LFO分配给振荡器或滤波器参数。所有有效滤波模式均使用完整调制范围。

## 7. RTL验证

`sim/run_global_filter_test.do`依次验证SVF核心和统一外壳：

- 正、负PCM旁路逐位通过；
- 低通直流收敛，高通和带通拒绝直流；
- 陷波保留直流；
- 低通抑制逐样本翻转信号，高通保留该信号；
- Mix=0、Mix=127端点和中间混合比例；
- 已移除的模式5、6在滤波器接口回退旁路；
- 正常输入节奏下没有`input_overrun`；
- SVF忙时重复输入会置位粘滞错误标志。

顶层回归另外验证CC42～45通过UART和MIDI解析后进入正确的目标寄存器。

## 8. 上板检查

1. 使用旁路确认声音与改动前一致；
2. 选择低通、Resonance=0、Mix=127，缓慢扫动Cutoff；
3. 分别验证高通、带通和陷波；
4. 固定中等Cutoff，逐渐提高Resonance；
5. 检查Mix端点和模式切换，并观察`global_filter_input_ready`、`global_filter_output_valid`及`global_filter_input_overrun`。

## 9. 已知限制

- SVF高共振输出使用硬饱和；截止刻度为近似映射。
- 资源与时序改善需要重新综合布线确认。
