# synth1_9_18

Gowin FPGA wavetable synthesizer project for the Tang Mega 138K platform.

Current audio path:

```text
fixed A4 debug Note On -> note/Unison task scheduler
                       -> 4 generic oscillator engines x 8 TDM slots
                       -> per-task ADSR + engine partial-sum mixer
                       -> 8x FIR decimator -> PT8211 stereo DAC interface
```

The hardware top level is temporarily in fixed-note debug mode. It emits one
MIDI-note-69 event after reset, expands it into three Unison oscillator tasks
by default, and does not expose the USB-UART receive pin. The reusable UART
receiver and MIDI parser sources remain in the repository for restoration
after waveform debugging.

The repository contains synthesizable RTL, constraints, FIR configuration,
simulation testbenches, the MIDI UART host tool, and project documentation.
Generated implementation output and local simulator artifacts are intentionally
excluded from version control.
