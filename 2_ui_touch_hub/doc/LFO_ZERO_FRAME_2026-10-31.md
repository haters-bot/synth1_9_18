# LFO 全零路由：网表根因、修复与SRAM部署记录

## 14:51 最终构建与SRAM完成，实板功能待用户复测

生产源码已本地提交 **a6c4a8b261eb89fb90fc0e0d11f7e4c2b85c1ba6**（未推送）。正式工程 `2_ui_touch_hub.gprj`、顶层 `ui_touch_hub_top`，构建 `E:/gaoyun_builds/R16A_build_20261031_143345`，实际place3/route1/timing/correct_hold1；相比此前部署041417，109项输入清单中只有 `rtl/midi_uart_tx/lfo_sysex_tx.v` 改变。

`functional_evidence.json`已保存binding/renderer/sender三份文件的Git blob、工作区、构建快照哈希及规范化换行的内容一致性；sender与官方网表回归的输入哈希一致。没有误用旧工程、错误顶层或旧sender。源码修复没有改变source/depth状态：修复前后绑定/q/sh始终为1/127；改变的是综合后的组帧读取，由0000恢复为017F，即UART两个数据字节02 7F。

`audit_20261031_144906_544956.json`：109输入全部一致，124引脚一致，7时钟达标，setup/hold/recovery/removal/pulse五类无违例，最差余量分别为 **+0.033/+0.140/+0.372/+0.287/+0.451ns**；pixel50.081/50MHz、DDR112.974/100MHz。setup余量窄，不能把本次通过解释成后续每次必过。资源Logic64348/138240（47%）、Register34535/139095（25%）、BSRAM99/340；相较上一版增加428 Logic、30 Register。位流39857421字节，SHA256 **74E75DD438B0D77FC30B57CE5D202F2269B1E063C567DAB4B2DFA3F2DBBFCD1E**。

按用户此前“完成到烧录完毕”授权，14:49只读再次确认1个UI138B/旧UserCode966后，唯一一次执行 `deploy_verified.py --board ui --target sram`。部署目录 `impl/deploy_runs/20261031_144944_UI_LFO_ROUTE_STATIC_GATE_20261031`：双端SHA一致，SRAM operation2、PROGRAMMER_EXIT=0、CODEX_PROGRAM_COMPLETE、manifest状态sram_programmed，写后只读复核UserCode **0x00009C50**、Status **0x00026230**；completion_record.json保存完整证据。Flash和音频工程未操作，无自动重试，无探针位流写入。

抓拍已人工查看，只看到工作台和键盘，没有可读UI屏幕，因此显示和LFO实板功能仍标为待用户验收。接下来请用户在9C50上重新执行BIND LFO1→Detune→松手，UI TX应为 `F0 7D 4F 02 7F F7 F0 7D 7E 00 00 F7`；Level对应56。此处UART字节是RTL/官方网表已观察及新版预期，**尚不是新版实板TX实测**。先前长时间未收敛的直接原因是仅用RTL仿真及STA验证，未覆盖综合后的功能不等价；可复现官方网表回归现已加入，最终仍须实际UI TX闭环。

下方14:33/14:30及更早条目是排查过程，当前状态以本节为准。所有原失败证据保留。

## 14:33 验证收齐，准备正式构建

正式源码（sender SHA256 `b2f97bdfcd5a6b99ee1ab67ac43a428f566d6e94342be8963888b4e5a5ade2d4`）的可复用网表回归已完成：`E:/gaoyun_builds/lfo_route_gate_test_20261031_142950_216897/result.json`，RTL和官方网表均PASS，源码快照匹配。107帧覆盖真实触摸绑定6/13、LFO1/2/3重绑、32次AMOUNT减量至−127、解绑保留深度、无UP超时提交及曲线126→80。关键实际字节如下：

```text
LFO1 → Detune : F0 7D 4F 02 7F F7
LFO1 → Level  : F0 7D 56 02 7F F7
LFO2 → Detune : F0 7D 4F 04 7F F7
LFO3 → Level  : F0 7D 56 06 7F F7
Level depth−127: F0 7D 56 07 01 F7
Clear Level    : F0 7D 56 01 01 F7  (source=0、depth仍为−127)
Timeout Detune : F0 7D 4F 06 7F F7
每个批次结尾  : F0 7D 7E 00 00 F7
```

协议增强回归 `impl/midi_lfo_protocol_20261031_143029_654639` 已全PASS；53目标以不同深度、四种source初始化，逐帧核验，覆盖旧的重复深度无法排除的切片错位。完整renderer、真实31250及仲裁等五项142920_842985均PASS。本轮首次批量回归调用使用了不存在的测试名，在读取测试文件时失败、未启动仿真，空证据目录仍保留；修正为实际现有测试名后运行的是142920_842985，不掩盖失败。

已再次fetch，integration远端仍3664276、无分叉。沿用用户此前“完成到烧录完毕”的明确授权，下一步提交指定文件、唯一正式UI normal工程构建，全部审计通过才SRAM2。当前尚未开始正式构建或再次烧录，板上仍00000966，最终功能仍须新版实板UI TX复测。

