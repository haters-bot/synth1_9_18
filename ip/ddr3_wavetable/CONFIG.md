# DDR3 波表存储控制器 IP 配置

## 用途

为板载 DDR3 提供控制器用户接口。第一阶段只连接独立 BIST，后续再连接
SD 卡装载器和波表缓存管理器。

## 依据

- 器件：`GW5AST-LV138PG484AC1/I0`
- 官方指南：`高云规范化文件/高云规范化文件/IPUG281-2.6_Gowin_DDR3_Memory_Interface_IP用户指南.pdf`
- 官方板卡例程：`TangMega-138K-example-main/ddr_memory/ddr_memory_test_uart`
- 用户接口时序：官方指南第 4.4.5～4.4.8 节

## IP Core Generator 设置

在当前工程中打开 DDR3 Memory Interface IP，并按下表设置。不同 EDA
版本的文字可能略有差异，以实际生成器和官方指南为准。

| 选项 | 设置值 |
| --- | --- |
| File Name | `ddr3_wavetable_ip` |
| 顶层模块 | `DDR3_Memory_Interface_Top` |
| User Interface | `Controller` |
| Memory Type | `DDR3` |
| Memory Clock | `400 MHz` |
| Clock Ratio | `1:4` |
| DQ Width | `32` |
| DRAM Width | `16` |
| Rank Width | `1` |
| Bank Width | `3` |
| Row Width | `15` |
| Column Width | `10` |
| Burst Mode | `BL8` |
| Burst Type | `Sequential` |
| CAS Latency | `6` |
| CAS Write Latency | `5` |
| Additive Latency | `0` |
| Address/Command Mode | `1T` |
| Output Drive | `HIGH` |
| RTT_NOM | `40 ohm` |
| RTT_WR | `OFF` |
| ECC | `OFF` |
| User Refresh | `OFF` |
| Arbitration Mode | `Mode4` |
| MC Storage | `BSRAM` |
| AXI4 Interface | `OFF` |
| Simulation | `OFF` |

时序参数与官方例程保持一致：

| 参数 | 数值 |
| --- | ---: |
| tRCD | 15000 ps |
| tRP | 15000 ps |
| tRC | 55000 ps |
| tRAS | 37500 ps |
| tRFC | 260000 ps |
| tREFI | 7800000 ps |
| tFAW | 40000 ps |
| tRRD | 10000 ps |
| tRTP | 7500 ps |
| tWTR | 7500 ps |
| tCKE | 10000 ps |
| tDLLK | 512 cycles |

生成后确认模板接口为：

- `addr[28:0]`
- `wr_data[255:0]`
- `wr_data_mask[31:0]`
- `rd_data[255:0]`
- `O_ddr_addr[14:0]`
- `O_ddr_ba[2:0]`
- `IO_ddr_dq[31:0]`
- `IO_ddr_dqs[3:0]`
- `IO_ddr_dqs_n[3:0]`

建议把生成文件完整保存到 `src/ddr3_memory_interface/`，并将厂商生成的实际
Verilog文件加入工程。`sim/ddr3_vendor_ip_stubs.v` 只供RTL检查，禁止加入
综合文件列表。

## 地址与数据粒度

当前配置中，一次 BL8 事务传输 `8 × 32 bit = 256 bit = 32 Byte`。厂商
接口的地址直接映射为 `Rank-Bank-Row-Column`，不是字节地址。连续事务地址
按 `8` 递增：`0、8、16、24...`。

## 生成后检查

1. 不手工修改厂商生成文件。
2. 把实际生成端口与 `src/ddr3_wavetable_wrapper.v` 对照。
3. 确认 `pll_stop`、`pll_lock`、`memory_clk` 和 `clk_out` 均存在。
4. 保留 `.ipc`、模板文件、生成日志和仿真模型。
5. 将厂商生成的物理布局要求与
   `constraints/tang_mega_138k_ddr3_standalone.cst` 合并检查。

## 当前阶段验收

- `init_calib_complete` 能稳定拉高。
- BIST 写入并读回64个256位数据块。
- `error_count=0`，状态 LED 常亮。
- 逻辑分析仪中地址按 `8` 递增。
