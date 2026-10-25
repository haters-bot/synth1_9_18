# UI Touch Hub 当前交接入口

## 2026-10-26 03:18：LFO SysEx V2 位流已烧录 SRAM，实屏黑屏待排查

- `b10e365` 已推送到 `origin/integration/dual-138k-uart-phase1`。最终候选 `impl/R16A_build_20261025_224744/` 已通过五类时序门禁，位流 SHA256 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`。
- 工程机重连后，`tools/deploy_verified.py --target sram` 在 `impl/deploy_runs/20261026_031805_LFO_SYSEX_V2_TIMING_CLOSED_RETRY/` 完成 100% SRAM 编程，`PROGRAMMER_EXIT=0`、状态码 `0x00026230`、远端哈希一致。Flash 未操作。
- 工程机摄像头调用成功并返回 `preview.jpg`/`telemetry.png`，但屏幕画面为全黑，因此当前只确认“位流已写入 SRAM”，不确认 UI 实屏运行。下一步先检查板卡复位/HDMI 链路和显示器输入，再决定是否需要重新部署；不要把黑屏当作 UI 验收通过。

## 2026-10-25 23:00：LFO SysEx 发送器时序已收口（Codex，待提交/部署）

- 在保留 ZCode 实现和协议文档的基础上，Codex 对 `constraints/ui_touch_hub.cst` 采用最小物理约束：`INS_LOC "u_render/u_navigation_render/ch1_0_s0" R35C151[0][A];`。尝试过的发射端/参数端锚点导致全局布局回归，已撤掉；没有降频、没有时序豁免。
- 最终候选 `impl/R16A_build_20261025_224744/`，审计 `audit_20261025_225837_331586.json`：setup/hold/recovery/removal/pulse 全部零违例，余量分别 `+0.171/+0.196/+0.100/+0.497/+0.453 ns`，`timing_closed=true`，位流 SHA256 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`。
- `tb_lfo_sysex_tx` 94 项全过，`tb_midi_uart_tx` 100% 全过。下一步是把工作区改动（含本条约束、协议文档、回归测试和协同日志）提交并推送集成分支，然后只用 `tools/deploy_verified.py --target sram` 烧录。Flash 继续暂停。
- 验收边界：音频板当前尚未实现 SysEx V2 接收/调制计算，因此烧录后 UI 画面应与 R17B_HD_FONT 一致，音频板暂时只会忽略这些未知 SysEx ID；不能把这次 UI 发送器上板称为音频调制已联调。

## 2026-10-25 20:45：LFO SysEx 发送器已实现（ZCode，未提交，时序门禁未过，待 Codex 收尾）

- 工作区未提交改动实现了 UI LFO 协议 V2（`docs/UI_LFO_MODULATION_PROTOCOL_V2.md` §7 全部四项）：新增 `rtl/midi_uart_tx/lfo_sysex_tx.v`（静默快照→diff→SysEx 流式发送→原子 commit，ID72 相位同步）；`midi_uart_tx.v` 增 sysex 注入端口（Note/CC 同拍优先、组合 accept 防双推）；顶层接线 `u_lfo_sysex`；gprj 已登记。
- 仿真证据：`sim/tb_lfo_sysex_tx.v` 94 项全过（全量 81 帧、点/路由/模式编辑、CC 抢占）；`tb_midi_uart_tx` 原回归 100%；全顶层 `-sv` 编译 0 错。命令：`cd sim && D:/altera/modelsim_ase/win32aloem/vsim.exe -c -do "vlog +incdir+../rtl/ui_vector_engine ../rtl/midi_uart_tx/*.v tb_lfo_sysex_tx.v; vsim work.tb_lfo_sysex_tx; run -all; quit -f"`。
- 时序：三轮构建收敛 setup −3.685→−2.933→**−0.056ns**，唯一剩余违例 `u_navigation_render/id0_5_s0→ch1_0_s0` 为既有路径被布局挤占（非 LFO 逻辑），Gowin 布局确定性重跑无效。**timing_closed=false，禁止烧录。**
- 给 Codex 的收尾建议：参照 `a276b9b`（serializer 复位 INS_LOC 先例）锚定上述两 FF；构建目录 `impl/R16A_build_20261025_202146`（=203946 同结果）含审计 JSON。改动未 commit（Mimosa 拦截与本次无关的历史脚本告警），`git diff` 可见全部。
- 详细过程与协议背景见 `docs/AI_COLLABORATION_LOG.md` 2026-10-25 两条目。Flash 暂停不变；本改动不影响 CC/Note 行为（回归已证）。

## 2026-10-25 19:28：高分辨率字体位流已由 ZCode 烧录上板（R17B_HD_FONT）

- 当前板上为 `impl/deploy_runs/20261025_192830_R17B_HD_FONT/`，即 Codex 构建审计的 `b8b7efd`（`navigation_font_hd.vh` 高分辨率导航字体，7×10 映射 12×16 框、标题 2× 放大、旧 4×6 保留回退）。位流 SHA256 `C82CFF39CFE71C53619A7706B918F3CDD58C0D9E1772795C12C3D5B5AA9E7EF`，双机哈希一致，GW5AST-138B/operation2 SRAM/23.06s/PROGRAMMER_EXIT=0，Flash 未动。
- 部署由 ZCode 按用户指令执行（synth1_9_18 侧 tools/deploy_verified.py；gaoyun 侧同名脚本对 b8b7efd 快照审计会报 navigation_font_hd.vh 缺失，勿用）。抓拍 `preview.jpg` 证明新位流运行；**高分辨率字体的实屏可读性与触控验收仍待用户确认**，完成前不设验收标签。
- 当日工程机网络间歇断连根因：ZeroTier 对端纯 RELAY 海外中继 + 工程机约 19:16 起疑似闲置睡眠失联，恢复后完成烧录。两次失败尝试均未触碰烧录，远端 D:/gaoyun_deploy/ 可能有残留半截 zip（无害）。详细记录见 `docs/AI_COLLABORATION_LOG.md` 2026-10-25 条目。

## 2026-10-20：R17导航页清晰度和设置扩展位候选（尚未上板）

- 用户已确认VISUALIZATION能切换，但另外两个页面文字小、发虚。当前工作区候选改为导航独立原生字形（正文约11×16、标题约15×22）并提高说明色；合成器原字体不改。
- 六窗增加标注为`EXAMPLE / NOT LIVE`的概念图：音符、波形、立体声相位、频谱柱、频谱热图、电平。真实Note/PCM/FFT尚未接入，不能将示意图写成实时数据。
- SYSTEM四栏目常驻显示并高亮：CONTROLS、DISPLAY、INPUTS、ABOUT。状态由`settings_section_id[7:0]`保存，当前ID1..4；切换不改变Macro、FX、LFO或页面状态。新增设置必须分配新ID并实现状态/触摸/标签。
- 仿真证据：`impl/navigation_20261020_223045/`（导航行为、设置切换、Macro保持、BIND取消）、`impl/video_alignment_20261020_223056_502124/`（6136项原视频对齐）、`impl/navigation_preview_20261020_222440/`（六张整帧，字体/示意图已查看）。尚未重新综合、时序审计或部署；Flash暂停。

## 2026-10-19 22:44：SSH恢复，R17实屏照片已补取

- 工程机SSH返回DESKTOP-FDEVSGP，摄像头抓拍成功，主力机证据 `impl/deploy_runs/20261019_222930_R17_six_windows/recheck_20261019_224344.jpg` 已查看：新MENU/SYNTHESIZER/VISUALIZATION/SYSTEM顶栏可见，合成器OSC/FILTER/ENV/FX/LFO布局完整。此照片仅证明当时合成器画面，不作为六窗或触摸验收。
- 未再次烧录；当前仍为222026构建。已请用户点VISUALIZATION确认3×2六窗，待回复，再验证返回控制台与触摸/绑定保持。Flash暂停。

