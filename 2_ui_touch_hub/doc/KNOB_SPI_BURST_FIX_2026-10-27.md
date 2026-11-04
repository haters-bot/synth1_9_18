# 旋钮 SPI 连续读取与 C14 日志修复（2026-10-27）

## 范围与当前状态

用户确认实物使用原接线：2CS=A15、1CS=B20、SCLK=B21、SDI=B17、SDO=D17、INT=A18、RESET=D14；C14 接 USB-TTL RX，115200 8N1，公共地。

实际工作副本：`D:/github/synth1_9_18/2_ui_touch_hub`。本次修复已完成 RTL 仿真与完整源文件编译，**尚未运行 Gowin、未生成新的可部署位流、未烧录**。板上最后有记录的版本仍为 `20261027_162828_I2S_LIVE_PHASE_SPECTRUM_HISTORY`；不得用仿真结果替代现场验收。未删除文件，未操作 Flash，未修改音频/I2S/FFT 渲染逻辑。

## 找到的缺陷

1. 普通顶层默认 `DEBUG_KNOB_ASCII=0`，C14 镜像 MIDI，并非用户要求的 115200 ASCII 旋钮日志。后续 I2S 部署使用普通顶层，因此不能沿用此前诊断版 C14 行为的假设。
2. 大工程的 SPI 接收器没有沿用已实测成功的小工程：原来每次片选只发 24 个时钟，并通过第二字节改变端口；小工程使用单次片选连续 64 个时钟，发送 `82 00 00 00 00 00 00 00`，同时接收状态高/低字节及 P0–P5。原测试台按照 DUT 内部的 `port_idx` 生成逐端口返回，未验证这种差异。
3. 旋转待发掩码循环同拍覆盖输出 ID，同时清除了所有待发位，导致多旋钮同一扫描变化时只保留最后一个事件。开关边沿也存在同拍覆盖。
4. 原接收器要求两颗芯片都正常才解码，任一芯片失败会屏蔽另一颗的旋钮。

修复前备份：`impl/knob_fix_backup_20261027_164910_066/`。其中 SPI 接收器和顶层的 SHA256 分别与已部署 `R16A_build_20261027_161611/source_manifest.json` 对应项一致，证明上述缺陷存在于该部署源码快照，非只存在于未部署的工作区改动。

## 实现

- SPI 收发恢复为与实测探针相同的 Mode 0、64-clock 连续帧；保留位间与字节间低电平及片选间隔。
- GPIO 保持连续三位映射：`A=3*k、B=3*k+1、SW=3*k+2`，U1=K01–K16，U2=K17–K32。
- 保留原 32 路参数 ID 绑定。四个有效正交沿产生一个 detent，继续通过现有参数中枢的增量入口更新当前值，而非把接收器旧缓存值覆盖到 UI。
- 按下/释放去抖后缓存并逐个发出；目前只输出事件，不擅自赋予按压业务功能。
- 每颗芯片独立维护可用状态与基线；断开/恢复不会产生假旋转，一颗故障不屏蔽另一颗。
- 普通、诊断顶层均默认开启 C14 ASCII，MIDI 仍走原端口。顶层日志 FIFO 改为 128 项，覆盖 32 路批量事件；持续超过串口吞吐能力的无限事件流不在本次验收范围。
- 首次完成检测，以及有效状态改变时输出一次链路状态；没有周期心跳。连接判断依据返回帧状态字段，不是独立插拔传感器，也不能定位任意单根线的物理接触情况。

示例输出（与实际格式化器一致）：

```text
U1 SPI CONNECTED
U2 SPI CONNECTED
K01 CW U1
K01 CCW U1
K01 PRESS U1
K01 RELEASE U1
U2 SPI DISCONNECTED
```

上电首次状态为一次性消息：若串口在检测完成后才打开，空闲时不会补发。串口应在复位前打开。修改实际接线前断电，不用带电插拔验证。

## 验证证据

