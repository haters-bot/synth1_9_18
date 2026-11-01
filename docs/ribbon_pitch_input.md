# 六通道电阻滑条音高输入

## 1. 第一版目标

第一版使用一片ADS1256轮询六条电阻滑条，每条滑条独立产生Gate和连续音高。
滑条触摸时分配一次声部，滑动期间只更新已有声部的DDS相位步进，松手后进入
现有ADSR Release。它不会把每个ADC样本转换成新的MIDI Note On。

暂定音域如下：

| ADS1256通道 | Source ID | 音域 |
|---:|---:|---|
| AIN0 | 0 | C1～C3 |
| AIN1 | 1 | C2～C4 |
| AIN2 | 2 | C3～C5 |
| AIN3 | 3 | C4～C6 |
| AIN4 | 4 | C5～C7 |
| AIN5 | 5 | C6～C8 |

六条全部触摸且Unison=4时，每个OSC Bank占用24个任务，能够放入当前32槽位。
OSC A和OSC B各有独立32槽Bank，因此两者同时开启仍是每组24/32，而不是把48个
任务塞进同一个Bank。

## 2. 数据通路

```text
ADS1256 AIN0～AIN5
       |
ads1256_scanner
  15 kSPS总采样率，六通道约636次/秒/通道
       |
ribbon_pitch_processor
  三点中值 -> 自适应一阶低通 -> Gate迟滞 -> 两八度Q7.8音高
       |
ribbon_pitch_to_step
  相邻半音freq_lut查表和8位分数插值
       |
oscillator_task_scheduler
  Source ID拥有一组Unison槽位，滑动只更新step
       |
OSC A/B TDM Bank
```

`ribbon_controller_6ch.v`封装前三个模块。其连续事件输出必须同时送到OSC A和OSC B
调度器。`scheduler_ready`应满足：两个调度器都空闲，并且当前拍没有优先处理的MIDI
音符事件。这样一个滑条事件要么被两组同时接收，要么继续保持，不会只更新其中一组。

## 3. ADS1256设置

- 主时钟：模块上的7.680 MHz晶振；
- FPGA SPI：1 MHz，SCLK空闲低，在下降沿交换数据；
- STATUS：ACAL开启，输入缓冲关闭；
- PGA：1；
- DRATE：15 kSPS；
- AINCOM：接模拟地；
- 扫描顺序：AIN0～AIN5；
- 每次切换通道后发送`SYNC`、`WAKEUP`，等待下一次DRDY再读取，保证结果已建立。

默认ADC码值按VREF=2.5 V、双极性满量程正端+5 V估算：

| 项目 | 电压 | 默认码值 |
|---|---:|---:|
| 松手 | 约0.09 V | 仅用于观察，不直接映射音高 |
| Gate Off阈值 | 0.30 V | 503316 |
| Gate On阈值 | 0.55 V | 922747 |
| 有效音高左端 | 0.84 V | 1409286 |
| 有效音高右端 | 2.30 V | 3858759 |

如果实际VREF或ADS1256模块前端不同，必须用板上原始码重新校准这些参数，不能只按
电压表读数修改。最终版本应为六条滑条分别保存左右端校准值。

## 4. Gate和滤波

- Gate On：连续3个本通道样本高于阈值；
- Gate Off：连续4个本通道样本低于阈值；
- 松手时保留最后有效音高，只发送Gate Off，避免出现向低音滑落；
- 先做三点中值滤波，去除偶发尖峰；
- 一阶低通根据移动速度采用`1/4`、`1/8`或`1/16`更新；
- 音高变化小于Q8格式的4 LSB时不发送，约为1.56音分死区。

实测静态波动约3.5 mV峰峰值，对两八度范围约等于5.75音分。当前滤波参数是安全
起点，板测时应同时观察稳定性和滑动延迟，再决定是否收紧死区。

## 5. 调度语义

`oscillator_task_scheduler`新增连续音高事件：

- 首次Gate On：按当前Unison数量分配任务并触发Attack；
- 同Source音高更新：更新全部成员的base step和Detune数据，不清相位、不重触发ADSR；
- Gate Off：同Source全部成员进入Release；
- Release未完成时再次触摸：重新触发该Source的Attack；
- MIDI任务仍按MIDI音符号拥有槽位，滑条任务按Source ID拥有槽位，两者不会因同音高
  被误认为同一个声部。

## 6. 当前集成边界

RTL处理链、调度器接口和仿真已经加入工程。由于ADS1256的`DRDY、DOUT、DIN、SCLK、
CS、RESET`尚未指定FPGA引脚，顶层目前将连续音高入口固定为0，保持现有MIDI板测和
布局布线引脚不变。确定六个SPI引脚后，再例化`ribbon_controller_6ch`并补充CST约束。

供电建议仍是AVDD约5 V、DVDD 3.3 V、VREF 2.5 V，并与FPGA共地。外置电源的模拟地
回流应避开功放和扬声器大电流路径。

## 7. 验证

- `sim/run_ads1256_scanner_test.do`：初始化流程和AIN0～AIN5扫描顺序；
- `sim/run_ribbon_pitch_test.do`：滤波、Gate迟滞、两八度映射和相位步进转换；
- `sim/run_task_scheduler_test.do`：连续音高分配、滑动更新和释放；
- 原TDM、顶层MIDI和完整顶层展开回归保持通过。

当前只做RTL编译和ModelSim功能仿真，没有运行Gowin综合或布局布线。
