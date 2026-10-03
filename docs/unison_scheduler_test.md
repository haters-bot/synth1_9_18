# Three-oscillator Unison scheduler test

The MIDI allocator treats the 32 TDM oscillator slots as ten groups of three
adjacent slots. Each Note On and Note Off is serialized into three slot updates
on consecutive 50 MHz clocks:

```text
logical group 0 -> slots 0, 1, 2
logical group 1 -> slots 3, 4, 5
...
logical group 9 -> slots 27, 28, 29
```

Slots 30 and 31 are intentionally unused by MIDI allocation. The low-level
scheduler test still enables all 32 slots to verify its worst-case timing.

## Detune

The three lanes use approximately `-4.011`, `0`, and `+4.011` cents. The
detune delta is calculated from the normal MIDI phase step with shifts and
adds:

```text
delta = (base_step >> 9) + (base_step >> 12) + (base_step >> 13)
```

This avoids adding a general multiplier to the oscillator timing path.

## Envelope and level behavior

All three lanes receive matching ADSR commands on consecutive system clocks.
They keep independent phase and envelope state. The active count includes all
three physical lanes, so the existing `/N` normalization limits a three-lane
group to the same worst-case aligned peak as one full-scale oscillator.
When the oscillator count rises, attenuation is applied immediately because
all newly reset Unison phases are initially coherent. Gain recovery after
released lanes become idle remains smoothed.

## Verification targets

- The UART MIDI test expects three slot updates per note event.
- A held three-lane note remains active while other groups enter Release.
- The scheduler remains loaded with all 32 physical slots at the real 768 kHz
  request interval.
- Equal-note Unison phases advance in low / center / high order.
- No scheduler overrun occurs at the normal request interval.
