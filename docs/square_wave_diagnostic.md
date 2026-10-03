# Square-wave diagnostic

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
