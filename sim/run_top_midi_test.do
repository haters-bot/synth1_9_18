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
    src/synth_control_router.v \
    src/adsr_parameter_mapper.v \
    src/oscillator_task_scheduler.v \
    src/freq_lut.v \
    src/sine_lut.v \
    src/triangle_lut.v \
    src/square_lut.v \
    src/sawtooth_lut.v \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
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
add wave sim:/tb_top_midi_input/dut/midi_note_event_channel
add wave sim:/tb_top_midi_input/dut/midi_note_event_note
add wave sim:/tb_top_midi_input/dut/midi_note_event_velocity
add wave sim:/tb_top_midi_input/dut/midi_control_change_valid
add wave sim:/tb_top_midi_input/dut/midi_control_change_channel
add wave sim:/tb_top_midi_input/dut/midi_control_change_number
add wave sim:/tb_top_midi_input/dut/midi_control_change_value
add wave sim:/tb_top_midi_input/dut/waveform_select
add wave sim:/tb_top_midi_input/dut/pan_target
add wave sim:/tb_top_midi_input/dut/wt_position_target
add wave sim:/tb_top_midi_input/dut/detune_amount
add wave sim:/tb_top_midi_input/dut/unison_count
add wave sim:/tb_top_midi_input/dut/attack_control
add wave sim:/tb_top_midi_input/dut/decay_control
add wave sim:/tb_top_midi_input/dut/sustain_control_target
add wave sim:/tb_top_midi_input/dut/sustain_control_current
add wave sim:/tb_top_midi_input/dut/release_control
add wave sim:/tb_top_midi_input/dut/task_update_valid
add wave sim:/tb_top_midi_input/dut/task_update_slot
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/task_update_phase_step
add wave sim:/tb_top_midi_input/dut/task_update_velocity
add wave sim:/tb_top_midi_input/dut/task_update_enable

run -all
