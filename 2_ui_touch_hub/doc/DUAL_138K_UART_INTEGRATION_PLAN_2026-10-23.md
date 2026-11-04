# UI Touch Hub × 音频合成器：双 138K UART 联调计划

日期：2026-10-23
范围：两块 Tang Mega 138K 独立运行；UI 板经 UART 控制音频板。本文是基于当前仓库代码的联调方案，不是双方已签字冻结的协议，也不代表本轮已经改代码、接线或烧录。

## 1. 结论先行

两边都实现了 UART MIDI，但现有编号并不兼容。**不要把当前 UI 位流直接接到音频仓库最新 `origin/main` 并开始扫全部旋钮。**例如 UI 的 Filter Cutoff 发 CC74，而最新音频把 CC74 解释为 Phaser Mix；Filter Resonance 发 CC71，而音频把 CC71 解释为 Phaser Depth。振荡器 B 也有多项沿用 A 的 CC 编号。

建议保持两个独立 Gowin 工程、独立时钟/复位和独立位流，只在 Git 的协作分支里并列保存 `2_ui_touch_hub/` 和音频工程；板间先做单向 31250/8N1 控制，再增加独立回传线同步音频状态和可视化遥测。共用仓库不等于把两个 top 合成到同一块 FPGA。

## 2. 本次检查的基线

- UI 源码仓库：`D:\github\gaoyun\2_ui_touch_hub`，本轮联调提交 `974ce189867e598de1b01dcfcb43d7cee6c06414`（短号 `974ce18`）。导航4×6实验仍未纳入该提交；其候选没有完整STA结论，因此不能作为已验证部署位流。
- 音频仓库：`D:\github\synth1_9_18`。本地协作分支 `ui-touch-hub-v1.0` 为 `3ade0c0`、干净，但 fetch 后显示落后 `origin/ui-touch-hub-v1.0` 3 个提交；本地 `main` 落后 `origin/main` 39 个提交。
- 本次刚 fetch 的音频远端主线是 `origin/main = 3f2bed2b0731d4f7f1d0ccc2947f083bb47f28d4`（`Add distortion chorus phaser and compressor effects`）。下面对音频能力的描述以这个远端快照的 RTL/文档为准，不能误当成本地旧 `main` 已经包含。
- UI 在本地独立开发；协作仓库的音频根目录保留原有布局，并将 UI 放在 `2_ui_touch_hub/` 子目录。不要把独立 UI 仓库根目录直接合并覆盖音频仓库根目录。

## 3. 两块板的职责与信号

```text
触控屏 ──USB/CH569 HSPI/UART──> UI 138K
实体旋钮组 ──SPI 草案──────────> UI 138K
                                  │
                                  ├── HDMI TMDS ──> 屏幕
                                  │
                                  └── UART MIDI TX ──> Audio 138K RX
                                                         │
                                                         ├── MIDI解析/控制路由
                                                         ├── 双OSC任务调度、TDM、ADSR
                                                         ├── 波表、滤波和全局效果
                                                         └── FIR / I2S ──> MAX98357A
```

UI 顶层 `ui_touch_hub_top.v` 负责 USB/HSPI/UART 触控、坐标命中、参数仲裁、矢量绘制和 MIDI TX。音频顶层 `src/top.v.v` 负责 UART RX、Note/CC/SysEx 解析、OSC A/B、ADSR、滤波/效果、I2S；音频时钟仍来自其自身 50 MHz 板载时钟。

UART 是异步边界：两板不共享 50 MHz 时钟，也不应将任一板复位直接接到另一板。当前第一阶段控制接线：UI J8 pin 9（PMOD1 IO2/AB21）→音频J8 pin 9（PMOD1 IO2/AB21），J8 pin 3或4共地，不接电源脚。未来回传候选是PMOD1 IO4/J8 pin 7，需另加协议/RTL。只接单向线时UI显示的是目标/发送状态，不能确认音频已应用。

## 4. 传输层和物理引脚建议

两边现有代码都支持 31250 baud、8N1；每字节10个线位，完整三字节 CC 约0.96 ms，理论约1041条消息/秒（未扣除队列和优先级影响）。UI `midi_uart_tx` 的实际参数为 50 MHz / 31250，发送完整三字节；文件注释里的 62.5 MHz 已过时。音频顶层 `UART_BAUD_RATE` 默认31250，并行识别 MIDI 和已有 LFO SysEx。

