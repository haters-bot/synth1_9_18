# UI Touch Hub 当前交接入口

> **2026-10-30 21:42 ZCode 断电重烧完成，板上恢复为已验收同版位流。** 用户报告板卡断电（SRAM 配置丢失），已用同一保留位流 `E:/gaoyun_builds/R16A_build_20261030_201520/impl/pnr/2_ui_touch_hub.fs` 重新执行唯一一次 SRAM operation2：写前重读审计 timing_closed=true、双端 SHA256 一致 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`，PROGRAMMER_EXIT=0、User Code `0x00001521`（与20:44首烧一致）、Status `0x00026230`、26.3s。部署目录 `impl/deploy_runs/20261030_214138_R16_stereo_hc07_F14_F16_reburn_after_powerloss`。位流文件断电前后哈希逐位一致，未重新编译（主机未断电文件无损）；Flash 未动、无重试。显示验收沿用户此前"没事，正常的"结论（同一位流）；preview.jpg 仍朝天花板仅留档。

> **2026-10-30 GitHub检查点：用户已授权提交并推送当前版本。** 分支 `integration/dual-138k-uart-phase1`；版本范围为当前已审计/烧录且显示正常的UI源码、安卓壳、网页、测试与协作文档，摘要见 [R16发布检查点](doc/RELEASE_R16_STEREO_HC07_2026-10-30.md)。不纳入实现输出、APK/签名密钥、仿真库、抓拍或临时分析；旧音频构建脚本改动留在本地。此前“不推送”条目为用户本次授权前的历史约束。

> **2026-10-30 用户现场确认新版UI显示正常。** 对20:43 SRAM部署，用户回复“没事，正常的”，已记入部署目录hardware_acceptance.json；摄像头朝天花板的局限不再影响显示验收结论。用户准备验证手机→MIDI→灯屏→实体演奏→I²S录音→手机回传链路；提供C大调4秒音阶与90BPM《小星星》单旋律测试MIDI，位于 `E:/gaoyun_builds/midi_examples_20261030/`，均已用生产JS解析器核对。实体键盘最低音仍待核对，当前固件60起，曲谱只指引不自动发声；蓝牙/灯带/录音回传尚未宣称实物验收。

> **2026-10-30 20:44 UI新版已执行一次SRAM烧录，显示/功能待现场验收。** 用户明确要求“按照烧录流程烧录”。IPv6只读扫描1个GW5AST-138B/138C（ID0x0001081B），无其他Programmer进程；deploy_verified.py在写前重新校验105输入/123引脚/五类时序全部通过。部署目录 `impl/deploy_runs/20261030_204315_R16_stereo_hc07_F14_F16`；operation2、PROGRAMMER_EXIT=0、User Code **0x00001521**、Status **0x00026230**、programming_status=sram_programmed；本地/远端位流SHA256均 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`。Flash未写、没有自动重试/推送/改音频。摄像头preview.jpg朝向天花板，没有拍到屏幕，不能证明显示正常或异常；hardware_acceptance.json标为待用户现场确认。当前板上应为本轮F14TX/F16RX、F13灯带/PAN/LFO/双声道/蓝牙与录音导出新版，不再是14:03旧固件；实际蓝牙/实体音域/灯带/整曲DDR未验收。下方“未部署”均为写板前历史。

> **2026-10-30 20:36 最终统一候选审计通过，未部署。** `E:/gaoyun_builds/R16A_build_20261030_201520` 于20:35:12退出0；审计 `audit_20261030_203534_639478.json`：105输入工作区/快照哈希一致、123/123引脚一致、setup/hold均0端点、无负路径/审计错误，七时钟全部达标，`timing_closed=true`。最差setup/hold/recovery/removal/pulse为 **+0.472/+0.133/+0.335/+0.338/+0.361ns**，pixel51.722/50MHz，DDR104.959/100MHz；3路OSER10复位完整检查且无豁免。原5条FX setup违例已消除。位流 `impl/pnr/2_ui_touch_hub.fs` 39707831bytes，SHA256 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`。保留place3/route1，不靠盲换模式/放宽频率收敛。最终APK仍为202948（SHA见下一条），蓝牙 **F14 TX／F16 RX**、灯带 **F13**。功能与回归索引 `functional_evidence.json` 已保存。Gowin已结束，本轮浏览器及HTTP辅助进程已关闭，不需重跑相同输入。未烧录/推送/修改音频板；板上仍14:03旧固件，真实安卓/HC-07、实体最低音、灯带映射及整曲DDR验收均待执行。

> **2026-10-30 20:31 Codex：唯一统一候选仍在布局，未部署。** 当前为 `E:/gaoyun_builds/R16A_build_20261030_201520`，Gowin PID40292；综合已完成，布局Phase2完成，尚无最终STA结论。实际cmd.do确认place3/route1/timing/correct_hold1、唯一combined CST/SDC。综合Logic70214/138240、寄存器44534、BSRAM89/340。D盘曾满：201235因误将系数include头文件独立登记为Verilog而失败（登记已纠正，头文件保留）；201321因磁盘满停止，证据均保留。仅按用户授权删除3个本轮安装压缩包，释放314912768字节，解压工具和工程保留。最终APK更新为 `impl/phone_apk_20261030_202948/FPGA-Performance.apk`，SHA256 `3ae03bf7555c305ceaa9c89322062ee5bc0487d36e7b7df2e644bf28d2566c71`；页面320/360/412px验证无横向溢出。浏览器原生桥模拟已走通16事件上传及12帧单声道下载；不属于真实蓝牙验收。接续先核对唯一进程与日志，完成后严格audit_build.py审计，禁止相同输入另起Gowin。RTL冻结，未烧录/推送/改音频工程。

> **2026-10-30 20:10 Codex：功能整合完成，最终候选待构建/审计，尚未部署。** PAN(CC10/91/92)/最终L:R双波形与相位/F13直接24灯/LFO14bit与FX流水线保留；HC-07双向ACK、曲谱整包校验/去重、DDR原PCM离线127tap低通96k→8k单/双声道回传和安卓RFCOMM壳已实现。用户要求蓝牙改近邻 **F14 TX→RXD、F16 RX←TXD**，已核对原理图第7/19页及无DDR引脚冲突；E13方案作废。APK `impl/phone_apk_20261030_200836/FPGA-Performance.apk` 已签名验证，未手机实测。双速串口8回复、31板端会话、337精确FIR样本、I²S→DDR→11帧FIR端到端、14 JS用例、网关真ACK、PAN/LFO/导航/视频/灯带回归通过。统一Gowin尚未启动，下一步冻结源后唯一候选、五类时序与全部引脚审计。详见 [蓝牙协议与验收](doc/HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md)。不推送/删除/改音频/自动烧录；192337中断产物保留。

> **2026-10-30 19:35 Codex 整合进行中：用户要求全部问题（含新提供HC-07手册）解决后再统一构建一次。** PAN/左右波形与L:R相位/F13直连24灯/LFO 14bit及FX输入流水线已改并通过相关仿真，尚未部署；提前启动的192337构建已按用户要求停止并保留，非最终候选。安卓轻量壳+HC-07双向通信/录音降采样仍待实现。详情见 [整合状态](doc/STEREO_HC07_UPDATE_2026-10-30.md)。所有历史失败证据保留，未推送/烧录/删除/修改音频工程。


> **后续EDA工作先读：** [EDA经验与执行规则](doc/EDA_LESSONS_2026-10-30.md)，集中记录RAM推断、唯一CST、DDR时钟边界、流水时序修复、模式归因边界和减少重复构建的要求。该文件已持久落盘，不代表已确认写入Hindsight独立长期记忆。

> **2026-10-30 最新实板状态：** 用户确认“这一版成功上板”。已执行唯一一次 UI SRAM operation 2，部署 `impl/deploy_runs/20261030_140337_R16_local_performance_ui_sram_20261030`；PROGRAMMER_EXIT=0、User Code `0x00009B47`、Status `0x00026230`，本地/远端 SHA256 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`。验收原话见部署目录 `hardware_acceptance.json`。首次摄像头抓拍偏黑，但用户随后现场确认成功；不再依据该单帧认定黑屏。此确认只覆盖成功上板，未扩展为灯带逐键、实际音域或 DDR 整曲录音逐项验收。Flash 未动、未推送、未删除、未改音频板。下方旧“未烧录/目标板未确认”均为历史。

