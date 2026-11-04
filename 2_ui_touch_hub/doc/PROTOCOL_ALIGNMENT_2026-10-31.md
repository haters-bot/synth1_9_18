# UI／音频协议适配与手机选曲修复（2026-10-31）

> **21:05追加：滑音/颤音改为第六PITCH页，准备与本文件全部改动一起构建。** 最新fetch音频 `origin/main=dbffe3768fa29405ad50845d4e915577d1c16557`（含790d131的C19 Note接收），真实parser/router/LFO router与原5224279逐字节一致。本次参考测试已固定到dbffe37，未合并音频RTL到UI工程。原五效果器顺序不变，后接PITCH；原底部重复控件移入该页。VIBRATO开关CC82、速率83、深度84；PORTAMENTO开关CC85、时间86，均通道16/BF。开关0/127，参数0～127，关闭保留数值；未校准物理单位，不臆造Hz/ms。新页只选择不发CC，拖动/外部绝对值/跨页排队保持各自ID。74启动CC及53个LFO目标不变；滑音/颤音不擅增LFO调制槽。UI截图与最终回归/构建位置以CODEX_HANDOFF顶部为准。当前尚未启动Gowin，用户已授权完成后统一构建，不把下方早期21项/0.2.1当作最终产物。

> **最新音域规则覆盖旧结论：** 每次手机连接后，在UI演奏页CALIBRATE并按实体最左键，F15捕获0x29/0x35/0x41/0x4D之一；0x59因用户实测高端无声禁用。App收到校准成功/epoch后对上传副本整曲移调，音域含两端≤32允许，>32拒传，禁止超宽折八度、丢音或截断。运行时base同时驱动实体跟弹、屏幕/试听和19白灯（另5灯灭）。手机协议增加HELLO nonce、STATUS26和BEGIN8/epoch，音频Note/CC/SysEx和53目标号不改。详见 `MIDI_RANGE_ADAPTATION_2026-10-31.md` 及 `HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md` 顶部。本轮仍只源码/仿真/APK，未EDA/烧录；后文旧固定起音/0x59可用/折八度描述不再有效。

## 范围与版本

实际 UI 工作副本为 `D:/github/synth1_9_18/2_ui_touch_hub`，聊天目录 `D:/github/gaoyun` 不是本次生产工程。分支 `integration/dual-138k-uart-phase1`；本轮修改基于 `1a8ced1bdd0f087809a551d9cafe54e069ac46f6`。修改前已按根 AGENTS 保存并推送基准；本轮新增功能单独保存检查点。没有改动音频 RTL。

本轮再次 `git fetch origin`，可见音频 `origin/main` 仍为 `52242799c1bc8b0ee411a2de39600408472b3219`，integration 远端仍为 `1a8ced1`。审查使用这个确定版本的协议文档和真实 RTL，而非旧的本地音频源码。冻结参考和 SHA 清单：

`E:/gaoyun_builds/protocol_align_20261031_183337/audio_reference_manifest.json`

用户已经转述音频队友修好 C19 Note 接收，本轮不再把它列为阻塞；可见远端版本尚不能证明那份新固件的实现，交接仅要求后续对齐准确提交号，不要求队友重复修复。

本轮仅完成源码、仿真、像素检查及 APK 打包。未启动新的 Gowin 综合／布局布线、未访问 JTAG 写入、未烧 SRAM／Flash。板上仍是上一轮 18:00 部署版（UserCode `0x3056`），不包含本文新增 UI。

## 1. WARP：模式选择与 Amount 独立

原 UI 只有 Amount，没有将队友已实现的 Warp Mode 接入，因此仅旋转 Amount 时，音频 Mode 仍可能是 Off。

现在在 OSC A/B 波形框下沿增加 `WARP <模式>` 按钮，轻点展开 12 项菜单，再点选模式；原 WARP Amount 旋钮保留。不是反复点击 Amount 来切换算法。

| 模式值 | 模式 |
|---:|---|
| 0 | Off |
| 1 | PWM |
| 2 | Sync |
| 3 | Bend + |
| 4 | Bend − |
| 5 | Bend +/− |
| 6 | Asym + |
| 7 | Asym − |
| 8 | Asym +/− |
| 9 | Flip |
| 10 | Mirror |
| 11 | Quantize |

OSC A Mode/Amount 为 CC38/39；OSC B 为 CC40/41。全部 CC 使用通道16 `BF cc value`、31250 baud、8N1。例如 A PWM 为 `BF 26 01`。表格数字为十进制，字节示例为十六进制。