- UI的U15保留为USB-UART监视输出；跨板TX为`audio_link_tx`，PMOD1 IO2/AB21/J8 pin 9。
- 音频V14保留USB-UART调试输入，新增`midi_gpio_rx`使用PMOD1 IO2/AB21/J8 pin 9；两个RX在逻辑上合并，要求发包源轮流使用，不电气并联TX。
- PMOD1 IO2复用到DVP/SDRAM1扩展网，接线前确认相机/SDRAM1扩展设备未占用；两板共地，不跨接供电，不共享时钟/复位。
- 共地但不要把一块板的3.3V电源脚接到另一块板供电；核实两板电平和接地后再接线。每个接收端使用自己的 UART RX 时钟域。
- 音频板可先单独用板载 USB-UART 和 `tools/midi_uart_sender.py` 做回环/声音测试；此调试连接与 UI 跨板 TX 不应未经确认并联。

## 5. 当前 MIDI 映射差异（必须先修）

音频当前 MIDI 控制通道是 Channel 16（状态字节 `0xBF`）；演奏通道是 Channel 1（Note On `0x90`、Note Off `0x80`）。通道约定对得上，但 UI 的 CC 编号多数仍是旧映射。

**状态更新（同日实现）**：下表保留初始审计到的旧版差异作为修改动机；当前可执行映射已统一写入音频仓库 `docs/ui_uart_integration_v1.md` 和UI镜像 `doc/MIDI_CONTROL_PROTOCOL.md`。UI TX现已采用该映射，未实现参数会被抑制，不再发送旧冲突编号。

| UI 控件/旧发送值 | 音频 `origin/main` 当前解释 | 结论 / 推荐适配 |
|---|---|---|
| OSC A WT Pos：CC20 | A WT Pos：CC20 | 对齐 |
| OSC B WT Pos：CC20 | B WT Pos：CC28 | B 必须改为28 |
| OSC A Detune：CC22 | A Detune：CC22 | 对齐 |
| OSC B Detune：CC22 | B Detune：CC30 | B 必须改为30 |
| OSC A Unison：CC23 | A Unison：CC23，夹到1..8 | 对齐，保留值域 |
| OSC B Unison：CC23 | B Unison：CC31 | B 必须改为31 |
| UI WARP A/B：CC21 | CC21=OSC A Waveform；OSC B Waveform=CC29 | Warp 和 Waveform 分开；A/B各用独立编号 |
| Filter Cutoff：CC74 | CC74=Phaser Mix | 严重冲突；Cutoff改43 |
| Filter Resonance：CC71 | CC71=Phaser Depth | 严重冲突；Resonance改44 |
| Filter Mix：CC95 | CC95 当前未映射 | 改45 |
| Filter Mode / Type / Power | CC42=0旁路、1低通、2高通、3带通、4陷波、5梳状+、6梳状- | UI enum需逐项确认后映射，不要将UI电源开关生硬映射到未定义CC104 |
| ENV A/D/S/R：CC73/75/76/72 | 音频A：CC24..27；B：CC32..35 | UI Attack会撞Phaser Feedback，Decay/Sustain撞Compressor；按OSC A/B重新映射 |
| ENV Hold：CC79 | CC79=Compressor Release；音频无Hold阶段 | 禁发CC79。先隐藏/禁用Hold，或由音频队友新增真正的Hold实现和测试 |
| Master：CC7 | Master Level：CC48 | 改48 |
| Reverb：CC91；Delay：CC12 | Reverb CC55..57；Delay CC52..54 | 重新拆成音频实际参数，不能用单一旧CC冒充整组功能 |
| Chorus：CC93 | Chorus CC63..68 | 重新拆分Enable/Rate/Depth/Delay/Feedback/Mix |
| Macro CC1..4、OSC Enable102/103、Filter Enable104 | 当前 router 未定义这些CC | 暂不显示为已联通功能，或由两方共同分配新映射 |
| UI新FX内部ID 0x60..0x88、LFO/route事件 | `midi_uart_tx` 只处理旧 `param_merger` CC 请求；FX和route事件没有接进现有普通CC串口映射 | 这些目前是UI本地状态；实现独立协议适配器后再宣称联动 |

音频当前CC主表：

| 分组 | 音频实际 CC |
|---|---|
| OSC A | WT20、Wave21、Detune22、Unison23、ADSR24–27、Enable36、Warp Mode/Amount38–39、Level46、Wavetable Index49 |
| OSC B | WT28、Wave29、Detune30、Unison31、ADSR32–35、Enable37、Warp Mode/Amount40–41、Level47、Wavetable Index50 |
| Filter / Master | Mode42、Cutoff43、Resonance44、Mix45、Master48 |
| Delay / Reverb | Mode51、Delay Time/Feedback/Mix52–54、Reverb Size/Decay/Mix55–57 |
| Distortion / Chorus / Phaser / Compressor | Distortion58–62、Chorus63–68、Phaser69–74、Compressor75–81 |