## 2026-10-19 22:36：R17完整时序通过，SRAM烧录完成，待交互验收

- 当前板上已更新 `impl/R16A_build_20261019_222026/`，源码`df2d3b6`+`739922f`。像素实际50MHz/估算57.036MHz，setup/hold0/0；setup+0.622、hold+0.147、recovery+0.098、removal+0.497、pulse+0.453ns；三路复位覆盖、无豁免、55份输入哈希一致。审计`audit_20261019_222921_505893.json`。
- 位流SHA256 `7A425327D7D5B71B4775D90B5CD4C7FEEF52B2DA483DC08B409CC29A4829B5BE`。部署`impl/deploy_runs/20261019_222930_R17_six_windows/`因下载过慢触发本地240秒超时，远程继续完成；没有重烧，后续只读查询/留档确认operation2 SRAM、退出0、Finished、23.27秒、远程哈希匹配，证据`recovered_programmer.log`，原超时保留。照片补取进行中，页面/触摸尚待用户验收，不设用户验收标签。
- 六窗目前等待Note/PCM/FFT真实数据。导航、菜单、系统Macro±与诊断显隐已仿真通过；不称占位窗为实时分析。后续抓拍及存图缩略图回传均SSH超时，未取得本地实屏图，`capture_recovery_error.txt`留档；已向用户询问新导航显示情况，待回复后逐项实屏验收。旧已验收203742及回退标签保留，Flash暂停。

## 2026-10-19 22:23：R17首候选时序未通过，常量矩形并行优化后重建

- 221024候选像素Fmax45.403/50MHz、setup17项/最差−2.025ns，未部署；hold/recovery/removal/pulse通过也不代表整设计通过。关键路径是导航背景的变量坐标计算。失败审计和原位流均保留。
- 六窗口改常量矩形并行比较，未改时钟/时序例外/图层拍数。完整导航行为及三页七拍对齐再次通过；222016三张导航整帧与221113版逐像素完全相同，PNG已查看。
- 第二候选 `impl/R16A_build_20261019_222026/` 正在构建，待独立审计。22:19工程机SSH恢复、返回DESKTOP-FDEVSGP；板上仍203742已验收版，Flash暂停。详细证据见R17文档。

## 2026-10-19 22:14：R17六窗口/菜单/系统页仿真通过，首候选综合中

- 用户选择一屏六小窗（3列×2行），允许先占位。新增VISUALIZATION六框等待真实数据，未接PCM/Note/FFT。顶部改MENU/三页签/USB状态，Master保留，Macro1..4移系统页±控制，原通用HUD遮盖且屏蔽触摸；旧RTL和接口不删除。
- 切页在VSYNC上升沿提交，导航页触摸不穿透背景；参数、FX、LFO和已建绑定保持，切页仅取消临时BIND手势。系统诊断底栏/紫十字可显隐，默认隐藏。
- 完整顶层行为/真实参数库宏控制/三页七拍对齐通过；导航三整帧2764800像素无X且PNG查看；前轮曲线13746像素、视频6136、FX/LFO四组、正常/诊断编译回归通过。详细入口 `doc/R17_NAVIGATION_SIX_WINDOWS_2026-10-19.md`。
- 候选 `impl/R16A_build_20261019_221024/`正在布局，尚待审计/部署。工程机SSH预检超时，已请求检查。板上仍203742，Flash暂停，不删除旧文件。R17未实际音频可视化，不称假动画为实时分析。

## 2026-10-19 20:48：BIND 快速操作修复已上板，用户连续复测无卡住

- 当前板上为 `impl/R16A_build_20261019_203742/`，逻辑提交 `7ae2e78`、物理约束提交 `a276b9b`。普通/按钮接触50ms释放，仅活跃绑定拖动保留500ms宽限，允许BIND缺UP交接曲线。包含上一轮RES/OSC/ENV有效值曲线修复。
- 本候选完整审计通过：实际像素50MHz/估算Fmax58.983MHz，setup/hold0/0，最差setup+0.622、hold+0.156、recovery+0.100、removal+0.497、pulse+0.453ns；三路复位覆盖、无豁免、输入快照一致。首候选202225失败归档，未部署。
- 部署 `impl/deploy_runs/20261019_204532_R16_bind_contact_fixed/` 双机哈希匹配，位流SHA256 `F3CF9E3F2EBE6DD58CF2F0E175BA33B20DBF3648683167554DB1AA2AC9EB82A6`，GW5AST-138B/operation2 SRAM/PROGRAMMER_EXIT=0，22.82秒，照片回传查看。用户连续5～10次编辑/BIND/拖拽并操作FX后确认“连续操作正常，没有再卡住”。
- 详细根因复现、20轮联合回归、物理约束依据与边界：`doc/R16_BIND_CONTACT_FIX_2026-10-19.md`。上一验收版200320与标签保留，Flash暂停，未删文件，未推送新远程提交。

## 2026-10-19 20:38：BIND 首候选因最小脉宽拒绝，固定复位FF位置后重建

- `7ae2e78` 为BIND逻辑修复提交；202225候选setup/hold=0/0但pulse slack -0.346ns，审计明确失败，未部署。三路reset_pipe FF的250MHz时钟分布PTR3/PBR3，和200320已通过候选不同。
- 按本机官方SUG1018 §2.3 INS_LOC语法，把九个复位FF固定到200320 routed报告中的站点，未改逻辑、未加豁免、未降频。新候选 `impl/R16A_build_20261019_203742/` 正在综合；本候选通过前禁止烧录。详细失败与处理记录见 `doc/R16_BIND_CONTACT_FIX_2026-10-19.md`。
- 板上仍200320，Flash暂停。工程机20:24 SSH已确认在线。此记录覆盖下方“202225尚待审计”的旧进度。

## 2026-10-19 20:23：BIND 偶发无响应已仿真复现，修复候选构建中

- 用户补充LFO编辑后BIND偶发抓不起曲线，触摸操作失效但动态白色指示仍运动。旧绑定器把普通接触也保留500ms，漏UP时吞掉下一次按下；旧版新增测试先复现失败。
- 非拖动接触改50ms释放，仅拖动保留500ms瞄准宽限；BIND按钮无UP也可交接曲线拖动。四组绑定/FX/高亮/生命周期及连续20轮真实编辑器联合测试通过；前一轮13,746像素曲线同步、正常/诊断编译与日志回归通过。
- 新候选 `impl/R16A_build_20261019_202225/` 正在综合，尚未时序审计/部署。板上仍200320。证据及局限见 `doc/R16_BIND_CONTACT_FIX_2026-10-19.md`。不改USB解码、音频协议或时钟；Flash暂停。

## 2026-10-19 20:15：LFO 调制曲线修复已 SRAM 上板，用户确认 RES 曲线同步

- 修复 RTL 提交 `40d3cf0`。当前板上为 `impl/R16A_build_20261019_200320/`，取代192921；FILTER/OSC/ENV曲线与旋钮共用有效调制值，ENV命中显示位置但保持基础值相对编辑。
- 新候选审计通过：实际像素50MHz、估算Fmax57.657MHz，setup/hold违例0/0；最差setup+0.622、hold+0.204、recovery+0.098、removal+0.497、pulse+0.453ns，三路OSER10复位均覆盖、无豁免，源码快照一致。
- 部署 `impl/deploy_runs/20261019_201142_R16_scope_preview_fixed/`：双机哈希一致，位流SHA256 `09C82CEB4AA3FB7EEB8D064E9CD9D1543BF199877A875C000B0CE1B090CF5B44`，GW5AST-138B/operation2/PROGRAMMER_EXIT=0，照片回传并查看。用户对RES绑定LFO实测明确回复“曲线已同步变化”。
- 验收范围仅明确覆盖本次RES实屏故障；OSC/ENV同类修复和动画白点编辑为仿真验证。完整记录 `doc/R16_SCOPE_MODULATION_FIX_2026-10-19.md`。上一已验收版192921与标签继续保留用于回退。Flash仍暂停；音频实际调制未接入，不把UI动画当作声音验收。

