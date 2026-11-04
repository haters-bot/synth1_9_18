# R15G：右下角恢复 LFO 编辑区

## 已核实的来源与需求

- 用户明确指定包络图右侧、旧四条槽位和底部 REVERB/DELAY/CHORUS/PORTA 的整个区域，并选择“恢复 LFO 曲线编辑区”。用户接受本轮完成本地编辑、音频接口后续与音频核对接的边界。
- 原始图：`D:\github\gaoyun\serum_reference.png`（900×728）。右下主要区域原为 LFO 编辑器，下有速率、上升、延迟、平滑等控制；最右侧另有 VOICING（单音/复音、连奏、滑音）。本轮在现有 460×326 像素区域恢复简化 LFO 编辑器，未声称完整复刻原版所有功能。
- 旧工程说明：`D:\github\gaoyun\hdmi_serum_ui\SERUM_UI_SOURCE_MAP.md`，明确列出 ENV、LFO、VOICING。
- Antigravity 记录：`C:\Users\胡珂\.gemini\antigravity\brain\44b86f26-de1b-41bc-bc6c-1efd36abce37\UI_TOUCH_HUB_V2_DELIVERY.md`，以及同目录 `.system_generated\logs\transcript_full.jsonl`。报告将此区域改称 FX 矩阵；日志 step 20 仍有旧 LFO 窗口，step 323/361 出现四条 FX 槽位设计。
- 代码核对：旧 `u_fx_matrix.mod_amt1..4` 实际接 REVERB/DELAY/CHORUS/PORTAMENTO 数值，槽位没有独立源/目标参数；不能当成已实现的 LFO 调制矩阵。
- 补充浏览 Xfer 官网 `https://xferrecords.com/products/serum-2`，核对官方对 LFO 调制的描述；该页面为 Serum 2，不能用来认定旧 Serum 1 的精确布局。旧布局以上述本地参考图为准。

## 代码与操作

- 新增 `rtl/ui_vector_engine/lfo_editor_state.v`：三个独立页签，各自保存七个 0..127 节点、速率、循环/单次模式及预设状态。节点时间位置固定为 X=832+64*n，垂直拖动或横向划过节点可编辑幅度。
- 新增 `lfo_panel_renderer.v`：完整接管 X796..1256、Y368..693 的像素；七点线性插值、方波阶梯、网格、节点、动态播放线及清晰文字。沿用原三阶段像素流水。
- TRIANGLE/RAMP/SQUARE 可恢复预设。RATE 每次点按轮换 0.25/0.5/1/2/4/8 Hz；MODE 切换 FREE/ONCE；RESTART 从起点播放。速率按像素时钟 62.5 MHz 计算，是本地视觉预览速度。
- 触摸归一化仍由 `touch_event_router` 使用已验证的 R15E X/Y 比例完成，新模块直接消费同一时钟域的归一化事件；未重复拟合坐标。
- 右下角旧矩阵和效果器触摸入口停用，原模块文件、参数 ID、SPI/MIDI 后端保留。LFO 面板像素优先于旧旋钮/按钮，因此不会出现旧效果器文字。
- 以首次接触位置捕获手势，外部旋钮拖入不能改变 LFO；50 ms 无事件看门狗处理丢失抬手。按钮每次接触仅动作一次。

## 明确限制

- 本轮为 **本地 LFO 曲线编辑与预览**，不是已接通的音频调制器；屏幕标注 `LOCAL PREVIEW` 和 `AUDIO LINK PENDING`。
- 没有发送未经协议定义的 LFO CC，没有新增实际声音调制、MIDI 音符触发、调制目标/深度路由或 VOICING 功能。ONCE 为手动启动的一次预览，不伪装为音频 Note On 触发。
- 旧效果器触屏控件在此区域被替换；如需恢复，可另设明确 FX 页面，不能将它们冒充 LFO 参数。
- R15F 可回退基线：tag `verified/ui-R15F-20261017` → `0cf8569`。不得删除旧文件或部署档案。
- R15F 已用户确认清晰且触控正常，但像素域时序未闭合（59.180 MHz < 62.5 MHz，TNS -10.611 ns）。本轮需读取新的时序报告，构建成功不能等同于时序通过。

## 验证与部署记录（持续更新）

