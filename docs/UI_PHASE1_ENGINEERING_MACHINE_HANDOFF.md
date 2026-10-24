# UI Phase 1 工程机交接说明

本文件用于把 UI 板的 Phase 1 GPIO UART 联调版本交给工程机执行。它描述的是“待执行流程”，不代表当前已经生成位流或已经烧录。

## 固定源码基线

- 共享仓库分支：`integration/dual-138k-uart-phase1`
- UI 快照提交：`0dfae7c995bc7029f1253c8c4843a10eb3d4376f`
- UI 工程目录：`2_ui_touch_hub/`
- 正常工程：`2_ui_touch_hub.gprj`
- 正常构建脚本：`build.tcl`
- UI UART 输出：`audio_link_tx -> AB21`（J8 pin 9）
- USB-UART 监视输出：`midi_uart_tx -> U15`

不要使用 UI 独立仓库中未提交的导航字体实验构建本轮位流。不要使用 `build_debug.tcl` 作为双板联调位流；诊断工程会让对外 MIDI/UART 行为不同。

## 工程机构建门禁

1. 在工程机取得上述分支，并确认工作区干净。
2. 确认 Gowin 目标器件为 `GW5AST-LV138PG484AC1/I0` / `GW5AST-138B`。
3. 使用 `2_ui_touch_hub.gprj` 和 `build.tcl` 完整综合、布局布线和时序分析。
4. 使用 `tools/audit_build.py` 审计：必须同时满足 setup、hold、recovery、removal、minimum pulse width 无违例，输入快照 hash 一致，且 bitstream 文件完整。
5. 保存构建目录、审计 JSON、最终 `.fs` 的 SHA256；任何一项缺失都不能进入烧录。

## 烧录门禁

- 仅允许 SRAM：`tools/deploy_verified.py --target sram ...`
- Flash 仍暂停，禁止使用 `--target external-flash`。
- 必须先由用户确认工程机已开机且板卡已连接；SSH 超时后不得自动重试，因为远端可能已经完成 SRAM 写入。
- 烧录后必须保留远端 programmer 日志、退出码、远端位流 hash 和实屏抓拍。
- 实屏抓拍只能证明 UI 板运行；它不能证明音频板已收到 UART。

## 板上联调条件

UI J8 pin 9（AB21）连接音频板 J8 pin 9（AB21），两板 J8 pin 3 或 pin 4 共地。不连接电源、时钟、复位；测试期间不要占用 PMOD1 对应的 DVP/SDRAM1 扩展资源。

第一轮只验证 CC20、CC21、CC22、CC23、CC42、CC43、CC44、CC45、CC48。验收链路必须包含“UI 发出 UART、音频 RX 收到、音频参数实际改变”；不能只依据 UI 页面数值变化。

## 当前未完成项

- 当前分支尚未完成 Gowin 综合、STA、bitstream 生成和 UI 板烧录。
- 当前 UI 没有音频状态回传，因此“已发送”不能写成“已应用”。
- Note On/Off 仍不是本阶段的 UI 顶层验收项。
