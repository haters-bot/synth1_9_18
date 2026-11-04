# 本地演奏功能继续入口（2026-10-29）

> **2026-10-30 实板更新：** 用户现场确认“这一版成功上板”。normal `222234` 已于14:03发起唯一一次 UI SRAM operation 2，退出0、User Code `0x00009B47`、Status `0x00026230`，位流哈希与下方审计一致。部署目录 `impl/deploy_runs/20261030_140337_R16_local_performance_ui_sram_20261030` 保存 manifest、programmer.log、抓拍和用户确认。首次抓拍偏黑不能推翻用户现场确认；灯带逐键映射、32键实际音域和 DDR 整曲录音仍待专项验收。Flash未动、不推送、不删除、不改音频板。下方未烧录/待确认目标板记录均为历史。

> **接续校正：** 以下旧时间点均为历史快照；其中 21:11 的 C14 冲突判断已由 22:55 的引脚复核解决。以 22:55 的 J16→U15→J24 pin 3 引脚核对、23:00 的 normal SRAM 只读预检为准。23:12 重跑的 `performance_led_serial_20261029_231227_998673`（25像素串行链）和 `performance_keys_20261029_231227_990124`（白键映射/MIDI键态）均 PASS。当前 normal/debug 构建均通过五类时序与122/122引脚审计；未烧录、未推送、未删除、未改音频板。实际灯带接线、32键 MIDI 音域和 DDR 整曲录音仍待实板确认。

> **23:42 接续执行验证：** 新建只读 SRAM 候选校验再次通过：99 输入文件无 workspace/snapshot mismatch，五类时序零违例，122/122 引脚一致，normal 位流 SHA256 仍为 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`。当前复跑 PASS：25 像素 GRB/1200脉冲 WS2812链、15个基准音/1920 MIDI编号/480+480重叠键态、命令解码、曲谱提示、11个显示状态、MIDI解析、三源事件串行、PCM捕获/独立时钟/整链路DDR读回、长曲进度、传输协议、5档曲谱容量和录音store故障/读回。完整页面的重复预览从 `performance_preview_20261029_233625_591423` 启动后，因渲染速度低于实用限度而中止；只留下925816字节部分hex和日志，没有PASS结果，未删除文件且确认仿真进程已退出。上一轮完整页面预览 `performance_preview_20261029_213935_466000/result.json` 仍为PASS证据。没有访问工程机、烧录或修改硬件；用户要求确认安排后执行，实物JTAG目标/灯带接线尚待确认。

> **只读 JTAG 探测：** 通过 IPv6 `ssh gaoyun` 在工程机运行 Programmer CLI `--scan`，返回 `Gowin USB Cable(FT2CH)/0`、1 个 `GW5AST-138B/GW5AST-138C (One of them)`、ID `0x0001081B`。该结果只证明下载器和一枚高云 138K 器件在线，不能区分 UI 板/音频板，也未执行任何 SRAM/Flash 写入。

> **23:00 正常位流部署前只读预检通过，未烧录：** `R16A_build_20261029_222234` 的 SRAM `--check-only` 重新验证输入哈希、五类时序和 122 个引脚，位流 SHA256 为 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`；脚本未访问工程机、未写 SRAM。

> **21:11 历史预检（已被22:55后的构建/引脚复核取代）：** `191907` 候选曾通过 `--check-only`，但当时只审计121个引脚；没有访问工程机或写板。当时发现的 C14 冲突来自旧方案，后来已按 Dock 原理图将灯带独立接到 J16、C14 保留调试 UART。当前依据是本文件顶部所列 normal 构建与只读预检；未烧录、未推送、未删除、未修改音频板。
> **22:55 本轮硬件核对与重构完成：** 根据 Sipeed `Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf` Rev 1.3 第 7/9 页，FPGA J16→板载 U15 DIN、U15 DOUT→J24 pin 3；J24 pin 1=GND、pin 2=NC、pin 4=受 0.45 A 限制的 5V。已将 `performance_led_data` 独立为 J16 顶层端口，C14 恢复调试 UART。WS2812 链改为 25 像素：板载首像素固定黑色，随后 24 个外接像素；颜色降低以限制最大电流。24 灯/黑键映射、生产 renderer 全屏预览（7帧、921600像素）、C14 UART/正常与诊断完整 RTL 编译通过。正常构建 `impl/R16A_build_20261029_222234` 审计 `audit_20261029_223823_390089.json`：99 输入哈希一致、122/122 引脚匹配，setup/hold 0/0，最差 setup/hold/recovery/removal/pulse +0.140/+0.138/+0.335/+0.302/+0.361 ns，像素 50.352 MHz、DDR 用户时钟 110.36 MHz。诊断构建 `impl/DEBUG_R16A_build_20261029_223907` 审计 `audit_20261029_225516_529584.json`：100 输入哈希一致、122/122 引脚匹配，五类 0 违例，最差余量 +0.649/+0.135/+0.335/+0.299/+0.361 ns。首候选 `220509` 有 5 条 setup（−0.126 ns）并保留未删。以上仅为 RTL/仿真/P&R 证据；仍未烧录，实际灯带接线、24 灯实物、键盘音域及 DDR 实板录音需后续验收；手机/蓝牙仅保留接口，未推送、未删除、未改音频板。详见 `doc/UI_PCB_DEBUG_UART_PINOUT.md`。

