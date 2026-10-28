> 2026-10-28更新：LFO已切换至[七节点Hermite／53目标V2协议](lfo_v2_integration.md)，新配置ID48..126。下文三点／8路由内容是旧版记录。新增静态CC87/88控制OSC A Phase/Rand，CC89/90控制OSC B Phase/Rand。控制口仍为C19，实体键盘口为E19。

# MIDI演奏与合成参数控制协议

## 1. 设计目标

当前验证阶段只有一个UART输入，因此演奏数据和合成参数共用一条串行链路。
最终系统计划使用两个物理输入：MIDI键盘负责音符与力度，外部控制单片机负责
Pan、WT Position、Detune、Unison等合成参数。

本协议使用两级解耦：

1. UART与MIDI解析层只负责恢复消息、消息类型和通道号；
2. `synth_control_router`根据通道和CC编号，把消息转换为内部音符事件或参数寄存器。

因此以后增加第二个UART时，振荡器、声部调度器和参数寄存器接口不需要重新设计。

## 2. 当前数据流

```text
Python测试工具
    |
    | 31250 bit/s，UART 8N1，原始MIDI字节
    v
uart_rx
    |
    | byte_data + byte_valid
    v
midi_note_parser
    |
    | Note事件 / Control Change事件 / MIDI通道
    v
synth_control_router
    |                         |
    | 通道1 Note事件          | 通道16 CC参数
    |                         |-- OSC A参数寄存器
    |                         |-- OSC B参数寄存器
    |                         `-- 全局Pan
    |                         |
    +------------+------------+
                 |
        +--------+--------+
        v                 v
OSC A调度器/Bank     OSC B调度器/Bank
        |                 |
        +--------+--------+
                 |
       开关/Level平滑增益与A/B混音
                 |
            固定6 dB余量
                 |
             共享FIR
                 |
          96 kHz全局滤波器
