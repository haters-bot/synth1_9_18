# synth1_9_18

Gowin FPGA wavetable synthesizer project for the Tang Mega 138K platform.

Current audio path:

```text
USB-UART MIDI -> MIDI parser -> note/Unison task scheduler
              -> 4 generic oscillator engines x 8 TDM slots
              -> per-task ADSR + engine partial-sum mixer
              -> 8x FIR decimator -> PT8211 stereo DAC interface
```

The repository contains synthesizable RTL, constraints, FIR configuration,
simulation testbenches, the MIDI UART host tool, and project documentation.
Generated implementation output and local simulator artifacts are intentionally
excluded from version control.