> **21:13 本地录音边界回归补齐：** PCM 捕获深度 3/16、左右声道次序/有符号采样、背压、容量、溢出、排空、断源及命令优先级通过（`impl/performance_pcm_20261029_211338_276125`）；生产 I²S 发送器到独立时钟 UI 接收器的逐对采样测试通过。长曲目进度 1047 项参考通过（`impl/performance_progress_20261029_211338_277479`）。加上上一轮 DDR adapter 全链路读回回归，软件侧录音/进度用例已覆盖。当前只读 SRAM 预检仍通过，物理接线与断电状态未确认，继续不烧录、不推送。

> **20:58 构建与本地演奏回归收尾：** 唯一候选 `impl/R16A_build_20261029_191907` 已于 19:46:38 退出 0；实际 `cmd.do` 为 `GW5AST-138B/PBGA484A-1`、`place_option 3`、`route_option 1`、`timing`、`correct_hold 1`、`route_maxfan 23`，使用唯一 `ui_touch_hub_combined.cst`。最新审计 `audit_20261029_205750_886777.json`：99/99 输入哈希匹配，121/121 引脚匹配，setup/hold 违例 0/0，最差 setup/hold/recovery/removal/pulse 分别 +0.214/+0.140/+0.335/+0.369/+0.361 ns；`clk_pixel` 50.541 MHz、`ddr_user_clk100` 104.122 MHz，OSER10 recovery/removal 三端点齐全且无豁免，`2_ui_touch_hub.fs` 38,731,437 bytes，SHA256 `78FEB3FA6EA7771B9D4DB0979C724437238355B2FE7B3DF2A09FC99A112C396`。旧 `185326` 仅综合后中断，保留未删。`performance_led_white_mapper` 的综合 swept 警告不作为硬件失效结论；当前白键映射、24 灯 WS2812 波形、实体键/曲谱提示均有独立回归和完整 renderer 预览证据。
>
> 当前回归全部 PASS：`performance_keys_20261029_194846_759722`、`performance_led_serial_20261029_194846_765328`、`performance_cue_20261029_194846_766005`、`performance_command_tests_20261029_194846_811607`、`performance_store_20261029_194932_141837`（两组异步时钟、137 对生产 I²S 样本逐帧读回、故障恢复）、`performance_display_20261029_194932_141544`、`navigation_20261029_194932`、`trace_tests_20261029_194932_169522`、`performance_notes_20261029_205545_646398`、`performance_scheduler_tests_20261029_205545_632768`，以及 MIDI/协议 Python 回归。当前 renderer 预览 `performance_preview_20261029_202447_714069/result.json` PASS，`performance.png` 为 1280×720，720 行×1280 像素、7 个 24 灯帧/921600 有效像素，已人工查看。预览工具改为逐行写出并严格恢复/校验完整像素，原始超时目录 `performance_preview_20261029_195017_613814` 保留。
>
> `impl/R16A_build_20261029_191907/functional_evidence.json` 汇总上述构建、位流、预览和回归路径。仍不烧录、不推送、不改音频、不删除：实体键盘最低 MIDI 音仍是临时 `PERFORMANCE_BASE_NOTE=60`，DDR 实板容量/校准、WS2812 电气接线和整首录音硬件验收未完成；手机/蓝牙只保留接口，音频板由队友负责。
> **19:40 接续恢复：** 先前 `impl/R16A_build_20261029_185326` 不是成功结束：PID 37860 已不存在，日志只到 Routing Phase 0，只有综合产物，没有 P&R 时序/位流；该目录 99 个输入哈希均匹配，未删除。按同一最终源码启动唯一新候选 `impl/R16A_build_20261029_191907`，构建 PID 17256、exec 19784；真实日志已完成综合并进入布局 `[30%] Placement Phase 2 completed`，进程仍存活，未收结果。实际 `cmd.do` 已核对 `-place_option 3`、`-route_option 1`、`-correct_hold 1`；约束文件为唯一 `ui_touch_hub_combined.cst`。综合资源为 Logic 61259/138240、Register 38370/139095、BSRAM 86/340；仍需完整五类时序审计。综合日志报告 `performance_led_white_mapper` 实例 swept；白键映射与 24 灯串行有 RTL 回归及生产 renderer 预览证据，但该综合警告与实体灯带行为仍须实板核实，不据仿真宣称硬件验收。继续不并行 Gowin、不烧录、不推送、不改音频、不删除。



