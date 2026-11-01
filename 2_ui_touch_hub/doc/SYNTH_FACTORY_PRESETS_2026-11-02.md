# SYSTEM 音色库：源码与仿真交付（2026-11-02）

## 本轮边界

- 只增加 UI 板音色预设；本轮没有启动 Gowin 综合、布局布线或任何烧录。
- 实际工作副本 `D:/github/synth1_9_18/2_ui_touch_hub`；分支 `integration/dual-138k-uart-phase1`，基准 HEAD `bfb3afe`。本轮改动保留于本地工作区，未提交、未推送。
- 用户确认：先做 12 个官方预设，自定义只预留入口和数据接口，不做存入、删除或断电保存。
- 未修改音频 RTL、音频协议、MIDI 通道、53 个 LFO 目标、手机或 ESP 固件。原有 App/ESP/其他脏文件保留。

## 工程检查与实施选择

这是一套 FPGA RTL 界面，现有状态由 `param_merger`、`audio_controls_state`、`fx_editor_state` 分别持有，生产发送由 `static_cc_sync`、`lfo_sysex_tx` 和 `midi_uart_tx` 完成。不能只发预设 CC 而不更新这些状态库；也不能只把差异同步器触发一次，因为它不重发相同值，且扫描顺序不等于参考程序。

采用在现有参数库增加受控的整批装载口、增加小型预设事务生产者的方式。复用原有 8 项 MIDI FIFO、串口编码和 Note 优先级，不增加第二套串口驱动。没有改变 UART 或板间协议。

## 页面安排

入口为 **SYSTEM → PRESETS**，使用原第四个 ABOUT 子页的位置；顶层 SYNTHESIZER / VISUALIZATION / PERFORMANCE / SYSTEM 导航不增加标签。其余三个 SYSTEM 页签保留。

- 左侧 6 个分类：ACOUSTIC、CLASSIC、LEAD、BASS、KEYS、ATMOSPHERE。
- 右侧每类 1～3 张大卡片，点击直接应用；显示名称、一句话说明、当前高亮。
- 顶部显示当前/正在应用的音色和 READY / APPLYING / QUEUED 状态。
- 底部 REAPPLY 完整重发；BACK 回 SYNTHESIZER，仍在 VSYNC 提交导航。
- CUSTOM : RESERVED 显示为灰色；点击只提示尚未实现保存/删除，不伪造保存成功。
- 继续使用现有英文 7×10 字库，主要文字以 2 倍尺寸显示；原中文名称和完整介绍保留在生成的数据目录中。

## 权威数据与只读结构

固定参考为 `haters-bot/synth1_9_18` 提交 **`f0da2279eba79c3b368248718f96033f0cc8f9b6`** 的 `tools/midi_uart_sender.py`。通过 `git fetch origin` / `git show <固定提交>:tools/midi_uart_sender.py` 读取 GitHub 对象，不依赖队友工作区，不合并音频分支。

`tools/generate_synth_presets.py` 从该固定 Git 对象的 AST 提取常量、`make_synth_preset()` 和最终 `SYNTH_PRESETS`；GUI 不被导入执行。全局、OSC A/B 默认值展开后生成完整数据。

- `synth_presets.vh`：12 × 518 位只读配置，每个音色 74 × 7 位；另有按 Python 顺序发送的 slot ROM。
- `synth_presets_reference.json`：中文名称、说明、完整展开参数、原始 CC 值、UI 值、顺序及参考 SHA256。
- 波形仅在 UI 状态域转换为原有枚举（0 sine / 1 saw / 2 square / 3 triangle / 4 SD）；发送继续用原来的 `midi_uart_tx` 映射回 0/96/64/32/127。
- CC 编号没有散落在页面中，页面只提交音色索引；控制器使用集中 `static_cc_slots.vh` 的内部 ID，UART 使用原有集中 CC 映射。
- 没有动态内存分配。只读表随 FPGA 配置装入；本轮没有往外部 Flash 写入数据。

| 索引 | 官方音色 | 备注 |
|---|---|---|
| 0 | 原声模拟｜合成钢琴（波表8） | SD/DDR 8 |
| 1 | 原声模拟｜弓弦独奏（波表9） | SD/DDR 9 |
| 2 | 经典合成｜温暖模拟铜管 | 完整 A/B 参数 |
| 3 | 经典合成｜复古弦乐机 | 完整效果参数 |
| 4 | Lead｜经典 PWM 主音 | 保留参考 Warp 设置 |
| 5 | Lead｜宽广 Supersaw | A4 + B3，总计 7 Unison 成员 |
| 6 | Bass｜圆润 Sub Bass | 完整关闭未用功能 |
| 7 | Bass｜Acid 303 风格 | SD/DDR 0 |
| 8 | Keys｜明亮拨弦 Pluck | 完整 ADSR |
| 9 | Keys｜晶莹电钢 | 完整 ADSR |
| 10 | Keys｜经典晶体管风琴 | 完整 A/B 参数 |
| 11 | 氛围｜宽广模拟 Pad | A3 + B2，总计 5 Unison 成员 |

