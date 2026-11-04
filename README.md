# gaoyun — 基于双 FPGA 架构的实时多复音波表合成系统

全国大学生嵌入式芯片与系统设计竞赛（高云赛道）参赛作品。

两块 Tang Mega 138K（GW5AST-138B）通过 31250 波特 MIDI UART 链路互联：
**UI 板**（触控屏 + 参数交互）将静态参数与配置下发给**音频板**，
音频板以 TDM 调度 64 个振荡器、32 复音、96 kHz 采样率实时合成音频。
板上已验证版本：UI `9ee5dce`（0x617D）。

```text
USB-UART MIDI -> MIDI parser -> channel/control router
              -> note/Unison task scheduler
              -> 4 generic oscillator engines x 8 pipelined TDM slots
              -> basic waveforms or 16-frame Acid wavetable with WT Position
              -> per-task ADSR + engine partial-sum mixer
              -> 8x FIR decimator -> MAX98357A standard I2S interface
```

## 目录导览

| 目录 | 内容 |
|---|---|
| `src/` | 音频板 RTL：振荡器 TDM 内核、MIDI 解析、FIR、I2S、DDR 波表通路（顶层 `src/top.v.v`） |
| `2_ui_touch_hub/` | UI 板工程：触控 HUD、矢量渲染引擎、参数面板、演出模式（含独立 `README.md` 与 `CODEX_HANDOFF.md`） |
| `constraints/` | 音频板约束 |
| `sim/` | ModelSim 测试台（每模块对应 `tb_*.v`） |
| `ip/` | Gowin IP 配置 |
| `tools/` | 构建 / 审计 / 部署脚本（`build_audio_isolated.py`、`audit_build.py`、`deploy_verified.py` 等） |
| `scripts/` | 辅助脚本 |
| `docs/` | 设计文档：架构、协议（`UI_LFO_MODULATION_PROTOCOL_V2.md`）、板间集成（`ui_uart_integration_v1.md`）、远程访问（`REMOTE_ACCESS_IPV6_MIGRATION.md`）、协作日志 |
| `hardware_docs/` | Tang Mega 138K 官方硬件资料：原理图、位号图、机械图、datasheet |
| `RGB/` | 外设小工程：STM32F103 + WS2812 灯带（Keil 工程） |
| `score_print/` | 展板曲谱排版（`make_score.py` 可复用换曲） |
| `fpga-competition-2026/` | 2026 年竞赛官方赛题与选题指南 |
| `高云规范化文件/` | 高云官方规范文档 |

双板互联协议、LFO 调制协议 V2、时序收敛与部署流程见 `docs/` 对应文档；
板间交付历史见 `docs/AI_COLLABORATION_LOG.md` 与根目录 `CHANGELOG_ALIGNMENT.md`。

## 构建与部署（速览）

- 音频板 / UI 板各自独立的 Gowin 工程（`synth1_9_18.gprj` 与 `2_ui_touch_hub/2_ui_touch_hub.gprj`）
- 流程：隔离构建 → `audit_build.py` 五类违例全零 → `deploy_verified.py` SRAM 烧录（operation 2）
- 只烧 SRAM；Flash 烧录（operation 69）注意事项见 `docs/remote_build_automation.md`
- 仿真：ModelSim，`sim/` 下每个测试台可独立运行

## 版本管理约定

- `integration/dual-138k-uart-phase1` 为主线开发分支，与板间联调同步推进
- 功能开发开独立分支（如 `integration/osc-ab-main-20261028`），验收后合入主线
- 未合入分支的实验修改以 diff 形式存档于 `docs/`（如 `osc-ab-do-mods-20261028.diff`）
- 不提交 Gowin 实现输出、仿真工作库、波形文件、IDE 本地状态（见 `.gitignore`）
- 提交信息格式：`类型(范围): 描述`（feat / fix / docs / build）
