transcript on

if {![file isdirectory sim/work_top_midi]} {
    vlib sim/work_top_midi
}
vmap work_top_midi sim/work_top_midi

vlog -work work_top_midi \
    sim/fir_decimator_8x_ip_stub.v \
    sim/sys_pll_50m_ip_stub.v \
    src/reset_release_sync.v \
    src/sys_clock_manager.v \
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
    src/wavetable_phase_warp.v \
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
add wave sim:/tb_top_midi_input/dut/pan_target
add wave sim:/tb_top_midi_input/dut/osc_a_waveform_select
add wave sim:/tb_top_midi_input/dut/osc_a_wt_position_current
add wave sim:/tb_top_midi_input/dut/osc_a_detune_amount
add wave sim:/tb_top_midi_input/dut/osc_a_unison_count
add wave sim:/tb_top_midi_input/dut/osc_a_warp_mode
add wave sim:/tb_top_midi_input/dut/osc_a_warp_amount_target
add wave sim:/tb_top_midi_input/dut/osc_a_warp_amount_current
add wave sim:/tb_top_midi_input/dut/osc_b_waveform_select
add wave sim:/tb_top_midi_input/dut/osc_b_wt_position_current
add wave sim:/tb_top_midi_input/dut/osc_b_detune_amount
add wave sim:/tb_top_midi_input/dut/osc_b_unison_count
add wave sim:/tb_top_midi_input/dut/osc_b_warp_mode
add wave sim:/tb_top_midi_input/dut/osc_b_warp_amount_target
add wave sim:/tb_top_midi_input/dut/osc_b_warp_amount_current
add wave sim:/tb_top_midi_input/dut/osc_a_enabled
add wave sim:/tb_top_midi_input/dut/osc_b_enabled
add wave -radix unsigned sim:/tb_top_midi_input/dut/osc_a_mix_gain_q8
add wave -radix unsigned sim:/tb_top_midi_input/dut/osc_b_mix_gain_q8
add wave sim:/tb_top_midi_input/dut/osc_a_task_update_valid
add wave sim:/tb_top_midi_input/dut/osc_a_task_update_slot
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/osc_a_task_update_phase_step
add wave sim:/tb_top_midi_input/dut/osc_b_task_update_valid
add wave sim:/tb_top_midi_input/dut/osc_b_task_update_slot
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/osc_b_task_update_phase_step
add wave sim:/tb_top_midi_input/dut/osc_a_mix
add wave sim:/tb_top_midi_input/dut/osc_b_mix
add wave sim:/tb_top_midi_input/dut/oscillator_mix

run -all