> **2026-10-29 接续入口：** 灯带安排按 Dock 原理图确定为 FPGA J16→板载 U15→J24 pin 3，C14 保留调试 UART；每帧为1个板载黑像素+24个外接像素。normal `R16A_build_20261029_222234` 与 debug `DEBUG_R16A_build_20261029_223907` 均通过五类时序和122/122引脚审计。normal SRAM `--check-only` 通过，SHA256 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`，未访问工程机、未烧录。23:12 重跑的25像素WS2812串行与白键/MIDI键态回归通过（`performance_led_serial_20261029_231227_998673`、`performance_keys_20261029_231227_990124`）。仍待实物确认J24接线/供电、32键实际音域、DDR整曲录音；不推送、不删除、不修改音频板。

> **23:42 最新本地验证：** 再次执行 normal SRAM `--check-only`，99个构建输入哈希无偏差，五类时序通过、122/122引脚一致、位流哈希不变。25像素串行/键位映射/曲谱提示/录音显示/命令/MIDI/Note仲裁/PCM与DDR读回/进度/协议/调度器回归全PASS。重复全页预览因耗时中止，部分文件保留、无仿真进程；先前完整预览仍有PASS结果。实物 JTAG 目标和 J24 接线未确认，尚未烧录。

> **历史记录口径：** 本文件下方较早条目中的 121 引脚门槛、C14 灯带待确认和旧构建句柄均只描述当时状态，已由本入口的 J16/J24、122 引脚和最新构建结论取代；旧文件和产物保留，不作为当前门禁。

> **最新只读设备探测：** 工程机通过 IPv6 SSH 在线，Programmer CLI `--scan` 识别到 1 个 `GW5AST-138B/GW5AST-138C`（ID `0x0001081B`）和 Gowin USB Cable FT2CH。扫描没有写 SRAM/Flash；在确认该器件就是 UI 板且确认 JTAG/灯带接线后，才可执行 SRAM operation 2。

> **2026-10-29 22:55 接续：演奏灯带引脚安排已按官方 Dock 原理图修正并通过双构建审计。** FPGA J16 驱动板载 WS2812B U15，U15 DOUT 经 J24 pin 3 接外部灯带；pin1 GND、pin2 NC、pin4 5V（0.45 A max）。演奏链每帧发 1 个板载黑像素 + 24 个外部像素；J16 已作为独立 `performance_led_data` 顶层端口，C14 保留 debug UART。PWM 颜色受限流约束，灯带文档见 `doc/UI_PCB_DEBUG_UART_PINOUT.md`。串行链路仿真 `performance_led_serial_20261029_213654_873950` PASS；完整renderer预览 `performance_preview_20261029_213935_466000` 的 7 个25像素帧/1200位和921600屏幕像素 PASS，PNG已检查。正常构建 `R16A_build_20261029_222234` 与诊断构建 `DEBUG_R16A_build_20261029_223907` 均以唯一 combined CST/SDC 完成，审计均 122/122 引脚匹配、五类时序零违例；余量和哈希详见 `doc/LOCAL_PERFORMANCE_STATUS_2026-10-29.md`。未烧录/推送/删除或修改音频板。实物J24接线、灯带电气/亮度、键盘音域、DDR录音仍未验收。**

> **21:11 历史 SRAM 只读预检（已被22:55后的构建和引脚复核取代）：** `191907` 候选曾通过 `--check-only`，当时只审计121个引脚；没有访问工程机或写板。当时发现的 C14 冲突来自旧方案，后来已按 Dock 原理图将灯带独立接到 J16，C14 保留调试 UART。当前状态见本文件顶部，未烧录。

> **21:13 本地录音边界回归补齐：** PCM 捕获深度 3/16、左右声道次序/有符号采样、背压、容量、溢出、排空、断源及命令优先级通过（`impl/performance_pcm_20261029_211338_276125`）；生产 I²S 发送器到独立时钟 UI 接收器的逐对采样测试通过。长曲目进度 1047 项参考通过（`impl/performance_progress_20261029_211338_277479`）。加上上一轮 DDR adapter 全链路读回回归，软件侧录音/进度用例已覆盖。当前只读 SRAM 预检仍通过，物理接线与断电状态未确认，继续不烧录、不推送。

> **20:58 历史构建与回归记录（已被22:55候选取代）：** `191907` 曾通过121/121引脚和五类时序审计；旧位流及资源数据仅供追溯，当前以顶部 `222234` normal 与 `223907` debug 构建审计为准。旧 `185326` 综合后中断且保留。后续修正了灯带端口、引脚数与串行证据，详见最新入口和状态文档。
>
> 当前回归全部 PASS：`performance_keys_20261029_194846_759722`、`performance_led_serial_20261029_194846_765328`、`performance_cue_20261029_194846_766005`、`performance_command_tests_20261029_194846_811607`、`performance_store_20261029_194932_141837`（两组异步时钟、137 对生产 I²S 样本逐帧读回、故障恢复）、`performance_display_20261029_194932_141544`、`navigation_20261029_194932`、`trace_tests_20261029_194932_169522`、`performance_notes_20261029_205545_646398`、`performance_scheduler_tests_20261029_205545_632768`，以及 MIDI/协议 Python 回归。当前 renderer 预览 `performance_preview_20261029_202447_714069/result.json` PASS，`performance.png` 为 1280×720，720 行×1280 像素、7 个 24 灯帧/921600 有效像素，已人工查看。预览工具改为逐行写出并严格恢复/校验完整像素，原始超时目录 `performance_preview_20261029_195017_613814` 保留。
>
> `impl/R16A_build_20261029_191907/functional_evidence.json` 汇总上述构建、位流、预览和回归路径。仍不烧录、不推送、不改音频、不删除：实体键盘最低 MIDI 音仍是临时 `PERFORMANCE_BASE_NOTE=60`，DDR 实板容量/校准、WS2812 电气接线和整首录音硬件验收未完成；手机/蓝牙只保留接口，音频板由队友负责。
> **19:40 接续恢复：** 先前 `impl/R16A_build_20261029_185326` 不是成功结束：PID 37860 已不存在，日志只到 Routing Phase 0，只有综合产物，没有 P&R 时序/位流；该目录 99 个输入哈希均匹配，未删除。按同一最终源码启动唯一新候选 `impl/R16A_build_20261029_191907`，构建 PID 17256、exec 19784；真实日志已完成综合并进入布局 `[30%] Placement Phase 2 completed`，进程仍存活，未收结果。实际 `cmd.do` 已核对 `-place_option 3`、`-route_option 1`、`-correct_hold 1`；约束文件为唯一 `ui_touch_hub_combined.cst`。综合资源为 Logic 61259/138240、Register 38370/139095、BSRAM 86/340；仍需完整五类时序审计。综合日志报告 `performance_led_white_mapper` 实例 swept；白键映射与 24 灯串行有 RTL 回归及生产 renderer 预览证据，但该综合警告与实体灯带行为仍须实板核实，不据仿真宣称硬件验收。继续不并行 Gowin、不烧录、不推送、不改音频、不删除。



> **2026-10-30 17:55 ZCode 接续：队友 LFO 协议修复 8f46f98 已同步入库并通过回归，但两轮全量构建均差 5 条同源 setup 违例（-0.084~-0.126ns），均未烧录；板上 14:03 版仍为旧 LFO 编码，待随用户其他改动一并收敛。** `git pull --ff-only` 将 integration/dual-138k-uart-phase1 从 ea28bf3 快进到 8f46f98（队友 TEENAGERKILLER 10-29 20:55 "encode LFO SysEx as MIDI-safe 14-bit values"：value 改 14bit 拆两个 7bit、route source 移 value[9:8]，协议文档 §2 同步更正）。pull 时 AI_COLLABORATION_LOG.md 与本地未提交条目冲突，已合并保留双方全部条目（stash 已清）；工作区其余脏文件原样未动，未提交、未推送。验证：lfo_sysex_tx.v blob=ff99eea；tb_lfo_sysex_tx 于 sim/work_lfo_sync_20261030 全 PASS（含新增 T6：OSC A Level/LFO1/+127 → 0x017F）。
>
> 两轮唯一隔离构建（PID 38296/22064，先后串行、无并行 Gowin）：impl/R16A_build_20261030_165924 与 R16A_build_20261030_172142，快照 lfo_sysex_tx.v sha256=0dcf9ecf…（修复版）。审计 audit_20261030_172103_048998.json / audit_20261030_173930_618017.json 结果逐位相同：setup 5/hold 0，全部同源 u_knob_spi/param_id_3_s0 → u_render/u_fx_state/packet_external_value_{0,2,3,4}（-0.126×3、-0.084×2）；recovery/removal/pulse 通过、122 引脚全匹配、七时钟 Fmax 达标（pixel 49.686、ddr_user 110.36/100）。timing_closed=false，禁止部署。
>
> 关键结论：① 相同输入两轮 Fmax/违例逐位相同（且 222234 与 191907 位流同为 SHA 9F842D53），本机 Gowin P&R 同输入确定性再次实证，重跑相同输入无意义；② 222234 全零版 worst setup 仅 +0.140ns，LFO 修复 9 行（不在关键路径）挪动全局布局把该族老路径挤过线，属布局敏感非结构缺陷。收敛建议：方案A fx_state 入口对 knob param_id/value 事件寄存一拍（10-19 参数库整体寄存先例）并重跑 fx_lfo/knob 回归；方案B 试 place_option 3→2（当前 build.tcl 第 8-9 行 place3/route1）。板上 14:03 部署版快照 lfo=4a89beca 为旧编码，音频板未实现接收端故暂无实害，但联调前必须换新。队友 main 另有 4 新提交至 5224279（立体声振荡器+全局声像、恢复板载 PT8211、音频流水线）未合并。本轮无活跃 Gowin/ModelSim 进程残留。

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
> normal/debug SDC已按高云GW5AST-138B官方例程拆开DDR100/400异步组，并按本机SUG940 5.5.1加入扩大及pixel/bit-clock专项report_timing，未降低频率或豁免域内/OSER10 reset。尚未跑下一候选；142528仍拒绝部署。下一步先补录音请求失败/自动停止恢复及真实状态显示、三源Note仲裁和容量硬门槛，再相关回归、唯一完整构建/五类审计。键盘最低音仍待现场MIDI采样，C14分配仍待回复；不依赖它们的本地工作继续。未推送/烧录/删除或改音频工程。

> **15:01 接续核对：** 已再次fetch队友main，仍d4338fb。E19的MIDI音符号原样进入合成器、解析器接受全部16通道；UI发送约定通道1，不能写成E19只收通道1。仓库仍无实体32键最低音，60只是临时参数；不需要原理图，但实体灯安装/验收前必须采样实际键号。只读源码证据impl/audio_note_contract_20261029_145705，协议文档已纠正。
>
> **DDR官方约束新证据：** 高云官网DDR3 ZIP内含GW5AST-138B专用1:4工程，其SDC将100MHz用户时钟与400MHz PHY设异步组（源头/逐项对照/SHA在doc/DDR_OFFICIAL_TIMING_REFERENCE_2026-10-29.md与impl/ddr_official_reference_20261029_145035）。此前142528最差25条setup全部跨此边界（4条到下降沿、21条到上升沿），先前“同组”指导已被官方示例纠正。normal/debug SDC已按官方分组，域内时序/OSER10 reset未豁免，尚未重跑P&R，不代表时序闭合或DDR实物验收。无新活跃Gowin；preview144245/session70866/kernel34760仍运行，hex持续增长，RTL冻结等待收回。未烧录、推送、删除或改音频源。

> **14:48 已收回Gowin结果（覆盖下条运行状态）：** 142528已退出0，session31668结束，无活跃Gowin。最终121处引脚全部匹配，combined CST修复得到实证；但233setup、pixel45.907/50MHz、最差-7.508ns（DDR PHY read_rclksel/hold_gen及校准相关），hold0，recovery/removal/pulse最差+0.324/+0.287/+0.451ns；removal摘要前25条未含全三路OSER10，审计仍拒绝。完整审计`audit_20261029_144607_910780.json`；最差25条全在DDR内部，须获取更广路径报告与IP时序说明，不能任意false-path或再盲目换route模式。该快照也早于按钮移动，不部署。新preview144245/session70866/kernel34760仍真实运行并输出全帧；尚未PASS。无新Gowin，不推送不烧录不删除，目标未完成。

> **2026-10-29 14:44 当前恢复入口：** 实际UI仍本副本，音频只读。发现Gowin两份CST只读取最后DDR份，旧135029/140630所有UI引脚被自动重派，均禁止部署；已改为normal/debug各唯一combined CST+唯一SDC，build_isolated做预检，audit_build新增最终121处引脚核对（含差分），旧验收032336的50处正向通过，错误140630负向拒绝。DDR400/100MHz显式时钟组与录音命令RAM输出寄存已加；录音store142445、normal/debug串口142445、WS2812逐位141945、导航144322、演奏按钮144134均PASS。唯一Gowin仍`impl/R16A_build_20261029_142528`、PID33588、exec31668在routing（真实cmd.do确认place3/route1、combined CST）；勿并行启动。该快照早于下述按钮移动，后续即使STA通过也不能直接部署。旧整帧预览142720在部分画面发现演奏控件被全局导航覆盖，已只停止该preview kernel并保留全部产物，不能写PASS。控件已移至y136..168；新完整预览`impl/performance_preview_20261029_144245_230550`、exec70866、kernel34760，增加真实导航+触控+命令联动、7帧4032位LED解码及全帧，仍在运行，恢复先收取结果。C14分配已问用户尚无答复，源码暂按PERFORMANCE_LED_ENABLE=1专用灯带，不能动态切UART；未部署。详见状态文档最新条目；目标未完成、不推送不删除不烧录。

> **2026-10-29 14:13 接续：** 实体键盘协议已按最新远端 `origin/main=d4338fb` 再核对，E19=31250/8N1/3.3V标准MIDI，音符号原样进入合成器；仓库没有32键最低音。工作分支音频源旧于E19接入，参考必须用`git show origin/main:...`。UI的60仍临时配置，待实物校准。DDR wrapper/PLL/IP/正常诊断顶层已接，旧“尚未接顶层”已过时；修正前135029退出0但109setup/120hold及recovery/removal负裕量，禁止部署。最新导航135807、完整normal/debug与串口135828、键映射135930、演奏命令135936均PASS。唯一新Gowin候选`impl/R16A_build_20261029_140630`、PID6804、exec27762正在布局，先核对真实进程不并行Gowin；UI DDR显式时钟/异步约束仍待补齐及验证。详见`doc/LOCAL_PERFORMANCE_STATUS_2026-10-29.md`。不改音频、不烧录、不推送、不删除，目标未完成。

> **13:35 本地演奏 UI 控制更新：** 演奏页顶栏加入播放/暂停/继续/停止图标，新增 `performance_touch_controls.v` 做触摸边沿和坐标门控；命令接入共享 `performance_command_decoder` 状态，因此后续手机 PLAY/PAUSE/STOP 与本地控制一致。`performance_command_tests_20261029_133453_862938`、`navigation_20261029_133336`、`trace_tests_20261029_133336_612787`均PASS，`git diff --check`通过。未运行Gowin、未烧录/推送/删除；UI DDR IP/实体容量仍未确认，不能宣称整首录音或实板可用。音符协议仍按队友仓库标准MIDI 21..108，实体键盘最低音无记录，`PERFORMANCE_BASE_NOTE=60`仅待实物校准。

> **13:23 最终验证（覆盖下条状态）：** 新增 `performance_recording_subsystem.v` 已加入 normal/debug GPRJ；137 个 VIS V2 左右 PCM 样本穿过生产 `i2s_visual_rx`、真实采集/存储子系统与队友 d4338fb 原版 DDR adapter，逐帧读回一致，DDR cmd/data 两种握手次序均被覆盖。证据 `impl/performance_store_20261029_131716_863132`。存储传输、2053 帧尾掩码、错误/超时/source-loss 均通过；演奏页 `navigation_20261029_131949`、I²S `i2s_tests_20261029_131949_887871`、工程/串口 `trace_tests_20261029_131949_891687` 均PASS。UI top仍未接DDR IP/pins，实物容量/校准无证据；UI工具版本1.9.11、队友IP模板1.9.12。本轮未构建/烧录/推送/删除，目标未完成。

> **12:57 验证收尾补充（覆盖下条运行句柄）：** navigation_20261029_125443 已退出0且PASS，含当前源码SHA256；正常/诊断完整源码编译与串口回归 trace_tests_20261029_125622_446219 已退出0且PASS；git diff --check通过。句柄34083已结束，不再等待。本轮所有已启动测试均已收回结果，无待观察测试句柄；本轮未启动Gowin。整体本地演奏/整首录音目标仍未完成，继续入口见下条及详细状态文档。

> **2026-10-29 12:55 本地演奏接续，目标未完成。** 已重新 fetch 音频队友 main=d4338fb；E19 为 MIDI 音符原样输入，无物理最低音事实。UI 顶层增加可配置 PERFORMANCE_BASE_NOTE（60 仅临时值），32 键与 24 白键灯映射分离；修正导航文字页号、拖键立即抬起粘键、出屏/切页释放、停止/清空/重播提示清理，Python 默认32键。长曲目进度新增48拍除法器，1047 大整数参考通过。新增 PCM 录音前端，独立 FIFO3/16 及生产 I²S发送→独立相位UI接收→PCM写流全通过，但尚未接入整首外存，UI不再把录音请求显示为真实保存状态。15起始音/1920MIDI/480重叠、I²S/原可视化、正常诊断源码与串口回归通过；最终导航回归句柄34083/目录navigation_20261029_125443恢复先查真实状态。旧105439已完成但审计失败：494 setup、-27.684ns、20.971/50MHz，禁止部署。本轮无Gowin、不烧录、不推送、不删除，音频代码未改。详细现状、证据、DDR1.9.12与本机1.9.11兼容边界及下一步见 doc/LOCAL_PERFORMANCE_STATUS_2026-10-29.md；勿把小FIFO当作整首录音或把C19当作Note输入。

> **2026-10-29 演奏功能 EDA 自查：音频任务已取消，以下旧音频运行条目均为历史，不恢复音频工作。** 实际 UI 源码仍在本副本，保留所有脏改动、不推送、不烧录、不删除。`090153` 已退出1，PR0004/19825未布线，CLS98%，不能继续等待旧会话23053。其实际place3/route2与成功UI基线相同；确认调度器RAM展开，旧完整层次占48262FF且无BSRAM。修正单同步读/单写无复位RAM过程后，同参数1024容量独立综合由48266FF/27235LUT/0BSRAM降为131FF/178LUT/3BSRAM，证据`impl/performance_eda_probe_20261029_105142/resource_comparison.json`。ModelSim容量5/8/1024/4096生命周期回归及Python MIDI/协议通过。正常/诊断build.tcl明确小写gowinsynthesis、place3、route1、timing_driven1；route1仅是质量优先选择，不能声称它是已证根因。新唯一完整UI候选`impl/R16A_build_20261029_105439`、PID28528、exec35235，此记录时尚未完成；先核对真实进程/日志，不并行Gowin，通过后仍须五类审计。详见`doc/UI_PERFORMANCE_EDA_AUDIT_2026-10-29.md`。实体灯带/手机/音频录制回传未完成实机联调。

> **2026-10-28 04:01 恢复更新：UI焦点已通过用户现场验收。** 用户确认“高亮已正常恢复并保留”，验收记录位于原副本部署034258的focus_acceptance.json。旧音频候选034258在会话续接后已无Gowin/监督进程，日志停Placement Phase1、无fs/最终STA，状态已记interrupted_no_exit_code，不能当作运行中或合格。未自动重烧、未删除文件。为避免终端任务被会话中断带走，构建器新增--background，经WMI隐藏独立启动；当前唯一音频候选为整合副本impl/AUDIO_XY_build_20261028_040056_136483，Gowin PID13268、监督PID20512，启动日志impl/audio_launcher_20261028_040055_308690/supervisor.log。通过文件/真实进程核对，不依赖已失效exec句柄。音频未部署，JTAG仍UI，五类审计后再请用户切换；目标未完成。**

> **2026-10-28 03:44 接续：UI 新版已实际部署，音频构建中。** UI候选 `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261028_032336` 已完成五类时序审计，73输入哈希一致、0 setup/hold端点、pixel50.879/50MHz；setup/hold/recovery/removal/pulse余量+0.346/+0.203/+0.184/+0.497/+0.453ns。用户确认JTAG接UI板后，仅一次SRAM2部署 `20261028_034258_R16_OSC_AB_FOCUS_UI` 成功，PROGRAMMER_EXIT=0、User Code0x00009A81、Status0x00026230，双机SHA256 `0322CBA28DC6004AB1CA697DE30F5874B46C4C2A3C2140B7B0DC9933F6D06DB2`；摄像头画面正常，用户已实物确认“高亮已正常恢复并保留”；验收原话保存在该部署目录focus_acceptance.json。原副本与构建输入完全相符，新整合副本20个输入只有CRLF/LF差异，故使用原副本严格审计/部署，不弱化哈希。音频首候选034022在Tcl因不支持-inc_place退出，尚未综合；脚本改用全新目录保证无增量，并修正生成Tcl原始字节哈希。当前唯一Gowin为整合副本impl/AUDIO_XY_build_20261028_034258_711468，PID24760、session61358，综合已完成、正在布局；不得另起Gowin。预览session43904已退出且PASS，完整921600像素/4096逐拍检查及64输入哈希通过，preview.png已查看；模拟PCM，不是实板音频证据。两板独立供电、仅一根JTAG，音频烧录前仍须用户切换并确认目标。Flash未动，音频未烧录，目标未完成。**

> **2026-10-28 03:35 接续入口：两板OSC A/B与焦点修复仍进行中，尚未部署。** 用户保留X=OSC A/Y=OSC B并接受两板更新，随后授权拉取合并队友main并由工程机顺序烧两块板SRAM。main两次fetch均为29939e2（提交时间10月26日23:02，非服务端推送时间）。独立整合副本D:/github/synth1_9_18-osc-ab-20261028，分支integration/osc-ab-main-20261028，合并4b4cca1已推送，保留E19键盘、AB21/C19及弯音/滑音。原工作区脏文件未覆盖。当前UI唯一构建在原副本impl/R16A_build_20261028_032336，gw_sh PID33488、session98565，最近Placement Phase2；先核对进程，严禁并行Gowin。音频尚未启动构建。真实路由1329焦点检查、完整renderer的2638对A/B/26椭圆像素与最终输出隔离、247971时钟非零音频基线比较均通过；FIR用数学模型，不能代替加密IP/硬件验证。详细证据见新副本doc/OSC_AB_XY_FOCUS_2026-10-28.md。两板一根可切换JTAG USB线、独立供电，烧录前确认连接目标。Flash暂停、只SRAM2、五类时序全过、超时不自动重烧。**

> **2026-10-28 01:13 焦点修正版已完成第二次 SRAM 部署。** 提交 `bbb38f4` 将实体 motion/press 优先级置于旧触摸选择之后，完整构建 `impl/R16A_build_20261028_005621` 五类时序全零，最差 setup/hold/recovery/removal/pulse `+0.625/+0.166/+0.114/+0.519/+0.361ns`。位流 SHA256 `9AA00FC4F6B62CEDE91E054712D1EB0F9ADBAFF6950C23079CE5183D7D208B99`。部署 `impl/deploy_runs/20261028_011226_R16_UI_FOCUS_FIX_20261028`，operation2、PROGRAMMER_EXIT=0、User Code `0x00006D89`、Status `0x00026230`，Flash未操作。李萨如图仍严格绘制真实左右声道采样：同相/单声道是直线，正交输入才是椭圆，禁止伪造；现场需确认音频板是否真的输出了相位差的独立L/R。**

> **2026-10-28 00:25 本轮已构建并部署 UI SRAM，等待现场功能验收。** 最终候选 `impl/R16A_build_20261028_001108`：73输入文件无快照偏差，clk_pixel 50.374MHz，setup/hold/recovery/removal/pulse 最差余量 +0.149/+0.207/+0.212/+0.504/+0.361ns，五类违例全零，`timing_closed=true`。位流 SHA256 `E0E51202991CE576EC1C14C846333240E51E712DCD34B637DF4481135F827819`。唯一一次 UI SRAM operation2 部署 `impl/deploy_runs/20261028_002411_R16_UI_CONTROLS_LFO_STEREO_20261028`：PROGRAMMER_EXIT=0、User Code `0x00002ADC`、Status `0x00026230`，工程机回传 `preview.jpg` 已看到正常合成器画面；Flash未操作。现场尚未验证新LFO动态值、SYSTEM步长、旋钮白色焦点、DISPLAY缩放、第三窗正交椭圆或第六窗左右电平，不能把抓拍写成这些功能已验收。**

 > **2026-10-28 00:03 接续状态：首候选impl/R16A_build_20261027_235709已退出（综合EX0337：tri0弱驱动与保留寄存器冲突），未生成可部署位流。** 已把新增可选tri0端口改为显式wire，测试台补齐零配置；同时导航/BIND触摸不再抢回旧焦点，保持衰减不低于当前峰值。最新000024正常/诊断完整编译、319实体/共享银行、67893LFO、13746显示区域、6136视频、I2S/导航/SPI/ASCII均通过；000124新增52776个FX基线像素及两个可见白圈焦点切换通过。234517立体声六窗完整预览已通过4096逐拍/921600像素及全部输入哈希，已查看；旧三页设置预览900s超时，前两帧完整保留，不能称全套通过。最终显式端口版本正在生成DISPLAY单页session8262、立体声六窗session77812，另有频谱回归81794。无活跃Gowin；下一步提交兼容修正/推送，再唯一新候选构建。详细需求/证据见doc/UI_CONTROL_IMPROVEMENTS_2026-10-27.md。未部署、板上仍为上一轮验收版；Flash未动。**

> **2026-10-27 23:55 新一轮控件/可视化修复进行中，尚未构建或部署，不能复用上一轮验收。** 实际源码仍 D:/github/synth1_9_18/2_ui_touch_hub，需求检查点3daf062已推送。LFO绝对曲线/+127默认深度、实体方向/独立焦点、32项1/2/4/8步长、DISPLAY及图内缩放、左右独立RMS/峰值保持已实现。319步长/焦点/共享银行检查、67893 LFO数值、13746显示区域像素、86FFT/3591DFT/49152相位像素（含真实正交椭圆）、四档波形/历史时间、导航/视频/I2S/SPI/UART/MIDI/SysEx回归通过。设置页/立体声六窗预览session17898/57105正在运行，目录234517；先检查状态，不重复启动。首张controls_01_08_review.png已查看。新版FX音频CC原本未对接，K31/32现仅与可见Reverb Size/Delay Feedback共用UI银行，原始UART ID保留；不能宣称FX音频或音频板新调制语义已联调。完整证据/限制见doc/UI_CONTROL_IMPROVEMENTS_2026-10-27.md。未删除文件，无活跃Gowin；下步完成预览、提交推送，再按授权唯一构建/五类时序/SRAM2；Flash暂停。下方“六窗升级已完成”属于上一轮基线。**

> **2026-10-27 22:56 本轮最终状态：六窗完整升级已完成并通过用户现场验收，原话“六窗响应、旋钮联动都正常”。以下旧“当前/进行中/未烧录”均为历史。实际源码D:/github/synth1_9_18/2_ui_touch_hub，RTL检查点0ae2e6a已推送。最终构建impl/R16A_build_20261027_223956，67输入哈希一致、五类时序零违例，余量setup/hold/recovery/removal/pulse=+0.695/+0.200/+0.201/+0.497/+0.453ns，pixel Fmax56.229/50MHz。仅一次SRAM operation2部署impl/deploy_runs/20261027_225244_R16_I2S_SIX_WINDOW_UPGRADE，PROGRAMMER_EXIT=0、User Code0x0000D385、Status0x00026230、双机SHA256 1794286747E826D0116430014E17EDC4D8628CAE83AFA28B5EBA38B596FC1212。完整预览223706的921600像素/4096逐拍检查通过且与旧预览零字节差异。用户验收原话与证据已保存部署目录hardware_acceptance.json。无本轮活跃构建/仿真/部署；未操作Flash、未删除文件。详细范围/误差/限制/回归见doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。下一次不得据下方历史失败候选再次烧录。**

> **22:40执行状态：0ae2e6a已提交并推送。唯一Gowin候选impl/R16A_build_20261027_223956，gw_sh PID57140、外层session65121，正在综合；新预览session93990仍运行。当前源不要修改；先核对这些进程/日志，不重复起构建。新增完整编译/串口回归impl/trace_tests_20261027_224024_709676通过，旋钮专项impl/knob_integration_20261027_224024_694694、session20012运行中。ssh gaoyun hostname返回DESKTOP-FDEVSGP。升级未烧录。**

> **2026-10-27 22:37 当前入口：第三候选221458已正常退出，但完整时序不合格，禁止部署（46.978/50MHz、11 setup、最差-1.287ns；其余四类通过）。已按实际11条路径把相关性游标乘/除/坐标相加分为三拍，并把峰值/RMS/保持幅值选择与dBFS编码分拍。最新metrics_tests_20261027_223640_711807（新增held dBFS检查）、i2s_tests_20261027_223517_840724（新增512坐标/有效脉冲/断线复位）、navigation_20261027_223640、video_alignment_20261027_223517_870292均通过。最新完整预览audio_upgrade_preview_20261027_223706_531567、session93990运行中；旧221458预览已完整通过且与211752逐字节一致。无活跃Gowin，下一步提交/推送后启动唯一新候选并完整审计；升级尚未烧录，仍须时序、SRAM与现场验收。**

> **2026-10-27 22:25 当前状态（下方所有旧“当前/最终”条目均为历史）：六窗完整升级仍在执行，未烧录。实际源码在 D:/github/synth1_9_18/2_ui_touch_hub，最新代码64fc7d6已推送。唯一Gowin候选impl/R16A_build_20261027_221458，PID52788、session26316，正在布局；先核对进程/日志，不可另起第二份。第一候选212132最终STA不合格；第二候选220133在完整STA前主动停止，其综合USB跨域负裕量不能作为最终STA失败证明（SDC已设置异步组）。当前已实现dBFS三拍、数字译码分拍与USB状态两级同步，生产I2S整链路、数字逐拍像素、导航/视频、32旋钮回归均通过。对应完整预览impl/audio_upgrade_preview_20261027_221458_244681、session28302正在输出，4096图元检查已过；旧不完整PPM均保留。板上最后部署仍20261027_190826_KNOB_SPI_BURST_C14_ASCII。必须完整五类时序通过后才SRAM operation2，Flash暂停，SSH烧录超时不重试；现场六窗验收尚未完成。详情doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。**

> 本轮最终验收通过（2026-10-27）：用户现场回复“三、四、五窗及原波形、电平均正常”。当前 UI SRAM 为 `20261027_162828_I2S_LIVE_PHASE_SPECTRUM_HISTORY`，构建 `impl/R16A_build_20261027_161611`；第三窗真实 L/R 相位、第四窗 1024 点 FFT 相对对数频谱、第五窗 32 频带/64 列历史均正常，第二窗波形和第六窗前两条电平无回退。第一窗继续 EXAMPLE / NOT LIVE，等待 Note/Velocity 回传；削波未做现场验收。五类时序违例全零，余量 +0.622/+0.147/+0.102/+0.497/+0.453 ns，像素 Fmax 61.072/50 MHz，64 个输入哈希一致。operation 2、PROGRAMMER_EXIT=0、Status 0x00026230、User Code 0x0000AE7E；双机 SHA256 `D3A66CCFBFEFA56CA9EE79C3397A862A4345571454B422F4B46A924225A706D4`。本轮只有一次 SRAM 烧录，无运行中的本轮构建/部署，Flash 未动。验收原话保存在部署目录 hardware_acceptance.json；详细文档见实际副本 doc/I2S_LIVE_PHASE_SPECTRUM_HISTORY_2026-10-27.md。以下候选进度为历史，以本条为准。

> 16:17 当前状态（覆盖下方旧状态）：唯一 Gowin 候选 `impl/R16A_build_20261027_161611`（PID 51036）正在综合。`160027` 因综合估算发现幅度/对数链为 30 级、最差 -8.752 ns，已主动停止布线并保留全部产物，未完成最终时序审计、未部署。已将幅度、峰值、对数编码、缩放和柱高存储分拍；70 帧/3078 DFT 频点（误差 7.854 LSB）、192 个独立柱高比较通过，最慢 43128 拍=0.86256 ms；导航、6136 项视频和串口/完整编译回归通过。新模拟预览 `impl/spectral_preview_20261027_161621` 运行中。板上仍为上一轮验收版；时序审计、SRAM 部署和本轮现场验收待完成。

> 16:10 状态：当前唯一候选为实际副本 `impl/R16A_build_20261027_160027`（PID 58952），正在布线。综合为 33913 LUT、14790 寄存器、22 BSRAM，FFT 已映射为块 RAM。最新预览 `impl/spectral_preview_20261027_160027/frame.png` 已通过 4096 次新图逐拍检查与 921600 像素完整输出并查看；仅为模拟 PCM 证据。最新导航 `navigation_20261027_160326`、视频 `video_alignment_20261027_160326_128724` 及数值/I2S/串口回归全部通过。时序审计、SRAM 部署和本轮现场验收尚未完成，板上仍为上一轮已验收波形/电平版本。以下旧候选状态均以本条为准。

## 2026-10-27 当前入口：I2S 波形与电平

> 16:00 更新：首候选 `154902` 因 FFT 同时双写造成约 32768 个存储位展开为寄存器，已主动停止布局并保留全部产物，未部署。FFT 改为分拍读写的双缓冲单写 RAM；70 帧/3078 DFT 频点、相位 24576 像素、I2S（新增短槽配对拒绝）、原波形电平均通过。当前唯一候选为实际副本 `impl/R16A_build_20261027_160027`，PID 58952；新预览 `impl/spectral_preview_20261027_160027` 运行中。先核对进程/日志，不重启第二份 Gowin；时序审计和 SRAM 部署待完成。

> 新一轮进行中：用户选择先接第三、四、五窗真实 I2S 显示，第一窗继续示例。上一轮检查点 `73cb6b7` 已提交并推送。左右声道、相位双缓冲、1024 点 Hann FFT 与 32 频带/64 列历史已实现，数值和回归通过。当前唯一 Gowin 候选为实际副本 `impl/R16A_build_20261027_154902`（PID 47420）；时序审计与部署尚未完成，不要重复启动构建。新整帧预览 `impl/spectral_preview_20261027_155111` 运行中。详见实际副本 `doc/I2S_LIVE_PHASE_SPECTRUM_HISTORY_2026-10-27.md`。板上仍是上一轮已验收版本。

> 本轮最终验收通过（用户现场确认）：音频板补烧后第二窗真实波形正常；用户进一步确认第六窗 LEVELS 前两条电平“都正常响应”，即随发声上升、停音后回零。本轮“真实波形与电平”任务完成。第一、三、四、五窗仍为 `EXAMPLE / NOT LIVE`，不能写成六窗全部实时；第三条削波保持仅有 RTL 仿真验证，未做现场削波测试。当前 UI SRAM 为部署 `20261027_150557_I2S_LIVE_WAVEFORM_LEVELS`，SHA256 `68DEE3B30642D10632F6D383856BB45661FA0EFFDF94DA3EF16D5FDCB38082CE`。音频板由用户在另一电脑烧录，音频位流 hash 未提供；本会话没有再次构建或烧录。以下条目为历史排查记录，其中的待答问题已由本条验收结论取代。

> 最新现场进展：用户确认此前音频板未烧录带 VIS 回传的版本，随后已在另一台电脑完成音频板烧录，反馈“2 窗口和 4 窗口正常”。第二窗可作为波形反馈；第四窗仍是 `EXAMPLE / NOT LIVE` 频谱示例，不能计为真实频谱验收。新抓拍 `D:/github/synth1_9_18/2_ui_touch_hub/impl/i2s_after_audio_program_20261027_153131/preview.jpg` 显示第二窗已由琥珀色等待线变为青色有效采样中线，抓拍瞬间电平为空。当前唯一待答问题：第六窗 LEVELS 前两条是否随发声上升、停音回零。音频固件具体 hash 未提供，烧录由用户在另一电脑完成；本会话未重新烧录 UI、未构建或烧录音频板。整轮现场验收仍待第六窗确认。

> 音源确认更新：用户回复测试时音频板“没有声音”。当前唯一待答问题改为“刚才通过实体 MIDI 键盘、仅旋钮/UI，还是板载测试音触发”。已烧录 UI 的 `note_on_req/note_off_req` 都固定为 0，仅调参数不能产生音符；队友 `origin/main` 音频代码的实体键盘入口为 E19，而本地整合音频副本仍是旧 AB21 MIDI 入口，不能混用接线或视为同一已烧录版本。当前音频源码走外接 MAX98357A，关闭板载 NS4263；I2S 时钟独立于音符持续运行，因此无声仍不能单独解释 UI 等待基线。未修改 RTL、未重复烧录。

> 现场反馈更新：用户回复“波形和电平两项都没有响应”，**现场音频验收未通过**。新抓拍 `impl/i2s_no_response_20261027_150948/preview.jpg` 显示 VISUALIZATION 第二窗为琥珀色等待基线、第六窗为空，表明未进入完整有效采样显示状态；不能仅凭该图区分缺 BCLK、缺 WS、接线或音频板固件。已问唯一待答问题：音频板耳机/扬声器是否确实有声音。已核对音频 `origin/main` 与本地源码都有 `VIS_BCLK=R19/VIS_LRC=U21/VIS_DIN=R17` 镜像，但未找到音频板实际加载该版本的部署证据；本会话仅确认 UI 板 SRAM 部署。未重复烧录，未修改 RTL。

> 最新结果 15:07：`impl/R16A_build_20261027_145452` 已完成并通过完整审计，`timing_closed=true`；五类时序余量为 `+0.601/+0.196/+0.319/+0.497/+0.453 ns`，像素 Fmax 56.823/50 MHz，61 个源码与快照哈希一致。新位流已且仅烧录一次 UI 板 SRAM：`impl/deploy_runs/20261027_150557_I2S_LIVE_WAVEFORM_LEVELS/`，`PROGRAMMER_EXIT=0`、Status `0x00026230`、User Code `0x0000FE58`，双机 SHA256 `68DEE3B30642D10632F6D383856BB45661FA0EFFDF94DA3EF16D5FDCB38082CE`。摄像头确认合成器页正常显示；已询问用户切到 VISUALIZATION，验证第二窗波形与第六窗前两条电平的发声/停音响应。**现场音频验收仍待回复**，不能仅据静态抓屏宣称通过。其余四窗为示意。Flash 未操作，无运行中的本轮 Gowin 构建。

> 最新状态 14:55：`143844` 剩 1 个 setup 违例（字符译码，-0.371 ns），未部署。已改为同步字符 ROM，8192 项与原译码逐项一致，65536 字形格点及音频/导航/视频回归通过。当前唯一 Gowin 构建是 `impl/R16A_build_20261027_145452`，PID 59032；先看实际进程/日志再恢复。`145330` 因旧版 HDL 循环上限前端退出，已改显式常量表，不改时钟、不添加时序例外。Flash 暂停。

> 最新状态 14:39：第三候选因旧字符寄存器布局锚点不再存在而在约束检查退出，正常/诊断 CST 已将这一条旧导航锚点保留为注释，外部引脚及九个串行器复位锚点不变。当前构建是 `impl/R16A_build_20261027_143844`（第四候选），尚未部署。65536 字形格点回归通过，字体流水调整前后 921600 像素整帧逐字节完全一致。

- 实际接续工作副本为本目录 `D:/github/synth1_9_18/2_ui_touch_hub`；`D:/github/gaoyun/2_ui_touch_hub` 的 RTL 尚未同步 I2S，不要用旧副本反向覆盖。
- 用户本轮明确只先完成第二窗真实波形和第六窗真实电平，已确认 I2S 三线与公共地接好。其余四窗暂留标注示意。
- 已修正 I2S 16 位槽末位/WS 切换错误：旧生产环回得到 0 个样本，新版 141 个样本逐值匹配，流中复位与断线恢复通过。128 点/10.7 ms 波形、峰值/平均绝对幅度/削波显示、导航、6136 项视频对齐和串口回归通过。
- 首候选 `140338` 因 4 个 setup 违例/最差 -0.695 ns 拒绝部署；按实际跨区布线与 154 扇出路径做本地文字页状态隔离、译码扇出限制，并补齐波形相邻样本连线。回归再次通过。第二候选 `impl/R16A_build_20261027_141808` 正在 P&R；**时序审计与新 SRAM 部署待完成**。此前 13:18 版本虽成功烧录但有上述接收缺陷，不代表现场真实音频验收。
- 详情与原始文件备份见 `doc/I2S_LIVE_WAVEFORM_LEVELS_2026-10-27.md`。Flash 暂停，不删除文件。

- 14:34 更新：第二候选 `141808` 仍有 2 个 setup 违例（最差 -0.687 ns），未部署。字形行/列查表重新分拍、混色移入原输出级，保持字体和视频总延迟；关闭被导航完全覆盖的旧 HUD 无效绘制入口但保留源码/控制接口。导航/视频/音频专项通过，第三候选 `impl/R16A_build_20261027_143358` 正在构建。恢复时先看该构建进程与日志，不并行重启 Gowin。

## 2026-10-27 01:05：实体旋钮动作诊断版已通过时序门禁并部署 SRAM

- 诊断串口 C14 使用 115200 8N1；收到实体旋转事件时打印 `KNOBnn CW/CCW`，按压与释放分别打印 `PRESS/RELEASE`，空闲不打印旋钮事件。旋钮编号按 UI 四区映射，物理/参数表见 `doc/TXE8148_EC11_SPI_INTEGRATION.md`。
- 修正追踪帧共用事件标志导致的旧按键动作重放；旋转事件清空旧按键动作，PC 解码按动作字节区分旋转和开关边沿。方向状态使用单个寄存器，诊断假设一次操作一个旋钮；多旋钮同一扫描批次的并发方向尚未作为验收目标。
- `python tools/test_touch_trace.py` 通过，包括串口波形、完整帧解码、方向、错帧恢复和主/诊断 RTL 编译。
- 隔离构建 `impl/DEBUG_R16A_build_20261027_005555/` 审计通过，源码和快照一致，setup/hold/recovery/removal/pulse width 全部无违例；最差余量依次 `+0.633/+0.156/+0.608/+0.334/+0.448 ns`，`clk_pixel` 实测 Fmax `52.855 MHz`（要求 50 MHz）。位流 SHA256 `DA3A01208EB321513418C8495C7BD0E15C3E4CA6C9DBFDA17E09611F4D2FEEDF`。
- 已以 `--target sram` 烧录，目录 `impl/deploy_runs/20261027_010415_KNOB_ACTIVE_EVENTS/`；工程机识别 `GW5AST-138B`，`PROGRAMMER_EXIT=0`，Status `0x00026230`，User Code `0x0000881D`，远端 SHA256 匹配。摄像头抓屏显示正常六窗 UI；此证据不代替现场 32 个旋钮方向/按压逐项验收。Flash 未操作。
- 后续做布局收敛时优先先定位单一关键路径并做一次有证据的最小调整；减少无目标的连续 P&R 试跑。安全边界不变：负 setup/hold/recovery/removal/pulse slack 或低于约束时钟要求都不能部署。

## 2026-10-26 22:25：外接 PCB/UI 调试 UART 已分配并部署 SRAM

- 用户指定 UI 板 `C14` 为 UART TX、`E13` 为 UART RX；约束为 3.3 V LVCMOS。C14 镜像 U15 监视流，诊断构建下输出 115200 baud trace；E13 暂时仅作输入脚保留，没有命令协议。
- 接线：C14→USB-TTL RXD，E13←USB-TTL TXD，GND 共地；USB-TTL 适配器必须是 3.3 V TTL，禁止 5 V/RS-232。C14/E13 不复用音频链路 AB21，也不改变旋钮 SPI。
- 修正诊断工程漏登记的导航/LFO 源文件，并为诊断顶层建立独立 CST；`build_isolated.py --debug` 支持诊断构建，`audit_build.py` 可审计普通及诊断位流。
- 诊断构建 `impl/DEBUG_R16A_build_20261026_221313/` 审计通过：源码快照一致，Setup/Hold 违例 0，Recovery/Removal/Pulse Width 通过，worst setup `+0.074 ns`；SHA256 `D5A8492AC467CDD4C2C0183FCBB37FE593DAE93E84756B640D70B525981F5080`。
- 该诊断位流已部署至 UI 板 SRAM：`impl/deploy_runs/20261026_222436_UI_PCB_DEBUG_UART_C14_E13/`，`PROGRAMMER_EXIT=0`，Status `0x00026230`，User Code `0x0000233D`。现场串口解码和旋钮输入日志仍待用户验证。

## 2026-10-26 20:55：PCB bank 映射修正版已烧录 UI 板 SRAM

- 使用提交 `0699cac` 对应位流执行 `tools/deploy_verified.py --target sram`，部署目录为 `impl/deploy_runs/20261026_205443_TXE8148_PCB_BANK_MAPPING_3V3/`。
- 工程机 `10.136.125.157` 识别 `GW5AST-138B (0x0001081B)`；SRAM 编程完成，`PROGRAMMER_EXIT=0`，Status `0x00026230`，User Code `0x00008733`，用时 23.14 s。远端 SHA256 与本地一致：`37FB1A5409AF62F51B32BBC04146C125D09F7FB55320527128E22FC76D25E541`。
- `preview.jpg` 已抓到正常 UI 画面。当前待用户现场确认旋钮旋转是否改变对应参数；按压持久选中态仍未接入全局 UI。

## 2026-10-26 20:47：根据 32 旋钮 PCB 原理图修正 GPIO bank 映射（待 SRAM 部署）

- 用户提供的 `32旋钮PCB.zip` 原理图确认：每颗 TXE8148 的 48 路 GPIO 按三组 16 路 bank 接线，`P0/P1 -> A`、`P2/P3 -> B`、`P4/P5 -> SW`。此前按 `A/B/SW` 三个连续 GPIO 读取是错误根因，导致实体输入没有反应。
- RTL 已改为芯片内 `k=0..15` 使用 `A=GPIO[k]`、`B=GPIO[16+k]`、`SW=GPIO[32+k]`；四区参数 ID 映射保持不变。
- PCB 原理图还确认 Type-C VCC 网络为 `3.3V-IN -> VCC`。此前文档写成 5 V 入口已更正；键盘板不得直接接 5 V，用户已确认当前改接 3.3 V。
- 新构建 Setup/Hold 违例均为 0，恢复/移除/脉宽门禁也通过；最差恢复余量 `+0.201 ns`。位流 SHA256 `37FB1A5409AF62F51B32BBC04146C125D09F7FB55320527128E22FC76D25E541`。
- 当前新位流尚未烧录；上一版 `8C2617...FB71` 仍在板上。提交、推送和 SRAM 部署需在本条目之后完成，Flash 继续暂停。

## 2026-10-26 12:18：实体按压选中态接入试跑已撤回

- 试验把 `knob_select_valid/select_id` 接入 `touch_event_router.selected_param_id`，目标是让实体按压更新屏幕旋钮高亮。
- 试跑 P&R 产生 2 条 setup 违例，最差 Slack `−0.339 ns`（另一条为导航既有路径），因此未提交、未部署，已恢复到提交 `3b8807b` 的闭合版本。当前板上仍是 `8C2617...FB71` 对应的旋转采样/四区映射版本。
- 后续如果继续做按压视觉反馈，应只把选择 ID 接到旋钮局部渲染路径，避免改变全局触摸选择寄存器和导航布局。

## 2026-10-26 11:27：四区映射位流已烧录 UI 板 SRAM

- 使用提交 `3b8807b` 对应位流执行 `tools/deploy_verified.py --target sram`，部署目录为 `impl/deploy_runs/20261026_112652_TXE8148_EC11_SPI_QUADRANT_MAPPING/`。
- 工程机 `10.136.125.157` 识别 `GW5AST-138B (0x0001081B)`；SRAM 编程完成，`PROGRAMMER_EXIT=0`，Status `0x00026230`，User Code `0x00004262`，用时 22.73 s。远端 SHA256 与本地一致：`8C2617DB216CA7F930818B1032EE1ED520D2B214AB53613A025525518281FB71`。
- `preview.jpg` 已抓到正常 UI 六窗画面，证明新位流正在板上运行。该抓屏不证明 32 个 EC11 的现场方向和按压逐项验收；Flash 未操作。

## 2026-10-26 11:05：TXE8148 SPI 采样与四区映射版本时序闭合（待 SRAM 部署）

- 本轮修复 `rtl/knob_spi_intake/knob_spi_rx.v` 的 SPI 采样时序：TXE8148 在 SCLK 下降沿更新 SDO，接收器改为在高电平阶段结束时采样稳定后的同步数据。保留两颗 TXE8148、32 个 EC11 的 A/B/SW 解码与 0..127 参数值输出。
- 物理编号映射已按面板四区收口：旋钮 1..8=左上 OSC A，9..16=左下 ENV/Global，17..24=右上 OSC B，25..32=右下 Filter/FX。完整 ID 表见 `doc/TXE8148_EC11_SPI_INTEGRATION.md` 和 `doc/HARDWARE_WIRING_PINOUT.md`。
- 当前旋转事件已进入 `param_merger` 的 SPI 参数路径；触摸路径保持原逻辑。实体按压的 `select_valid/select_id` 已在 SPI 接收器中识别并保留，但本轮没有并入高扇出 `btn_tap`/渲染选择路径，因为该接法使既有环境曲线路径出现 22 条 setup 违例。按压到持久 UI 选中态需另做低扇出、时序收口的实现，不能把本轮称为按压视觉反馈已验收。
- Gowin 全量 P&R 已通过：Setup 违例 0、Hold 违例 0，最差 Setup Slack `+0.595 ns`；位流 `impl/pnr/2_ui_touch_hub.fs` SHA256 `8C2617DB216CA7F930818B1032EE1ED520D2B214AB53613A025525518281FB71`。`tb_lfo_sysex_tx` 全部检查通过，`tb_midi_uart_tx` 全部协议检查通过。
- 当前仅完成源码构建与仿真证据，尚未把该新位流写入 UI 板 SRAM；Flash 继续暂停。部署前需继续执行 `tools/deploy_verified.py --target sram`，并核对工程机编程返回码、远端哈希和摄像头画面。实体 32 路旋转/按压仍需现场逐项验收。

## 2026-10-26 04:48：TXE8148 32 路旋钮版本已烧录 SRAM

- 使用提交 `76a7fb9` 对应位流 `impl/pnr/2_ui_touch_hub.fs` 执行 `tools/deploy_verified.py --target sram`。
- 工程机 `10.136.125.157` 识别 `GW5AST-138B (0x0001081B)`；SRAM 编程 100%，`PROGRAMMER_EXIT=0`，状态码 `0x00026230`，User Code `0x000014A6`，用时 22.68 s。
- 部署审计目录：`impl/deploy_runs/20261026_044804_TXE8148_EC11_SPI_76A7FB9/`；远端 SHA256 与本地一致：`E0246684F67C3D155519FCA57182DD2619F45E2F2D482269FDFCCF6F7FCDF54F`。
- `preview.jpg` 已抓到正常 UI 六窗画面，说明该位流已在板上运行。当前只完成画面和编程链路确认，32 个 EC11 的每个旋钮、按键和方向尚未做逐项物理输入验收。Flash 未操作。

## 2026-10-26 04:32：TXE8148 双芯片 32 路 EC11 SPI 接收器已综合通过

- 当前工作区把旧的 16 通道 ADC SPI 接收器替换为双 TXE8148 轮询接收器：两路独立 `CS#`、共享 `SCLK/SDI/SDO`，连续读取两颗芯片的 `0x20..0x25` 输入端口寄存器。
- 32 个 EC11 按每三个 GPIO 的 `A/B/SW` 顺序解码：第一颗芯片从 `P0.0/P0.1/P0.2` 对应旋钮 1 开始，第二颗芯片从 `P0.0` 对应旋钮 17 开始。旋钮值为 0..127，初值 64；首次扫描仅建立基线。
- 新引脚约束为 `2CS#=A15`、`1CS#=B20`、`SCLK=B21`、`SDI=B17`、`SDO=D17`、`INT#=A18`、`RESET=D14`。键盘板 VCC 走独立 Type-C 5 V 入口，FPGA 不驱动 E16。
- 本地 Gowin 构建 `2_ui_touch_hub/impl/pnr/` 完成综合、布局、布线、时序和位流生成；Setup/Hold 违例均为 0，`clk_pixel` Fmax 50.656 MHz，位流 `2_ui_touch_hub.fs` SHA256 `E0246684F67C3D155519FCA57182DD2619F45E2F2D482269FDFCCF6F7FCDF54F`，长度 35,627,521 bytes。
- 这只是源码构建证据，尚未烧录；5 V 键盘板的 TXE8148 与 FPGA 之间的电平适配仍需硬件侧实测确认。

