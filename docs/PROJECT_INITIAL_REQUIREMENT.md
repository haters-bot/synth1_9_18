# 先阅读这个文件，是之前这个项目的对话记录，之后我们讨论下一步行动

> 先阅读这个文件，是之前这个项目的对话记录，之后我们讨论下一步行动
>
> User context
>
> Attachments:
> - # 我想构建一个波表合成器里的振荡器，但是感觉逻辑稍微有点乱，帮我在这个代码基础.md: `./# 我想构建一个波表合成器里的振荡器，但是感觉逻辑稍微有点乱，帮我在这个代码基础.md`

<details><summary>2 previous messages</summary>

> 我先完整阅读这份对话记录，并顺带确认一下项目目录概况；这一轮只梳理上下文，不修改任何文件。
>
> 文件约 52.9 万字节、9410 行，里面嵌了较大的波形截图 Base64，刚才一次读取被输出上限截断了。我会分段继续读，并把图片数据本体略过、保留其前后对话与结论。
</details>

已完整阅读这份对话记录，并跳过了其中体积很大的 Base64 图片数据；没有修改任何文件。

我目前掌握的项目状态是：

- 系统时钟为 50 MHz。
- 振荡器采用 32 位相位累加器和 MIDI 音符相位步进查表。
- 内部采样率为 768 kHz。
- 经高云 Advanced FIR 做 8:1 抽取，输出采样率为 96 kHz。
- 当前音频输出使用板载 PT8211 通路。
- 总体规划是 4 个物理核心，每核心时分复用 32 个槽位，共 128 个逻辑振荡器。
- 当前已完成并实际上板验证的是“1 个物理核心 × 32 个槽位”：
  - 槽位按 0～31 顺序调度；
  - 相位分别保存并正确累加；
  - 每轮产生混音结果；
  - `schedule_overrun=0`。
- 已加入单槽位更新接口，包括音符、启用状态和相位复位。
- 当前顶层上电后依次初始化 MIDI 48～79，并把 32 个槽位全部开启。
- 槽位关闭后输出为零、停止相位累加；重新开启时可选择续播或从零相位触发。
- 目前还没有 ADSR，因此直接开关槽位可能产生咔哒声。
- 后续操作还要遵守项目中的高云开发规范，尤其是厂商 IP 的生成、集成以及综合/布局布线流程。

下一步开始前，我会先以当前磁盘中的 RTL 为准重新核对，因为对话记录描述的是演进过程，不会盲目把历史状态当成当前文件状态。可以继续讨论下一步方向。

> 现在我想模拟i2s的实际输入，但是我没有midi键盘，能用电脑当i2s输出源吗

可以，但要先区分两种信号：

- MIDI：告诉合成器“按了哪个键、力度多少、何时松开”。
- I?S：传输已经生成好的数字音频采样。

你的波表合成器需要模拟的“键盘输入”其实是 MIDI，而不是 I?S。I?S 应该位于振荡器、混音和滤波之后，用来把音频送到 PT8211。

电脑不能通过普通耳机口或常规 USB 口直接输出裸 I?S；若一定要让电脑成为 I?S 音源，需要 USB-to-I?S 转换板，并处理主从时钟、采样率和电平等问题，对当前项目帮助不大。

更适合当前阶段的方法是让电脑模拟 MIDI 键盘：

```text
电脑上的虚拟钢琴/测试程序
        ↓
USB 串口或开发板自带串口
        ↓
FPGA UART MIDI 接收模块
        ↓
音符分配器
        ↓
voice_update_* 接口
        ↓
TDM振荡器 → FIR → PT8211
```

可以定义简单的测试协议，例如每条命令3字节：

```text
Note On ：90 3C 64   // MIDI 60，力度100
Note Off：80 3C 00
```

电脑端用 Python 或串口工具发送即可。以后接真实 MIDI 键盘时，再把串口测试入口替换成 USB-MIDI、传统 DIN MIDI 或 TRS MIDI 解码模块。

如果暂时不想增加串口硬件，还可以在 FPGA 内写一个“自动演奏器”，用 ROM 保存音符、持续时间和开关事件，直接驱动现有的 `voice_update_valid/note/enable/phase_reset` 接口。这是验证多复音、关闭槽位和后续 ADSR 最简单的方案。

因此建议下一步不是模拟 I?S 输入，而是实现：

1. 一个简单的 UART MIDI 测试输入；
2. 电脑端发送音符的小程序；
3. 一个基础槽位分配器，将 Note On/Off 转换成现有的 `voice_update_*` 信号。

这样电脑就可以充当虚拟 MIDI 键盘。

> 噢，说错了，现在我想模拟midi的实际输入，但是我没有midi键盘，能用电脑当i2s输出源吗

可以用电脑模拟 MIDI 输入，但电脑应作为“**MIDI 输出源**”，不是 I?S 输出源。I?S 是音频数据，与按键控制无关。

有三种测试方式：

1. 最简单：USB 转串口

```text
电脑虚拟键盘/Python程序
→ USB-UART
→ FPGA UART_RX
→ MIDI消息解析
→ voice_update_*接口
```

串口设置为传统 MIDI 的格式：

```text
31250 baud
8 data bits
no parity
1 stop bit
```

电脑发送例如：

```text
90 3C 64    Note On，MIDI 60，力度100
80 3C 00    Note Off，MIDI 60
```

注意 USB-UART 输出必须是 FPGA 可接受的 3.3 V逻辑电平，并且芯片支持准确设置 `31250 baud`。

2. 最接近真实 MIDI 键盘：USB-MIDI 转接器

```text
电脑虚拟MIDI键盘
→ USB-MIDI接口的DIN/TRS MIDI OUT
→ 光耦MIDI输入电路
→ FPGA
```

这种方式能够测试真正的 MIDI 31.25 kbit/s 电流环接口，包括光耦和硬件输入电路。电脑上可以使用虚拟钢琴或 DAW 输出 MIDI。

3. 纯 FPGA 仿真

在 testbench 中按 `31250 baud` 串行发送 MIDI 字节，可以验证：

- Note On/Off解析；
- Running Status；
- 不同通道；
- 力度为零的 Note On；
- 多音同时按下和释放；
- 槽位分配与回收。

对当前项目，我建议先采用 USB-UART：实现成本最低，也足以完成 MIDI 接收器、音符分配器和32复音测试。等逻辑验证通过，再接光耦和标准 MIDI 插口测试真实电气接口。电脑的耳机口、HDMI或普通 USB 音频输出都不能直接当 MIDI 或裸 I?S 信号接入 FPGA。

> 先采用 USB-UART吧，这个板子上有串口吗

<details><summary>3 previous messages</summary>

> 我会先查当前工程的约束、顶层端口和本地板卡原理图，确认板载 USB-UART 是否存在、连接到哪些 FPGA 管脚。这里涉及读取 PDF 原理图，我会按 PDF 检查流程核对，不先改代码。
>
> 当前工程里没有现成的 UART 端口或约束；我正在定位这块 Tang Mega 138K/NEO Dock 的原理图，避免仅凭“开发板通常带串口”作判断。
>
> <details><summary>Searched the web</summary>
>
> Searched the web for `Tang Mega 138K NEO Dock schematic USB UART CH340 ...`
>
> Searched the web for `github Tang_Mega_NEO_Dock_31005 UART_TX UART_RX pin ...`
>
> Searched the web for `"BL616" "UART_RX" "Tang Mega 138K" ...`
>
> Searched the web for `site:github.com "N16" "FPGA_RXD" "Tang Mega 138K" ...`
>
> </details>
</details>

有。你这块 Tang Mega 138K NEO Dock 带板载 **USB-JTAG/UART**，就是 PCB 上标有 `JTAG|UART` 的 USB-C 接口。官方资料确认该接口由板载调试器提供 UART 功能。[Sipeed 官方说明](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k)

官方同型号示例给出的 FPGA 管脚是：

```text
uart_rx：V14   // 电脑 → FPGA，当前主要需要
uart_tx：U15   // FPGA → 电脑，可用于调试回传
电平：  3.3 V LVCMOS
```

对应约束可以写成：

```tcl
IO_LOC  "uart_rx" V14;
IO_PORT "uart_rx" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;

IO_LOC  "uart_tx" U15;
IO_PORT "uart_tx" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
```

