# AI Collaboration Change Log

Purpose: durable handoff record for AI-assisted changes made on the shared UI/audio integration branch. Each entry records touched files, verification, limits, and the associated commit once pushed.

## 2026-10-26 04:48 — TXE8148 32-encoder SRAM deployment

- Deployed commit `76a7fb9` with `tools/deploy_verified.py --target sram` to engineering host `10.136.125.157`.
- Gowin Programmer identified `GW5AST-138B (0x0001081B)`, completed SRAM programming at 100%, returned `PROGRAMMER_EXIT=0`, status `0x00026230`, User Code `0x000014A6`, and 22.68 s elapsed.
- Deployment run `2_ui_touch_hub/impl/deploy_runs/20261026_044804_TXE8148_EC11_SPI_76A7FB9/` contains the manifest, programmer log, preview and telemetry. Local/remote bitstream SHA256 is `E0246684F67C3D155519FCA57182DD2619F45E2F2D482269FDFCCF6F7FCDF54F`.
- Camera preview shows the normal six-window UI. This confirms SRAM programming and video output; physical validation of each of the 32 encoder A/B/SW inputs remains pending. Flash was not touched.

## 2026-10-26 04:32 — TXE8148 dual-chip / 32-EC11 SPI intake implemented

- Replaced `2_ui_touch_hub/rtl/knob_spi_intake/knob_spi_rx.v` with a TXE8148 SPI mode-0 polling master. It reads both chips independently, decodes the `A/B/SW` triplets for 32 EC11 encoders, emits absolute 0..127 parameter events, and routes the first six push switches to existing UI buttons.
- Updated normal/debug top-level ports and `2_ui_touch_hub/constraints/ui_touch_hub.cst` for `2CS# A15`, `1CS# B20`, `SCLK B21`, `SDI B17`, `SDO D17`, `INT# A18`, `RESET D14`. The keyboard panel VCC is documented as a separate 5 V Type-C input; no FPGA I/O is used as a power rail.
- Added `2_ui_touch_hub/doc/TXE8148_EC11_SPI_INTEGRATION.md` and updated `HARDWARE_WIRING_PINOUT.md` with GPIO order, provisional UI parameter map, button map, and 5 V/3.3 V level boundaries.
- Gowin local build completed in `2_ui_touch_hub/impl/pnr/`: Setup/Hold violations 0, `clk_pixel` Fmax 50.656 MHz, bitstream SHA256 `E0246684F67C3D155519FCA57182DD2619F45E2F2D482269FDFCCF6F7FCDF54F`.
- Hardware boundary: no SRAM/Flash deployment was performed. The keyboard board's SDO voltage must be confirmed before connecting it to FPGA input D17. Commit: `4ce34cd`.

## 2026-10-26 03:30 — Latest LFO SysEx UI confirmed on screen after power fix

