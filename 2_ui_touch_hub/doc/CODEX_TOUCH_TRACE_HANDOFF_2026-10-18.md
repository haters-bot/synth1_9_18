# 点击日志、接口调研与 V1.0 交接（2026-10-18）

## 用户要求与交付边界

现在实现 PC 可读的板卡点击日志；未来分期扩展。实体键盘/旋钮到 UI、UI 到音频核先调研，
资料不足不替队友定协议。已验收 UI 作为 V1.0 放入共享仓库，保留来源和给队友的同步说明。
不删除旧文件、不重写历史、不搬队友音频工程、不自动合并 main。

## Git 与版本

- 独立开发仓库：`D:\github\gaoyun\2_ui_touch_hub`，master，原先无 remote。
- 已验收 R15I RTL `c988661`；UI 本地 V1.0 标签 `ui-v1.0.0` → `2e110e8`（含可移植 build.tcl 和发布说明）。
- 共享仓库 https://github.com/haters-bot/synth1_9_18 ，本地 `D:\github\synth1_9_18`。
  分支 `ui-touch-hub-v1.0` 基于音频 main `85edc8264efe103aa238b300b938729e77b80e19`；
  基线导入 `75847e6`，共享标签 `ui-v1.0.0` → 该导入提交。
- 两仓库提交号不同：团队仓库保留音频历史，通过带来源清单的 `2_ui_touch_hub/` 快照导入。
  `V1_0_SOURCE.json` 保留基线来源，诊断扩展另行提交，不移动基线标签。
- 历史考证和接口差异见 `TEAM_INTEGRATION_2026-10-17.md`。现有历史不支持“队友改回目录结构”；
  本轮只新增 UI 子目录，不搬音频根目录，不创建空队友工程。

## 实现与使用

新增 `rtl/debug/ui_debug_trace.v`、debug wrapper / GPRJ / SDC / build脚本、UART bench 和 PC/远程采集工具。
普通顶层 `DEBUG_TOUCH_LOG=0` 保留 U15 MIDI 31250；诊断为 1，U15 改为 115200 8N1 日志。
内部 MIDI busy 和 UI 状态机继续运行。日志只观察，无 UI 写回、背压，不修改触摸校准。
LFO 新增只读状态输出，排除动画相位；USB 仅移动 `u_dev_conn` 声明至实例之前。

记录原始/归一化坐标、来源/按下、按钮/旋钮 delta、曲线、本地 LFO、参数请求、SPI 与当前选中值。
参数请求不等于音频接收确认；focus 是保留选择，不等于本次命中。完整含义见 `TOUCH_TRACE_V1.md`。
固定 64 字节帧、XOR 校验、序号/毫秒/丢包计数，16 时钟合并窗口，32 帧 FIFO，满丢新记录。
不承诺任意事件洪峰无损；PC 推导 DOWN 数量不能当绝对硬件点击数。

```powershell
# 主力机：诊断版已烧录后，实时查看工程机串口并回传
python tools/capture_remote_trace.py --port COM6 --seconds 60 --label clicks
# 工程机直接查看，保持 tools 与 rtl/ui_vector_engine/params.vh 相对结构
python tools/touch_trace_monitor.py --port COM6 --seconds 60
# 离线复核，无串口访问
python tools/touch_trace_monitor.py --decode 完整路径/capture.bin
```

## 构建与时序

诊断 fs：`impl/pnr/2_ui_touch_hub_debug.fs`，36,691,629 字节，SHA256：
`F34A5197EE10D99C7AC58A0CC9392222C6F206DCE79E9C83B986207336D60226`。
归档 `impl/TOUCH_TRACE_final_20261018_002528/` 含 fs、报告、日志、manifest。

第一轮综合后因 wrapper 使 PLL 层次变化，原 SDC 失配；新增 `u_hub/` 层次的 debug SDC 后解决。
第二轮 PnR 被用户中断；随后从网表继续 PnR，`impl/codex_touch_trace_pnr_20261018_0024.log`，exit 0。
**时序尚未收敛**：像素目标 62.5 MHz、Fmax 57.876 MHz，最差 setup -1.278 ns，
setup 违规共 96（像素同域 TNS -47.170 ns / 93 个），hold 违规 0。
最差路径 touch router selected_param_id → param merger midi_cc_val，另有 LFO 文字路径。
Logic 20,131 / 138,240，FF 5,200，BSRAM 25，DSP 39.5；日志 FIFO 增加 BSRAM。
实屏正常不能替代时序签核。

## 回归结果与明确失败

- `tools/test_touch_trace.py` PASS：普通/诊断全源码编译，从 UART 引脚波形逐 bit 独立解码，
  同时多类事件、批边界、负增量、坐标、曲线/LFO、FIFO 超载/heartbeat、PC 分段/坏包恢复。
  证据 `impl/trace_tests_20261018_000807_580983/`。