这与当前工程的 `GW5AST-LV138PG484AC1/I0` 器件匹配；官方工程也使用 `V22` 作为 50 MHz 时钟，和我们当前工程一致。[官方 Tang Mega 138K 示例仓库](https://github.com/sipeed/TangMega-138K-example)

目前工程中还没有 UART 顶层端口和这两个约束，所以暂时不能直接收数据。连接后，Windows 设备管理器中应出现一个 COM 端口。我们可以先让电脑发送标准 MIDI 字节，例如：

```text
90 3C 64    Note On
80 3C 00    Note Off
```

建议先使用真正的 MIDI 串口速率 `31250 baud`；如果板载 USB-UART 驱动不能稳定设置该速率，可以先用 `115200 baud` 验证完整消息解析逻辑，字节内容保持 MIDI 格式。官方还提示，如果实际波特率变成设置值的四倍或持续乱码，需要更新板载调试器固件。[UART故障说明](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k#the-uart-of-the-onboard-debugger-cannot-be-used)

所以下一步可以直接增加：

```text
板载USB-UART → uart_rx → UART接收器 → MIDI消息解析器 → voice_update_*
```

不需要额外购买 USB-UART 模块。

> 是直接接ch569-usb3这个typec口就行吗

不是。**不要接 CH569-USB3 的 Type-C 口来做 UART。**

应该连接 PCB 上标有：

```text
JTAG|UART
```

的 USB-C 口，也就是平时给 FPGA 下载位流使用的接口。它通过板载 BL616 调试器提供 USB-UART，连接电脑后会出现 COM 端口。

两个接口的区别：

```text
JTAG|UART Type-C → 下载位流 + UART串口（我们需要）
CH569-USB3 Type-C → USB 3.0/HSPI高速数据通道
```

CH569 端口默认不会把电脑串口数据送到 FPGA 的 `V14/U15` UART 管脚。[Sipeed 官方接口说明](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k)

如果你目前就是通过某个 USB-C 口下载 `.fs` 文件，那么通常那个口就是正确的 `JTAG|UART` 口。连接后可在 Windows“设备管理器 → 端口（COM 和 LPT）”中查看是否出现新的 COM 端口。

> 用这个口，不会冲突吧

不会产生管脚冲突，但 **JTAG 和 UART 不建议同时操作**。它们共用板载 BL616 调试器和同一个 USB-C 接口。

推荐顺序：

```text
1. 用 Gowin Programmer 下载位流
2. 关闭 Programmer，释放调试器
3. 打开对应 COM 端口
4. 从电脑发送 MIDI 字节
```

注意：

- 当前工程没有使用 `V14/U15`，因此加入 `uart_rx/uart_tx` 后不会与现有音频、时钟和复位管脚冲突。
- 重新下载位流时，COM 端口可能短暂断开、重连或丢失数据。
- 不要让串口工具一直占用 COM 口再启动下载；若 Programmer 找不到设备，先关闭串口软件。
- 官方资料也说明调试器支持 UART，但某些固件下 UART/JTAG切换或波特率可能异常，必要时需更新调试器固件。[Sipeed 官方说明](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k#the-uart-of-the-onboard-debugger-cannot-be-used)

所以用于我们的测试完全可行：**下载完成后切到串口通信即可。**

> 好，现在做两件事，1.给fpga增加midi接受功能2.写一个能发midi的上位机程序

<details><summary>11 previous messages</summary>

> 我会把链路完整接通：板载 USB-UART 接收原始 MIDI 字节，解析 Note On/Off，再分配到现有 32 个逻辑槽位；同时做一个 Windows 可运行的虚拟 MIDI 键盘上位机。默认按 `31250 baud、8N1`，并保留可切换波特率以兼容板载调试器。先核对现有 RTL、测试结构和高云工程规范，再开始修改。
>
> 接口关系已经确认：当前顶层仍在上电后自动开启 32 个测试音，必须替换为 MIDI 事件驱动；否则电脑发来的音符无法成为唯一控制源。我会新增三个职责分离的模块（UART采样、MIDI字节解析、32槽位分配），不使用新的厂商 IP，也不会运行综合或布局布线。
>
> <details><summary>Created 5 files, edited 4 files, deleted 2 files</summary>
>
> - Wrote `./constraints/tang_mega_138k_audio_test.cst` (+2 -0)
> - Wrote `./src/midi_note_parser.v` (+60 -0)
> - Wrote `./src/midi_voice_allocator.v` (+113 -0)
> - Wrote `./src/top.v.v` (+53 -25)
> - Wrote `./src/uart_rx.v` (+106 -0)
> - Wrote `./synth1_9_18.gprj` (+3 -0)
> - Wrote `./sim/run_top_midi_test.do` (+35 -0)
> - Deleted `./sim/run_top_voice_init_test.do` (+0 -30)
> - Wrote `./sim/tb_top_midi_input.v` (+172 -0)
> - Deleted `./sim/tb_top_voice_init.v` (+0 -82)
> - Wrote `./src/midi_voice_allocator.v` (+6 -2)
> - Wrote `./src/top.v.v` (+4 -2)
>
> </details>
>
> FPGA 端的数据通路已经接入：上电后全部槽位保持关闭，收到 Note On 才分配槽位，Note Off 则关闭对应槽位；支持 Running Status、`Note On velocity=0` 和插入式实时消息。现在补上可直接操作的电脑端虚拟键盘，并把串口参数做成可选，以便板载调试器不接受 31250 时快速切到 115200 排查。
>
> <details><summary>Created 3 files, edited a file</summary>
>
> - Wrote `./docs/midi_uart_test.md` (+52 -0)
> - Wrote `./tools/midi_uart_sender.py` (+271 -0)
> - Wrote `./tools/requirements.txt` (+1 -0)
> - Wrote `./tools/midi_uart_sender.py` (+1 -1)
>
> </details>
>
> 实现已经落盘。验证会分三层同时进行：MIDI顶层串行输入仿真、原有32槽位调度回归、上位机与工程文件静态检查；按照项目规范，不启动高云综合和布局布线。
>
> 当前环境里历史记录中的 `E:\MODELSIMstandalone` 路径已不存在，所以仿真命令没有启动；这是工具路径变化，不是 RTL 失败。我先定位本机现有 ModelSim/Questa，再继续同一组回归。
>
> <details><summary>Edited 3 files</summary>
>
> - Wrote `./sim/tb_top_midi_input.v` (+1 -1)
> - Wrote `./docs/tdm_scheduler_validation.md` (+18 -7)
> - Wrote `./tools/midi_uart_sender.py` (+14 -7)
>
> </details>
>
> ModelSim 在这台环境里确实未安装/不可访问。为了不把“文本看起来正确”当成验证结果，我会临时使用独立的 Verilog/SystemVerilog 前端做语法与展开诊断；它不综合、不布局布线，也不改动工程文件。之后仍保留 ModelSim 自检脚本，方便你本机直接跑时序仿真。
>
> <details><summary>Edited a file</summary>
>
> - Wrote `./src/midi_voice_allocator.v` (+5 -3)
>
> </details>
>
> 替代前端检查已经通过：新增 RTL、顶层连接和测试平台均为 0 个编译/展开错误，新增文件也没有诊断警告；原工程仍有波表常量符号转换等既有警告，本次未扩大处理范围。电脑端程序通过 Python 编译和导入检查。唯一未能实际执行的是 ModelSim 动态仿真，因为当前机器找不到 `vsim.exe`，但自检 testbench 和运行脚本已经准备好。
</details>

两项功能都已完成，数据链现在是：

```text
电脑虚拟键盘
→ USB-UART 31250 baud
→ MIDI Note On/Off解析
→ 32槽位动态分配
→ TDM振荡器
→ FIR
→ PT8211音频输出
```

FPGA端新增：

- [uart_rx.v](./src/uart_rx.v:3)：50 MHz时钟下接收31250 baud、8N1串口。
- [midi_note_parser.v](./src/midi_note_parser.v:4)：支持Note On、Note Off、Running Status、实时消息插入及速度为0的Note Off。
- [midi_voice_allocator.v](./src/midi_voice_allocator.v:3)：管理32个复音槽位，支持空闲分配、同音重触发和满复音循环偷音。
- [top.v.v](./src/top.v.v:2)：已移除上电自动播放32个测试音，改为完全由MIDI控制。
- [管脚约束](./constraints/tang_mega_138k_audio_test.cst:22)：`uart_rx`连接到板载USB-UART的`V14`。
- 已将新增RTL加入高云工程文件。

音符范围限制为MIDI 21～108。当前力度只用于判断音符开启/关闭，暂未控制音量；Note Off仍是直接关闭，ADSR和Release阶段尚未加入。

上位机位于：

[midi_uart_sender.py](./tools/midi_uart_sender.py:39)

运行方法：

```powershell
python -m pip install -r tools/requirements.txt
python tools/midi_uart_sender.py
```

操作时：

1. 用`JTAG|UART` USB-C口连接电脑。
2. 下载位流后关闭Gowin Programmer。
3. 上位机选择对应COM端口。
4. 默认选择`31250 baud`并连接。
5. 用鼠标琴键或电脑键盘`A W S E D F T G Y H U J K`演奏。

详细说明在 [midi_uart_test.md](./docs/midi_uart_test.md:1)。

验证情况：

- RTL语法及顶层展开：0错误。
- 新增RTL：0诊断警告。
- Python编译和导入检查：通过。
- 工程XML和V14管脚约束检查：通过。
- 已添加完整串行波形自检：[run_top_midi_test.do](./sim/run_top_midi_test.do:1)。
- 当前环境找不到ModelSim的`vsim.exe`，因此尚未实际运行动态仿真。
- 按工程规范，没有运行高云综合或布局布线。

> 上位机显示连接成功，但是发送了指令后fpga没反应

<details><summary>3 previous messages</summary>

> 我先按链路分段定位：确认电脑识别到的串口设备和当前工程波特率，然后检查“物理RX是否跳变 → UART是否收出字节 → MIDI是否生成槽位更新”。连接成功只表示COM口被打开，不代表板载调试器实际以31250 bit/s输出。暂时不改综合逻辑。
>
> 已经找到一个很可能的直接原因：电脑枚举了两个FTDI串口——COM3是通道A、COM4是通道B；上位机当前自动选列表第一个端口，因此很可能连到了用于JTAG的COM3，而真正连接FPGA UART的通常是通道B（这里是COM4）。我再读取串口接口字段确认，并修正上位机的显示和默认选择。
>
> <details><summary>Edited 2 files</summary>
>
> - Wrote `./docs/midi_uart_test.md` (+5 -1)
> - Wrote `./tools/midi_uart_sender.py` (+27 -10)
>
> </details>
</details>

找到一个很可能的原因：电脑枚举出了两个FTDI串口：

```text
COM3：FTDI通道A，通常用于JTAG
COM4：FTDI通道B，连接FPGA UART
```

如果上位机连的是COM3，界面仍会显示“连接成功”，但发送的数据不会到达FPGA。

我已更新上位机，现在会明确显示：

```text
COM4 ... FTDI B / UART推荐
COM3 ... FTDI A / JTAG
```

请关闭旧上位机并重新启动：

```powershell
python tools/midi_uart_sender.py
```

然后按顺序测试：

1. 选择`COM4 - FTDI B / UART推荐`。
2. 波特率选择`31250`。
3. 点击连接。
4. 按虚拟键盘的C4。

如果仍然没声音，将波特率框手动改成：

```text
7812
```

再连接测试。部分旧版调试器固件存在“实际波特率为设置值4倍”的问题，`7812 × 4 ≈ 31250`。如果7812能够工作，就证明FPGA接收与MIDI逻辑正常，只需之后更新板载调试器固件。

这次只更新了上位机端口识别和诊断选项，不需要重新生成FPGA位流。若COM4在31250和7812下都没有反应，下一步应抓取：

```text
uart_rx
uart_byte_valid
uart_byte
midi_note_event_valid
voice_update_valid
```

由此可以准确判断问题停在物理串口、UART解码、MIDI解析还是槽位更新阶段。

> OK现在正常了，但是我发现同时演奏多个音时音频合成链路应该有问题，一演奏复音就会有一个低频的规律的噪声，噪音会随输入的信号的变化而变化

<details><summary>6 previous messages</summary>

> 这个现象先不要直接归因于“复音本身”：相近音程确实会产生拍频，但规律性杂音也可能来自混音定点截断、FIR握手或50 MHz下共享波表路径的时序错误。我先检查最新实现报告的时序余量、FIR接口配置和混音位宽，找能被证据支持的原因；这一轮先诊断，不改声音算法。
>
> 最新布局布线报告排除了一个重要方向：50 MHz时钟下没有setup/hold违例，实际Fmax约64.96 MHz，关键共享相位路径仍有约4.61 ns余量。因此“多音一开就因时序失败”目前没有证据。接下来我会用当前实际波表、相位步进和FIR系数离线复现双音混音，区分正常拍频与定点链路新产生的低频分量。
>
> 离线按当前RTL逐样本复现后，C4单音、C4+E4、相邻半音和五度都没有产生显著的新低频数字分量；150 Hz以下最强伪分量约低于主音53 dB。因此现有加法、右移和FIR系数本身不像会制造明显低频噪声。剩下最值得核对的是厂商FIR的`sync/valid`时序语义；我会按本地官方PDF手册核实这一点。
>
> Context compaction
>
> Source: automatic
> Status: completed
>
> 我已经把问题缩小了一轮：当前实现的时序、FIR 握手和离线数字模型都没有显示出明显的复音链路错误。我再核对一下 FIR 手册对应的接口时序图，然后给你一组很快能区分“正常拍频/模拟互调”和“FPGA 链路故障”的实验。
>
> 手册时序图也确认了：单通道时 `fir_sync_i` 应随每次有效输入一起拉高，当前接法是符合手册的，因此暂时不能把噪声归因于 FIR 接口误用。现在最可疑的是双音拍频或后级非线性产生的差频，其次才是运行时偶发的 overrun。
</details>

目前没有证据表明复音累加或 FIR 链路本身出错。检查结果是：

- 最新布局布线报告没有 setup/hold 违例，50 MHz 时钟余量正常。
- 32 路分时调度可以在下一个 768 kHz 采样周期前完成。
- FIR 单通道握手符合官方手册：单通道下 `fir_sync_i` 应随 `fir_valid_i` 一起有效。:codex-file-citation{path="D:/GOWINproject/synth1_9_18/高云规范化文件/高云规范化文件/IPUG543-2.2_Gowin_Advanced_FIR_Filter_IP用户手册.pdf" purpose="source"}
- 我用当前频率表、正弦表和 FIR 系数做了离线双音模拟，没有产生明显的新低频数字分量。
- 混音固定除以 32，两个声音的数字峰值仍有很大余量，基本可以排除数字削顶。

现在最像的是“拍频”或者模拟输出链路的差频互调。两个频率同时发声时，波形包络会按频率差规律起伏；功放、扬声器或耳机存在非线性时，还可能真正产生一个差频音。因此它会显得规律，而且随输入音符改变。

请先做这组测试：

1. C4（MIDI 60）单音：应当没有规律低频声。
2. C4 + C#4：频差约 `15.56 Hz`，应该出现明显缓慢起伏。
3. C4 + E4：频差约 `68.00 Hz`，起伏会明显变快。
4. C4 + C5：不应再出现十几或几十赫兹的慢速噪声。

判断方式：

- 噪声速度随上述频差明显变化：大概率是拍频或后级模拟互调，不是 FPGA 调度故障。
- 不管按什么音，噪声频率基本固定：需要检查 `oscillator_schedule_overrun`、`fir_input_overrun` 和 FIR 输出节奏。
- 只有板载扬声器有，而耳机/线路输出没有：重点怀疑 NS4263 功放、电源或扬声器的非线性。
- 相隔八度仍有同样的慢速噪声：就不属于正常拍频，应继续查数字链路。

下一步最有效的是把两个 sticky overrun 标志以及 `oscillator_mix_valid`、`fir_output_valid` 接入 GAO。这样可以直接确认硬件运行时有没有漏采样。

- 增加链路诊断
- 设计双音测试
- 分析录音频谱

> 相隔八度噪声就完全消失了，两个音相隔越小噪声越明显

这个现象基本可以确定是正常的“双音拍频”，不是 FPGA 复音链路故障。

两个频率接近的正弦波相加时，振幅会以频率差周期性起伏：

\[
f_\text{beat}=|f_2-f_1|
\]

例如：

- C4（261.63 Hz）+ C#4（277.18 Hz）：约 15.56 Hz 的慢速起伏，容易听成低频噪声或“突突声”
- C4 + E4：约 68 Hz，起伏更快
- C4 + C5：两者是严格的 1:2 倍频关系，合成波形稳定重复，所以慢速噪声消失

这与你观察到的“音程越小越明显、相隔八度完全消失”高度吻合。

需要注意：纯数字线性混音一般没有真的生成一个 15.56 Hz 音调，而是高频声音的幅度包络在起伏。但板载功放、扬声器或耳机会因为非线性，把这种包络进一步变成可听见的差频，所以听起来更像低频噪声。

因此当前不建议修改振荡器或 FIR。后续如果希望听感更像成品合成器，可以考虑：

- 增加 ADSR 包络，改善多个音同时触发时的生硬感
- 给不同声部做左右声道分配，减少单声道叠加产生的强拍频
- 加入每声部音量控制和混音增益管理
- 用耳机/线路输出与板载扬声器对比，检查功放是否放大了差频感

但只要两个接近频率在同一个单声道中同时存在，拍频无法在不改变音高或声道分配的情况下彻底消除。当前复音链路大概率是正常的。

> 开源合成器都是怎么解决这种问题的

<details><summary>2 previous messages</summary>

> 我会对照几个成熟开源合成器的实际实现来看，重点确认它们是“消除拍频”，还是通过包络、声像和增益结构让拍频不再像故障噪声。
>
> <details><summary>Searched the web</summary>
>
> Searched the web for `site:github.com/surge-synthesizer/surge voice pan envelope unison source code ...`
>
> Searched the web for `site:github.com/mtytel/vital "voice_amplitude" envelope stereo voice source ...`
>
> </details>
</details>

成熟开源合成器通常不会“消除拍频”，因为它是正确的声学结果；它们主要通过完整的声部结构，让拍频听起来像自然的复音，而不是裸露的周期噪声。

典型结构是：

```text
每个声部：
振荡器 → 音量包络/VCA → 滤波器 → 声像

所有声部：
立体声混音 → 主增益/效果 → DAC
```

例如 Surge XT 的每个 voice 都有独立的振幅包络、音量、声像以及左右声道输出，而不是直接把所有振荡器裸波形相加。[SurgeVoice 实现](https://github.com/surge-synthesizer/surge/blob/main/src/common/dsp/SurgeVoice.h)
Vital 同样提供 voice amplitude、stereo routing 和 stereo mode 等声部参数。[Vital 参数实现](https://github.com/mtytel/vital/blob/main/src/common/synth_parameters.cpp)
VCV Rack 的典型补丁也会把 VCO 经过 ADSR 控制的 VCA 后再混音，而不是直接混合持续满幅振荡器。[VCV Fundamental](https://github.com/VCVRack/Fundamental)

你当前实现与成熟合成器相比，主要缺少以下部分：

1. 每声部 ADSR 包络

目前 Note On 后正弦波立即从 0 相位满幅启动，Note Off 又立即切断。这会让所有音持续保持同等幅度，拍频特别明显，同时还会产生启停点击。

加入 ADSR 后，每个声部类似：

\[
voice[n] = oscillator[n]\times envelope[n]\times velocity
\]

它不会从数学上消灭拍频，但会让相邻音的干涉更自然。

2. MIDI 力度控制

目前接收了 velocity，但它没有真正参与振荡器音量。成熟合成器一般会把力度转换为非线性增益，例如近似：

\[
gain \approx \left(\frac{velocity}{127}\right)^2
\]

这样不同音符不再始终等幅。两个完全等幅的近频正弦产生的拍频最深，稍微改变声部幅度就能降低“完全忽大忽小”的感觉。

3. 立体声声像分配

当前 PT8211 左右声道发送的是完全相同的单声道信号。成熟合成器经常把声部轻微分散到左右声道，例如：

- voice 0：稍偏左
- voice 1：稍偏右
- voice 2：更偏左
- voice 3：更偏右

左右耳中不再是两音完全等幅叠加，拍频感会减弱。需要注意，如果最终通过单个板载扬声器播放，左右声道又会被物理合并，效果有限。

4. 合理的增益结构

你当前永远将总和除以 32。它能保证不削顶，但一两个音时电平非常低，后级需要很大的模拟增益，可能放大功放噪声和非线性差频。

更常见的方式是：

- 每声部先有独立增益；
- 根据最大复音数预留合理余量；
- 主输出设置可调音量；
- 必要时使用平滑限幅；
- 避免根据当前声部数量突然切换增益，否则会产生“抽吸”。

但限幅器不能解决拍频，而且过强的非线性限幅反而会制造更多互调分量。

5. 更丰富的音色和滤波

纯正弦波的两个频率非常干净，因此周期性包络特别容易被耳朵识别。实际合成器通常还有：

- 波表或锯齿等复杂频谱；
- 滤波器；
- 合唱、混响；
- 声部声像和微小音色差异。

这些会掩蔽拍频，但不是把它从数学上删除。

对这个 FPGA 工程，我建议按以下顺序升级：

1. 加入每声部 ADSR；
2. 让 MIDI velocity 控制声部振幅；
3. 把当前单声道混音改成左右双累加器，交错分配声部；
4. 重新设计混音增益，不再无条件固定除以 32；
5. 最后再加入滤波器、合唱或混响。

其中 ADSR 和力度控制最值得先做，也是完整合成器声部必需的组成部分。单纯加高通滤波器通常无效，因为数字信号里可能并不存在那个低频分量——你听到的是包络起伏；如果功放已经通过非线性产生了真实差频，高通只能缓解后果。

> 每声部 ADSR是什么

每声部 ADSR，就是给每一个正在演奏的音符分别配一个“音量随时间变化的包络”。

ADSR 是四个阶段：

```text
音量
最大值       /\
            /  \________
           /            \
静音 ______/              \____
           A   D    S      R       时间
       按键按下          按键松开
```

- A — Attack（起音）：按键后，音量从 0 平滑升到最大值。
- D — Decay（衰减）：从最大值下降到持续音量。
- S — Sustain（保持）：按住按键时维持的音量等级。
- R — Release（释音）：松开按键后，音量逐渐降到 0。

例如钢琴式设置可以是：

- Attack：5 ms
- Decay：300 ms
- Sustain：30%
- Release：500 ms

“每声部”的含义是，每个复音槽位都有自己独立的 ADSR 状态：

```text
槽位 0：C4 → 自己的振荡器 × 自己的 ADSR
槽位 1：E4 → 自己的振荡器 × 自己的 ADSR
槽位 2：G4 → 自己的振荡器 × 自己的 ADSR
                         ↓
                    全部相加混音
```

假设先按 C4，再按 E4：

- C4 的包络可能已经进入 Sustain；
- E4 的包络刚进入 Attack；
- 松开 C4 时，只有 C4 进入 Release；
- E4 仍然正常保持。

因此不能在最终混音之后只放一个公共 ADSR。否则松开一个键可能让整个和弦一起衰减。

在你当前工程中，状态基本只有：

```verilog
note_state[slot]
enable_state[slot]
phase_state[slot]
```

加入 ADSR 后，每个槽位还需要类似：

```verilog
envelope_level[slot]  // 当前包络幅度
envelope_stage[slot]  // IDLE/ATTACK/DECAY/SUSTAIN/RELEASE
velocity_gain[slot]   // MIDI 力度
```

每个声部输出从：

```verilog
voice_sample = wave_sample;
```

变成：

```verilog
voice_sample = wave_sample * envelope_level * velocity_gain;
```

Note On 不再直接满音量，而是：

```text
IDLE → ATTACK → DECAY → SUSTAIN
```

Note Off 也不再立即禁用振荡器，而是：

```text
当前阶段 → RELEASE → IDLE
```

只有 Release 降到零之后，槽位才真正释放。

它主要能改善：

- 按下和松开音符时的爆音；
- 多个音符同时满幅叠加的生硬感；
- 复音的层次和自然程度；
- MIDI 力度表现；
- 音色从持续测试正弦变成更像真正乐器。

不过 ADSR 不会从数学上消除两个近频率产生的拍频；它只是让声部不再从头到尾等幅裸混，从而令这种现象不那么突兀。

> adsr能被时分复用吗

可以，而且非常适合时分复用。你当前振荡器已经按 32 个槽位逐个计算，ADSR 可以并入同一条槽位流水线，每个物理 ADSR 计算单元依次处理 32 个声部。

基本结构是：

```text
每个采样周期开始
  ↓
slot 0：读相位 + ADSR 状态 → 算振荡器和包络 → 写回
slot 1：读相位 + ADSR 状态 → 算振荡器和包络 → 写回
...
slot 31：读相位 + ADSR 状态 → 算振荡器和包络 → 写回
  ↓
输出全部声部之和
```

需要为每个槽位保存状态，但计算硬件只需要一套：

```verilog
phase_state[0:31]
note_state[0:31]
envelope_level[0:31]
envelope_stage[0:31]
velocity_gain[0:31]
```

共享计算单元大致执行：

```verilog
case (current_envelope_stage)
    ATTACK:  next_level = current_level + attack_step;
    DECAY:   next_level = current_level - decay_step;
    SUSTAIN: next_level = sustain_level;
    RELEASE: next_level = current_level - release_step;
    default: next_level = 0;
endcase

scaled_sample = wave_sample * current_level;
```

然后把 `next_level` 和 `next_stage` 写回当前槽位。

### 资源需求

不需要 32 套 ADSR：

- 32 份包络电平寄存器；
- 32 份阶段状态寄存器；
- 一套加减比较逻辑；
- 一套乘法器，把波形乘以包络；
- 如果加入 velocity，包络与 velocity 可以预先合并，仍可只使用一套乘法器。

例如采用 16 位包络：

```text
32 × 16 bit 包络电平 = 512 bit
32 × 3 bit 阶段状态  = 96 bit
```

状态存储量很小。

### 更新时间选择

推荐每产生一个 768 kHz 内部采样，就让所有声部的 ADSR 更新一次。因为你现在每个内部采样本来就遍历 32 个槽位，所以整合起来很自然。

但 ADSR 的时间常数通常很慢，没有必要使用如此高的控制率。也可以每隔若干音频采样才更新一次，例如：

```text
768 kHz ÷ 16 = 48 kHz ADSR 更新率
```

中间采样保持当前包络值。48 kHz 对 ADSR 已经非常平滑，并能让步进值和长时间参数更容易表示。

不过以当前 FPGA 资源和时序来说，每个内部采样更新一次也完全可行。

### 对当前调度预算的影响

当前时钟是 50 MHz，内部采样率为 768 kHz：

\[
50\,000\,000 / 768\,000 \approx 65.1
\]

也就是每次内部采样之间约有 65 个系统时钟。现在遍历 32 个槽位，每槽大约一个周期，剩余约 33 个周期。

简单 ADSR 加减比较可以与相位更新并行，不增加槽位周期。包络乘法若综合成 DSP，也可以做成一至数级流水线，但必须相应调整：

- 槽位编号流水线；
- 包络状态写回地址；
- 混音累加时刻；
- `partial_valid` 产生时刻。

### 最适合这个工程的方案

建议第一版采用：

- 32 个独立 ADSR 状态；
- 一套共享 ADSR 更新逻辑；
- 16 位无符号包络，`0～65535`；
- Attack、Decay、Release 使用固定步长；
- Sustain 使用固定电平；
- 一套有符号波形 × 无符号包络乘法器；
- ADSR 与振荡器按相同槽位顺序时分复用；
- Release 到零后才把槽位置为空闲。

最大的结构性改动其实不是 ADSR 运算，而是 voice allocator：现在收到 Note Off 后会立刻禁用并释放槽位；加入 ADSR 后，应先进入 Release，等包络真正降到零再通知 allocator 该槽位可以重新使用。

> adsr状态如何确定？是不是需要计数器

ADSR 状态由“当前阶段 + 当前包络电平 + MIDI 事件”共同确定。可以使用计数器，但更适合当前时分复用架构的方法是：每个声部保存一个电平累加器，不必为每个声部配置独立计数器。

每个声部保存：

```verilog
envelope_stage[slot]  // IDLE、ATTACK、DECAY、SUSTAIN、RELEASE
envelope_level[slot]  // 例如16位，0～65535
gate_state[slot]      // MIDI按键是否还按着
```

状态转换为：

```text
                达到最大值
IDLE ──Note On──> ATTACK ─────> DECAY
                    │             │
                    │ Note Off    │ 到达 Sustain 电平
                    ↓             ↓
                  RELEASE <── SUSTAIN
                    │
                    │ 电平降到 0
                    ↓
                   IDLE
```

任何阶段收到 Note Off，都可以立即进入 RELEASE。

### 推荐：电平累加器方式

每次 ADSR 控制更新时，根据当前阶段加减固定步长：

```verilog
case (stage)
    IDLE: begin
        level <= 0;
    end

    ATTACK: begin
        if (level + ATTACK_STEP >= ENV_MAX) begin
            level <= ENV_MAX;
            stage <= DECAY;
        end else begin
            level <= level + ATTACK_STEP;
        end
    end

    DECAY: begin
        if (level <= SUSTAIN_LEVEL + DECAY_STEP) begin
            level <= SUSTAIN_LEVEL;
            stage <= SUSTAIN;
        end else begin
            level <= level - DECAY_STEP;
        end
    end

    SUSTAIN: begin
        level <= SUSTAIN_LEVEL;
    end

    RELEASE: begin
        if (level <= RELEASE_STEP) begin
            level <= 0;
            stage <= IDLE;
        end else begin
            level <= level - RELEASE_STEP;
        end
    end
endcase
```

这里的 `level` 本身就起到了“记录经过时间”的作用，所以不需要每个声部再加一个时间计数器。

### 步长怎么计算

假设 ADSR 更新频率为 48 kHz，16 位包络最大值为 65535。

Attack 设为 10 ms：

\[
N_A=48000\times0.010=480
\]

\[
AttackStep=\lceil65535/480\rceil=137
\]

Release 设为 200 ms：

\[
N_R=48000\times0.2=9600
\]

\[
ReleaseStep=\lceil65535/9600\rceil=7
\]

如果 Sustain 为 70%：

\[
SustainLevel\approx65535\times0.7=45875
\]

Decay 步长只需要覆盖从 65535 到 45875 的差值：

\[
DecayStep=
\left\lceil
\frac{65535-45875}{DecayTime\times48000}
\right\rceil
\]

### 要不要全局计数器

建议只使用一个共享分频计数器，产生 ADSR 控制更新脉冲：

```text
768 kHz 音频更新
      ↓ ÷16
48 kHz ADSR 控制更新
```

```verilog
reg [3:0] env_tick_counter;
wire env_tick = (env_tick_counter == 4'd15);
```

然后：

- 振荡器每次 768 kHz 采样都计算；
- ADSR 电平每 16 个采样更新一次；
- 所有槽位共享同一个 `env_tick`；
- 每个槽位保存自己的 `stage` 和 `level`。

即使所有声部共享更新脉冲，它们的状态仍是独立的，因为每个声部的 Note On 时刻和当前电平不同。

### 使用独立计数器的方案

另一种方法是每个声部保存：

```verilog
stage_counter[slot]
```

进入阶段时清零，根据计数值直接计算包络。这可以精确保证 Attack/Decay/Release 时长，但通常需要除法、乘法或者查表，硬件更复杂。

对于当前 FPGA，推荐使用：

```text
每声部：
16位 envelope_level
3位 envelope_stage
1位 gate_state

全局共享：
ADSR更新分频计数器
加法器/减法器/比较器
波形×包络乘法器
```

### MIDI 事件处理

Note On：

```verilog
gate  <= 1;
stage <= ATTACK;
level <= 0;       // 第一版可以从0重启
```

Note Off：

```verilog
gate  <= 0;
stage <= RELEASE;
// 不清零level，从当前音量开始释放
```

Release 到零：

```verilog
stage        <= IDLE;
voice_enable <= 0;
```

需要特别注意：Note Off 后不能立即释放 voice allocator 中的槽位。它必须继续占用槽位并完成 RELEASE，等电平归零后才能标记为空闲。否则 Release 阶段还没播放就会被新音符覆盖。

> 可以，按照推荐方案执行吧

<details><summary>8 previous messages</summary>

> 我会按“32 份声部状态 + 一套时分复用 ADSR 运算单元”的方案实现，并同步修改声部分配逻辑，确保 Note Off 后进入 Release、包络归零后才真正释放槽位。先核对现有模块接口和项目约束，再动 RTL 与仿真。
>
> 实现参数我先固定为适合板测的第一版：ADSR 控制率约 48 kHz，Attack 约 10 ms、Decay 约 100 ms、Sustain 70%、Release 从 Sustain 电平约 190 ms。包络每 16 个内部采样更新一次，但每个 768 kHz 音频采样都会乘上当前包络值。这样只增加一套共享乘法路径，不需要 32 套 ADSR。
>
> <details><summary>Edited 6 files</summary>
>
> - Wrote `./src/midi_voice_allocator.v` (+19 -1)
> - Wrote `./src/oscillator_tdm_bank.v` (+26 -3)
> - Wrote `./src/oscillator_tdm_core.v` (+135 -7)
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+31 -2)
> - Wrote `./sim/tb_top_midi_input.v` (+13 -3)
> - Wrote `./src/top.v.v` (+3 -0)
>
> </details>
>
> 核心路径已经接入：Note On 启动 Attack，Note Off 只进入 Release；Release 归零后通过 one-hot 完成掩码通知分配器释放槽位。接下来我在检查测试时序和端口完整性，重点防止新增的一次 Release 调度把原有计数断言弄偏。
>
> <details><summary>Edited 2 files</summary>
>
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+15 -4)
> - Wrote `./sim/tb_top_midi_input.v` (+8 -0)
>
> </details>
>
> 现有仿真器在这台机器上不可用，但之前保留的临时 `pyslang` 语法/展开检查器仍可使用。我会用它分别编译核心单元测试和顶层 MIDI 测试；不会调用 Gowin 综合或布局布线。
>
> 两套设计的语法与模块展开检查均为 0 错误。现在我做最后一轮 RTL 审阅，确认定点乘法符号、包络更新时间、释放完成与同音重触发之间没有竞态；随后会给出需要重新综合后重点观察的板测现象。
>
> <details><summary>Created a file, edited 3 files</summary>
>
> - Wrote `./docs/adsr_envelope.md` (+57 -0)
> - Wrote `./docs/adsr_envelope.md` (+2 -1)
> - Wrote `./src/oscillator_tdm_core.v` (+8 -5)
> - Wrote `./sim/tb_top_midi_input.v` (+2 -2)
>
> </details>
</details>

已按推荐方案完成时分复用 ADSR。

主要变更：

- 32 个声部分别保存 `stage/level/gate`。
- 所有声部共享一套 ADSR 更新逻辑和包络乘法器。
- 默认参数：
  - Attack：约 10 ms
  - Decay：约 102 ms
  - Sustain：70%
  - Release：约 191 ms
- Note Off 不再立即关闭振荡器，而是进入 Release。
- Release 归零后通过 `voice_idle_mask` 通知分配器释放槽位。
- 处理了同音重触发与延迟到达的 Release 完成脉冲之间的竞态。

相关文件：

- [oscillator_tdm_core.v](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_core.v:12)
- [oscillator_tdm_bank.v](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_bank.v:11)
- [midi_voice_allocator.v](/D:/GOWINproject/synth1_9_18/src/midi_voice_allocator.v:80)
- [top.v.v](/D:/GOWINproject/synth1_9_18/src/top.v.v:28)
- [ADSR 设计说明](/D:/GOWINproject/synth1_9_18/docs/adsr_envelope.md:1)

验证结果：

- TDM 核心测试：编译和模块展开 0 错误。
- 顶层 MIDI 测试：编译和模块展开 0 错误。
- 测试已增加“Note Off 后保持运行、Release 归零后释放”的检查。
- 当前机器没有可用的 ModelSim，所以没有执行动态 RTL 仿真。
- 按项目规范没有运行 Gowin 综合和布局布线。新增了 `17×17` 包络乘法路径，重新综合后需要重点确认它是否映射至 DSP，以及 `50 MHz` 时序是否仍然收敛。
- 静态检查仍有原工程中的缺少 timescale、符号转换等非阻断诊断。

目前 MIDI velocity 尚未加入增益计算。烧录后应该能明显听到平滑的起音和释音；两个持续保持的近频音仍会有自然拍频，ADSR 不会彻底消除它。

> 目前adsr释放时有抽吸感，如何解决

先区分两种“抽吸感”：

- 单音 Release 也有：主要是当前线性 Release 曲线听感不自然，或者输出电平太低导致尾音落入功放噪声。
- 只有相邻复音有：主要还是拍频；ADSR 只是让拍频包络一起衰减，并不能消除它。

目前 Release 使用固定减法：

```verilog
level <= level - RELEASE_STEP;
```

数学上它单调下降，不会自己产生周期性抽吸；但人耳对响度接近对数响应，因此线性幅度衰减通常会表现为“前面变化不明显，后面突然被吸走”。

更合适的方案是指数 Release：

```verilog
release_delta = envelope_level >> RELEASE_SHIFT;

if (envelope_level <= RELEASE_END_LEVEL) begin
    envelope_level <= 0;
    envelope_stage <= ENV_IDLE;
end else if (release_delta == 0) begin
    envelope_level <= envelope_level - 1;
end else begin
    envelope_level <= envelope_level - release_delta;
end
```

推荐第一版参数：

```verilog
RELEASE_SHIFT     = 11;
RELEASE_END_LEVEL = 64;
```

在当前约 48 kHz 包络更新率下：

- 时间常数约 43 ms；
- 衰减到约 `-60 dB` 需要约 300 ms；
- 尾音会比现在自然；
- 仍然只需要移位、减法和比较，不增加乘法器。

另外当前单声部数字电平较低：

```text
70% Sustain × 1/32混音缩放 ≈ -33 dBFS
```

这会使 Release 尾音很快接近板载功放的噪声和非线性区域，也可能形成“被噪声吸进去”的感觉。后续还应改善混音增益，但不要根据当前声部数量瞬间切换增益，否则会制造真正的 pumping。

建议处理顺序：

1. 把 Release 改成指数曲线。
2. Release 尾部低于阈值后直接归零，避免长时间整数爬行。
3. 用单音、八度、半音分别测试。
4. 如果只有半音仍然抽吸，那是拍频，需要用立体声声像或不同声部音量减弱。
5. 再调整固定混音增益，提高少量复音时的有效电平。

其中指数 Release 是最应该先改的。

> 单音 Release 也有，怎么改比较好

<details><summary>3 previous messages</summary>

> 单音也有的话，先只改 Release 曲线最稳妥：把当前固定步长线性下降改为指数下降，并在约 `-60 dB` 处直接归零。这样不动 Attack、Decay 和混音增益，板测时可以明确判断改善是否来自 Release 本身。
>
> <details><summary>Edited 4 files</summary>
>
> - Wrote `./docs/adsr_envelope.md` (+6 -3)
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+2 -1)
> - Wrote `./src/oscillator_tdm_bank.v` (+4 -2)
> - Wrote `./src/oscillator_tdm_core.v` (+13 -3)
> - Wrote `./docs/adsr_envelope.md` (+1 -1)
>
> </details>
>
> 指数曲线已经替换完成。默认 `RELEASE_SHIFT=11` 时，从 70% Sustain 到 `-60 dB` 阈值约 198 ms，整体时长与原先接近，因此这次板测主要比较“曲线形状”，不会把改善和大幅延长 Release 混在一起。以后若想更长，可把它改为 12（约 335 ms）。
</details>

已经把 Release 从线性下降改成指数下降：

```verilog
delta = envelope_level >> RELEASE_SHIFT;
envelope_level <= envelope_level - delta;
```

默认参数：

- `RELEASE_SHIFT = 11`
- 结束阈值约 `-60 dB`
- 从 70% Sustain 衰减到结束约 198 ms
- 低于阈值后直接归零，避免整数长尾

主要修改在 [oscillator_tdm_core.v](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_core.v:244)，参数传递和文档也已同步。两套 RTL 编译与模块展开检查均为 0 错误；未运行 Gowin 综合和布局布线。

如果希望 Release 更柔和、更长，可以将：

```verilog
RELEASE_SHIFT = 12
```

此时约为 335 ms。

建议先使用默认值 11 上板测试。若单音仍然出现“周期性”抽吸，而不只是尾音下降不自然，就不太可能是 ADSR，因为现在的包络严格单调下降。下一步应检查当前 `/32` 混音导致的低数字电平，以及板载功放在小信号区域的行为。

> 重新烧录后尾音下降还是不自然，会感觉有一个较原音符音调偏高的声音

<details><summary>1 previous message</summary>

> 这个新现象很像尾音进入了“低位数量化失真区”，不是 Release 曲线本身在升高音调。我先按当前位宽和 `/32` 混音缩放计算尾音还剩多少个 PCM 台阶，再决定是提高截止阈值、调整增益，还是加入抖动。
</details>

这基本可以定位为尾音的定点量化失真：听到的不是振荡器音高真的升高，而是低电平正弦逐渐只剩几个 PCM 台阶，产生了明显的高次谐波。

当前单声部经过 `/32` 混音缩放后：

| 包络电平 | 最终峰值 |
|---|---:|
| Sustain 70% | 约 716 LSB |
| -30 dB | 约 31 LSB |
| -36 dB | 约 15 LSB |
| -42 dB | 约 7 LSB |
| -48 dB | 约 3 LSB |
| -54 dB | 约 1 LSB |

目前 Release 一直下降到 `RELEASE_END_LEVEL=64`，此时输出只剩 `0～1 LSB`。波形已经不再像正弦，而接近稀疏脉冲，因此会产生比原音更高的谐波音。

另外，两级算术右移目前直接截断，对负数存在向负无穷舍入的偏置，也会加重尾音失真。

建议下一版同时做三项修改：

1. 提前结束 Release

```verilog
RELEASE_END_LEVEL = 16'd1024;
```

此时结束点约为包络 `-36 dB`，输出峰值仍有约 15 LSB，不会进入最严重的 1～3 LSB 失真区。

2. 为保持自然尾音，延长指数 Release

```verilog
RELEASE_SHIFT = 12;
```

配合阈值 1024，从 Sustain 到结束约 315 ms。这样不是直接砍短尾音，而是更慢、更平滑地下降，在进入严重量化区之前归零。

3. 两次缩放都改为四舍五入

包络乘法从：

```verilog
envelope_scaled = envelope_product >>> 16;
```

改成带舍入：

```verilog
envelope_scaled = (envelope_product + 34'sd32768) >>> 16;
```

Bank 的 `/32` 也从直接右移改为：

```verilog
scaled_sum = (combined_sum + 32'sd16) >>> 5;
```

这会显著减小负半波偏置以及低电平谐波失真。

如果这三项之后尾音仍有轻微调性残留，下一步是在最终截位前加入 TPDF dither，把相关的高频谐波变成非常微弱的非调性底噪。当前优先做“提高结束阈值 + 正确舍入”，比直接加入复杂的动态增益更稳妥。

> 后两项改动会不会太臃肿了

不会。第二项几乎没有硬件开销，第三项有少量开销，但可以暂缓。

- `RELEASE_SHIFT: 11 → 12` 只是改变常数右移位置，综合后基本是重新布线，不会增加计数器、乘法器或状态机。
- 带舍入缩放会增加一个 34 位常数加法器和一个 32 位常数加法器，资源不算大，但确实可能延长当前音频数据路径。

考虑到当前目标是先解决尾音高次谐波，建议采用最小修改：

```verilog
RELEASE_SHIFT     = 12;
RELEASE_END_LEVEL = 16'd1024;
```

效果是：

- Release 约 315 ms；
- 在输出跌到约 15 LSB 时结束；
- 避免进入 1～3 LSB 的严重量化失真区；
- 不增加实际运算单元；
- 不改变混音和 FIR 数据路径。

舍入可以先不加。如果重新烧录后高音残留已经消失，就没有必要继续增加逻辑。如果只是有所减轻但仍能听见，再单独加入舍入，这样也符合一次只改变一个关键因素的验证原则。

> 应用这三项吧

<details><summary>3 previous messages</summary>

> 我会一次应用三项：Release 阈值改为 1024、指数系数改为 `SHIFT=12`，并在包络乘法与 Bank `/32` 缩放前加入半 LSB 舍入。舍入加法会显式扩展一位，避免常数相加造成边界溢出。
>
> <details><summary>Edited 3 files</summary>
>
> - Wrote `./docs/adsr_envelope.md` (+7 -4)
> - Wrote `./src/oscillator_tdm_bank.v` (+14 -5)
> - Wrote `./src/oscillator_tdm_core.v` (+6 -3)
>
> </details>
>
> 三项 RTL 改动已完成。现在检查参数传播、扩位舍入表达式和测试平台，尤其确认参数化的 `OUTPUT_SHIFT` 在静态展开时不会产生负移位或位宽错误。
</details>

三项改动已全部应用：

- `RELEASE_SHIFT`：`11 → 12`
- `RELEASE_END_LEVEL`：`64 → 1024`
- 包络乘法和 Bank `/32` 缩放均加入半 LSB 舍入，并提前扩展位宽防止溢出

现在 Release 从 Sustain 到结束约 315 ms，并会在进入严重低位量化区前归零。

修改位置：

- [包络参数与乘法舍入](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_core.v:20)
- [Bank 混音舍入](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_bank.v:119)
- [ADSR 说明](/D:/GOWINproject/synth1_9_18/docs/adsr_envelope.md:14)

验证结果：

- TDM 核心编译与模块展开：0 错误
- 顶层 MIDI 链路编译与模块展开：0 错误
- 未运行 Gowin 综合和布局布线

重新烧录后，尾音应该更长、更平滑，并在出现 1～3 LSB 的明显高次谐波前结束。如果仍能听到偏高的尾音，下一步才考虑加入 TPDF dither。

> 还是有明显的较原音符音调偏高的声音，我觉得是目前幅值的数值压得太低了，应该取消目前统一除32的模式，改成同时演奏几个音就除几，可行吗

可行，而且能直接改善当前单音尾音位数不足的问题。

当前单音也固定 `/32`：

```text
Sustain 峰值约 716 LSB
Release 尾部只剩几个 LSB
```

如果改为按实际活动声部数归一化，单音时除以 1：

```text
Sustain 峰值约 22937 LSB
Release 结束阈值处仍约 512 LSB
```

有效精度会提高很多，高次量化谐波应该显著减弱。

但不能直接瞬间执行：

```verilog
output = voice_sum / active_voice_count;
```

否则声部数变化时，所有现存音符都会突然改变音量。例如两个音变成一个音，增益会从 `1/2` 瞬间变成 `1`，剩余音符突然增加 6 dB，产生明显的抽吸或点击。

推荐结构是：

```text
活动声部数
    ↓
倒数查找表：1/N
    ↓
平滑后的混音增益
    ↓
声部总和 × 混音增益
    ↓
舍入、饱和、FIR
```

具体设计：

1. 统计真正活动的声部

Release 中的声部仍算活动，直到包络归零：

```verilog
active_voice_count =
    slot_active[0] + slot_active[1] + ... + slot_active[31];
```

不能只统计当前按住的键，否则 Note Off 时增益会立即跳变。

2. 用倒数 LUT 代替硬件除法

使用 17 位 Q1.16 增益：

```text
N=0  → 65536  // 静音时保持1.0，为下一次单音准备
N=1  → 65536
N=2  → 32768
N=3  → 21845
N=4  → 16384
...
N=32 → 2048
```

然后：

```verilog
normalized_sum = (voice_sum * smoothed_gain + 32768) >>> 16;
```

这样只需要一个共享乘法器，不需要实现昂贵的动态除法器。

3. 平滑增益变化

目标增益变化时使用一阶平滑：

```verilog
gain <= gain + ((target_gain - gain) >>> GAIN_SMOOTH_SHIFT);
```

建议从：

```verilog
GAIN_SMOOTH_SHIFT = 12;
```

开始。在 768 kHz 更新率下，时间常数约 5.3 ms；完全稳定需要几十毫秒，可以避免声部数变化造成瞬时跳变。

4. 删除固定 `/32`

当前：

```verilog
scaled_sum = rounded_sum >>> 5;
```

改为乘以平滑后的 `1/N`。最终仍保留 16 位饱和保护，应对增益尚未稳定时的短暂过载。

这种方案的效果是：

- 单音：接近全幅输出，尾音精度明显提高。
- 两个音：每个约缩放一半。
- 多音：保证最坏情况下总和不会长期溢出。
- Release 声部结束时：增益平滑过渡，不会瞬间跳变。
- 偷音时：活动声部数量不变，混音增益也不变。

所以方案本身可行，但关键是“倒数 LUT + 平滑增益”，不能直接根据声部数瞬间切换除数。

> 在改动之前把这个项目上传到github吧，以后每次大改动之前就备份一次

<details><summary>10 previous messages</summary>

> 我先检查 GitHub CLI 登录状态、项目体积和需要排除的生成文件。由于目录里含厂商文档、实现产物和临时文件，我会默认创建私有仓库，并在首次提交前加合适的 `.gitignore`；这样以后可随时改成公开仓库。
>
> 当前机器没有安装 GitHub CLI，但 Git 和提交身份已配置。下一步我会检查是否已有 GitHub 凭据或相邻项目的远端信息，同时整理首个提交范围；不会读取或输出任何令牌内容。
>
> 我会把源码、约束、IP 配置、测试、工具和项目文档纳入版本控制；排除 `impl/`、仿真工作库、波形和临时渲染等可再生成文件。同时加入项目级协作规则：以后进行架构调整、数据通路重构等大改动前，先提交并推送当前状态。
>
> <details><summary>Created 3 files</summary>
>
> - Wrote `./.gitignore` (+24 -0)
> - Wrote `./AGENTS.md` (+10 -0)
> - Wrote `./README.md` (+16 -0)
>
> </details>
>
> 首次提交范围已检查：共 52 个文件，没有超过 GitHub 单文件上限，也没有发现令牌、密码或 API Key。最大的实现产物已被排除；厂商 PDF 会进入私有仓库，方便完整恢复开发环境。接下来创建本地基线提交。
>
> <details><summary>Created a file</summary>
>
> - Wrote `./.gitattributes` (+14 -0)
>
> </details>
>
> 本地基线提交已经创建，提交号是 `612dde3`，工作区干净。现在安装 GitHub CLI；安装后如果机器没有现成登录态，GitHub 会要求进行一次浏览器授权。
>
> GitHub CLI 已安装，但当前没有登录。接下来会打开 GitHub 的设备授权页面；请在浏览器中确认授权。这个步骤只授权官方 CLI，我不会读取你的密码或令牌。
>
> 授权命令正在等待浏览器确认。如果浏览器已打开 GitHub 页面，请完成登录并点击授权；命令会在授权成功后自动继续。
>
> 刚才的无窗口授权等待超时了，登录没有完成。我改为打开一个可见的 PowerShell 授权窗口；窗口里会显示一次性代码并打开 GitHub 页面。完成后可以关闭该窗口，我会自动检查登录状态并继续创建仓库。
</details>

本地备份已经完成：

- 已初始化 Git 仓库
- 已建立 `.gitignore`
- 已加入“大改前提交并推送”的项目规则
- 基线提交：`612dde3 chore: establish FPGA synth baseline`
- GitHub CLI 已安装

目前卡在 GitHub 登录授权。请在刚打开的 PowerShell/浏览器窗口中完成 GitHub 授权，然后回复我“授权完成”。我会继续创建私有仓库并推送。

> 授权完成

<details><summary>2 previous messages</summary>

> 我现在验证登录状态和工作区是否仍与基线提交一致，然后创建名为 `synth1_9_18` 的私有仓库并推送 `main`。如果同名仓库已经存在，我会改为连接现有仓库而不是覆盖它。
>
> 私有仓库已经创建并完成首次推送。我再核对远端可见性、默认分支和提交哈希，确认不是只创建了空仓库。
</details>

项目已成功上传到 GitHub 私有仓库：

https://github.com/haters-bot/synth1_9_18

- 默认分支：`main`
- 基线提交：`612dde3`
- 本地与远端提交哈希一致
- 当前工作区干净
- 已排除 Gowin 实现产物、仿真工作库、波形和临时文件
- 已写入项目规则：今后进行架构或音频数据通路等大改动前，先提交并推送当前状态

现在可以继续实现动态声部数归一化。

> 继续实现动态声部数归一化

<details><summary>8 previous messages</summary>

> 基线 `612dde3` 已经推送，满足大改前备份规则。现在按“活动声部包含 Release 声部、倒数 LUT、约 5.3 ms 平滑增益、最终饱和保护”实现；不会在音频路径里综合动态除法器。
>
> <details><summary>Edited 5 files</summary>
>
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+14 -2)
> - Wrote `./sim/tb_top_midi_input.v` (+7 -0)
> - Wrote `./src/midi_voice_allocator.v` (+6 -1)
> - Wrote `./src/oscillator_tdm_bank.v` (+89 -17)
> - Wrote `./src/top.v.v` (+5 -4)
>
> </details>
>
> 动态路径已经接入：单音目标增益为 1.0，32 音目标仍为 1/32；Release 中的声部继续计数，声部完全静音后才改变目标增益。现在先检查测试代码插入位置和所有模块端口，再处理可能的位宽诊断。
>
> <details><summary>Created a file, edited 4 files</summary>
>
> - Wrote `./docs/dynamic_voice_normalization.md` (+48 -0)
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+3 -2)
> - Wrote `./src/top.v.v` (+1 -1)
> - Wrote `./docs/adsr_envelope.md` (+4 -4)
> - Wrote `./sim/tb_top_midi_input.v` (+23 -21)
>
> </details>
>
> 静态编译和模块展开均为 0 错误，倒数表 `N=2…32` 也已逐项与 `round(65536/N)` 校验一致。最后我会检查差异和空白错误，然后按项目规则把这次动态归一化作为一个新检查点提交并推送。
>
> <details><summary>Edited 2 files</summary>
>
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+1 -1)
> - Wrote `./src/oscillator_tdm_bank.v` (+2 -1)
>
> </details>
>
> 本地功能提交已经生成：`7a2612d`。首次推送因 GitHub 443 连接超时失败，代码没有丢失；我正在重试并核对远端提交。
>
> 连续三次 Git HTTPS 推送都被当前网络到 `github.com:443` 的连接重置；GitHub API 本身可达，说明账号和仓库正常。为避免用 API 另造一条与本地不一致的提交历史，我保留本地标准 Git 提交，先核对本地/远端状态后交付；网络恢复后只需重试一次 `git push origin main`。
</details>

