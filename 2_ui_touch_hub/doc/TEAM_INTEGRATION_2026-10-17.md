# 三人协作考证与接口对照（2026-10-17 调研，18 日落档）

## 1. 仓库与原分工：证据和结论

共同协作仓库：https://github.com/haters-bot/synth1_9_18 。
本地克隆：`D:\github\synth1_9_18`；UI 独立开发仓库：`D:\github\gaoyun\2_ui_touch_hub`。

原始证据为 Antigravity 日志：
`C:\Users\胡珂\.gemini\antigravity\brain\44b86f26-de1b-41bc-bc6c-1efd36abce37\.system_generated\logs\transcript_full.jsonl`。

- JSONL 第 1 行：用户提供以上 GitHub 链接，要求三个人工程独立，先并列归档，后续再融合。
- 第 25 行：实际执行 `git clone ... D:\github\synth1_9_18`。
- 第 39 行：初步提出 common_protocols / hw_ui_touch_hub / synth_audio_core 等目录。
- 第 47 行：根据用户纠正，改为根目录下 `1_hardware_knobs / 2_ui_touch_hub / 3_synth_engine / doc_protocols` 并列方案。
- 实际 UI 在 `D:\github\gaoyun\2_ui_touch_hub` 独立 Git，原先无 remote；不能把“本地提交”写成“已经推送团队仓库”。

2026-10-18 通过 GitHub 的 Git 远端查询并 fetch，核实 `origin/main` 为
`85edc8264efe103aa238b300b938729e77b80e19`（TEENAGERKILLER，2026-10-17 20:06:35 +08:00，Scale comb LFO depth to 70）。
远端根目录仍为 src / docs / constraints / ip / sim / tools / synth1_9_18.gprj。
对上述四个规划目录查询可达 main 历史，没有相关新增、删除或修改提交。

**结论：现有 Git 证据不支持“队友把并列结构改回了”；更可能是旧规划没有落实到远端。**
这不是对未保存操作、不可达历史或队友意图的断言。为避免音频工程相对路径失效，
本轮仅新增 `2_ui_touch_hub/` 子目录，不移动根目录音频文件，也不创建空的队友工程冒充交付。
将来如果三人共同决定把音频搬至 `3_synth_engine/`，另开迁移工作。

共享交付采用 `ui-touch-hub-v1.0` 分支，基于已核实的最新 main，改动限于 `2_ui_touch_hub/`。
独立 UI 仓库不能直接把自身 master 强推到这个音频仓库，否则两者根目录含义不一致。
本地 UI 开发保留自身历史；共享分支为有来源提交和清单的快照。

## 2. 分工与数据路径

| 负责人 | 负责范围 | 现状 |
|---|---|---|
| 上游硬件队友 | 实体键盘/旋钮采集，ADC 转换、协议发送 | 未找到其仓库代码或已确认的 SPI 协议；不能把本项目接收草案当双方约定 |
| 本项目 UI Touch Hub | USB 触控、HDMI、UI 状态、参数仲裁；未来接收键盘高亮和旋钮反馈 | 触控/UI 已验收；实体键盘输入尚未实现；SPI 接收已有草案，待双方确认 |
| 下游音频队友 | 音符分配、双 OSC、包络、滤波器、LFO、I2S | 以远端 `85edc82` 的 RTL / docs 为准；本地旧 main `969de5e` 已落后 26 个提交 |

后续实体键盘每个键应有明确音符编号、按下/抬起、力度、通道、来源；UI 高亮和发送给音频的音符事件要基于同一事件。
尚待确定键盘事件直达音频还是经 UI 中转，以及 UI 是否保留键盘显示区域。
**当前 UI 已无钢琴区，顶层 Note On/Off 请求常零，不能宣称键盘接入就会高亮。**
物理旋钮还须约定参数编号、绝对/相对值、值域、采样频率、校验、掉线与触控抢占规则。
这轮记录并调研上述事项，不擅自替队友定协议或改其代码。

## 3. 上游 SPI：仅为本项目实现草案

实际 `rtl/knob_spi_intake/knob_spi_rx.v`：CS 低有效，SCLK 上升沿采样、MSB first，16 位 `[channel(4), ADC(12)]`；
输出 7 位参数值并做滞回。是否最终采用 Mode 0、SCLK 上限、帧间隔与该帧格式，仍须硬件队友确认。
channel 0/1→Cutoff/Res，2/3/4→OSC A WT/Detune/Unison，5/6→A Pan/Level，
7/8/9/10→ENV A/D/S/R，11→Master，12..15→Macro1..4。
不要按顶层过期注释接线；当前 CST：CS W16、SCLK U16、MOSI T16。