操作参考来源：Xfer 官方产品页 <https://xferrecords.com/products/serum-2>（本次 HTTP200，页面副本 `serum2_official.html` 在冻结参考目录），该页介绍 wavetable warp 功能。旧地址 `/products/serum` 返回404，未将其作为成功来源。这里借鉴模式选择＋独立强度的操作方式，实际 12 项算法和值严格来自队友 RTL，不声称复制 Serum 的全部算法或音色。

## 2. 五级效果链

原生产效果器条与音频链不同：旧 EQ 及若干 Delay/Reverb 参数没有音频对应。现在原效果器区域改成五个页签，不增顶层页面、不挪动 ENV／LFO 区域：

`Dist → Phas → Chor → Dly/Rev → Comp`

它们对应音频固定处理顺序 `Distortion → Phaser → Chorus → Delay/Reverb → Compressor`，页签顺序不表示用户可以重排 DSP。

| 页签 | 音频控制 | 行为 |
|---|---|---|
| Dist | CC58 Enable、59 Type、60 Drive、61 Tone、62 Mix | Type 0 Soft Clip／1 Hard Clip／2 Foldback |
| Phas | CC69 Enable、70 Rate、71 Depth、72 Center、73 Feedback、74 Mix | 独立开关 |
| Chor | CC63 Enable、64 Rate、65 Depth、66 Delay、67 Feedback、68 Mix | 独立开关 |
| Dly/Rev | CC51 Mode；52 Time、53 Feedback、54 Mix；55 Size、56 Decay、57 Mix | Delay/Reverb 两个开关合成为 Mode 的两个位 |
| Comp | CC75 Enable、76 Threshold、77 Ratio、78 Attack、79 Release、80 Makeup、81 Mix | 独立开关 |

CC51 的 0/1/2/3 分别为两者关闭／仅 Delay／仅 Reverb／两者开启。3 是音频既有的等权并联，不是串联。其他 Enable 用 0／127，音频实际判定非0即开启。

参数块支持水平／垂直拖动，显示原始 MIDI 值0～127，避免显示没有校准依据的 dB／Hz。效果器下方补上队友已支持的 Vibrato CC82～84 和 Portamento CC85～86 开关及参数。

新增34项使用 UI 内部 ID `A0..C1`，通过独立静态参数库发送 CC；它们不是音频 SysEx ID，也不是新增 LFO 目标。原53目标表、编号和 LFO 编码保持。

原六个已接入音频的 Delay/Reverb LFO 目的地继续可绑定：targets34/35/39/40/41/46。在新参数块上拖入 LFO，转换坐标后仍送原绑定状态机；回归观测 LFO1/+127 路由依次为：

```text
target35 Time     F0 7D 6C 02 7F F7
target34 Feedback F0 7D 6B 02 7F F7
target39 Dly Mix  F0 7D 70 02 7F F7
target40 Rev Size F0 7D 71 02 7F F7
target41 Decay    F0 7D 72 02 7F F7
target46 Rev Mix  F0 7D 77 02 7F F7
```

各次更新后保留 Commit。旧 EQ targets47～52 仍保留为 NC，绝不借它们发送 Distortion。新 Dist／Phaser／Chorus／Compressor 暂为静态控制，音频现有53槽没有它们的通用 LFO 目的地。

旧实体 FX 旋钮的 Delay Feedback／Reverb Size 调节保留。新 FX 触摸与不同实体参数同拍更新时，两项都保存；同参数触摸持有期间触摸优先，释放后实体恢复。新增全部 FX 参数可触摸操作；没有擅改32旋钮板的固件／编号来为每项分配实体旋钮。

## 3. 真实 WAVEBANK.WTB

只读核验用户文件 `D:/github/gaoyun/WAVEBANK.WTB`，并对照音频 `tools/pack_wavetable_bank.py` 和 `docs/sd_ddr_wavetable_path.md`：

- WTB1 v1，10张，每张256帧×256点×16bit小端；总长1,310,752字节。
- SHA256：`59a09d279c4a55883cb92085a890e405e0b3494d5b03048ffad6765c05ae2a90`。
- WTB1没有表名字段，因此按 `BANK 00..09` 显示，不杜撰源 WAV 名称。
- 本轮不把1.3MB音频负载复制进 UI FPGA ROM；真实声音仍来自音频板SD→DDR。

OSC 波形选择增加第五项 `SD BANK`；A发 `BF 15 7F`，B发 `BF 1D 7F`。波形框下沿右侧 BANK 的左／右半区分别减／加，0～9循环。A/B分别发 CC49/50，例如A第9表 `BF 31 09`、B第9表 `BF 32 09`；WT Position 仍为CC20/28。先选表再切SD也会保存并发送选择。

