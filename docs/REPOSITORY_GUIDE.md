# Repository and build guide

## Source layout

- `src/`: audio-engine RTL and vendor wrappers. `src/top.v.v` is the audio-board top.
- `constraints/`: board top-level pin assignments and timing constraints. `synth1_9_18.gprj` enables the full-synthesis profile by default.
- `ip/`: vendor IP configuration/notes. Generated vendor netlists stay in local Gowin output folders unless the vendor project explicitly requires source-controlled files.
- `sim/`: testbenches, simulation stubs, and ModelSim `.do` files. `work_*`, transcripts, waves, and reports are local outputs.
- `tools/`: host-side MIDI and wavetable utilities.
- `docs/`: audio architecture/protocol references and cross-team integration documents.
- `2_ui_touch_hub/`: UI board's independent Gowin project, source, constraints, testbenches and tools. Do not merge its files over the audio root.

## Branch roles

- `main`: audio-engine source of truth.
- `ui-touch-hub-v1.0`: shared collaboration branch, based on audio `main` and containing the UI as `2_ui_touch_hub/`.
- The separate UI development checkout at `D:\github\gaoyun\2_ui_touch_hub` has its own Git history. Mirror only reviewed integration files into the shared subdirectory; retain its local experiments and generated evidence in their original checkout.

## Build and verification boundaries

- Use documented ModelSim `.do` tests for behavioral RTL changes.
- The audio repository rules prohibit Gowin synthesis/P&R solely for automated verification. Run the board-specific implementation flow only as a user-requested hardware release step and preserve the timing report and bitstream hash.
- UI and audio bitstreams are built and programmed separately on their respective 138K boards.
- Never treat a UI display update or UART waveform as proof that audio state changed; require an audio-side assertion, audible check, or future state telemetry.

## Cleanup policy

Implementation output and simulator work libraries are ignored locally. Preserve test evidence and user-local files unless a reviewed task explicitly requires removing them. Prefer adding precise ignore rules to deleting uncertain files.
