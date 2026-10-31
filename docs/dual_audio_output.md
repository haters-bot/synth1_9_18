# 外接I2S音频输出

工程输出一组96 kHz、左右声道独立的16位标准I2S信号，并将信号镜像到可视化接口：

| 输出 | 格式 | 引脚 |
|---|---|---|
| 外接I2S DAC | 标准I2S | `MAX_BCLK=Y22`、`MAX_LRC=Y21`、`MAX_DIN=AB22` |
| 可视化接口 | 标准I2S镜像 | `VIS_BCLK=R19`、`VIS_LRC=U21`、`VIS_DIN=R17` |

MAX98357A的`SD`和`GAIN`保持高电平。PCM5102A可直接使用BCK、LCK和DIN，模块其余模式引脚
按模块要求配置。板载PT8211与NS4263输出链路已经从顶层和引脚约束中移除。

768 kHz内部采样和96 kHz输出调度仍由I2S发送器产生的tick驱动。可视化接口仅组合镜像
同一组I2S信号，不会重复触发振荡器或效果链。

验证命令：

```powershell
vsim -c -do "do sim/run_i2s_tx_test.do; quit -f"
vsim -c -do "do sim/run_full_top_elaboration.do; quit -f"
```