音频值多为7位0..127；离散参数须量化。Unison只允许1..8，滤波模式只允许0..6，波形按值分档，Warp Mode只允许0..11。UI应保留自身内部 ID，新增一个清晰的 `ui_param_id → audio wire command → audio state` 适配层；不能把UI内部ID当作MIDI CC。

## 6. 推荐协议版本

### V1：先跑稳定的控制面

1. 31250 baud、8N1、3.3V CMOS UART；默认先发完整三字节 MIDI 消息，不依赖 Running Status。音频解析器支持 Running Status，但简化发送/抓包时完整状态字节更稳妥。
2. `0x90/0x80` 保留音符；`0xBF` 保留Channel 16 CC。音符值、力度、CC值均为7位数据。
3. 按第5节冻结CC表、离散枚举、复位默认值、A/B含义和变化平滑规则。范围不兼容时由适配层量化/饱和，并在测试中覆盖端点。
4. UI发送端增加按参数合并的dirty队列：同一参数排队期间只保留最新值；Note On/Off优先；记录队列满/丢帧计数。当前UI TX是8条消息FIFO，`cc_req`满载时没有可见的ready/ack回压，连续拖动可能丢CC；曲线事件虽有单独待发合并，不代表所有参数都可靠排队。
5. 连接/复位后发送完整的已支持参数快照，避免UI显示的默认值和音频上电默认值分叉。未经音频回传确认时状态标成“待发送/已发送”，不要标“已应用”。

### LFO：复用音频已实现的SysEx，不从UI内部快照直连

音频已实现六字节字段帧 `F0 7D parameter_id value_msb value_lsb F7`，支持3个LFO、每个3点、两段曲率、速率和8个路由槽；ID25用于原子Commit。各字段数据必须保持7位。

当前UI是7点等距、0..127单极性预览，音频是三点双极性Q1.13、可移动P1和两段曲率，并采用96 kHz运行；两者不能无损互译。推荐把UI真实控制模型改成音频同构模型（P0/P1/P2、P1时间/两段曲率、Enable/Rate、最多8条路由），主曲线预览使用音频相同公式；不要继续显示7点精确曲线却只发送一个近似三点曲线。若产品坚持7点UI，则音频需另行实现7点曲线，工期和资源/时序验证都会增加。

首版只开放音频已有的LFO目标：A/B WT Position、A/B Warp Amount、A/B Level、Filter Cutoff/Resonance/Mix。Pan虽有路由编号，但音频文档注明当前单声道输出听不到变化；未实现的UI ENV、多源目标不应显示为已联通。

### V1.1：加状态回传和可视化遥测

当前音频顶层和UI顶层尚无应用状态遥测协议。回传物理候选是PMOD1 IO4/AA20/J8 pin 7，启用前需增加两端TX/RX、CST和版本化遥测帧。

建议先冻结轻量版本化回传帧，至少包含 `protocol_version / message_type / sequence / payload / checksum`，并提供：

- `HELLO/READY`：协议版本、构建ID、能力位、初始化完成；
- `STATE`：参数ID、实际寄存值/值域、序号；
- `NOTE/VOICE`：已接受的音符事件或活动声部数；
- `METER`：Peak/RMS、OSC A/B活动任务数、音频clip计数、错误/overrun计数；
- `SCOPE`：低速抽取的单声道样本窗口；
- `SPECTRUM`：压缩的频带能量帧。

先用115200 baud做返回遥测的带宽起点；必须以实际需要和误码测试定最终值。单声道96 kHz、16-bit原始PCM需要约1.536 Mbit/s有效负载（含UART 8N1线路开销约1.92 Mbit/s），所以31250/115200都不适合连续全速回传。应由音频板在96 kHz样本处做抽取、RMS/Peak聚合和少量频带计算，再按10–30 Hz回送摘要/短窗口，而不是搬运全量I2S流。

## 7. UI控制页怎样与音频实现对齐