- **负向复现**：`impl/knob_integration_20261027_164922_515222/tb_knob_spi_burst.log`，原源码被独立引脚级从机拒绝：`TXE8148 requires 64 clocks under one CS; got 24`。
- **修复后专项**：`python tools/test_knob_integration.py`；`impl/knob_integration_20261027_165411_271152/`。
  - 引脚级检查每次片选 64 个上升沿，MOSI 精确等于 `8200000000000000`，状态/P0–P5 字节次序正确。
  - 32 个旋钮各一组 CW、CCW、PRESS、RELEASE；批量事件不丢编号，UART 逐字节解码并逐行校验。
  - 139 行预期 ASCII、1366 个 SPI 帧全部核对；初始断线、连接、U2 单独断开/恢复、稳定空闲不重复输出。
  - K01 驱动真实参数中枢；触屏调值后实体继续增减，验证上下限与不跳回缓存值。
  - 既有 K01 SPI 回归、ASCII 格式化回归及主/诊断工程所有 Verilog 源文件编译通过。
- **既有串口回归**：`python tools/test_touch_trace.py`；`impl/trace_tests_20261027_165151_750032/`，波形、解码、分段输入、重同步、事件输出和完整编译通过。该测试主动制造的 drops=15 不是实板丢包统计。
- **参数中枢**：`impl/curve_tests_20261027_165411/tb_param_merger.log`，默认值、SPI/触屏更新、限幅、仲裁优先级、ID/值配对和连续事件吞吐全部通过。
- **未通过项**：`python tools/test_curve_editor.py` 在 `tb_curve_touch_editor` 报 `Pending curve MIDI did not drain`；日志在上述 curve_tests 目录。该脚本编译清单不包含本次修改的 SPI 接收器、顶层或 ASCII 日志模块；相关曲线/MIDI RTL 和测试台本轮均未修改。这项结果必须单独保留，不能声称该套件全绿。

## 后续上板门禁

工作副本根 `AGENTS.md` 要求未经明确请求不以自动验证为由运行 Gowin。因此当前停在已修复、已仿真的源码阶段。用户明确要求生成部署版本后，再执行唯一隔离构建，五类时序完整审计通过后才允许 `deploy_verified.py --target sram`（operation 2）；SSH 超时不自动重试，Flash 暂停。新位流上板后，仍须确认串口事件与实体/屏幕联动。

## 后续执行更新：用户已明确授权构建与条件 SRAM 烧录

- 用户回复“是，构建并在审计通过后烧录 SRAM”，已满足工作副本 AGENTS.md 的明确请求要求。
- 当前唯一隔离构建：D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_185258，gw_sh PID 47704。综合与引脚约束解析完成，正在布局；source_manifest.json 已保存。恢复工作时先核对进程与日志，不重复启动 Gowin。
- 尚未产生最终时序结论，尚未调用烧录器。上文“未运行 Gowin”是授权之前的状态，以此更新为准；Flash 继续暂停。

## 2026-10-27 19:08–19:09：旋钮 SPI 连续帧/C14 ASCII 修正版构建并部署

- 用户已授权“构建并在审计通过后烧录 SRAM”。唯一隔离构建 `impl/R16A_build_20261027_185258` 完成，Gowin exit 0；64 个源文件快照与工作区一致。
- 五类审计通过：clk_pixel 56.905/50 MHz；setup +0.622 ns；hold +0.191 ns；recovery +0.201 ns；removal +0.497 ns；pulse width +0.453 ns；setup/hold 违例 0，负路径 0，OSER10 recovery/removal 三路均有报告，无 reset 例外。
- 仅执行一次 UI SRAM operation 2：`impl/deploy_runs/20261027_190826_KNOB_SPI_BURST_C14_ASCII/`。远程 `PROGRAMMER_EXIT=0`，User Code `0x00001766`，Status `0x00026230`；本地/远程位流 SHA256 `76E2B27474035033C464B72036230395BB29A1BDF15B95C928480BD9406C4DA5`。现场预览 `preview.jpg` 已抓取，屏幕画面正常。Flash 未操作。
- 当前待用户实测：打开 C14 串口（C14→USB-TTL RX、GND 共地、115200 8N1）后复位 UI 板，期望首次看到 `U1 SPI CONNECTED`、`U2 SPI CONNECTED`；随后旋转/按压应输出 `Kxx CW/CCW/PRESS/RELEASE U1/U2`。空闲不应每秒打印。SPI 连接状态只在首次检测或状态变化打印。
- 硬件状态仍需用户现场验证，不能用预览图替代旋钮事件验收。若要验证断线状态，先断电再改变接线并重新上电，避免带电插拔。
