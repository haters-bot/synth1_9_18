transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory sim/work_steal_priority]} {vlib sim/work_steal_priority}
vmap work_steal_priority sim/work_steal_priority
vlog -sv -work work_steal_priority src/freq_lut.v src/oscillator_task_scheduler.v sim/tb_steal_priority_equivalence.v
