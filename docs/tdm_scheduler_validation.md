# Generic oscillator task scheduling

## Architecture

The top level has four identical physical oscillator engines. Each engine
time-division-multiplexes eight logical contexts, for a shared pool of 32
ordinary oscillator tasks.

Unison is not implemented by a special oscillator type. The global
`oscillator_task_scheduler` receives a MIDI note and a requested member count,
calculates the detuned phase steps, and allocates that many ordinary tasks.
The scheduler distributes consecutive members across physical engines before
placing a second member on an engine. With four engines, allocation order is:

```text
global slots: 0, 8, 16, 24, 1, 9, 17, 25, ...
engine:       0, 1,  2,  3, 0, 1,  2,  3, ...
```

The scheduler owns MIDI-note/group metadata. An oscillator engine receives
only a phase step, enable/gate command, and optional phase reset; it has no
MIDI-note or Unison-specific logic.

## Interfaces and state

The scheduler-to-bank update interface changes at most one task per clock:

```verilog
task_update_valid
task_update_slot[7:0]
task_update_phase_step[31:0]
task_update_enable
task_update_phase_reset
```

The bank converts a global slot number into an engine number and local slot.
Each core stores independent `phase_step_state`, `phase_state`, enable/gate,
and ADSR state for each of its eight contexts. The datapath and wavetable are
shared within that engine.

Each engine starts from the same 768 kHz `start_tick`, evaluates its eight
contexts, and emits a partial sum. The bank adds all four partial sums and
normalizes by the total number of active physical tasks.

## Note and group behavior

- Note On creates 1 to 8 generic tasks according to `unison_count`.
- Three-member Unison uses approximately -4, 0, and +4 cents.
- Re-triggering the same note replaces/reuses its group and supports changing
  the requested member count.
- Note Off sends every task owned by that note into its independent Release
  stage.
- A task remains active for normalization until its ADSR reports idle.
- When all 32 contexts are occupied, a complete existing note group is chosen
  as the victim. Needed contexts are reused and any surplus victim contexts
  enter Release.

MIDI control events are much slower than the scheduler scan. The current
interface intentionally has no event FIFO; the parser must not present another
event while `scheduler_busy` is asserted if the MIDI source is replaced by a
faster control source.

## Verification

Run the focused tests from ModelSim:

```tcl
do sim/run_task_scheduler_test.do
do sim/run_tdm_test.do
do sim/run_top_fixed_note_test.do
```

The tests cover variable Unison counts, balanced 32-task full load, full-pool
group replacement, phase-step/context updates, 768 kHz scheduling without
overrun, and the current fixed-A4 debug-mode top level.

The RTL was also elaborated and simulated with Icarus Verilog. Gowin synthesis
and place-and-route are intentionally not part of automated verification.