> **16:44 当前唯一构建164300正在综合，目标未完成。** 实际UI impl/R16A_build_20261029_164300，PID29796、exec39803，99输入哈希一致。上一162301已退出0并审计：3setup/0hold，pixel50.299/50MHz已通过，DDR90.976/100MHz仍失败，最差-0.992ns为committed到return_data64，121引脚全匹配，recovery/removal/pulse+0.335/+0.290/+0.361ns，三路OSER10均有完整检查，不可部署。审计audit_20261029_163948_380808.json。
>
> 已增加M_CALCULATE阶段，先寄存memory_base+committed及committed+frames，再比较并生成状态，未放宽时钟/约束。store164215两异步时钟/2053帧/137生产I²S链路/故障恢复PASS；测试原随机窗口未覆盖data-first，已改逐写强制交替，两顺序各9次通过，保留失败证据。trace164051正常/诊断完整编译、cue164331、navigation164331、display164331通过；notes162226及背景259330逐点比较输入仍匹配。索引当前构建functional_evidence.json。
>
> 无运行中预览；旧preview152737已经PASS和人工查看，本版以背景等价和七拍导航回归支持，不声称新整帧截图。曲谱默认只指引，MIDI最低音60临时且实体32键待采样；E19队友main仍d4338fb。无线延后，整首DDR实际容量/校准/录音读回及灯带电气未实板验收。不烧录/推送/删除/修改音频。

> **16:31 当前唯一构建162301仍在布局，未完成。** 实际UI impl/R16A_build_20261029_162301，PID32320、exec80315，99输入SHA与工作区一致。旧155807已退出0并审计失败：329setup/0hold，pixel48.774/50MHz、DDR81.593/100MHz，最差-2.256ns为committed计数到req_wmask；121引脚匹配，recovery/removal/pulse为+0.335/+0.377/+0.361ns，不能部署。审计audit_20261029_161438_233137.json。
>
> 已按关键路径将DDR命令锁存与校验分成M_VALIDATE阶段，宽请求载荷锁存独立于合法性检查。回归发现校准丢失后结束标记被旧故障逻辑覆盖，已把transaction_failed限定实际REQUEST/RESPONSE，store162149两时钟/2053帧/137生产I²S链路与校准丢失恢复全PASS。notes162226、cue162225（默认曲谱只指引不发音频Note）、navigation162226、display162225、trace162149正常/诊断完整编译PASS。带哈希证据索引impl/performance_timing_fix_20261029_155312/final_regressions_162301.json。trace脚本无result.json，记录日志证据，不伪造结果。
>
> 上一整帧预览152737已PASS并人工查看；该图早于时序改动，本版以259330背景等价比较和七拍导航回归支持，无新整帧捕获。Sipeed官方标称1GB DDR3/512MB×2，来源impl/ui_memory_reference_20261029_160033；配置1GiB录音区理论96kHz/16位双声道46分36秒，具体实板容量/校准/地址不折返未验收。验收基准doc/LOCAL_PERFORMANCE_ACCEPTANCE_2026-10-29.md。音符沿队友d4338fb原始MIDI号，实体最低音仍待测，60临时。无线继续延期；未烧录/推送/删除/改音频；目标未完成。

> **15:58 接续：旧预览152737已收回PASS，当前唯一Gowin155807正在运行。** preview/session70304/kernel29548均结束；921600像素与7灯帧/4032位、按钮/切页全灭PASS，result.json输入SHA一致，performance.png已人工查看。解除冻结后增加DDR mem_token数据/valid保留边界、Note队列独立弹性输出寄存、并行背景选择（保持7拍），默认关闭曲谱自动发声，灯/屏幕指引不变。旧综合网表为加密文件，无法凭搜索不到mem_token断言寄存消失；是否改善以新STA判断。
>
> 新回归store155532（两异步时钟/2053帧/137生产VIS V2 I²S/队友adapter精确读回及故障恢复）、notes155532（36事件真实串行/背压/溢出）、cue155618（1000位置/暂停/停止且曲谱无音频Note）、navigation155618、display155618、trace155618正常/诊断完整编译均PASS；background_final_result.json比较259330组旧/新背景PASS，全部带哈希证据当前匹配。索引impl/performance_timing_fix_20261029_155312/final_regressions.json。编译曾因循环变量sc重名失败，已改名并重新通过，失败证据保留。
>
> 唯一构建实际副本impl/R16A_build_20261029_155807，exec61759，PID=34700；99输入SHA匹配，尚未时序审计。无第二份Gowin、无运行中整帧预览，不烧录/推送/删除、不改音频，目标未完成。键盘协议按队友d4338fb的E19 MIDI原始编号，最低音60仍临时，实物验收前需采样实际32键；无线延期。旧152727仍因488setup/DDR81.944MHz/pixel46.81MHz拒绝部署。

