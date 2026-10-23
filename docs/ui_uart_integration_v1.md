# UI Touch Hub ↔ Audio Engine UART Integration v1

Status: Phase 1 implementation candidate. The pin and mapping table is the shared source of truth for the current UI adapter. Physical wiring and on-board acceptance are not yet claimed complete.

## Board link

- Format: 31250 baud, 8N1, 3.3 V LVCMOS, full MIDI status byte per message.
- UI board USB-UART monitor remains on U15. Cross-board TX is `audio_link_tx`, PMOD1 IO2 / AB21 / J8 pin 9.
- Audio board V14 remains the on-board FT2232 USB-UART RX. Dedicated input `midi_gpio_rx` is PMOD1 IO2 / AB21 / J8 pin 9. The audio RTL combines the two idle-high RX pins with AND, so either source can be used without electrically joining two TX outputs. Only one source may transmit at a time; simultaneous traffic is unsupported.
- Phase 1 wire: UI J8 pin 9 → audio J8 pin 9; J8 pin 3 or 4 → common GND. Do not connect the PMOD 3.3 V power pin. Do not share board clocks or resets.
- PMOD1 IO2 is also routed to DVP/SDRAM1 expansion nets on the dock schematic. Remove/avoid those expansion devices during UART testing. Both board constraints specify 3.3 V LVCMOS.
- Candidate return path for a future UI telemetry receiver: PMOD1 IO4 / AA20 / J8 pin 7, subject to hardware confirmation and the board not using that DVP/SDRAM1 signal.

## MIDI channels and rate

- Channel 1: MIDI Note On/Off. Audio accepts note numbers 21..108. UI currently ties Note requests low, so Phase 1 covers parameter control only.
- Channel 16: Control Change, status byte `0xBF`, payload `0xBF, cc, value`.
- A complete three-byte CC takes about 0.96 ms at 31250 baud. UI TX has an eight-message FIFO; under saturation a new CC may be dropped. The UI has no audio-state acknowledgment yet.

## Phase 1 parameter table

| UI control | CC | Conversion and audio behavior |
|---|---:|---|
| OSC A WT Position | 20 | 0..127 |
| OSC A Waveform | 21 | UI enum Sine/Saw/Square/Triangle (0/1/2/3) converts to audio codes 0/96/64/32 |
| OSC A Detune / Unison | 22 / 23 | Detune 0..127; Unison clamps to 1..8 |
| OSC A Enable / Warp Amount / Level | 36 / 39 / 46 | Enable 0=off, nonzero=on; amount and level 0..127 |
| OSC B WT Position | 28 | 0..127 |
| OSC B Waveform | 29 | Same conversion as OSC A |
| OSC B Detune / Unison | 30 / 31 | Detune 0..127; Unison clamps to 1..8 |
| OSC B Enable / Warp Amount / Level | 37 / 41 / 47 | Enable 0=off, nonzero=on; amount and level 0..127 |
| Filter Mode | 42 | 0=bypass, 1=LP, 2=HP, 3=BP, 4=notch. Audio also has Comb+/Comb- at 5/6, not exposed in the current UI. |
| Filter Cutoff / Resonance / Mix | 43 / 44 / 45 | 0..127; actual Hz/response mapping is in the audio engine. |
| OSC A ADSR | 24 / 25 / 26 / 27 | Attack / Decay / Sustain / Release, 0..127. Current first UI ENV tab only. |
| Master Level | 48 | 0..127 |

The UI transmitter suppresses controls that are not represented by this table, including Pan (the current audio output is mono), Hold, EQ, macros, and legacy one-number FX controls. UI FX IDs and seven-point LFO snapshots are not MIDI CC numbers. Audio LFO setup uses its existing SysEx protocol in a later phase.

## Phase gates

1. UI TX bench proves 8N1 and this CC map. Audio top testbench proves both V14 and PMOD RX paths.
2. User connects the GPIO cable and confirms the PMODs are not occupied by DVP/SDRAM1 hardware.
3. On hardware, use one source at a time. First test OSC A WT and Filter Cutoff/Mode; then expand through the table and listen for the corresponding audio change.
4. Do not label a displayed UI value as “applied” until audio telemetry/acknowledgment exists. Add versioned STATE/READY/METER return frames before live visualizations.

## Explicit limits

- No Note events originate from the current UI top.
- Audio ADSR has A/B groups, while UI currently emits only its first ENV page to A. UI Hold and other ENV pages remain local.
- The UI Filter response and oscillator windows are model previews, not sampled audio output.
- Audio remains mono; Pan and Stereo Phase are not audibly/visually live.
- Seven-point UI LFO cannot be sent losslessly into the audio engine's three-point/two-curvature LFO. Use the audio SysEx after a deliberate UI model change or implement a separately specified approximation.
