# UI Touch Hub 与音频引擎 UART 协议 v1

状态：第一阶段候选，双方硬件接线前复核；唯一CC基线位于音频仓库 `docs/ui_uart_integration_v1.md`。

## 传输层

- 3.3V LVCMOS UART，31250 baud，8N1；发送完整状态字节，不依赖Running Status。
- MIDI Channel 1：Note On/Off。音频支持Note 21..108；当前UI顶层把Note请求接常量0，第一阶段只验参数，不声称UI触控演奏已接通。
- MIDI Channel 16：CC状态字节`0xBF`，每条CC完整发送`0xBF, cc, value`，数据均为7位。
- U15保留为UI板板载USB-UART监视输出；跨板TX另走`audio_link_tx`，映射PMOD1 IO2 / AB21 / J8 pin 9。
- 音频的`uart_rx`仍为V14 USB-UART调试输入；新增`midi_gpio_rx`映射音频板PMOD1 IO2 / AB21 / J8 pin 9。接收端逻辑为两个空闲高UART输入相与；同一时刻只允许一个发包源。

## 第一阶段已映射控件

| 控件 | MIDI CC | 编码/限制 |
|---|---:|---|
| OSC A WT Position | 20 | 0..127 |
| OSC A Waveform | 21 | UI 0/1/2/3分别映射音频0/96/64/32：Sine/Saw/Square/Triangle |
| OSC A Detune / Unison | 22 / 23 | Detune 0..127；Unison 1..8 |
| OSC A Enable / Warp Amount / Level | 36 / 39 / 46 | Enable 0/127；其余0..127 |
| OSC B WT Position | 28 | 0..127 |
| OSC B Waveform | 29 | 同OSC A编码 |
| OSC B Detune / Unison | 30 / 31 | Detune 0..127；Unison 1..8 |
| OSC B Enable / Warp Amount / Level | 37 / 41 / 47 | Enable 0/127；其余0..127 |
| Filter Mode | 42 | 0=Bypass，1=LP，2=HP，3=BP，4=Notch；5/6梳状模式UI未提供 |
| Filter Cutoff / Resonance / Mix | 43 / 44 / 45 | 0..127；频率映射由音频端执行 |
| OSC A Attack / Decay / Sustain / Release | 24 / 25 / 26 / 27 | 0..127；只在当前ENV第一栏发往A |
| Master Level | 48 | 0..127 |

未映射或暂不发送：Pan（音频当前mono）、OSC八度/半音/Fine、ENV Hold和ENV第二/第三栏、宏、EQ、旧FX占位参数、LFO七点数组和53目标本地快照。LFO后续使用音频原生SysEx协议单独适配，不伪装成CC。

## 串口拥塞与状态

单条CC需约0.96 ms。当前TX只有8条完整消息FIFO，满载时普通CC会被抑制；逐像素拖动并非保证每个中间值都传到。UI显示目前代表本地目标值和本次发送请求，音频状态回读未实现，不等于音频已应用。

第一阶段手动联调时一次只使用一个发送源：USB-UART调试输入或跨板GPIO输入。UI板J8 pin 9到音频板J8 pin 9，J8 pin 3/4接公共GND；不接J8电源脚，不共时钟/复位。PMOD1 IO2还复用DVP/SDRAM1扩展网络，接线前确认J8/J14没有相机/SDRAM扩展卡占用。