## 2026-10-26 03:30：最新 LFO SysEx 位流已恢复并实屏确认

- 显示器电源接好后，最终 LFO SysEx 位流在 `impl/deploy_runs/20261026_033031_LFO_SYSEX_V2_CURRENT_AFTER_POWER_FIX/` 重新烧录成功：`PROGRAMMER_EXIT=0`、状态码 `0x00026230`、User Code `0x000030AF`、SHA256 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`。
- `preview.jpg` 已看到正常的 UI 六窗可视化页面；此前黑屏来自显示器电源连接问题，当前最新版本已在板上运行。Flash 未操作。

## 2026-10-26 03:24：黑屏 A/B 对照未指向 LFO SysEx 位流

- 当前 LFO 位流已写入 SRAM（User Code `0x000030AF`），但摄像头画面为黑屏/偶闪。随后把已验收的 R17B HD-font 位流写回 SRAM，运行 `20261026_032317_R17B_HD_FONT_RECHECK` 同样成功，但摄像头仍为黑屏。
- 已将当前 LFO 位流恢复到 SRAM，运行 `20261026_032427_LFO_SYSEX_V2_RESTORE_CURRENT`，哈希 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`、`PROGRAMMER_EXIT=0`。
- 现有证据不支持把黑屏归因于 LFO SysEx RTL；下一步应现场检查 HDMI 线、显示器输入源、板卡复位/供电和显示链路。当前不标记 UI 实屏验收通过。

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
# 2026-10-26 23:26 — PCB knob event serial trace (Codex, timing gate failed)

