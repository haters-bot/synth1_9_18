我已经对两个仓库的关键入口、顶层、约束、MIDI文档、LFO协议和效果器实现做了核对。结论是：

**两块138K板应保持独立运行，通过UART连接；当前最大风险不是FPGA容量，而是参数协议没有对齐、UI没有音频回传、可视化没有真实遥测。**

完整方案已保存到：

[双138K UART联调计划](D:/github/gaoyun/2_ui_touch_hub/doc/DUAL_138K_UART_INTEGRATION_PLAN_2026-10-23.md)

当前基线：

- UI仓库：`D:\github\gaoyun\2_ui_touch_hub`
- 音频仓库：`D:\github\synth1_9_18`
- 音频最新远端：`origin/main = 3f2bed2`
- UI当前工作区有未提交的导航字体修改，不能直接作为已验证部署版本。
- 两边应分别构建、分别烧录，协作仓库只保存并列工程和协议文档。

建议的物理拓扑：

```
UI板 U15 TX ─────> 音频板 V14 RX
      GND ───────> 音频板 GND
```

两块板不共享时钟和复位。UI的U15与音频的V14都是3.3V逻辑，但V14目前也是音频板板载USB-UART输入，接线前必须确认USB-UART桥不会和UI TX发生推挽冲突。第一阶段只做单向控制；要让UI显示音频真实状态，需要再增加音频板TX到UI板RX的独立回传线。

当前协议存在明显冲突：

| 功能             | UI当前发送    | 音频最新主线实际解释 |
| ---------------- | ------------- | -------------------- |
| OSC A WT         | CC20          | CC20                 |
| OSC B WT         | CC20          | CC28                 |
| OSC A Detune     | CC22          | CC22                 |
| OSC B Detune     | CC22          | CC30                 |
| OSC A Unison     | CC23          | CC23                 |
| OSC B Unison     | CC23          | CC31                 |
| Filter Cutoff    | CC74          | CC43                 |
| Filter Resonance | CC71          | CC44                 |
| Filter Mix       | CC95          | CC45                 |
| A ADSR           | CC73/75/76/72 | CC24–27              |
| B ADSR           | 旧映射        | CC32–35              |
| Delay            | CC12          | CC52–54              |
| Reverb           | CC91          | CC55–57              |
| Chorus           | CC93          | CC63–68              |

例如，UI的CC74在音频端会被当作 Phaser Mix，CC71会被当作 Phaser Depth。当前UI不能直接接最新音频位流扫旋钮。

应该冻结一套新的“音频线协议”：

- MIDI通道1：`0x90/0x80`，Note On/Off。
- MIDI通道16：`0xBF`，参数CC。
- 连续参数统一0～127。
- Unison限定1～8。
- Filter Mode使用0～6。
- Waveform使用音频约定的分段值。
- A/B振荡器使用独立CC。
- UI内部参数ID继续保留，但必须经过独立适配层转换为音频CC。
- 连续拖动不能每个像素都发包，应采用“同一参数只保留最新值”的dirty队列。
- Note On/Off优先于普通参数。
- 首版发送完整三字节消息，不依赖Running Status，便于逻辑分析仪抓包。

LFO不能继续用UI的七点曲线直接冒充音频调制。音频最新主线已经有：

```
3个LFO
每个LFO 3个控制点
两段曲率
8条路由
SysEx配置
Commit原子提交
```

音频协议是：

```
F0 7D parameter_id value_msb value_lsb F7
```

建议首版把UI的真实音频LFO页面改成音频同构模型：P0、P1、P2、P1时间、两段曲率、速率、Enable、路由和Depth。现有七点曲线可以继续作为本地设计预览，但没有完成确定性转换前，不能声称它已经驱动音频LFO。

页面对接建议：

- OSC A/B：分别对应音频A/B的WT、Waveform、Detune、Unison、ADSR、Enable、Warp和Level。
- Filter：对应Mode42、Cutoff43、Res44、Mix45。
- ENV：首版只开放OSC A和OSC B两组ADSR；UI的Hold没有音频对应实现，ENV3也暂不发送。
- FX：重组为音频实际存在的Delay、Reverb、Distortion、Chorus、Phaser、Compressor。当前UI的EQ页没有对应音频寄存器，暂时只能标成未接入。
- 当前UI顶层把 `note_on_req` 和 `note_off_req` 固定为0，因此UI现在并没有真正向音频发送虚拟键盘音符。需要先决定是恢复触控琴键，还是由另一块硬件提供音符源。

可视化必须分层：

| UI页面       | 第一阶段             | 后续真实联调                        |
| ------------ | -------------------- | ----------------------------------- |
| NOTES        | 显示UI发出的Note事件 | 显示音频实际接收和分配的声部        |
| WAVEFORM     | 显示参数模型预览     | 音频板回传抽取后的PCM窗口           |
| Filter曲线   | 显示参数模型         | 显示音频实际Mode/Cutoff/Res/Mix状态 |
| LEVELS       | 显示发送值或本地状态 | 音频回传Peak/RMS/Clip               |
| SPECTRUM     | 保持示意图           | 音频板增加FFT或频带遥测             |
| SPECTROGRAM  | 保持示意图           | 接收带序号的频带帧                  |
| STEREO PHASE | 标记Mono/Unavailable | 等音频真正实现双声道后再启用        |

音频当前是全局单声道链路，因此Stereo Phase不能拿UI动画代替真实立体声数据。六窗口现在也必须继续保留 `EXAMPLE / NOT LIVE` 标记。

建议按下面顺序联调：

1. 冻结双方提交和协议表。
2. UI单独抓包确认31250、8N1、CC编号。
3. 音频单独用USB-UART验证最新CC表和声音变化。
4. 两板只连接UI TX→音频RX，先测试一个Cutoff或WT参数。
5. 逐项加入A/B振荡器、Filter、ADSR、FX和Note。
6. 实现音频LFO SysEx和原子Commit。
7. 增加音频TX→UI RX回传，先做READY、STATE、METER。
8. 最后接入Waveform、Spectrum、Spectrogram等真实遥测。

本轮已新增联调计划文档，未修改RTL、未合并分支、未接线、未构建或烧录。