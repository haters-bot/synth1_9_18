# Square-wave diagnostic

> 该文件记录早期固定方波诊断。当前版本已通过MIDI CC21/CC29分别选择OSC A/B波形，
> 复位后仍默认使用方波。

The shared oscillator is temporarily connected to `square_lut` to identify
whether unexpected timbre comes from waveform generation or from the later
FIR, DAC, amplifier, or speaker stages.

The lookup output is a DC-balanced hard square wave:

- phase `0x00` through `0x7f`: `+32767`
- phase `0x80` through `0xff`: `-32767`

This waveform is deliberately not band-limited. It should sound much brighter
than the previous triangle wave, but high notes can alias. Note-on transients
may also be more obvious because a reset phase starts at full positive level.
It is intended only as a short listening test.