动态声部数归一化已经实现。

现在的行为：

- 单音：增益 `1.0`，不再固定除以 32。
- 两音：目标增益 `1/2`。
- 三音：目标增益约 `1/3`。
- 最高 32 音：目标增益 `1/32`。
- Release 中的声部仍计入活动数，包络归零后才移出。
- 增益变化经过约 5.3 ms 时间常数平滑。
- 静音时自动恢复单位增益，保证下一次单音满增益启动。
- 使用倒数 LUT 和乘法器，没有动态除法器。
- 最终保留舍入和 16 位饱和保护。

主要修改：

- [midi_voice_allocator.v](/D:/GOWINproject/synth1_9_18/src/midi_voice_allocator.v:20)：活动声部计数
- [oscillator_tdm_bank.v](/D:/GOWINproject/synth1_9_18/src/oscillator_tdm_bank.v:115)：倒数 LUT、平滑增益和归一化乘法
- [top.v.v](/D:/GOWINproject/synth1_9_18/src/top.v.v:25)：顶层连接
- [dynamic_voice_normalization.md](/D:/GOWINproject/synth1_9_18/docs/dynamic_voice_normalization.md:1)：设计说明

验证结果：

- 倒数表 `N=2～32` 全部校验正确。
- TDM 核心编译/展开：0 错误。
- 顶层 MIDI 链路编译/展开：0 错误。
- 未运行 Gowin 综合和布局布线；重新综合后需要确认新增归一化乘法器映射到 DSP，并检查 `50 MHz` 时序。

本地检查点已提交：

```text
7a2612d feat: normalize mix by active voice count
```

GitHub 推送连续三次因当前网络无法连接 `github.com:443` 而失败，本地分支目前领先远端一个提交，工作区是干净的。网络恢复后执行：

```powershell
git push origin main
```

即可完成备份。

> 把波表换成三角波试试，看看情况

<details><summary>6 previous messages</summary>

> 这次只替换振荡器波表，不改 MIDI、ADSR、归一化或 FIR。先确认当前提交状态并重试推送上一版动态归一化检查点，然后用独立的 `triangle_lut` 替换核心中的正弦查表，便于随时切回。
>
> <details><summary>Ran a command</summary>
>
> - Ran `git status -sb; git log -2 --oneline; git push origin main`
>
> </details>
>
> 上一版已成功推送到 GitHub。三角波会采用 256 相位地址、16 位有符号输出，零相位从 0 开始，上升至正峰、回到 0、下降至负峰再返回；这样 Note On 相位复位仍从零交叉开始，不会额外制造起音跳变。
>
> <details><summary>Created 2 files, edited 5 files, ran a command</summary>
>
> - Wrote `./README.md` (+1 -1)
> - Wrote `./docs/triangle_wavetable_test.md` (+23 -0)
> - Wrote `./sim/run_tdm_test.do` (+1 -1)
> - Wrote `./sim/run_top_midi_test.do` (+1 -1)
> - Wrote `./src/oscillator_tdm_core.v` (+1 -1)
> - Wrote `./src/triangle_lut.v` (+30 -0)
> - Wrote `./synth1_9_18.gprj` (+1 -0)
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; @'
> import importlib.util, os, sys
> from pathlib import Path
> base=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> sys.path.insert(0,base)
> os.add_dll_directory(base+r'\pyslang.libs')
> os.add_dll_directory(base+r'\nanobind_backend.libs')
> import nanobind_backend
> spec=importlib.util.spec_from_file_location('pyslang',base+r'\pyslang\pyslang.pyd')
> s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
> root=Path(r'D:\GOWINproject\synth1_9_18')
> tests={
>  'tdm':['src/freq_lut.v','src/triangle_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v'],
>  'top_midi':['src/reset_release_sync.v','src/uart_rx.v','src/midi_note_parser.v','src/midi_voice_allocator.v','src/freq_lut.v','src/triangle_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','src/fir_decimator_8x_wrapper.v','src/pt8211_tx.v','sim/fir_decimator_8x_ip_stub.v','src/top.v.v','sim/tb_top_midi_input.v']}
> failed=False
> for name,files in tests.items():
>  c=s.ast.Compilation()
>  for rel in files:c.addSyntaxTree(s.syntax.SyntaxTree.fromFile(str(root/rel)))
>  c.getRoot();errors=[d for d in c.getAllDiagnostics() if d.isError() and 'MissingTimeScale' not in str(d.code)]
>  print(f'{name}: compile/elaboration errors={len(errors)}')
>  for d in errors:print(f'  {d.code} {d.location} {d.args}')
>  failed|=bool(errors)
> sys.stdout.flush();os._exit(1 if failed else 0)
> '@ | python -; git diff --check; git status --short`
>
> </details>
>
> 三角波模块和两套顶层展开检查均为 0 错误。现在再核对波表关键点、周期边界和直流均值，避免由于正负峰不对称引入额外 DC，然后提交这个可回退的波形检查点。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `python -c "vals=[]
> for a in range(256):
>  q=a>>6;r=(a&63)*512
>  v=(r if q==0 else 32767-r if q==1 else -r if q==2 else -32768+r)
>  vals.append(v)
> print('key_points=',[(hex(i),vals[i]) for i in (0,63,64,127,128,191,192,255)])
> print('min=',min(vals),'max=',max(vals),'sum=',sum(vals),'mean=',sum(vals)/256)
> print('max_adjacent_step=',max(abs(vals[(i+1)%256]-vals[i]) for i in range(256)))"`
> - Ran `git add README.md docs/triangle_wavetable_test.md sim/run_tdm_test.do sim/run_top_midi_test.do src/triangle_lut.v src/oscillator_tdm_core.v synth1_9_18.gprj; git commit -m "feat: switch oscillator wavetable to triangle"; git push origin main; git status -sb; git log -3 --oneline`
>
> </details>
</details>

已将振荡器切换为三角波，并推送到 GitHub。

主要改动：

- 新增 [triangle_lut.v](/D:/GOWINproject/synth1_9_18/src/triangle_lut.v:1)
- 振荡器核心由 `sine_lut` 切换为 `triangle_lut`
- 更新 Gowin 工程和两套仿真脚本
- 原正弦表继续保留，方便随时切回
- 添加了 [三角波测试说明](/D:/GOWINproject/synth1_9_18/docs/triangle_wavetable_test.md:1)

验证结果：

- 波表范围：`-32768～32767`
- 最大相邻步长：512
- 直流偏置：仅 `-0.25 LSB`
- TDM 和顶层 MIDI 编译/展开：均为 0 错误
- 未运行 Gowin 综合和布局布线

GitHub 检查点：

```text
db3be49 feat: switch oscillator wavetable to triangle
```

本地与远端已经同步。

三角波本身包含明显的 3、5、7 次等奇次谐波，因此整体听起来会比正弦波明亮。板测时重点判断：偏高声音是全程存在，还是只在 Release 尾部异常突出。

> 把波表换成三角波试试，看看情况

已经切换成三角波并推送完成，当前工程直接重新综合、烧录即可测试。

提交：

```text
db3be49 feat: switch oscillator wavetable to triangle
```

测试时重点听：

- 偏高声音是否从按键开始就存在：这是三角波正常的奇次谐波。
- 是否只在 Release 尾部突然变明显：仍可能是低电平量化或模拟输出问题。
- 单音音量是否明显提高：可验证动态声部归一化是否生效。
- 相邻复音的拍频是否仍规律变化。

当前三角波入口在 [triangle_lut.v](/D:/GOWINproject/synth1_9_18/src/triangle_lut.v:1)，原正弦表仍保留，可随时切回。

> 感觉听起来不像三角波

<details><summary>4 previous messages</summary>

> 我先确认你烧录的实现是否真的包含 `triangle_lut`，再用当前频率表、三角波公式和 FIR 系数做一次频谱核对。这样可以区分“仍烧着旧正弦版本”和“三角波谐波被滤波/扬声器掩蔽”。
>
> <details><summary>Ran 3 commands</summary>
>
> - Ran ``$files = @('impl\pnr\synth1_9_18.fs','impl\pnr\synth1_9_18_tr_content.html','impl\gwsynthesis\synth1_9_18.vg','src\triangle_lut.v','synth1_9_18.gprj'); foreach ($f in $files) { if (Test-Path $f) { $x=Get-Item $f; '{0}`t{1}`t{2:N2} MB' -f $x.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),$f,($x.Length/1MB) } }; rg -n -i "triangle_lut|u_shared_triangle" impl src synth1_9_18.gprj -g "*.html" -g "*.log" -g "*.vg" -g "*.v" -g "*.gprj"``
> - Ran `Select-String -Path src\freq_lut.v -Pattern "7'd60"; Get-Content ip\fir_decimator_8x\CONFIG.md -Encoding UTF8 | Select-Object -First 100; Get-Content ip\fir_decimator_8x\coeff_q17.txt | Select-Object -First 10`
> - Ran `@'
> import re
> from pathlib import Path
> import numpy as np
> fs_in=768000.0
> fs_out=96000.0
> text=Path('src/freq_lut.v').read_text(encoding='utf-8')
> m=re.search(r"7'd60:\s*data\s*=\s*32'h([0-9A-Fa-f]+)",text)
> step=int(m.group(1),16)
> f=step*fs_in/(2**32)
> N=int(fs_in*0.6)
> phase=(np.arange(N,dtype=np.uint64)*np.uint64(step)) & np.uint64(0xffffffff)
> addr=(phase>>np.uint64(24)).astype(np.int32)
> q=addr>>6
> r=(addr&63)*512
> x=np.select([q==0,q==1,q==2],[r,32767-r,-r],default=-32768+r).astype(np.float64)
> h=np.loadtxt('ip/fir_decimator_8x/coeff_q17.txt',dtype=np.float64)/131072.0
> y=np.convolve(x,h,mode='valid')[::8]
> y=y[5000:]
> t=np.arange(len(y))/fs_out
> amps=[]
> for k in (1,2,3,4,5,7,9):
>  c=2*np.abs(np.dot(y,np.exp(-2j*np.pi*(k*f)*t)))/len(y)
>  amps.append((k,c))
> a1=amps[0][1]
> print(f'actual fundamental={f:.9f} Hz, output samples={len(y)}')
> for k,a in amps:
>  print(f'H{k}: {20*np.log10(max(a,1e-20)/a1):7.2f} dBc')
> '@ | python -`
>
> </details>
>
> 最新综合和布局布线产物明确包含 `u_shared_triangle_lut`，所以不是旧比特流；离线模型也测到标准三角波频谱：3 次谐波约 ?19 dBc、5 次约 ?28 dBc。再检查一下这次实现的时序报告，排除新增归一化乘法器造成的时序违例。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `rg -n -i "setup.*violat|hold.*violat|worst.*slack|WNS|TNS|Fmax|Maximum Frequency|Slack" impl\pnr\synth1_9_18_tr_content.html impl\pnr\synth1_9_18_tr.html impl\pnr\synth1_9_18.log -g "*.html" -g "*.log" | Select-Object -First 80`
> - Ran `Get-Content impl\pnr\synth1_9_18_tr_content.html | Select-Object -Skip 80 -First 85`
>
> </details>
</details>

检查结果表明当前烧录文件确实包含三角波，不是旧正弦版本：

- 最新 bitstream：2026-10-03 10:57
- 综合报告中存在 `u_shared_triangle_lut`
- 时序无违例，实际 Fmax 为 60.820 MHz
- 离线频谱符合标准三角波：
  - 3 次谐波：约 `-19.03 dBc`
  - 5 次谐波：约 `-27.96 dBc`
  - 7 次谐波：约 `-33.85 dBc`
  - 偶次谐波低于约 `-53 dBc`

三角波听起来确实可能比较接近正弦波，因为基波占绝对主导，3 次谐波只有基波幅度的约 11%。尤其在以下情况会更像正弦：

- 演奏较高音符，高次谐波超出听觉范围或被 FIR 滤除；
- 使用板载小扬声器，高频响应较弱；
- 音量不高；
- 没有与正弦波即时 A/B 对比。

建议先用 C2～C3 的低音，通过耳机测试。低音三角波的奇次谐波更容易辨认。

更明确的诊断方法是暂时换成方波。方波的 3 次谐波约为 `-9.54 dBc`，听感会明显得多：

- 如果方波仍听起来接近正弦，问题可能在 FIR、DAC、功放或扬声器响应。
- 如果方波明显变亮，说明当前三角波实际正常，只是听感比预期柔和。
- 如果 Release 尾部的偏高声音在正弦、三角和方波下都相似，基本可以确认它不来自波表。

> 暂时换成方波看看

<details><summary>9 previous messages</summary>