- Added diagnostic-only `knob_spi_rx` event outputs for each decoded quadrature step and both active-low switch edges. The normal parameter update and press-to-select paths remain unchanged.
- Kept the 64-byte trace frame/version/checksum. Reserved bytes 59/60 carry action `1=CW, 2=CCW, 3=PRESS, 4=RELEASE` and zero-based physical knob index. Host decoder renders only `KNOBnn CW/CCW/PRESS/RELEASE`; idle scans generate no panel log.
- `python tools/test_touch_trace.py` passed; direct host decoder checks printed all four expected forms. The full debug Gowin build completed and produced `impl/DEBUG_R16A_build_20261026_231122/impl/pnr/2_ui_touch_hub_debug.fs`, but audit `audit_20261026_232620_303411.json` failed: 23 setup endpoints, worst setup `-0.962 ns`, pulse-width worst `-0.352 ns`. No deployment was attempted; the new bitstream must not be programmed until timing is closed.
- One earlier build failed because the diagnostic CST lacked the navigation anchor documented in its comments; adding the hierarchical anchor allowed P&R to complete but did not close timing. This was a failed repair attempt, not a passing result.

## 2026-10-27 14:08 接续原会话：I2S 波形与电平候选

- 原会话“检查串口旋钮数据刷新逻辑”（01a17933-4ae0-7f02-b5ef-194131117c1b）实际继续工作位于 `D:/github/synth1_9_18/2_ui_touch_hub`。本目录旧工程尚未同步 I2S，不能据本目录文件判断已部署源码，不能用旧副本覆盖新结果。
- 用户确认三根 I2S 与公共地已接好，本轮明确只先完成真实波形与电平；其余四窗后续接入。
- 原 13:18 UI SRAM 烧录成功，但接收功能仿真此前未跑完。已复现旧接收器解出 0 个左声道样本；修正 16 位 I2S 槽末位与 WS 边界，生产发送器 141 样本逐值环回、复位和断线恢复通过。
- 第二窗改 128 点/约 10.7 ms 的同步 RAM 历史；第六窗改真实峰值、平均绝对幅度和削波保持。显示专项、导航状态保持、6136 项视频对齐与串口回归通过。
- 候选 `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_140338` 正在构建，尚未通过时序审计或部署。完整说明在同副本 `doc/I2S_LIVE_WAVEFORM_LEVELS_2026-10-27.md`。Flash 暂停，不删除或覆盖旧产物。

