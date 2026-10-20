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
| `cutoff_control_q8` | 15 | Q7.8格式；SVF使用整数部分，Comb同时使用整数与小数部分 |
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

Comb同时使用等权前馈和可调反馈结构。目标延迟为`D + t`时，单口RAM依次读取
`D-1`、`D`、`D+1`和`D+2`四个历史样本，再执行Catmull-Rom三次插值：

```text
ym1 = delay[n-(D-1)]
y0  = delay[n-D]
y1  = delay[n-(D+1)]
y2  = delay[n-(D+2)]
d   = y0 + 0.5*t*(a2 + t*(a1 + t*a0))
a0  = -ym1 + 3*y0 - 3*y1 + y2
a1  = 2*ym1 - 5*y0 + 4*y1 - y2
a2  = -ym1 + y1
df = damp(d)
delay[n] = sat(x[n] +/- Resonance * df)
wet[n]   = (x[n] +/- d) / 2
```

- 延迟线深度：`2048 x 16 bit`，约`32 Kibit / 4 KiB`；
- 存储写有BSRAM推断属性，最终映射结果仍需以综合报告为准；
- 延迟长度：约8.375～2045个96 kHz样本，约`87.2 us～21.30 ms`；
- 基础梳齿频率约为`96 kHz / D`，对应约`12 kHz～46.9 Hz`；
- Cutoff先用16级/倍频程的只移位表映射为Q12.8延迟，再在四点三次插值器中实现分数延迟；
- 前馈直接读取未经阻尼的延迟样本，输入与延迟各占0.5，可形成完整深度的梳齿；
- Resonance=0时理论陷波点能够降到零，Cutoff会明显移动峰谷位置；
- Resonance控制反馈峰值的锐度，127时反馈系数约为`0.981`，不会设置为1；
- 只有反馈路径使用固定1/4更新量的一阶低通阻尼；
- 写回BRAM前饱和到signed 16-bit，阻止二进制回绕；
- 上电不清空整块RAM，而用已写样本计数屏蔽未初始化区域，保留BSRAM推断条件。

Comb状态机按`读取四点 -> 计算系数 -> 三次分时乘加 -> 阻尼 -> 反馈乘法 -> 写回`执行，
统一外壳输出约在接受输入后的16拍出现，远小于约521拍的样本间隔。新增的第一拍用于
锁存Cutoff映射结果并切断延迟地址计算长路径。四个读取周期与
写入周期共用一个RAM端口；三次插值乘法也复用一条乘法路径。

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
CC42：Filter Mode，0～6
CC43：Filter Cutoff，0～127
CC44：Filter Resonance，0～127
CC45：Filter Mix，0～127
CC48：Master Level，0～127
```

控制消息通过MIDI通道16发送。上位机连接串口后会发送滤波器参数和Master Level的当前值。
静态Cutoff继续使用CC43；通用LFO通过SysEx发送三点、两段曲率、速率以及8条
调制路由，曲线随后由FPGA以96 kHz实时生成。每条路由具有独立的双极性Depth，
可把同一个LFO分配给振荡器或滤波器参数。Cutoff路由用于Comb+和Comb-时，FPGA
内部按`141/256`缩放调制偏移，使最大实际深度约为70；其他滤波模式保持完整范围。

## 7. RTL验证

`sim/run_global_filter_test.do`依次验证SVF核心和统一外壳：

- 正、负PCM旁路逐位通过；
- 低通直流收敛，高通和带通拒绝直流；
- 陷波保留直流；
- 低通抑制逐样本翻转信号，高通保留该信号；
- Mix=0、Mix=127端点和中间混合比例；
- Cutoff=0、64、127分别映射为2045.0、127.9375、8.375点Comb延迟；
- 半个CC刻度的映射结果位于相邻两个整数CC映射结果之间；
- Resonance=0时，8.375点延迟的12000幅度脉冲产生约
  `-440、4365、2338、-264`的四抽头湿输出；
- 把Cutoff切换到127点延迟后，第8个样本不再出现该延迟项；
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

- Catmull三次插值比两点线性插值更能保持高频，但会产生很小的前后振铃和过冲；
- 三点LFO只支持两段三次平滑曲线，尚不支持任意数量控制点；
- Comb阻尼为固定值，尚未开放独立Damping参数；
- Comb是混音后的全局效果，各复音共享同一条延迟反馈路径；
- SVF和Comb的高反馈输出使用硬饱和，尚未加入模拟软削波；
- SVF截止刻度和Comb频率刻度是近似映射；
- 尚未完成本版本的高云综合、资源映射、布局布线和上板听感验证。
