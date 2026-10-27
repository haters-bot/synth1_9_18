# UI 板 ↔ 32 旋钮 PCB 调试 UART

## 引脚分配

| UI 板 FPGA 引脚 | 信号 | USB-TTL 端 | 说明 |
|---|---|---|---|
| `C14` | `debug_uart_tx` | RXD | UI 板输出调试/监视字节 |
| `E13` | `debug_uart_rx` | TXD | 预留的主机输入，当前版本不解析命令 |
| 任意 GND | 公共地 | GND | 必须连接 |

电气标准为 **3.3 V TTL、8N1**。调试构建的输出波特率为 115200；普通构建输出的是现有 MIDI 发送流（31250 baud）。禁止接 RS-232 电平或 5 V USB-TTL。

`C14` 的输出与板载 `U15` 监视输出保持同一数据流副本；它不占用 UI 到音频板的 `AB21` UART，也不改变旋钮板的 SPI 接线。`E13` 已锁定为输入脚，后续可增加主机命令或回读协议。

连接顺序：

```text
UI C14 (TX)  -> USB-TTL RXD
UI E13 (RX)  <- USB-TTL TXD
UI GND       -> USB-TTL GND
```