## 2026-10-19 20:04：修复 LFO 旋钮与曲线参数源不一致，等待新候选审计

- 用户确认手动 FILTER RES 会改变曲线，LFO 调制时曲线不动。已定位曲线层读取基础值、旋钮读取有效值。FILTER/OSC/ENV 曲线统一读取 mod_preview；ENV 用独立显示几何命中移动白点，保持基础值相对编辑。
- 13,746 次实际绑定/正负深度/解除/基础值隔离像素比较、原有触控/UART、6,136 次视频对齐、正常/诊断顶层编译及新增移动 ENV 命中专项均通过。详见 `doc/R16_SCOPE_MODULATION_FIX_2026-10-19.md`。
- 新候选 `impl/R16A_build_20261019_200320/` 正在综合，尚未审计、尚未部署。板上仍为192921已验收版。Flash暂停，不触碰E盘，不删除旧档案；音频LFO仍未接入，不声称声音已变化。

## 2026-10-19 19:50：本轮验收归档与盘符恢复完成

- 用户已更正最后一项为“选错了，都正常”：REVERB SIZE/EQ GAIN/ENV切页与节点跟手且画面正常。此前已确认DELAY MIX正常、LFO2整曲线绑定后L2+AMOUNT存在、调低深度后数值/动态范围/标记均正常。完整证据与接口边界在 `doc/R16_BOARD_ACCEPTANCE_2026-10-19.md`。
- 本地验收标签 `verified/ui-R16A-20261019` 指向 `5b09337`，RTL为 `9d761aa`，后续仅文档更新；未推送新的远程提交。当前部署192921源快照与RTL一致，所有时序门禁通过，Flash暂停。
- **替代下方E盘待清理历史**：用户明确说“E那个是我删掉的”；实际E:/gaoyun_builds不存在。D盘已核验的76文件旧档案通过同盘重命名恢复原路径 `impl/R16A_build_20261019_181815`（实目录，非junction）。旧失效junction保留为 `impl/R16A_build_20261019_181815_stale_E_junction`，不含独立档案；未删除此记录。中断构建185328的63文件备份仍在D盘。后续工作不依赖E盘，不声称代理完成了E盘删除。

- **当前验收报告**：[R16板上状态与接口/回退/E盘未清理项](doc/R16_BOARD_ACCEPTANCE_2026-10-19.md)。后续工作优先读本条与下节，下面未收敛/待验收描述均为历史。当前R16只在SRAM，Flash暂停；用户已亲自清理E盘，旧构建恢复到D盘真实目录，详见下条。

## 2026-10-19 19:40–19:48：绑定修正版已 SRAM 部署并完成主要交互验收

- 当前板上为 `impl/R16A_build_20261019_192921`，RTL提交 `9d761aa`。审计 `audit_20261019_193823_970785.json`：像素估算Fmax59.438MHz/实际50MHz，setup0/hold0；setup+0.590、hold+0.147、recovery+0.201、removal+0.506、pulse+0.450ns，全部三路复位覆盖、无OSER10 RESET豁免，源码/快照哈希均匹配。
- 位流35926701字节，SHA256 `9C758B67F235139D522D1185489A76B8431147A5EA21A0F036801A4FCD165522`。部署 `impl/deploy_runs/20261019_193852_R16_binding_release_fixed/` 双机哈希匹配，Programmer operation2 SRAM、识别GW5AST-138B、Finished/PROGRAMMER_EXIT=0，完成耗时22.78秒，照片已回传查看。Flash未操作。
- 用户已复测明确确认“L2高亮和AMOUNT都出现”；随后点−降低深度，确认“数值、动态范围和标记都正常”。修正版整曲线分配、持续标记、深度及动态预览已获得实机操作证据。`impl/R16_binding_verified_20261019_194232/preview.jpg` 保存后续现场照片。
- 上一板上候选190726的DELAY MIX已由用户确认跟手/画面正常，但其绑定未提交；用户已补测新候选REVERB SIZE/EQ GAIN/原ENV页签和节点，并将误选“异常”更正为“选错了，都正常”，验收通过。点击替代入口/外部FX旋钮接口在仿真已通过，实际队友硬件还未接入，不能宣称已跨板联调。

## 2026-10-19 19:30：R16 已上板，FX 验收通过；修正 LFO 缺失 UP 提交

- `impl/R16A_build_20261019_190726/` 真实时序闭合：pixel Fmax55.120/50MHz；setup0/hold0；最差setup+0.588、hold+0.192、recovery+0.199、removal+0.387、pulse+0.460ns，三路OSER10复位均在报告中且无豁免。审计 `audit_20261019_191640_547268.json`，位流35882497字节，SHA256 `7A195D32821EC7E812A078379E3344306E54118AFB59B331161BC3D98A49FB7B`。
- `impl/deploy_runs/20261019_191654_R16_pipeline_verified/` 远程operation2 SRAM完成，识别GW5AST-138B，PROGRAMMER_EXIT=0，双机哈希匹配，抓拍确认R16A及FX三栏正常，证明该屏当时接受50MHz/约40.404Hz。未写Flash；没有通过静态照片宣称长期无闪烁。
- 用户明确验收DELAY MIX“跟手，画面正常”。LFO用户反馈“能绑定但L2标记缺失”，继续确认底部仍是UI PREVIEW，说明没有提交。19:29抓拍 `impl/R16_binding_observe_20261019_192900/preview.jpg` 显示BIND模式仍亮、无AMOUNT。推断缺失UP/50ms取消与该现象一致，未捕获真实HID序列，不能写成已证明根因。
- `lfo_binding_state` 静默宽限改500ms（50MHz下25000000拍、25bit计数），到期沿用显式UP提交最后有效hover，不再静默丢弃；有效新报文优先，迟到UP不会重复提交，无效最后落点仍取消。兼容用户允许的BIND后直接点目标，按下即绑定且capture该接触防止基础旋钮变值，拖整曲线仍保留。
- 新 `sim/tb_lfo_binding_release.v` 将宽限缩为1000拍进行可观测生命周期检查，覆盖接近超时的停顿、移动最终目标、缺UP、迟到UP去重、无效落点、正常UP、点击替代，以及FSM真实sources驱动overlay持续彩色标记。`fx_lfo_tests_20261019_192835_494813` 三组全部通过；对齐 `video_alignment_20261019_192932_148400` 6136项通过。
- 完整最终入口/HUD预览 `impl/ui_preview_20261019_190937_R16_final_event_pipeline/frame.png` 已完成，所有frame/geometry/LFO/caption检查通过。新绑定生命周期逻辑不改像素流水。
- 新修正版构建 `impl/R16A_build_20261019_192921/`，会话5981，正在运行；必须重新审计后才部署，不使用190726通过结论替代。板上当前仍是190726（旧50ms绑定逻辑），用户交互后各参数会变化。
- 19:21连续抓拍第一次SSH超时，之后ping约350ms与单独抓拍成功。`impl/R16_stability_20261019_192057/` 未取得有效序列，不能作为稳定性证据。

## 2026-10-19 19:10：恢复 D 盘构建，控制/光栅流水回归已通过

