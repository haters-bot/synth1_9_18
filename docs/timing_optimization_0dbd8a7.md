# 针对 0dbd8a7 布线报告的时序优化

## 起点

参考 `build_results/synth1_0dbd8a7f4648_20261102_150037` 的 Signoff 报告：

- `clk_sys` 约束 50 MHz，报告 Fmax 43.594 MHz，169 个 Setup 违例端点。
- 报告中一条系统域最差路径：`u_ads1256_scanner/state_3_s1` 经 `processor_sample_channel` 到 `u_ribbon_pitch_processor/work_filtered_24_s0`，裕量 -2.938 ns。
- 另一条报告路径：`u_performance_pitch_controller/vibrato_phase_26_s0` 到 `vibrato_ratio_delta_q16_11_s0`，裕量 -2.736 ns。
- DDR PHY 最差报告 Setup -6.004 ns、Hold -0.208 ns；这两项需要结合 DDR IP 的时序要求和完整约束判断。
- Routing Phase 1 用时 36 分 15 秒；总构建用时 54 分 47 秒。

## RTL 改动

1. `ribbon_pitch_processor` 将每笔输入拆为采样及历史锁存、中值计算、差值计算、差值绝对值、滤波累加，再进入原有映射和事件提交。滤波阈值、舍入、截断、Gate 规则、各通道历史以及事件顺序保持原样。输入握手及事件握手保留；处理延迟与最小输入间隔均增加 4 个 50 MHz 时钟周期，即 80 ns。实际 ADC 通道扫描为微秒级，仍有足够处理空隙；极端同周期 MIDI/滑带交互的相对先后可能随 80 ns 改变。
2. `performance_pitch_controller` 在每次相位更新时提前查找下一相位正弦并寄存；深度乘法使用与原设计相同的当前相位正弦。相位、颤音输出、滑音和 MIDI 输出的可见时刻保持不变。
3. 未改动音频计算、板级引脚、时钟约束、DDR IP 或时序例外。DDR 相关问题和普通时钟布线警告仍需结合新报告单独判断。

切分流水线可以缩短组合路径，但还会改变布局及资源使用；单次新布线不能确保缩短耗时，也不能保证其余路径收敛。

## 功能验证

- 滑带处理器与 Git 基线 `0dbd8a7` 同输入逐事件对照：校准反向及普通模式各 640 笔样本，分别输出 310 和 322 个一致事件；覆盖四通道、负值、正负满量程、Gate 阈值、通道交替及输出背压。
- 颤音和演奏控制与 `0dbd8a7` 逐周期对照 250000 周期，覆盖相位回卷、相邻采样脉冲、参数变化以及 MIDI 输入。
- 滑带故障释放、校准端点、滑带音高通路、演奏音高控制和顶层 MIDI 回归均通过。

等价测试所用旧版由 `sim/run_timing_equivalence.do` 从 Git 历史中的 `0dbd8a7` 提取至忽略目录 `tmp/`。参考基线必须存在于本地 Git 历史。

## 等待实际构建确认

尚未运行本次 Gowin 综合和布局布线。重跑后需要对照新的 `project_tr_content.html` 和 `project.rpt.html`：

- `clk_sys` 的 Fmax、Setup 最差裕量及违例端点数量；滑带和颤音路径是否退出最差路径。
- DDR 的 Setup/Hold 和约束覆盖情况；不要为了消除违例而盲目增加 false path。
- Routing Phase 1、总布局布线耗时、Logic/CLS/DSP/BSRAM 使用量。
- 烧录后先验证 ADS1256 原始数据及串口状态，再测试滑带发声、MIDI 仲裁、故障释放和颤音。