> Context compaction
>
> Source: automatic
> Status: completed
>
> 我先把共享波表临时切成直流对称的硬方波，并同步工程与仿真文件；它会明显更亮，也可能暴露混叠，正适合判断问题是在波形生成端还是后级链路。这个改动较小，当前三角波版本已经推送备份，因此不额外做前置备份。
>
> <details><summary>Created 2 files, edited 5 files, ran 4 commands</summary>
>
> - Ran `git status --short; rg -n "triangle_lut|sine_lut" src sim *.gprj README.md docs -g "*"`
> - Ran `Get-ChildItem -Filter *.gprj | Select-Object -ExpandProperty FullName; Get-Content src\triangle_lut.v; Get-Content src\oscillator_tdm_core.v -TotalCount 145; Get-Content sim\run_tdm_test.do -TotalCount 30; Get-Content sim\run_top_midi_test.do -TotalCount 25`
> - Ran `Select-String -Path synth1_9_18.gprj -Pattern "lut.v"; rg -n "triangle|Triangle|三角" README.md docs src sim synth1_9_18.gprj -g "!sim/work*/*"`
> - Ran `rg -n "sample_out|expected|assert|triangle|sine" sim\tb_oscillator_tdm_bank.v sim\tb_top_midi_input.v; Get-Content synth1_9_18.gprj -TotalCount 35; Get-Content README.md -TotalCount 30`
> - Wrote `./README.md` (+1 -1)
> - Wrote `./docs/square_wave_diagnostic.md` (+15 -0)
> - Wrote `./sim/run_tdm_test.do` (+1 -1)
> - Wrote `./sim/run_top_midi_test.do` (+1 -1)
> - Wrote `./src/oscillator_tdm_core.v` (+1 -1)
> - Wrote `./src/square_lut.v` (+13 -0)
> - Wrote `./synth1_9_18.gprj` (+1 -0)
>
> </details>
>
> 方波源已经接入：正负半周分别为 `+32767/-32767`，均值为零；相位复位时会从正满幅开始，因此起音点击声比三角波明显是预期现象，不应把它误判为原来的尾音问题。现在做 RTL 语法/展开检查，并确认工程只改到了波形选择相关文件。
>
> <details><summary>Edited 2 files, ran 19 commands</summary>
>
> - Ran `git diff --check; git diff --stat; git diff -- src/square_lut.v src/oscillator_tdm_core.v synth1_9_18.gprj sim/run_tdm_test.do sim/run_top_midi_test.do README.md docs/square_wave_diagnostic.md; $toolsToFind = 'iverilog','verilator','vlog'; foreach ($toolName in $toolsToFind) { $cmdInfo = Get-Command $toolName -ErrorAction SilentlyContinue; if ($cmdInfo) { "$toolName=$($cmdInfo.Source)" } }`
> - Ran `Get-ChildItem 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 20 FullName; git status --short`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import pyslang; print(pyslang.__version__)"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import pyslang; files=['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v']; trees=pyslang.SyntaxTree.fromFiles(files); c=pyslang.Compilation(); [c.addSyntaxTree(t) for t in trees]; ds=list(c.getAllDiagnostics()); print('TDM diagnostics:',len(ds)); [print(d) for d in ds]"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import pyslang; print(pyslang.__file__); print([x for x in dir(pyslang) if 'Syntax' in x or 'Compilation' in x][:20])"; Get-Content 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\__init__.py' -TotalCount 40`
> - Ran `Get-ChildItem 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang' | Select-Object Name,Length`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys; p=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang.pyd'; s=importlib.util.spec_from_file_location('pyslang.pyslang',p); m=importlib.util.module_from_spec(s); sys.modules['pyslang.pyslang']=m; s.loader.exec_module(m); print(m.__version__); print(hasattr(m,'SyntaxTree'))"`
> - Ran `Get-ChildItem 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify' -Directory | Select-Object Name; Get-ChildItem 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang.libs' -ErrorAction SilentlyContinue | Select-Object Name`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys,os; root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend; p=root+r'\pyslang\pyslang.pyd'; s=importlib.util.spec_from_file_location('pyslang.pyslang',p); m=importlib.util.module_from_spec(s); sys.modules['pyslang.pyslang']=m; s.loader.exec_module(m); print(m.__version__); print(hasattr(m,'SyntaxTree'))"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys,os; root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend; p=root+r'\pyslang\pyslang.pyd'; s=importlib.util.spec_from_file_location('pyslang.pyslang',p); m=importlib.util.module_from_spec(s); sys.modules['pyslang.pyslang']=m; s.loader.exec_module(m); print([x for x in dir(m) if not x.startswith('_')]); print(hasattr(m.syntax,'SyntaxTree')); print(hasattr(m.ast,'Compilation'))"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys,os; root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend; s=importlib.util.spec_from_file_location('pyslang.pyslang',root+r'\pyslang\pyslang.pyd'); m=importlib.util.module_from_spec(s);sys.modules['pyslang.pyslang']=m;s.loader.exec_module(m); files=['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v']; trees=m.syntax.SyntaxTree.fromFiles(files); c=m.ast.Compilation();[c.addSyntaxTree(t) for t in trees]; ds=list(c.getAllDiagnostics()); print('TDM diagnostics:',len(ds)); print('errors:',sum(d.severity==m.DiagnosticSeverity.Error for d in ds)); [print(d) for d in ds]"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys,os; root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend; s=importlib.util.spec_from_file_location('pyslang.pyslang',root+r'\pyslang\pyslang.pyd'); m=importlib.util.module_from_spec(s);sys.modules['pyslang.pyslang']=m;s.loader.exec_module(m); files=['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v']; tree=m.syntax.SyntaxTree.fromFiles(files); c=m.ast.Compilation();c.addSyntaxTree(tree); ds=list(c.getAllDiagnostics()); print('TDM diagnostics:',len(ds)); print('errors:',sum(d.severity==m.DiagnosticSeverity.Error for d in ds)); [print(d) for d in ds]"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; python -c "import importlib.util,sys,os; root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend; s=importlib.util.spec_from_file_location('pyslang.pyslang',root+r'\pyslang\pyslang.pyd'); m=importlib.util.module_from_spec(s);sys.modules['pyslang.pyslang']=m;s.loader.exec_module(m); tree=m.syntax.SyntaxTree.fromFiles(['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v']); c=m.ast.Compilation();c.addSyntaxTree(tree); ds=list(c.getAllDiagnostics()); print(dir(ds[0])); print(ds[0].code); print(dir(c)[:80])"`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root = r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> os.add_dll_directory(root + r'\pyslang.libs')
> os.add_dll_directory(root + r'\nanobind_backend.libs')
> import nanobind_backend
> spec = importlib.util.spec_from_file_location('pyslang.pyslang', root + r'\pyslang\pyslang.pyd')
> slang = importlib.util.module_from_spec(spec)
> sys.modules['pyslang.pyslang'] = slang
> spec.loader.exec_module(slang)
> checks = {
>     'TDM': [
>         'src/freq_lut.v', 'src/square_lut.v',
>         'src/oscillator_tdm_core.v', 'src/oscillator_tdm_bank.v',
>         'sim/tb_oscillator_tdm_bank.v'
>     ],
>     'TOP_MIDI': [
>         'sim/fir_decimator_8x_ip_stub.v', 'src/reset_release_sync.v',
>         'src/uart_rx.v', 'src/midi_note_parser.v',
>         'src/midi_voice_allocator.v', 'src/freq_lut.v',
>         'src/square_lut.v', 'src/oscillator_tdm_core.v',
>         'src/oscillator_tdm_bank.v', 'src/fir_decimator_8x_wrapper.v',
>         'src/pt8211_tx.v', 'src/top.v.v', 'sim/tb_top_midi_input.v'
>     ]
> }
> failed = False
> for name, files in checks.items():
>     tree = slang.syntax.SyntaxTree.fromFiles(files)
>     compilation = slang.ast.Compilation()
>     compilation.addSyntaxTree(tree)
>     diagnostics = list(compilation.getAllDiagnostics())
>     errors = [d for d in diagnostics if d.isError()]
>     print(f'{name}: {len(errors)} errors, {len(diagnostics) - len(errors)} warnings')
>     for diag in errors:
>         print(f'  {diag.code}')
>     failed = failed or bool(errors)
> raise SystemExit(1 if failed else 0)
> '@; python -c $verify`
> - Ran `rg -n "class CompilationOptions|defaultTimeScale|MissingTimeScale" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\ast.pyi' 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\__init__.pyi' | Select-Object -First 40`
> - Ran `rg -n -A35 "class CompilationOptions" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\ast.pyi'; rg -n -A25 "class TimeScale" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\__init__.pyi' | Select-Object -First 40`
> - Ran `rg -n -A18 "class Compilation:" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\ast.pyi'; rg -n -A18 "class TimeUnit" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\__init__.pyi' | Select-Object -First 30`
> - Ran `rg -n -A28 "class Bag" 'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify\pyslang\pyslang\__init__.pyi' | Select-Object -First 40`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root = r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> os.add_dll_directory(root + r'\pyslang.libs')
> os.add_dll_directory(root + r'\nanobind_backend.libs')
> import nanobind_backend
> spec = importlib.util.spec_from_file_location('pyslang.pyslang', root + r'\pyslang\pyslang.pyd')
> slang = importlib.util.module_from_spec(spec)
> sys.modules['pyslang.pyslang'] = slang
> spec.loader.exec_module(slang)
> checks = {
>     'TDM': ['src/freq_lut.v', 'src/square_lut.v', 'src/oscillator_tdm_core.v', 'src/oscillator_tdm_bank.v', 'sim/tb_oscillator_tdm_bank.v'],
>     'TOP_MIDI': ['sim/fir_decimator_8x_ip_stub.v', 'src/reset_release_sync.v', 'src/uart_rx.v', 'src/midi_note_parser.v', 'src/midi_voice_allocator.v', 'src/freq_lut.v', 'src/square_lut.v', 'src/oscillator_tdm_core.v', 'src/oscillator_tdm_bank.v', 'src/fir_decimator_8x_wrapper.v', 'src/pt8211_tx.v', 'src/top.v.v', 'sim/tb_top_midi_input.v']
> }
> options = slang.ast.CompilationOptions()
> base = slang.TimeScaleValue(slang.TimeUnit.Nanoseconds, slang.TimeScaleMagnitude.One)
> precision = slang.TimeScaleValue(slang.TimeUnit.Picoseconds, slang.TimeScaleMagnitude.One)
> options.defaultTimeScale = slang.TimeScale(base, precision)
> bag = slang.Bag()
> bag.compilationOptions = options
> failed = False
> for name, files in checks.items():
>     tree = slang.syntax.SyntaxTree.fromFiles(files)
>     compilation = slang.ast.Compilation(bag)
>     compilation.addSyntaxTree(tree)
>     diagnostics = list(compilation.getAllDiagnostics())
>     errors = [d for d in diagnostics if d.isError()]
>     print(f'{name}: {len(errors)} errors, {len(diagnostics) - len(errors)} warnings')
>     for diag in errors:
>         print(f'  {diag.code}')
>     failed = failed or bool(errors)
> raise SystemExit(1 if failed else 0)
> '@; python -c $verify`
> - Wrote `./docs/triangle_wavetable_test.md` (+1 -1)
> - Wrote `./src/oscillator_tdm_core.v` (+1 -1)
>
> </details>
>
> 两条关键链路（TDM 振荡器与完整 MIDI 顶层）均已通过展开检查，都是 0 个 RTL 错误；没有运行 Gowin 综合或布局布线。接下来把这个可烧录的方波诊断版本作为小检查点提交并推送，方便之后一键回退到三角波版本。
>
> <details><summary>Ran a command</summary>
>
> - Ran `git diff --check; git status --short; git add README.md docs/triangle_wavetable_test.md docs/square_wave_diagnostic.md sim/run_tdm_test.do sim/run_top_midi_test.do src/oscillator_tdm_core.v src/square_lut.v synth1_9_18.gprj; git commit -m "test: switch oscillator to square wave"; git push origin main`
>
> </details>
>
> 本地提交已经完成；推送时网络连接在接收确认阶段被重置，Git 同时提示 “Everything up-to-date”。我再核对远端 `main` 的实际提交号，避免把“可能已上传”当成成功。
>
> <details><summary>Ran 3 commands</summary>
>
> - Ran `$localHead = git rev-parse HEAD; $remoteHead = git ls-remote origin refs/heads/main | ForEach-Object { ($_ -split '\s+')[0] }; "LOCAL=$localHead"; "REMOTE=$remoteHead"; git status --short`
> - Ran `git push origin main`
> - Ran `git status --short; git status -sb; git log -1 --oneline`
>
> </details>
</details>

已临时切换为硬方波：

- 方波幅值为 `+32767 / -32767`，无直流偏置。
- Gowin 工程和两套仿真脚本已同步更新。
- TDM 与完整 MIDI 顶层展开检查均为 **0 错误**。
- 未运行 Gowin 综合，请重新综合、生成 bitstream 并烧录。
- 本地提交：`cf4b50b test: switch oscillator to square wave`

方波应该明显比三角波明亮、尖锐。高音可能出现混叠，起音也可能有点击声，这次仅用于诊断。

重点观察：

- 如果方波依旧接近正弦波，问题大概率在 FIR、DAC、功放或扬声器的频响。
- 如果方波明显明亮，说明波形生成链路正常，之前的三角波本身只是听起来比较柔和。
- 如果那个偏高尾音依然存在，基本可以排除波表形状。

相关文件：[square_lut.v](./src/square_lut.v) 和 [oscillator_tdm_core.v](./src/oscillator_tdm_core.v)。

GitHub 当前无法连接，本地分支暂时比远端领先 1 个提交；代码已经安全保存在本地，但尚未确认推送成功。

> 响度过于大了，先把响度调小到原来的100分之一吧

<details><summary>4 previous messages</summary>

> 我会直接把诊断方波的幅值缩放到约 1%：从 `±32767` 改为 `±328`（整数最接近 32767/100）。这样不动 ADSR、动态复音归一化和后级增益，之后恢复其他波形时不会留下全局增益副作用。
>
> <details><summary>Edited 2 files, ran a command</summary>
>
> - Wrote `./docs/square_wave_diagnostic.md` (+6 -2)
> - Wrote `./src/square_lut.v` (+4 -4)
> - Ran `git diff --check; git diff -- src/square_lut.v docs/square_wave_diagnostic.md; $env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root = r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> os.add_dll_directory(root + r'\pyslang.libs')
> os.add_dll_directory(root + r'\nanobind_backend.libs')
> import nanobind_backend
> spec = importlib.util.spec_from_file_location('pyslang.pyslang', root + r'\pyslang\pyslang.pyd')
> slang = importlib.util.module_from_spec(spec)
> sys.modules['pyslang.pyslang'] = slang
> spec.loader.exec_module(slang)
> files = ['src/freq_lut.v', 'src/square_lut.v', 'src/oscillator_tdm_core.v', 'src/oscillator_tdm_bank.v', 'sim/tb_oscillator_tdm_bank.v']
> options = slang.ast.CompilationOptions()
> base = slang.TimeScaleValue(slang.TimeUnit.Nanoseconds, slang.TimeScaleMagnitude.One)
> precision = slang.TimeScaleValue(slang.TimeUnit.Picoseconds, slang.TimeScaleMagnitude.One)
> options.defaultTimeScale = slang.TimeScale(base, precision)
> bag = slang.Bag()
> bag.compilationOptions = options
> tree = slang.syntax.SyntaxTree.fromFiles(files)
> compilation = slang.ast.Compilation(bag)
> compilation.addSyntaxTree(tree)
> diagnostics = list(compilation.getAllDiagnostics())
> errors = [d for d in diagnostics if d.isError()]
> print(f'TDM: {len(errors)} errors, {len(diagnostics) - len(errors)} warnings')
> raise SystemExit(1 if errors else 0)
> '@; python -c $verify`
>
> </details>
>
> 缩放后的振荡器展开检查通过，0 个错误。由于这是一个明确可烧录的听感测试点，我会单独提交；随后再尝试把前一个方波提交和本次音量修正一起推到 GitHub。
>
> <details><summary>Ran 3 commands</summary>
>
> - Ran `git add src/square_lut.v docs/square_wave_diagnostic.md; git commit -m "test: reduce square wave level to one percent"; git push origin main`
> - Ran `git status -sb; git log -2 --oneline`
> - Ran `git diff -- synth1_9_18.gprj`
>
> </details>
</details>

已将方波幅值从 `±32767` 调整为 `±328`，约为原来的 **1/100（-40 dB）**。

- RTL 检查：0 错误
- 本地提交：`2912e89`
- 需要重新综合并烧录
- GitHub 连接仍被重置，目前两个本地提交尚未推送

修改位置：[square_lut.v](./src/square_lut.v:12)

> 太夸张了这个板载放大电路，现在这个响度接耳机都响的完全不能戴在耳朵上听

<details><summary>2 previous messages</summary>

> 先不要再把耳机戴上测试，也不要把耳机直接接在板载功放的扬声器输出端。当前已经衰减约 40 dB 仍然过响，说明这一路很可能是给扬声器/线路后级设计的，不是受控的耳机输出；如果是桥接功放，耳机共地接法还可能造成输出端互相短接。我先查一下项目里是否记录了具体音频输出和功放型号，再给你合适的安全衰减方案。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `rg -n -i "amplifier|功放|headphone|耳机|speaker|扬声器|PT8211|audio out|line out|NS[0-9]|PAM[0-9]|TPA[0-9]" . -g "!impl/**" -g "!sim/work*/**" -g "!.git/**"`
> - Ran `Get-Content src\fir_decimator_8x_wrapper.v; rg -n "sample_out|fir_|dout|data_out|\[[0-9]+:[0-9]+\]|GAIN|shift|>>>" src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\top.v.v | Select-Object -First 180`
>
> </details>
</details>

这已经不是普通的音量偏大了：**不要再把耳机直接接到板载功放输出并戴耳试听**。如果功放是 BTL/桥接输出，共地耳机还可能短接左右声道或功放端。

当前数字幅值已经只有满量程约 1%（?40 dB）。继续靠数字衰减会严重浪费 16 位 DAC 的动态范围，噪声和量化失真会越来越明显。长期正确方案是：

- PT8211 线路输出后接带音量控制的耳放；或
- 在进入耳放前增加电阻分压/电位器；
- 不要直接从扬声器功放输出驱动普通共地耳机。

临时听方波可以先降到 `±4`，相比现在再降低约 82 倍，总计约 **?78 dBFS**；但首次仍应把耳机放在桌上试听，不能保证硬件端的安全响度。需要我现在改成 `±4` 吗？

> 你先检查一下板子的放大电路看看情况file:///C:/Users/teenagekiller/Downloads/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf

<details><summary>7 previous messages</summary>

> 我会使用 PDF 检查流程读取这份原理图，定位 PT8211、功放芯片、音频插座及其接法，重点确认输出是否为 BTL、耳机是否共地，以及实际增益和衰减网络。先只做只读检查，不改代码。
>
> <details><summary>Ran 3 commands</summary>
>
> <details><summary>Explored a file</summary>
>
> - Read `C:/Users/teenagekiller/.codex/plugins/cache/openai-primary-runtime/pdf/26.921.10847/skills/pdf/SKILL.md`
>
> </details>
>
> - Ran `$pdfPath='C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'; Get-Item -LiteralPath $pdfPath | Select-Object FullName,Length,LastWriteTime; $pdfInfo=Get-Command pdfinfo -ErrorAction SilentlyContinue; $pdfText=Get-Command pdftotext -ErrorAction SilentlyContinue; $pdfPpm=Get-Command pdftoppm -ErrorAction SilentlyContinue; "pdfinfo=$($pdfInfo.Source)"; "pdftotext=$($pdfText.Source)"; "pdftoppm=$($pdfPpm.Source)"; if ($pdfInfo) { & $pdfInfo.Source $pdfPath }`
>
> - Ran `python -c "import importlib.util; print('pypdf',bool(importlib.util.find_spec('pypdf'))); print('pdfplumber',bool(importlib.util.find_spec('pdfplumber'))); print('fitz',bool(importlib.util.find_spec('fitz'))); print('pymupdf',bool(importlib.util.find_spec('pymupdf')))"`
>
> - Ran `$names='mutool','qpdf','gswin64c','magick'; foreach($n in $names){$c=Get-Command $n -ErrorAction SilentlyContinue;if($c){"$n=$($c.Source)"}}; python -m pip install --user pypdf pymupdf`
>
> </details>
>
> PDF 工具已就绪。我会先用文字层筛出音频相关页，再把对应整页渲染出来逐项核对网络连接；原理图判断不能只依赖文字提取，因为跨页网络名和左右声道走线很容易被漏读。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `$script=@'
> import fitz,re
> p=r'C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'
> doc=fitz.open(p)
> print('pages',doc.page_count)
> terms=['PT8211','AUDIO','Audio','audio','SPK','HP','PHONE','EAR','AMP','NS','PAM','TPA','DAC','LINE','LINEOUT','LOUT','ROUT']
> for i,page in enumerate(doc):
>     text=page.get_text('text')
>     hits=[t for t in terms if t.lower() in text.lower()]
>     if hits:
>         print(f'--- PAGE {i+1} hits={hits} ---')
>         lines=[ln.strip() for ln in text.splitlines() if ln.strip()]
>         for j,ln in enumerate(lines):
>             if any(t.lower() in ln.lower() for t in terms):
>                 print(' | '.join(lines[max(0,j-2):min(len(lines),j+3)]))
> '@; python -c $script`
> - Ran `New-Item -ItemType Directory -Force -Path 'tmp\pdfs' | Out-Null; $script=@'
> import pymupdf
> p=r'C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'
> doc=pymupdf.open(p)
> page=doc[9]
> pix=page.get_pixmap(matrix=pymupdf.Matrix(3,3), alpha=False)
> pix.save(r'tmp\pdfs\audio_page_10.png')
> print(page.rect, pix.width, pix.height)
> '@; python -c $script; Get-Item tmp\pdfs\audio_page_10.png | Select-Object FullName,Length`
>
> </details>
>
> Viewed an image
>
> 已定位到第 10 页：耳机插座确实由 `NS4263` 功放驱动，不是直接接 PT8211。插入耳机后，插座检测脚会让 `HP-IN=1`，芯片切到 headphone enable；左右耳机信号经过 100 ?F 隔直电容输出，因此它不是把 BTL 两端直接送进共地耳机，之前对“可能短接 BTL”的担忧在这块板的 3.5 mm 插座上不成立。接下来我核对 NS4263 的耳机模式增益和输入电阻网络，解释为什么 1% 数字幅度仍然这么响。
>
> <details><summary>Searched the web</summary>
>
> Searched the web for `NS4263 datasheet pdf headphone gain ...`
>
> Searched the web for `NS4263 耳机模式 增益 20.5K 输入电阻 ...`
>
> </details>
</details>

检查结果：板载 3.5 mm 插座确实是正规的耳机输出，但功放增益非常高且没有模拟音量控制，所以现在的响度是合理的，不代表数字缩放失效。

根据原理图第 10 页，链路为：

`PT8211 → LMV321 单位增益低通 → NS4263 → 100 ?F 隔直 → 3.5 mm 耳机插座`

关键点：

- NS4263 是 3 W 双声道扬声器功放，同时具有耳机模式。
- 插入耳机后，插座检测让 `HP-IN=1`，NS4263 自动切换为 AB 类单端耳机输出。
- 耳机左右声道通过 `C135/C136 = 100 ?F` 隔直，地线接 `GNDA`，因此板载耳机口可以接普通共地耳机，不存在直接短接 BTL 输出的问题。
- 扬声器接口 J27/J28 才使用桥接输出。
- 板上没有电位器或模拟衰减电路。

真正夸张的是固定增益。NS4263 耳机模式增益公式为：

\[
A_v=\frac{240k}{2R_{IN}}
\]

板上 `R135/R136 = 20.5 kΩ`，所以：

\[
A_v=\frac{240k}{2\times20.5k}=5.85
\]

