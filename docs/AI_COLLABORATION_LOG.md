# AI Collaboration Change Log

Purpose: durable handoff record for AI-assisted changes made on the shared UI/audio integration branch. Each entry records touched files, verification, limits, and the associated commit once pushed.

## 2026-10-29 — Local performance acceptance and handoff corrected

- Updated the UI performance acceptance criteria to match the schematic-verified LED route: FPGA J16 → onboard U15 → J24 pin 3, with C14 reserved for debug UART; corrected the pin audit threshold to 122.
- Updated the latest status and handoff entries with normal/debug timing and pin-audit results, the normal SRAM check-only hash, and the 23:12 LED/key regression reruns.
- No hardware was programmed; no files were deleted; no changes were pushed; the audio-board project was not modified. Physical LED wiring, keyboard MIDI range and full-length DDR recording remain for board validation.

## 2026-10-29 23:42 — Local performance regression resumed

- Re-ran the 25-pixel WS2812 chain, 32-key MIDI/white-key mapping, cue/display/command, MIDI parser, note arbitration, PCM capture, long-score progress, protocol, scheduler, and PCM-to-DDR exact-readback regressions; all passed.
- Re-ran UI SRAM `--check-only`: 99 inputs matched, all five timing classes passed, 122/122 pins matched, and the bitstream SHA256 remained `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`.
- A duplicate full-page renderer run was stopped for excessive runtime; its partial output and logs were retained, and its simulator process exited. The earlier completed preview remains the full-page PASS evidence.
- No hardware programming, remote engineering-host access, deletion, push, or audio-board modification occurred. Physical JTAG target and LED wiring are still unconfirmed.

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
## 2026-10-26 11:05 — UI 侧 TXE8148 采样点修复与四区参数映射（Codex）

- **改动**：`2_ui_touch_hub/rtl/knob_spi_intake/knob_spi_rx.v` 将 SDO 捕获从低相位开始前移采样改为高相位结束采样，匹配 TXE8148 在下降沿更新 SDO 的 SPI 时序；旋钮 0..31 改为左上 OSC A、左下 ENV/Global、右上 OSC B、右下 Filter/FX 四个 8 路区域映射。
- **输入语义**：旋转事件仍走 `spi_param_valid/id/val` → `param_merger`，触摸路径未改。EC11 按压只在接收器内部形成 `select_valid/select_id` 单拍事件；尝试把它直接并入 `btn_tap` 或渲染选择路径会改变高扇出布局并产生 setup 违例，因此持久视觉选中态留待低扇出实现。当前不能宣称实体按压 UI 反馈已完成。
- **验证**：Gowin P&R Setup/Hold 违例均为 0，最差 Setup Slack `+0.595 ns`；`tb_lfo_sysex_tx` 与 `tb_midi_uart_tx` 均通过；位流 SHA256 `8C2617DB216CA7F930818B1032EE1ED520D2B214AB53613A025525518281FB71`。
- **部署边界**：截至本条目，尚未烧录这版新位流；仅 SRAM 目标，Flash 暂停。下一步是提交/推送后执行 `deploy_verified.py --target sram`，然后以工程机编程返回码、远端哈希、摄像头抓屏和现场旋钮逐项测试作为证据。
## 2026-10-26 11:27 — 四区映射位流已部署到 UI 板 SRAM（Codex）

- **来源**：提交 `3b8807b`，位流 SHA256 `8C2617DB216CA7F930818B1032EE1ED520D2B214AB53613A025525518281FB71`。
- **部署**：工程机 `10.136.125.157` 执行 `tools/deploy_verified.py --target sram`，目录 `2_ui_touch_hub/impl/deploy_runs/20261026_112652_TXE8148_EC11_SPI_QUADRANT_MAPPING/`；GW5AST-138B、SRAM operation 2、`PROGRAMMER_EXIT=0`、Status `0x00026230`、User Code `0x00004262`、22.73 s，远端哈希匹配。
- **实屏证据**：`preview.jpg` 显示正常六窗 UI。仍待现场旋钮逐个转动确认参数变化、方向正负和 EC11 按压行为；Flash 保持暂停。
## 2026-10-26 12:18 — 实体按压选中态接入试跑失败并撤回（Codex）

- **尝试**：将 `knob_select_valid/select_id` 接到 `touch_event_router.selected_param_id`，使 EC11 按压更新屏幕当前选中参数。
- **结果**：Gowin P&R 出现 2 条 setup 违例，最差 `−0.339 ns`；其中一条是导航 `ch1_4_s0 → coverage2_0_s0`，另一条是 `id0_2_s0 → ch1_0_s0`。该试验没有提交、没有部署，已撤回，工作区恢复干净。
- **当前状态**：提交 `3b8807b` 的 SPI 采样修复、四区映射和旋转事件路径仍在板上；按压事件仍只在接收器内部形成 `select_valid/select_id`，持久视觉选中态待低扇出旋钮局部路径实现。
## 2026-10-26 20:47 — PCB 原理图审计发现并修正 TXE8148 GPIO bank 映射（Codex）