```

## 3. UART与MIDI消息格式

UART使用`8N1`：1个起始位、8个数据位、无校验、1个停止位。板级默认波特率是
`31250 bit/s`。一个UART字节占10个线路位，因此发送一个字节约需`320 us`。

当前使用的MIDI通道消息均为3字节：

```text
状态字节  数据字节1  数据字节2
```

状态字节的高4位表示消息类型，低4位表示通道编号减1：

```text
8n：Note Off
9n：Note On
Bn：Control Change
```

例如：

```text
90 3C 64    通道1，中央C按下，力度100
80 3C 00    通道1，中央C松开
BF 14 55    通道16，OSC A的CC20，WT Position=85
```

三个完整字节需要约`0.96 ms`。使用Running Status时，同类型且同通道的后续消息
可省略状态字节，每次参数更新只需两个数据字节，约`0.64 ms`。解析器允许
`F8`到`FF`的实时消息插入数据流，而不破坏Running Status。

## 4. 通道分工

| MIDI通道 | 内部编号 | 用途 | 当前路由规则 |
|---|---:|---|---|
| 1 | 0 | Note On、Note Off、力度 | 允许进入声部调度器 |
| 16 | 15 | OSC A/B及全局参数 | 允许写入参数寄存器 |
| 其他 | 1～14 | 保留 | 当前忽略 |

通道分工实现的是同一字节流中的逻辑解耦。正式硬件不能把MIDI键盘和控制单片机的
两个TX引脚直接并联；最终版本应使用两个UART接收器，或者由外部控制单片机先完成
消息合并。

## 5. Control Change映射

| 目标 | 参数 | 通道 | CC编号 | 数据范围 | 复位值 |
|---|---:|---:|---:|---:|---|
| 全局 | Pan | 16 | 10 | 0～127 | 64 |
| OSC A | WT Position | 16 | 20 | 0～127 | 0 |
| OSC A | Waveform | 16 | 21 | 0～127 | 64，即方波 |
| OSC A | Detune | 16 | 22 | 0～127 | 64 |
| OSC A | Unison | 16 | 23 | 1～8 | 顶层参数决定 |
| OSC A | Attack | 16 | 24 | 0～127 | 27 |
| OSC A | Decay | 16 | 25 | 0～127 | 54 |
| OSC A | Sustain | 16 | 26 | 0～127 | 89 |
| OSC A | Release | 16 | 27 | 0～127 | 67 |
| OSC B | WT Position | 16 | 28 | 0～127 | 0 |
| OSC B | Waveform | 16 | 29 | 0～127 | 64，即方波 |
| OSC B | Detune | 16 | 30 | 0～127 | 64 |
| OSC B | Unison | 16 | 31 | 1～8 | 顶层参数决定 |
| OSC B | Attack | 16 | 32 | 0～127 | 27 |
| OSC B | Decay | 16 | 33 | 0～127 | 54 |
| OSC B | Sustain | 16 | 34 | 0～127 | 89 |
| OSC B | Release | 16 | 35 | 0～127 | 67 |
| OSC A | Enable | 16 | 36 | 0=关闭，1～127=开启 | 开启 |
| OSC B | Enable | 16 | 37 | 0=关闭，1～127=开启 | 开启 |
| OSC A | Warp Mode | 16 | 38 | 0～11，见下表 | 0 |
| OSC A | Warp Amount | 16 | 39 | 0～127 | 0 |
| OSC B | Warp Mode | 16 | 40 | 0～11，见下表 | 0 |
| OSC B | Warp Amount | 16 | 41 | 0～127 | 0 |
| 全局 | Filter Mode | 16 | 42 | 0～6，见第9节 | 0，旁路 |
| 全局 | Filter Cutoff | 16 | 43 | 0～127 | 127 |
| 全局 | Filter Resonance | 16 | 44 | 0～127 | 0 |
| 全局 | Filter Mix | 16 | 45 | 0～127 | 127 |
| OSC A | Level | 16 | 46 | 0～127 | 127 |
| OSC B | Level | 16 | 47 | 0～127 | 127 |
| 全局 | Master Level | 16 | 48 | 0～127 | 127 |
| OSC A | DDR波表编号 | 16 | 49 | 0～15 | 0 |
| OSC B | DDR波表编号 | 16 | 50 | 0～15 | 0 |
| 全局效果 | Mode | 16 | 51 | 0～3 | 0，旁路 |
| Delay | Time | 16 | 52 | 0～127 | 64 |
| Delay | Feedback | 16 | 53 | 0～127 | 48 |
| Delay | Mix | 16 | 54 | 0～127 | 64 |
| Reverb | Size | 16 | 55 | 0～127 | 64 |
| Reverb | Decay | 16 | 56 | 0～127 | 72 |
| Reverb | Mix | 16 | 57 | 0～127 | 48 |
| 演奏音高 | Vibrato Enable | 16 | 82 | 0=关闭，1～127=开启 | 关闭 |
| 演奏音高 | Vibrato Rate | 16 | 83 | 0～127，约0.1～12.1 Hz | 52 |
| 演奏音高 | Vibrato Depth | 16 | 84 | 0～127，最大约正负100 cent | 0 |
| 演奏音高 | Portamento Enable | 16 | 85 | 0=关闭，1～127=开启 | 关闭 |
| 演奏音高 | Portamento Time | 16 | 86 | 0～127，见下文 | 80 |

两组`Unison`都把0限制为1，把大于8的数值限制为8。A/B的Detune、Unison、
波形、WT Position和ADSR寄存器彼此独立；同一个Note事件会同时送到两个调度器。

Enable是音频开关，不会清除调度器槽位、相位或包络状态。关闭的振荡器仍继续处理
任务，只是其混音增益平滑降到0；重新开启后从当前状态恢复。两路都开启时各使用0.5
增益，只开启一路时该路使用1.0增益。增益以96 kHz速率逐级变化，完整切换约2.67 ms，
用来减少开关造成的咔哒声。

ADSR的阶段状态仍由FPGA按逻辑声部独立维护。外部单片机只需要发送四个参数，不需要
持续发送32个声部的实时电平。A、D、R每增加8个控制值，阶段时间约翻倍；详细映射和
定点算法见`docs/adsr_envelope.md`。

两组Waveform都使用相同的数值编码：

```text
CC21或CC29 =   0～31：正弦波
CC21或CC29 =  32～63：三角波
CC21或CC29 =  64～95：方波
CC21或CC29 =  96～126：锯齿波
CC21或CC29 =       127：Acid多帧波表
```

## 6. Detune计算原理

每组调度器在收到Note On后，先从`freq_lut`取得该音符在`768 kHz`内部采样率下的
32位相位步进`base_step`。N个Unison成员的位置定义为：

```text
position = 2 * member_index - (N - 1)
```

因此不同成员数的位置为：

```text
N=1：  0
N=2： -1, +1
N=3： -2,  0, +2
N=4： -3, -1, +1, +3
```

旧版本的一个position单位约为`2.006 cents`。当前CC22按下式缩放这个单位：

```text
实际频差 = 原频差 * detune_amount / 64
```

由此得到：

- `CC22=0`：所有Unison成员同频；
- `CC22=64`：保持加入可调Detune之前的默认间距；
- `CC22=127`：约为默认间距的1.984倍。

Unison成员位置在Note On到达时锁存，Detune深度则由活动槽位实时读取。改变Detune
不会重建槽位或复位相位。Portamento开启时，实时Detune偏移会根据共享滑音基础频率
重新计算，因此OSC A/B以及各Unison成员在跨音程滑动时仍保持相对音程关系。

### 6.1 Vibrato与单音Legato Portamento

Vibrato使用FPGA内部256点正弦表，以96 kHz控制速率更新相位。`CC84=127`时深度约为
正负一个半音；它产生有符号Q16频率比例偏移，并在TDM核心的实时Detune路径中改变
`phase_step`，不会清零相位或重新触发包络。Portamento关闭时，该比例同样可以作用于
多个复音槽位。

Portamento开启后，最多保存8个同时按住的音符，并按“最后按下音符优先”工作：

1. 第一个Note On建立单音任务并触发包络；
2. 继续按下其他音符只更新目标音高，不重新分配槽位、不重触发包络；
3. 松开当前最高优先级音符时，目标返回仍按住的上一个音符；
4. 最后一个音符松开时才向A/B两个调度器发送Note Off。

OSC A与OSC B共享同一个Q7.16滑音音高和`glide_base_step`，之后才分别叠加各自的
Unison/Detune，因此两路不会因独立舍入或独立调度而产生滑音不同步。`CC86`采用固定
音程速率分段；下面的时间表示跨越一个八度的大约耗时：

```text
  0：立即到达
  1～15：5 ms       16～31：10 ms
 32～47：20 ms      48～63：50 ms
 64～79：100 ms     80～95：250 ms
 96～111：500 ms   112～119：1 s
