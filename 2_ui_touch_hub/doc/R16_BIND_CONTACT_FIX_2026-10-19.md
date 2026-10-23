# R16 BIND 偶发无响应修复（2026-10-19）

## 用户现象与证据边界

用户报告编辑右下 LFO 后按 BIND，偶发无法抓起曲线，整个界面的触摸操作暂时无效。进一步明确：已绑定旋钮的白色动态指示继续运动，只有触摸无响应。这支持触摸捕获/接触状态问题，不能据此宣称 FPGA 或视频时钟停转。

代码和仿真确认了一条可复现路径：`lfo_binding_state` 原来将所有接触的静默释放时间统一设为 500 ms，普通 LFO/FX/曲线/路由编辑器为 50 ms。缺少 UP 的曲线编辑接触，在 50..500 ms 内再次按 BIND，绑定状态机仍认为旧手指按下，不执行新按钮；后续 DOWN 继续重置计时。BIND 自己的 UP 若丢失，紧接的曲线报文也不能开始 drag，armed/capture 可继续屏蔽其他编辑器。该路径匹配用户现象；当前没有现场原始 HID 事件序列，不能认定所有偶发现象只有这一成因。

## 修改

- `WATCHDOG_CYCLES=25000000` 保留为已开始拖动的静默宽限，50 MHz 下为 500 ms，用于短暂停下瞄准目标和缺 UP 最终提交。
- 新 `CONTACT_TIMEOUT_CYCLES=WATCHDOG_CYCLES/10`：非拖动的普通/按钮/工具/点击绑定接触 50 ms 静默即释放，和其他编辑器一致。armed 模式仍保留等待用户选择曲线/目标，可按 BIND 再次取消。
- armed 且仍是 BIND 按钮捕获时，进入曲线区域直接交接给拖动。无需依赖按钮 UP，支持快速操作或连续从按钮移入曲线；来源页签在拖动开始锁存，拖动仅开始一次。
- 显式 UP、500 ms 拖动缺 UP 提交、无效目标取消、持久标记、AMOUNT、基础参数隔离不变。没有更改 USB 报文解码、时钟、视频或音频协议。
- 仍需明确：若普通非按钮接触缺 UP，且两次接触完全没有超过 50 ms 的报文间隔，现有报文无 contact ID/真实边界可用，不能保证区分为两次接触；不把新的时限说成能重建任意丢失 HID 信息。

## 验证

旧版负向复现：先新增测试、不改 RTL，运行 `tools/test_fx_lfo.py`，在 `impl/fx_lfo_tests_20261019_201900_337574/release_simulation.log` 明确报 `Stale curve contact swallowed BIND after normal contact timeout`。这是旧代码复现证据，不计为新版本通过。

修复后 `impl/fx_lfo_tests_20261019_202214_983612/` 四组全部通过：

- 53 路目标、三 LFO、19 FX 参数/外部仲裁、开关、深度、曲线平滑和基础值隔离。
- 持久标记/颜色、候选目标、缩略图。
- 新增真实编辑器联合测试 `tb_binding_editor_handoff`，连续 20 轮编辑曲线 → 缺 UP → 75 ms 等效间隔 → BIND → 无 UP 快速进入曲线 → 目标提交；曲线值保持，结束后 FX 可操作，LFO 预览继续运行。测试按比例缩短计时，没有强制 DUT 状态。
- 生命周期覆盖短接触释放、快速 BIND 交接、点击绑定后恢复、模式取消、500 ms 内瞄准停顿、最终目标、迟到 UP 去重、无效落点和显式 UP。

联合测试初次使用了 FX 开关命中框外的坐标，并将相位观察窗设得短于其周期；已按实际公开坐标改为 X760/Y387、观察 40 拍，未改变 DUT 或放宽功能断言。旧错误测试结果不作为通过依据。

前一轮曲线同步测试 `impl/modulated_scopes_20261019_202052_592006/` 13,746 像素比较通过。正常/诊断全顶层和日志回归 `impl/trace_tests_20261019_202052_567443/` 通过。

## 构建与部署状态

首个候选 `impl/R16A_build_20261019_202225/` 完成，但审计 `audit_20261019_203140_211086.json` **失败并禁止部署**：setup/hold 违例 0/0，setup +0.413、hold +0.146、recovery +0.321、removal +0.275 ns，最小脉宽 -0.346 ns。报告落在三路串行器 reset_pipe FF，250 MHz 时钟 PRIMARY 分布为 PTR3/PBR3；上一通过候选 200320 仅 PBR3。不能将这份 setup/hold 通过当成完整时序通过。

已读取本机 Gowin 官方 `SUG1018-1.6E_Arora Ⅴ Design Physical Constraints User Guide.pdf` §2.3（正文7页）的 INS_LOC 语法，以及§2.7时钟网约束。依据 200320 已审计的 routed timing report，给九个复位 FF 固定同一组物理站点，保持原有两级上升沿、末级下降沿释放逻辑与所有时序检查，不新增 false-path/豁免、不降频。此方案仍须新报告验证，不宣称位置固定必然解决一切时钟问题。

新候选 `impl/R16A_build_20261019_203742/` 包含约束修改，20:45 完整审计 `audit_20261019_204504_001308.json` 已通过：实际像素50MHz，估算Fmax58.983MHz，setup/hold违例0/0；最差setup+0.622、hold+0.156、recovery+0.100、removal+0.497、pulse+0.453ns。三路OSER10复位覆盖，无复位豁免，52个输入文件与工作区/快照一致。recovery余量较小，报告通过不等同于全温压长期验收。

复位FF仍在已通过站点；位流35,904,599字节，SHA256 `F3CF9E3F2EBE6DD58CF2F0E175BA33B20DBF3648683167554DB1AA2AC9EB82A6`。RTL提交 `7ae2e78`，物理约束提交 `a276b9b`。

## SRAM部署与用户验收完成

- 部署 `impl/deploy_runs/20261019_204532_R16_bind_contact_fixed/` 完成，双机SHA256匹配，工程机识别 GW5AST-138B，operation2/SRAM Program，Finished、PROGRAMMER_EXIT=0，烧录耗时22.82秒。manifest为sram_programmed，preview.jpg与telemetry.png已回传，现场图已查看。
- 用户按要求连续5～10次“编辑LFO → 点BIND → 拖曲线到旋钮”，中间操作FX，明确回复 **“连续操作正常，没有再卡住”**。本轮用户操作验收通过；不把这次有限复测扩大为任意输入下永久无卡顿的保证。
- 当前板上为203742候选，包含此前RES曲线调制同步修复。上一验收200320位流和 `verified/ui-R16A-scopes-20261019` 标签继续保留。Flash继续暂停，旧位流均保留，不删除文件。修复提交及验收记录仅本地Git保存，本轮未推送远程仓库。
