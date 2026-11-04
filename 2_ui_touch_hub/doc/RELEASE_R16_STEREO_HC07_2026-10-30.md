# R16 UI / stereo / HC-07 checkpoint — 2026-10-30

This checkpoint contains the UI performance page, 32 logical keys and white-key
LED mapping, DDR recording of the audio board's final I²S output, stereo display,
PAN controls, the MIDI-safe LFO protocol fix, and the Android HC-07 SPP client.
The audio board source is not changed by this checkpoint.

## Connections and behavior

- F14 TX → HC-07 RXD; HC-07 TXD → F16 RX; common GND.
- F13 → external 24-pixel strip DIN. Wire with power off. Confirm module supply
  rating separately from the 3.3 V UART signal level.
- K27 / MASTER PAN sends CC10; OSC A/B PAN uses CC91/92.
- Playback provides LED/screen guidance; the user plays the physical keyboard.
- I²S recording retains raw 96 kHz / 16-bit stereo PCM in DDR. Phone export uses
  a 127-tap low-pass filter and 12× decimation to 8 kHz mono or stereo WAV.
- Firmware currently assumes MIDI note 60 at the leftmost key. The physical
  keyboard range still needs measurement; out-of-range MIDI is rejected.

## Verification and deployed image

The isolated build `R16A_build_20261030_201520` passed all five timing categories,
all seven clock requirements, all 123 pin locations and all 105 source hashes.
Gowin used the GW5AST-138B PBGA484A-1 device, one combined CST and one SDC,
gowinsynthesis, place3, route1, timing-driven routing and hold correction.

| Check | Result |
| --- | --- |
| Setup / hold violated endpoints | 0 / 0 |
| Worst setup / hold | +0.472 / +0.133 ns |
| Worst recovery / removal / pulse | +0.335 / +0.338 / +0.361 ns |
| Pixel clock | 51.722 MHz available / 50 MHz required |
| DDR user clock | 104.959 MHz available / 100 MHz required |
| Logic / registers / BSRAM | 70214 / 44534 / 89 |

The former five knob-to-FX setup violations are resolved with an input pipeline;
no frequency relaxation or extra domain-local timing exemption was added.
RTL regressions cover phone framing/session/retries, PCM storage/export,
PAN/LFO, stereo visualization, navigation, touch/knob controls and LED serialization.
The production JavaScript parser/client tests and gateway tests passed. The
Android APK compiled, aligned, signed and verified. Browser native-bridge tests
are simulations and do not establish real Bluetooth acceptance.

Bitstream SHA256:
`4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`

UI SRAM was programmed once using operation 2 at 20:43 Shanghai time. Programmer
exit was 0, User Code `0x00001521`, status `0x00026230`; local and remote hashes
matched. The user confirmed that the UI displays normally. Flash was not written.
Real HC-07 round-trip, physical LED mapping, PAN behavior and full-song DDR/WAV
acceptance remain pending.

Local evidence is retained outside Git:
`E:/gaoyun_builds/R16A_build_20261030_201520/` and
`impl/deploy_runs/20261030_204315_R16_stereo_hc07_F14_F16/`.
Implementation outputs, simulator libraries and local signing keys are not
versioned. Do not repeat programming merely because the camera missed the screen.

## Entry points

- [Connection and protocol acceptance](HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md)
- [EDA lessons](EDA_LESSONS_2026-10-30.md)
- Android source: `../phone_android/`; web assets: `../performance_web/`.
- Android build: `python tools/build_phone_apk.py` from the UI directory, with
  the local toolchain configuration created by `tools/prepare_android_toolchain.py`.
- MIDI samples: `../performance_web/examples/` (4-second C-major scale and
  32-second, 90 BPM Twinkle Twinkle single melody).
- Build: `python tools/build_isolated.py`; audit: `python tools/audit_build.py BUILD`.
- Deployment: `tools/deploy_verified.py --target sram --board ui --fs FS --label LABEL`;
  use `--check-only` before writing. Never automatically retry an SSH write timeout.