- OSC A/B分开呈现WT位置、Waveform、Detune、Unison、ADSR、Enable、Warp Mode/Amount、Level和波表编号；每个控件绑定独立音频CC，不能让A/B共用同一CC。
- Filter控件绑定Mode42、Cutoff43、Res44、Mix45。UI图形刻度应复用 `docs/global_filter.md` 的参数映射；模式按音频0..6定义。UI当前4类滤波选项若不能一一覆盖音频模式，应将未暴露模式保留为“暂不支持”，避免不同枚举暗中错位。
- ADSR按音频实际结构定义：OSC A用CC24..27，OSC B用CC32..35。UI现有3个ENV标签和A/H/D/S/R与音频两个A/D/S/R包络不同构。建议首版只开放OSC A和OSC B两套ADSR，Hold不发；第三个ENV页待音频侧给出对应状态所有者后再开放。这个是需要你和音频队友共同确认的产品语义。
- FX页重组到音频已有参数：Delay Mode/Time/Feedback/Mix；Reverb Size/Decay/Mix；Distortion、Chorus、Phaser、Compressor各自的Enable和参数。UI当前EQ及旧版Delay/Reverb单旋钮若无音频对应状态，应隐藏/禁用或明示仅本地预览。
- 统一归一化值到显示单位转换。音频A/D/R使用近似指数时间；Filter Cutoff在SVF中约69.9 Hz至17.4 kHz的16级/倍频程映射；不得直接把UI整数当作Hz/ms/dB。
- 加入在线状态与应用状态：离线、待发送、已发送、已确认、音频端限制/拒绝。没有反向状态帧前只能做乐观本地显示，并应保留“未确认”标记。

## 8. 可视化页怎样与音频数据对齐

| 页面/图层 | 音频端现有可复用数据 | 还需新增/限制 | 联调呈现原则 |
|---|---|---|---|
| NOTES | Note解析事件、A/B活动任务数 | 音符接受回传/声部状态帧 | 区分“UI发出的音符”和“音频已分配声部” |
| WAVEFORM / Scope | 音频最终样本在主音量/I2S前可做采样点 | 加PCM窗口抽取和回传 | 只显示实际采到的样本；注明mono和时间窗 |
| STEREO PHASE | 当前无真正独立L/R输出；当前音频链为单声道 | 先完成双声道DSP/Pan，再增加同步L/R遥测 | 目前标“MONO / unavailable”；不要显示假丽萨如图 |
| SPECTRUM | 当前可从96 kHz样本分析 | 音频端新增FFT/频带分析或明确由其它处理器计算 | 频带数量、窗函数、缩放、更新率写进协议 |
| SPECTROGRAM | 可复用频带帧 | 需带帧序号/历史缓存/失帧处理 | 只绘制有序的真实频谱帧，丢帧时显示断档 |
| LEVELS | `audio_clip_count`、OSC A/B活动任务数已有内部信号 | 新增Peak/RMS统计和低速回传 | UI meter对应最终音频节点，不能拿主音量旋钮值冒充响度 |

六窗口目前在UI里仍是概念示意；R17A文档要求标 `EXAMPLE / NOT LIVE`。OSC波形、Filter响应和ENV图目前可作为“参数模型预览”，不等于I2S实测波形、声学频响或真实音符包络。若预览要求和引擎一致，必须使用同一张波表/模式枚举/参数映射，或由音频板回送实际状态。

## 9. 联调阶段与验收门槛

### 阶段0：冻结基线和协议表

- 确认音频基线使用最新主线还是现有协作分支；本次检查两者相差3个协作分支提交，不能混用。
- UI当前工作树有未提交修改；先保留其状态并选定有独立测试记录的UI提交/位流，不重置或覆盖。
- 共同签字确认CC、SysEx、ENV A/B、模式枚举、值域/单位、启动默认值、队列策略、超时和遥测版本。
- 交付 `protocols/ui_audio_uart_v1.md` 或音频仓库同等权威文档；两边协议文档只引用同一版本。

### 阶段1：音频端单独验证

- 用音频仓库现有测试工具从板载USB-UART发Note On/Off、OSC A/B WT、Filter CC43/44和FX CC，确认声音/模式确实变化。
- 运行音频 `sim/run_top_midi_test.do`、参数/效果/LFO相关测试；对新增映射做独立 testbench，不只看UART波形。
- 捕获音频板上电默认寄存值和复位/错误行为。

### 阶段2：UI串口发送验证

- 不接音频输入，先在UI U15用逻辑分析仪/USB-UART接收器确认31250、8N1、空闲高电平、`0xBF`及目标CC顺序。
- 用UI testbench覆盖每个适配CC、A/B隔离、枚举端点、触摸连续拖动、Note优先和队列满时最新值合并。
- 当前UI顶层将 `note_on_req` / `note_off_req` 固定接0；接通之前先实现明确音符源（触控键盘或外部MIDI桥接），否则不能验收UI发音。

### 阶段3：跨板最小联通

