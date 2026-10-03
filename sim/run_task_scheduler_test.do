transcript on

if {![file isdirectory sim/work_task_scheduler]} {
    vlib sim/work_task_scheduler
}
vmap work_task_scheduler sim/work_task_scheduler

vlog -work work_task_scheduler \
    src/freq_lut.v \
    src/oscillator_task_scheduler.v \
    sim/tb_oscillator_task_scheduler.v

vsim -voptargs=+acc -lib work_task_scheduler tb_oscillator_task_scheduler

add wave sim:/tb_oscillator_task_scheduler/dut/state
add wave sim:/tb_oscillator_task_scheduler/dut/pending_note
add wave sim:/tb_oscillator_task_scheduler/dut/pending_unison_count
add wave sim:/tb_oscillator_task_scheduler/dut/pending_member_index
add wave sim:/tb_oscillator_task_scheduler/dut/task_update_valid
add wave sim:/tb_oscillator_task_scheduler/dut/task_update_slot
add wave -radix hexadecimal sim:/tb_oscillator_task_scheduler/dut/task_update_phase_step
add wave sim:/tb_oscillator_task_scheduler/dut/active_task_count

run -all