也就是约 **+15.35 dB**。NS4263 数据手册也确认，插入耳机后会进入单端耳机模式，并由外部输入电阻设置增益。[NS4263 数据手册](https://www.chipsourcetek.com/Uploads/file/NS4263.pdf)

因此当前方波虽然是：

\[
328/32767 \approx 1\%=-40\text{ dBFS}
\]

经过耳机功放后相当于：

\[
-40+15.35\approx-24.65\text{ dB}
\]

即耳机端仍有约 **5.85% 的 DAC 满幅电压**。对高灵敏度耳塞，这完全可能达到难以佩戴的响度。方波的 RMS 也比同峰值正弦波高约 3 dB，并且高频谐波会让主观听感更刺耳。

所以结论是：

1. 板载耳机电路接法没问题。
2. NS4263 的耳机增益确实很大。
3. 当前 `1/100` 的数字幅度对这块板来说仍远远不够低。
4. 最终设计应增加独立的高精度主音量控制；仅缩小波表幅值会浪费内部计算精度。
5. 临时测试可从 `±4` 开始，相当于约 `?78 dBFS`，但首次仍应把耳机放在桌上试听。

原理图来源：:codex-file-citation{path="C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf" purpose="source"}

- 降至安全测试音量
- 增加数字主音量
- 设计模拟衰减

> 你先检查一下板子的放大电路看看情况file:///C:/Users/teenagekiller/Downloads/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf

<details><summary>3 previous messages</summary>

> 我会重新按原理图逐段核对一次，重点看 PT8211 后的滤波、NS4263 的输入增益、耳机检测和输出接法，并把“耳机模式”和“扬声器模式”分开说明。使用 PDF 检查流程，只读分析，不改项目。
>
> <details><summary>Ran a command</summary>
>
> <details><summary>Explored a file</summary>
>
> - Read `C:/Users/teenagekiller/.codex/plugins/cache/openai-primary-runtime/pdf/26.921.10847/skills/pdf/SKILL.md`
>
> </details>
>
> - Ran `$pdfPath='C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'; Get-Item -LiteralPath $pdfPath | Select-Object FullName,Length,LastWriteTime; if (-not (Test-Path -LiteralPath 'D:\GOWINproject\synth1_9_18\tmp\pdfs\audio_page_10.png')) { New-Item -ItemType Directory -Force -Path 'D:\GOWINproject\synth1_9_18\tmp\pdfs' | Out-Null; $script=@'
> import pymupdf
> p=r'C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'
> doc=pymupdf.open(p)
> pix=doc[9].get_pixmap(matrix=pymupdf.Matrix(3,3), alpha=False)
> pix.save(r'D:\GOWINproject\synth1_9_18\tmp\pdfs\audio_page_10.png')
> '@; python -c $script }; Get-Item -LiteralPath 'D:\GOWINproject\synth1_9_18\tmp\pdfs\audio_page_10.png' | Select-Object FullName,Length`
>
> </details>
>
> Viewed an image
</details>

检查完成。板载耳机输出的接法是合理的，但它的固定增益确实很高，而且没有模拟音量旋钮。

音频链路是：

`PT8211 → LMV321 低通滤波 → NS4263 功放 → 3.5 mm 耳机口`

具体情况：

- PT8211 使用 3.3 V 供电。
- 两级 LMV321 是单位增益 Sallen-Key 低通滤波器，主要滤除 DAC 高频成分，不会明显放大信号。
- NS4263 使用约 5 V 的 `VBUS_PA` 供电。
- `R135/R136 = 20.5 kΩ` 决定 NS4263 的输入增益。
- 耳机模式电压增益约为：

\[
A_v=\frac{240k}{2\times20.5k}=5.85
\]

也就是约 **+15.35 dB**。

- 未插耳机时，J27/J28 使用 BTL 桥接方式驱动扬声器。
- 插入耳机后，检测触点令 `HP-IN=1`，NS4263 自动切换成单端 AB 类耳机模式。
- 左右耳机输出分别经过 `C135/C136 = 100 ?F` 隔直，再接到 CTIA 插座。
- 耳机地接 `GNDA`，所以板载 3.5 mm 插座可以正常使用普通共地耳机，并不会短接 BTL 输出。

现在方波幅度虽然只有 `±328`，即约 `-40 dBFS`，但经过功放后等效为：

\[
-40+15.35=-24.65\text{ dB}
\]

也就是耳机端仍达到 PT8211 满幅电压的约 **5.85%**。对于高灵敏度耳塞，这完全可能非常响。最初满幅方波还会让 NS4263 严重削波，确实有听力风险。

另外，功放输入的 `100 nF + 20.5 kΩ` 构成约 **78 Hz** 高通，因此低频会有一定衰减；这与音量过大无关。

结论：电路没有接错，问题是板载设计使用了固定的高功放增益，却没有提供模拟音量控制。因此项目需要把数字主音量当作正式功能，而不是继续通过缩小波表幅值解决。短期测试建议从 `±4` 开始，长期则在 FIR 后、PT8211 前增加高精度主音量乘法器。

原理图依据：:codex-file-citation{path="C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf" purpose="source"}

- 降到安全测试响度
- 实现数字主音量
- 设计模拟衰减方案

> 你先检查一下板子的放大电路看看情况file:///C:/Users/teenagekiller/Downloads/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf

<details><summary>2 previous messages</summary>

> 我已经定位并核对了原理图第 10 页的完整音频链路。这次我直接给出电路结论和关键数值，不改代码。使用 PDF 检查流程复核来源。
>
> <details><summary>Ran a command</summary>
>
> - Ran `Get-Content -Raw 'C:\Users\teenagekiller\.codex\plugins\cache\openai-primary-runtime\pdf\26.921.10847\skills\pdf\SKILL.md' | Out-Null; $pdfPath='C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'; Get-Item -LiteralPath $pdfPath | Select-Object FullName,Length,LastWriteTime; python -c "import pymupdf; d=pymupdf.open(r'C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf'); p=d[9]; t=p.get_text(); keys=['PT8211-S','LMV321','NS4263','20.5K/1%','100uF/10V','HEADPHONE JACK 3.5MM CTIA']; print('page_count=',d.page_count); print({k:(k in t) for k in keys})"`
>
> </details>
</details>

已经检查了原理图第 10 页，结论很明确：**板载耳机输出接法正常，但固定增益非常大，而且没有音量控制。**

音频路径：

`PT8211 → LMV321 单位增益低通 → 100 nF 耦合 → NS4263 → 100 ?F 隔直 → 3.5 mm 耳机口`

关键参数：

- NS4263 输入电阻 `R135/R136 = 20.5 kΩ`
- 耳机模式增益：

\[
A_v=\frac{240k}{2\times20.5k}=5.85
\]

约为 **+15.35 dB**。

- 插入耳机后，`HP-IN` 自动变高，NS4263 切换到单端 AB 耳机模式。
- 耳机左右声道通过 `C135/C136 = 100 ?F` 隔直，共地连接是正确的。
- J27/J28 才是 BTL 扬声器输出；板载 3.5 mm 口不会短接 BTL。
- 电路中没有模拟音量电位器。

所以当前 `±328` 虽然是 `?40 dBFS`，经过功放后相当于约 `?24.65 dB`，对高灵敏度耳塞仍然可能非常响。原来的满幅方波则一定会让功放严重削波。

建议：

- 临时测试先降到 `±4`，约 `?78 dBFS`。
- 正式方案是在 FIR 后、PT8211 前增加高精度数字主音量。
- 如果长期使用耳机，最好再增加模拟衰减或改大 `R135/R136`。

原理图依据：:codex-file-citation{path="C:\Users\teenagekiller\Downloads\Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf" purpose="source"}

- 方波降至 ±4
- 增加主音量模块
- 计算模拟衰减

> 算了，先不管了，让音频幅度正常吧，先测试其他功能

<details><summary>5 previous messages</summary>

> 明白。我会只撤销临时的 1% 幅度限制，把方波恢复为标准满幅 `±32767`；波形仍保持方波，ADSR、复音归一化和其他链路不动。烧录后如果还接耳机，请不要佩戴试听，优先用示波器、线路输入或远离耳朵的扬声器测试。
>
> <details><summary>Edited 2 files, ran a command</summary>
>
> - Wrote `./docs/square_wave_diagnostic.md` (+2 -6)
> - Wrote `./src/square_lut.v` (+4 -4)
> - Ran `git diff --check; git diff -- src/square_lut.v docs/square_wave_diagnostic.md; git status --short; $env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root = r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> os.add_dll_directory(root + r'\pyslang.libs')
> os.add_dll_directory(root + r'\nanobind_backend.libs')
> import nanobind_backend
> spec = importlib.util.spec_from_file_location('pyslang.pyslang', root + r'\pyslang\pyslang.pyd')
> slang = importlib.util.module_from_spec(spec)
> sys.modules['pyslang.pyslang'] = slang
> spec.loader.exec_module(slang)
> files = ['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v']
> options = slang.ast.CompilationOptions()
> base = slang.TimeScaleValue(slang.TimeUnit.Nanoseconds, slang.TimeScaleMagnitude.One)
> precision = slang.TimeScaleValue(slang.TimeUnit.Picoseconds, slang.TimeScaleMagnitude.One)
> options.defaultTimeScale = slang.TimeScale(base, precision)
> bag = slang.Bag(); bag.compilationOptions = options
> tree = slang.syntax.SyntaxTree.fromFiles(files)
> compilation = slang.ast.Compilation(bag); compilation.addSyntaxTree(tree)
> diagnostics = list(compilation.getAllDiagnostics())
> errors = [d for d in diagnostics if d.isError()]
> print(f'TDM: {len(errors)} errors, {len(diagnostics)-len(errors)} warnings')
> raise SystemExit(1 if errors else 0)
> '@; python -c $verify`
>
> </details>
>
> 满幅方波已恢复，TDM 振荡器展开检查为 0 错误。工程文件里另有一处 Gowin 自动调整的文件顺序，我会保留且不纳入这次提交，只提交幅度恢复本身。
>
> 本地提交已完成；GitHub 推送仍在等待网络响应，我会再确认一次结果。代码和提交已经安全保存在本地，不影响你现在重新综合测试。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `git add src/square_lut.v docs/square_wave_diagnostic.md; git commit -m "test: restore full-scale square wave level"; git push origin main`
> - Ran `git status -sb; git log -3 --oneline`
>
> </details>
</details>

已恢复正常满幅：

- 方波幅值：`±32767`
- 仍保持方波，其他音频链路未改
- RTL 展开检查：0 错误
- 本地提交：`e0e33a8`
- 可重新综合、生成 bitstream 并烧录

GitHub 网络仍无响应，目前本地领先远端 3 个提交。Gowin 自动调整的 `synth1_9_18.gprj` 文件顺序未纳入提交。

注意：满幅方波接板载耳机功放会非常响，请勿佩戴耳机试听。

> 考虑加入unison，怎么实现比较好

<details><summary>2 previous messages</summary>

> 我先结合现在的 32 声部 TDM 架构看一下声部分配、相位状态和混音位置，再给出不会把 ADSR、复音归一化搞乱的 Unison 方案。先做设计评估，不改 RTL。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `rg -n "module |SLOTS_PER_ENGINE|phase_state|current_phase_step|voice_update|active_voice_count|reciprocal_gain|note_event|free|voice" src/oscillator_tdm_core.v src/oscillator_tdm_bank.v src/midi_voice_allocator.v src/top.v.v | Select-Object -First 280`
> - Ran `Get-Content src\top.v.v | Select-Object -Skip 120 -First 60; Get-Content src\pt8211_tx.v -TotalCount 90; Get-Content src\midi_voice_allocator.v -TotalCount 180`
>
> </details>
</details>

最适合当前架构的是：**先做固定 3 振荡器 Unison，让一个 MIDI 音符占用 3 个连续 TDM 槽位**。这样不增加每个采样周期的运算次数，只会把最大复音数从 32 降到 10，风险最低。

| Unison 数 | 每个音符占用槽位 | 最大复音数 |
|---:|---:|---:|
| 1 | 1 | 32 |
| 2 | 2 | 16 |
| 3 | 3 | 10，剩余 2 槽 |
| 4 | 4 | 8 |

推荐第一版参数：

- 三个振荡器：`-6 cents / 0 / +6 cents`
- 单声道混合，暂不做声像扩展
- 三个振荡器同时 Note On、Note Off
- 暂时保持同相位起振
- 组内按 `1/3` 衰减，优先保证不削波
- 继续使用现有每槽 ADSR，但三个槽同步更新

实现结构建议：

1. 声部分配器改为“逻辑声部组”

   一个 MIDI 音符分配一组连续槽位，例如：

   - 逻辑声部 0 → 槽位 0、1、2
   - 逻辑声部 1 → 槽位 3、4、5
   - …
   - 逻辑声部 9 → 槽位 27、28、29

   Note Off、Release 完成和偷音都必须以整组为单位，不能只释放其中一个振荡器。

2. 增加 Unison 更新序列器

   当前分配器一次只能发出一个 `voice_update`。收到 Note On 后，用连续三个系统时钟依次更新三个槽位即可。MIDI 事件速度远低于 50 MHz，这点开销可以忽略。

3. 为每个槽位保存 `unison_lane`

   建议用两位：

   - `0`：中心
   - `1`：负失谐
   - `2`：正失谐

4. 使用失谐步进 LUT

   不要在运行时计算 `2^(cent/1200)`。增加一个小型 `detune_delta_lut`：

   ```text
   base_step = freq_lut(note)
   lane 0: phase_step = base_step
   lane 1: phase_step = base_step - detune_delta
   lane 2: phase_step = base_step + detune_delta
   ```

   LUT 按 MIDI 音高提前生成 ±6 cents 对应的相位增量差，资源很小，也不会增加乘法器关键路径。

5. 保持现有 32 次 TDM 调度

   不建议在每个现有槽位内部再计算 3 个子振荡器。当前 50 MHz 时钟与 768 kHz 内部采样率每次只有约 65 个时钟，32 槽可以容纳，96 次振荡器计算则无法由当前单引擎按时完成。

6. 归一化先按物理振荡器数量计算

   三个 Unison 槽都计入 `active_voice_count`，现有 `/N` 归一化可以保证最坏情况下不削波。后续如果觉得 Unison 变薄，可以再改成单独的 Unison 增益，例如 3 个振荡器乘 `1/2`，并预留更多混音位宽。

需要特别注意：Unison 本身就是通过相近频率产生低频拍频。±6 cents 在 A4 附近会出现约 1.5 Hz 的起伏，这属于预期效果。你之前不喜欢的“规律低频噪声”可能会再次出现，因此建议提供至少三档：

- Tight：±2 cents
- Normal：±4 cents
- Wide：±7 cents

另外，当前硬方波含有大量高次谐波和混叠，不适合判断 Unison 音色。实现前建议先恢复三角波，或者以后使用带限锯齿波。

第一版我建议最终定为：**10 复音 × 3 Unison、±4 cents、组内 `/3`、单声道、同步 ADSR**。等基本行为验证稳定，再加入随机起始相位、可调宽度和立体声展开。这个改动属于声部分配与音频数据路径重构，正式实现前需要先把当前三个本地提交成功推送到 GitHub。

> 考虑加入unison，怎么实现比较好

<details><summary>16 previous messages</summary>

> 结合当前架构，最合理的方案是把“声部”和“振荡器”分成两层：
>
> - 1 个逻辑声部：保存 MIDI 音符、Gate、ADSR、偷音状态。
> - 每个逻辑声部包含 3 个振荡器通道：各自保存相位和失谐量。
> - 32 个现有 TDM 槽位作为物理振荡器使用。
>
> 推荐第一版：
>
> ```text
> 10 个逻辑声部 × 3 个振荡器 = 30 个槽位
> 每组：-4 cents / 0 / +4 cents
> 剩余 2 个槽位暂不使用
> ```
>
> 这样仍然只调度最多 30 个振荡器，能放进当前每个 768 kHz 采样周期约 65 个系统时钟的预算中。
>
> 关键实现方式：
>
> 1. 每组共享一个 ADSR
>
>    不要让三个 Unison 振荡器各自决定包络状态。逻辑声部只保存一份 ADSR，三个振荡器读取同一个包络幅值，可以避免细微不同步和 Release 状态难以管理。
>
> 2. 每个振荡器只独立保存相位
>
>    ```text
>    oscillator_phase[voice][0]
>    oscillator_phase[voice][1]
>    oscillator_phase[voice][2]
>    ```
>
> 3. 使用失谐增量 LUT
>
>    ```text
>    base_step  = freq_lut(note)
>    detune_step = detune_delta_lut(note)
>
>    lane 0 = base_step - detune_step
>    lane 1 = base_step
>    lane 2 = base_step + detune_step
>    ```
>
>    不需要实时计算指数或除法。
>
> 4. 整组分配、释放和偷音
>
>    Note On 分配一个逻辑声部，而不是分别寻找三个空闲槽。Note Off 同时让整组进入 Release。偷音也必须替换整个组，否则容易出现残留音。
>
> 5. 两级归一化
>
>    先对组内三个振荡器除以 3，再按活动逻辑声部数量归一化：
>
>    ```text
>    三个振荡器求和
>        ↓
>    × 1/3
>        ↓
>    乘共享 ADSR
>        ↓
>    所有逻辑声部求和
>        ↓
>    × 1/活动逻辑声部数
>    ```
>
>    这样打开或关闭 Unison 不会破坏现有复音响度逻辑，也能保证同相起振时不削波。
>
> 6. 第一版保持单声道
>
>    当前 PT8211 模块把同一个样本复制到左右声道。立体声 Unison 需要双路混音、双路 FIR 和 PT8211 左右独立输入，改动明显更大，建议之后再做。
>
> 需要注意：Unison 的本质就是可控拍频。±4 cents 在 A4 附近会产生约 1 Hz 左右的幅度起伏。若不喜欢明显“抽动”，可以从 ±2 cents 开始。
>
> 建议分两步实施：
>
> - 第一阶段：固定 3-Unison、±4 cents、共享 ADSR、单声道、安全 `/3`。
> - 第二阶段：增加 1/2/3/4 档数量、Detune 参数、随机起始相位和立体声展开。
>
> 这会涉及声部分配接口和音频数据路径，属于大改动。正式开始前应先解决 GitHub 连接，把当前本地提交推送备份。
>
> 再例化几个震荡器吧，刚好测试实际工况下的调度器功能
>
> 可以。我会按“固定 3-Unison”把每个 MIDI 音符分配到 3 个 TDM 逻辑振荡器槽位，用它真实压测调度器，而不是复制三个完整硬件核心。先按项目规则把当前状态提交并推送；随后实现整组 Note On/Off、固定失谐和组内安全归一化，并补充调度验证。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `git status -sb; git diff -- synth1_9_18.gprj; git log -5 --oneline --decorate`
> - Ran `git add synth1_9_18.gprj; git commit -m "chore: sync Gowin project file order"; git push origin main`
>
> </details>
>
> 当前状态已成功备份到 GitHub（提交 `4b37f97`）。实现上我采用 10 个逻辑声部、每声部 3 个连续振荡器槽位；这样会让现有 32 槽调度器在多音时接近真实满载，同时仍保留两个空槽作为边界余量。第一版使用 `?4/0/+4 cents`，并保持现有安全归一化。
>
> <details><summary>Created a file, edited 5 files, deleted a file, ran 2 commands</summary>
>
> - Ran `Get-Content src\freq_lut.v -TotalCount 180; Get-Content sim\tb_oscillator_tdm_bank.v; Get-Content sim\tb_top_midi_input.v`
> - Deleted `./src/midi_voice_allocator.v` (+0 -142)
> - Wrote `./src/midi_voice_allocator.v` (+194 -0)
> - Wrote `./src/oscillator_tdm_core.v` (+23 -1)
> - Ran `Get-Content src\top.v.v -TotalCount 130; Get-Content src\oscillator_tdm_bank.v -TotalCount 115`
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+4 -0)
> - Wrote `./src/oscillator_tdm_bank.v` (+2 -0)
> - Wrote `./src/top.v.v` (+6 -1)
> - Wrote `./sim/tb_top_midi_input.v` (+46 -26)
>
> </details>
>
> 三路 Unison 的整组分配与更新通路已经接好：每个 Note On/Off 会连续发出 3 个槽位更新，调度槽使用 `?4/0/+4 cents`。我现在先做静态展开检查，优先找接口遗漏、参数宽度和综合不友好的写法，再补满载调度测试。
>
> <details><summary>Created a file, edited 4 files, ran 8 commands</summary>
>
> - Ran `rg -n "voice_update_unison_lane|midi_voice_allocator|oscillator_tdm_bank" src sim -g "*.v" -g "*.do"; git diff --check; $env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root = r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'
> os.add_dll_directory(root + r'\pyslang.libs')
> os.add_dll_directory(root + r'\nanobind_backend.libs')
> import nanobind_backend
> spec = importlib.util.spec_from_file_location('pyslang.pyslang', root + r'\pyslang\pyslang.pyd')
> slang = importlib.util.module_from_spec(spec); sys.modules['pyslang.pyslang'] = slang; spec.loader.exec_module(slang)
> checks = {
> 'TDM':['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v'],
> 'TOP':['sim/fir_decimator_8x_ip_stub.v','src/reset_release_sync.v','src/uart_rx.v','src/midi_note_parser.v','src/midi_voice_allocator.v','src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','src/fir_decimator_8x_wrapper.v','src/pt8211_tx.v','src/top.v.v','sim/tb_top_midi_input.v']}
> options=slang.ast.CompilationOptions(); options.defaultTimeScale=slang.TimeScale(slang.TimeScaleValue(slang.TimeUnit.Nanoseconds,slang.TimeScaleMagnitude.One),slang.TimeScaleValue(slang.TimeUnit.Picoseconds,slang.TimeScaleMagnitude.One)); bag=slang.Bag(); bag.compilationOptions=options
> failed=False
> for name,files in checks.items():
>  tree=slang.syntax.SyntaxTree.fromFiles(files); c=slang.ast.Compilation(bag); c.addSyntaxTree(tree); ds=list(c.getAllDiagnostics()); es=[d for d in ds if d.isError()]; print(f'{name}: {len(es)} errors, {len(ds)-len(es)} warnings'); [print(' ',d.code) for d in es]; failed |= bool(es)
> raise SystemExit(1 if failed else 0)
> '@; python -c $verify`
> - Ran `$env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend
> s=importlib.util.spec_from_file_location('pyslang.pyslang',root+r'\pyslang\pyslang.pyd'); m=importlib.util.module_from_spec(s); sys.modules['pyslang.pyslang']=m; s.loader.exec_module(m)
> files=['sim/fir_decimator_8x_ip_stub.v','src/reset_release_sync.v','src/uart_rx.v','src/midi_note_parser.v','src/midi_voice_allocator.v','src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','src/fir_decimator_8x_wrapper.v','src/pt8211_tx.v','src/top.v.v','sim/tb_top_midi_input.v']
> o=m.ast.CompilationOptions(); o.defaultTimeScale=m.TimeScale(m.TimeScaleValue(m.TimeUnit.Nanoseconds,m.TimeScaleMagnitude.One),m.TimeScaleValue(m.TimeUnit.Picoseconds,m.TimeScaleMagnitude.One)); b=m.Bag(); b.compilationOptions=o
> t=m.syntax.SyntaxTree.fromFiles(files); c=m.ast.Compilation(b); c.addSyntaxTree(t)
> for d in c.getAllDiagnostics(): print(d.code, d.location)
> '@; python -c $verify`
> - Ran ``$text = Get-Content -Raw src\midi_voice_allocator.v; $offsets = 2228,4540,4596,4884,5961,6336,6682,7343; foreach($offset in $offsets){$prefix=$text.Substring(0,[Math]::Min($offset,$text.Length)); $line=($prefix -split "`n").Count; $start=[Math]::Max(0,$offset-50); $len=[Math]::Min(130,$text.Length-$start); "OFFSET=$offset LINE=$line"; $text.Substring($start,$len).Replace("`r",' ').Replace("`n",' ')}``
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+21 -4)
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+7 -2)
> - Ran `Get-Content docs\dynamic_voice_normalization.md -TotalCount 20; Get-Content README.md -TotalCount 18`
> - Wrote `./README.md` (+2 -2)
> - Wrote `./docs/unison_scheduler_test.md` (+43 -0)
> - Ran `Get-Content docs\dynamic_voice_normalization.md | Select-Object -Last 20`
> - Ran `$roots='C:\Gowin','C:\Gowin_V1.9.11.03','C:\intelFPGA','C:\questasim64_2021.2'; foreach($root in $roots){if(Test-Path $root){Get-ChildItem -LiteralPath $root -Filter vlog.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 2 -ExpandProperty FullName; Get-ChildItem -LiteralPath $root -Filter iverilog.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 2 -ExpandProperty FullName}}; git diff --check; git diff --stat; git status --short`
> - Ran `$base=[Convert]::ToUInt32('00258BF2',16); $delta=($base -shr 9)+($base -shr 12)+($base -shr 13); $ratio=[double]$delta/$base; $cents=1200*[Math]::Log(1+$ratio,2); "A4 base_step=$base delta=$delta detune_cents=$cents"; $clocksPerSample=50000000/768000; "clocks_per_768k_sample=$clocksPerSample scheduler_slots=32 spare_clocks=$($clocksPerSample-32)"`
> - Ran `Get-Content src\oscillator_tdm_bank.v | Select-Object -Skip 175 -First 85`
> - Wrote `./docs/unison_scheduler_test.md` (+3 -0)
> - Wrote `./src/oscillator_tdm_bank.v` (+6 -7)
>
> </details>
>
> 静态展开已经通过。为了让“实际工况”不只停留在手工听感，我再补一套专门的 3-Unison 满载测试：通过真实分配器启动 10 个 MIDI 音符（30 个振荡器槽），按 768 kHz 的真实间隔持续调度，并检查第 11 个音符的整组偷音、整组 Release 和 overrun。
>
> <details><summary>Created 2 files, ran 3 commands</summary>
>
> - Wrote `./sim/run_unison_scheduler_test.do` (+26 -0)
> - Wrote `./sim/tb_unison_scheduler_load.v` (+220 -0)
> - Ran `git diff --check; $env:PYTHONPATH='C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; $verify = @'
> import importlib.util, sys, os
> root=r'C:\Users\teenagekiller\AppData\Local\Temp\codex_pyslang_verify'; os.add_dll_directory(root+r'\pyslang.libs'); os.add_dll_directory(root+r'\nanobind_backend.libs'); import nanobind_backend
> s=importlib.util.spec_from_file_location('pyslang.pyslang',root+r'\pyslang\pyslang.pyd'); m=importlib.util.module_from_spec(s); sys.modules['pyslang.pyslang']=m; s.loader.exec_module(m)
> checks={'TDM':['src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_oscillator_tdm_bank.v'],'UNISON_LOAD':['src/freq_lut.v','src/square_lut.v','src/midi_voice_allocator.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','sim/tb_unison_scheduler_load.v'],'TOP':['sim/fir_decimator_8x_ip_stub.v','src/reset_release_sync.v','src/uart_rx.v','src/midi_note_parser.v','src/midi_voice_allocator.v','src/freq_lut.v','src/square_lut.v','src/oscillator_tdm_core.v','src/oscillator_tdm_bank.v','src/fir_decimator_8x_wrapper.v','src/pt8211_tx.v','src/top.v.v','sim/tb_top_midi_input.v']}
> o=m.ast.CompilationOptions(); o.defaultTimeScale=m.TimeScale(m.TimeScaleValue(m.TimeUnit.Nanoseconds,m.TimeScaleMagnitude.One),m.TimeScaleValue(m.TimeUnit.Picoseconds,m.TimeScaleMagnitude.One)); b=m.Bag(); b.compilationOptions=o
> failed=False
> for name,files in checks.items():
>  t=m.syntax.SyntaxTree.fromFiles(files); c=m.ast.Compilation(b); c.addSyntaxTree(t); ds=list(c.getAllDiagnostics()); es=[d for d in ds if d.isError()]; print(f'{name}: {len(es)} errors, {len(ds)-len(es)} warnings'); [print(' ',d.code,d.location) for d in es]; failed |= bool(es)
> raise SystemExit(1 if failed else 0)
> '@; python -c $verify`
> - Ran `winget search --query iverilog --accept-source-agreements`
> - Ran `winget search --query verilator --accept-source-agreements; winget search --query "Icarus Verilog" --accept-source-agreements`
>
> </details>
>
> 三套 RTL（底层 32 槽、Unison 满载、完整 MIDI 顶层）都已完成静态展开，0 错误。为真正跑完新增的时序行为测试，我会安装轻量的 Icarus Verilog 仿真器；这只用于仿真，不会运行 Gowin 综合或布局布线。
>
> <details><summary>Ran 6 commands</summary>
>
> - Ran `winget install --id Icarus.Verilog --exact --silent --accept-package-agreements --accept-source-agreements`
> - Ran `$iv=Get-Command iverilog -ErrorAction SilentlyContinue; if($iv){$iv.Source}else{Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Filter iverilog.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 5 -ExpandProperty FullName}`
> - Ran `Get-ChildItem 'C:\Users\teenagekiller\AppData\Local','C:\iverilog' -Filter iverilog.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10 -ExpandProperty FullName; Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*Icarus*'} | Select-Object DisplayName,InstallLocation`
> - Ran `$paths='C:\iverilog\bin\iverilog.exe','C:\Program Files\iverilog\bin\iverilog.exe','C:\Users\teenagekiller\iverilog\bin\iverilog.exe','C:\Users\teenagekiller\AppData\Local\Programs\iverilog\bin\iverilog.exe'; foreach($p in $paths){if(Test-Path -LiteralPath $p){$p}}; winget list --id Icarus.Verilog`
> - Ran `$iverilog='C:\iverilog\bin\iverilog.exe'; $vvp='C:\iverilog\bin\vvp.exe'; $outDir=Join-Path $env:TEMP 'synth1_unison_sim'; New-Item -ItemType Directory -Force -Path $outDir | Out-Null; & $iverilog -g2012 -s tb_oscillator_tdm_bank -o (Join-Path $outDir 'tdm.vvp') src/freq_lut.v src/square_lut.v src/oscillator_tdm_core.v src/oscillator_tdm_bank.v sim/tb_oscillator_tdm_bank.v; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; & $vvp (Join-Path $outDir 'tdm.vvp'); if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; & $iverilog -g2012 -s tb_unison_scheduler_load -o (Join-Path $outDir 'unison.vvp') src/freq_lut.v src/square_lut.v src/midi_voice_allocator.v src/oscillator_tdm_core.v src/oscillator_tdm_bank.v sim/tb_unison_scheduler_load.v; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; & $vvp (Join-Path $outDir 'unison.vvp')`
> - Ran `$iverilog='C:\iverilog\bin\iverilog.exe'; $vvp='C:\iverilog\bin\vvp.exe'; $outDir=Join-Path $env:TEMP 'synth1_unison_sim'; & $iverilog -g2012 -s tb_top_midi_input -o (Join-Path $outDir 'top_midi.vvp') sim/fir_decimator_8x_ip_stub.v src/reset_release_sync.v src/uart_rx.v src/midi_note_parser.v src/midi_voice_allocator.v src/freq_lut.v src/square_lut.v src/oscillator_tdm_core.v src/oscillator_tdm_bank.v src/fir_decimator_8x_wrapper.v src/pt8211_tx.v src/top.v.v sim/tb_top_midi_input.v; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; & $vvp (Join-Path $outDir 'top_midi.vvp')`
>
> </details>
>
> 三项行为仿真都已实际跑通：
>
> - 32 槽满载、真实 768 kHz 调度间隔：PASS
> - 30 振荡器的 3-Unison 分配、整组偷音、整组 Release：PASS
> - UART MIDI 到顶层三路槽位更新：PASS
>
> 没有运行 Gowin 综合或布局布线。现在做最后差异检查，然后提交并推送这个可回退检查点。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `git diff --check; git status --short; git diff --stat; git diff -- src/oscillator_tdm_core.v src/midi_voice_allocator.v src/oscillator_tdm_bank.v src/top.v.v | Select-Object -First 500`
> - Ran `git add README.md docs/unison_scheduler_test.md sim/run_unison_scheduler_test.do sim/tb_unison_scheduler_load.v sim/tb_oscillator_tdm_bank.v sim/tb_top_midi_input.v src/midi_voice_allocator.v src/oscillator_tdm_bank.v src/oscillator_tdm_core.v src/top.v.v; git commit -m "feat: add three-oscillator unison scheduling"; git push origin main`
>
> </details>
>
> 实现与本地提交已经完成；GitHub 在推送确认阶段再次重置连接。我会再重试并核对远端提交号，本地成果不会受影响。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `git push origin main`
> - Ran `git status -sb; git log -2 --oneline; git diff --check`
>
> </details>
</details>