> **15:48 唯一构建152727已退出0，仍拒绝部署：** 审计audit_20261029_154524_330143.json，99输入哈希匹配、121引脚全匹配，setup488/hold0，pixel46.81/50MHz、DDR user81.944/100MHz。官方DDR异步分组已消除原PHY跨域-7.508ns路径；本次最差-2.203ns为commands BSRAM到return_data/req，pixel最差-1.363ns为raster x到导航背景；另Note arbiter计数到MIDI FIFO使能-0.877ns。recovery/removal/pulse+0.335/+0.302/+0.361ns，三路OSER10均完整报告且通过。critical_path_review.json已保留，后续应保留DDR数据寄存边界、Note输出寄存、并行背景选择，不盲换模式。
>
> 无活跃Gowin；preview152737/session70304/kernel29548仍真实运行，约15:47已有5.8MB像素，未结束前RTL继续冻结。最终同源录音store153326通过拒绝/满/停止/断线恢复，candidate证据索引已更新。默认设计依据原需求为用户按实体琴键发声、曲谱仅指引；可选自动发声问题尚未答复，当前候选中曲谱到预留MIDI输出的默认行为仍需在冻结解除后明确。未烧录/推送/删除或改音频，目标未完成。

> **15:31 本地功能已推进，源码冻结验证中：** 录音接受/拒绝/自动停止反馈已闭环，新增真实状态与字符ROM；解决上次断线故障污染下一次录音的capture epoch问题。store152158的2053帧两时钟组和137帧生产I²S→队友adapter→精确读回，含拒绝重试、满容量/停止/断线恢复及状态均PASS。三源Note独立16深队列+UART ready/独立键掩码，36事件真实串行、480三源同键重叠通过；超载可见但密集32键和Stop/Pause已发送Note清理尚须后续验收，不称完整音频演奏通路。
>
> 候选曲谱容量升16384事件并集中参数，满后额外写入导致load_error并拒绝播放截断曲谱；scheduler152702覆盖5/8/1024/4096/16384通过。新增提前1秒的下落Note-On提示，cue152729验证1000位置/暂停冻结/Off不提示/停止清除；导航152743、I²S字形/ROM152708、全部11状态字符152744、normal/debug完整编译152702通过。手机无线仍延后，只同步32键/容量接口。
>
> **唯一Gowin**实际副本impl/R16A_build_20261029_152727、PID22828、exec60928，仍综合，normal/debug使用官方DDR分组与扩大STA报告；不可并行。**新版preview**impl/performance_preview_20261029_152737_017392、exec70304，真实renderer/7灯帧验证运行中，相关RTL/vh冻结直到收回。恢复先核对真实进程/同句柄。未烧录、推送、删除或改音频工程，目标未完成。

> **15:07 预览已收回并通过（覆盖下方运行中状态）：** performance_preview_20261029_144245_230550/session70866退出0，kernel34760已结束；921600有效像素、7个24灯帧/4032位、控制点击不切页、启动全灭/触摸/松开/MIDI64/停止/退出页全灭全部PASS，result.json的输入SHA256一致。完整performance.png已人工查看，控制按钮无导航遮挡；这不是实板验收。当前无活跃Gowin或ModelSim，RTL冻结已解除。
>
> normal/debug SDC已按高云GW5AST-138B官方例程拆开DDR100/400异步组，并按本机SUG940 5.5.1加入扩大及pixel/bit-clock专项report_timing，未降低频率或豁免域内/OSER10 reset。**此为14时段历史计划**：当时142528被拒绝部署，后续已完成本地功能实现与新构建。键盘最低音仍待现场MIDI采样；C14旧冲突判断已被22:55引脚复核取代。未推送/烧录/删除或改音频工程。

> **15:01 接续核对：** 已再次fetch队友main，仍d4338fb。E19的MIDI音符号原样进入合成器、解析器接受全部16通道；UI发送约定通道1，不能写成E19只收通道1。仓库仍无实体32键最低音，60只是临时参数；不需要原理图，但实体灯安装/验收前必须采样实际键号。只读源码证据impl/audio_note_contract_20261029_145705，协议文档已纠正。
>
> **DDR官方约束新证据：** 高云官网DDR3 ZIP内含GW5AST-138B专用1:4工程，其SDC将100MHz用户时钟与400MHz PHY设异步组（源头/逐项对照/SHA在doc/DDR_OFFICIAL_TIMING_REFERENCE_2026-10-29.md与impl/ddr_official_reference_20261029_145035）。此前142528最差25条setup全部跨此边界（4条到下降沿、21条到上升沿），先前“同组”指导已被官方示例纠正。normal/debug SDC已按官方分组，域内时序/OSER10 reset未豁免，尚未重跑P&R，不代表时序闭合或DDR实物验收。无新活跃Gowin；preview144245/session70866/kernel34760仍运行，hex持续增长，RTL冻结等待收回。未烧录、推送、删除或改音频源。

## 14:48 构建结果已收回（当前恢复入口）