`tools/import_wavetable_catalog.py` 校验头、版本、保留字节、尺寸、位深、长度，生成 `wavetable_catalog.vh` 和 `doc/WAVETABLE_CATALOG_2026-10-31.json`（含每表hash及幅度范围）。音频板换包后需重新导入并构建UI，当前没有状态／目录回传可自动发现新数量。

```powershell
python tools/import_wavetable_catalog.py D:/github/gaoyun/WAVEBANK.WTB
```

音频加载器按 SD 根目录第0个普通文件读取，不是搜索同名文件。需确认SD实际加载的是同一包。UI没有SD就绪／哈希回传，不会伪造“已加载成功”。初版固定显示无预览／状态不可获取；后续已补本地 WTB 预览源码，详见 `SD_WAVETABLE_PREVIEW_2026-10-31.md`，不等于该预览已经上板。预览随BANK及WT POSITION变化，并注明LOCAL，不冒充音频板的SD状态或实际输出采样；常规四波形图仍是原本的本地示意。

## 4. PAN 的实际含义与修正

OSC A/B 的 PAN 分别发 CC91/92；MASTER PAN（K27，沿用内部 `FLT_PAN` ID）发 CC10。三者都为0硬左、64中心、127硬右，默认64。没有交换A/B、没有把PAN当音量或仅控制示波图。

音频 `stereo_pan_mixer.v`／`stereo_output_stage.v` 使用中心不衰减的线性平衡律，中心L/R增益均为1，不是 equal-power 的左右各0.707。大致为：左半区保持左1并提高右；右半区保持右1并降低左，127时左强制0。因此中心更响并不自动说明 CC 映射错误。

UI原16方向指针表在64时落到右偏约9°，是确定的视觉问题。现在三路PAN=64均画垂直指针并显示 `C`；63／65仍分别位于左／右。0/64/127真实UART回归已送入队友原版parser/router验证。

另外，当前音频先计算 Mid=(L+R)/2、Side=(L−R)/2，只有Mid进入全局滤波／FX，Side旁通，最后重构L/R再应用Master/PAN。所以硬PAN且开非线性FX时，可能出现对侧有效果声、声像或听感变化。这属于音频现有架构边界，不能通过UI“把64改成63”解决。本轮未擅改音频平衡律／DSP。严格立体声效果或equal-power需要双方另行确认和音频资源评估。

## 5. APK 0.2.1：选文件到上传

> 后续更新：19:59已生成0.2.3/code5，修正起音0x29=41并加入自动移调/折八度；本节0.2.1为原生选文件首次修复记录。安装及音域验收以 [MIDI范围适配](MIDI_RANGE_ADAPTATION_2026-10-31.md) 为准，板上旧范围必须随UI固件一起更新。

用户确认的故障阶段是“无法选文件，或选后没有反应”。旧0.2.0依赖 WebView `<input type=file>`→content URI→WebView File／Blob→FileReader，安卓文档提供者、MIME和WebView实现的兼容链较长；本机没有用户手机，不能把某个具体厂商的原因说成已复现。

本轮改为明确的“选择 MIDI”按钮，APK通过原生 `ACTION_OPEN_DOCUMENT`、`*/*` 打开文件选择器，`ContentResolver.openInputStream()` 在后台读取，不猜测content URI磁盘路径；读取中文显示名，验证4MiB上限及 MThd 头，再交给现有JS完整MIDI解析器。取消／权限或提供者错误／无Note曲谱都有可见提示，并清除旧选择，恢复按钮。传输中禁重复选择，防止显示曲名与正在上传的数据不一致。普通网页保留 FileReader 路径。

MIDI选择完成只做解析；仍需点击“发送到板卡”。显示曲名、时长、事件数，上传分包按真实ACK更新进度。蓝牙SPP连接／CRC／ACK协议未变。保留上一轮完整PCM缓存后导出WAV的修复，不再在下载前导出44B空壳；音频仍采UI板I²S输入，不用手机麦克风。

最终APK：`E:/gaoyun_builds/phone_apk_20261031_190934_716726/FPGA-Performance.apk`。

- versionName `0.2.1`，versionCode `3`，同一开发签名，可覆盖本项目旧APK。
- SHA256 `a0e1ba1e76eb679d2b888f88e111949094bcec5d61558a91d3f943c8cae09681`。
- `source_manifest.json` 记录打包输入；签名验证、badging及输入哈希检查留档。
- 尚未在真实安卓／HC-07上验收，不能以主机桥模拟替代实物结论。