- 原 curve、LFO/router 坐标、pixel 回归 PASS：`impl/curve_tests_20261018_000844/`、
  `impl/lfo_tests_20261018_000900/`、`impl/pixel_tests_20261018_000911/`。
- 完整 RTL 预览 PASS 且已看图：`impl/ui_preview_20261018_000918_TRACE_observation_regression/frame.png`。
- 四个 Python 工具 py_compile 和 diff whitespace 检查通过。
- **旧 USB bench 失败，未掩盖**：`impl/usb_declaration_regression_20261018/`。
  `tb_usb_touch_intake.v` 针对回退前格式，与已验收 R15I sticky-format 解码不一致；
  首包实际 19747/33，旧断言期待 9163/8525。本轮没改解码，不为旧断言重构已工作映射。
  不能宣称本轮历史“42 项全部通过”。

## 实机证据与网络异常

主力机 `.235`、工程机 `.157`；仅远程 SRAM 烧录。工程机枚举 COM5/COM6，
VID:PID 0403:6010、序号 2025030317A/B。**COM6 已由有效状态帧确认 UART；不要打开可能用于 JTAG 的 COM5。**
本地 Dock 31002 原理图第 8/21 页为 BL616 桥；USB VID/PID 不独立证明物理 FT2232。
资料来源和实际 CST 引脚见 `TOUCH_TRACE_V1.md`。

部署目录 `impl/deploy_runs/20261018_002528_TOUCH_TRACE_V1/`，远端同名位于 `D:/gaoyun_deploy/`。
远端 fs SHA256 与本地一致。Programmer 识别 GW5AST-138B 并开始 SRAM Program，
SSH 在最后收到 44% 后超时，未收到 PROGRAMMER_EXIT/完成标记，未重复烧录。
恢复网络后确认 programmer_cli 已退出，摄像头界面正常，COM6 输出有效诊断协议。
这支持诊断固件实际运行，**不能补写未收到的 exit 0，也没有在线运行固件的哈希回读机制**。
原工具没落盘异常 stdout，`network_failure_note.txt` 是事实摘要，不冒充原始日志。
部署工具已改为保留异常输出，未来在远端写 programmer.log / programmer_exit.txt，仍禁止自动重试。

首轮采集 `impl/touch_logs/20261018_003044_385792_heartbeat_after_disconnect/`：
5 秒 5 条连续 STATUS、bad_frames=0、board_dropped=0、touch_records=0；
skipped_bytes=594、trailing_bytes=0，代表起始重同步前字节，不可宣称零杂字节。
bin SHA256 `06A7DBF4A395503CD89D225018EE97BDA2AC005F0DB7D98CA998CC60B56E9622`。
`impl/deploy_runs/20261018_002528_TOUCH_TRACE_V1/preview.jpg` 已查看，界面正常。
实际点击采集另存，不能以 STATUS 或仿真样例替代真实点击验证。

第二轮 `impl/touch_logs/20261018_003257_639293_real_clicks/`，120 秒收到 240 条 STATUS，
无 touch/button/curve 记录，尚未取得用户本轮真实操作证据，不能宣称点击实机通过。
bad_frames=0、board_dropped=0，但 sequence_gap_total=5，skipped_bytes=2。
最初 1 秒批量读出 121 条缓存状态帧，随后接收约每秒一条；不要把缓存时间跨度当实际采集时长。
五个缺失序号的原因未查明，可能在起始缓存/串口传输环节，不归咎于硬件 FIFO，也不声称链路无损。
本次 bin SHA256 `74704DA27FEEDC8B699872E66166C580CC84B2DE37DFCCED48D232892896F34A`。
工具现把总序号空洞写入 manifest，保留全部原始证据。

## 回退与继续工作

```powershell
python tools/deploy_verified.py --label R15I_rollback --fs impl/R15I_final_build2_20261017_2336/2_ui_touch_hub.fs
```

R15I fs SHA256 `3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`，R15H 也保留。
连接不稳先核查，不能自动重烧。诊断 U15 暂停对外 MIDI，声音联调前切回普通版或落实独立日志口。
本地基线源码/硬件包 `impl/v1_0_release_20261018/`；实现产物不进团队 Git。

下位接手先看本文件、TOUCH_TRACE_V1、TEAM_INTEGRATION 与 bin/JSONL/manifest。
上游键盘资料不足；UI 旧 MIDI/ENV/七点 LFO 与下游有差异，本轮只调研。
顶层旧注释部分引脚过期，以 CST 为准：TX U15、RX V14、SPI W16/U16/T16、USB H13/G13。
先处理已有时序问题，再考虑升分辨率。