- `R16A_build_20261029_142528` 已退出0，exec31668结束；本轮无活跃Gowin。
- 最终pin report全部121处与源约束一致，证明单一combined CST修复实际生效。
- 完整审计 `audit_20261029_144607_910780.json` 仍拒绝：233 setup、0 hold，pixel45.907/50MHz；setup最差-7.508ns，前25条负路径都在DDR PHY内部（read_rclksel_conf、hold_gen到DQS、校准到IDES）。recovery/removal/pulse最差+0.324/+0.287/+0.451ns，但removal仅前25条报告未覆盖全部三路OSER10，不能当成完整复位验证。
- 本轮没有新增PHY false-path。下一步核对与当前工具版本匹配的DDR IP时序要求，获取各域更广路径报告，分别修复DDR PHY与UI pixel域；不要只切route模式重复构建。GitHub公开API查询Sipeed例程遇到403 rate limit，未获得新参考依据；本地IP帮助只说明时钟比例，未找到足以豁免负路径的条款。
- 该构建也早于演奏控制条移动，必须在最终源稳定后重新唯一构建。当前无理由部署142528。
- 新完整预览 `performance_preview_20261029_144245_230550`、exec70866、kernel34760仍运行（已输出pixel hex），还未PASS；恢复先检查同一句柄及simulation.log，不要重复启动。相关源码冻结至该验证结束。按钮/导航回归已分别通过144134/144322。
- 存储、灯带串行、约束门槛和按钮布局的源码修改已保存；实际录音状态恢复/错误显示、事件仲裁、整曲容量策略、物理键盘校准、灯带电气和实板DDR验收仍未完成。C14 分配已由后续原理图复核确定为调试 UART，灯带数据使用 J16。

## 14:44 画面审查修正与当前句柄（覆盖14:33）

- 旧完整preview142720部分画面已人工查看，发现播放/暂停/停止/录音原y8..40区域被全局导航遮挡且点击可触发导航。已验证该preview kernel身份后只停止PID30820；exec88840退出1，保留partial_review.png、部分hex与日志，不作为PASS。
- 演奏控制条及触摸命中移动到y136..168，指引轨道从y192开始，保留底部y420..719全宽32键。`performance_command_tests_20261029_144134_269634`与`navigation_20261029_144322`均PASS。
- 新完整preview `impl/performance_preview_20261029_144245_230550`、exec70866、kernel34760仍运行。新增实际导航/触控/command decoder联动，逐项点击播放/暂停/录音/停止后检查仍为演奏页；检查7个24灯帧与4032脉冲，并输出921600像素后检查退出页全灭。只有该完整流程结束及人工查看PNG后才可称预览通过。
- 当前唯一Gowin142528/PID33588/exec31668仍在routing；实测cmd.do明确place3/route1、combined CST与normal SDC，无重复Gowin。该快照尚不含按钮移动，不能因后续STA通过就直接部署，必须匹配最终源码与清单。当前输入正在预览期间冻结。
- 下一轮仍须解决实际录音状态/错误/完成显示及录音失败后重试按钮请求状态、Note事件仲裁、曲谱容量与实物校准；本次没有把这些列为已完成。所有禁止烧录/推送/删除边界继续适用。

## 14:33 当前执行入口（覆盖下方旧候选与待办状态）

- **发现并修正错误的约束加载**：Gowin 对两份 active CST 只加载最后一份。135029/140630 的 pin report 确认原 UI 引脚被自动改派（例如 C14 输出落 W14），两份都拒绝部署。现在 normal/debug 工程各只有一份 combined CST 与一份 SDC；debug DDR INS_LOC 加 `u_hub/` 前缀。源分片保留不删除，`tools/combined_constraints.py` 生成合并文件；build_isolated 在快照前检查唯一活动约束与合并内容一致性。
- `audit_build.py` 增加最终 routed pin report 对照，覆盖差分引脚正负端。已验证旧验收候选032336全部50处匹配，错误140630被检测出多份CST及UI引脚错配。`deploy_verified.py` 本来就重新调用 inspect_build，因此该检查同时成为部署门槛。
- normal/debug SDC 已添加明确的400MHz DDR/100MHz user时钟，并把二者保留在同一组内，只隔离与UI/USB/HSPI之间的异步域；未豁免PHY内部setup/hold或OSER10复位。
- 录音命令FIFO输出增加宽数据寄存级，再做协议检查/请求选择，以处理140630的BSRAM到req_wdata关键路径。存储回归 `performance_store_20261029_142445_729452` 两组异步时钟/2053帧/故障覆盖/137帧生产I²S到队友adapter读回均PASS；normal/debug完整编译与串口 `trace_tests_20261029_142445_739988` PASS。
- WS2812增加启动及帧后300us低电平、明确RGB输入转GRB串行、50MHz下0.4/0.8us高电平；冻结完整帧按键掩码，启动发送全灭帧。`performance_led_serial_20261029_141945_786092` 逐位检查两帧1152位通过，含busy写隔离和全灭。
- **历史方案，已被22:55引脚复核取代：** 当时曾提出 C14 与灯带复用并等待用户确认；最终方案不复用 C14，改由 J16 独立驱动灯带，C14 保持调试 UART。实物灯带型号、供电、信号电平和亮度仍待验收。
- **当前唯一Gowin**：`impl/R16A_build_20261029_142528`、PID33588、exec31668；已综合，日志确认读的是combined CST，仍在布局。恢复先核对日志/真实进程，不并行再起Gowin。140630已退出0但454setup/34hold、五类审计不通过且引脚错误，严禁部署。
- **当前完整演奏预览**：`impl/performance_preview_20261029_142720_043136`、exec88840、ModelSim kernel PID30820；已串行验证启动全灭/触摸/松开/MIDI64四帧，正在输出921600像素全帧，末尾还会验证退出页面全灭。未结束前不得声称预览PASS。相关输入冻结；恢复先收回结果，再查看PNG。
- 无音频源修改、烧录、推送或删除。本地完整UI时序、DDR PHY实物校准/容量、整首录音以及灯带电气验收均未完成，目标保持进行中。