- 用户暂停后已明确要求继续，后续产物只写本工程 D 盘 impl；Flash 继续暂停，板卡仍是 R15I。18:48 SSH、USB FTDI 双通道/COM5/COM6及摄像头抓拍通过，证据 `impl/connection_20261019_184802/`。
- 182721 最终审计：pixel 43.495/50 MHz、setup25、hold0，reset recovery+0.201/removal+0.491ns；183647：46.656/50 MHz、setup10、hold0，reset recovery+0.315/removal+0.267ns。两者均禁止部署；复位已按真实 recovery/removal 报告覆盖三路，不恢复旧 false-path。
- 光栅入口十份保留坐标副本，外部视频总延迟七拍；参数库全部输入事件整体寄存一拍，HUD选中ID本地寄存，阻断 selected ID 跨模块共享译码。此前脚本批量替换误将两个子模块端口也改名，已恢复 `.selected_param_id(hud_selected_id)`，完整正常/诊断顶层编译通过。
- 当前回归：`curve_tests_20261019_185144` 完整通过，包括 FILTER/ENV、128值几何、参数事件连续吞吐/ID值配对/无重复/同拍按钮>SPI>触摸；`fx_lfo_tests_20261019_184950_032168` 通过53目标/三来源/19 FX旋钮/九开关/持续标记/候选/缩略图；`video_alignment_20261019_185144_136003` 6136项通过；`trace_tests_20261019_185144_167186` 正常与诊断顶层编译及UART回归通过。旧参数测试台改为下降沿刺激/检查，补齐空闲输入，保留原参数断言。
- 完整预览 `impl/ui_preview_20261019_183647_R16_raster_distribution_actual/frame.png` 已生成并查看，921600像素无X、110305旋钮几何、921600节点、49280插值及caption像素通过，画面含中央FX、压缩ENV、L1/L2绑定标记。该预览编译于18:36，最终控制事件/HUD入口寄存改动随后通过上面的对齐/控制回归，不能把仿真图当作板卡画面。
- 18:53 D盘满时曾将旧档案迁至 `E:/gaoyun_builds/preserved_R16A_build_20261019_181815` 并在D盘原位置建junction；E盘新构建 `R16A_build_20261019_185328` 后进程退出但未生成时序/位流，running状态文件已过期。部署脚本曾因磁盘写满截断，已从本地HEAD完整恢复。
- 用户要求清理E盘新增目录。自动审批拒绝了迁回/移除junction的命令，原因仅 `blocked by policy`；原位恢复未执行。已将旧档案复制到 `impl/R16A_build_20261019_181815_restored`（76文件），E盘中断构建复制到 `impl/R16A_build_20261019_185328`（63文件），所有文件逐一SHA256核对一致。**E盘两目录尚未删除，D盘181815仍为指向E盘的junction**，不得声称清理完成；后续清理须注意已核验的D盘restored副本。后续构建/部署脚本已恢复只在D盘默认写产物，没有E盘默认路径。
- D盘经用户清理后实际约2.8GB可用。当前新隔离构建 `impl/R16A_build_20261019_190726`（会话83520），先读取进程/日志，结束后运行audit；严禁未通过审计就烧录，50MHz/1650/750约40.404Hz兼容性待实机核验。

## 2026-10-19 18:30：撤销旧闭合结论，修正复位审计后继续 SRAM 上板

- **优先级高于下方14:01记录**：135450候选对三路OSER10 RESET使用false-path，屏蔽了recovery/removal，不能据setup/hold为0声称复位稳定；部署脚本现已拒绝该候选。其50.120 MHz是STA估算Fmax，实际PLL输出50 MHz，setup仅0.048 ns，不能说有充分余量。保留原档案，不覆盖、不删除。
- 50 MHz / (1650×750)=40.404 Hz；保持1280×720画布，屏幕是否接受此非标准刷新尚待上板摄像头验证，不能提前写“稳定输出”。Flash继续暂停。
- 已读取本机Gowin官方UG304-1.3.2E §4.3.5/表4-37（正文105页）：RESET是高有效异步复位；SUG940-2.0E §5.4.1（正文69页）：false-path默认同时排除setup/hold/recovery/removal。来源在`D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/doc/EN/`，没有假称查到厂家认可的复位豁免。
- PHY改为每路本地、保留实例的复位同步链，异步源来自外部复位和两个PLL锁定；编码器仍使用像素域系统复位。OSER10 RESET不加false-path。181815候选：像素49.813/50 MHz、setup1、hold3；recovery+0.656 ns、removal−0.404 ns，明确拒绝部署。removal来自FCLK上升沿与PCLK上升沿重合，最新改为两级上升沿同步、末级下降沿释放，候选`impl/R16A_build_20261019_182721/`正在完整P&R，结果未定。
- LFO首级文字译码改为固定矩形并行选择：与135450参考1855562输出像素逐位相等；Gowin真实OSER10模型通过20次非边沿复位/停钟恢复、80项检查。新增曲线提示文字并行选择，扩展像素等价测试运行中，不能拿旧结果替代新测试。
- `tools/audit_build.py`现检查setup/hold/recovery/removal/脉宽报告、三路OSER10复位端点覆盖、位流完整性、源码快照hash和复位例外。`tools/deploy_verified.py`在远程写入前实时重读隔离构建审计，历史JSON通过标记不能绕过。
- 最新已通过：视频/同步6136、FX/LFO53路目标/三来源/持续标记与拖拽、compact ENV五点/串行MIDI。`test_compact_env.py`原脚本把已经压缩的testbench坐标再次缩半而误报；修正重复迁移后通过，未放宽参数断言。新增实际50MHz时钟/31250 baud串口解码，Note On与Filter CC通过，不仅验证加速串口。
- 工程机SSH和摄像头现已恢复，18:22只读硬件取帧证据`impl/connection_20261019_182245/preview.jpg`确认仍为R15I。没有新候选写入SRAM，没有任何Flash操作。
- 本轮目标仍为FX三栏触屏/预留接口、LFO平滑曲线/按钮后拖整曲线分配/持久标记/深度/动态预览，以及六页可视化规划。第二期规划已在`doc/VISUALIZATION_PHASE2_PLAN.md`，不把示意数据接入实屏，不改队友音频实现；实机操作验收尚未完成。
- 18:31最终复位/文字专项：`impl/clock_reset_tests_20261019_183022_343033/`通过2101322个LFO/提示文字输出像素、全部提示行/三个ENV页签/12组LFO状态，以及下降沿释放下的80项真实OSER10模型复位检查；视频对齐`video_alignment_20261019_182828_131832`通过6136项。18:28专项曾因新增刺激循环误放在检查进程中而打印0项像素的无效PASS，该结果不可采信；脚本已修正进程并增加至少2100000项的覆盖断言，以18:31结果为准。
- `midi_50mhz_tests_20261019_182533_110677`通过物理50MHz/31250 baud的6字节Note On/CC解码。部署负向测试确认135450在创建部署目录/HTTP服务/SSH之前即被拒绝。181815审计确实覆盖全部三路OSER10 recovery/removal，脉宽最差+0.454 ns，但其setup/removal失败，继续保留为拒绝样本。

## 2026-10-19 14:01：R16 50 MHz 时序闭合，待工程机恢复网络后 SRAM 部署

> 历史结论已由18:30记录修正：以下135450位流禁止按原重试命令部署；旧审计不足以证明复位可靠。

