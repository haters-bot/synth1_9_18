# R15H：FILTER / ENV 曲线直接触控

## 需求、基线与范围

用户确认希望右上 FILTER 和左下 ENV 的曲线都能像右下 LFO 一样直接拖动，并希望理解各控件用途。R15G 的 LFO 切换和节点拖动已由用户确认正常。本轮不改动已经验收的 USB 接线、ILITEK 报文抽取和 R15E 坐标比例。

修改前本地 Git 备份：`ui/R15G-before-direct-curves-20261017` → `35c6571`。旧固件、源码、实机照片均保留；没有执行删除、reset 或历史改写。此前记录见 `doc/CODEX_LFO_PANEL_HANDOFF_2026-10-17.md`。

## 用户操作说明

### 右上 FILTER：改变声音的频率成分

曲线是简化的频率响应示意，横轴表示频率，纵轴表示通过强度。它不是可任意加点的音频波形。

| 控件 | 用途 / 操作 |
| --- | --- |
| 电源符号 | 滤波器开关；关闭时显示平直的旁路曲线 |
| LOWPASS / HIGHPASS / BANDPASS / NOTCH 与左右箭头 | 切换低通、高通、带通、陷波四种示意 |
| A / B | 选择振荡器 A / B 进入滤波器的路由 |
| N / S | 原版概念是噪声 / 低音振荡器进入滤波器的路由 |
| K | 键盘跟踪：原版概念是音高改变时截止频率随之变化 |
| CUTOFF | 截止频率；图内按住向右增加，向左减小 |
| RES | 截止位置附近的共振强度；LP/HP/BP 向上拖增加，NOTCH 向下拖加深凹口 |
| PAN / DRIVE / FAT / MIX | 分别表示左右声像、驱动、丰满度和滤波干湿比例；保留已有旋钮 |

FILTER 图内任意位置可开始 XY 拖动，保留初次按下时的偏移，避免按下瞬间跳值。一个白点对应 CUTOFF 与 RES 两个维度，不能通过增加无物理含义的点把滤波器伪装成任意曲线编辑器。

**音频边界：**本轮验证了 CUTOFF / RES 的实际 UART 输出。A/B/N/S/K 和滤波类型已有 UI 状态，但当前 `midi_uart_tx.map_id_to_cc` 缺少相应专用映射、会落到默认 CC0；不能宣称这些路由和模式已控制音频核。N/S 也不能据此认定已有对应声源。其余旋钮的实际听感需结合音频核协议验收。

### 左下 ENV：改变按键前后参数随时间的变化

横轴是时间，纵轴是参数大小。ENV1 通常用作音量包络；ENV2/3 在原版可分配给其他调制目标，当前工程尚无这套完整路由。

| 阶段 / 白点 | 含义 | 本轮直接拖动 |
| --- | --- | --- |
| A / ATTACK，上升线顶点 | 从零上升到峰值所用时间 | 左右改变 Attack |
| H / HOLD，峰值上方独立点 | 在峰值停留的时间 | 左右改变 Hold；抬高 12 px，H=0 时仍可单独选中 |
| D / DECAY，下降线终点 | 从峰值下降到保持值所用时间 | 左右改变 Decay，上下同时改变 Sustain |
| S / SUSTAIN，水平保持段右端 | 按住音符时保持的数值 | 上下改变 Sustain；这不是持续时间旋钮 |
| R / RELEASE，回到零的终点 | 松开音符后回到零所用时间 | 左右改变 Release |

最左侧零点固定，不是第六个可编辑阶段。五个已有旋钮继续生效。ENV1/2/3 三页现在独立保存五个参数，仅保留在本次上电会话，未实现 Flash 持久化。

**音频边界：**ENV1 的 A/H/D/S/R 沿用 CC73/79/75/76/72。ENV2/3 当前为独立本地编辑，屏幕显示 `ENV 2:3 LOCAL EDIT ONLY`，不向音频核冒发 ENV1 的 CC。页签选择本身也不再发无定义的 CC0。右下 LFO 仍为 R15G 的本地编辑/预览，尚未对接音频调制。