已实现固定 3-Unison，并用它压测了实际调度链路。

当前配置：

- 每个 MIDI 音符占用 3 个振荡器槽
- 失谐：约 `?4.01 / 0 / +4.01 cents`
- 10 复音 × 3 振荡器 = 30 个活动槽
- 槽位 30、31 保留
- Note On、Note Off、Release、偷音均按整组处理
- 新声部加入时立即降低归一化增益，避免三个同相振荡器起音时削波
- Release 后的增益恢复仍保持平滑

验证结果全部通过：

- 32 槽、768 kHz 实际间隔调度：PASS
- 30 振荡器满载、整组偷音和 Release：PASS
- UART MIDI → 三路 Unison 更新：PASS
- RTL 静态展开：0 错误
- 未运行 Gowin 综合或布局布线

主要实现位于：

- [midi_voice_allocator.v](./src/midi_voice_allocator.v)
- [oscillator_tdm_core.v](./src/oscillator_tdm_core.v)
- [unison_scheduler_test.md](./docs/unison_scheduler_test.md)
- [tb_unison_scheduler_load.v](./sim/tb_unison_scheduler_load.v)

本地提交为 `c8c3a7a feat: add three-oscillator unison scheduling`。GitHub 推送两次均因连接重置失败，目前本地领先远端 1 个提交。

现在可以重新综合并烧录。当前仍是满幅硬方波，板载耳机输出会非常响，请用远离耳朵的扬声器或测量设备测试。

> 先讲解一下unison的原理

Unison 的核心很简单：**按下一个音符时，不只启动一个振荡器，而是同时启动多个频率非常接近的振荡器，再把它们混合起来。**

例如按下 A4（440 Hz），普通振荡器只有：

```text
440 Hz
```

3-Unison 可以是：

```text
振荡器 1：约 438.98 Hz  （-4 cents）
振荡器 2：440.00 Hz     （中心）
振荡器 3：约 441.02 Hz  （+4 cents）
```

## 为什么声音会变厚

三个频率很接近，但并不完全相同，所以它们的相位会逐渐错开：

```text
开始：       三个波形基本重合
一段时间后：相位逐渐分离
再过一段：   部分相长、部分相消
```

叠加后的音量会缓慢起伏，这就是拍频。两个频率的拍频大致为：

\[
f_\text{beat}=|f_1-f_2|
\]

例如 440 Hz 与约 441.02 Hz 混合，会产生约 1 Hz 的缓慢起伏。多个拍频同时存在时，声音就不再像单个稳定振荡器，而会显得更厚、更活、更有宽度。

这和合唱效果器有些相似，但 Unison 是直接在振荡器层产生多个声源，不是对最终音频增加延迟调制。

## cents 是什么

半音被划分为 100 cents，一个八度是 1200 cents。频率关系为：

\[
f_\text{detuned}=f\times2^{c/1200}
\]

其中 `c` 是失谐 cents。

常见听感大致是：

- `±1～2 cents`：很轻，主要消除声音的静态感
- `±3～5 cents`：比较自然的厚度
- `±7～12 cents`：明显拍频和合唱感
- 更大：开始容易被听成多个不同音高

当前实现使用约 `?4.01 / 0 / +4.01 cents`。

## Unison 和复音的区别

复音是同时演奏多个不同的 MIDI 音符：

```text
C4 + E4 + G4
```

Unison 是一个 MIDI 音符内部包含多个振荡器：

```text
C4：
  C4 - 4 cents
  C4
  C4 + 4 cents
```

因此当前 3-Unison 演奏 C、E、G 三和弦时，实际运行的是：

```text
3 个 MIDI 音符 × 每音符 3 个振荡器 = 9 个振荡器
```

## ADSR 怎么处理

通常一个 Unison 组共享一套逻辑 ADSR：

```text
一个 MIDI Gate
       ↓
一个 ADSR 包络
       ↓
控制三个振荡器
```

这样三个振荡器会同时起音、同时进入 Sustain、同时 Release，不会出现某一个振荡器残留。

当前版本的三个物理槽仍各自保存 ADSR 状态，但它们在连续三个 50 MHz 时钟中收到相同命令，因此实际上同步工作。后续可以进一步改成真正共享一份包络状态。

## 为什么要降低混合幅度

如果三个振荡器同时处于同相位：

\[
x+x+x=3x
\]

不衰减就可能立即削波。因此安全做法是：

\[
y=\frac{x_1+x_2+x_3}{3}
\]

当前动态归一化会把三个物理振荡器都计入活动数量。新音符加入时，衰减立即生效；音符释放后，增益再缓慢恢复，避免响度跳变。

`/3` 保证峰值安全，但失谐后的平均响度可能稍微偏小。商业合成器有时使用约 `1/√3` 的增益，再配合额外余量、压缩器或软削波，让 Unison 听起来更响。我们的第一版优先保证不削波。

## 当前 FPGA 如何调度

现在 32 个 TDM 槽位按三个一组：

```text
逻辑声部 0：槽 0、1、2
逻辑声部 1：槽 3、4、5
逻辑声部 2：槽 6、7、8
...
逻辑声部 9：槽 27、28、29
保留槽位：30、31
```

每次内部采样时，调度器依次计算所有 32 个槽：

```text
slot 0 → slot 1 → ... → slot 31 → 输出混音结果
```

50 MHz 时钟下，一个 768 kHz 内部采样周期约有 65 个时钟，所以完成 32 个槽的计算后还有约 33 个时钟余量。

## 方波测试时的特殊现象

当前使用的是硬方波。方波包含大量高次谐波，三个轻微失谐的方波会让每一组谐波都产生拍频，所以听起来可能非常粗糙、刺耳，甚至像规律噪声。

判断 Unison 是否自然时，三角波或带限锯齿波更合适。方波更适合确认调度器和多振荡器确实在工作，不适合评价最终音色。

> 先讲解一下unison的原理

Unison（齐奏）的本质是：**按下一个音符，同时让多个振荡器演奏这个音，但给它们很小的音高、相位或声像差异，然后叠加。**

例如按下 A4：

```text
振荡器1：438.98 Hz  -4 cents
振荡器2：440.00 Hz   0 cents
振荡器3：441.02 Hz  +4 cents
```

它们听起来仍然都是 A4，但因为频率不完全相同，相位会不断发生变化。

## 为什么会变厚

两个相近频率叠加时，会交替出现：

```text
相位接近 → 相长，声音变大
相位相反 → 相消，声音变小
```

这种缓慢的音量变化叫“拍频”：

\[
f_\text{beat}=|f_1-f_2|
\]

例如 440 Hz 和 441 Hz 叠加，大约每秒产生一次强弱变化。三个或更多振荡器一起变化时，声音就会显得更厚、更活跃。

## Unison 不是复音

复音是同时演奏不同音符：

```text
C4 + E4 + G4
```

3-Unison 是一个音符内部运行三个振荡器：

```text
C4-4 cents + C4 + C4+4 cents
```

所以演奏一个三和弦时：

```text
3 个 MIDI 音符 × 3 个 Unison 振荡器
= 9 个实际振荡器
```

## 通常有哪些参数

- `Voices`：每个音符使用几个振荡器。
- `Detune`：振荡器之间相差多少 cents。
- `Phase`：起振相位相同、固定错开或随机。
- `Spread`：不同振荡器放在左右声道的不同位置。
- `Blend`：中心振荡器和失谐振荡器的音量比例。

Detune 越小，声音越稳定；Detune 越大，拍频越明显，最后可能听起来像多个音高。

## ADSR 如何处理

一个 MIDI 音符对应一个逻辑声部，通常共享一套 ADSR：

```text
一个 MIDI Gate
      ↓
一个 ADSR
      ↓
同时控制三个振荡器
```

因此三个振荡器同时起音、同时 Sustain、同时 Release。

## 为什么需要归一化

三个满幅振荡器直接相加，峰值可能达到原来的三倍：

\[
x_1+x_2+x_3=3x
\]

所以需要做组内衰减：

\[
y=\frac{x_1+x_2+x_3}{3}
\]

这样三个振荡器完全同相时也不会削波。

## 当前 FPGA 中的实现

当前采用固定 3-Unison：

```text
每个 MIDI 音符：
槽位0：-4 cents
槽位1： 0 cents
槽位2：+4 cents
```

32 个 TDM 槽被分成：

```text
10 个逻辑声部 × 3 个振荡器 = 30 个槽
剩余 2 个槽保留
```

调度器仍然每个采样周期依次处理 32 个槽，因此不需要增加三个完整硬件振荡器，只是让一个 MIDI 音符占用三个逻辑振荡器状态。

当前硬方波的高次谐波很多，Unison 拍频会格外明显，甚至听起来像规律噪声。之后换回三角波或带限锯齿波，更适合评价实际的 Unison 音色。

> 取消你的改动，按我的想法组织振荡器：不设置unison专用振荡器，将振荡器统一化，给予调度器音符和unison个数信息后由调度器把声音的参数分配给后续例化的多个实体振荡器分别时分复用计算后相加输出，先不要应用改动，我要确认你理解了我的意图

我理解了。你想要的不是“给 Unison 单独划出一组特殊振荡器”，而是建立一套统一、通用的振荡器资源池，Unison 只是调度器的一种分配策略。

这与我刚才实现的固定三槽分组方案不同。当前提交 `c8c3a7a` 中这些设计都不符合你的方向：

- 固定 `3-Unison`
- 固定连续槽位分组
- 振荡器核心内部存在 `unison_lane`
- 核心内部根据 lane 计算 `?4/0/+4 cents`
- 复音固定下降到 10

你的目标结构应当是：

```text
MIDI音符 + Unison个数 + 音色参数
                  │
                  ▼
             全局调度器
      将一个音符展开为N个普通振荡器任务
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
   实体振荡器0 实体振荡器1 实体振荡器2 ...
   时分复用槽位 时分复用槽位 时分复用槽位
        │         │         │
        └────部分和相加──────┘
                  │
                  ▼
              最终音频
```

这里需要明确区分三层概念。

1. 音符声部

代表一次 MIDI Note On，保存：

- MIDI 音高
- Gate
- ADSR
- Unison 数量
- Detune 宽度
- 波形等公共参数

2. 逻辑振荡器任务

调度器根据 Unison 数量动态展开。

例如：

```text
Note 60，Unison=1
→ 生成1个普通振荡器任务

Note 64，Unison=3
→ 生成3个普通振荡器任务：
   note=64，detune=-4 cents
   note=64，detune= 0 cents
   note=64，detune=+4 cents

Note 67，Unison=5
→ 生成5个普通振荡器任务
```

这些任务完全是同一种数据结构，不存在“主振荡器”和“Unison 专用振荡器”。

每个任务保存自己的：

- 相位
- 相位增量
- Detune
- 使能状态
- 所属音符声部 ID

它们可以共享所属音符声部的 ADSR。

3. 实体振荡器

这是 FPGA 中真正例化出来的计算模块。比如：

```text
4个实体振荡器
每个实体时分复用8个逻辑振荡器槽
总容量仍为32个逻辑振荡器
```

调度器可以把任务均匀分配：

```text
实体0：逻辑振荡器 0、4、8、12……
实体1：逻辑振荡器 1、5、9、13……
实体2：逻辑振荡器 2、6、10、14……
实体3：逻辑振荡器 3、7、11、15……
```

每个实体振荡器在一个内部采样周期内依次计算自己的槽位，最后产生一个部分和；所有实体的部分和再相加。

这样带来的结果是：

- Unison 数量可以动态变化。
- 没开启 Unison 时，全部资源可以用于普通复音。
- 开启 Unison 后，只是一个音符消耗更多通用逻辑振荡器容量。
- 不需要固定连续槽位。
- 不需要在振荡器核心内部识别 Unison lane。
- 振荡器只接收已经计算好的通用参数，例如 `phase_step`、波形和包络增益。
- 调度器负责资源分配、Detune 参数生成、整组释放和整组偷音。
- 实体振荡器数量与总逻辑振荡器数量彼此独立，可以调整为 `2×16`、`4×8`、`8×4` 等结构。

Note Off 时，调度器根据声部 ID 找到由该音符展开出的所有普通振荡器任务，让它们一起进入 Release。偷音也应当偷掉完整的音符声部，而不是随机抢走其中一个 Unison 成员。

我建议 ADSR 保持“一份音符声部 ADSR，由该声部展开出的所有振荡器共享”。这样 Unison 数量变化不会额外复制包络状态，也不会出现同组振荡器 Release 不同步。

所以我的理解可以概括为：

> Unison 不属于振荡器硬件本身，而属于调度器。振荡器实体全部统一；调度器把音符按 Unison 数量展开成若干通用振荡器任务，再分发给多个并行实体振荡器进行时分复用，最终相加。

这轮我没有修改任何文件。你确认这个理解正确后，我会先撤销 `c8c3a7a` 的固定 3-Unison 实现，再根据这个结构设计接口；在你确认具体结构前不会应用改动。

> 取消你的改动，按我的想法组织振荡器：不设置unison专用振荡器，将振荡器统一化，给予调度器音符和unison个数信息后由调度器把声音的参数分配给后续例化的多个实体振荡器分别时分复用计算后相加输出，先不要应用改动，我要确认你理解了我的意图

理解一致。这一轮不会改文件，也不会立即执行回退。

你想要的是“统一振荡器资源池 + 全局调度器”，而不是固定的 Unison 振荡器组：

```text
音符事件 + Unison数量 + 音色参数
                  │
                  ▼
       调度器展开普通振荡器任务
                  │
         动态分配到多个相同实体
          │       │       │
          ▼       ▼       ▼
       振荡器0  振荡器1  振荡器2 ...
       多槽TDM   多槽TDM   多槽TDM
          │       │       │
          └────部分和相加───┘
```

例如存在 4 个完全相同的实体振荡器，每个实体时分复用 8 个状态槽：

```text
Note 60，Unison=3：

普通任务A：Note60，Detune=-4
普通任务B：Note60，Detune= 0
普通任务C：Note60，Detune=+4

调度结果可以是：
任务A → 实体0、槽0
任务B → 实体1、槽0
任务C → 实体2、槽0
```

这些任务不必连续，也不必落在固定实体上。下一个 `Unison=1` 的音符可以分配到任意空闲位置。

每个实体振荡器只接受统一参数，例如：

```text
槽位号
phase_step
phase_reset
waveform
enable
envelope_gain或voice_id
```

实体振荡器不知道该任务是不是 Unison，也不存在 `unison_lane`。Detune 计算、成员关系、资源分配、整组释放和整组偷音都由调度器负责。

因此：

- Unison=1 时，32 个逻辑槽全部可以用于普通复音。
- Unison=3 时，一个音符动态消耗 3 个普通槽。
- 不固定为 10 复音，也不预留 Unison 专用资源。
- 实体数量和每个实体的 TDM 槽数可以独立配置，例如 `4×8`。
- 每个实体产生部分和，最终混音器把所有部分和相加。
- Note Off 根据 `voice_id/group_id` 找到该音符展开的全部任务，一起 Release。
- 偷音以完整 MIDI 声部为单位，不拆散 Unison 成员。

我之前的 `c8c3a7a` 固定三槽实现确实不符合这个方向，之后应完整撤销，包括：

- 固定 `UNISON_COUNT=3`
- 连续三槽分组
- `unison_lane`
- 振荡器核心内部的 Detune 计算
- 固定 10 复音限制

我建议一份 ADSR 属于 MIDI 声部，展开后的普通振荡器任务共享它；但这点需要你最后确认。另一个需要确认的是首版实体数量，我倾向于从 **4 个实体 × 每实体 8 个 TDM 槽**开始。除此之外，我对你的总体架构理解如上。

> 可以，按我的想法更改吧

<details><summary>13 previous messages</summary>

