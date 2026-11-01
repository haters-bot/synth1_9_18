# 官方音色库正式构建、时序收敛和 SRAM 部署记录

> **最终结果：2026-11-02 06:22，第三轮正式位流已全部通过审计，并且唯一一次 UI SRAM operation 2 烧录和后置只读复核成功。板上 UserCode=0x617D，Status=0x26230。前两轮失败位流从未烧录。**

用户于 2026-11-02 明确授权：开始构建，按照流程直到完成烧录。仅 UI SRAM operation 2；不写 Flash、音频板或 ESP。

## 第一轮正式构建：禁止部署

- 源码检查点：`e27b2c36851dad48d3ec583e15c8072e4dde49f3`。
- 工程：`2_ui_touch_hub.gprj` / `ui_touch_hub_top`；Gowin Synthesis、place3、route1、timing driven，配置显式指定。
- 隔离目录：`E:/gaoyun_builds/R16A_build_20261102_044748`。
- 04:47:51 启动、05:09:47 退出 0；位流生成成功，但时序失败。
- 审计：`audit_20261102_051007_420448.json`，124 冻结/工作区输入和 124 引脚匹配；setup 314、hold 0，最差 setup −1.062 ns，像素时钟 47.477/50 MHz；其他六个时钟及 recovery/removal/pulse 通过。
- 该位流绝未烧录。整个失败目录、审计、网表、位流和 `source_acceptance_frozen.json` 保留。

### STA 报告中暴露的两条长组合链

已报告的 250 条负路径由两类起点组成，不能把报告条数当作完整违例端点数：

1. `u_rst_sync/reset_cnt_1_s0` → MIDI/FIFO 的 CC 接收组合译码 → `u_static_cc_sync/sent[]`、`initial_pending[]`。最差到 `sent[44]_2_s1` 的 CE 为 −1.062 ns。UART 接收确认同拍直接驱动大量参数影子寄存器的写使能，跨越长译码和高扇出布线。
2. `u_touch_router/s0_tx_7_s0` → 导航头栏几何/capture → `u_render/u_binding/depth[]`。最差约 −1.007 ns。原始导航取消信号没有寄存，穿过导航逻辑后直接进入绑定库。

这次问题不是未设置 EDA 默认模式，也不是逻辑容量满。第一轮实际使用的配置正确，最终资源为逻辑 56%、寄存器 29%、BSRAM 55%；需要缩短真实组合路径。

## 最小 RTL 修补

仅修改两个生产文件，没有修改协议、53 个目标、串口编码、引脚、时钟或约束：

- `static_cc_sync.v`：用本地寄存器保存 UART 已接受的 scan/value/valid，下一拍写入影子库；请求仍在真实 FIFO 接受沿撤销。增加一拍提交间隔，避免 COUNT=1 时在影子尚未提交前重复发送。接受沿发生的新编辑仍在后续重发，不能误记成已发送。
- `lfo_binding_state.v`：导航取消先寄存一拍，再作用于绑定库；原有触摸数据包有两拍译码，取消仍在对应头栏触摸包之前生效。保持已保存路由，取消活动拖动，返回后可重新绑定。

没有添加 false path、multicycle、降低像素/DDR 时钟或调整综合布线策略来绕开违例。

## 修补后源码验证

全部使用当前源哈希重新运行并通过：

- 16 项原有 RTL 回归：`E:/gaoyun_builds/six_fix_20261102_051439_661319/result.json`。
- 完整预设状态库/UART：`E:/gaoyun_builds/synth_presets_20261102_051439_574254/result.json`，11,343 字节与固定 Python 参考一致；包括同音色重发、快切、启动立即应用、Note 优先及后续 CC/重新绑定。
- 实际 renderer：`E:/gaoyun_builds/synth_preset_ui_20261102_051529_989988/result.json`，12 卡片、512 次七拍对齐、六分类共 1,382,400 个像素采样。
- normal/debug 层次：`E:/gaoyun_builds/ui_elaboration_20261102_051549_434465/result.json`。
- FX 实体输入 4,352 项：`impl/fx_input_pipeline_20261102_051555_406348/result.json`。
- 新增/扩展的针对性检查：接受沿修改的旧/新值所有权、COUNT=1 无重复、导航取消和重新绑定。
- 6 组证据、135 个当前测试输入哈希一致，汇总为 `SYNTH_FACTORY_PRESETS_2026-11-02.acceptance.json`。

旧 FX 固定颜色 oracle 在原始未修改 HEAD 也失败，保持单独失败记录，不计作通过；本次不改原显示像素来迎合陈旧期望。

