transcript on

if {![file isdirectory sim/work_full_top]} {
    vlib sim/work_full_top
}
vmap work_full_top sim/work_full_top

# 厂商IP使用接口桩，只检查完整SD/DDR/音频顶层的RTL语法和层次连接。
vlog -sv -work work_full_top \
    sim/fir_decimator_8x_ip_stub.v \
    sim/sys_pll_50m_ip_stub.v \
    sim/ddr3_vendor_ip_stubs.v \
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
    src/i2s_visual_tx.v \
    src/control_event_merge.v \
    src/async_fifo.v \
    src/sd_wavetable_loader.v \
    src/ddr3_transaction_arbiter.v \
    src/wavetable_cache_loader.v \
    src/ddr3_user_port_adapter.v \
    src/ddr3_wavetable_wrapper.v \
    src/sd_card/sdcmd_ctrl.sv \
    src/sd_card/sd_reader.sv \
    src/sd_card/sd_file_list_reader.sv \
    src/wavetable_storage_system.sv \
    src/top.v.v

vsim -c -lib work_full_top top
quit -f