## 14:13 接续更新（优先于下方历史状态）

- GitHub `haters-bot/synth1_9_18` fetch 后 `origin/main` 仍为完整提交 `d4338fb1509f724e686d84f7bbac45692632ea3b`。本地工作分支的音频源早于 E19 接入，不能用工作区 `src/top.v.v` 代替 `git show origin/main:src/top.v.v`。
- 实体键盘接入提交 `7a18fd0` 明确 `keyboard_uart_rx=E19`、3.3 V、31250 baud、8N1；独立解析器和事件 FIFO 原样传递 7 位 MIDI 音符号。没有实体 32 键最低音、转换模块键位表或键盘型号记录。60 仍只是可配置默认值，需之后读取最左键并检查全键范围/移调；用户不需要提供不存在的原理图。
- DDR IP、PLL、复位与 user-port wrapper 已接正常/诊断 UI 顶层和工程文件；录音 PCM 请求已连到 DDR wrapper。下方“UI top 尚无 DDR ports/后端未接入”描述已过时。IP 可在本机完成综合/P&R，但这不证明 DDR 实物校准、容量或可靠录音。
- 修正前快照 `impl/R16A_build_20261029_135029` 14:05 退出 0；审计 `audit_20261029_140620_318327.json` 不通过：109 setup、120 hold，最差 setup/hold/recovery/removal=-2.428/-1.649/-3.691/-0.449 ns；快照含未驱动 DDR 请求且与当前顶层不一致，禁止部署。
- 最新正常/诊断完整编译和串口回归 `trace_tests_20261029_135828_735964`、导航 `navigation_20261029_135807`、键/白键灯映射 `performance_keys_20261029_135930_824815`、触摸/演奏命令 `performance_command_tests_20261029_135936_191643` 均 PASS。
- 当前唯一 Gowin 候选 `impl/R16A_build_20261029_140630`，PID 6804、exec session 27762；已综合并进入布局，恢复时先核对 `build_process.json`、日志和真实进程，不并行启动 Gowin。DDR 请求未驱动及 adapter 被裁掉告警已消失；尚无最终时序结论。
- 待后续处理：UI SDC 尚无队友 `full_synth.sdc` 中的 DDR 400/100 MHz 显式时钟及异步组；须结合实际 CDC 与 DDR IP 文档补齐，不能通过任意 false-path 隐藏 PHY 内部负裕量。灯带串行、画面、事件仲裁和实板录音验收仍未完成。
- 本次未改音频 RTL、未烧录、未推送、未删除；保留已有修改和构建证据。

## 13:35 本地演奏控制更新

- 演奏页顶栏新增播放、暂停/继续、停止图标控件；触摸输入在页面内做边沿检测和坐标门控。
- 本地命令进入与预留手机协议相同的 command decoder，统一驱动 scheduler 的 start/stop/pause 状态。
- 验证：`performance_command_tests_20261029_133453_862938` 覆盖触摸命中区域、页面门控、本地三种控制和远程暂停后本地恢复；`navigation_20261029_133336` 32键触摸/页面回归PASS；`trace_tests_20261029_133336_612787` normal/debug源码编译与串口回归PASS；`git diff --check`通过。
- 此为RTL与模块仿真，未运行Gowin P&R，按钮尚未实板验收。整首DDR后端仍未接UI顶层，因此不显示可用录音状态；手机无线仍只保留接口。

## 用户范围

实际工程 `D:/github/synth1_9_18/2_ui_touch_hub`。音频板交由队友接手，
本任务不修改、构建、推送或烧录音频工程；保留工作区已有文件，不删除。
手机上传/下载及无线模块适配暂缓，保留接口。继续实现 UI 本地演奏页、
32 键曲谱提示、24 灯白键提示和来自音频板 I²S 的整首 PCM 录音。
本轮未运行 Gowin、未烧录、未推送。目标尚未完成。

## 已核实的音高安排

