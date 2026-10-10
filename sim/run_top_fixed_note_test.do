transcript on

if {![file isdirectory sim/work_top_fixed_note]} {
    vlib sim/work_top_fixed_note
}
vmap work_top_fixed_note sim/work_top_fixed_note

vlog -work work_top_fixed_note \
    sim/fir_decimator_8x_ip_stub.v \
    src/reset_release_sync.v \
    src/oscillator_task_scheduler.v \
    src/freq_lut.v \
    src/square_lut.v \
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    src/fir_decimator_8x_wrapper.v \
    src/i2s_tx.v \
    src/top.v.v \
    sim/tb_top_fixed_note.v

vsim -voptargs=+acc -lib work_top_fixed_note tb_top_fixed_note

add wave sim:/tb_top_fixed_note/dut/fixed_note_event_valid
add wave sim:/tb_top_fixed_note/dut/task_update_valid
add wave sim:/tb_top_fixed_note/dut/task_update_slot
add wave -radix hexadecimal sim:/tb_top_fixed_note/dut/task_update_phase_step
add wave sim:/tb_top_fixed_note/dut/active_task_count
add wave -radix decimal sim:/tb_top_fixed_note/dut/oscillator_mix
add wave sim:/tb_top_fixed_note/dut/oscillator_mix_valid
add wave -radix decimal sim:/tb_top_fixed_note/dut/filtered_sample
add wave sim:/tb_top_fixed_note/dut/fir_output_valid

run -all
