# synth1_9_18

Gowin FPGA wavetable synthesizer project for the Tang Mega 138K platform.

Current audio path:

```text
USB-UART MIDI -> MIDI parser -> channel/control router
              -> note/Unison task scheduler
              -> 4 generic oscillator engines x 8 TDM slots
              -> per-task ADSR + engine partial-sum mixer
              -> 8x FIR decimator -> MAX98357A standard I2S interface
```

The hardware top level accepts MIDI Note On and Note Off on MIDI channel 1,
and synthesizer Control Change messages on MIDI channel 16. Unison count and
detune depth are runtime controls; the current default is one oscillator task
per note. Note Off closes the task gates, lets the per-task ADSR envelopes
finish their Release stage, and then returns those task slots to the idle pool.

The repository contains synthesizable RTL, constraints, FIR configuration,
simulation testbenches, the MIDI UART host tool, and project documentation.
Generated implementation output and local simulator artifacts are intentionally
excluded from version control.