120～127：2 s
```

除了通道16的自定义控制，演奏通道1也兼容常见MIDI映射：`CC1`控制Vibrato Depth并
自动开关Vibrato，`CC5`控制Portamento Time，`CC65`以64为阈值控制Portamento开关。
为避免切换单音/复音所有权时听到Release尾音改变，建议在没有按键时切换Portamento。

## 7. WT Position数据通路

Acid模式使用16帧、每帧256个16位采样。7位WT Position拆成：

```text
frame_index    = wt_position[6:3]   // 0～15
frame_fraction = wt_position[2:0]   // 相邻帧之间8级插值
```

一次振荡器读取需要获得当前帧和下一帧的同一相位采样，再做线性插值：

```text
y = A + (B - A) * frame_fraction / 8
```

`osc_a/b_wt_position_target`不会直接驱动波表地址。顶层在每个96 kHz采样边界最多向目标移动
一级，完整0～127行程约为`127 / 96000 = 1.32 ms`。TDM核心又在每个768 kHz批次
开始时锁存一次当前位置，使同一批次内的全部槽位使用同一个参数值。

同步ROM增加一拍读取延迟。核心现在使用“发出槽位地址”和“提交槽位结果”两级流水：
第N拍向ROM发出槽位k的当前帧与下一帧地址，第N+1拍取得两个采样并提交槽位k，
同时发出槽位k+1。流水线填满后吞吐率保持每拍一个槽位。1引擎×32槽位的RTL压力
测试能在约65拍的768 kHz周期预算内完成。当前板级配置为两个独立Bank，每个Bank
使用1个实体引擎×32槽位，因此共有2个实体振荡器、64个振荡器任务槽位。

ROM使用推断式双读口存储和`$readmemh`初始化。是否真正映射到Gowin BSRAM、是否复制
存储体以实现两个读口，仍需用户运行综合后从资源报告确认。

## 8. Warp地址变换

Warp位于相位累加器与波表地址之间。32位相位累加器仍按MIDI音高连续累加，
Warp只变换送入波表的高8位地址，因此基音调度、逻辑声部状态和TDM槽位周期均不变。

每个OSC拥有独立的`Warp Mode`和`Warp Amount`。TDM核心在一个768 kHz批次开始时锁存
这两个参数，使同一批次内全部槽位使用一致的地址变换。组合地址变换不会给BRAM读取
流水增加拍数。

`Warp Amount`与WT Position一样在每个96 kHz边界最多向目标移动一级，完整行程约
`1.32 ms`。这能减小上位机滑块或外部控制器直接跳变造成的波形不连续和咔哒声。

当`Warp Mode`在两个非零模式之间切换时，顶层不会直接替换地址映射。它先把当前
`Warp Amount`逐级降到0，在原始地址直通点切换模式，再逐级升到目标深度。这样一次
最坏情况的模式切换约需`2 * 127 / 96000 = 2.65 ms`。关闭Warp时只需完成前半段；
关闭期间内部深度保持为0，而控制寄存器仍保存用户设置的目标深度。

| 编号 | 模式 | 地址变换效果 |
|---:|---|---|
| 0 | Off | 原地址直通 |
| 1 | PWM | 移动波形半周期分界，方波表现为占空比变化 |
| 2 | Sync | 一个基准周期内读取1～8个波表周期 |
| 3 | Bend + | 将波表地址向周期前部弯曲 |
| 4 | Bend - | 将波表地址向周期后部弯曲 |
| 5 | Bend +/- | 四段对称S形地址弯曲 |
| 6 | Asym + | 只弯曲前半周期 |
| 7 | Asym - | 只弯曲后半周期 |
| 8 | Asym +/- | 两个半周期按相反结构弯曲 |
| 9 | Flip | 从正向读取逐渐过渡到反向读取 |
| 10 | Mirror | 最大深度下先正向、再反向读取一个波表周期 |
| 11 | Quantize | 逐步清除地址低位，形成相位台阶 |

PWM模式使用分段线性地址映射：

```text
distance = raw[7] ? 255 - raw : raw
offset   = distance * amount / 128
address  = raw + offset
```

`amount=0`时地址完全不变；`amount=127`时，方波的正半周占空比从约50%缩短到约25%。
同一个变换也可以作用于其他波表，但听感是相位弯曲，不一定等同于传统脉冲宽度调制。

Sync模式把一个基准周期内的波表读取次数从1倍连续提高到8倍：

```text
factor_q4 = 16 + floor(amount * 113 / 128)
address   = floor(raw * factor_q4 / 16) mod 256
```

`amount=0`对应1倍，`amount=127`对应8倍。非整数倍率会在基准相位回绕时产生硬同步式
跳变和新谐波。768 kHz内部采样与后级共享FIR会降低混叠，但高Sync倍率与高音区仍可能
产生超过内部Nyquist频率的成分，后续可根据实测增加倍率限制或按音高限制深度。

Bend、Asym、Flip和Mirror先构造最大深度的目标地址，再用`Warp Amount`从原始地址
线性靠近目标地址。深度0严格旁路，深度127使用完整目标曲线。各模式共享一个有符号
乘法器，不会随模式数量增加而继续复制DSP。

Quantize不使用乘法器。`Warp Amount[6:4]`决定清除1～7个地址低位；最大深度只保留
地址最高位。该模式会产生较强的新谐波，因此高音区可能出现比Bend和Asym更明显的混叠。

## 9. 全局滤波器

全局滤波器位于8倍降采样FIR之后、I2S之前，以96 kHz采样率工作。它不会占用
振荡器TDM槽位，也不会改变768 kHz波表生成和抗混叠路径。

模式编码如下：

```text
CC42 = 0：旁路
CC42 = 1：低通
CC42 = 2：高通
CC42 = 3：带通
CC42 = 4：陷波
CC42 = 5：梳状正反馈
CC42 = 6：梳状负反馈
```

滤波器采用两次内部迭代的状态变量结构。每个96 kHz输入样本在50 MHz时钟域内约用
14拍完成，远小于相邻样本约521拍的间隔。低通、高通、带通和陷波共享同一组内部状态以及
一个分时复用乘法器。

`Cutoff`使用16级/倍频程的近似指数映射，`0～127`约对应`70 Hz～17.3 kHz`。
`Resonance`从高阻尼逐渐过渡到低阻尼，`0`基本无共振，`127`为当前允许的最大共振。

Comb模式使用2048×16位循环延迟线。Cutoff先映射为约8.375～2045点的Q12.8延迟，
单口RAM分四拍读取`D-1、D、D+1、D+2`，并用分时乘法执行Catmull-Rom三次插值。
Resonance映射为最大约0.981的反馈系数；正负
模式决定反馈符号。反馈路径含固定一阶低通阻尼和16位饱和保护。输出采用当前输入与
插值后的延迟样本等权相加或相减，因此Resonance=0时也能形成完整深度的梳齿，Cutoff
会连续移动梳齿位置。该延迟线带BSRAM推断属性，实际资源映射需要通过综合报告确认。

静态Cutoff在顶层使用Q7.8状态。每次收到CC43后，在512个96 kHz样本内线性插值到
新目标，过渡时间约5.33 ms；通用FPGA LFO可通过调制矩阵在该静态值上叠加调制；
Resonance和Mix仍以每个样本一级平滑，完整行程约1.32 ms。Mix=0为全干声，Mix=127
为全湿声。模式切换时先把Mix退到0，提交新模式后再恢复，避免不同滤波状态直接跳变。

旁路模式保持输入样本数值不变，但SVF状态仍在后台更新。因此重新开启基础滤波器时，
不会从全零状态重新充电。

## 10. 全局效果器

效果器位于全局滤波器之后、Master Level之前，以96 kHz处理整机混音。处理顺序为
Distortion、Phaser、Chorus、Delay/Reverb、Compressor。CC51继续选择旁路、Delay、
Reverb或两者并联；CC52～57控制时间、反馈、空间尺寸、衰减和Dry/Wet。
Delay使用32768点循环缓冲，范围约5.0～335.7 ms。Reverb由4条低通反馈梳状线和
2条全通线构成。具体定点结构、延迟长度和RAM预算见`docs/global_effects.md`。

新增效果器使用以下独立CC，因此可以同时开启：

| CC | 参数 | 默认值 |
|---:|---|---:|
| 58 | Distortion Enable | 0 |
| 59 | Distortion Type：0 Soft、1 Hard、2 Foldback | 0 |
| 60～62 | Distortion Drive、Tone、Mix | 32、127、64 |
| 63 | Chorus Enable | 0 |
| 64～68 | Chorus Rate、Depth、Delay、Feedback、Mix | 20、32、48、20、64 |
| 69 | Phaser Enable | 0 |
| 70～74 | Phaser Rate、Depth、Center、Feedback、Mix | 20、48、64、20、64 |
| 75 | Compressor Enable | 0 |
| 76～81 | Threshold、Ratio、Attack、Release、Makeup、Mix | 96、64、20、80、0、127 |

## 11. Pan的当前边界

协议层已经保存`pan_target[6:0]`，默认值64表示中央。当前`i2s_tx`仍把同一份单声道
样本复制到左右声道，因此CC10暂时不会改变音频。

接入立体声混音时建议先使用平滑后的左右增益，再分别送入I2S左右声道。参数目标值
不能直接跳变，否则乘法增益的突变可能产生咔哒声。MAX98357A是单声道功放，实际听到
左声道、右声道或混合结果还取决于模块的声道选择配置。

## 12. 上位机应用方法

`tools/midi_uart_sender.py`已经按本协议更新：

- “演奏通道”只影响Note On和Note Off，正常测试保持通道1；
- OSC A/B及全局参数固定通过通道16发送；
- 连接串口后自动发送Pan、Master Level以及OSC A/B各自的Enable、Level、Waveform、Warp、WT Position、Detune、Unison和ADSR；
- 音色预设下拉框可一次载入并发送完整参数组合；当前包含使用DDR波表8的合成钢琴和使用DDR波表9的合成提琴，切换预设时会关闭旧LFO路由，避免残留调制影响新音色；
- 全局滤波器面板通过CC42～45控制模式、Cutoff、Resonance和Mix；
- 全局效果器面板通过CC51～57控制Delay和Reverb，通过CC58～81独立控制Distortion、
  Chorus、Phaser和Compressor；
- 上位机带三个独立FPGA通用LFO，每个都可调`0.1～10 Hz`速率、三个控制点和两段独立曲率；
  8条共享路由可独立选择LFO 1/2/3，并分别指向OSC A/B的WT Position、Warp Amount、Level以及Pan、Filter
  Cutoff、Resonance和Mix，每条路由具有独立的`-127～+127`深度；
- 参数滑块在释放鼠标时发送一次，避免测试阶段用大量连续CC占满31250 bit/s链路。

原来由Python每5 ms发送CC39或CC41的临时Warp LFO已经删除。现在曲线与路由只在
配置变化时发送一次，运行时不占用串口带宽，也不受桌面定时器抖动影响。Pan路由目前
只生成控制值；由于音频链路仍为单声道复制，暂时没有可听的左右声像变化。

外部控制单片机发送示例：

```text
BF 0A 40    Pan居中
BF 14 60    WT Position=96
BF 15 00    选择正弦波
BF 15 7F    选择Acid波表
BF 16 40    使用默认Detune深度
BF 17 04    后续音符使用4个Unison成员
BF 18 1B    Attack控制值27，约9.85 ms
BF 19 36    Decay控制值54，约102.4 ms
BF 1A 59    Sustain控制值89，约70.1%
BF 1B 43    Release控制值67，约315.1 ms
BF 1C 60    OSC B WT Position=96
BF 1D 00    OSC B选择正弦波
BF 1E 20    OSC B使用较小Detune
BF 1F 02    OSC B使用2个Unison成员
BF 20 1B    OSC B Attack控制值27
BF 21 36    OSC B Decay控制值54
BF 22 59    OSC B Sustain控制值89
BF 23 43    OSC B Release控制值67
BF 24 00    关闭OSC A
BF 24 7F    开启OSC A
BF 25 00    关闭OSC B
BF 25 7F    开启OSC B
BF 26 01    OSC A选择PWM模式
BF 27 60    OSC A Warp Amount=96
BF 28 02    OSC B选择Sync模式
BF 29 7F    OSC B Warp Amount=127，即8倍Sync
BF 2A 01    全局滤波器选择低通
BF 2B 60    全局滤波器Cutoff=96
BF 2C 30    全局滤波器Resonance=48
BF 2D 7F    全局滤波器Mix=127
BF 2E 60    OSC A Level=96
BF 2F 40    OSC B Level=64
BF 30 7F    Master Level=127
```

如果连续发送多个CC，可以只发送一次`BF`，随后按“CC编号、数值”成对发送。只要中间
没有出现其他非实时状态字节，Running Status就持续有效。

## 13. 未来双输入迁移

正式版本建议保留两条独立物理链路：

```text
MIDI键盘 -> 31250 bit/s UART A -> MIDI解析器A -> 音符事件FIFO
控制MCU  -> 高速UART B        -> MIDI解析器B -> 参数事件FIFO
```

两个FIFO之后增加事件仲裁器，再复用当前参数寄存器和声部调度器。UART B可以提高到
`115200 bit/s`或更高，但这时只是沿用MIDI消息语义，不再属于标准MIDI DIN电气速率。

双输入可能在同一个系统时钟周期产生事件，因此不能直接把两个`valid`信号相或。仲裁器
需要逐条取出事件并保留未处理事件。参数更新可以后写覆盖，Note On/Off则不能丢失。

## 14. 当前限制

- `CC123 All Notes Off`尚未转换为调度器的全局释放命令；当前上位机会先逐个发送
  Note Off，因此测试流程不受影响。
- 调度器忙时没有输入FIFO。单个31250 bit/s串口的消息间隔远大于调度器处理时间，
  当前不会形成压力；增加双UART后必须加入事件FIFO。
- Pan目前停在参数寄存器边界，等待立体声混音数据通路。
- 当前只有Acid多帧波表响应WT Position，四个基本波形没有帧轴。
- 当前CC值为7位。大量波表帧或精细自动化可在后续升级为14位CC或NRPN。

## 15. 验证结果

顶层仿真覆盖以下行为：

1. 通道1的CC不能修改合成参数；
2. 通道16的CC10、20～57正确进入对应的全局、OSC A和OSC B寄存器；
3. 通道16的Note On不能进入声部调度器；
4. 通道1的Note On/Off、力度和Running Status保持原有行为；
5. MIDI实时字节穿插不会破坏解析状态；
6. Detune为0时Unison成员同频，增大Detune后相位步进有序展开；
7. 原有32槽位分配、释放、满载和整组偷音回归通过。
8. Acid波表ROM地址、同步读取、边界帧和帧间插值参考值通过单元仿真；
9. CC21和CC29数值127能为对应振荡器选择Acid模式，原四个控制值保持兼容；
10. 1引擎×32槽位在加入同步读取流水线后仍未发生调度超时。
11. Sustain为0时，Gate保持有效而包络在Decay后归零；
12. 可调Release完成后能通知调度器回收槽位；
13. 同一Note事件会按两组独立的Unison/Detune设置生成不同的任务数与相位步进；
14. 两个1×32 Bank的输出有效脉冲对齐，调度无超时，并在宽位乘加后进入FIR。
15. CC36/CC37能独立关闭两路音频，CC46/CC47独立控制两路Level；单路最大增益0.5，
    双路最大增益各0.25，为FIR和滤波器保留6 dB余量。
16. CC48控制滤波器后的Master Level，0～127映射为0～1.0，并在96 kHz边界平滑。
17. CC51～57能独立配置效果模式、Delay和Reverb参数；旁路逐位保持输入。
18. 最短Delay在第480个96 kHz历史样本返回冲激；Reverb冲激响应产生非零尾音。

本次只执行RTL编译与ModelSim功能仿真，没有运行Gowin综合和布局布线。

## 16. FPGA三点LFO与调制矩阵参数

通用LFO配置使用以下非商业厂商SysEx消息：

```text
F0 7D parameter_id value_msb value_lsb F7
```

参数ID 16～24配置LFO 1；ID 31～38配置LFO 2；ID 39～46配置LFO 3。ID 26～30
依次配置路由编号、使能、目标、双极性深度和调制源；ID 25把三组曲线和全部8条路由
原子提交。FPGA在96 kHz下并行产生三个LFO值，并在50 MHz域用10拍完成共享路由。
CC参数继续作为各目标的基础值。
完整目标编号、编码和定点计算见`docs/lfo_curve_control.md`。

## 独立音色控制UART（2026-10-23）

- `control_uart_rx`: FPGA C19, 3.3 V UART RX, internal pull-up enabled (user-selected header pin).
- 外部MCU TX接C19，双方GND共地。接口是3.3 V TTL UART，空闲高，不可直接连接RS-232或5 V TX。
- 默认31250 baud、8N1；独立参数 `CONTROL_UART_BAUD_RATE` 可修改新口速率。原USB-UART速率由 `UART_BAUD_RATE` 决定，原入口继续同时接受音符与音色指令。
- 新口只接受音色控制：通道16 CC（状态BF）与现有 `F0 7D id msb lsb F7` 高精度参数；该口Note事件丢弃，键盘演奏仍走原入口。
- 两路独立UART同步接收并独立解析完整消息，然后通过8项事件队列合并。每拍最多入队2项、出队1项。同拍按原口、新口顺序处理，不丢弃后者；同参数最后处理的写入生效。溢出由 `control_event_overflow` 粘滞标志记录，复位清除。
- 字节流及Running Status互相独立。由于LFO的route index、配置影子寄存器和Commit是共享状态，一次多消息配置事务应只由一个控制源发送，另一个源等待事务结束；队列不会隔离两套同时修改的LFO配置事务。
- 调试时可把上位机USB-TTL串口接到新RX口，沿用原协议；无须改为另一套协议。

板测：先用原口Note On维持声音，新口发送 `BF 2E 20` 修改OSC A Level=32；再用原口发送 `BF 2E 7F` 恢复127。随后从新口发送LFO配置，确认活动音符产生调制。抓取control_uart_byte_valid、control_uart_framing_error、merged_control_valid、control_event_overflow定位输入问题。

本次已运行ModelSim路由及顶层回归，包含新增目标、同拍双UART CC、独立SysEx和按住音符实时Detune检查。未运行综合布线，资源增量与时序仍需下一次报告确认。

## 实体MIDI键盘UART输入（2026-10-26）

- `keyboard_uart_rx`：FPGA E19，3.3 V TTL UART RX，内部上拉，空闲高电平。
- 默认格式为31250 baud、8N1，由顶层参数`KEYBOARD_UART_BAUD_RATE`配置。
- MIDI DIN/TRS电流环不能直接连接FPGA；必须先经过光耦或合规的MIDI接收转换电路，向E19输出3.3 V UART电平，并与FPGA共地。
- 板载USB-UART与实体键盘口分别使用独立UART接收器和独立MIDI Running Status解析器，解析完成后通过8项事件FIFO合并，避免两路原始字节交织。
- 实体键盘口第一版只接收Note On、Note Off、MIDI通道、音高和力度。其Control Change不会进入音色参数控制链；音色控制仍由原USB-UART或C19独立控制口负责。
- 同拍到达时先保留板载USB-UART事件，再保留实体键盘事件；`midi_note_event_overflow`记录队列溢出，复位后清零。
