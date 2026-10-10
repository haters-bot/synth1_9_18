transcript on

if {![file isdirectory sim/work_top_midi]} {
    vlib sim/work_top_midi
}
vmap work_top_midi sim/work_top_midi

vlog -work work_top_midi \
    sim/fir_decimator_8x_ip_stub.v \
    src/reset_release_sync.v \
    src/uart_rx.v \
    src/midi_note_parser.v \
    src/oscillator_task_scheduler.v \
    src/freq_lut.v \
    src/square_lut.v \
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    src/fir_decimator_8x_wrapper.v \
    src/i2s_tx.v \
    src/top.v.v \
    sim/tb_top_midi_input.v

vsim -voptargs=+acc -lib work_top_midi tb_top_midi_input

add wave sim:/tb_top_midi_input/dut/uart_byte
add wave sim:/tb_top_midi_input/dut/uart_byte_valid
add wave sim:/tb_top_midi_input/dut/midi_note_event_valid
add wave sim:/tb_top_midi_input/dut/midi_note_event_on
add wave sim:/tb_top_midi_input/dut/midi_note_event_note
add wave sim:/tb_top_midi_input/dut/midi_note_event_velocity
add wave sim:/tb_top_midi_input/dut/task_update_valid
add wave sim:/tb_top_midi_input/dut/task_update_slot
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/task_update_phase_step
add wave sim:/tb_top_midi_input/dut/task_update_velocity
add wave sim:/tb_top_midi_input/dut/task_update_enable

run -all