- After the UI display power connection was corrected, the final LFO SysEx bitstream was written again in run `impl/deploy_runs/20261026_033031_LFO_SYSEX_V2_CURRENT_AFTER_POWER_FIX/`.
- SRAM programming completed with `PROGRAMMER_EXIT=0`, status `0x00026230`, User Code `0x000030AF`, and SHA256 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`.
- The returned `preview.jpg` now shows the expected UI six-window visualization page. The earlier black-screen A/B result was caused by the display power connection; the LFO SysEx bitstream is currently restored and visibly running. Flash remains untouched.

## 2026-10-26 03:24 — Black-screen A/B check after LFO SysEx deployment

- The current LFO SysEx bitstream was first confirmed in SRAM (`User Code 0x000030AF`), but the engineering-host camera captured a black monitor with only intermittent visible output.
- As an A/B check, the previously accepted R17B HD-font bitstream (`C82CFF39CFE71C53619A7706B918F3CDD58C0D9E1772795C12C3D5B5AA9E7EF`, prior deployment `20261025_192830_R17B_HD_FONT`) was written to SRAM using run `20261026_032317_R17B_HD_FONT_RECHECK`; it also completed with `PROGRAMMER_EXIT=0`, yet the returned camera frame remained black.
- The current LFO SysEx bitstream was restored in run `20261026_032427_LFO_SYSEX_V2_RESTORE_CURRENT`, again with `PROGRAMMER_EXIT=0` and the expected hash. This A/B result does not support attributing the black screen to the LFO SysEx RTL; HDMI/display input, board reset state, or the display link still requires physical inspection.

## 2026-10-26 03:18 — LFO SysEx V2 UI bitstream programmed to SRAM

- First deployment attempt at `2026-10-25 23:04` transferred and hash-verified the final bitstream but Gowin Programmer returned `PROGRAMMER_EXIT=50` before progress; the failure is preserved in `2_ui_touch_hub/impl/deploy_runs/20261025_230403_LFO_SYSEX_V2_TIMING_CLOSED/`.
- After the UI board and Gowin USB cable were reconnected, read-only JTAG identification returned ID `0x0001081B`, then `tools/deploy_verified.py --target sram` completed run `impl/deploy_runs/20261026_031805_LFO_SYSEX_V2_TIMING_CLOSED_RETRY/`: 100% SRAM programming, status `0x00026230`, `PROGRAMMER_EXIT=0`, remote SHA256 matched `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`.
- `preview.jpg` and `telemetry.png` were returned by the engineering-host camera, proving the camera path ran; the captured monitor is black, so physical display/HDMI acceptance is still pending. The deployment is recorded as SRAM programmed, with Flash untouched.
- The board-visible behavior is not yet accepted from this capture. Audio-side SysEx V2 receive and modulation computation remain unimplemented, so this deployment only validates the UI transmitter bitstream and its outgoing UART behavior.

## 2026-10-25 23:00 — UI LFO SysEx timing closed; SRAM deployment candidate (ZCode + Codex)

- ZCode's uncommitted UI LFO SysEx V2 implementation and protocol document were preserved unchanged in function: `lfo_sysex_tx.v`, MIDI SysEx injection ports, top-level `u_lfo_sysex` wiring, project registration, and `tb_lfo_sysex_tx.v`. The audio board still has no SysEx receiver; unsupported IDs are ignored, so this build does not claim audio-side modulation.
- Codex retained the original failing builds and audits, then added one physical constraint to `2_ui_touch_hub/constraints/ui_touch_hub.cst`: `u_render/u_navigation_render/ch1_0_s0` at `R35C151[0][A]`, taken from the previously timing-closed high-resolution build. The attempted source and parameter anchors were removed after their audits showed placement regression; no timing waiver or frequency reduction was used.
- Final isolated build: `2_ui_touch_hub/impl/R16A_build_20261025_224744/`; audit `audit_20261025_225837_331586.json`; source/snapshot mismatches empty; setup `+0.171 ns`, hold `+0.196 ns`, recovery `+0.100 ns`, removal `+0.497 ns`, pulse width `+0.453 ns`; all five violation classes zero; `timing_closed=true`; bitstream SHA256 `01724C38F29E3C4C40729BFDA7C634451052DB99F0E87855C9B2302EBBBB9EC2`.
- Regression after the constraint: `tb_lfo_sysex_tx` 94 checks PASS and `tb_midi_uart_tx` 100% PASS. ModelSim emits its normal post-`$finish` diagnostic, while both processes exit 0.
- Deployment boundary: SRAM only after the coordinated commit/push; Flash remains paused. The expected board-visible UI is the already deployed R17B HD-font UI, with additional outgoing SysEx traffic only. Physical audio modulation remains pending the audio-side V2 receiver/core.

## 2026-10-23 — Phase 1 UART integration baseline

Status: RTL implementation and simulation passed. UI source snapshot: `0dfae7c995bc7029f1253c8c4843a10eb3d4376f`; source archive SHA256: `A5D30CBDA828C9B19CEAE0D8E26802D0E3999D3B71EC211F8038D57F421FA9B1`. Shared implementation commits: `db851cd` and `bf896e4` on `integration/dual-138k-uart-phase1`; branch pushed to `origin/integration/dual-138k-uart-phase1` on 2026-10-24.

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

## 2026-10-25 19:28 — R17B HD-font bitstream deployed to UI board SRAM (ZCode)

- Operator: ZCode agent, on explicit user instruction. Bitstream built and audited by Codex earlier the same day; ZCode performed deployment only.
- Source: commit `b8b7efd` isolated build `2_ui_touch_hub/impl/R16A_build_20261025_184819/`, audit `audit_20261025_185815_975286.json` (timing_closed, five violation classes clean, clk_pixel 52.35 MHz). Re-audit inside deploy script passed; input snapshot matched HEAD.
- Deploy: `tools/deploy_verified.py --label R17B_HD_FONT --target sram`, run `impl/deploy_runs/20261025_192830_R17B_HD_FONT/`. Bitstream SHA256 `C82CFF39CFE71C53619A7706B918F3CDD58C0D9E1772795C12C3D5B5AA9E7EF` matched on both machines. GW5AST-138B, operation 2 SRAM, 23.06 s, Status Code `0x00026230`, PROGRAMMER_EXIT=0. Flash untouched.
- Camera capture `preview.jpg` shows a lit UI screen with full interface; this proves the board runs the new bitstream, not readability acceptance. User visual/interaction acceptance of the HD navigation font is pending.
- Two earlier deploy attempts (19:11 TCP unreachable; 19:16 firmware.zip HTTP transfer reset mid-way) reached no programming; leftover half zip may remain under remote `D:/gaoyun_deploy/` timestamped dirs and is harmless. Root cause of the flaky link: ZeroTier peer was RELAY-only (see session records); engineering PC also went unresponsive ~19:16 (suspected idle sleep), recovered before this deploy.

## 2026-10-25 20:05 — LFO modulation protocol V2 drafted (ZCode)

- User decision recorded: UI board is display+control only (LFO modulation shown as visual preview, static CC values transmitted unchanged); all real modulation is computed on the audio board from CC base values + LFO configuration sent as SysEx. The audio-side LFO math must be reworked to match the UI model (7-point C1 monotone cubic Hermite with minmod tangents, 384-phase table, 0.25×2^r Hz, 53 per-target routes, formula `clamp(base + depth×wave/128, 0, 127)`), replacing the current 3-point/two-curvature model.
- Deliverable: `docs/UI_LFO_MODULATION_PROTOCOL_V2.md` — data model, exact math incl. fixed-point bit widths and a Python golden model, SysEx ID plan 48–126 (no overlap with existing 16–46), phase-sync and commit frames, audio-side rework checklist, and a corrected UI-parameter/destination mapping table (note: `mod_targets.vh` IDs are decimal, first draft of the table misread them as hex — table rewritten against `params.vh`).
- No RTL changed on either side in this entry; UI transmitter implementation and audio-side core rework are tracked as follow-ups in the protocol §6/§7.

## 2026-10-25 20:45 — UI-side LFO SysEx transmitter implemented (ZCode, uncommitted, timing gate open)

- Implemented protocol §7 items 1–4 in the UI RTL (working tree of `integration/dual-138k-uart-phase1`, NOT committed — Mimosa blocks commits on unrelated legacy findings; `git diff` shows everything):
  - NEW `2_ui_touch_hub/rtl/midi_uart_tx/lfo_sysex_tx.v`: snapshots the LFO config after a 20 ms quiet window, diffs against the last committed shadow, streams changed 6-byte frames (`F0 7D id msb lsb F7`, IDs 48–126 per protocol V2), phase-sync frame ID72 rides along curve/mode edits, batch ends with atomic commit ID126. Pipelined per-entry change vectors + 77-bit signature edit detection (no wide comparators in one level).
  - `rtl/midi_uart_tx/midi_uart_tx.v`: added `sysex_req/sysex_msgs[47:0]/sysex_accept` (combinatorial accept prevents double-push). Note/CC keep same-cycle priority; SysEx enters only with ≥2 free FIFO slots.
  - `rtl/ui_touch_hub_top.v`: wired the renderer snapshot outputs to a new `u_lfo_sysex` instance feeding `u_midi_tx`.
  - `2_ui_touch_hub.gprj`: registered the new file. `sim/tb_lfo_sysex_tx.v` NEW (94 checks, ALL PASS); `sim/tb_midi_uart_tx.v` port-tied for the new inputs (regression 100% PASS); full top compiles clean under `-sv`, elaborates to the device-primitive boundary.
- Timing status: three build/audit rounds converged −3.685 → −2.933 → **−0.056 ns** setup (hold/recovery/removal/pulse all positive). The remaining single violation `u_render/u_navigation_render/id0_5_s0 → ch1_0_s0` (−0.056) is a pre-existing path squeezed by placement, not in the LFO logic; Gowin placement is deterministic so re-running reproduces it. **timing_closed = false — deployment is prohibited by the gate.**
- Handover to Codex: suggest anchoring those two FFs via INS_LOC exactly as commit `a276b9b` did for the serializer resets (site syntax `R##C##[0][A]` from a routed report), or shrinking/relocating `u_lfo_sysex`. Builds: `impl/R16A_build_20261025_200224`, `_201138`, `_202146`/`_203946` (last two identical results). No bitstream programmed.