## 实现与重要修正

- 新增 `rtl/touch_intake/curve_touch_editor.v`：共用路由器归一化事件；FILTER XY、ENV 最近实际节点命中、首次接触捕获、越界钳位、50 ms 丢失抬手看门狗。回到初始按下位置可精确恢复初始参数，未移动的轴保持原值。
- `touch_event_router.v` 停用旧 FILTER 通用拖动与 ENV 固定分区；曲线捕获期间禁止越过页签/按钮时误触，旋钮功能保留。
- `param_merger.v` 新增三组 ENV 参数、带掩码的绝对值事务和末值缓冲。曲线更新与 SPI 仲裁；FILTER / ENV1 待发 CC 按 UART 空闲发送并合并到最新值，实际串口解码验证成对参数不会漏发。
- 修正旧绘图乘法位宽不足：FILTER 截止横坐标及共振高度、ENV 各段长度及 Sustain 高度，原先在较高参数时可溢出回绕。绘制和触控共用 `params.vh` 中的 ENV 几何公式，NOTCH 白点改到凹口。
- ENV 新增 H/S 白点和 H 引线；新增三阶段 `curve_hint_renderer.v`，显示横纵轴操作和 ENV2/3 的本地限制；底栏版本 R15H。
- `2_ui_touch_hub.gprj` 与实际 RTL 预览工具注册新模块。

## 可复现验证

```powershell
cd D:\github\gaoyun\2_ui_touch_hub
python tools/test_curve_editor.py
python tools/test_lfo_editor.py
python tools/render_rtl_preview.py --label R15H_default
python tools/render_rtl_preview.py --label R15H_notch_max --value 127 --env-tab 1 --filter-type 3
```

- `impl/curve_tests_20261017_222610/`：新触控→路由→编辑器→参数→真实 MIDI FIFO/UART 集成测试 PASS；覆盖 FILTER XY/NOTCH、全部阶段、无跳变/返回原点、极值、捕获/看门狗、SPI 仲裁、串口最终参数、ENV 独立与 ENV2/3 不污染音频。
- 同目录 `tb_curve_geometry.log`：128 档实际绘图输入逐一检查单调、边界和全精度整数参考，四种滤波模式白点位置均 PASS。
- 同目录 `tb_param_merger.log`：原参数合并器测试 PASS。
- `impl/lfo_tests_20261017_222011/`：LFO 独立页、编辑、预览，以及旧坐标/触摸回归 PASS。
- 全帧预览、最终构建、时序和远程烧录结果在下面续记，硬件状态以下方最新记录为准。
- 两个最终真实 RTL 预览均 PASS：`impl/ui_preview_20261017_222610_R15H_final_default/frame.png` 和 `impl/ui_preview_20261017_222610_R15H_final_notch_max/frame.png`。每帧 921,600 像素无未知值、全帧节点判定及 49,280 次 LFO 插值检查通过。目视确认操作提示完整、H/S 节点、ENV2 本地提示、NOTCH 凹口白点及 127 极值布局正常。

## 构建、时序、部署与现场验收（待续记）

主力机仅构建；工程机 `10.136.125.157` 持有 JTAG。使用 `python tools/deploy_verified.py --label R15H_final` 远程 SRAM 烧录并留存唯一目录、双机 SHA256、Programmer 日志与摄像头照片。

已知 R15G 像素域 Fmax 58.253 MHz，目标 62.5 MHz，时序未闭合。本轮必须读取实际新报告，不能把仿真 PASS、生成比特流或摄像头正常显示当成时序闭合。