## 2026-10-31 14:30：已在 Gowin 网表复现，并验证最小修复

用户补充曲线抓包：ID `33` 的值从 `7E` 逐步变化到 `50`，每次都伴随正确的 `F0 7D 48 00 04 F7` 和 Commit。曲线动态值及固定相位同步值4均正常，不能再归因于通用UART后半帧全部清零。逐帧转录保存在下面原版网表目录的 `user_curve_capture_20261031.txt`。

隔离探针使用生产 router、binding、sender、MIDI FIFO/UART，经原始触摸包触发真实绑定；没有向配置口注入路由。计时缩短，UART加速至5 Mbaud，其他引脚自动分配，**仅供仿真，禁止烧录其位流**。Gowin V1.9.11.03 Education 官方 `-gen_verilog_sim_netlist 1` 导出的 `.vo`，配官方 `gw5a/prim_sim.v`，进行布局布线后功能仿真（未标注SDF，不是时序仿真）。

| 证据 | 原写法 | 常量切片选择写法 |
|---|---|---|
| 目录 | `E:/gaoyun_builds/lfo_route_gate_20261031_142203_921997` | `E:/gaoyun_builds/lfo_route_static_20261031_142623_211207` |
| 同一触摸测试的RTL | PASS，6/13均027F | PASS，6/13均027F |
| Gowin网表 | FAIL，6/13均0000 | PASS，6/13均027F |
| 绑定与q/sh快照 | 绑定后均source=1、depth=7F | 绑定后均source=1、depth=7F |
| 曲线节点126→80 | 正确发送007E→0050 | 正确发送007E→0050 |

原版 `diagnose_sim.log` 已直接观察：target6时scan33、target13时scan40，q与sh都为 `1/7F`，而输出帧却是 `F07D4F0000F7`、`F07D560000F7`。原版严格测试在启动深度007F被发为0000处失败；继续运行的诊断台故意将断言改为FAIL输出以观察后续，其沿用的末尾PASS文字**不能作为通过标记**，`failure_result.json` 明确记为失败。修复版 `compare_result.json` 则RTL与网表都通过。

根因定位至 `lfo_sysex_tx.v` 的路由动态切片读取：`sh_sources[route_idx*2 +: 2]` 和 `sh_depths[route_idx*8 +: 8]` 在本工具/工程下生成了与RTL不等价的零值路由数据。不是绑定写入丢失，也不是q/sh快照过期；无需修改触摸FSM、音频协议或UART。最小修复将这两处读取改为展开的53路常量切片选择，ID和14bit打包方式保持不变。此证据支持该具体表达式的综合偏差，不泛化成所有Gowin动态索引都错误。

正式源码已应用同一改法（生产RTL仅此一处修改）。新增 `sim/lfo_route_probe.v`、`sim/tb_lfo_route_probe.v` 和 `tools/test_lfo_route_gate.py`，可显式 `--build` 重做隔离网表比较，或 `--netlist-dir` 使用已有网表。工具拒绝FAIL行，保存源码/网表/原语库哈希，禁止与其他Gowin并行。正式探针增加LFO2/3、负深度、解绑、无UP超时覆盖，正在执行；先前首次运行因脚本router路径拼错在EDA启动前失败，目录142920_320119保留，路径已修正为rtl/touch_intake。

正式源回归 `impl/six_fix_20261031_142920_842985/result.json` 已PASS且快照一致：真实31250绑定6/13、binding→SysEx、同拍latch竞态、完整renderer释放/解绑重绑/LFO2/3/超时及串行Note/CC/Commit仲裁、51字节满队列背压。原协议工具142845也PASS；随后增强 `tb_lfo_sysex_tx.v` 的53目标初始source/depth为不同值，防止错误切片被重复值掩盖，该增强回归正在执行。

**本条状态：完整UI工程尚未重新构建、审计或部署，板上仍原00000966版本；不能声称实板已修好。** 下方“待用户曲线数据/生产RTL未改/未跑网表”为较早记录，由本条更新。

## 当前事实

用户在本轮 SRAM 部署后反馈，BIND LFO 后将 LFO1 拖到 OSC A Detune，实际仍得到：

```text
F0 7D 4F 00 00 F7
F0 7D 7E 00 00 F7
```

用户明确确认数据来自直接采集 UI TX 原始字节，而不是音频板解析后打印的字段。因此不能将该现象解释成音频板日志打印错误。预期仍是 `F0 7D 4F 02 7F F7` 后接 Commit；没有修改协议。

用户随后确认：松手后Detune有保留标记，并标明LFO1，但没有在旋钮旁看到深度。`modulation_overlay.v` 的旋钮标记直接取 `sources_r[n*2+:2]`，不是仅凭拖动意图绘制；该观察支持绑定源已进入UI状态。深度实际显示位置是LFO区底部AMOUNT栏（y658～693），不在旋钮旁，不能把“旋钮旁没有深度数字”当成depth=0的证据。新绑定底部应显示 `AMOUNT +127`，该数值尚未获用户确认。

