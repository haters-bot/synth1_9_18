# SD 卡到 DDR 波表存储路径

## 当前目标

分阶段建立真实波表数据路径：

```text
SD 卡 -> 扇区 BRAM 双缓冲 -> DDR3 -> 波表 BRAM 缓存 -> TDM 振荡器
```

本阶段只完成 DDR3 用户接口适配和独立写读回验证。现有音频顶层、振荡器和 I2S 输出尚未接入 DDR3。

## 时钟域

| 时钟域 | 频率 | 用途 |
| --- | ---: | --- |
| `sys_clk` | 50 MHz | 外部参考时钟、状态串口和后续 SD 卡读取 |
| `memory_clk` | 400 MHz | DDR3 PHY，由专用 PLL 产生 |
| `user_clk` | 100 MHz | DDR 控制器用户接口，由 DDR IP 输出 |
| `clk_sys` | 50 MHz | 现有音频系统 PLL 输出 |

SD 卡和 DDR 用户接口属于异步时钟域。后续使用双口扇区 BRAM 或异步 FIFO 完成跨域，不逐位同步数据总线。

## 第一阶段模块

### `ddr3_user_port_adapter`

向上提供单事务接口：

```text
req_valid/req_ready
req_write
req_addr[28:0]
req_wdata[255:0]
req_wmask[31:0]

rsp_valid
rsp_write
rsp_rdata[255:0]
rsp_error
```

适配器分别保持 Gowin IP 的命令与写数据通道，直到各自完成握手。即使 `cmd_ready` 与 `wr_data_rdy` 不在同一周期有效，也不会丢失命令或写数据。第一版只允许一个未完成事务，便于验证正确性；SD 卡峰值速率远低于 DDR 带宽，不会因此形成瓶颈。

### `ddr3_bist`

默认从地址 0 开始：

1. 向 64 个地址写入不同的 256 位测试模式。
2. 地址依次为 `0、8、16...504`。
3. 逐项读回并比较。
4. 保存错误数量、首个错误地址、期望值和实际值。

总测试数据量为 `64 × 32 Byte = 2 KiB`。

### `ddr3_standalone_test_top`

这是独立板测顶层，不替换当前音频 `top`。DDR 校准完成后自动启动 BIST。

NEO Dock 原理图中 V13 对应 `USR_CLK_IN`，不能作为状态 LED。状态改由板载 USB 串口 TX 引脚 U15 输出，串口格式为 `115200 baud, 8N1`。

| 阶段 | 串口输出 |
| --- | --- |
| 顶层复位释放 | `DDR TEST START` |
| DDR 校准完成 | `DDR INIT OK` |
| BIST 通过 | `DDR BIST PASS` |
| BIST 失败 | `DDR BIST FAIL` |

每条消息以 `CR LF` 结尾，并且每次上电只发送一次。`init_done`、`test_finished` 和 `test_passed` 从 100 MHz 用户域同步到 50 MHz 串口域；结果标志在完成信号稳定后再采样。

## 下一阶段接口

SD 卡每扇区输出 512 字节，DDR 一次事务接收 32 字节，因此一个扇区对应 16 次 DDR 写入。后续使用两个 512 字节双口 BRAM 交替工作：

```text
50 MHz SD 侧：逐字节写入当前扇区缓冲
100 MHz DDR 侧：每次取 32 字节，连续执行 16 次 DDR 写入
```

这一结构同时解决字节打包、速率差和时钟域跨越问题。

## 已知限制

- 厂商 DDR3 IP 和 DDR PLL 由用户在 Gowin EDA 中生成。
- `ddr3_status_uart.v` 必须加入独立 DDR 测试工程的源文件列表。
- 当前 RTL 仿真验证用户接口协议和状态串口，不模拟 DDR3 PHY 训练与板级信号完整性。
- 真正接入音频前，还需完成 SD 扇区缓冲、DDR 地址分配和波表缓存管理器。