- 第一轮源码 `1c897d4`，日志 `impl/codex_R15H_build_20261017_2230.log`，构建正常退出 0，但像素域仅 28.510 MHz，最差 setup slack -19.075 ns，TNS -990.232 ns / 206 endpoints，Hold TNS 0。主要路径是未分级的 ENV 几何/最近节点选择及有符号常量除法。**此版没有烧录。** 比特流和报告备份 `impl/R15H_build1_20261017_224307/`。
- 后续修正：事件及其参数快照对齐通过长度、端点、距离、平衡最小值树四级流水；归一化坐标限制下缩窄几何算术。逆映射改用有界倒数定点乘法，六种跨度全部像素（含负值和超限）逐项对照整数除法，保持相同舍入/钳位结果。触摸控制延迟仅增加四个 16 ns 时钟，不改变 USB 比例或交互含义。新的控制路径需重新全量构建。
- 分级后完整回归 `impl/curve_tests_20261017_224357/` PASS，包含六种跨度的逐像素逆映射参考、真实 UART、各节点、页签独立、SPI 事务、看门狗，以及绘图 128 档全范围和旧参数合并器测试。绘图 RTL 未随这次分级改动，前述最终两张全帧预览仍适用。
- 第二轮构建源码 `2dfbd73`，日志 `impl/codex_R15H_build2_20261017_2246.log`。构建期间仅追加交接说明，不修改 RTL 或工程源清单；部署/时序结果待下续。
- 第二轮构建正常退出 0。最终报告：像素域 Fmax **57.813 MHz < 62.5 MHz**，最差 setup slack **-1.297 ns**，TNS **-49.450 ns / 74 endpoints**，Hold TNS 0。最差路径为原有 `u_render/u_lfo_panel/ch0_1_s0` 文字渲染，前 25 条 setup 路径均不经过新增曲线编辑器。长计算路径已修复，但**整机时序仍未闭合**，不能据此声称硬件时序全部通过。
- 最终比特流和报告另存 `impl/R15H_final_build2_20261017_2251/`。SHA256 `911054F05264B88D565FBF4FC6A600751E93848057080B9A1D67C8F36BE1AC90`；对应 RTL 为 `2dfbd73`。
- 首次远程部署留档 `impl/deploy_runs/20261017_225056_R15H_final/`，在 TCP/SSH 连接阶段明确报 `connect to host ... port 22: Connection timed out`，未建立远程会话，**未执行烧录**。该目录仅含本地打包/manifest，不能作为板上固件证据。
- 网络排查：主力机 ZeroTier 1.16.2 为 ONLINE，网络 `76fc96e4982f0766`（名称 222）为 OK，IP `10.136.125.235/24`、ifIndex 26，指定目标路由正确；目标 `10.136.125.157` 的邻居解析/SSH 超时。用户确认工程机仍开机，随后反馈已重新启动。恢复连接后的部署结果待续。
- 本轮结束时状态：用户重启后再次探测仍为 SSH 连接超时，目标邻居为 Incomplete；已向用户询问工程机“222”网络当前 IP，待回复。**R15H 尚未烧录、尚无实机触控验收、尚无本轮实屏照片**。最后一次成功部署记录为 R15G，详见上一份 LFO 交接文档；不要把 R15H 仿真帧当成现场照片。拿到可达地址后按用户指定双机拓扑继续，先核对目标身份再部署，不得在主力机调用 JTAG。

### 后续恢复与最终验收（覆盖上述网络阻塞状态）

- 同一目标 `10.136.125.157` 后续恢复可达，绑定源仍为 `10.136.125.235`；未改变双机拓扑。
- R15H 已成功远程 SRAM 烧录：`impl/deploy_runs/20261017_230432_R15H_reconnect/`，远程 `D:/gaoyun_deploy/20261017_230432_R15H_reconnect/`，35,139,671 bytes，双机 SHA256 均为 `911054F05264B88D565FBF4FC6A600751E93848057080B9A1D67C8F36BE1AC90`，`PROGRAMMER_EXIT=0`、`CODEX_PROGRAM_COMPLETE` 确认。RTL 对应 `2dfbd73`。
- `preview.jpg` 和 `telemetry.png` 已回传，目视核对 R15H、FILTER 操作提示、ENV 五阶段节点和原 LFO。用户在新问题中要求提高像素精细度，故先落实曲线基线再推进绘图升级。
- 用户实机验收明确回复 **“两块都正常”**，对应 FILTER 横/纵拖动和 ENV 白点拖动、下方数值同步。由此确认本轮交互功能恢复并扩展成功；音频边界和未闭合时序仍按本文说明，不扩大验收结论。