2026-10-31 13:50，仅执行 Programmer `--run 0` 只读检查，当前 JTAG 目标 User Code **0x00000966**、Status **0x00026230**，与04:38部署相同，读取退出0。证据：`D:/github/synth1_9_18/2_ui_touch_hub/impl/lfo_zero_frame_20261031_135047_580594/jtag_current_read.log`。没有写入、复位、重新综合或布局布线。

当前源码HEAD为 `366427637fd51e5e7e335ab219b9ef6ba9d409cb`（部署后的文档提交），部署RTL仍为 **f86e882157595ce14a6e9b501fd4320c4c14d888**。fetch后 origin/main 仍为5224279，origin/integration/dual-138k-uart-phase1仍为3664276。生产RTL未改。

## 不能混淆的两件事

原修复针对可复现的快照dirty漏发竞态，相关回归通过；它没有唯一复现历史0000帧，本次实板反馈说明实际故障仍未收敛。完整时序审计和 SRAM 写入成功不能代替功能实板验收。

当前 `lfo_binding_state.v` 对每个目标复位深度为127，绑定写127，深度按钮步长为8、端点为±127，解绑只清source。因此正常状态机可达的depth始终为奇数，**0不是正常可达深度**。即使绑定手势未命中，也不能单独解释默认深度被发成0。需继续区分：屏幕所用绑定状态是否正确、发送快照/帧装配/FIFO是否丢值、实际采集引脚与对应固件是否一致，或综合实现与RTL行为是否存在偏差。尚未有证据可唯一确定其中任何一项。

## 新增诊断回归与限制

新增 `sim/tb_lfo_binding_realbaud.v`，输入是原始触摸坐标DOWN/MOVE/UP，经过生产 `touch_event_router` 归一化、真实绑定状态机、发送快照、MIDI FIFO、50MHz/31250 baud逐位接收；没有直接向cfg_sources/cfg_depths注入路由值。

首次完整81帧启动UART和5ms HID间隔版本触及测试工具240秒墙钟上限，**整项不算通过**。目录 `impl/six_fix_20261031_134906_936783` 保留，transcript已记录初始 `F07D4F007FF7`、`F07D56007FF7`、Commit，以及绑定后的 `F07D4F027FF7`、Commit；未完成target13验收。工具 `test_six_fix.py` 已补超时捕获，后续会保存部分输出和failure.json，避免只保留Python异常。

随后为隔离真实UART分频，在测试环境缩短UI静默/手势计时、快速握手消化启动批次；路由仍只由真实绑定状态机产生，后续绑定帧经过真实31250波特率串口。`impl/six_fix_20261031_135607_753534/result.json` PASS，源码快照匹配，实际逐位接收到：

```text
target6 : F0 7D 4F 02 7F F7
Commit  : F0 7D 7E 00 00 F7
target13: F0 7D 56 02 7F F7
Commit  : F0 7D 7E 00 00 F7
```

这只能证明该RTL仿真路径和真实UART分频可产生正确值，**没有复现实板全零，也不是修复完成证据**。此回归没有实例化整个renderer；此前完整renderer回归仍单独保留，二者不能混写成新的全板实物验证。

## 两种RTL语言模式的补充检查

`impl/lfo_transport_frontends_20261031_140921_123261/result.json` 保存最小生产链的不可变源码快照，分别以默认Verilog-2001和显式`-sv`编译RTL，再以SystemVerilog编译测试台。两个版本各执行三项：

- `tb_lfo_sysex_tx`：81帧完整启动、曲线节点/模式/相位同步、正负路由深度、CC抢占和精确Level值；均PASS。
- `tb_lfo_binding_realbaud`：原始触摸→router→绑定→真实31250 UART，6/13均发027F；均PASS，仍保留上述计时压缩和启动握手限制。
- `tb_midi_sysex_handshake`：51个实际串行字节、Note/CC优先、unsupported CC延后、FIFO满与两槽背压、Commit恰好一次；均PASS。

六次运行通过且工作区/源码快照匹配。该结果没有发现ModelSim两种语言模式的解释差异，**不是Gowin综合网表验证，也不能排除综合实现偏差**。本轮只查询过Gowin CLI帮助，没有运行综合、布局布线或写入。

## 接续需要的观察

已请用户将LFO1曲线中间节点明显拖高或拖低，并贴出随后UI TX完整原始字节，当前待答。除了变化的曲线节点值，LFO1相位同步帧应固定为 `F0 7D 48 00 04 F7`，之后是Commit。若该常量4也变成0，重点检查通用组帧/后半帧/FIFO传输；若常量4正确而路由仍0000，继续查路由快照与动态选取。两种情况都需要实际数据支持，不能提前认定根因。

生产RTL仍未改，没有新构建或重复烧录；不要为了让target6固定发027F而硬编码字段，否则会破坏53目标、LFO2/3和负深度协议。修复前必须保留可复现证据，修复后同时回归真实绑定状态机和通用发送链。
