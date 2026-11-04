# UI LFO 能力、有效值预览与启动同步修复

本轮只修改 UI 工程、运行 RTL 仿真和代码审查。没有运行 Gowin 综合/布局布线、没有烧录 SRAM/Flash、没有推送。

## 基准与根因

- 实际仓库 `D:/github/synth1_9_18`，分支 `integration/dual-138k-uart-phase1`；不是 `D:/github/gaoyun` 的旧 UI 副本。
- 开始时 fetch 并 `merge --ff-only` 检查远端：integration 为 `366427637fd51e5e7e335ab219b9ef6ba9d409cb`，本地 HEAD `e981aafc29acfd1747c34d49f70936ed5b489d62` 已包含它，领先 4 提交，无落后。本轮修复保留在工作区，尚未提交。
- GitHub `origin/main` 的只读音频参考固定在 `52242799c1bc8b0ee411a2de39600408472b3219`：`src/lfo_target_router_v2.v`、`src/synth_control_router.v`、`src/top.v.v`。音频源没有修改。
- 速率：附件所述“5 回 0”的旧问题在当前 HEAD 已修好；保留 editor 的 0..7 循环、16/32Hz 标签和 sender 的常量切片模式编码，不重复修改。
- 预览：旧代码绑定后忽略 base、对负深度使用 `127-wave`，并近似除以 127，与音频端加法调制不一致。
- 能力：原绑定/渲染没有区分 53 个保留协议槽与实际接入的 24 个音频目标，造成未接入目标看起来也有效。
- 静态 CC：Phase/Rand 缺少映射与 supported 白名单；已有 Delay/Reverb 6 个已接入目标也没有静态 CC 出口。
- 启动：原顶层只在用户编辑时向 MIDI 投递单拍 CC，没有完整初始快照，也没有 CC 接收握手；FIFO 忙或 Note 同拍优先时无法确认 CC 是否入队。

## 修改位置

| 文件 | 修改 |
|---|---|
| `rtl/ui_vector_engine/audio_capabilities.vh` | 集中定义 53 位掩码；供绑定、预览、渲染使用 |
| `rtl/ui_vector_engine/lfo_binding_state.v` | 拖放、超时和点选绑定拒绝 NC；保存的 source/depth 不清除 |
| `rtl/ui_vector_engine/modulation_overlay.v` | 未接入目标显示灰色 NC；不显示动态有效值标记；保留静态旋钮 |
| `rtl/ui_vector_engine/modulation_preview.v` | 对齐 base 流水；有符号乘法、算术右移 7 位、加 base 后钳位；仍用一个扫描乘法器 |
| `rtl/midi_uart_tx/midi_uart_tx.v` | Phase/Rand CC87..90、Delay/Reverb CC52..57；增加精确入 FIFO 的 `cc_accept` |
| `rtl/ui_vector_engine/params.vh` | 给现有 FX 0x60+index 位置增加具名 ID，不移动 ID/目标位置 |
| `rtl/ui_vector_engine/static_cc_slots.vh` | 集中列出 40 个静态同步槽，与 24 项 LFO 能力表分开 |
| `rtl/param_merger/param_merger.v` | 导出 34 项实时静态值，包括独立 ENV1/ENV2；Filter power/type 合成一个模式值 |
| `rtl/midi_uart_tx/static_cc_sync.v` | 首次逐项同步、FIFO 回压和后续变化同步；比较上次已接收值与当前 UI 值 |
| `rtl/ui_touch_hub_top.v` | 接入 34+6 项实时值、同步器和 UART；静态启动发送完后释放 LFO sender |
| normal/debug `.gprj` | 加入新同步器源；顶层仍为 `ui_touch_hub_top` |
| `sim/tb_*.v`、`tools/test_six_fix.py` | 完整 renderer 速率、能力/像素、实际音频参考、启动并发测试；快照与日志放 E 盘 |

没有修改 `lfo_sysex_tx.v`、曲线插值器、53 项快照格式、7 位安全 SysEx、Restart/Commit 或音频协议。新同步器读取实时总线采用常量切片展开，沿用之前避免 Gowin 动态切片误编译的经验；本轮没有进行网表验证。

## 8 档实际串行字节