- **证据**：用户提供的 `32旋钮PCB.zip` 中 `SCH_Schematic2_2026-10-26.pdf` 明确分出 `P1A..P32A`、`P1B..P32B`、`P1SW..P32SW` 三组总线；TXE8148 符号包含 P0.0..P5.7 六个 8 位端口。由此确认每颗芯片的 16 个旋钮按端口 bank 接线：P0/P1=A、P2/P3=B、P4/P5=SW。
- **修正**：`knob_spi_rx.v` 改为 `A=GPIO[k]`、`B=GPIO[16+k]`、`SW=GPIO[32+k]`，不再按三个连续 GPIO 交错读取。四区 UI 参数映射保持原定义。
- **供电修正**：同一原理图把 Type-C VCC 网络标为 `3.3V-IN`，因此文档中的 5 V 入口说明已改为 3.3 V，禁止把 5 V 直接接入键盘板 VCC。用户已确认已改接 3.3 V。
- **验证**：Gowin P&R Setup/Hold 违例 0，最差恢复余量 `+0.201 ns`；位流 SHA256 `37FB1A5409AF62F51B32BBC04146C125D09F7FB55320527128E22FC76D25E541`。新位流尚未部署。
## 2026-10-26 20:55 — PCB bank 映射修正版已部署到 UI 板 SRAM（Codex）

- **来源**：提交 `0699cac`，位流 SHA256 `37FB1A5409AF62F51B32BBC04146C125D09F7FB55320527128E22FC76D25E541`。
- **部署**：工程机 `10.136.125.157` 执行 `tools/deploy_verified.py --target sram`，目录 `2_ui_touch_hub/impl/deploy_runs/20261026_205443_TXE8148_PCB_BANK_MAPPING_3V3/`；GW5AST-138B、SRAM operation 2、`PROGRAMMER_EXIT=0`、Status `0x00026230`、User Code `0x00008733`、23.14 s，远端哈希匹配。
- **实屏证据**：`preview.jpg` 显示正常 UI。现场旋钮旋转、方向和按压仍待用户逐项确认；Flash 保持暂停。
# 2026-10-26 22:25 — UI 板外接调试 UART C14/E13（Codex）

- 按用户指定新增 `debug_uart_tx=C14`、`debug_uart_rx=E13`，LVCMOS33；TX 镜像 `midi_uart_tx` 监视流。诊断 build 下 U15/C14 是 115200 trace；normal build 仍是 31250 MIDI 镜像。E13 当前只分配为上拉输入，无命令协议。
- 新增 `doc/UI_PCB_DEBUG_UART_PINOUT.md`；接线为 C14→USB-TTL RX、E13←USB-TTL TX、共地，仅 3.3 V TTL。
- 调试工程原先缺少 `ui_navigation_state.v`、`ui_navigation_renderer.v`、`navigation_font.vh`、`lfo_sysex_tx.v`，且误使用普通 CST 内部实例锚点。本轮补齐源文件并新增无旧内部锚点的 `ui_touch_hub_debug.cst`；`build_isolated.py --debug`、`audit_build.py` 已支持诊断工程构建/审计。
- 诊断 build `DEBUG_R16A_build_20261026_221313` 通过完整时序审计：Setup/Hold 0、最差 Setup `+0.074 ns`，其余 recovery/removal/pulse 检查通过，源码快照一致。SHA256 `D5A8492AC467CDD4C2C0183FCBB37FE593DAE93E84756B640D70B525981F5080`。
- SRAM 烧录成功：`2_ui_touch_hub/impl/deploy_runs/20261026_222436_UI_PCB_DEBUG_UART_C14_E13/`，`PROGRAMMER_EXIT=0`、Status `0x00026230`、User Code `0x0000233D`。不代表串口已在电脑端解码验收。

## 2026-10-27 01:05 — 实体旋钮动作串口诊断版已烧录 SRAM（Codex）

- C14 调试 UART 在实体旋钮有动作时输出 `KNOBnn CW/CCW/PRESS/RELEASE`，空闲不输出旋钮事件；`python tools/test_touch_trace.py` 全过。追踪解码器已避免复用旧按键动作造成误报。
- 隔离构建 `DEBUG_R16A_build_20261027_005555` 五类时序余量均为正，clk_pixel Fmax 52.855 MHz，源码快照匹配。SHA256 `DA3A01208EB321513418C8495C7BD0E15C3E4CA6C9DBFDA17E09611F4D2FEEDF`。
- 工程机 SRAM 烧录成功：`2_ui_touch_hub/impl/deploy_runs/20261027_010415_KNOB_ACTIVE_EVENTS/`，User Code `0x0000881D`，Status `0x00026230`，`PROGRAMMER_EXIT=0`，远端哈希匹配；抓屏显示六窗 UI 正常。Flash 未操作。实体旋钮逐个方向和按压仍待现场验收。
- **项目协作偏好（用户要求）**：处理时序/P&R 时先快速核对一次整体门禁和关键路径，采用有数据支撑的最小修复，减少连续无目标试跑；时序安全条件仍须全部达标，不得把负余量或低于约束频率放行为通过。


## 2026-10-29 — UI LFO V2 SysEx MIDI-safe packing fix

- Root cause: the UI route payload placed `source` in bits `[15:14]` and emitted the value as ordinary 16-bit big-endian bytes. The audio board expects `source` in `[9:8]` and reconstructs a 14-bit MIDI-safe value from two 7-bit data bytes. This made a typical OSC A Level / LFO1 / +127 binding decode as `source=0`, while negative depths could emit status-valued bytes `0x80..0xFF` and abort SysEx parsing.
- Fix: route values are now `{6'd0, source[1:0], depth[7:0]}` and every frame emits `{1'b0,value[13:7]}` followed by `{1'b0,value[6:0]}`. The protocol document now specifies the 14-bit representation explicitly.
- Verification: ModelSim compiled the UI MIDI/LFO transmitter with zero errors and warnings. Existing Note/CC regression passed; the LFO regression passed initial 81-frame synchronization, negative depth, CC preemption, and the exact OSC A Level target 13 / ID 86 / LFO1 / +127 case as decoded value `0x017F`. Gowin synthesis, place-and-route, bitstream programming, and physical board acceptance were not run for this change.