- 结论：62.5 MHz 不是本项目 720p 输出的硬性要求。当前 `1650x750` 视频时序在 50 MHz 下仍可稳定输出；62.5 MHz 只是原先 PLL/5x TMDS 配置采用的目标值。R16 UI 组合渲染在 62.5 MHz 下多次只能达到约 56–58 MHz，setup 违例随 P&R 波动，不能作为稳定上板目标。
- 当前架构已改为 `clk_pixel=50 MHz`、`clk_5x_bit=250 MHz`，触控 UART、MIDI 分频及相关 watchdog/预览计时均按 50 MHz 重算；UI、FX/LFO、触控拖动逻辑未回退。
- 关键回归通过：视频对齐 6136 次、FX/LFO 控制 53 路目标与三 LFO、像素细节 2870 glyph/327680 混色、FX 像素 470764 次。
- 可部署候选：`impl/R16A_build_20261019_135450/`。审计 `audit_20261019_140114_336856.json`：`clk_pixel=50.120 MHz`、setup `0`、hold `0`、bitstream 完整；位流 35,649,623 bytes，SHA256 `F347494F2AF386914B939D09EDE36B74A493CEBA5E4ADE5258F49DA7A1B63DBB`。
- DVI 复位处理：OSER10 的 `RESET` 直接使用异步初始化复位；两个 SDC 对三路 OSER10 RESET 端点加 false-path，仅排除异步复位端点，不屏蔽像素数据路径。该约束语法已被 Gowin 接受并完成 P&R。
- SRAM 部署已发起但未执行：`impl/deploy_runs/20261019_140150_R16_50MHz_sram/manifest.json` 记录远程 SSH 到 `10.136.125.157:22` 超时，当前 `programming_status=not_confirmed`。随后 ping 与 TCP 22 均超时，说明工程机/ZeroTier 当前不可达；不要把这次记录当作已烧录。
- 待网络恢复后，使用已保存位流执行：`python tools/deploy_verified.py --label R16_50MHz_sram_retry --target sram --fs impl/R16A_build_20261019_135450/impl/pnr/2_ui_touch_hub.fs`。禁止改用 `external-flash`。

## 2026-10-19 03:02 新候选结果

- 完整帧 `impl/ui_preview_20261019_023105_R16F_lfo_caption_pipeline_fix/frame.png` 已完成；日志 PASS：完整无未知像素、110305旋钮几何、921600节点、49280 LFO插值。已人工查看，中央 FX/ENV/LFO 和 LFO 标题正常。
- `R16A_build_20261019_023206`：57.688 MHz、177 Setup、0 Hold，审计 `audit_20261019_024501_453232.json`，位流不可部署。
- 对旋钮首级译码按四个不重叠 Y 区域分组，3,686,407 次旋钮全帧像素对照通过；`R16A_build_20261019_024929` 的审计 `audit_20261019_030200_892001.json` 为57.622 MHz、116 Setup、0 Hold。违例明显下降但Fmax略回落，仍不部署。最新最差路径转到按钮边框/元素译码及旋钮值选择。
- 该分组译码源码待随本记录提交；部署/Flash仍暂停，板卡未烧录。

## 2026-10-19 03:03 全帧与路径转移

- 上述R16F整帧已通过并人工查看，ModelSim记录在 `ui_preview_20261019_023105_R16F_lfo_caption_pipeline_fix`。
- `R16A_build_20261019_024929` 已完成，审计见 `audit_20261019_030200_892001.json`：57.622 MHz、116 Setup、0 Hold；输入快照及工作区一致，仍不可部署。实际报告中最差路径转到 `u_timing/reg_pixel_y_2_s0 -> u_render/u_buttons/s0_border_s0`，其次是按钮元素译码以及旋钮参数选择。
- 需要下一步对 button 第一级区域/元素命中逻辑按固定 Y 区域并行化；不能假设旋钮分组已解决整体像素时序。

## 2026-10-19 02:38 后续时序优化

- `R16A_build_20261019_014632` 审计 `audit_20261019_015610_828795.json`：Pixel 58.207/62.5 MHz、137 Setup、0 Hold，工作区/快照一致。对比 01:39 的 56.834/482，拆开 FX 命中提交和 LFO 目标编码后有明确改善，但未达标。
- 下一版 `R16A_build_20261019_020202`：Pixel 56.812 MHz、112 Setup、0 Hold，最差路径到 LFO 字符译码，性能回退。为处理路径，先把 LFO 节点页签选择明确化；ENV 端点缩放前置；FX 标题译码分段；overlay 颜色合并分阶段。FX 470764像素对照、旋钮3686407、OSC7372807、字体覆盖率、LFO表15400 bit-exact、视频对齐、FX/LFO控制回归通过。详见当次审计 `audit_20261019_021107_440908.json`。
- LFO 字符路径进一步拆成 label/origin 寄存与 glyph lookup；HUD 3x5 glyph 缓存；为 LFO/FX strip/modulation overlay 的本地坐标寄存器保留实例、限制扇出。**候选 `R16A_build_20261019_023206` 已启动，当前布局布线，尚无时序结论**。完整帧 `ui_preview_20261019_023105_R16F_lfo_caption_pipeline_fix` 正在 ModelSim，目前进度见其 `simulation.log`。
- 新版控制回归通过 `fx_lfo_tests_20261019_023206_479114`、`lfo_tests_20261019_023206`；FX逐像素470764、视频对齐6136、旋钮3686407、OSC7372807、曲线表15400 bit-exact对照、像素字体/混色327680等已通过。待收取完整帧和R16F P&R 后更新结论。
- 本地已提交控制命中拆级 `aa1fcb7`；后续像素/扇出修改待第二次审计后单独提交。工程机 SSH 01:48 成功，但无新烧录；Flash仍暂停，板卡最后已知 R15I。

## 后续实施（2026-10-19 01:46：控制命中拆级）

- FX命中和开关ID先寄存，状态提交使用同拍延迟的坐标/valid/down；外部事件同步延迟以保持与触控的仲裁关系。绑定的53目标先并行寄存命中位，再编码，来源页签与报文一起延迟。流水中BIND/工具按下预先占用手势。
- 新增连续每拍报文回归：BIND/UP/graph/target/UP、来源页签变化、FX按下/移动/松手、外部输入与触控同拍。`fx_lfo_tests_20261019_014611_832027` 两组全通过；`video_alignment_20261019_014632_359853` 6136次通过。
- 新独立构建 `impl/R16A_build_20261019_014632/`，会话25846，已启动但时序结果未知；先收取结果，不重复构建。上一候选仍不达标，无烧录。
- 完整帧 `impl/ui_preview_20261019_012944_R16D_split_blends/frame.png` 已完成且人工查看：110305旋钮几何、921600节点、49280插值及最终caption像素检查通过。对应四级knob/OSC渲染；本轮控制译码改动不改变渲染流水。
- `curve_tests_20261019_014711` 三组通过；`trace_tests_20261019_014749_992257` 编译/串口/解码与损失报告通过（测试主动制造的FIFO丢弃为15，不是实机丢包测量）。01:48 SSH再次成功，工程机返回 `DESKTOP-FDEVSGP`；未调用烧录器。

## 最新核实（2026-10-19：01:39 构建审计结果）

- `impl/R16A_build_20261019_012934/` 已完成，不再是构建运行中。审计 `audit_20261019_013920_558224.json`：Pixel **56.834 / 62.5 MHz**，Setup **482**、Hold **0**，最差 Slack **-1.595 ns**；工作区及快照 hash 无 mismatch。时序未收敛，禁止部署此候选。
- 最差路径为 `u_touch_router/s0_tx_5_s0 -> u_render/u_fx_state/switches_3_s1`；绑定目标译码也在最差路径前列，后续计划拆分触控命中译码与状态提交。显示 overlay、knob、HUD 等路径仍有违例，不能声称只剩触控路径。
- 位流 SHA256：`1F7495CA27B468B349E16D8BCC3FA08914A9D4416B23BB21883384220C94378A`。本轮未烧录，最后已知板上版本仍为 R15I；Flash 继续暂停。
- 本次收取会话 `14087` 仍在运行；`ui_preview_20261019_012944_R16D_split_blends/simulation.log` 最新明确进度为 **480 / 720 行**，尚无完整帧通过结论，不重复启动。

