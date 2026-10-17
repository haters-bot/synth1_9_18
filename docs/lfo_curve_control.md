# FPGA三点Cutoff LFO

## 1. 结构

Cutoff LFO已经从Python上位机移入FPGA。上位机只在设置发生变化时发送配置，
`filter_curve_lfo`在每个96 kHz `sample_tick`上推进相位并计算Cutoff。

```text
上位机：速率、深度、三个点、两个曲率
                    │ SysEx，仅配置变化时发送
                    ▼
highres_parameter_parser
                    ▼
filter_curve_lfo影子寄存器 ── commit ──► 活动配置
                    ▼
两段局部相位累加器 + 曲率插值 + 深度缩放
                    ▼
global_filter.cutoff_control_q8
```

静态Cutoff仍使用控制通道16的`CC43`，并先经过512个96 kHz样本的线性平滑。
LFO关闭或深度回到0后，滤波器重新使用该静态值。

## 2. 三个控制点

第一版固定为三个点：

- `P0`时间固定为0，电平范围为-1～+1；
- `P1`时间可在0.125～0.875周期内移动，电平范围为-1～+1；
- `P2`时间固定为1，电平范围为-1～+1；
- `C0`控制P0到P1的曲率；
- `C1`控制P1到P2的曲率。

“首尾连续”默认开启，使P2电平跟随P0。关闭后可以产生周期边界跳变，但梳状滤波
可能把该跳变转换成明显的瞬态和宽带边带。

曲率为0时是线性插值。正曲率向`t²`混合，负曲率向`1-(1-t)²`混合：

```text
basis = curve >= 0 ? t² : 1-(1-t)²
weight = t + (basis-t) * abs(curve)
value = start + (end-start) * weight
```

Python编辑器和FPGA使用同一个公式，因此界面预览与RTL计算一致。

## 3. 相位与速率

每一段有独立的24位局部相位累加器。上位机根据LFO速率和P1时间计算两个14位步进：

```text
step0 = round(rate_hz * 2^24 / (96000 * middle_time))
step1 = round(rate_hz * 2^24 / (96000 * (1-middle_time)))
```

P1时间限制为0.125～0.875，使0.1～10 Hz范围内两个步进都不超过14位。上位机发送
的是配置系数；每个音频样本的LFO值仍由FPGA实时生成。

## 4. SysEx配置协议

每个字段沿用六字节非商业SysEx帧：

```text
F0 7D parameter_id value_msb value_lsb F7
```

`value_msb`和`value_lsb`组成14位无符号值。参数编号如下：

| ID | 字段 | 编码 |
|---:|---|---|
| 16 | Enable | 0或1 |
| 17 | Segment 0 phase step | 14位整数 |
| 18 | Segment 1 phase step | 14位整数 |
| 19 | Depth | Q7.7 |
| 20 | P0 level | 双极性Q1.13偏移编码 |
| 21 | P1 level | 双极性Q1.13偏移编码 |
| 22 | P2 level | 双极性Q1.13偏移编码 |
| 23 | C0 | 双极性Q1.13偏移编码 |
| 24 | C1 | 双极性Q1.13偏移编码 |
| 25 | Commit | 数值忽略 |

双极性值按`encoded=round((value+1)*8191.5)`编码。FPGA先把ID 16～24写入影子
寄存器；收到ID 25后全部复制到活动寄存器，避免串口逐字段传输时出现半更新状态。

## 5. 平滑和延迟

- LFO计算使用五级50 MHz流水线，结果在`sample_tick`后约100 ns得到；
- Depth以每个96 kHz样本16个Q7.7最低位渐变，全范围约10.6 ms；
- Enable从0变1时相位从P0重新开始；
- Disable后Depth先平滑回零，再把相位复位到P0；
- 最终Cutoff限制在0～127，对应滤波器的Q7.8控制输入。

## 6. 与旧实现的区别

旧实现由Python每5 ms发送一个具体Cutoff值，FPGA在相邻目标之间做512样本线性插值。
该路径受桌面定时器抖动和控制点斜率突变影响，已经删除。现在串口负载只发生在参数
变化时，LFO运行不依赖上位机刷新周期。
