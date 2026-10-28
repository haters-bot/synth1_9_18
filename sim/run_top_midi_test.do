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
    src/highres_parameter_parser.v \
    src/parameter_linear_interpolator.v \
    src/filter_curve_lfo.v \
    src/synth_control_router.v \
    src/adsr_parameter_mapper.v \
    src/performance_pitch_controller.v \
    src/oscillator_task_scheduler.v \
    src/freq_lut.v \
    src/sine_lut.v \
    src/triangle_lut.v \
    src/square_lut.v \
    src/sawtooth_lut.v \
    src/wavetable_phase_warp.v \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
    src/wavetable_frame_cache.v \
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    src/fir_decimator_8x_wrapper.v \
    src/global_svf_filter.v \
    src/global_comb_filter.v \
    src/global_filter.v \
    src/global_delay.v \
    src/global_reverb.v \
    src/global_delay_reverb.v \
    src/global_distortion.v \
    src/global_phaser.v \
    src/global_chorus.v \
    src/global_compressor.v \
    src/global_effects.v \
    src/i2s_tx.v \
    src/control_event_merge.v \
    src/lfo_hermite_table.v \
    src/lfo_target_router_v2.v \
    src/lfo_v2_engine.v \
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
add wave sim:/tb_top_midi_input/dut/vibrato_enable
add wave -radix unsigned sim:/tb_top_midi_input/dut/vibrato_rate
add wave -radix unsigned sim:/tb_top_midi_input/dut/vibrato_depth
add wave sim:/tb_top_midi_input/dut/portamento_enable
add wave -radix unsigned sim:/tb_top_midi_input/dut/portamento_time
add wave sim:/tb_top_midi_input/dut/pitch_note_event_valid
add wave sim:/tb_top_midi_input/dut/pitch_note_event_on
add wave -radix unsigned sim:/tb_top_midi_input/dut/pitch_note_event_note
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/glide_base_step
add wave -radix signed sim:/tb_top_midi_input/dut/vibrato_ratio_delta_q16
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/debug_glide_current_pitch_q16
add wave -radix hexadecimal sim:/tb_top_midi_input/dut/debug_glide_target_pitch_q16
add wave sim:/tb_top_midi_input/dut/pan_target
add wave sim:/tb_top_midi_input/dut/filter_mode_target
add wave sim:/tb_top_midi_input/dut/filter_mode_active
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_cutoff_target
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_cutoff_current_q8
add wave sim:/tb_top_midi_input/dut/filter_cutoff_interpolation_busy
add wave sim:/tb_top_midi_input/dut/lfo_v2_config_applied
add wave sim:/tb_top_midi_input/dut/lfo_v2_config_busy
add wave -radix unsigned sim:/tb_top_midi_input/dut/lfo_v2_phase_indices
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_resonance_target
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_resonance_current
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_mix_target
add wave -radix unsigned sim:/tb_top_midi_input/dut/filter_mix_current
add wave -radix unsigned sim:/tb_top_midi_input/dut/master_level_target
add wave -radix unsigned sim:/tb_top_midi_input/dut/master_gain_q8
add wave sim:/tb_top_midi_input/dut/osc_a_waveform_select
add wave sim:/tb_top_midi_input/dut/osc_a_wt_position_current
add wave sim:/tb_top_midi_input/dut/osc_a_detune_amount
add wave sim:/tb_top_midi_input/dut/osc_a_unison_count
add wave sim:/tb_top_midi_input/dut/osc_a_warp_mode
add wave sim:/tb_top_midi_input/dut/osc_a_warp_mode_active
add wave sim:/tb_top_midi_input/dut/osc_a_warp_amount_target
add wave sim:/tb_top_midi_input/dut/osc_a_warp_amount_current
add wave sim:/tb_top_midi_input/dut/osc_b_waveform_select
add wave sim:/tb_top_midi_input/dut/osc_b_wt_position_current
add wave sim:/tb_top_midi_input/dut/osc_b_detune_amount
add wave sim:/tb_top_midi_input/dut/osc_b_unison_count
add wave sim:/tb_top_midi_input/dut/osc_b_warp_mode
add wave sim:/tb_top_midi_input/dut/osc_b_warp_mode_active
add wave sim:/tb_top_midi_input/dut/osc_b_warp_amount_target
add wave sim:/tb_top_midi_input/dut/osc_b_warp_amount_current
add wave sim:/tb_top_midi_input/dut/osc_a_enabled
add wave sim:/tb_top_midi_input/dut/osc_b_enabled
add wave -radix unsigned sim:/tb_top_midi_input/dut/osc_a_level
add wave -radix unsigned sim:/tb_top_midi_input/dut/osc_b_level
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
add wave sim:/tb_top_midi_input/dut/master_output_sample
add wave sim:/tb_top_midi_input/dut/oscillator_mix_clip
add wave sim:/tb_top_midi_input/dut/filter_output_limit
add wave sim:/tb_top_midi_input/dut/master_output_clip
add wave -radix unsigned sim:/tb_top_midi_input/dut/audio_clip_count

run -all