## 最新继续入口（2026-10-19 01:30：R16D 混色流水验证）

- 上一轮已保存本地提交 `cfdcebb`，不含用户 `tools/deploy_verified.py` 修改；当前还有下面列出的后续未提交修改。目标 active，未烧录，Flash 暂停，未远程推送。
- `R16A_build_20261019_011349` 已审计：Pixel **56.864 MHz / 62.5 MHz**，Setup **549**、Hold 0，最差 Slack **-1.586 ns**，快照/工作区当时一致；审计 `audit_20261019_012309_767977.json`。Fmax 有改善但违例总数增加，仍禁止部署。位流 SHA256 `13B8826201794796158D6C9F47B14E0FC2749AD822F7C508B717EE98DD9BFA50`。
- 根据新最差路径，把 OSC 和 knob 的覆盖率/字形查表与 RGB 混色拆开：二者从三拍改四拍，与 ENV 同样在第 5 拍合成，外部总视频流水仍为六级。合成保留 diagnostic/hint/LFO/button > knob > HUD > OSC > FILTER > ENV 的优先级。
- 新 `tools/test_osc_pixels.py` 对照固定 `542cdeb`，8 帧覆盖四波形及 power/morph，`osc_pixel_tests_20261019_012606_549224` **7372807** 次精确比较通过。旋钮参考端延迟一拍，`knob_pixel_tests_20261019_012616_596422` **3686407** 次通过；测试先等待流水填充，未跳过有效图形范围。
- LFO 预览各 bank 阈值并行比较，保留 32 位下溢语义，避免 active_tab 到宽移位/减法/比较；`lfo_tests_20261019_012717` 通过。缩略表读取提前一拍寄存，与局部坐标对齐；`fx_lfo_tests_20261019_012828_300217` 两组全部通过，含持续标记/候选/缩略图。
- 当前新构建 `impl/R16A_build_20261019_012934/`、新完整帧标签 `R16D_split_blends` 在运行，须先核实进程/日志；不可拿前一帧或前一时序代替。`R16C_aligned_geometry/frame.png` 是上一流水版本的已验证完整帧。

## 后续进展（2026-10-19 01:16）

- `R16A_build_20261019_005905` 审计已完成：Pixel 54.436 MHz / 62.5 MHz，Setup 342、Hold 0，最差 Slack -2.370 ns；文件 hash 一致。**仍不合格，不部署**。审计 `audit_20261019_010811_072194.json`，位流 SHA256 `27F4BDF123EF3D51D47425C937388C2B5A407B804F821C31FB035F7233535F71`。
- 完整帧 `impl/ui_preview_20261019_005915_R16C_aligned_geometry/frame.png` 已生成、通过脚本与人工视觉检查：110305 个旋钮几何、921600 个节点判定、49280 个 LFO 插值检查；最终 caption 像素也通过。此前“半帧”记录不能代替本结果。此图对应 00:59 源码；后续按钮求色改动有固定版本四帧等价比较。
- 后续将按钮颜色计算按 43 个固定元素并行展开。`button_pixel_tests_20261019_010955_377152` 四种按钮状态、3686403 次精确比较通过。对照工具已固定基线为 `542cdeb`，不随未来 HEAD 变化。
- 根据本机官方 `SUG550-2.0.1E_GowinSynthesis User Guide.pdf` 第 47-50、55-57 印刷页（PDF 55-58、63-65 页），对按钮/旋钮及合成器的局部坐标寄存器设置 `syn_preserve=1 syn_maxfan=32`，避免合并后的跨图层高扇出；不改 SDC/PLL。`video_alignment_20261019_011339_130458` 6136 次检查通过。
- 当前新候选 `impl/R16A_build_20261019_011349/` 正在综合/P&R，尚无最终时序结论。恢复工作时先核对实际构建状态。
- 曲线测试又加强为独立整数公式提供坐标，避免用 DUT 内部寄存器生成期望；Attack=61、Hold=127、Decay=104、Sustain=122/90/122、Release=127 等精确断言。`curve_tests_20261019_010302` 全部三组通过。
- 工程机 SSH 首次超时，之后固定 `.235` 源地址、8 秒连接超时重试成功，主机名 `DESKTOP-FDEVSGP`。没有烧录或改变板卡配置。当前已知的连接成功不代表后续始终可用。

## 最新继续入口（2026-10-19 01:00：R16C 验证与时序）

- 目标未完成，尚未部署 R16。Flash 仍暂停，不改拨码；部署前必须审计时序。
- `impl/R16A_build_20261019_003236/` 已完成但不合格：Pixel 54.053 MHz / 62.5 MHz，Setup 594、Hold 0；审计 `audit_20261019_004018_410678.json`。源码快照与工作区当时一致，位流不得部署。
- 新候选 `impl/R16A_build_20261019_005905/` 正在构建；对应完整画面 `impl/ui_preview_20261019_005915_R16C_aligned_geometry/` 正在仿真。继续时先核查实际会话/进程与日志，不能凭本条把任务当成仍运行或已结束。
- 修正了 ENV 新流水级的合成位置：旧图层 3 级，ENV 4 级，基础合成统一到 5 级，与 FX/调制图层对齐，输出为第 6 级。旧的 2039 次视频回归没有充分覆盖基础/ENV 边界，不能据此证明全面对齐；加强后的 `impl/video_alignment_20261019_005736_730262/` 通过 6136 次检查，含 20 处静止基准与连续跳坐标比较。
- 旋钮改为互斥单元并行译码和 6 位局部距离；按钮电源/箭头改局部 5 位坐标。`knob_pixel_tests_20261019_005518_790114` 与 HEAD 四帧逐像素对比 3686403 次通过；按钮 `button_pixel_tests_20261019_005736_725851` 全帧 921603 次通过。
- `curve_tests_20261019_003158` 三组全部通过。测试随缩窄后的 ENV 更新为 65/30/80 像素量程，并使用随参数变化的节点位置；包含真实 UART MIDI、独立 ENV bank 和滤波曲线操作。
- `fx_lfo_tests_20261019_005925_825479` 两组通过：53 个路由目标、19 个 FX 参数、三 LFO、深度/清除、来源色/L1-L3 标记/候选/拖拽缩略图；`fx_pixel_tests_20261019_004230_722461` 470764 次比较通过；`pixel_tests_20261019_004224` 通过。
- 本轮改动未提交；保留用户 `tools/deploy_verified.py` 原有改动及未跟踪文件，不删除历史产物。记录中的“板上 R15I”是最后一次已知部署状态，当前未重新抓拍核实。

## 当前继续工作入口（2026-10-18 23:34：FX / LFO 时序收敛中）

- 用户要求持续完成今晚目标，工作尚未完成。最新连续记录在[夜间实施记录](doc/CODEX_NIGHT_CONTINUATION_2026-10-18.md)。局部坐标预寄存后，FX和调制标记为五拍图层；基础图层、HSYNC/VSYNC/DEN已匹配延迟。触控坐标标定、PLL/SDC和Flash暂停指示均未改变。
- 最新候选为`impl/R16A_build_20261018_232618/`，尚在P&R；对应整帧验证`impl/ui_preview_20261018_232618_R16B_local_geometry/`运行中。没有上板，板上仍为普通R15I。
- 本轮专项回归：`fx_lfo_tests_20261018_232548_461398` PASS（含全部53个目标高亮/编号/清除）；`fx_pixel_tests_20261018_232618_605557` PASS（470764次精确比较）；`video_alignment_20261018_233348_282099` PASS（2039次连续像素和HSYNC/VSYNC/DEN核验）。这些不能代替P&R时序和实屏验证。
- 新增`tools/audit_build.py`检查实际时序报告、输入快照一致性及位流哈希；`tools/build_isolated.py`后续保存构建PID/退出状态，避免把仍在运行的构建当作失败并启动重复任务。