## 4. 下游 UART：真实存在的差异

核查网站与内容：GitHub 上 `haters-bot/synth1_9_18` 的 main（固定到 `85edc82`），
`docs/midi_control_protocol.md`、`docs/lfo_curve_control.md`、`src/midi_note_parser.v`、`src/highres_parameter_parser.v`。
网页资料均通过 Git 获取；没有从推测或旧聊天摘要认定支持范围。

共同基础为 UART 31250 bit/s、8N1；通道 1 音符、通道 16（0xBF）参数。
但当前 UI 并未对齐新的参数编号：

| 控件/参数 | UI R15I 当前输出 | 音频 main `85edc82` | 后续工作 |
|---|---|---|---|
| WT Position A/B | 两者都 CC20 | A20 / B28 | 分离目标 |
| Detune A/B | 两者都 CC22 | A22 / B30 | 分离目标 |
| Unison A/B | 两者都 CC23，发送时限制 1..8 | A23 / B31 | 分离目标并统一 UI 显示值域 |
| 波形按钮 | UI 枚举 0/1/2/3，ID 未映射则 CC0 | A21 / B29；0..31 正弦、32..63 三角、64..95 方波、96..126 锯齿、127 Acid | 编号及值域均须转换 |
| Warp | A/B 都映射 CC21 | A 模式38/深度39，B40/41 | 目前会被音频解释成波形，不能直接联调 |
| OSC Enable | A102 / B103 | A36 / B37 | 替换编号 |
| FILTER Cutoff / Res / Mix | 74 / 71 / 95 | 43 / 44 / 45 | 替换编号 |
| FILTER Type/Enable | Type 无有效映射；Enable104 | CC42：0旁路，1低通，2高通，3带通，4陷波，5/6梳状 | UI 四类型与开关需组合编码 |
| ENV A/D/S/R | ENV1 73/75/76/72；ENV2/3 本地 | A24..27 / B32..35 | 先明确 ENV 页签与 OSC 的对应关系 |
| ENV Hold | UI CC79 | 音频 ADSR 无 Hold 字段 | 需决策，不能捏造支持 |
| LFO | UI 三组七点、本地预览 | 音频一个三点两曲率 Cutoff LFO | 数据模型不同，不能直接把七点数组发过去 |
| Pan | CC10 | CC10 保存目标，尚未改变立体声输出 | 编号一致，但不等于声音已生效 |
| Master/Macro/FX/路由等 | 有 UI 状态及部分旧 CC | 需逐项定义或确认 | 未对齐项不宣称音频支持 |

音频 LFO 新协议：`F0 7D parameter_id value_msb value_lsb F7`。
ID16 Enable，17/18 两段相位步进，19 Depth Q7.7，20..22 三点电平，23/24 曲率，25 原子提交。
音频运行速率 0.1..10 Hz；Comb 深度内部约按 70/127 缩放，UI 无需再缩放一次。
当前 UI 七点、固定横坐标的曲线无法无损转换成三个点加曲率，需要三人选择统一模型或明确近似策略。

## 5. 日志与协议分开管理

本轮点击日志为独立诊断固件，详见 `TOUCH_TRACE_V1.md`；普通固件依旧输出原 MIDI。
U15 只有一个物理 TX：诊断模式 115200 输出二进制日志，普通模式 31250 输出 MIDI，不能同时接收两种协议。
**普通固件暂时保留旧映射是为了保持已验收基线；日志新增不意味着已解决本表的对齐差异。**
后续同时需要日志和音频时，需新增经过原理图核实的独立 TX/转接器，或共同约定可兼容的复用协议。

## 6. 接下来需要队友提供/共同决定的信息

1. 硬件队友的发送端工程、SPI 完整帧与实体键盘事件格式、实际接口电压和接线。
2. ENV1/2/3、双 OSC ADSR 与 Hold 的产品语义。
3. UI 七点 LFO 与音频三点 LFO 如何统一；哪些 LFO 目标需要真正发声。
4. 控件改动在 UI 和音频两侧的初始状态同步、回读确认、离线状态与丢包策略。

仅凭现在的资料不能完成上述决策；本轮没有擅自实现或发消息给队友。
