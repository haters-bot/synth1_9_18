# synth1_9_18

Gowin FPGA wavetable synthesizer project for the Tang Mega 138K platform.

Current audio path:

```text
USB-UART MIDI -> MIDI parser -> channel/control router
              -> note/Unison task scheduler
              -> 4 generic oscillator engines x 8 pipelined TDM slots
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

## Shared UI integration

The UI Touch Hub is maintained as the `2_ui_touch_hub/` subproject on the
`ui-touch-hub-v1.0` collaboration branch; the audio synthesis top remains the
root `src/top.v.v`. The projects target separate Tang Mega 138K boards and
communicate over the versioned 31250-baud MIDI link described in
[`docs/ui_uart_integration_v1.md`](docs/ui_uart_integration_v1.md). Keep each
board's Gowin project, constraints, timing checks, and bitstream validation
independent. Cross-project handoff history is recorded in
[`docs/AI_COLLABORATION_LOG.md`](docs/AI_COLLABORATION_LOG.md).