## 工程机和部署前置条件

用户将主力机切回昨晚成功的 Wi-Fi。使用直接 LAN：本机 `192.168.31.182`、工程机 `192.168.31.183`，通过 `GAOYUN_LOCAL_IP`、`GAOYUN_REMOTE_IP` 环境变量覆盖；没有使用 ZeroTier 中继，也没有改全局 SSH 配置。

- `preset_remote_preflight_20261102_045347_285633`：只读确认主机 DESKTOP-FDEVSGP、无其他下载进程、唯一预期 UI 板旧 UserCode `0x352D` / Status `0x26230`。
- `preset_transfer_preflight_20261102_050021_730553`：工程机可从本机 8899 端口读取传输测试内容。没有烧录操作。

后续正式构建、五类审计和唯一一次 SRAM 写入结果完成后追加于本记录；第一轮失败位流始终禁止部署。

## 第二轮正式构建：仍禁止部署

- 源码 `0593b6ec45bee5a67b08723a1d05c263d9b34416`，目录 `E:/gaoyun_builds/R16A_build_20261102_052003`，05:20:04～05:47:38，正常退出 0。
- `audit_20261102_054746_640497.json`：setup184、hold0，worst −1.848 ns、pixel45.770/50 MHz；其他四类时序、其他六时钟、124源/124引脚均过，未烧录。
- 最差路径转到全局复位归约 → MIDI/FIFO 接收译码 → 预设 `message_index`；报告中另有复位到 UART 内部状态、少量 CC 同步控制路径。第一次只在影子库端提交寄存，尚未充分隔离共享复位/请求/确认反馈。
- 触摸剩余路径转到 FX 坐标转换后的 53 路 `target_hits` 比较。取消寄存已拆开原来的深度更新路径，但坐标自身仍需分级。
- 失败目录、位流、审计和源阶段 acceptance 冻结副本全部保留，不原样重跑。

### 第三轮前的局部管线修补

1. 预设生产者在准备阶段等待 UART 空闲，SEND 阶段只保持稳定请求，不再把 `uart_busy` 组合到请求和确认循环。真实 FIFO 接受沿立即撤销请求，下一拍独立 ADVANCE 状态推进索引。仍为每次一个批量消息，Note 优先，完整字节顺序不变。
2. 在像素时钟内为 UART、CC 同步器、预设生产者、LFO 发送器各放一个保留的本地复位寄存器：异步断言、同步同时释放。释放只多一个像素时钟；将远处全局复位归约从 MIDI 组合译码起点移开。Note ready 在 UART 本地复位期间为低，防止提前消费演奏事件。
3. 绑定触摸先寄存原坐标/FX页/LFO bank/valid/down，再寄存 FX 坐标转换和同组元数据，然后进入原有目标比较。额外延迟仅两个像素时钟，不改变七拍显示管线或目标编号。

MIDI 编码文件 `midi_uart_tx.v`、53 个目标表、时钟/引脚约束和综合/布局布线策略保持原值。没有添加时序例外。

### 第三轮前验证

- 17 项完整 RTL：`E:/gaoyun_builds/six_fix_20261102_055548_138957/result.json`；新增本地复位断言/释放、12轮复位、停钟与恢复检查，原16项全部通过。
- 预设 11,343 字节：`E:/gaoyun_builds/synth_presets_20261102_055548_037074/result.json`。
- UI/512七拍/六图：`E:/gaoyun_builds/synth_preset_ui_20261102_055637_643734/result.json`。
- normal/debug：`E:/gaoyun_builds/ui_elaboration_20261102_055657_920737/result.json`。
- FX 4,352项：`impl/fx_input_pipeline_20261102_055704_553134/result.json`。
- 6组证据/136当前输入全部匹配；acceptance已更新。编译前曾遇到新局部变量声明顺序不兼容旧 ModelSim，已调整并保留失败记录后重跑通过。

## 第三轮正式构建与最终全审计：通过

- 源码：`9ee5dce473774f85e8010ec0add1d4e942047855`；分支 `integration/dual-138k-uart-phase1`，本地提交未推送。
- 构建：`E:/gaoyun_builds/R16A_build_20261102_060044`，06:00:46～06:21:30，约20分44秒，退出0。
- 工程/顶层：`2_ui_touch_hub.gprj` / `ui_touch_hub_top`，GowinSynthesis / place3 / route1 / timing driven；与前两轮配置相同。
- 124 项冻结输入、工作区文件、规范化 Git 内容全部匹配；136 项当前仿真输入一致。相比第二轮仅 controller、top、renderer 三个生产文件变化，其他121项输入相同。
- `audit_20261102_062137_424718.json` 与烧前 `deploy_check_only.json` 复审均通过；没有新增时序例外。