## 2026-10-27：旋钮 SPI 连续帧和普通固件 C14 日志修复（仅源码/仿真，尚未部署）

- 用户确认原接线 A15/B20/B21/B17/D17/A18/D14，串口 C14、115200 8N1。实际修复在 D:/github/synth1_9_18/2_ui_touch_hub；gaoyun 旧 RTL 不反向覆盖。
- 已定位普通顶层关闭 ASCII 导致 C14 镜像 MIDI；SPI 接收器又使用 24-clock 逐端口帧，未复用已实测成功的 64-clock 连续读。原文件哈希与 161611 已部署快照一致。严格引脚级模型在旧代码上复现“expected 64 clocks, got 24”。
- 已修复连续读、普通顶层默认 ASCII、多旋钮/开关事件逐个发出、两颗芯片独立断线处理；现有共享参数增量入口保留，按压不增加业务功能，SPI 状态仅首次/变化时打印。
- 专项 1366 个 SPI 帧、139 行精确 ASCII 校验、32 路 CW/CCW/PRESS/RELEASE、触屏与实体交替/限幅、单颗断开重连全部通过。既有串口回归和独立参数中枢回归通过。曲线套件 tb_curve_touch_editor 另报 Pending curve MIDI did not drain，其编译输入未含本轮修改 RTL，不能列为全绿。
- 未运行 Gowin、未生成新部署位流、未烧录、未操作 Flash、未删除文件。板上最后有记录的部署仍为 20261027_162828_I2S_LIVE_PHASE_SPECTRUM_HISTORY。工作副本 AGENTS.md 要求明确请求后才进行 Gowin 构建；时序审计和实板联动验收仍待后续完成。
- 完整证据与备份位置：实际副本 doc/KNOB_SPI_BURST_FIX_2026-10-27.md；原文件备份 impl/knob_fix_backup_20261027_164910_066。

