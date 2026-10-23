# SD 卡到 DDR 波表存储路径

## 当前目标

分阶段建立真实波表数据路径：

```text
SD 卡 -> 扇区 BRAM 双缓冲 -> DDR3 -> 波表 BRAM 缓存 -> TDM 振荡器
```

DDR3独立写读回阶段已经完成，当前版本进一步接入SD文件读取、异步FIFO、两组双帧
缓存和原有音频振荡器。完整文件格式与使用方法见`docs/sd_ddr_wavetable_path.md`。

## 时钟域

| 时钟域 | 频率 | 用途 |
| --- | ---: | --- |
| `sys_clk` | 50 MHz | 外部参考时钟、状态串口和后续 SD 卡读取 |
| `memory_clk` | 400 MHz | DDR3 PHY，由专用 PLL 产生 |
| `user_clk` | 100 MHz | DDR 控制器用户接口，由 DDR IP 输出 |
| `clk_sys` | 50 MHz | 现有音频系统 PLL 输出 |

SD卡和DDR用户接口属于异步时钟域。当前使用256位异步FIFO完成负载跨域，不逐位
同步数据总线。

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

## SD到DDR接口

SD卡每扇区输出512字节，DDR一次事务接收32字节，因此一个扇区对应16次DDR写入。
当前实现使用8深度、每项256 bit的异步FIFO：

```text
50 MHz SD侧：跳过32字节WTB1头，把负载每32字节打包
100 MHz DDR侧：从异步FIFO取出256 bit数据并逐事务写入DDR
```

DDR写入完成后，OSC A/B缓存控制器按需各读取相邻两帧。每个缓存采用双bank，
新帧全部写完才原子切换，避免音频侧读到半更新波表。

## 已知限制

- 厂商 DDR3 IP 和 DDR PLL 由用户在 Gowin EDA 中生成。
- `ddr3_status_uart.v` 必须加入独立 DDR 测试工程的源文件列表。
- 当前RTL仿真验证用户接口、SD字节打包、DDR事务、缓存换帧和音频回归，不模拟
  DDR3 PHY训练与板级信号完整性。
- SD控制器当前读取根目录第0个普通文件；板测阶段建议卡中只保留一个WTB1文件。
