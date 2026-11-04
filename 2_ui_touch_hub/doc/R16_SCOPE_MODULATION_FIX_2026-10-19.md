# R16 调制曲线显示修复（2026-10-19）

## 现场问题与原因

用户确认：手动拖动右上 FILTER RES 时响应曲线变化，绑定 LFO 后旋钮动态值变化，曲线仍静止。

`ui_top_renderer` 的旋钮层已读取 `mod_preview`，但 FILTER、OSC A/B 和 ENV 的曲线层仍读取基础参数。问题是显示链路使用了不同参数源；不能据旋钮动画声称音频核已收到调制。

RES 改变滤波响应示意图的共振峰，CUTOFF 改变截止位置。此图不是实时 FFT、实测频响或振荡器波表。当前音频调制接口尚待队友接入，这次修复不增加音频 DSP 或新 MIDI 调制发送。

## 修改范围

- FILTER CUTOFF/RES、OSC A/B WT POS、ENV A/H/D/S/R 曲线改用与旋钮一致的有效预览值。
- 基础值与调制结果继续分离：`effective=clamp(base+floor(depth*wave/128),0,127)`，不将预览反写基础参数。
- ENV 编辑器启用独立的显示几何输入：触点命中移动后的白点，按下时捕获的相对编辑基准仍来自基础值。捕获后即使 LFO 移动白点，手势目标不改变。
- `display_env_snapshot[34:0]` 按低位起 A/H/D/S/R 排列，仅供本地命中几何使用；没有改变队友现有协议。
- 不改时钟、视频七拍流水、绑定手势和已验收 FX 功能；SRAM 部署，Flash 继续暂停。

## 验证记录

- `tools/test_modulated_scopes.py`：真实触控建立九个目标绑定、编辑 LFO 曲线、调节正/负深度及解除 RES；13,746 次像素比较。独立参考参数由测试计算，不从 DUT 调制输出获取；检查所有基础参数未变化。通过，证据 `impl/modulated_scopes_20261019_200136_468313/`。
- `tools/test_curve_editor.py`：原有 FILTER/ENV/参数库/UART 回归及新增动画 ENV 命中专项全部通过。专项覆盖显示与基础位置相距超过命中半径、按下无写入、捕获不漂移、基础值相对编辑、精确回到锚点及 Sustain。证据 `impl/curve_tests_20261019_200253/`。
- `tools/test_video_alignment.py`：6,136 次连续像素和同步对齐通过，`impl/video_alignment_20261019_200136_468434/`。
- `tools/test_touch_trace.py`：正常/诊断顶层编译、UART 日志和解码回归通过，`impl/trace_tests_20261019_200136_480473/`。
- 旧版反证：`python tools/test_modulated_scopes.py --renderer-ref 48f9ea9` 在同一刺激下复现 mode=2 的曲线像素不匹配；`impl/modulated_scopes_20261019_200350_034211/`。旧版负向运行的 Fatal 是预期复现证据，不是新实现通过结果。
- FX/LFO 全套回归通过：53 目标、三 LFO、19 FX 旋钮/外部输入、九开关、持续标记和缺 UP 生命周期，`impl/fx_lfo_tests_20261019_200529_279911/`。

## 构建与时序

修复提交 `40d3cf0`；新隔离构建 `impl/R16A_build_20261019_200320/` 已完成。审计 `audit_20261019_201128_912102.json`：52 个输入文件与工作区/快照一致，setup/hold 违例 0/0，无复位豁免，三路 OSER10 recovery/removal 均覆盖。

- 实际像素 PLL 50 MHz；STA 估算 Fmax 57.657 MHz，不能把后者当作实际运行频率。
- 最差 slack：setup +0.622、hold +0.204、recovery +0.098、removal +0.497、pulse width +0.453 ns。均通过，但 recovery 余量较小，不能据此承诺所有温压和长期实机行为。
- 位流 35,904,599 字节，SHA256 `09C82CEB4AA3FB7EEB8D064E9CD9D1543BF199877A875C000B0CE1B090CF5B44`。
- SRAM 部署 `impl/deploy_runs/20261019_201142_R16_scope_preview_fixed/` 已完成：双机 SHA256 相同，Programmer 识别 GW5AST-138B，operation 2 / SRAM Program，Finished / PROGRAMMER_EXIT=0，烧录耗时 22.85 秒；manifest 状态为 sram_programmed。现场照片 preview.jpg 已回传并查看，显示 R16A 和 FX/LFO 界面。Flash 未操作。

## 实机验收

烧录后请用户将 LFO 绑定到 FILTER RES，询问旋钮变化时上方曲线的共振峰是否同步起伏，用户明确回复 **“曲线已同步变化”**。因此 FILTER RES 的本次故障已获实机验收；OSC/ENV 同类连接和移动 ENV 白点编辑已通过上述仿真，本轮未逐项获得实屏反馈，不扩大用户验收范围。

20:04 预检工程机 ping/SSH 超时；用户检查连接后，20:10 SSH 返回 DESKTOP-FDEVSGP，随后完整部署成功。未因超时盲目重复烧录。

旧版安全回退保留：`impl/R16A_build_20261019_192921/impl/pnr/2_ui_touch_hub.fs`，验收标签 `verified/ui-R16A-20261019`。