UI 只发波表编号，不加载或伪造音频板 DDR 状态；无对应波表时仍由音频板原有回退处理。没有降低 Unison。

## 状态与发送事务

统一入口为 `preset_apply_req` + `preset_apply_index[3:0]`，由 `synth_preset_controller` 接收。

1. 暂停普通参数/LFO 差异生产者，等待已经接受的串口消息排空；已入队消息不被截断。
2. `load_bank` 一拍把 74 个值写入全部权威参数库，ENV1/2 同时更新，两个 Hold 归零但不发送 Hold CC；清除旧 FX link，防止其联动覆盖独立预设值。
3. 在真实 `lfo_binding_state` 中把全部 53 个 source/depth 清为 0，UI 标记同步消失。现有协议没有单独的 LFO enable 字段；与 Python 一样，通过所有 route source=0 关闭有效调制，不发明新协议位。原有三条 7 节点曲线和 rate/stepped/once 保留。
4. 按参考方法发送 42 个全局、滤波器和效果器 CC。
5. 发送完整 LFO 配置：每 bank 的 7 节点再 mode、53 个清零路由、三个 restart（4/5/6）、Commit。逐字节对齐 Python `configuration_fields()` 的插入顺序。
6. 按参考顺序发送 OSC A 16 项、OSC B 16 项；普通 CC 均 `BF cc value`。
7. UART 物理发送排空后，`adopt_bank` 更新差异同步器/LFO 发送器的已发送快照，然后恢复普通编辑。避免把预设刚刚发出的值又重复发一遍。

每次应用完整发送 **74 个 CC + 81 个 SysEx 帧 = 708 字节**，即使同一个音色也完全重发。31250 baud、8N1 下仅线速下限为 226.56 ms，另有状态机开销和 Note 抢占；不是“切换瞬间全部参数同时到达音频板”。

一次只处理当前整批，并保留 **1 个最新待执行选择**；连续点击会覆盖尚未开始的待执行选择，当前批次完成后再完整应用最新一项。不同预设不交错，pending 有 UI 提示，没有无界队列或静默 FIFO 溢出。暂不支持在当前预设中途撤销已发参数。

批量生产者只有 UART 空闲时才提交下一条消息，并使用真实 `cc_accept/sysex_accept` 前进；Note 继续使用原有最高优先级和 `note_ready`。切换过程不发送 All Notes Off。装载/发送期间相关参数编辑暂时锁定，导航和演奏 Note 仍可处理，状态页显示 APPLYING；结束后恢复旋钮与 LFO 编辑。

## 自定义扩展接口

`doc/SYNTH_CUSTOM_PRESET_SCHEMA_V1.json` 是预留的版本化数据契约：`schema_version=1`、name、description、固定 74 项 UI 原生值，slot 顺序与 `static_cc_slots.vh` 相同。schema 约束布尔 enable、Unison 1～8、五种波形、Warp 0～11、Bank 0～9 等范围。

采集端未来可读取现有完整 `audio_static_values[517:0]`；恢复端复用本次各参数库的 `preset_load` + `preset_values` 装载口和事务发送机制。当前控制器只接受官方 0～11，12～15 作为非法请求拒绝并产生诊断脉冲；不能通过这些编号假装调用自定义。

尚未增加自定义写入接口、用户槽位、名称编辑、存储驱动或删除逻辑。schema 是后续实现的契约，不是已经可用的导入/保存功能。

## 修改文件

新增生产 RTL：

- `rtl/midi_uart_tx/synth_preset_controller.v`：固定容量事务、待执行选择、完整 CC/SysEx 生产者。
- `rtl/ui_vector_engine/synth_preset_ui.v`：分类、卡片、重发、返回和预留入口。
- `rtl/ui_vector_engine/synth_preset_panel.v`：四拍预设面板，与原导航组合后仍为七拍。
- `rtl/ui_vector_engine/synth_presets.vh`、`synth_preset_text.vh`：编译期只读数据。