完整 renderer 的真实触摸包经过 editor → renderer snapshot → sender → FIFO → UART，覆盖 3×8×4=96 组合，469 个六字节帧。速率测试加速 UART 仅用于缩短仿真，另有真实 50MHz/31250 baud 的绑定回归；生产波特率没有修改。

以下为平滑循环模式：

| Hz | index | LFO1 | LFO2 | LFO3 |
|---|---:|---|---|---|
| 0.25 | 0 | `F0 7D 45 00 00 F7` | `F0 7D 46 00 00 F7` | `F0 7D 47 00 00 F7` |
| 0.5 | 1 | `F0 7D 45 00 01 F7` | `F0 7D 46 00 01 F7` | `F0 7D 47 00 01 F7` |
| 1 | 2 | `F0 7D 45 00 02 F7` | `F0 7D 46 00 02 F7` | `F0 7D 47 00 02 F7` |
| 2 | 3 | `F0 7D 45 00 03 F7` | `F0 7D 46 00 03 F7` | `F0 7D 47 00 03 F7` |
| 4 | 4 | `F0 7D 45 00 04 F7` | `F0 7D 46 00 04 F7` | `F0 7D 47 00 04 F7` |
| 8 | 5 | `F0 7D 45 00 05 F7` | `F0 7D 46 00 05 F7` | `F0 7D 47 00 05 F7` |
| 16 | 6 | `F0 7D 45 00 06 F7` | `F0 7D 46 00 06 F7` | `F0 7D 47 00 06 F7` |
| 32 | 7 | `F0 7D 45 00 07 F7` | `F0 7D 46 00 07 F7` | `F0 7D 47 00 07 F7` |

每个 bank 的模式变化随后依次发送 Restart `F0 7D 48 00 04/05/06 F7` 与 Commit `F0 7D 7E 00 00 F7`，测试检查连续顺序。4Hz Stepped/Once/两者分别为 `0C/14/1C`；完整模式值为 `index | stepped<<3 | once<<4`，不发送 Hz 整数。

## 集中能力表

| 类别 | 已接入的固定目标索引及名称 |
|---|---|
| Master | 4 Level |
| OSC A | 6 Detune；8 Phase；9 Rand；10 WT Position；11 Warp；12 Pan；13 Level |
| OSC B | 15 Detune；17 Phase；18 Rand；19 WT Position；20 Warp；21 Pan；22 Level |
| Filter | 23 Cutoff；24 Resonance；28 Mix |
| Delay | 34 Feedback；35 Left Time；39 Mix |
| Reverb | 40 Size；41 Decay；46 Mix |

其余 29 项：0..3 Macro；5/7、14/16 Unison/Blend；25..27 Filter Pan/Drive/Fat；29..33 ENV1 AHDSR；36..38 Delay Right Time/Filter Freq/Q；42..45 Reverb Low Cut/High Cut/Spin/Depth；47..52 EQ。

NC 只描述 LFO 调制能力。Unison、ENV ADSR、Master Pan 等已经支持的静态操作仍有效；例如内部 Filter Pan ID 仍复用为 Master Pan CC10，但目标 25 没有 LFO 接入。全部 53 项存储/快照/位置保留。既有 NC 路由只保留数据、显示灰色 NC，不伪造音频调制；不自动删除。以后接入目标时修改集中掩码即可恢复绑定和动态预览。

## 预览数值和行为提示

`effective = clamp(base + ((signed(depth) * signed({0,wave})) >>> 7), 0, 127)`。

| base | depth | wave=0 | wave=64 | wave=127 |
|---:|---:|---:|---:|---:|
| 127 | +127 | 127 | 127 | 127 |
| 64 | +63 | 64 | 95 | 126 |
| 127 | -127 | 127 | 63 | 0 |
| 0 | -127 | 0 | 0 | 0 |

逐值测试直接编译固定 Git 提交的原版 `lfo_target_router_v2.v`，没有重写音频模型：255 个深度 ×128 个 wave ×24 已接入目标 =783,360 个对照值，含基础值 0/64/127/变化值；额外核对所有 NC 目标只显示 base。现有独立流水回归继续检查 raw curve、三 bank 相位/采样及 Source=0。