## 后续执行更新：用户已明确授权构建与条件 SRAM 烧录

- 用户回复“是，构建并在审计通过后烧录 SRAM”，已满足工作副本 AGENTS.md 的明确请求要求。
- 当前唯一隔离构建：D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_185258，gw_sh PID 47704。综合与引脚约束解析完成，正在布局；source_manifest.json 已保存。恢复工作时先核对进程与日志，不重复启动 Gowin。
- 尚未产生最终时序结论，尚未调用烧录器。上文“未运行 Gowin”是授权之前的状态，以此更新为准；Flash 继续暂停。

## 2026-10-27 19:08–19:09：旋钮 SPI 连续帧/C14 ASCII 修正版构建并部署

- 用户已授权“构建并在审计通过后烧录 SRAM”。唯一隔离构建 `impl/R16A_build_20261027_185258` 完成，Gowin exit 0；64 个源文件快照与工作区一致。
- 五类审计通过：clk_pixel 56.905/50 MHz；setup +0.622 ns；hold +0.191 ns；recovery +0.201 ns；removal +0.497 ns；pulse width +0.453 ns；setup/hold 违例 0，负路径 0，OSER10 recovery/removal 三路均有报告，无 reset 例外。
- 仅执行一次 UI SRAM operation 2：`impl/deploy_runs/20261027_190826_KNOB_SPI_BURST_C14_ASCII/`。远程 `PROGRAMMER_EXIT=0`，User Code `0x00001766`，Status `0x00026230`；本地/远程位流 SHA256 `76E2B27474035033C464B72036230395BB29A1BDF15B95C928480BD9406C4DA5`。现场预览 `preview.jpg` 已抓取，屏幕画面正常。Flash 未操作。
- 当前待用户实测：打开 C14 串口（C14→USB-TTL RX、GND 共地、115200 8N1）后复位 UI 板，期望首次看到 `U1 SPI CONNECTED`、`U2 SPI CONNECTED`；随后旋转/按压应输出 `Kxx CW/CCW/PRESS/RELEASE U1/U2`。空闲不应每秒打印。SPI 连接状态只在首次检测或状态变化打印。
- 硬件状态仍需用户现场验证，不能用预览图替代旋钮事件验收。若要验证断线状态，先断电再改变接线并重新上电，避免带电插拔。

