# SD卡到DDR波表存储路径

## 当前目标

分阶段建立真实波表数据路径：

```text
SD卡 -> 扇区BRAM双缓冲 -> DDR3 -> 波表BRAM缓存 -> TDM振荡器
```

本次只完成第一阶段：DDR3用户接口适配和独立写读回验证。现有音频顶层、
振荡器和I2S输出均未接入DDR3。

## 时钟域

| 时钟域 | 频率 | 用途 |
| --- | ---: | --- |
| `sys_clk` | 50 MHz | 外部参考时钟、SD卡读取和DDR IP参考时钟 |
| `memory_clk` | 400 MHz | DDR3 PHY，由专用PLL产生 |
| `user_clk` | 100 MHz | DDR控制器用户接口，由DDR IP输出 |
| `clk_sys` | 50 MHz | 现有音频系统PLL输出 |

SD卡和DDR用户接口属于异步时钟域。后续不会逐位同步数据，而会使用双口
扇区BRAM或异步FIFO完成跨域。

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

适配器内部将 Gowin IP 的命令和写数据通道分别保持到各自完成握手。因此即使
`cmd_ready` 与 `wr_data_rdy` 不在同一周期有效，也不会丢失命令或写数据。
第一版只允许一个未完成事务，方便确认正确性；SD卡的峰值速率远低于DDR带宽，
不会因此形成瓶颈。

### `ddr3_bist`

默认从地址0开始：

1. 向64个地址写入不同的256位模式。
2. 地址依次为 `0、8、16...504`。
3. 逐项读回并比较。
4. 保存错误数量、首个错误地址、期望值和实际值。

总测试数据量为 `64 × 32 Byte = 2 KiB`。

### `ddr3_standalone_test_top`

这是单独的板测顶层，不替换当前音频 `top`。DDR校准完成后自动启动BIST。
V13状态LED低有效：

| 状态 | LED行为 |
| --- | --- |
| PLL或DDR未完成初始化 | 熄灭 |
| BIST运行中 | 慢闪 |
| BIST通过 | 常亮 |
| BIST失败 | 快闪 |

## 下一阶段接口

SD卡每扇区输出512字节，DDR一次事务接收32字节，因此一个扇区正好对应
16次DDR写入。后续使用两个512字节双口BRAM交替工作：

```text
50 MHz SD侧：逐字节写入当前扇区缓冲
100 MHz DDR侧：每次取32字节，连续执行16次DDR写入
```

这一结构同时解决字节打包、速率差和时钟域跨越问题。

## 已知限制

- 厂商DDR3 IP和DDR PLL尚需用户在Gowin EDA中手动生成。
- 当前未把独立DDR测试顶层加入主工程文件列表。
- 当前RTL仿真验证用户接口协议，不模拟DDR3 PHY训练和板级信号完整性。
- 真正接入音频前，还需要完成SD扇区缓冲、DDR地址分配和波表缓存管理器。