| 检查 | 最差裕量 | 结果 |
|---|---:|---|
| Setup | +0.730 ns | 0违例 |
| Hold | +0.138 ns | 0违例 |
| Recovery | +0.365 ns | 0违例 |
| Removal | +0.299 ns | 0违例 |
| Pulse width | +0.366 ns | 0违例 |

七个时钟全部达标：sys_clk228.636/50 MHz，pixel54.027/50 MHz，DVI5x393.797/250 MHz，USB88.300/59.999 MHz，CH569421.941/50 MHz，DDR400为2016.129/400 MHz，DDR user112.592/100 MHz。124 项最终引脚匹配约束。

最终资源（Gowin报告）：逻辑76706/138240（56%），寄存器40191/139095（29%），BSRAM185/340（55%）。不是资源容量溢出。

正式位流 `impl/pnr/2_ui_touch_hub.fs` 为41,215,585字节；SHA256：

```text
FF2A32811EF2AC11F2933C99F8AB5EA409AB946C4C2380BCC3A477512A18BF13
```

## 唯一一次 SRAM 写入及只读复核：通过

- 烧前即刻只读 `preset_remote_preflight_20261102_062154_375835`：主机身份、无其他下载进程、唯一 UI 板旧352D/26230确认。
- 仅调用 `tools/deploy_verified.py --board ui --target sram`，label `UI_FACTORY_PRESETS_20261102`；没有写 Flash、音频板或 ESP。
- 部署目录：`D:/github/synth1_9_18/2_ui_touch_hub/impl/deploy_runs/20261102_062216_UI_FACTORY_PRESETS_20261102`。
- 工程机文件哈希通过后执行 operation2；100%完成，耗时26.76秒，`PROGRAMMER_EXIT=0`、`CODEX_PROGRAM_COMPLETE`。
- 新板卡读码：**UserCode=0x0000617D，Status=0x00026230**。
- 再独立执行只读核验，确认工程机身份、两台电脑位流 SHA256 相同、保存的 Programmer exit0、无遗留下载/构建进程、板卡读码一致；`completion_record.json`已保存。
- 这是文件传输哈希核对及板卡设备码/状态读取，不冒称对整片 SRAM 做了 SHA256 读回。
- 全程只有一次实际写入，没有 SSH 写入超时或自动重试；两个失败构建完整保留。

相机拍到了工作台，未覆盖可验收的 UI 屏幕。因此本轮证明的是源码/仿真、正式时序及正确位流的 SRAM 部署；没有声称已现场听过12个音色或验证了所有实屏触摸。

## 现场验收建议

1. UI 上进入 **SYSTEM → PRESETS**，检查6个分类、12个音色卡片。
2. 依次试钢琴（SD8）、Supersaw、Sub Bass、Pad，按实体键听音；切换后回 SYNTHESIZER 检查 OSC、Filter、ENV1/2、FX、Pitch 参数同步。
3. 修改任一相关参数后点 REAPPLY，确认完整恢复；先绑定一个 LFO，再选音色，检查旧绑定消失。
4. 快速选多个卡片，最终应落在最后一次选择，Note On/Off不中断；CUSTOM仍只是预留提示。

SD8/9能否发出预期音色仍取决于音频板波表已加载，UI不负责加载SD文件。手机/ESP固件本轮未更换。烧录重置了UI会话，验收 PERFORM/手机传曲时按原流程重新连接和校准。

## 本轮经验

Gowin退出0且生成fs不能代表可上板；本轮前两次都由审计阻止。原始长链同时包括全局复位、UART状态/FIFO判断、握手确认、消费者索引/写使能，单改一个消费端可能只把最差端点转移。应把请求准备、稳定保持、确认和索引推进拆成独立时钟阶段，必要时就近分布同步释放的复位。

触摸目标比较即使已有寄存，其上游的坐标重映射、共享几何和高扇出原始总线仍可能成为长链；寄存坐标时必须同时寄存 valid/down/LFO bank/FX page，保持事务归属。

这次没有选错 EDA 默认模式，也未靠放宽时钟/增加例外过关。后续新增功能仍可能改变全局布局，必须继续执行独立源码、引脚、七时钟和五类时序审计，不能保证以后永不出现时序收敛工作。
