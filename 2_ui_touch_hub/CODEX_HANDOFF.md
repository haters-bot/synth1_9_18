# UI Touch Hub 当前交接入口

## 追加记录（2026-10-18：ENV 点位与掉电启动 Flash）

- ENV 图中从左往右数、包含最左端起点时，第三个白点为 HOLD 手柄，参数只代表峰值平台的保持时间，因此只允许水平拖动。右侧下降段终点可调 DECAY 时间与 SUSTAIN 高度；最右侧平台点只调 SUSTAIN。`sim/tb_curve_touch_editor.v` 新增 DECAY 手柄垂直调节 Sustain 并还原的断言，`python tools/test_curve_editor.py` 已通过。
- GitHub 团队仓库 `haters-bot/synth1_9_18` 的 `ui-touch-hub-v1.0` 分支已包含本地源码提交 `a2b6e6c` 的诊断版本，发布提交为 `3ade0c0`；草稿 PR #1 已存在，未合并主分支。此分支已有诊断 UART 扩展；本记录更新若要同步，需继续向该分支追加提交。
- 工程机远程只读检测 `programmer_cli --device GW5AST-138B --run 51` 成功识别外部 Flash ID `0x0B4018`。Gowin Programmer 1.9.11.03 CLI 支持操作 69（exFlash 经 GAO-Bridge 5A 擦除、写入并校验）。Sipeed 官方 [Tang Mega 138K Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html) 列出单颗 128/64 Mbit Flash，并建议使用 GAO-Bridge 5A（V1.9.11.03+）或 Arora V（V1.9.12+）；同页还要求按 Flash 烧录图设置 DIP 开关。当前仅检测到芯片，尚未擦写 Flash，也未确认板上 DIP 状态。
- 掉电启动候选固件：普通 R15I 保留 U15 MIDI 31250、不带诊断日志；U15 诊断版输出 115200 日志并暂停 U15 对外 MIDI。不要把两种用途混淆。Flash 擦写会替换非易失配置，待用户确认要将哪种版本作为默认启动镜像、且按官方图确认 DIP/模式后，再执行操作 69 并回读校验。普通 R15I 已验收 fs 的 SHA256 为 `3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`；诊断位流的历史 hash 与当前构建产物见诊断交接，不把缺失的 SRAM Programmer 返回码写成成功。

## 当前状态（2026-10-18）

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