> 我会按确认后的架构执行。第一步先用可追溯的 revert 撤销固定三槽 Unison 提交，并推送这个干净基线；随后重构为“全局任务调度器 + 多个统一实体振荡器 + 每实体内部 TDM + 部分和汇总”。首版采用我们确认的 `4 个实体 × 每实体 8 个逻辑槽`，总容量仍为 32。
>
> <details><summary>Ran a command</summary>
>
> - Ran `git status -sb; git log -3 --oneline --decorate; git revert --no-edit c8c3a7a; git push origin main`
>
> </details>
>
> 固定三槽方案已经通过 revert 完整撤销，本地回到干净基线。GitHub 当前出现 DNS 解析失败；因为这是大改动，我先重试备份推送，确认远端收到回退检查点后再开始写新架构。
>
> <details><summary>Ran a command</summary>
>
> - Ran `git push origin main`
>
> </details>
>
> 回退检查点已成功推送到 GitHub（`160704e`），现在开始新架构。实现重点是：调度器输出已经算好的 `phase_step`，实体振荡器不再接收音符或 Unison lane；4 个完全相同的实体各自 TDM 8 个槽，调度器按实体轮转顺序分配普通振荡器任务。
>
> <details><summary>Created a file, edited 7 files, deleted a file, explored a file, ran 6 commands</summary>
>
> - Deleted `./src/midi_voice_allocator.v` (+0 -142)
> - Wrote `./src/oscillator_task_scheduler.v` (+366 -0)
>
> - Wrote `./src/oscillator_task_scheduler.v` (+11 -2)
>
> - Ran `Get-Content src\oscillator_tdm_core.v -TotalCount 135; Get-Content src\oscillator_tdm_core.v | Select-Object -Skip 275 -First 45`
>
> - Ran `rg -n "note_state|current_note|freq_lut|voice_update_note" src\oscillator_tdm_core.v -C 3`
>
> - Wrote `./src/oscillator_tdm_core.v` (+10 -17)
>
> - Wrote `./src/oscillator_tdm_bank.v` (+2 -4)
>
> - Ran `Get-Content src\top.v.v -TotalCount 130`
>
> - Wrote `./src/top.v.v` (+33 -27)
>
> - Ran `rg -n "midi_voice_allocator|voice_update_note|NOTE_WIDTH|note_state|ENGINE_COUNT|SLOTS_PER_ENGINE" src sim README.md docs synth1_9_18.gprj -g "!sim/work*/**"`
>
> - Wrote `./sim/run_top_midi_test.do` (+2 -2)
> - Wrote `./synth1_9_18.gprj` (+1 -1)
>
> - Ran `Get-Content sim\tb_oscillator_tdm_bank.v | Select-Object -First 185; Get-Content sim\tb_oscillator_tdm_bank.v | Select-Object -Skip 205 -First 95`
>
> - Ran `rg -n "update_voice_slot|voice_update_note|note_state|NOTE_WIDTH" sim\tb_oscillator_tdm_bank.v`
>
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+13 -12)
>
> <details><summary>Explored a file</summary>
>
> - Read `./sim/tb_top_midi_input.v`
>
> </details>
>
> </details>
>
> Context compaction
>
> Source: automatic
> Status: completed
>
> 我继续完成这次架构改造：先把顶层 MIDI 仿真和调度器满载测试补齐，再用 Icarus 做语法、展开与行为验证；通过后会提交并推送这个架构检查点。按项目规则，不运行 Gowin 综合或布局布线。
>
> <details><summary>Created a file, edited 2 files, deleted a file, ran 4 commands</summary>
>
> - Ran `git status --short; rg -n "voice_update_note|u_midi_voice_allocator|voice_update_valid|note_state|midi_voice_allocator" src sim README.md docs synth1_9_18.gprj`
> - Ran `Get-Content -Raw sim/tb_top_midi_input.v; Get-Content -Raw src/oscillator_task_scheduler.v; Get-Content -Raw src/top.v.v`
> - Ran `Get-Content -Raw src/oscillator_tdm_bank.v; Get-Content -Raw sim/tb_oscillator_tdm_bank.v; Get-Content -Raw sim/run_top_midi_test.do; Get-Content -Raw README.md`
> - Ran `$bases = 0x0016534C,0x001C20D3,0x00217345; foreach($b in $bases){$u=($b -shr 10)+($b -shr 13)+($b -shr 14); '{0:X8} unit={1:X8} low={2:X8} high={3:X8}' -f $b,$u,($b-2*$u),($b+2*$u)}`
> - Deleted `./sim/tb_top_midi_input.v` (+0 -199)
> - Wrote `./sim/run_top_midi_test.do` (+3 -3)
> - Wrote `./sim/tb_top_midi_input.v` (+226 -0)
> - Wrote `./src/oscillator_tdm_bank.v` (+4 -7)
>
> </details>
>
> 顶层测试已改成检查“一个音符展开为三个普通任务”，并验证三个任务被轮转分散到 4 个物理引擎；同时将任务数增加时的归一化衰减改为立即生效，避免同相叠加的瞬时削波，增益恢复仍保持平滑。现在开始第一次编译和仿真，先根据真实报错收敛调度状态机。
>
> <details><summary>Created 4 files, edited 7 files, deleted 2 files, ran 10 commands</summary>
>
> - Ran `& 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_midi_input -o sim\tb_top_midi_input.out sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\uart_rx.v src\midi_note_parser.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_midi_input.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_top_midi_input.out }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_tdm_bank -o sim\tb_oscillator_tdm_bank.out src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v sim\tb_oscillator_tdm_bank.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_oscillator_tdm_bank.out }`
> - Wrote `./sim/run_task_scheduler_test.do` (+24 -0)
> - Wrote `./sim/tb_oscillator_task_scheduler.v` (+204 -0)
> - Ran `& 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_task_scheduler -o sim\tb_oscillator_task_scheduler.out src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_oscillator_task_scheduler.out }`
> - Ran `Get-Content -Raw docs/tdm_scheduler_validation.md; Get-Content -Raw docs/adsr_envelope.md; Get-Content -Raw docs/dynamic_voice_normalization.md; git diff --stat; git diff --check`
> - Wrote `./README.md` (+3 -2)
> - Wrote `./docs/adsr_envelope.md` (+1 -1)
> - Deleted `./docs/dynamic_voice_normalization.md` (+0 -48)
> - Deleted `./docs/tdm_scheduler_validation.md` (+0 -132)
> - Wrote `./docs/dynamic_voice_normalization.md` (+38 -0)
> - Wrote `./docs/tdm_scheduler_validation.md` (+79 -0)
> - Ran `rg -n "midi_voice_allocator|voice_update_note|note_state|active_voice_count" README.md docs src sim synth1_9_18.gprj; git status --short; git diff --check; & 'C:\iverilog\bin\iverilog.exe' -g2012 -Wall -s tb_oscillator_task_scheduler -o sim\tb_oscillator_task_scheduler.out src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; & 'C:\iverilog\bin\iverilog.exe' -g2012 -Wall -s tb_top_midi_input -o sim\tb_top_midi_input.out sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\uart_rx.v src\midi_note_parser.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_midi_input.v`
> - Ran `$targets = @('D:\GOWINproject\synth1_9_18\sim\tb_oscillator_task_scheduler.out','D:\GOWINproject\synth1_9_18\sim\tb_oscillator_tdm_bank.out','D:\GOWINproject\synth1_9_18\sim\tb_top_midi_input.out'); foreach ($target in $targets) { $resolved = (Resolve-Path -LiteralPath $target).Path; if (-not $resolved.StartsWith('D:\GOWINproject\synth1_9_18\sim\')) { throw "Unexpected path: $resolved" } }; Remove-Item -LiteralPath $targets; git status --short`
> - Ran `rg -n "voice_update|voice_idle|active_voice" src/oscillator_tdm_core.v src/oscillator_tdm_bank.v src/top.v.v sim/tb_oscillator_tdm_bank.v`
> - Wrote `./sim/tb_oscillator_tdm_bank.v` (+30 -30)
> - Wrote `./src/oscillator_tdm_bank.v` (+26 -26)
> - Wrote `./src/oscillator_tdm_core.v` (+26 -26)
> - Wrote `./src/top.v.v` (+7 -7)
> - Ran `rg -n "voice_update|voice_idle|active_voice|midi_voice_allocator|note_state" README.md docs src sim synth1_9_18.gprj -g '!*.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_task_scheduler -o sim\tb_oscillator_task_scheduler.out src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_oscillator_task_scheduler.out }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_tdm_bank -o sim\tb_oscillator_tdm_bank.out src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v sim\tb_oscillator_tdm_bank.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_oscillator_tdm_bank.out }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_midi_input -o sim\tb_top_midi_input.out sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\uart_rx.v src\midi_note_parser.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_midi_input.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' sim\tb_top_midi_input.out }`
> - Ran `Get-Content synth1_9_18.gprj | Select-String -Pattern 'oscillator|freq_lut|square_lut' -Context 1,1; Get-Content -Raw .gitignore; git diff -- src/oscillator_task_scheduler.v src/oscillator_tdm_core.v src/oscillator_tdm_bank.v src/top.v.v`
> - Ran `rg -n "voice_update|voice_idle|active_voice" sim/*.do sim/*.v docs/*.md src/*.v`
> - Ran `rg -n -g '*.do' -g '*.v' -g '*.md' "voice_update|voice_idle|active_voice" sim docs src`
> - Wrote `./docs/adsr_envelope.md` (+1 -1)
> - Wrote `./sim/tb_top_midi_input.v` (+5 -0)
> - Wrote `./src/oscillator_tdm_core.v` (+1 -1)
>
> </details>
>
> 三组自检已经通过：可变 Unison/满 32 任务/整组偷音、TDM 相位与时序、以及真实 UART-MIDI 顶层链路都通过。接口命名也已统一为 `task_*`，振荡器核心只保存相位步进和自身状态，不再含音符或 Unison 概念。接下来做最终全量检查并提交推送。
>
> <details><summary>Ran 4 commands</summary>
>
> - Ran `$targets = @('D:\GOWINproject\synth1_9_18\sim\tb_oscillator_task_scheduler.out','D:\GOWINproject\synth1_9_18\sim\tb_oscillator_tdm_bank.out','D:\GOWINproject\synth1_9_18\sim\tb_top_midi_input.out'); foreach ($target in $targets) { if (Test-Path -LiteralPath $target) { $resolved = (Resolve-Path -LiteralPath $target).Path; if (-not $resolved.StartsWith('D:\GOWINproject\synth1_9_18\sim\')) { throw "Unexpected path: $resolved" }; Remove-Item -LiteralPath $resolved } }; $schedOut = Join-Path $env:TEMP 'codex_synth_task_scheduler.out'; $tdmOut = Join-Path $env:TEMP 'codex_synth_tdm_bank.out'; $topOut = Join-Path $env:TEMP 'codex_synth_top_midi.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_task_scheduler -o $schedOut src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $schedOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_tdm_bank -o $tdmOut src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v sim\tb_oscillator_tdm_bank.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $tdmOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_midi_input -o $topOut sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\uart_rx.v src\midi_note_parser.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_midi_input.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $topOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git diff --check; rg -n -g '*.v' -g '*.md' -g '*.do' "midi_voice_allocator|voice_update_note|note_state|voice_idle_mask" src sim docs README.md; git status --short`
> - Ran `git diff --stat; git diff --name-status; git branch --show-current; git remote -v`
> - Ran `git add -- README.md docs/adsr_envelope.md docs/dynamic_voice_normalization.md docs/tdm_scheduler_validation.md sim/run_task_scheduler_test.do sim/run_top_midi_test.do sim/tb_oscillator_task_scheduler.v sim/tb_oscillator_tdm_bank.v sim/tb_top_midi_input.v src/midi_voice_allocator.v src/oscillator_task_scheduler.v src/oscillator_tdm_bank.v src/oscillator_tdm_core.v src/top.v.v synth1_9_18.gprj; git diff --cached --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git commit -m "refactor: schedule generic oscillator tasks"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git push origin main`
> - Ran `git status --short; git log -3 --oneline --decorate; git rev-parse HEAD; git rev-parse origin/main`
>
> </details>
</details>

已按你的架构完成并推送到 GitHub。

主要改动：

- 采用 4 个统一物理振荡器引擎，每个引擎时分复用 8 个任务，共 32 个振荡器任务。
- Unison 完全由全局调度器展开，不存在专用 Unison 振荡器。
- 每个普通任务只包含相位步进、相位、ADSR 和使能状态。
- Unison 成员轮流分配给不同物理引擎。
- 支持 1～8 个 Unison 成员、同音重触发和成员数变化。
- 满载时按完整音符组进行声部偷取。
- 动态归一化按实际振荡器任务数计算。
- 任务数增加时立即降低增益，减少同相叠加造成的瞬时削波；恢复增益仍然平滑。
- 当前顶层默认 `Unison=3`，约为 `-4 / 0 / +4 cents`。

验证结果：

- 可变 Unison、32 任务满载和整组偷音：通过
- TDM 相位、ADSR、归一化和调度时序：通过
- UART MIDI、Running Status、Note On/Off 和四引擎顶层链路：通过
- 未运行 Gowin 综合或布局布线

提交已经推送：

```text
c228f6f refactor: schedule generic oscillator tasks
```

当前工作区干净，`main` 与 `origin/main` 一致。下一步可以重新生成 bitstream 上板试听。目前波形仍然是方波。

> 可以，按我的想法更改吧

已经按你的方案更改完成并推送：

- 4 个统一物理振荡器引擎
- 每个引擎时分复用 8 个任务，共 32 个普通振荡器任务
- Unison 由全局调度器展开和分配
- 振荡器内部不再包含 Unison 专用逻辑
- 当前默认每个音符分配 3 个 Unison 成员
- 仿真测试全部通过

Git 提交：`c228f6f`

现在可以重新生成 bitstream 并上板测试。

> 感觉无论如何耳机的声音失真都太严重了，直接看fpga里的波形会更好

对，先绕开耳机、DAC 和板载功放，直接观察 FPGA 内部数字波形更容易定位失真来源。

推荐使用 Gowin 的片上逻辑分析仪 GAO，重点抓取：

- `oscillator_mix`：振荡器混合、归一化之后，FIR 之前
- `filtered_sample`：FIR 之后、送入 PT8211 之前
- `oscillator_mix_valid`
- `fir_output_valid`
- `active_task_count`
- 4 个振荡器引擎的部分和
- 各 Unison 成员的 `phase_state`、`phase_step_state` 和 ADSR 电平

观察时要以对应的 `valid` 信号为采样使能，不能直接把 50 MHz 下重复保持的数值当成连续音频采样。也不建议首先观察 `HP_DIN`，它只是串行化后的单比特数据，不容易直接判断波形是否正确。

这样可以分层判断：

1. `oscillator_mix` 已失真：问题在振荡器、Unison 求和、ADSR或归一化。
2. `oscillator_mix` 正常而 `filtered_sample` 失真：问题在 FIR。
3. 两者都正常但耳机失真：问题基本位于 PT8211、模拟输出或板载功放。

下一步我建议给顶层添加专门的 GAO 调试总线和采样触发信号，然后再生成一次调试 bitstream。

> 调试的时候会占端口，midi输入先取消，改成固定的一个音符吧

<details><summary>6 previous messages</summary>

> 可以。我会把硬件顶层暂时切成“复位后自动触发一个固定音符”，移除 UART/MIDI 接收链路和对应顶层端口，让该引脚可用于调试；振荡器调度架构保留，固定音符仍按当前默认 Unison 数展开。先确认工作区和端口约束，再修改并补一个自检。
>
> <details><summary>Ran a command</summary>
>
> - Ran `git status --short; rg -n "uart_rx|UART|S14|IO_LOC|top" -g '*.v' -g '*.v.v' -g '*.cst' -g '*.sdc' -g '*.gprj' -g '*.md' .`
>
> </details>
>
> 我发现工作区里已有两项不是我产生的改动：`synth1_9_18.gprj` 被修改，并新增了 `src/wavecheck.rao`，看起来正是你刚建立的 GAO 调试配置。我会保留它们，不覆盖也不单独提交；先检查它们如何关联端口，然后让固定音符改动与这套调试配置兼容。
>
> <details><summary>Created 2 files, edited 2 files, deleted 2 files, ran 3 commands</summary>
>
> - Ran `git diff -- synth1_9_18.gprj; Get-Item src\wavecheck.rao | Format-List FullName,Length,LastWriteTime; Get-Content -Encoding UTF8 -TotalCount 120 src\wavecheck.rao; Get-Content -Encoding UTF8 -Raw src\top.v.v; Get-Content -Encoding UTF8 -Raw constraints\tang_mega_138k_audio_test.cst`
> - Ran `rg -n "7'd69" src/freq_lut.v; Get-Content -Encoding UTF8 -Raw sim/fir_decimator_8x_ip_stub.v; Get-Content -Encoding UTF8 -Raw sim/run_top_midi_test.do | Select-Object -First 80`
> - Wrote `./constraints/tang_mega_138k_audio_test.cst` (+0 -2)
> - Deleted `./sim/run_top_midi_test.do` (+0 -35)
> - Deleted `./sim/tb_top_midi_input.v` (+0 -231)
> - Wrote `./src/top.v.v` (+18 -35)
> - Wrote `./sim/run_top_fixed_note_test.do` (+33 -0)
> - Wrote `./sim/tb_top_fixed_note.v` (+109 -0)
> - Ran `$out = Join-Path $env:TEMP 'codex_synth_top_fixed_note.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_fixed_note -o $out sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_fixed_note.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' $out }`
>
> </details>
>
> 固定音符模式已工作：复位释放后只产生一次 A4（MIDI 69）Note On，并且默认只分配 1 个振荡器任务，便于看到未经 Unison 拍频干扰的方波。UART 顶层端口和 V14 引脚约束已经移除，仿真确认持续产生非零音频样本且没有调度超时。
>
> <details><summary>Edited 3 files, ran 5 commands</summary>
>
> - Ran `git status --short; git diff -- src/top.v.v constraints/tang_mega_138k_audio_test.cst sim/run_top_midi_test.do sim/tb_top_midi_input.v; rg -n "run_top_midi_test|USB-UART MIDI|UART MIDI|uart_rx" README.md docs src/top.v.v constraints sim -g '*.md' -g '*.v' -g '*.v.v' -g '*.cst' -g '*.do'`
> - Wrote `./README.md` (+9 -4)
> - Wrote `./docs/midi_uart_test.md` (+4 -0)
> - Wrote `./docs/tdm_scheduler_validation.md` (+2 -3)
> - Ran `rg -n "PHASE|oversample_tick|sample_tick|96000|768000|DECIM" src/pt8211_tx.v src/fir_decimator_8x_wrapper.v src/freq_lut.v src/oscillator_tdm_core.v docs -g '*.md' -g '*.v'; Get-Content -Encoding UTF8 -TotalCount 90 src/pt8211_tx.v`
> - Ran `$schedOut = Join-Path $env:TEMP 'codex_fixed_sched.out'; $tdmOut = Join-Path $env:TEMP 'codex_fixed_tdm.out'; $topOut = Join-Path $env:TEMP 'codex_fixed_top.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_task_scheduler -o $schedOut src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $schedOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_tdm_bank -o $tdmOut src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v sim\tb_oscillator_tdm_bank.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $tdmOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_fixed_note -o $topOut sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_fixed_note.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $topOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git diff --check; git status --short`
> - Ran `git add -- README.md constraints/tang_mega_138k_audio_test.cst docs/midi_uart_test.md docs/tdm_scheduler_validation.md sim/run_top_midi_test.do sim/tb_top_midi_input.v sim/run_top_fixed_note_test.do sim/tb_top_fixed_note.v src/top.v.v; git diff --cached --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git commit -m "debug: replace MIDI input with fixed note"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git push origin main`
> - Ran `git status --short; git show --stat --oneline --summary HEAD; git rev-parse --short origin/main`
>
> </details>
</details>

已改为固定音符调试模式：

- 复位后自动触发一次 A4（MIDI 69）。
- 默认 `Unison=1`，只运行一个振荡器任务，便于观察原始波形。
- 移除了 `uart_rx` 顶层端口及 V14 引脚约束。
- 音符持续保持，不会自动 Note Off。
- `oscillator_mix` 和 `filtered_sample` 信号名称保持不变，现有 GAO 配置仍可使用。

三组 RTL 仿真全部通过，未运行 Gowin 综合或布局布线。

提交已推送：

```text
76c81d2 debug: replace MIDI input with fixed note
```

你创建的 `wavecheck.rao` 及其工程文件改动已保留在本地，没有纳入我的提交。固定音符可在 [top.v.v](./src/top.v.v:3) 中修改。

> 这时候使用哪个信号做触发信号比较好

当前固定音符模式下，推荐用 `task_update_valid` 的上升沿作为触发。

它表示固定 A4 已经真正写入振荡器任务槽，比 `fixed_note_event_valid` 更贴近音频链路起点。操作顺序是：

1. GAO 先进入等待触发状态。
2. 按一下板上复位键。
3. `task_update_valid` 上升沿触发采集。

同时把这些信号加入采集：

- `oscillator_mix[15:0]`
- `oscillator_mix_valid`
- `filtered_sample[15:0]`
- `fir_output_valid`
- `active_task_count`
- `task_update_valid`

需要注意：`sys_clk=50 MHz`、深度 4096 时只能记录约 `81.9 ?s`，远小于 A4 的一个周期（约 `2.27 ms`），直接看不到完整音频波形。

因此更合适的配置是：

- 看 FIR 前波形：以 `oscillator_mix_valid` 作为采样使能，只保存有效的 768 kHz 样本。
- 看 FIR 后波形：以 `fir_output_valid` 作为采样使能，只保存有效的 96 kHz 样本。
- 触发仍使用 `task_update_valid` 上升沿。
- 如果只想看稳定波形，可以等待声音稳定后使用 GAO 的手动强制触发。

不要用 `sys_clk` 本身作为触发条件，它一直翻转，基本等同于立即随机触发。

> 这个文件是以`fir_output_valid`   为时钟抓到的波形，应该有问题
>
> User context
>
> Attachments:
> - wavecheck_core0.csv: `./impl/wave/wavecheck_core0.csv`

<details><summary>6 previous messages</summary>

> 我会按电子表格分析流程读取这份 CSV，先确认列定义、采样数量和时间顺序，再计算波形的周期、幅值分布与重复模式。重点判断问题来自抓取时钟方式，还是 `filtered_sample` 本身已经异常。
>
> <details><summary>Explored a file</summary>
>
> - Read `C:/Users/teenagekiller/.codex/plugins/cache/openai-primary-runtime/spreadsheets/26.921.10847/skills/spreadsheets/SKILL.md`
>
> </details>
>
> 这个技能要求只读分析时保留原始 CSV，不生成或覆盖工作簿。我现在补齐它要求的只读审计说明，随后直接解析采样数据；不会修改你的抓波文件。
>
> <details><summary>Ran 4 commands</summary>
>
> - Ran `$p='C:\Users\teenagekiller\.codex\plugins\cache\openai-primary-runtime\spreadsheets\26.921.10847\skills\spreadsheets'; $lines=Get-Content "$p\SKILL.md"; $lines | Select-Object -Skip 120 -First 180; Get-Content -Raw "$p\workflows\edit_workflows.md"; Get-Content -Raw "$p\references\read_only_qna.md"`
> - Ran `$p='C:\Users\teenagekiller\.codex\plugins\cache\openai-primary-runtime\spreadsheets\26.921.10847\skills\spreadsheets'; (Get-Content "$p\SKILL.md") | Select-Object -Skip 300; Get-Content -Raw "$p\artifact_tool_docs\API_QUICK_START.md"; Get-Content -Raw "$p\style_guidelines.md"`
> - Ran `$p='D:\GOWINproject\synth1_9_18\impl\wave\wavecheck_core0.csv'; Get-Item -LiteralPath $p | Format-List FullName,Length,LastWriteTime; Get-Content -LiteralPath $p -TotalCount 15; Get-Content -LiteralPath $p -Tail 10`
> - Ran `Get-Content -Encoding UTF8 -Raw src/fir_decimator_8x_wrapper.v; $p='impl\wave\wavecheck_core0.csv'; $data=Get-Content $p | Select-Object -Skip 7 | ConvertFrom-Csv -Header time,osc,filtered,extra; $data.Count; $data | Select-Object -First 5 | Format-Table; $data | Group-Object osc | Sort-Object Count -Descending | Select-Object -First 12 Name,Count | Format-Table; $data | Group-Object filtered | Sort-Object Count -Descending | Select-Object -First 12 Name,Count | Format-Table`
>
> </details>
>
> 初步看，数据本身不像“完全坏掉”：`oscillator_mix` 是稳定的两电平方波，幅值为 ±22937；`filtered_sample` 在大部分稳态区间相同，只在跳变附近出现 FIR 的过渡与振铃。最可疑的是 CSV 的时间轴：GAO 把 `fir_output_valid` 当采样时钟后，第一列的 `1 us` 实际只是“第 1 个有效输出样本”，并不是真正的 1 微秒。我继续量化周期和 FIR 延迟。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `$lines=Get-Content -LiteralPath 'impl\wave\wavecheck_core0.csv'; $start=[Array]::IndexOf($lines,'time unit: us, oscillator_mix[15:0], filtered_sample[15:0],')+1; $rows=@(); for($i=$start;$i -lt $lines.Count;$i++){ if($lines[$i].Trim()){ $f=$lines[$i].Split(','); $rows += [pscustomobject]@{n=[int]$f[0]; osc=[int]$f[1]; filt=[int]$f[2]} } }; $oscTransitions=@(); $filtTransitions=@(); for($i=1;$i -lt $rows.Count;$i++){ if(([math]::Sign($rows[$i].osc)) -ne ([math]::Sign($rows[$i-1].osc))){$oscTransitions += $i}; if(([math]::Sign($rows[$i].filt)) -ne ([math]::Sign($rows[$i-1].filt))){$filtTransitions += $i} }; $eq=($rows | Where-Object {$_.osc -eq $_.filt}).Count; $fvals=$rows.filt | Sort-Object -Unique; "rows=$($rows.Count) equal=$eq ($([math]::Round(100*$eq/$rows.Count,2))%)"; "osc range=$($rows.osc | Measure-Object -Minimum | % Minimum)..$($rows.osc | Measure-Object -Maximum | % Maximum), unique=$(($rows.osc | Sort-Object -Unique).Count)"; "filt range=$($rows.filt | Measure-Object -Minimum | % Minimum)..$($rows.filt | Measure-Object -Maximum | % Maximum), unique=$($fvals.Count)"; "osc transitions: $($oscTransitions -join ', ')"; "osc half-periods: $((for($i=1;$i -lt $oscTransitions.Count;$i++){$oscTransitions[$i]-$oscTransitions[$i-1]}) -join ', ')"; "filt transitions: $($filtTransitions -join ', ')"; "filt half-periods: $((for($i=1;$i -lt $filtTransitions.Count;$i++){$filtTransitions[$i]-$filtTransitions[$i-1]}) -join ', ')"; "transition neighborhoods:"; foreach($t in $oscTransitions | Select-Object -First 3){$lo=[math]::Max(0,$t-5);$hi=[math]::Min($rows.Count-1,$t+12); "OSC transition $t"; $rows[$lo..$hi] | Format-Table -AutoSize | Out-String -Width 120 }`
> - Ran `$lines=Get-Content -LiteralPath 'impl\wave\wavecheck_core0.csv'; $start=[Array]::IndexOf($lines,'time unit: us, oscillator_mix[15:0], filtered_sample[15:0],')+1; $rows=@(); for($i=$start;$i -lt $lines.Count;$i++){ if($lines[$i].Trim()){ $f=$lines[$i].Split(','); $rows += [pscustomobject]@{n=[int]$f[0]; osc=[int]$f[1]; filt=[int]$f[2]} } }; $oscTransitions=@(); $filtTransitions=@(); for($i=1;$i -lt $rows.Count;$i++){ if(([math]::Sign($rows[$i].osc)) -ne ([math]::Sign($rows[$i-1].osc))){$oscTransitions += $i}; if(([math]::Sign($rows[$i].filt)) -ne ([math]::Sign($rows[$i-1].filt))){$filtTransitions += $i} }; $eq=($rows | Where-Object {$_.osc -eq $_.filt}).Count; $oscMin=($rows.osc | Measure-Object -Minimum).Minimum; $oscMax=($rows.osc | Measure-Object -Maximum).Maximum; $oscUnique=($rows.osc | Sort-Object -Unique).Count; $filtMin=($rows.filt | Measure-Object -Minimum).Minimum; $filtMax=($rows.filt | Measure-Object -Maximum).Maximum; $filtUnique=($rows.filt | Sort-Object -Unique).Count; $oscHalf=@(); for($i=1;$i -lt $oscTransitions.Count;$i++){$oscHalf += $oscTransitions[$i]-$oscTransitions[$i-1]}; $filtHalf=@(); for($i=1;$i -lt $filtTransitions.Count;$i++){$filtHalf += $filtTransitions[$i]-$filtTransitions[$i-1]}; "rows=$($rows.Count) equal=$eq ($([math]::Round(100*$eq/$rows.Count,2))%)"; "osc range=$oscMin..$oscMax unique=$oscUnique"; "filt range=$filtMin..$filtMax unique=$filtUnique"; "osc transitions: $($oscTransitions -join ', ')"; "osc half-periods: $($oscHalf -join ', ')"; "filt transitions: $($filtTransitions -join ', ')"; "filt half-periods: $($filtHalf -join ', ')"; foreach($t in ($oscTransitions | Select-Object -First 3)){ $lo=[math]::Max(0,$t-5); $hi=[math]::Min($rows.Count-1,$t+12); "OSC transition $t"; $rows[$lo..$hi] | Format-Table -AutoSize | Out-String -Width 120 }`
>
> </details>
</details>