## 前一阶段记录（2026-10-18 晚：R16A FX / LFO）

- **此前阶段状态：软件功能/接口与RTL仿真已实现；R16A时序未闭合，未上板。板上仍为普通R15I。** 源码 `dc16e6a`，候选 `impl/R16A_build_20261018_224623/` 已完成P&R和位流：49.468 MHz / 目标62.5 MHz，1467个Setup违例端点，最差Slack−4.215 ns，Hold违例0。禁止把该位流当成稳定版本部署。详见目录 `final_audit.json`。实屏验收项目见[待执行验收表](doc/R16A_MANUAL_ACCEPTANCE.md)。

- 用户已确认：缩窄 ENV，中央常驻 DELAY / REVERB / EQ；本轮实现触屏、参数和旋钮/音频逻辑接口，声音由音频队友接入。
- LFO 使用专用 BIND 按钮进入模式，再拖整条曲线到旋钮、松手提交。已绑定目标持续显示来源颜色与 L1/L2/L3；白色候选标记与持续标记分开。三组七节点平滑曲线、深度正负调整和清除均已实现。
- 主要记录：[工作与构建证据](doc/CODEX_FX_LFO_VISUAL_PLAN_2026-10-18.md)、[FX/LFO 接口和限制](doc/FX_LFO_INTERFACE_R16.md)、[第二期六页可视化建议](doc/VISUALIZATION_PHASE2_PLAN.md)。实际声音调制、键盘 Note On 同步、物理旋钮新协议仍待协同；不可声称已经对接。
- 功能初版提交 `9c83d2c`，共享乘法/标记路径优化提交 `f99d1cd`，FX文字优化提交 `d794cd1`，曲线系数流水提交 `9535144`，命中并行化提交 `f0a17bf`，四拍图层对齐提交 `ad2ff45`。后续 `dc16e6a`预解码触控包文并寄存缩略图边界，但最终P&R回退，不能说每次优化都改善时序。下一步先解决像素坐标到mark_rgb的长路径，保持当前PLL/触控标定与硬件画面。
- 截至该记录，板上仍是已验收普通 R15I。沿用用户暂停 Flash 的指示，仅在检查候选后考虑 SRAM；不修改拨码、不重试 Flash。最终部署结果以工作记录的后续条目为准。
- 已重新核实免密 SSH、COM5/6、摄像头真实取帧和远程只读 JTAG 扫描（ID 0x0001081B）。没有删除历史固件、原图或旧验证目录。

## 追加记录（2026-10-18：ENV 点位与掉电启动 Flash）

- ENV 图中从左往右数、包含最左端起点时，第三个白点为 HOLD 手柄，参数只代表峰值平台的保持时间，因此只允许水平拖动。右侧下降段终点可调 DECAY 时间与 SUSTAIN 高度；最右侧平台点只调 SUSTAIN。`sim/tb_curve_touch_editor.v` 新增 DECAY 手柄垂直调节 Sustain 并还原的断言，`python tools/test_curve_editor.py` 已通过。
- GitHub 团队仓库 `haters-bot/synth1_9_18` 的 `ui-touch-hub-v1.0` 分支已包含本地源码提交 `a2b6e6c` 的诊断版本；共享提交 `bee0a80` 加入本记录和 ENV Sustain 纵向拖动回归，`5a97181` 更新了共享版本记录。草稿 PR #1 已存在，未合并主分支。此分支已有诊断 UART 扩展。
- 工程机曾以只读操作 51 识别外部 Flash ID `0x0B4018`。Sipeed 官方 [Tang Mega 138K Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html) 列出单颗 128/64 Mbit Flash，并建议使用 GAO-Bridge 5A（V1.9.11.03+）或 Arora V（V1.9.12+）；DIP 参考位置为 DIP1 与 DIP6 ON、DIP2–5 OFF。后续外 Flash 操作失败与当前状态见下方“暂停外 Flash，恢复 R15I 画面”记录。
- 掉电启动候选固件：普通 R15I 保留 U15 MIDI 31250、不带诊断日志；U15 诊断版输出 115200 日志并暂停 U15 对外 MIDI。不要把两种用途混淆。Flash 擦写会替换非易失配置，待用户确认要将哪种版本作为默认启动镜像、且按官方图确认 DIP/模式后，再执行操作 69 并回读校验。普通 R15I 已验收 fs 的 SHA256 为 `3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`；诊断位流的历史 hash 与当前构建产物见诊断交接，不把缺失的 SRAM Programmer 返回码写成成功。

## 历史诊断阶段状态（2026-10-18 凌晨，当前入口见上文）

- 板上已观察到诊断日志运行：COM6 有效 STATUS、摄像头界面正常。烧录 SSH 曾在最后收到 44% 后掉线，
  未收到 Programmer 完成返回码，真实点击结果见新交接。**诊断 U15 为 115200 日志，暂停对外 MIDI。**
- [本轮日志实现、实机证据和限制](doc/CODEX_TOUCH_TRACE_HANDOFF_2026-10-18.md)、
  [日志使用](doc/TOUCH_TRACE_V1.md)、[接口差异](doc/TEAM_INTEGRATION_2026-10-17.md)、
  [给队友的说明](doc/TEAM_SYNC_V1_0.md)。
- 共享仓库 `haters-bot/synth1_9_18`，分支 `ui-touch-hub-v1.0`，仅新增 `2_ui_touch_hub/`。
  本轮上传已经用户授权，下面历史“不自动推送”不禁止本次授权发布。V1.0 标签保持，诊断扩展另行提交。
- 分支与基线标签已推送；草稿 PR：https://github.com/haters-bot/synth1_9_18/pull/1 ，未合并 main。
  本轮 120 秒采集仅 STATUS、无真实 touch，操作验证仍待用户；缓存与序号空洞详见交接。

## 已验收普通固件状态（2026-10-17，历史基线）

- 工程 `D:\github\gaoyun\2_ui_touch_hub` 有独立本地 Git；上级目录不是仓库。保持 master，不重写历史、不删除旧产物、不自动推送远程。
- **板上当前 R15I，已部署且用户验收通过**：用户明确回复“更精细，触控正常”。细化主要名称 / 数值 / 页签、平滑曲线；保持 1280×720、PLL 与触摸映射。`verified/ui-R15I-20261017` → RTL `c988661`；部署 `20261017_233834_R15I_final`，双机 SHA256 和 Programmer 返回 0 均确认，实景照片已检查。详细哈希、时序与 Gowin 启动器退出异常见本轮交接文档。
- **已验收回退基线 R15H**：`verified/ui-R15H-20261017` → `2dfbd73`。用户此前确认 FILTER XY 与 ENV 白点拖动及数值联动正常。
- 屏幕原生分辨率仅口述“可能 1920×1200”，未验证；不要据此直接升 PLL 或修改触摸比例。

## 详细记录

1. [本轮像素细节与验证、时序、部署记录](doc/CODEX_PIXEL_DETAIL_HANDOFF_2026-10-17.md)
2. [R15H FILTER / ENV 控制与已验收基线](doc/CODEX_DIRECT_CURVE_HANDOFF_2026-10-17.md)
3. [R15G LFO 面板与音频接口边界](doc/CODEX_LFO_PANEL_HANDOFF_2026-10-17.md)
4. [R15F 文字清晰度](doc/CODEX_UI_LEGIBILITY_HANDOFF_2026-10-17.md)
5. [触控排查与校准历史](doc/CODEX_TOUCH_DEBUG_HANDOFF_2026-10-16.md)

## 双机与可逆部署

