# synth1_9_18

Gowin FPGA wavetable synthesizer project for the Tang Mega 138K platform.

Current audio path:

```text
USB-UART MIDI -> MIDI parser -> channel/control router
              -> note/Unison task scheduler
              -> 4 generic oscillator engines x 16 pipelined TDM slots
              -> basic waveforms or 16-frame Acid wavetable with WT Position
              -> per-task ADSR + engine partial-sum mixer
              -> 8x FIR decimator -> MAX98357A standard I2S interface
```

The hardware top level accepts MIDI Note On and Note Off on MIDI channel 1,
and synthesizer Control Change messages on MIDI channel 16. Unison count,
detune depth, and global ADSR parameters are runtime controls; the current
default is one oscillator task per note. Note Off closes the task gates, lets
the per-task ADSR envelopes finish their Release stage, and then returns those
task slots to the idle pool.

The repository contains synthesizable RTL, constraints, FIR configuration,
simulation testbenches, the MIDI UART host tool, and project documentation.
Generated implementation output and local simulator artifacts are intentionally
excluded from version control.

## LFO V2（2026-10-28）

[接入与联调说明](docs/lfo_v2_integration.md)：3路七节点Hermite曲线、53固定绑定目标、Once/Stepped、双缓冲提交，以及双振荡器Phase/Rand。桌面调试工具已使用V2；触屏发送器需按说明同步。
