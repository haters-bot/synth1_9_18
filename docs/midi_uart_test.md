# USB-UART MIDI测试说明

> 当前硬件顶层同时提供V14板载USB-UART调试RX和PMOD1 IO2/AB21跨板RX，
> 默认31250 baud、8N1。两路RX在逻辑上合并；每次只从一个UART TX发包。

## 数据通路

```text
电脑上位机
  -> JTAG|UART USB-C接口
  -> 板载USB-UART
  -> FPGA V14 USB-UART RX 或 PMOD1 IO2/AB21 (跨板 `midi_gpio_rx`)
  -> UART接收器
  -> MIDI消息解析器和通道路由器
  -> 32槽位音符分配器
  -> TDM振荡器、FIR和MAX98357A I2S输出
```

FPGA默认使用标准MIDI串口格式：`31250 baud, 8N1`。板间连线为UI板J8 pin 9
（PMOD1 IO2/AB21）到音频板J8 pin 9，J8 pin 3或4共地；不要连接PMOD电源脚。
PMOD1 IO2还复用DVP/SDRAM1扩展信号，接线前拔除/避免相机和SDRAM1扩展设备。
解析器可以识别所有16个
MIDI通道，路由器只允许通道1的Note On/Off进入声部调度器，并只允许通道16的
Control Change写入合成参数。当前支持Running Status以及`Note On velocity=0`
形式的Note Off。
音符范围为MIDI 21～108；超出88键频率表的音符会被忽略。

力度会随Note On事件绑定到该音符的全部Unison任务，并在每个振荡器槽位中按
`velocity/128`近似映射为线性振幅；力度127保持满幅。移动上位机力度滑块只影响
之后触发的新音符，已经持续发声的音符保持其Note On时的力度。

通道16的CC21控制OSC A波形，CC29控制OSC B波形，按照控制值分档：

| CC21或CC29数值 | 对应振荡器波形 |
|---:|---|
| 0～31 | 正弦波 |
| 32～63 | 三角波 |
| 64～95 | 方波 |
| 96～127 | 锯齿波 |

复位默认值为方波。切换只改变共享波形读取来源，不会清除各槽位相位。
完整音频参数表见[`midi_control_protocol.md`](midi_control_protocol.md)；
UI v1跨板实际映射见[`ui_uart_integration_v1.md`](ui_uart_integration_v1.md)。

## 上位机运行

安装Python 3后，在工程根目录执行：

```powershell
python -m pip install -r tools/requirements.txt
python tools/midi_uart_sender.py
```

操作步骤：

1. 使用PCB上标有`JTAG|UART`的USB-C接口连接电脑，或按跨板GPIO方案连接UI板和音频板；两路不可同时发包。
2. 下载位流后关闭Gowin Programmer，避免其继续占用调试器。
3. 在上位机中选择标记为`FTDI B / UART推荐`的端口，波特率选择31250并连接。
4. 鼠标按住虚拟琴键，或者使用电脑键盘`A W S E D F T G Y H U J K`演奏。
5. 使用双振荡器参数区域分别发送OSC A/B的WT Position、Detune、Unison和ADSR控制。
6. 松开按键会发送Note Off；“全部停止”会逐个释放当前由上位机开启的音符。

若更改`UART_BAUD_RATE`，所有发送端必须同时改到相同波特率；UI正式联调基线固定31250。

部分旧版板载调试器固件会让实际UART速率变成设置值的四倍。在FPGA仍使用31250时，
可以先在上位机波特率框输入`7812`进行诊断；若此时能够发声，说明应更新板载调试器
固件，而不是修改MIDI解析逻辑。

## 槽位分配规则

```text
同一个音符再次Note On：按当前Unison数量重建该音符的任务组
新音符：按轮转顺序把Unison成员均衡分布到四个物理引擎
32个槽位全满：整组替换一个旧音符，避免只偷取部分Unison成员
Note Off：关闭该音符全部任务的Gate，等待ADSR Release归零后回收槽位
```

当前Note Off已经先进入ADSR Release，包络衰减到阈值以下后再关闭槽位。