## 2026-10-27 20:06–20:12：I2S 音频总览与频谱主频标记升级（源码/仿真，未部署）

- 用户批准开始升级，按比赛演示优先改动实际副本 `D:/github/synth1_9_18/2_ui_touch_hub`。第一窗从静态 NOTES/KEYS 示意改为 `AUDIO OVERVIEW`，使用真实 I2S PCM 的峰值、平均绝对幅度和削波保持；窗口标题说明同步更新。
- 第四窗新增 `peak_band[4:0]`，由 32 个真实 FFT 频带发布结果比较得到，黄色竖线标出当前能量最高频带。未增加 dBFS/RMS/LUFS 等未经校准的标签。
- 验证：I2S 可视化回归、FFT 3078 点浮点 DFT（最大误差7.854 LSB）、192频带、8/64/3号测试频点主频带、全顶层编译、旋钮/C14回归均通过。
- 本轮没有运行 Gowin P&R，没有生成或烧录新 UI 位流。当前稳定 UI 仍为上一轮已验收 SRAM；升级源码与测试证据见 `doc/I2S_AUDIO_OVERVIEW_UPGRADE_2026-10-27.md`。

## 2026-10-27 21:23：六窗完整升级源码已推送，隔离构建中（目标尚未完成）

- 实际源码仍在 D:/github/synth1_9_18/2_ui_touch_hub；3150b91 已推送。早期 e5f8182 的条形总览不是整轮目标，已扩展为真实能量圆/左右状态/数值、过零触发双缓冲波形与峰值保持、相关性/BAL、精确 FFT 峰值 Hz/幅度中心、历史色标、真正 RMS/dBFS/crest/clip。断线不再回退假键盘。
- 独立数值验证：16 个连续立体声窗口 RMS/峰值逐值一致，dBFS 最大误差0.226 dB；71 FFT帧/3591频点/224频带/7帧峰值与中心频率；高端46.875kHz防溢出。触发迟滞/完整双缓冲/自动触发/重连通过。旋钮1366帧139行、导航页保留、6136视频对齐通过。
- 唯一 Gowin 构建 impl/R16A_build_20261027_212132（gw_sh PID33716，外层命令session82151）。构建尚未退出，不能启动第二份；须按真实进程/日志核对状态，再审计五类时序。
- 整帧仿真 impl/audio_upgrade_preview_20261027_211752_968052（session58379）已通过4096项每拍能量/相位/频谱/历史像素对齐，正在输出921600像素。三分钟超时的旧预览211309已经终止，部分PPM不可作为完整画面。
- 当前升级未烧录，Flash未动。板上最后已验收部署仍为20261027_190826_KNOB_SPI_BURST_C14_ASCII。完整定义/限制/测试路径见 doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。现场验收待本轮构建/审计通过后进行，不能把目标标记完成。