修改现有 RTL：`param_merger.v`、`audio_controls_state.v`、`fx_editor_state.v`、`lfo_binding_state.v` 增加可选装载钩子；`static_cc_sync.v`、`lfo_sysex_tx.v` 增加可选 hold/adopt；`ui_touch_hub_top.v`、`ui_top_renderer.v` 接线；`ui_navigation_state.v`、`ui_navigation_renderer.v`、`navigation_labels.vh` 提供 SYSTEM 入口及合成。所有新钩子默认关闭，生产 top 显式启用，原 CC/SysEx 编码函数未改。

正常/调试 `.gprj` 均纳入三个新模块。现有隔离构建工具会收集同目录 `.vh`，两个 ROM 头文件包含在源码清单中；本轮仅核对输入，没有调用构建工具。

新增/更新工具与测试：`generate_synth_presets.py`、`synth_presets_reference.json`、`test_synth_presets.py`、`test_synth_preset_ui.py`、`verify_synth_preset_release.py`、`sim/tb_synth_presets.v`；`generate_navigation_labels.py` 更新标题；`test_fx_input_pipeline.py` 的实例定位兼容参数化实例。

## 验证与证据

最终汇总见同目录 `SYNTH_FACTORY_PRESETS_2026-11-02.acceptance.json`。以下是源码/RTL 仿真结果，不是板上验收。

- 12 × 74 = **888 项完整参数**逐项对照固定 Git 数据；所有值 0～127、Unison 1～8、枚举和值域一致。
- 真正执行参考 Python 的 `send_all_synth_controls()` 及发送辅助方法作为独立 oracle，不复制一份人工期望顺序。
- 真实参数库 → 现有 UART FIFO → 串行波形解码共 **11,343 字节**一致；包括 12 预设、重复应用、快速切换只保留最新待执行、开机立即应用、后续实体 CC 和 LFO 重新绑定。测试使用加速 UART 仿真；生产 baud 31250 未改。
- 真实状态机预先绑定 LFO 后应用预设，确认全部 53 个 source/depth 清零；全部 74 个实时 UI 值与发送库一致，没有旧 FX link 覆盖。
- Note 与批量 CC/SysEx 同拍竞争时优先接受，On/Off 串行载荷正确；批量期间不发 All Notes Off。
- 实际 `ui_top_renderer` 触摸：6 分类、12 卡片、REAPPLY、CUSTOM 只提示、BACK/VSYNC；新页面 **512 次七拍动态像素对齐检查**通过。
- 6 分类共 **1,382,400 个 RTL 像素采样**生成截图，已人工查看，放大文字后复验。
- normal/debug 全层次展开通过；使用 ModelSim 和官方原语模型，没有启动 Gowin。
- 原 FX 实体输入管线 **4,352 项**通过。原 Note/CC/SysEx/LFO/ENV/FX 等 16 项 RTL 回归独立执行，最终结果及快照哈希列在 acceptance 中。

四种代表音色（钢琴、Supersaw、Sub Bass、Pad）的完整 MIDI 字节保存在 `E:/gaoyun_builds/synth_presets_20261102_012625_658936/representative_midi.json`；该目录同时有实际串行 `preset_actual.hex`、Python `preset_expected.hex`、固定参考文件和所有输入快照。

新页面最终截图/交互记录：`E:/gaoyun_builds/synth_preset_ui_20261102_012820_925548`。normal/debug：`E:/gaoyun_builds/ui_elaboration_20261102_012755_697461`。

原 `test_video_alignment.py` 的旧 FX 固定颜色 oracle 仍报 cycle19 `actual=181c24 expected=384256`。已在完全未修改的 **HEAD bfb3afe** Git 对象冻结输入中重现完全相同的失败，证据 `E:/gaoyun_builds/preset_legacy_baseline_20261102_012941_449260/result.json`。该测试不计为通过，也未为迁就旧期望修改生产像素。新预设页七拍检查单独通过。

第一轮 16 项回归在运行期间仅因字体/页面改进使源码快照不再匹配，虽各 bench 通过也不作为最终验收；完整目录保留，最终已冻结代码重新运行。所有旧失败/日志/位流均保留。

## 后续构建前的限制

本轮未取得新增逻辑的 Gowin 资源、时序或板上结果，不能承诺本次添加必然保持上一版余量。以后由用户明确统一构建时，再核对冻结输入、正常/调试工程、五类时序及引脚/时钟审计；通过后按既有 SRAM 流程部署。

板上仍是上一轮已验收的源码 `03bd696`、UserCode `0x352D` 的版本，本轮没有读写 JTAG，也没有更新板上预设功能。波表实际加载、音色听感、实屏触摸及演奏仍需之后上板验收。
