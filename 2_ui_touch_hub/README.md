# UI Touch Hub — V1.0

全国大学生集成电路双创大赛高云杯：Tang Mega 138K 触控合成器界面工程。
维护范围为本目录；共享仓库根目录的音频工程由音频队友维护。

## 已验收基线

V1.0 对应 R15I，RTL 提交 `c988661`，用户已确认“更精细，触控正常”。
包含 OSC A/B、FILTER、ENV 1/2/3 与 LFO 1/2/3 本地编辑，FILTER / ENV / LFO 曲线支持直接拖动。
输出 1280×720，像素时钟 62.5 MHz；屏幕原生分辨率尚未核实。

**UI 验收不代表声音全链路联调完成，也不代表时序收敛。**
R15I 最差 setup -1.216 ns、65 个负裕量端点，目标 62.5 MHz，报告 Fmax 58.084 MHz。
LFO、ENV2/3 为本地编辑；当前 MIDI 映射与音频队友最新协议存在差异，见接口对照。

## 打开与构建

使用 Gowin V1.9.11.03 Education，器件 `GW5AST-LV138PG484AC1/I0` / `GW5AST-138B`。
打开本目录 `2_ui_touch_hub.gprj`，或运行：

```powershell
& 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' .\build.tcl
```

`build.tcl` 按脚本位置定位工程，无需固定在原开发机目录。工程文件中的源码、约束均使用相对路径。
生成的 `impl/`、仿真工作库、照片和比特流不进入 Git。
板卡物理连接工程机；仅通过 `tools/deploy_verified.py` 远程 SRAM 部署，不能在主力机本地调用 JTAG。

## 文档入口

- `doc/TOUCH_TRACE_V1.md`：点击日志接口、二进制格式与 PC/远程采集方法。
- `doc/CODEX_TOUCH_TRACE_HANDOFF_2026-10-18.md`：本轮构建、实机采集证据和后续交接。
- `CODEX_HANDOFF.md`：当前状态、详细开发记录和回退方法。
- `doc/RELEASE_V1_0.md`：已验收版本身份、比特流指纹与验证边界。
- `doc/TEAM_INTEGRATION_2026-10-17.md`：仓库考证、三人分工及接口差异。
- 历史 `ARCHITECTURE.md` / `MIDI_CONTROL_PROTOCOL.md` 含未实现规划，以实际 RTL 和上述新文档为准。

## 点击日志诊断工程

普通工程默认保留 MIDI 31250 输出。单独运行 `build_debug.tcl` 构建诊断工程，
U15 切为 115200 8N1 二进制点击日志，内部 UI/MIDI 状态机继续运行。
**诊断模式同一引脚暂停对外 MIDI；不要把日志接到音频接收器。**
在工程机枚举确认 UART 后运行 `python tools/touch_trace_monitor.py --port COM6 --seconds 60`；
主力机可用 `python tools/capture_remote_trace.py --port COM6 --seconds 30 --label clicks` 实时查看并回传。
实际验证结果和时序限制以本轮交接文档为准。
