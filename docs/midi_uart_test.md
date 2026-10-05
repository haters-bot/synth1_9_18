# USB-UART MIDI测试说明

> 当前硬件顶层为了使用 GAO 检查内部音频波形，暂时切换为固定 A4
> 调试音符，并移除了 `uart_rx` 顶层端口和 V14 约束。本页保留为恢复
> USB-UART MIDI 输入时的接线与测试参考。

## 数据通路

```text
电脑上位机
  -> JTAG|UART USB-C接口
  -> 板载USB-UART
  -> FPGA V14 (uart_rx)
  -> UART接收器
  -> MIDI Note On/Off解析器
  -> 32槽位音符分配器
  -> TDM振荡器、FIR和PT8211
```

FPGA默认使用标准MIDI串口格式：`31250 baud, 8N1`。接收所有16个MIDI通道，
当前支持Note On、Note Off、Running Status以及`Note On velocity=0`形式的Note Off。
音符范围为MIDI 21～108；超出88键频率表的音符会被忽略。

当前版本使用力度判断Note On/Off，但尚未把力度映射为振幅；ADSR和力度响应将在后续加入。

## 上位机运行

安装Python 3后，在工程根目录执行：

```powershell
python -m pip install -r tools/requirements.txt
python tools/midi_uart_sender.py
```

操作步骤：

1. 使用PCB上标有`JTAG|UART`的USB-C接口连接电脑。
2. 下载位流后关闭Gowin Programmer，避免其继续占用调试器。
3. 在上位机中选择标记为`FTDI B / UART推荐`的端口，波特率选择31250并连接。
4. 鼠标按住虚拟琴键，或者使用电脑键盘`A W S E D F T G Y H U J K`演奏。
5. 松开按键会发送Note Off；“全部停止”会逐个释放当前由上位机开启的音符。

如果31250 baud无法工作，可将FPGA顶层参数`UART_BAUD_RATE`改为115200，重新生成位流，
并在上位机中选择115200。电脑和FPGA两端的波特率必须完全一致。

部分旧版板载调试器固件会让实际UART速率变成设置值的四倍。在FPGA仍使用31250时，
可以先在上位机波特率框输入`7812`进行诊断；若此时能够发声，说明应更新板载调试器
固件，而不是修改MIDI解析逻辑。

## 槽位分配规则

```text
同一个音符再次Note On：重用原槽位并把相位清零
新音符：使用最低编号的空闲槽位
32个槽位全满：使用循环指针偷取一个槽位
Note Off：关闭保存该音符的槽位，并冻结其相位
```

当前直接关闭非零波形可能产生轻微咔哒声。加入ADSR后，Note Off应先进入Release，
包络衰减到零后再真正关闭槽位。
