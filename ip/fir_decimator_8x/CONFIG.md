# Gowin Advanced FIR Filter 配置清单

## 依据

- 项目器件：`GW5AST-LV138PG484AC1/I0`
- 本机 Gowin EDA：`V1.9.12.03 (64-bit)`
- 本机 Advanced FIR Filter IP：`2.7`
- 官方手册：`IPUG543-2.2_Gowin_Advanced_FIR_Filter_IP用户手册.pdf`
- 数据通路：`768 kHz` 有符号 PCM 输入，抽取 8 倍后输出 `96 kHz`

## IP Core Generator 设置

在 `Tools -> IP Core Generator -> DSP and Mathematics -> Advanced FIR Filter` 中设置：

| 选项 | 设置值 |
| --- | --- |
| File Name | `fir_decimator_8x_ip` |
| Module Name | `fir_decimator_8x_ip` |
| FIR Type | `FIR Polyphase Decimator` |
| Input Data Width | `16` |
| Coefficient Data Width | `18` |
| Output Data Width | `33` |
| Multi-Channel Number | `1` |
| Factor Number | `8` |
| Taps Number | `128` |
| Time Division Multiplexing | `8` |
| Coefficient Reload | 关闭；Polyphase Decimator 不提供运行时重载 |
| Coefficient File | `ip/fir_decimator_8x/coeff_q17.txt` 的绝对路径 |
| Coefficient Memory Type | 若界面提供此项，选择 `BSRAM` |

系数文件按手册要求使用十进制纯文本，顺序为 `h0` 到 `h127`。系数为有符号 `Q1.17`，总和为 `131072`，即直流增益为 `1.0`。

## 接口约定

- `clk`：`50 MHz` 的 `sys_clk`。
- `rstn`：低有效复位。最终 wrapper 会统一项目侧命名。
- `fir_data_i[15:0]`：有符号 16 位 PCM。
- `fir_valid_i`：每个 `oversample_tick` 尝试送入一个样本，但只有 `fir_rfi_o=1` 时才允许拉高。
- `fir_sync_i`：单通道模式下与被接受的 `fir_valid_i` 同拍拉高。
- `fir_valid_o`：输出有效脉冲，期望平均速率为 `96 kHz`。
- `fir_sync_o`：单通道输出同步标志。
- `fir_data_o[32:0]`：滤波累加结果。wrapper 将按 `Q1.17` 做舍入、右移 17 位并饱和到有符号 16 位。

## 生成后需要保留

将 IP Core Generator 生成的完整目录放在本目录下，并保留配置文件、初始化系数、仿真模型和生成日志。生成后再编写 wrapper 和顶层连接。

当前生成记录：

- 生成目录：`src/advanced_fir_filter`
- 配置文件：`fir_decimator_8x_ip.ipc`
- 实际 IP 版本：`2.7`
- 生成时间：`2026-09-24 20:23:46`
- 本地封装：`src/fir_decimator_8x_wrapper.v`

## 验收项

1. IP Core Generator 接受全部参数和 128 个系数。
2. `fir_rfi_o` 在每个 `768 kHz` 输入时刻均为高，不产生输入丢失。
3. 每接受 8 个输入样本产生 1 个 `fir_valid_o`。
4. 直流输入稳态增益接近 1；20 kHz 幅度约为 `-0.29 dB`。
5. 48 kHz 抑制度约为 `-82.3 dB`，防止抽取后的镜像折叠到音频带。