## 6. 启动一致性、文件与验证

静态同步从40项扩展到74项，原40项顺序保留，之后追加34项。首次74项确实从UART排空后才释放原81帧LFO全同步；后续有变化按真实FIFO accept更新sent，拥塞中合并中间值但保留最新状态，Note优先和SysEx整帧仲裁保留。新增参数没有使用会丢单周期脉冲的旁路发送器。

主要文件：

- `rtl/ui_vector_engine/audio_controls_state.v`、`audio_controls_renderer.v`：触摸状态／菜单／五FX页／像素流水。
- `audio_extra_controls.vh`、`wavetable_catalog.vh`、`params.vh`：34内部ID及波表数量；两个gprj均纳入模块。
- `ui_top_renderer.v`：生产集成、D/R绑定坐标适配、SPI和触摸双写入口。
- `rtl/ui_touch_hub_top.v`、`rtl/midi_uart_tx/static_cc_sync.v`／`static_cc_slots.vh`／`midi_uart_tx.v`：74项状态同步及CC编码。
- `param_merger.v`／`button_vector_unit.v`／`osc_panel_renderer.v`：第5种SD波形枚举；`touch_event_router.v`保留footer触摸区。
- `knob_vector_unit.v`：PAN中心显示；`fx_editor_state.v`：独立触摸／实体参数同时写入。
- `MainActivity.java`／`MidiDocumentReader.java`、网页及manifest：原生选文件链路、0.2.1。

本轮验证记录（ModelSim快照位于各目录）：

- `E:/gaoyun_builds/six_fix_20261031_190843_983136`：21项主回归全部PASS，`workspace_matches_snapshot=true`。包括74项启动CC＋81帧LFO同步与真实音频parser/router、真实WARP/WTB/FX触摸及UART、PAN、FX实体/触摸并发仲裁、LFO绑定速率、ENV、MIDI Note/CC/SysEx、手机播放模式等。
- 真实UART回归：A/B全部24个Warp mode选择、A/B各10个bank选择、25个FX scalar与switch、PAN 0/64/127；74启动CC唯一有序，后续LFO不抢占Note。
- `tb_lfo_rate_renderer_uart`：三LFO各8档×Smooth/Stepped/Once全96组合PASS；2Hz=`F0 7D 45 00 03 F7`，4Hz=`F0 7D 45 00 04 F7`，Stepped 4Hz低值`0C`、Once 4Hz低值`14`，重启/Commit仍在。
- `tb_lfo_binding_realbaud`和`tb_lfo_renderer_uart`：31250 baud真实序列验证target6/13 source/depth，以及Note/CC/SysEx Commit仲裁PASS。
- `tb_audio_controls_pixels`：708,932个生产像素位置流水对齐；同页参数及路由动态更新、五效果页、Warp菜单、SD无预览状态PASS。预览文件 `fx_preview.png`、`warp_sd_preview.png` 已人工查看。
- `E:/gaoyun_builds/ui_elaboration_20261031_191130_204995`：normal/debug完整层次展开PASS，采用官方primitive模型及DDR stub；它不模拟DDR真实行为。
- `E:/gaoyun_builds/phone_selection_20261031_190854_127597`：Android原生选择器读取、MIDI解析/错误/取消、分包进度、WAV缓存与实际导出头及旧14项phone client回归PASS。`device_tested=false`。
- 最终APK已用相同本机开发签名生成并通过apksigner验证；APK和各自输入SHA在 `E:/gaoyun_builds/phone_apk_20261031_190934_716726/source_manifest.json`。

ModelSim像素预览是RTL实际渲染，不是手绘。以上测试不证明Gowin时序、真实SD装载、真实Android文档provider或HC-07实机行为；后续正式构建仍必须五类时序、7时钟、124引脚与source manifest全审计。

## 7. 交付与实机核对顺序

1. 安卓覆盖安装0.2.1，先不连蓝牙也应能选取本地MID，出现曲名／时长／事件数；取消和坏文件应给明确提示。
2. HC-07连接并HELLO后发送短曲，确认分包读条，试听由队友已修好的C19 Note接收配合。
3. 在本轮UI正式构建部署后逐项核对WARP Mode/Amount、SD 00～09、五类FX开关／参数和三路PAN0/C/127。
4. 保留现有I²S录音回传验收：先有录音帧，再下载进度，到完整导出后打开WAV。

给音频agent的详细未适配项及建议见 [AUDIO_AGENT_HANDOFF_2026-10-31.md](AUDIO_AGENT_HANDOFF_2026-10-31.md)。