## 当前继续入口（2026-10-27 22:02，覆盖上面的21:23构建状态）

- 六窗升级仍未完成，不能标记goal complete。全部功能源码、独立数值/整链路/像素/导航/旋钮回归和完整预览已完成；时序收敛、SRAM上板、现场验收尚未完成。
- 第一次构建212132已退出且不合格：25.302/50MHz，105 setup，最差-19.522ns，路径u_metrics/tmp_peak_l到hold_db10。禁止部署该位流。其余四类+0.149/+0.201/+0.497/+0.453ns。完整audit_20261027_215716_545084.json保留。
- 已把原对数函数替换成三拍audio_dbfs_encoder，常数ROM取代32位乘除。32769种有效PCM幅值全部逐拍校验通过，最大0.315dB；16窗口RMS/相关/保持和生产I2S整链路回归通过。
- 当前唯一活跃隔离构建：D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_220133，gw_sh PID40640，外层命令session45828。source_manifest含66个输入且工作区一致。先核对这个进程/句柄/日志，不可因为观察超时另起Gowin。
- c8d9631已经推送（Git push需http.sslBackend=openssl，http.version=HTTP/1.1，http.postBuffer=52428800；schannel此前多次Empty reply）。与本轮无关的根目录脏文件保持原样。
- 预览：impl/audio_upgrade_preview_20261027_211752_968052/preview.png，完整921600像素和4096每拍能量/相位/频谱/历史对照均通过，已人工查看。模拟PCM，不是实板。预览在对数流水线替换前生成，数值语义已由穷举/字形回归证明一致。整帧原PPM及早先超时不完整PPM全部保留。
- 最新测试：metrics_tests_20261027_215958_053975；i2s_tests_20261027_215850_217355；spectral_tests_20261027_211752_887973；knob_integration_20261027_211825_465226；navigation_20261027_211943；video_alignment_20261027_212213_225013。
- 工程机ssh gaoyun hostname已验证可达；目前未烧录任何升级位流，板上仍190826旋钮稳定版。待当前构建完成必须audit_build五类全通过，再tools/deploy_verified.py --label R16_I2S_SIX_WINDOW_UPGRADE --fs <该构建>/impl/pnr/2_ui_touch_hub.fs（默认SRAMoperation2）。SSH烧录超时禁止自动重试，Flash暂停。
- 详细定义、误差、抽取波形6kHz混叠边界、失败时序与测量限制见doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。现场需要用户确认六窗随真实声音变化且旋钮仍正常；不可把仿真或摄像头静帧当作音频响应证明。

> **2026-10-30 23:3x 接续（Bene）:** 修复 `sim/tb_performance_cue.v` 与 `ui_top_renderer` 的实例失配（新增 `performance_mode` / `performance_local_mode_valid` / `performance_local_mode` 端口），并把测试台事件音改写为 `PERFORMANCE_BASE_NOTE(7'd29)` 同参化的 7'd29 以保持键位映射（避免 BASE_NOTE 默认 60 时的越界/映射偏差）。回归通过：`impl/performance_cue_20261030_232624_787123` PASS（1000 个曲谱时钟位置、精确 MIDI 键、暂停冻结、Note-Off 不提示、停止清空）。源码仅改该测试台，未动 RTL；本轮无 Gowin、无烧录、无推送。后续接续：跟弹模式必须等实体琴键输入（新需求，尚未实现——需把 `performance_key_state` 的实体 MIDI 键态接到引导提示通路，而不是仅触摸/遥控播放）。

