# Phone performance / audio input contract (V1)

Status: UI-side contract prepared from the teammate audio repository's remote
`main` at `d4338fb1509f724e686d84f7bbac45692632ea3b`. This document does not
modify the audio repository.

## Confirmed audio-side inputs

The current audio `main` reserves these inputs:

| Input | Pin | Current role |
|---|---|---|
| `uart_rx` | V14 | Onboard USB-UART; Note and control messages |
| `keyboard_uart_rx` | E19 | Physical MIDI keyboard converter; Note only |
| `control_uart_rx` | C19 | Control CC/SysEx; Note messages are discarded |

E19 is occupied by the physical piano-keyboard converter. The UI board must
not be wired to E19 in parallel with that converter. The latest audio `main`
does not expose the older `midi_gpio_rx`/AB21 cross-board input.

## UI-board gateway pins

The UI board keeps its existing pinout for this first implementation:

- `debug_uart_rx` on **E13** is the gateway RX at 115200 8N1. The gateway
  sends the framed song/control packets defined in
  `tools/performance_protocol.py`.
- Pending the user's physical pin allocation, `PERFORMANCE_LED_ENABLE=1`
  dedicates `debug_uart_tx` on **C14** to the external 24-pixel strip, including
  the final dark frame after leaving the performance page. U15 retains its
  original output. Set this parameter to 0 only when the strip is disconnected
  and C14 is deliberately used for UART diagnostics. A 3.3 V-to-5 V level
  shifter is required for a 5 V strip; the FPGA pin is not a power rail.

Do not switch a strip-connected C14 back to UART by changing pages: UART bytes
can be interpreted as LED data, and the transition can truncate the dark frame.
The default strip driver transmits GRB order, 0.4/0.8 us high times at 50 MHz,
and at least 300 us low at startup and after each frame. This is a provisional
WS2812 configuration, pending the exact strip model and electrical validation.

## Confirmed MIDI semantics

- 3.3 V TTL UART, 31250 baud, 8N1 by default.
- The E19 Note parser accepts Note On/Off on all 16 MIDI channels, preserving
  the received channel, note number and velocity. The UI/gateway uses channel 1
  as its output convention; channel 1 is not an E19 parser restriction.
- MIDI channel 16: synthesizer Control Change parameters.
- Note On with velocity 0 is treated as Note Off.
- The audio frequency table accepts MIDI notes 21..108; out-of-range notes
  are ignored.
- The audio side independently parses V14 and E19, then merges note events
  through an eight-entry event FIFO. FIFO overflow is latched.

## Required audio-side decision before hardware integration

The audio teammate must expose a dedicated third Note input for the UI board,
for example `ui_midi_rx`, while preserving E19 for the physical keyboard and
C19 for control messages. The new input should use the confirmed channel-1
Note event semantics and an independent parser/FIFO.

The UI side will not reuse E19, tie two TX outputs together, or change the
audio RTL in this task.

The current candidate UI image reserves **16384 timestamped events** through
`ui_touch_hub_top.PERFORMANCE_MAX_EVENTS`, shared with the decoder and renderer.
A Note On and its Note Off occupy two events. This is an event-count boundary,
not a guaranteed number of minutes. The browser/gateway contract uses the same
limit and 32 logical keys; wireless transport remains deferred.

The BSRAM scheduler reports a sticky load error if a record cannot be accepted;
an overflowed image cannot start, and clear/reload is required. The UI displays
the error rather than silently playing the accepted prefix. Simulation covers
capacities 5/8/1024/4096/16384, including exact-full acceptance, overflow refusal
and recovery by clearing. The earlier 1024-record limit and three-block probe
are historical; final resource/timing acceptance of the 16384-record candidate
is still pending its complete Gowin build.

## UI-side event representation

The phone/gateway parser converts Standard MIDI File events into records:

```text
time_us   : absolute event time from song start
note      : MIDI note number 21..108 after transpose/range validation
velocity  : 0..127
on        : Note On or Note Off
channel   : source MIDI channel, normalized to performance channel 1
track     : source track for diagnostics
```

The UI scheduler uses the same event pulse for the virtual piano and WS2812
guidance. Score-to-audio transmission is disabled by default through
`PERFORMANCE_SCORE_AUDIO_ENABLE=0`: the user plays the physical keyboard into
E19 while following the guidance. The future automatic-audio option requires
a dedicated audio-side Note input and stop/pause Note cleanup before use.
Remote/touch Note output remains a reserved interface, pending that input.
The UI does not infer notes from audio PCM.

## 32 physical keys and white-key LEDs (2026-10-29)

The audio repository was fetched again from
`https://github.com/haters-bot/synth1_9_18` on 2026-10-29. `origin/main`
is still `d4338fb1509f724e686d84f7bbac45692632ea3b`.
`src/midi_note_parser.v` exports the received 7-bit MIDI note unchanged;
`src/top.v.v` forwards E19 events to the merger without a keyboard-index
translation. Neither that path nor the E19 documentation specifies the
physical 32-key keyboard's lowest note. MIDI 21..108 is the synthesizer's
accepted range, not evidence of the keyboard's physical range.