- 先接命令TX→音频RX及GND，确保板载USB-UART TX未同时争用同一RX线。
- 只做一条已冻结、可听见的参数，例如 Filter Mode旁路/低通 + Cutoff43，或 OSC A WT Position20；确认从UI操作到音频声音的因果链。
- 再逐项加入OSC B独立CC、ADSR、音符、效果器；每项记录UI发送字节、音频寄存器值、I2S/听感结果。
- 如果没回传，串口发送成功不等同音频已接受；物理阶段可先用逻辑分析仪、PC端音频输出和固定参数测试辅助确认。

### 阶段4：双向状态同步与页面联动

- 增加Audio TX→UI RX专用线、READY/STATE/METER消息和序号/校验。
- 确认UI面板显示的参数来自音频已确认状态；增加音频复位、断线重连和全量状态同步测试。
- LFO先实现同构三点模型、SysEx字段写入和ID25原子提交，再联调路由及曲线预览。

### 阶段5：可视化数据链

- 先交付METER，再交付低速mono scope，再交付频谱帧。
- Stereo Phase排在真正双声道DSP/Pan之后；在此之前清楚标注不支持。
- 每个页面显示数据有效/过期、帧序号、更新率和音频板在线状态；静态演示不得覆盖实时页面的失联状态。

### 阶段6：仓库整合与发布

- 保持UI、音频各自 `.gprj`、约束和构建脚本；把双方已审核的源码/文档以子目录放进同一个协作分支。
- 由UI和音频队友分别提交自己仓库的确认变更；在共享分支记录每块板对应的源码SHA、构建报告、位流SHA、协议版本、引脚表和实测结果。
- 合并前分别跑功能仿真/编译、独立全量时序审计和两板实机；一个板子通过不能代表另一块。
- 保存当前板上可回退SRAM位流；Flash写入仍按项目单独审批流程处理。

## 10. 本次尚未完成的团队决策

1. 音频侧要把ENV1/2/3分别对应什么？本方案暂建议ENV A/B映射OSC A/B，Hold先不发，ENV3暂缓。
2. 第一阶段单向命令GPIO已实现；后续状态回传以PMOD1 IO4/J8 pin 7为候选，启用前仍需确认硬件空闲。
3. UI A/B波形/Filter图是“模型预览”还是要与音频内部实际输出逐点一致？若后者需共享波表/数学定义或传回数据。
4. 音频板的Pan和Stereo Phase需要在本项目实现立体声吗？当前音频代码路径为mono。
5. 音频寄存器值改变时，是否需要写回/状态确认？建议首版即增加低速状态回传，至少覆盖启动快照、CC应用值、音频ready和错误计数。

## 11. 仓库证据索引

- UI：`rtl/ui_touch_hub_top.v`（当前TX/Note tie-off）、`rtl/midi_uart_tx/midi_uart_tx.v`（旧CC映射/FIFO）、`rtl/param_merger/param_merger.v`（触摸/曲线事件）、`constraints/ui_touch_hub.cst`（U15/V14/3.3V）、`doc/MIDI_CONTROL_PROTOCOL.md`、`doc/FX_LFO_INTERFACE_R16.md`、`doc/HARDWARE_WIRING_PINOUT.md`、`doc/R17A_READABILITY_SETTINGS_2026-10-20.md`。
- 音频（以 fetch 后 `origin/main` 为准）：`README.md`、`src/top.v.v`、`src/midi_note_parser.v`、`src/highres_parameter_parser.v`、`src/synth_control_router.v`、`src/global_effects.v`、`docs/midi_control_protocol.md`、`docs/lfo_curve_control.md`、`docs/adsr_envelope.md`、`docs/global_filter.md`、`docs/midi_uart_test.md`、`constraints/tang_mega_138k_full_synth.cst`。

## 12. 2026-10-23 实施更新

- GPIO方案：UI/Audio的PMOD1 IO2 / AB21 / J8 pin 9；两板J8 pin 3或4共地。U15和V14留作USB-UART监视/调试，音频`uart_rx & midi_gpio_rx`兼收，要求两输入源轮流发送。PMOD1 IO2复用DVP/SDRAM1网络，外设未拔除前不接线。
- 音频合作分支已合入最新origin/main；当前CC表见`D:\github\synth1_9_18\docs\ui_uart_integration_v1.md`。
- UI TX映射已改为音频CC表，未映射参数被抑制；当前UI Note请求仍未实现。
- UI TX ModelSim协议回归通过；Audio顶层MIDI仿真含GPIO RX独立发送测试通过。未跑Gowin构建/STA或烧录，未做板上验收。
- 本轮实施了RTL和文档修改，不再适用上方早期“本轮只读检查”的结尾陈述。

本轮已修改协议适配RTL、约束、仿真和文档；已通过ModelSim协议/参数回归，未运行Gowin构建/STA，未接线或烧录，Flash未操作。