- Detune 是 Unison 声部间距，Unison=1 时可能听不出效果。
- Level/Master/Cutoff 的 base=127 时正深度可能全程钳位；测试 Level 请先降低 base 或使用负深度。
- Phase/Rand 主要影响 Note On 初始状态；保持中的音符不保证连续变化，需要重新触发音符验证。
- 原始 LFO 编辑窗口仍显示原始曲线。预览的本地相位不等于跨板音频时钟/Note 的硬件同步；本轮验证相同输入值的算法一致性。

## 启动静态同步清单

按下表顺序发送。均为 `BF cc value`，表中 CC/value 为十进制；Filter power/type 合用 CC42，只发送一个有效模式。

| 槽 | 参数 | CC | 复位发送值 |
|---:|---|---:|---:|
| 0 | Master Level | 48 | 100 |
| 1 | Master Pan | 10 | 64 |
| 2..11 | A Power/Wave/Unison/Detune/Phase/Rand/WT/Warp/Pan/Level | 36,21,23,22,87,88,20,39,91,46 | 127,0,1,64,0,64,0,64,64,100 |
| 12..21 | B Power/Wave/Unison/Detune/Phase/Rand/WT/Warp/Pan/Level | 37,29,31,30,89,90,28,41,92,47 | 127,96,1,64,0,64,64,64,64,100 |
| 22..25 | Filter Mode/Cutoff/Resonance/Mix | 42,43,44,45 | 1,80,32,127 |
| 26..29 | ENV1 Attack/Decay/Sustain/Release | 24,25,26,27 | 10,40,90,35 |
| 30..33 | ENV2 Attack/Decay/Sustain/Release | 32,33,34,35 | 10,40,90,35 |
| 34..39 | Delay Feedback/Left Time/Mix；Reverb Size/Decay/Mix | 53,52,54,55,56,57 | 64,64,32,64,64,32 |

同步逻辑读取当前 UI bank，不缓存一份会过期的复位常量：尚未发送的参数被修改后直接发送最新值。已经入队的旧值保持 FIFO 顺序，后续变化再发送最新值，不会在新值之后重播旧的启动快照。拥塞期间同一参数的多次中间编辑可以合并，最终值不会丢失；没有值变化的项不重复入队。该保证以用户输入已经被原参数 bank 接收为前提，不改变原触摸/SPI 同拍仲裁规则。

`cc_accept` 只在 CC 真正写入 FIFO 时有效；Note 保留最高优先级和第八个保留槽。六字节 SysEx 仍一次写入两项 FIFO，CC/Note 只能位于完整帧之间。`startup_sync_done` 是顶层内部调试信号：首次 40 项均被接收且 UART 排空后置位保持，再释放 LFO 完整同步。音频板若在 UI 之后单独复位，本轮没有增加音频 ACK/在线重连协议，需要重新触发 UI 复位同步。

独立串行测试实际观察到 Phase/Rand 编辑字节：`BF 57 0B`、`BF 58 0C`、`BF 59 0D`、`BF 5A 0E`。

## 仿真与审查证据

最终统一快照目录：`E:/gaoyun_builds/six_fix_20261031_163653_277245`。17 项全部通过，最终 `result.json` 的 `passed=true`、`workspace_matches_snapshot=true`，包含生产源/头文件/工程/全部测试及测试工具 SHA256 和只读音频参考提交/哈希。仿真进程已退出，没有 Gowin/JTAG 进程。

测试清单：

