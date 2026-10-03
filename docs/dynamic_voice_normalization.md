# Dynamic oscillator-task normalization

The old fixed `/32` attenuation is replaced by a `1/N` gain, where `N` is the
number of active physical oscillator tasks. This means every Unison member is
included in the divisor, just like any other generic oscillator task.

## Active-task definition

`oscillator_task_scheduler` derives `active_task_count` from its task table:

- a task is counted immediately after Note On allocation;
- a task remains counted during ADSR Release;
- it is removed only after the engine reports envelope idle;
- retriggering or reassigning an active context does not momentarily remove it.

Keeping releasing tasks in the divisor avoids an abrupt gain jump at Note Off.

## Gain calculation

The bank uses a 17-bit Q1.16 reciprocal lookup table:

```text
0 or 1 task: 65536 (1.0)
2 tasks:     32768 (1/2)
3 tasks:     21845 (approximately 1/3)
...
32 tasks:     2048 (1/32)
```

No runtime divider is present in the audio datapath. The engine sum is
multiplied by the Q1.16 gain, rounded, and saturated to signed 16-bit PCM.

When the active task count rises, attenuation is applied on the first complete
internal sample. This protects against a transient overload when newly started,
phase-coherent Unison members add together. When the active count falls, gain
recovery is smoothed with `GAIN_SMOOTH_SHIFT` (default 12) to avoid a sudden
increase in the remaining sound. With zero active tasks, unity gain is restored
while the output is silent.