主力机 `.235` 编码、ModelSim、Gowin；工程机 `.157` 持有板卡 JTAG、触摸屏和摄像头。SSH 绑定源 `10.136.125.235`；禁止在主力机调用 JTAG。部署脚本使用唯一目录、双机 SHA256、烧录返回码和摄像头回传，不自动重试烧录。

```powershell
# 仅在综合完成且检查报告后部署
python tools/deploy_verified.py --label R15I_final

# 用户要求退回时，直接使用已验收归档，不覆盖当前构建产物
python tools/deploy_verified.py --label R15H_rollback --fs impl/R15H_final_build2_20261017_2251/2_ui_touch_hub.fs
```

R15H 归档比特流 SHA256：`911054F05264B88D565FBF4FC6A600751E93848057080B9A1D67C8F36BE1AC90`。只烧入 SRAM。

## 不得扩大已有结论

- 触控、UI 预览、生成比特流、摄像头正常均不能替代时序收敛。
- R15I 像素域 Fmax 58.084 MHz，目标 62.5 MHz；负裕量端点 65 个，相比 R15H 的 57.813 MHz / 74 个略有改善，仍未收敛。下一轮升分辨率前先处理像素路径。
- LFO 仍为本地 UI 预览；ENV2/3 为独立本地编辑。不能声称这些已驱动音频核。


## 当前继续工作记录（2026-10-19 04:30：R16 时序收敛）

- 本轮继续优化 `button_vector_unit.v`、`knob_vector_unit.v` 与 `lfo_panel_renderer.v` 的像素第一级译码；所有已运行的逐像素和控制回归均通过，未部署板卡，未写 Flash。
- 最新已完成候选 `impl/R16A_build_20261019_041924/` 仍未闭合：`clk_pixel` 57.889 MHz / 62.5 MHz，Setup 112，Hold 0；位流完整但禁止部署。此前候选 `impl/R16A_build_20261019_040729/` 为 56.848 MHz、Setup 77，说明 P&R 波动明显，不能只看单次改善。
- `impl/R16A_build_20261019_043116/` 已完成但不合格：`clk_pixel` 56.657 MHz、Setup 162；随后 `impl/R16A_build_20261019_044352/` 仍不合格：56.646 MHz、Setup 153、Hold 0。P&R 波动与映射变化都存在，两个位流均禁止部署。只有 Fmax≥62.5 MHz 且 Setup/Hold=0 才允许 `deploy_verified.py` SRAM 烧录。
- 最近验证：按钮逐像素 3,686,403 次、旋钮逐像素 3,686,407 次、FX 470,764 次、曲线 bit-exact 15,400 次、LFO/ENV/Filter/参数回归均 PASS。工作区既有 `tools/deploy_verified.py` 修改、`sim/tb_curve_probe.v` 和 `transcript` 均保留。

## 追加记录（2026-10-19 10:32：R16A 构建审计）

- `impl/R16A_build_20261019_052447/` 构建进程于本地时间 05:34 正常退出（return code 0），P&R 与 35,799,213-byte 位流生成完成；审计时输入快照与当前工作区一致，SHA256 为 `F9B71CFB8273B902C3E5B6A0AD12EA8AF04F6267E1A61C25F7505B859FDA403B`。
- 该候选不可部署：`clk_pixel` 仅 57.353 MHz（要求 62.5 MHz），75 个 setup 违例端点、0 个 hold 违例；最差 slack −1.436 ns，路径为 `u_timing/reg_pixel_y_10_s0` 至 `u_render/u_buttons/s0_border_s0`。其他受审时钟 `clk_usb` 为 95.533 MHz、`ch569_htclk` 为 379.776 MHz。
- 这不是 Programmer/JTAG 报错：R16 尚未调用工程机烧录器。板卡最后已知状态仍是已验收 R15I 的 SRAM 画面；Flash 写入继续暂停。只有像素时钟达到至少 62.5 MHz 且 setup/hold 违例均为 0，才可考虑 SRAM 部署。

## 追加记录（2026-10-19 11:40：按钮/LFO 像素时序尝试）

- 按钮空间命中译码改为并行互斥矩形归约；按钮四状态逐像素对照 `button_pixel_tests_20261019_110629_257860` 通过 3,686,403 次，视频对齐 `video_alignment_20261019_110629_581065` 通过 6,136 次。该改动本身没有闭合全局时序。
- LFO 文本渲染去掉 144-bit packed label 在第二拍的字符 mux，改为第一拍寄存字符编号；FX/LFO 控制、字体/混色、视频对齐回归均通过（分别见 `impl/fx_lfo_tests_20261019_113122_486577/`、`impl/pixel_tests_20261019_113218/`、`impl/video_alignment_20261019_113122_321134/`）。
- 隔离 P&R：`impl/R16A_build_20261019_110822/` 审计为 `clk_pixel` 56.685 MHz、132 setup；`impl/R16A_build_20261019_111918/` 为 57.611 MHz、105 setup；`impl/R16A_build_20261019_113242/` 为 56.588 MHz、144 setup。结果受 P&R 波动影响，但均未达到 62.5 MHz/0 setup，均禁止部署。
- 当前最差路径仍在 `u_render/u_lfo_panel/char0_*_s0` 与旋钮局部几何译码，和触控拖动/点击手势无关；不能通过把拖动改成点击来解决。未烧录 R16，Flash 继续暂停。

## 追加记录（2026-10-18：暂停外 Flash，恢复 R15I 画面）

- 用户决定今天暂停 Flash 写入，并先保留当前 R15I 画面。
- 外 Flash 目标是普通 R15I（保留 MIDI）：`impl/R15I_final_build2_20261017_2336/2_ui_touch_hub.fs`，35,117,569 bytes，SHA256 `3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`。
- 用户把 DIP 调回 `100001`（DIP1→DIP6）。只读操作 51 成功读到 Flash ID `0x0B4018`。写入操作 69（GAO-Bridge 5A erase/program/verify）失败，退出码 64，报 `SPI Flash not found(0x000000)`；随后操作 67 的 GAO-Bridge 5A 校验也失败。操作 68（擦除/编程，不带 verify）同样失败；只读操作 66 可检测到 `0x0B4018`，但校验在地址 0 失败。另一次在 `000001` 状态下的操作 69 也以退出码 64 和 `SPI Flash not found` 结束。
- 因此没有 Flash 写入成功证据，不能声称掉电启动已完成。相关尝试档案保留在 `impl/deploy_runs/20261018_020607_R15I_flash_boot/` 与 `impl/deploy_runs/20261018_021801_R15I_flash_boot_retry/`，含 manifest、固件包及 Programmer 输出。用户要求暂停后，不再进行任何 Flash 擦写尝试。
- 按用户要求，`20261018_023049_R15I_screen_preserve` 已通过远程 operation 2 写入 FPGA SRAM，`PROGRAMMER_EXIT=0`，跨机 SHA256 与上述 R15I 归档一致。摄像头照片确认合成器画面恢复：`impl/deploy_runs/20261018_023049_R15I_screen_preserve/preview.jpg`；底栏裁图为 `telemetry.png`。这是易失 SRAM 状态，不是 Flash 启动证明，断电后不会保留。

- 拨码判断更正：重新对齐 Sipeed 官方 `dip-key_defualt.jpg` 与板卡照片后，官方用于 Flash 的位置是 DIP1、DIP6 为 ON，DIP2–5 为 OFF，即 `100001`。此前把官方图误读为仅 DIP6 为 ON，并建议改成 `000001`，判断错误；用户调回 `100001` 后只读操作 51 能读到 `0x0B4018`。保留这条更正，后续不要再让用户改拨码。Flash 写入失败原因尚未查明，当前 Flash 内容状态未验证。
