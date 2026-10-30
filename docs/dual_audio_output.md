# 双音频输出

工程同时输出两种串行音频格式，两路使用同一个96 kHz、16位单声道样本：

| 输出 | 格式 | 引脚 |
|---|---|---|
| 外接MAX98357A | 标准I2S | `MAX_BCLK=Y22`、`MAX_LRC=Y21`、`MAX_DIN=AB22` |
| 板载PT8211 | Japanese/LSBJ | `HP_BCK=Y17`、`HP_WS=AB17`、`HP_DIN=AA16` |

板载PT8211后接NS4263功率放大器，`PA_EN=AB16`为低电平有效，当前顶层固定输出低电平。
MAX98357A的`SD`和`GAIN`保持高电平，原有外接模块可以继续使用。

两个发送器使用同一个50 MHz系统时钟、同步复位和相同的BCK相位增量，因此帧边界一致。
768 kHz内部采样和96 kHz输出调度仍由MAX98357A发送器产生的tick驱动；板载发送器只负责
串行化最终音频样本，不会重复触发振荡器或效果链。

验证命令：

```powershell
vsim -c -do "do sim/run_dual_audio_output_test.do; quit -f"
vsim -c -do "do sim/run_full_top_elaboration.do; quit -f"
```
