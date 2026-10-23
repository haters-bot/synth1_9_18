# AI Collaboration Change Log

Purpose: durable handoff record for AI-assisted changes made on the shared UI/audio integration branch. Each entry records touched files, verification, limits, and the associated commit once pushed.

## 2026-10-23 — Phase 1 UART integration baseline

Status: RTL implementation and simulation passed. UI source snapshot: `0dfae7c995bc7029f1253c8c4843a10eb3d4376f`; source archive SHA256: `A5D30CBDA828C9B19CEAE0D8E26802D0E3999D3B71EC211F8038D57F421FA9B1`. Shared implementation commit: `db851cd` on `integration/dual-138k-uart-phase1`; GitHub push is pending.

### Branch synchronization

- Fast-forwarded local `ui-touch-hub-v1.0` to the existing remote collaboration head `5bf0f8f`.
- Created `integration/dual-138k-uart-phase1` from the synchronized `ui-touch-hub-v1.0` collaboration branch and merged current `origin/main` (`3f2bed2`, effects / DDR wavetable / three-LFO updates). Kept UI sources under `2_ui_touch_hub/`; no audio source directory was replaced.
- The independent UI source checkout remains `D:\github\gaoyun\2_ui_touch_hub`; it has no Git remote. The shared `2_ui_touch_hub/` snapshot is being synchronized to committed UI source `0dfae7c`; uncommitted navigation-font experiments and local session archives are excluded.

### Intended changes

- Add a dedicated audio-board GPIO RX input at PMOD1 IO2 / AB21 while retaining V14 for the onboard USB-UART debug path. Both RX pins are active-high idle and logically combined; simultaneous transmitters are unsupported.
- Add a UI-board dedicated GPIO TX output at PMOD1 IO2 / AB21 while retaining U15 for board USB-UART monitoring. Debug firmware keeps the cross-board audio line idle.
- Align supported UI CCs to the latest `synth_control_router` table; suppress unimplemented/local-only IDs so they cannot alias into Phaser, Compressor, or other unrelated CC targets.
- Add UI transmitter tests for A/B separation, waveform conversion, cutoff/resonance/mix, ENV A, master level, unison clamp, and unsupported Hold suppression.
- Add an audio top-level test that sends a valid CC through the new PMOD RX while existing tests continue using the V14 USB-UART RX.
- Maintain `docs/ui_uart_integration_v1.md` as the shared mapping/pin source, `docs/REPOSITORY_GUIDE.md` as the branch/build layout guide, and this file as the change history.

### Hardware wiring proposal

- UI J8 pin 9 (PMOD1 IO2/AB21) → Audio J8 pin 9 (PMOD1 IO2/AB21).
- UI J8 pin 3 or 4 GND → Audio J8 pin 3 or 4 GND.
- Do not connect the PMOD 3.3 V pins. Remove/avoid camera and SDRAM1 expansion devices on the PMOD1/DVP shared nets while testing.
- This avoids connecting UI TX to audio V14, which is also driven by the board's USB-JTAG/USB-UART bridge. It is a low-risk GPIO solution, not a guarantee against incorrect cabling or attached expansion hardware.

### Verification record

- UI MIDI TX ModelSim: PASS — Note On/Off, CC20, remapped CC43, separate OSC B CCs, waveform conversion, Unison clamp, Filter 44/45, ENV A, Master 48, unsupported Hold suppression, and queued Note priority.
- UI curve/parameter regression (`tools/test_curve_editor.py`): PASS — filter XY/notch, ENV handles, independent local ENV banks, UART serial MIDI, pending-value coalescing, parameter merger pairing and arbitration.
- Audio `sim/run_top_midi_test.do`: PASS — full audio top compiled; PMOD GPIO RX independently received CC20, while legacy V14 path continued passing the existing audio tests.
- Gowin synthesis/P&R: not run in this change; audio repository instructions prohibit automatic synthesis solely for verification. Physical board test is pending user wiring.
- No bitstream programming, Flash operation, or physical wiring performed by the AI.

### Files

- `src/top.v.v`
- `constraints/tang_mega_138k_full_synth.cst`
- `constraints/tang_mega_138k_audio_test.cst`
- `sim/tb_top_midi_input.v`
- `sim/tb_top_dual_unison8.v`
- `2_ui_touch_hub/rtl/midi_uart_tx/midi_uart_tx.v`
- `2_ui_touch_hub/rtl/param_merger/param_merger.v`
- `2_ui_touch_hub/rtl/ui_touch_hub_top.v`
- `2_ui_touch_hub/rtl/ui_touch_hub_debug_top.v`
- `2_ui_touch_hub/constraints/ui_touch_hub.cst`
- `2_ui_touch_hub/sim/tb_midi_uart_tx.v`
- `2_ui_touch_hub/sim/tb_param_merger.v`
- `2_ui_touch_hub/sim/tb_curve_touch_editor.v`
- `2_ui_touch_hub/doc/MIDI_CONTROL_PROTOCOL.md`
- `2_ui_touch_hub/doc/HARDWARE_WIRING_PINOUT.md`
- `2_ui_touch_hub/doc/DUAL_138K_UART_INTEGRATION_PLAN_2026-10-23.md`
- `README.md`
- `docs/midi_uart_test.md`
- `docs/REPOSITORY_GUIDE.md`
- `docs/ui_uart_integration_v1.md`

Future entries should append a dated section and never rewrite prior verification results. Distinguish source commit, build result, bitstream hash, board used, UART path, and user acceptance.