这份波形数据本身基本正常；有问题的是时间轴解释和抓取时钟的使用方式。

分析 [wavecheck_core0.csv](./impl/wave/wavecheck_core0.csv) 的 1024 个采样点后：

- `oscillator_mix` 只有 `-22937` 和 `+22937` 两个值，符合当前方波输出。
- 每次翻转严格间隔 109 个 FIR 输出样本。
- 按 96 kHz 输出采样率计算：

  ```text
  96000 / (109 × 2) ≈ 440.37 Hz
  ```

  与固定 A4 的 440 Hz吻合。

- `filtered_sample` 比原始方波延迟固定 8 个输出样本，约 `83.3 ?s`。
- FIR 跳变附近出现振铃，峰值约 ±26310，相对稳态幅度过冲约 14.7%。
- 最大值没有达到 ±32767，因此没有数字削波。
- 86.4% 的采样点上，滤波前后数值完全相同；差异集中在方波边沿附近。

CSV 第一列的 `time unit: us` 是误导性的。使用 `fir_output_valid` 作为 GAO 采样时钟后，`0、1、2……` 实际表示输出样本序号，每格应理解为约 `10.4167 ?s`，不是 1 ?s。

另外，`fir_output_valid` 是单周期有效脉冲，不是真正的连续时钟。当前抓取结果仍然可用，但更稳妥的设置是：

- GAO 采样时钟使用 `sys_clk`；
- 将 `fir_output_valid` 作为采样使能或数据有效标记；
- 如果 GAO 不能按有效信号压缩存储，可用 `HP_WS` 上升沿采样 `filtered_sample`；
- 触发仍使用 `task_update_valid`，或者稳定运行后手动触发。

因此目前没有看到振荡器频率错误、随机抖动或数字削波。看到的尖锐方波和边沿振铃，与当前使用 `square_lut` 完全一致。这个结论来自只读 CSV 审计，没有修改原文件。 :codex-file-citation{path="D:\GOWINproject\synth1_9_18\impl\wave\wavecheck_core0.csv" purpose="source"}

- 检查 FIR 振铃
- 改用正弦测试
- 配置正确抓波

> 真符合方波输出吗？怎么每个周期都反转，不可能反转的这么频繁

符合方波。关键是 CSV 第一列不是微秒，而是 `fir_output_valid` 的采样序号。

实际数据排列是：

```text
采样 0～83：     -22937
采样 84～192：   +22937
采样 193～301：  -22937
采样 302～410：  +22937
采样 411～519：  -22937
……
```

也就是每隔 109 个输出样本反转一次，不是每个样本都反转。

因为 `fir_output_valid` 的频率约为 96 kHz：

```text
半周期 = 109 / 96000 ≈ 1.135 ms
完整周期 = 218 / 96000 ≈ 2.271 ms
频率 = 1 / 2.271 ms ≈ 440.37 Hz
```

这正好对应固定的 A4（440 Hz）。

你感觉“反转太频繁”，是因为 GAO 把横轴错误标成了微秒：

```text
CSV 显示：第 84 us 反转
实际含义：第 84 个 96 kHz 样本反转
实际时间：84 × 10.4167 ?s ≈ 875 ?s
```

第一段不足109点，是因为采集从方波半周期中间开始；后面所有翻转间隔都是严格的109点。

另一个容易混淆的地方是 `filtered_sample`：它在边沿附近会连续出现多个不同数值，例如：

```text
-24205, -3574, 21041, 25826, 22173...
```

这是 FIR 的边沿过渡和振铃，不是振荡器每拍反相。真正的符号翻转仍然每隔109个输出样本发生一次。

所以频率没有异常，异常的是 GAO 对派生脉冲 `fir_output_valid` 的时间刻度解释。把横轴按“每格 10.4167 ?s”换算，波形就是标准的约440 Hz方波。

> 好的，那下一项测试吧，测测unison

<details><summary>6 previous messages</summary>

> 下一项切到三重 Unison：固定音符仍为 A4，把默认成员数改为 3，调度器应分别生成约 `-4 / 0 / +4 cents` 的三个普通任务并分配到三个物理引擎。你的 GAO 工程和 `wavecheck.rao` 会继续保留，我只改 RTL 默认值与自检。
>
> <details><summary>Edited 3 files, ran 2 commands</summary>
>
> - Ran `$b=0x00258BF2; $u=($b -shr 10)+($b -shr 13)+($b -shr 14); 'base={0:X8} unit={1:X8} low={2:X8} high={3:X8}' -f $b,$u,($b-2*$u),($b+2*$u); git status --short; rg -n "DEFAULT_UNISON_COUNT|FIXED_MIDI_NOTE|expected one oscillator|task_update_count" src/top.v.v sim/tb_top_fixed_note.v README.md`
> - Wrote `./README.md` (+4 -3)
> - Wrote `./sim/tb_top_fixed_note.v` (+29 -12)
> - Wrote `./src/top.v.v` (+1 -1)
> - Ran `$out = Join-Path $env:TEMP 'codex_synth_top_unison.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_top_fixed_note -o $out sim\fir_decimator_8x_ip_stub.v src\reset_release_sync.v src\oscillator_task_scheduler.v src\freq_lut.v src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v src\fir_decimator_8x_wrapper.v src\pt8211_tx.v src\top.v.v sim\tb_top_fixed_note.v; if ($LASTEXITCODE -eq 0) { & 'C:\iverilog\bin\vvp.exe' $out }; git diff --check`
>
> </details>
>
> 三重 Unison 的 RTL 自检已通过：三个任务分别落在全局槽位 `0、8、16`，对应三个不同物理引擎；相位步进为 `0x002575AA、0x00258BF2、0x0025A23A`，即约 `-4 / 0 / +4 cents`。我再跑调度器与 TDM 回归，然后提交这个测试检查点。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `$schedOut = Join-Path $env:TEMP 'codex_unison_sched.out'; $tdmOut = Join-Path $env:TEMP 'codex_unison_tdm.out'; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_task_scheduler -o $schedOut src\freq_lut.v src\oscillator_task_scheduler.v sim\tb_oscillator_task_scheduler.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $schedOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\iverilog.exe' -g2012 -s tb_oscillator_tdm_bank -o $tdmOut src\square_lut.v src\oscillator_tdm_core.v src\oscillator_tdm_bank.v sim\tb_oscillator_tdm_bank.v; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & 'C:\iverilog\bin\vvp.exe' $tdmOut; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git status --short`
> - Ran `git add -- README.md sim/tb_top_fixed_note.v src/top.v.v; git diff --cached --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git commit -m "debug: enable three-member fixed-note unison"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git push origin main; git status --short`
>
> </details>
>
> 本地提交已经完成，但第一次推送时 GitHub 连接被重置；这不是代码错误。我会重试推送，同时继续保留你本地未提交的 GAO 配置。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `git push origin main; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; git rev-parse --short HEAD; git rev-parse --short origin/main; git status --short`
> - Ran `git push origin main`
>
> </details>
</details>

三重 Unison 测试模式已经启用：

- 固定音符：A4
- 成员数：3
- Detune：约 `-4 / 0 / +4 cents`
- 分配槽位：`0、8、16`
- 分布在三个不同物理引擎

RTL 自检和全部回归测试均通过。

抓波时，混合方波除了约 `±22937`，还可能出现约 `±7646` 的中间电平。这表示三个方波因 Detune 逐渐错开，是正常的 Unison 叠加结果。

需要注意，1024 个 96 kHz 样本只有约 `10.7 ms`，而 ±4 cents 与中心音的拍频约为 1 Hz，无法在一次短抓取中看到完整的周期性起伏。可以先观察边沿是否逐渐分裂；完整拍频需要更长时间窗或更强的临时 Detune。

本地提交：

```text
690f70f debug: enable three-member fixed-note unison
```

GitHub 当前无法连接，连续三次推送均因 443 端口连接超时失败，因此该提交暂时只在本地。你的 `wavecheck.rao` 和工程文件改动仍保持未提交状态。

> 检查一下波形
>
> User context
>
> Attachments:
> - wavecheck_core0.csv: `./impl/wave/wavecheck_core0.csv`

<details><summary>4 previous messages</summary>

> 我会用只读 CSV 分析检查这次三重 Unison 抓波，不修改文件。重点核对输出电平是否出现三振荡器叠加应有的中间台阶、边沿漂移规律、峰值与削波，以及 FIR 前后的关系。
>
> <details><summary>Ran 2 commands</summary>
>
> - Ran `$p='C:\Users\teenagekiller\.codex\plugins\cache\openai-primary-runtime\spreadsheets\26.921.10847\skills\spreadsheets'; $s=Get-Content "$p\SKILL.md"; $s | Select-Object -First 170; $s | Select-Object -Skip 170 -First 170; $s | Select-Object -Skip 340; Get-Content -Raw "$p\workflows\edit_workflows.md"; Get-Content -Raw "$p\references\read_only_qna.md"; Get-Content -Raw "$p\artifact_tool_docs\API_QUICK_START.md"; Get-Content -Raw "$p\style_guidelines.md"`
> - Ran `$p='impl\wave\wavecheck_core0.csv'; Get-Item -LiteralPath $p | Format-List Length,LastWriteTime; Get-Content -LiteralPath $p -TotalCount 12; $lines=Get-Content -LiteralPath $p; $headerIndex=-1; for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -like 'time unit:*'){ $headerIndex=$i; break }}; $rows=@(); for($i=$headerIndex+1;$i -lt $lines.Count;$i++){ if($lines[$i].Trim()){ $f=$lines[$i].Split(','); $rows += [pscustomobject]@{n=[int]$f[0]; osc=[int]$f[1]; filt=[int]$f[2]} } }; "rows=$($rows.Count)"; 'osc levels:'; $rows | Group-Object osc | Sort-Object {[int]$_.Name} | Select-Object Name,Count | Format-Table -AutoSize; 'filtered most common:'; $rows | Group-Object filt | Sort-Object Count -Descending | Select-Object -First 20 Name,Count | Format-Table -AutoSize; $omin=($rows.osc|Measure-Object -Minimum).Minimum; $omax=($rows.osc|Measure-Object -Maximum).Maximum; $fmin=($rows.filt|Measure-Object -Minimum).Minimum; $fmax=($rows.filt|Measure-Object -Maximum).Maximum; "ranges osc=$omin..$omax filt=$fmin..$fmax"`
>
> </details>
>
> 这次 CSV 与上次不同：导出数据中途从十进制切换成了十六进制，例如出现 `59C6、E222、A667`。因此不能把整列直接当十进制读取；`E222` 实际是 16 位补码负数，而不是十进制文本。先按每行的实际表示方式统一解码，再判断 Unison 电平。
>
> <details><summary>Ran 4 commands</summary>
>
> - Ran `$p='impl\wave\wavecheck_core0.csv'; Select-String -Path $p -Pattern '[A-F]' | Select-Object -First 8 LineNumber,Line | Format-Table -Wrap -AutoSize; $lines=Get-Content $p; $firstHex=(Select-String -Path $p -Pattern ',\s*[0-9A-F]*[A-F][0-9A-F]*\s*,' | Select-Object -First 1).LineNumber; "firstHexLine=$firstHex"; $lo=[math]::Max(0,$firstHex-6); $hi=[math]::Min($lines.Count-1,$firstHex+8); for($i=$lo;$i -le $hi;$i++){"$($i+1): $($lines[$i])"}; Get-Content $p -Tail 20`
> - Ran `$lines=Get-Content -LiteralPath 'impl\wave\wavecheck_core0.csv'; $headerIndex=-1; for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -like 'time unit:*'){ $headerIndex=$i; break }}; $rows=@(); for($i=$headerIndex+1;$i -lt $lines.Count;$i++){if(-not $lines[$i].Trim()){continue};$f=$lines[$i].Split(',');$oraw=[int]$f[1].Trim();$oval=if($oraw -ge 32768){$oraw-65536}else{$oraw};$fraw=[Convert]::ToInt32($f[2].Trim(),16);$fval=if($fraw -ge 32768){$fraw-65536}else{$fraw};$rows += [pscustomobject]@{n=[int]$f[0];osc=$oval;filt=$fval}}; "rows=$($rows.Count)"; 'osc levels:'; $rows|Group-Object osc|Sort-Object {[int]$_.Name}|Select-Object Name,Count|Format-Table -AutoSize; $fmin=($rows.filt|Measure-Object -Minimum).Minimum;$fmax=($rows.filt|Measure-Object -Maximum).Maximum;$funique=($rows.filt|Sort-Object -Unique).Count;"filter range=$fmin..$fmax unique=$funique"; 'filter common:';$rows|Group-Object filt|Sort-Object Count -Descending|Select-Object -First 12 Name,Count|Format-Table -AutoSize; $runs=@();$start=0;$level=$rows[0].osc;for($i=1;$i -le $rows.Count;$i++){if($i -eq $rows.Count -or $rows[$i].osc -ne $level){$runs += [pscustomobject]@{start=$start;end=$i-1;len=$i-$start;level=$level};if($i -lt $rows.Count){$start=$i;$level=$rows[$i].osc}}}; 'osc runs:';$runs|Format-Table -AutoSize; $clipOsc=($rows|Where-Object {$_.osc -eq 32767 -or $_.osc -eq -32768}).Count;$clipFilt=($rows|Where-Object {$_.filt -eq 32767 -or $_.filt -eq -32768}).Count;"clip osc=$clipOsc filt=$clipFilt"`
> - Ran `$lines=Get-Content 'impl\wave\wavecheck_core0.csv';$h=($lines|Select-String '^time unit:').LineNumber;$o=@();$filt=@();for($i=$h;$i -lt $lines.Count;$i++){if(-not $lines[$i].Trim()){continue};$x=$lines[$i].Split(',');$u=[int]$x[1].Trim();$o+=if($u-ge32768){$u-65536}else{$u};$u=[Convert]::ToInt32($x[2].Trim(),16);$filt+=if($u-ge32768){$u-65536}else{$u}};$bestLag=0;$bestMse=[double]::PositiveInfinity;for($lag=0;$lag-le20;$lag++){$sum=0.0;$count=$o.Count-$lag;for($i=0;$i-lt$count;$i++){$d=[double]$filt[$i+$lag]-$o[$i];$sum+=$d*$d};$mse=$sum/$count;if($mse-lt$bestMse){$bestMse=$mse;$bestLag=$lag};"lag=$lag mse=$([math]::Round($mse,0))"};$meanO=($o|Measure-Object -Average).Average;$meanF=($filt|Measure-Object -Average).Average;$rmsO=[math]::Sqrt((($o|ForEach-Object {$_*$_}|Measure-Object -Average).Average));$rmsF=[math]::Sqrt((($filt|ForEach-Object {$_*$_}|Measure-Object -Average).Average));"best lag=$bestLag samples ($([math]::Round(1000*$bestLag/96,3)) us), means osc=$([math]::Round($meanO,2)) filt=$([math]::Round($meanF,2)), rms osc=$([math]::Round($rmsO,2)) filt=$([math]::Round($rmsF,2))"`
> - Ran `$lines=Get-Content 'impl\wave\wavecheck_core0.csv';$h=($lines|Select-String '^time unit:').LineNumber;$o=@();for($i=$h;$i-lt$lines.Count;$i++){if(-not$lines[$i].Trim()){continue};$x=$lines[$i].Split(',');$u=[int]$x[1].Trim();$o+=if($u-ge32768){$u-65536}else{$u}};$scores=@();for($lag=205;$lag-le230;$lag++){$same=0;$count=$o.Count-$lag;for($i=0;$i-lt$count;$i++){if($o[$i]-eq$o[$i+$lag]){$same++}};$scores += [pscustomobject]@{lag=$lag;same=$same;percent=[math]::Round(100*$same/$count,2)}};$scores|Sort-Object percent -Descending|Select-Object -First 8|Format-Table -AutoSize`
>
> </details>
</details>

这次波形符合三重 Unison 的预期，而且能明确看到三个振荡器已经分离。

CSV 有个容易误判的问题：两列使用了不同的显示进制。

- `oscillator_mix`：无符号十进制，需要按 16 位补码解释。
- `filtered_sample`：十六进制。
- 例如 `57890 → -7646`，而 `E222 → -7646`。
- `5999` 是十六进制 `0x5999 = 22937`，不是十进制 5999。

正确解码后，`oscillator_mix` 只有四个电平：

| 三个方波状态 | 混合输出 |
|---|---:|
| `+++` | +22937 |
| `++-` | +7646 |
| `+--` | -7646 |
| `---` | -22937 |

这正是三个等幅方波相加后再除以 3 的结果。

其他检查结果：

- 主波形约每 218 个 96 kHz 样本重复一次，对应约 `440.37 Hz`。
- 重复率不是100%，而是约98.8%，说明 Detune 正在让三个成员缓慢漂移。
- 边沿间隔呈约 `30、30、49` 个样本，说明三个振荡器的翻转时刻已经错开。
- FIR 输出相对混合输入延迟 8 个样本，即约 `83.3 ?s`。
- FIR 峰值约 ±24037，只比稳态峰值高约4.8%。
- 没有达到 ±32767，不存在数字削波。
- 输出平均值接近零，没有明显直流偏置。

结论：三重 Unison 的任务分配、Detune、求和和 `/3` 归一化都正常。现在这种四级阶梯状波形就是三个略微失谐方波叠加后的正确形态。建议在 GAO 中把两列都设置为“16位有符号十进制”后再导出，避免混合进制造成误判。分析过程遵循只读 CSV 审计，没有修改文件。 :codex-file-citation{path="D:\GOWINproject\synth1_9_18\impl\wave\wavecheck_core0.csv" purpose="source"}

- 增大 Detune 测试
- 切换正弦 Unison
- 检查听感失真来源

> 我想在别的电脑上继续这个项目，怎么迁移比较好

<details><summary>3 previous messages</summary>

> Stream error
>
> Reconnecting 5/5
> request timed out
>
> 最稳妥的是“GitHub 保存源码历史，单独打包本机专用的 Gowin/GAO 配置和生成 IP”。我先检查当前提交是否已推送、还有哪些未提交文件，再给你一套不会漏文件的迁移步骤。
>
> <details><summary>Ran 3 commands</summary>
>
> - Ran `git status --short; git log -4 --oneline --decorate; git rev-parse --short HEAD; git rev-parse --short origin/main; git remote -v; Get-Content -Raw .gitignore`
> - Ran `git ls-files src/*.rao src/advanced_fir_filter README.md docs | Select-Object -First 80; Get-ChildItem -LiteralPath src\advanced_fir_filter -Recurse -File | Select-Object FullName,Length | Format-Table -AutoSize; Get-ChildItem -LiteralPath . -File | Select-Object Name,Length | Format-Table -AutoSize`
> - Ran `rg --files -g '!impl/**' -g '!sim/work*/**' | Sort-Object | Select-Object -First 200`
>
> </details>
</details>

最推荐用“GitHub + 本地重新生成实现文件”的方式迁移，不要直接复制整个工程目录。

当前状态要注意：

- 本地最新提交：`690f70f`，包含三重 Unison 测试。
- GitHub 最新提交：`76c81d2`。
- 本地还有未提交的：
  - `synth1_9_18.gprj`
  - `src/wavecheck.rao`

所以现在直接在另一台电脑 `git clone`，会缺少三重 Unison 和 GAO 配置。

## 旧电脑上

建议把 GAO 配置提交，然后推送：

```powershell
git add synth1_9_18.gprj src/wavecheck.rao
git commit -m "debug: add GAO waveform configuration"
git push origin main
```

`.rao` 是调试配置，可以纳入版本库；实际抓取的 CSV、`impl/`、波形数据库和综合结果不要提交。

确认推送成功：

```powershell
git status
git log -3 --oneline
git rev-parse HEAD
git rev-parse origin/main
```

最后两个哈希应完全相同。

## 新电脑上

安装：

- Gowin EDA `V1.9.12.04`
- 对应器件支持：`GW5AST-LV138PG484AC1/I0`
- 板载下载器所需的 FTDI/JTAG 驱动
- 如需仿真，再安装 ModelSim 或 Icarus Verilog
- 如需 MIDI 上位机：

```powershell
pip install -r tools\requirements.txt
```

然后克隆：

```powershell
git clone https://github.com/haters-bot/synth1_9_18.git
cd synth1_9_18
git log -3 --oneline
```

在 Gowin 中打开：

```text
synth1_9_18.gprj
```

综合、布局布线和 bitstream 应在新电脑重新生成。

## 不需要迁移的文件

这些属于生成结果或本机状态：

```text
impl/
sim/work*/
*.wlf
transcript
modelsim.ini
synth1_9_18.gprj.user
src/advanced_fir_filter/temp/
*.vo
```

其中 FIR 的必要源文件和配置已经受 Git 管理，`fir_decimator_8x_ip.v`、`.ipc` 和系数文件都会随仓库迁移。

如果旧电脑无法连接 GitHub，可以使用 Git Bundle 保存完整历史：

```powershell
git bundle create synth1_9_18.bundle --all
```

把 bundle 拷到新电脑后：

```powershell
git clone synth1_9_18.bundle synth1_9_18
```

但前提仍是先提交 `gprj` 和 `wavecheck.rao`，否则未提交文件不会进入 bundle。

> 对话记录怎么迁移啊

<details><summary>2 previous messages</summary>

> 我会先按 Codex/OpenAI 产品说明确认会话是否会随账号同步；同时结合你仓库里已有的对话记录文件，给你一个即使会话列表不同步也不会丢项目上下文的迁移办法。
>
> <details><summary>Searched the web</summary>
>
> <details><summary>Explored a file</summary>
>
> - Read `C:/Users/teenagekiller/.codex/skills/.system/openai-docs/SKILL.md`
>
> </details>
>
> Searched the web for `site:developers.openai.com/codex conversation history sessions sync devices Codex app ...`
>
> Searched the web for `site:learn.chatgpt.com conversation history export data devices sync account ...`
>
> </details>
</details>

最稳妥的办法不是复制 Codex 的本地会话数据库，而是把“继续项目所需的上下文”放进 Git 仓库。

你的仓库已经有一份较完整的历史记录：

```text
# 我想构建一个波表合成器里的振荡器，但是感觉逻辑稍微有点乱，帮我在这个代码基础.md
```

它会随 Git 一起迁移。不过这个文件约 528 KB，内容很长，而且没有覆盖最近所有进展。建议再建立一个精简的：

```text
docs/project_handoff.md
```

里面记录：

- 当前架构：4 个物理引擎 × 8 个 TDM 槽位
- 当前调试模式：固定 A4、三重 Unison
- Detune：约 `-4 / 0 / +4 cents`
- 最近提交：`690f70f`
- GAO 抓取信号及数据进制
- 已通过的仿真
- 当前未提交的 `wavecheck.rao` 和工程配置
- 下一步准备测试什么
- 不允许自动运行 Gowin 综合/PnR 等项目规则

然后提交并推送。新电脑克隆后，新建 Codex 对话并发送：

```text
请先完整阅读 AGENTS.md、docs/project_handoff.md，
必要时再查阅项目根目录里的完整历史对话记录。
从当前 Git 状态继续，不要重复已经完成的工作。
```

如果新电脑登录相同账号后能看到这条原会话，可以直接打开继续；但不要把它作为唯一迁移手段。官方 Codex 文档说明线程可以通过保留的 thread ID 和本地历史恢复，但没有提供把桌面会话手动导入另一台电脑的通用流程。[OpenAI Codex thread resume 文档](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)

也不建议直接复制整个：

```text
C:\Users\<用户名>\.codex
```

其中可能包含登录凭据、机器相关配置、缓存和本地路径，整体复制容易造成认证或路径问题。

目前还要注意：GitHub 的 `origin/main` 仍停在 `76c81d2`，本地 `690f70f` 尚未推送，而且 `synth1_9_18.gprj`、`src/wavecheck.rao` 尚未提交。因此现在换电脑，最近的 Unison 测试和 GAO 配置还不会自动出现。