- 首版真实 RTL 全帧预览：`impl/ui_preview_20261017_210734_R15G_LFO_preview/frame.png`，921,600 像素，无未知值；发现并修正提示文本长度与方波边沿细节。
- 首版集成仿真通过：独立页签、节点、上下限、预设、速率、循环/单次、重启、手势捕获/看门狗、无旧 FX 事件，以及 ENV/Cutoff 回归。正式复现工具：`python tools/test_lfo_editor.py`。
- 全帧复现：`python tools/render_rtl_preview.py --label 任意唯一标签 --lfo-tab 0`，另用 1/2 检查斜坡/方波页签。新增每帧 49,280 次实际 LFO 插值检查。
- 当前尚在验证与构建阶段，部署结果和最终时序以下续记录为准。
- 正式集成测试 `impl/lfo_tests_20261017_211221/` 通过；覆盖旧矩阵左边界，确认不会泄漏旧 FX 事件。
- 三个实际 RTL 帧均通过 921,600 像素无 X 及每帧 49,280 次插值检查：`impl/ui_preview_20261017_211036_R15G_triangle_final/`，`impl/ui_preview_20261017_211252_R15G_ramp_final/`，`impl/ui_preview_20261017_211252_R15G_square_final/`。
- 第一轮构建完成，像素域 57.619 MHz < 62.5 MHz，最差 setup slack -1.355 ns，TNS -22.798 ns/41 endpoints。主要路径落在原按钮名称坐标求差/判定；已对新旧名称使用常量包围框和窄位宽字形坐标优化，保持像素/时序对齐。首轮比特流和报告另存 `impl/R15G_build1_20261017_211352/`，没有烧录，且不能作为最终源码对应固件。
- 优化后实际帧：`impl/ui_preview_20261017_211558_R15G_timing2/`，检查通过。RAM 页签状态仅在本次上电会话保存，未添加 Flash 持久化。
- 第二轮全量综合退出 0，生成 `impl/pnr/2_ui_touch_hub.fs`；实际像素域 Fmax 58.396 MHz < 62.5 MHz，最差 setup slack -1.124 ns，TNS -22.512 ns/48 endpoints。仍未时序闭合，部署前后均以实机视觉/触控验收为准。
- 第二轮固件已远程烧录，目录 `impl/deploy_runs/20261017_212356_R15G_LFO/`，SHA256 `23FE46AD762A69162266EA63A949928E02E69A70B1502F13AE7BDB084C33D7C3`，34,990,081 bytes，远程/本地哈希一致，`PROGRAMMER_EXIT=0`。抓拍显示 LFO 面板和底栏 R15G。这份固件比源码提交 `2ec2858` 少最后一处 MODE 文字起点修正，不能当作该提交的精确产物；已启动最终重建。
- `impl/ui_preview_20261017_211920_R15G_final_max127/` 检查通过，目视确认 MODE 已正确显示、三位数未截断。与优化前逐像素对照，右下角区域之外零差异；旧文字变化仅涉及新面板的 MODE 起点。
- 用户在第一次 R15G 实屏验收明确反馈：“切换和拖动都正常”（LFO 2 页签及白色曲线节点拖动）。该反馈验证 UI 操作，不代表音频调制已接通。
- 最终源码 RTL 为提交 `2ec2858`（后续仅文档记录）：全量构建日志 `impl/codex_R15G_final_build_20261017.log`，完成比特流/功耗报告生成；像素域 Fmax 58.253 MHz < 62.5 MHz，最差 setup slack -1.166 ns，TNS -12.481 ns/23 endpoints，Hold TNS 0。**仍非时序闭合版本**。前述 58.396 MHz 是上一轮数值，不能混用。
- 最终固件已烧录到工程机 FPGA SRAM：`impl/deploy_runs/20261017_213140_R15G_final/`；远程 `D:/gaoyun_deploy/20261017_213140_R15G_final/`。SHA256 `0E7B31814C3DA29216F82E74586A320A30DA92409A9A74F94C3FBF0B64A713EF`，35,117,569 bytes，跨机哈希一致，`PROGRAMMER_EXIT=0`、`CODEX_PROGRAM_COMPLETE` 均确认。该镜像包含 MODE 对齐修正，替代前一次 R15G 镜像。
- 最终抓拍已回传并目视核对：上述目录 `preview.jpg`（完整现场），`telemetry.png`（底栏）。可见 R15G、LFO 1/2/3、七节点曲线及 MODE/预设等文字，旧四条槽位和 FX 旋钮已被完整替换。相机照片只能确认当时显示，不能用于声称全部硬件时序正确。
- 最终构建在全部报告生成后 `gw_sh.exe` 仍未自行退出（本次 PID 30784，无子进程，CPU 已稳定），故不能记录正常退出 0；已在确认产物哈希/完成远程烧录后清理该次遗留进程。构建日志与产物保留。

## 当前结论与下一步交接

本轮 UI 恢复完成：本地 LFO 编辑器已部署，用户确认切换和拖动正常；最终仅追加文字对齐修正，现场抓拍复核完成。代码有本地 Git 记录，未推送远端。若继续产品化，优先完成像素时序闭合，再与音频核定义 LFO 数据/速率/触发/路由协议；不得把本地视觉预览作为音频功能验收。
