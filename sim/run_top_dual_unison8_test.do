transcript on

if {![file isdirectory sim/work_top_dual_unison8]} {
    vlib sim/work_top_dual_unison8
}
vmap work_top_dual_unison8 sim/work_top_dual_unison8

vlog -work work_top_dual_unison8 \
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
    src/ads1256_scanner.v \
    src/ribbon_pitch_processor.v \
    src/ribbon_pitch_to_step.v \
    src/ribbon_controller_6ch.v \
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
    src/stereo_pan_mixer.v \
    src/stereo_output_stage.v \
    src/control_event_merge.v \
    src/lfo_hermite_table.v \
    src/lfo_target_router_v2.v \
    src/lfo_v2_engine.v \
    src/top.v.v \
    sim/tb_top_dual_unison8.v

vsim -c -voptargs=+acc -lib work_top_dual_unison8 tb_top_dual_unison8
run -all