GitHub `haters-bot/synth1_9_18` 的 `main` 再次 fetch 后仍为 `d4338fb`。
直接读该提交的 `src/midi_note_parser.v`、`src/top.v.v` 和协议文档，
确认 E19 解析出的 MIDI 音符号原样进入合成器；支持范围 21..108。
没有实体键盘最低音的记录。UI/曲谱/声音以数值 MIDI ID 为共同依据，
不推断实体键盘从 C4 开始，不把测试刺激 48..55 当作实体键盘音域。

`ui_touch_hub_top.PERFORMANCE_BASE_NOTE` 已传至 UI 全部键位/灯带映射。
临时默认 60，待实物读取最左键后校准。校准应遍历 32 键并检查八度/移调状态，
不能未经验证就假定所有键连续。黑键只显示屏幕提示，白键自左向右依次分配灯；
临时 60..91 范围有 19 个白键，剩余 5 灯熄灭。

限制：当前 UI 无实体键盘 Note 事件回传；音频 `main` 的 C19 控制口丢弃 Note。
因此不能声称实体按键评分、UI 触摸发声或演奏自动发声已完成联调。

## 本轮代码

- 修正导航文字及顶栏为合成器/可视化/演奏/系统；菜单为页面 4。
  系统文字只在页面 3 出现。生成器仍限制 128 条文字矩形，未扩大字库。
- 32 键静态渲染区间与白键灯位分离，支持参数化最低音。
- 修复拖键后下一拍立即抬起丢失导致的粘键；坐标出屏及离开页面释放。
- 停止/有效清空/重播时清除曲谱提示状态，保留独立触摸状态。
- Python `note_to_key` 的默认键数同步为 32；暂缓网页草稿的接入和修改。
- 播放进度改为 48 拍定点除法器，避免约 65.5 秒后的 32 位乘法溢出，
  移除原来的大组合乘除表达式。未用新时序豁免，未声称时序已收敛。
- 新增 `performance_pcm_capture.v`：I²S 接收后的完整 L/R PCM 帧写入接口，
  可设置实际后端容量，支持 start/stop/clear、统计、阻塞保持、满容量、
  溢出/断线明确终止和排空。
- 新增 `performance_async_fifo.v`、`performance_pcm_store.v` 和
  `performance_recording_subsystem.v`：8 个 32-bit stereo frame 打包为一个
  masked 256-bit transaction，经 src/DDR user clock Gray FIFO；只在后端
  write response 成功后累计已提交帧。结束数、连续帧号、容量/区域、掩码
  均验证。录音源丢样、写/读错误、超时或校准丢失使 song 不可读；超时后
  DDR 端口隔离到复位，不自动重试。读口支持背压且数据稳定。
- 此为可连 DDR user-port 的模块层，不是 UI 板现成硬件缓存：UI top 仍无
  DDR ports、Gowin IP 与用户时钟 wrapper。`done` 代表外部 volatile DDR
  adapter 成功确认所有写请求，不代表非易失存储或手机下载。
- UI 不再把协议的录音请求位显示为真实录音状态；等待真正存储后端接入。

录音流 `write_data[15:0]=L`、`[31:16]=R`，`write_index` 为帧编号。
`written_frames` 代表后端 ready/valid 接受数；若后端内部还有排队，
必须等待其提交屏障才能对外报告整首存储完成，不能把 FIFO 排空当成 DDR 落盘。

## 验证证据

所有证据在本工程 `impl/` 中，本轮测试均在各自新目录运行，旧产物保留。

| 验证 | 证据目录 | 覆盖范围 |
|---|---|---|
| 键状态/白键灯位 | `performance_keys_20261029_124310_808687` | 15 起始音、1920 MIDI 输入、480 触摸重叠、黑键不占灯、空余灯熄灭、清除不抹掉触摸 |
| 事件调度器 | `performance_scheduler_tests_20261029_123924_250340` | 容量 5/8/1024/4096，时间、暂停、重播、满容量、停止、清空、复位 |
| I²S 与可视化 | `i2s_tests_20261029_131949_887871` | 生产 I²S、L/R 配对、断线恢复、65536 字形、8192 字符 ROM、576 逐拍数字像素、波形/RMS/相关性 |
| 完整源码/串口 | `trace_tests_20261029_131949_891687` | 当前 debug 工程源码编译，UART 波形、队列溢出、主机解码、分片恢复 |
| PCM 前端/真实链路模型 | `performance_pcm_20261029_125227_674937` | FIFO 深度 3/16，左右顺序、符号、容量、阻塞/溢出、命令优先级、生产发送器→异步相位接收器→PCM 写入流 |
| 长曲目进度 | `performance_progress_20261029_125443_375804` | 1047 个 Python 大整数参考，包括 5 分钟、1 小时、最大时间戳及中途复位 |
| DDR 传输 / I²S 整链路 | `performance_store_20261029_131716_863132` | 2 组异步时钟；0..7 尾掩码；2053 帧写后逐帧读回；容量、FIFO 阻塞、双握手先后、读写错、超时、校准丢失及复位；另 137 个 VIS V2 I²S pair 穿过 recording subsystem 和队友同 commit adapter 后逐帧一致 |
| DDR 与 UI pin 源级比较 | `performance_storage_pins_20261029_131522_465988` | 队友 66 个 DDR pin location 与 UI CST 无重复；不证明实际 PCB/BOM、bank 电压、芯片容量或 IP 可生成 |