1. `tb_static_startup_uart`：两次复位；40 项默认逐项仅一次；81 个初始 LFO 帧随后发送；FIFO 满/Note 优先；启动中修改未发送值；LFO 事务中并发 CC/Note；Phase/Rand；绝对/增量、ENV1/2 曲线及 bank 切换；Filter 关/切模式/重开；FX；Hold/ENV3 不发送。
2. `tb_lfo_capabilities`：53 个 ID 对照修复前 Git 内容；24 目标拖放；29 NC 拖放/点选拒绝；既有 NC 路由保留。
3. `tb_lfo_nc_overlay`：53 个单元的真实像素输出；29 灰色 NC，24 已支持未绑定目标不误标。
4. `tb_modulation_preview_pipeline`：1,272 项独立基础值/深度/来源检查，三 bank 相位/采样、切 tab、原始曲线不变。
5. `tb_fx_lfo_routing`：53 位置、24 可绑定目标、FX 拖动/SPI 并发、捕获/抬起/深度/清除/曲线与预览分离。
6. `tb_lfo_binding_release`：缺失 UP、aim grace、短接触超时、晚 UP 去重和状态标记。
7. `tb_lfo_snapshot_race`：绑定与批次锁存同拍竞态。
8. `tb_midi_sysex_handshake`：51 个真实串行字节；Note/CC 优先、满队列和完整帧精确一次。
9. `tb_lfo_sysex_tx`：53 不同目标值、曲线、路由、模式、Restart、Commit。
10. `tb_midi_uart_tx`：普通 Note/CC、四个新 Phase/Rand 和六个 FX CC、原映射/Unison/波形/队列。
11. `tb_lfo_binding_realbaud`：真实 31250 baud 下 raw 触摸归一化→绑定→快照→FIFO→UART。
12. `tb_lfo_editor`：七节点、预设、触摸、Once/Stepped/速率/相位。
13. `tb_lfo_rate_labels`：八档标签包含 16/32Hz。
14. `tb_env_banks_uart`：ENV1/2 绝对/增量/曲线/队列 bank，Hold/ENV3 静默。
15. `tb_lfo_renderer_uart`：完整 renderer 的 target6/13、重绑、切 LFO、超时和串行仲裁。
16. `tb_modulation_audio_equivalence`：783,360 项与实际音频 RTL 逐值对照。
17. `tb_lfo_rate_renderer_uart`：完整 renderer 的 96 组合、469 帧、Mode→Restart→Commit。

旧失败/超时和测试开发中的错误均保留，包括首版测试 oracle 的有符号表达式错误、测试激励未跨完整时钟边沿、旧 `.*` bench 缺新输出声明，以及慢速完整 renderer 回归的超时。它们不是硬件结果，不能用末尾继承的 PASS 替代最终结果。

## 剩余边界

- 最终正式验证已补齐：生产提交83ed585，构建173812五类时序/7时钟/124引脚及112清单项全部通过，20项回归通过；18:00唯一UI SRAM2成功、写后只读UserCode3056/Status26230，FS E2F33AD4…316463FDB。摄像头未见可读屏幕，现场功能验收仍待用户确认。详细新审计、寄存级/步进/列号时序小修补及部署证据见[时序修补记录](STATIC_SYNC_TIMING_2026-10-31.md)。下列未构建/未部署文字仅为当时源码阶段历史，不代表当前状态。
- 2026-10-31用户随后授权正式构建与烧录。首构建 `R16A_build_20261031_164831` / `31a20f4` 生成位流但时序失败：197setup端点、−1.897ns，未部署。现按STA为静态CC出口增加寄存，接收账本记录同拍UART实际取走的数据；堵塞期间更新待发值，同拍新编辑在下次扫描补发。实体旋钮步进及导航列号另作等价时序小修补。以下“没有综合”的结论仅描述授权前源码阶段，最新结果以CODEX_HANDOFF顶部及各次审计为准。
- 本轮没有综合或综合网表、布局布线、硬件串口、听感或上板验收结果。板上仍是之前的 RATE8 版本，不含本轮修改。
- 之前正式构建最差 setup 余量仅 +0.001ns；本轮新增逻辑是否影响资源/时序需用户另行授权构建后审计，不能承诺一次收敛。
- 29 个 NC 目标仍未接入音频；Hold、ENV3 和未定义静态协议的本地控件不凭空新增 CC。音频端未提供独立语义的 EQ/Delay Right/FX 开关等不在 40 项清单中。
- 40 项初始静态 CC 在 31250 baud 下理论串行时间约 38.4ms，加上完整 81 帧 LFO 约 155.52ms 和初始静默等待；Note/实际编辑可能增加时间，不能当作板级固定启动时长。
- 项目正常/调试工程已包含新同步器。`build_isolated.py` 原有头文件收集会把新增两个 `.vh` 纳入 source manifest；本轮只读审查该收集逻辑，没有执行构建。