Reconfirmed by an actual `git fetch origin main` at 14:56 on 2026-10-29;
the remote commit remains unchanged. Read-only evidence snapshots and SHA256
are preserved in `impl/audio_note_contract_20261029_145705/`.
Direct source references at that exact commit:

- [E19 parser: received note ID is preserved](https://github.com/haters-bot/synth1_9_18/blob/d4338fb1509f724e686d84f7bbac45692632ea3b/src/midi_note_parser.v)
- [Top: separate keyboard parser and merged Note events](https://github.com/haters-bot/synth1_9_18/blob/d4338fb1509f724e686d84f7bbac45692632ea3b/src/top.v.v)
- [Scheduler: default accepted range 21..108](https://github.com/haters-bot/synth1_9_18/blob/d4338fb1509f724e686d84f7bbac45692632ea3b/src/oscillator_task_scheduler.v)

No keyboard schematic is required for this contract. Physical alignment is
accepted by observing the MIDI ID from the existing converter while pressing
each key, leaving the existing converter-to-E19 connection in place. Any
measurement input must be electrically suitable; never parallel two TX drivers.
This is still a future physical check: no serial measurement was performed in
this repository review. I2S recording alone cannot establish the key-index map.

- There are **32 chromatic logical keys**, independent of the **24 LEDs**.
- `ui_touch_hub_top.PERFORMANCE_BASE_NOTE` is passed to all UI key and LED
  mappings. The default 60 is provisional; it is not a measured hardware fact.
- Local key `k` uses MIDI `PERFORMANCE_BASE_NOTE + k`, without folding,
  modulo-24 aliasing, implicit transpose, or changing the score's MIDI note.
- White notes (C/D/E/F/G/A/B) map left-to-right to consecutive LEDs; black
  notes have screen guidance only. Remaining LEDs stay off. For the provisional
  60..91 range, there are 19 white keys and LEDs 19..23 are unused.
- Before installing the strip, capture the leftmost key's actual Note On,
  then check all 32 keys, including any octave/transpose setting. Verify
  contiguous semitones before accepting a single-base mapping; a non-contiguous
  keyboard requires an explicit table. C4 naming conventions vary, so use the
  numeric MIDI ID as the acceptance reference.
- The UI currently has no physical-keyboard event return link. I2S PCM does
  not provide a reliable substitute for polyphonic Note On/Off feedback.
  Scoring actual key presses needs a separately agreed event return path.

## Local PCM recording frontend and storage boundary

The user-confirmed source is the audio board's I2S output connected to UI
R19/BCLK, U21/LRC and R17/DIN. Use `i2s_visual_rx.sample`, `sample_right`
and `stereo_valid`. In VIS V2, record the upper-16-bit final-output PCM;
the lower extension words contain OSC A/B visualization samples, not the
recorded final mix. Do not change the audio I2S format or use a microphone.

`rtl/performance/performance_pcm_capture.v` provides start/stop/clear,
captured/written frame counters, source-loss/full/overflow/command-error
status, and a ready/valid indexed 32-bit stereo write stream. FIFO data
remains stable under backpressure. Stop drains queued frames; `done` marks
the drained end. The first unbufferable sample terminates recording with
an explicit overflow flag. Clear/restart while busy cannot discard data.

This frontend is verified independently and with the production I2S transmitter
and UI receiver. `performance_recording_subsystem.v` now connects it to
`performance_pcm_store.v`. The store packs up to eight stereo frames per masked
256-bit DDR transaction and crosses between source and memory clocks with Gray
pointer FIFOs. It counts backend write responses, validates frame continuity and
the reserved memory region, and publishes read access only after a matching end
count. Source loss, overflow, memory errors, timeouts or calibration loss make
the recording unreadable. Timeouts quarantine the memory interface until reset;
there is no automatic retry. `done` means the external DDR adapter confirmed all
writes to volatile DDR. It is not a nonvolatile save or phone transfer.

ModelSim passed 137 distinct VIS V2 I2S sample pairs through the production
receiver, recording subsystem and the exact teammate adapter from commit
`d4338fb`, followed by exact per-frame readback. The backend model varied
command/data handshake order and delay. Two unrelated clock ratios also passed
2053-frame partial-tail, FIFO-stall, error, timeout, reset and readback checks.
This verifies RTL transactions only, not PHY training or a board-level memory.
The normal/diagnostic UI tops now instantiate DDR pins, IP/PLL wrapper and the
memory user clock and connect the recording requests. Complete routed timing,
physical PHY training and whole-song memory acceptance remain unproven.

At 96 kHz, signed 16-bit stereo consumes 384,000 bytes/s: 115,200,000 bytes
for five minutes, before metadata/alignment. A 16-frame FIFO holds only
166.7 microseconds. It cannot satisfy the whole-song requirement.
The backend must provide actual capacity and sustain writes, followed by an
indexed read interface for future phone export. Bluetooth transfer stays reserved.

The teammate's `docs/ddr_storage_path.md` describes a 100 MHz DDR user port,
400 MHz PHY, asynchronous FIFO and 256-bit requests (address increments of 8
per 32-byte transaction). Its DDR IP template is for the same FPGA device,
but was generated with Gowin **1.9.12.03**; the local UI uses **1.9.11.03**.
The UI CST has no source-level pin-location overlaps with the teammate's 66 DDR
locations. Sipeed's official Tang Mega 138K hardware-parameters page states
1GB DDR3 (512MB x 2), matching the current 1GiB reservation in address units
of 32-bit words. At 96kHz/16-bit stereo this is a configured theoretical limit
of about 46 minutes 36 seconds; it is not a measured recording duration.
The specific board revision, DRAM configuration, bank voltage/timing, calibration
and non-aliasing capacity still require physical verification. See
`doc/LOCAL_PERFORMANCE_ACCEPTANCE_2026-10-29.md` for the official URL, saved
evidence and acceptance procedure. This machine has Gowin 1.9.11.03, while that IP
template identifies 1.9.12.03. The supplied IP has now compiled in the local
tool, but the early 135029/140630 images failed timing and used only the last
of two CST fragments, incorrectly auto-assigning UI pins. Both are rejected.
The project now loads one combined CST and the final routed pin report must
match all preserved assignments. An audio-board DDR simulation/BIST statement
does not verify the UI board.

## Current validation boundary

RTL simulation verifies the 32-key MIDI mapping, white-only LED bitmaps,
touch drag/release behavior, stop/clear guidance state, and PCM write-stream
behavior. It does not establish whole-song storage, Bluetooth functionality,
actual-key feedback, UI-generated sound on the teammate image, LED electrical
behavior, or final UI timing closure. The latest completed full build `152727`
failed 488 setup endpoints (worst -2.203 ns, pixel Fmax 46.81 MHz vs 50 MHz,
DDR user 81.944 MHz vs 100 MHz). It must not be deployed. Candidate `155807`
is undergoing complete synthesis/place/route after targeted register/background
changes. No programming has been performed for this performance feature.

## Known timing boundary

The existing 31250-baud three-byte MIDI stream takes about 0.96 ms per event.
That is adequate for sparse melodies but cannot by itself prove deterministic
sub-5-ms delivery for dense chords. A future score mode may therefore need an
audio-side timestamped event FIFO or a faster dedicated transport.

## 2026-10-29 15:30 local interaction update

The recorder command request is reconciled with actual start-accepted/rejected,
recording-active and done feedback. Automatic full/source-loss termination
releases the request latch. A previous take's sticky source error is gated until
the new capture epoch starts, preventing a recovered input from immediately
poisoning the next take. UI status distinguishes unavailable, recording,
flushing, saved, capacity limit, source failure, storage failure and rejected
commands. Saved means acknowledged volatile DDR contents; calibration loss
invalidates that indication. No phone microphone path is used.

Independent scheduled/remote/touch key masks avoid erasing another source's held
key. Three independent 16-entry Note queues replace the priority-only output
mux; round-robin delivery preserves each source's event order. UART `note_ready`
prevents dequeuing into its full eight-message FIFO. Queue overload is sticky
and visible as MIDI QUEUE OVERFLOW. This is bounded buffering, not proof that
arbitrarily dense bursts can meet the 31250-baud line rate. Stop/pause cleanup of
already transmitted audio Notes and high-density burst policy still require
further acceptance before declaring the future UI-to-audio Note path complete.
The audio image still needs its separately agreed Note input; this change does
not connect UI TX to E19 or enable Notes through C19.

The performance page now includes a score-clock one-second falling cue for the
next prefetched Note On. Pause freezes its position and Note Off records are
not shown as new presses. The on-time active masks still drive the 32 screen
keys and white-key LED mapping. This is one prefetched-event advance cue, not a
complete multi-note scrolling piano roll or real-key scoring system.

The 15:27 preview `performance_preview_20261029_152737_017392` completed:
921600 pixels and seven decoded LED frames passed, all input hashes matched,
and the image was inspected. The corresponding build `152727` failed timing.
The subsequent candidate `R16A_build_20261029_155807` preserves the DDR
command-register boundary, registers the Note arbiter output, parallelizes
background selection without adding pixel latency, and disables score audio
by default. Its store, serialized Notes, guidance-only cue, navigation,
recorder text and normal/diagnostic compile regressions passed. A 259330-case
legacy/candidate background comparison also passed. See
`impl/performance_timing_fix_20261029_155312/final_regressions.json`.
Candidate `155807` still requires final pin and all five timing checks;
physical memory/keyboard/strip acceptance remains outstanding.