`test_performance_protocol.py` 与 `test_performance_midi.py` 本轮通过。
最终 `test_navigation.py` 目录 `navigation_20261029_125443` 已退出 0 且 PASS，包含源码 SHA256 与实际顶层的
32 键 MIDI、慢拖动、立即抬起、出屏、切页、原参数/路由保持和菜单/设置回归。

I²S 原回归第一次失败原因：测试台未连接新增演奏端口，产生 Z/X。
补齐明确零输入后整套通过，没有放宽像素期望或跳过检查。

最后一轮导航/I²S/完整 debug 源码回归全部通过。存储整链路证据目录为
`performance_store_20261029_131716_863132`。所有本轮测试句柄均已结束；
最终文档改动后需再次运行 `git diff --check`。

## 尚未完成与后续顺序

1. **实物 DDR 后端**：完成了 DDR user-port 协议模块和内存模型验证；UI top
   尚无 DDR I/O、IP/PLL wrapper 与 100 MHz user clock，因此 FPGA 上尚未使用
   这块 DDR。当前 machine Gowin UI 为 1.9.11.03，队友同提交的 DDR IP template
   是 1.9.12.03；尚未证明本机可以生成并综合该 IP。源级 66-pin 不重叠不证明
   板卡 revision、DRAM 型号、bank 电压/时序、训练或容量；需据实物 BOM/原理图
   及目标板工具生成结果确认，再接入当前 subsystem。
2. **整首容量**：96 kHz/16 bit/双声道为 384000 B/s，
   5 分钟需 115200000 B，不得用小 FIFO 替代整首需求。
   队友 `docs/ddr_storage_path.md` 提供 100 MHz 用户端、400 MHz PHY、
   256-bit 事务和异步 FIFO 接口。其 DDR IP 为 Gowin 1.9.12.03，
   本机 UI 为 1.9.11.03；先确认 UI 板 DDR 引脚/时钟与 IP 兼容性。
   需要容量保护、CDC、256-bit 打包、写响应/排空屏障、索引读取以及丢样报告。
3. **本地完整交互**：演奏页播放/暂停/停止、录音控制，状态来自实际后端。
   手机未接入前用本地已载入事件进行验证；不得伪装手机已连接或歌曲已上传。
   事件上限目前仍为 1024；整首曲谱超过上限必须明确拒绝，后续需外存扩容。
4. **事件仲裁/声音接口**：曲谱、触摸、预留网关同时到达不能丢 Note Off；
   与队友约定 UI Note 独立输入/实体按键事件回传，保留 E19 键盘与 C19 控制。
5. **灯带串行与画面**：验证 24 灯实际 WS2812 位序与脉宽、帧更新一致性、
   C14 退出演奏页时的最后熄灯帧及调试复用；生成并检查完整演奏页预览。
   当前已过的位图测试不能替代这些串行/电气检查。
6. **时序和实机**：旧候选 `R16A_build_20261029_105439` 的完整审计为
   pixel 20.971/50 MHz、494 setup、最差 -27.684 ns，禁止部署。
   新静态键区/进度逻辑尚未经布局布线；RTL 通过不代表时序闭合。
   在获得本轮构建/部署授权后，只启动一份 Gowin，通过源码清单及五类审计后
   才能按 SRAM operation 2 流程执行，Flash 不动。

无线模块手册、手机上传/回传继续等待用户后续提供，本轮不扩展该部分。

## 15:34 current validation limitations

The first 16384-event image completed synthesis with 61456 logic cells (45%),
37923 registers (28%) and 93/340 BSRAM blocks (28%). This is capacity evidence,
not routed timing closure. The unique build remains PID22828/exec60928.
The new preview is kernel29548/exec70304, with pixel output growing.

A requirement-to-test index is preserved in
`impl/performance_candidate_152727_evidence.json`. The recorder chain initially
predates the decoder's final capacity/zero-velocity normalization edit; a fresh
same-source recorder chain is running to close that evidence mismatch.

Outstanding local work after the frozen validations: evaluate routed critical
paths, preserve complete reset-path reporting, decide guidance versus automatic
sound (user question pending), prevent stuck transmitted Notes on Stop/Pause
if automatic sound is required, and improve the advance cue beyond a single
prefetched event if needed for polyphonic scrolling. Wireless transport remains
explicitly deferred. No physical-key scoring or automatic note calibration is
claimed. UI DDR capacity/electrical checks and exact strip pin/model require
physical acceptance; no new hardware programming is authorized by these tests.
