transcript on

if {![file isdirectory sim/work_tdm]} {
    vlib sim/work_tdm
}
vmap work_tdm sim/work_tdm

vlog -work work_tdm \
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
    sim/tb_oscillator_tdm_bank.v

vsim -voptargs=+acc -lib work_tdm tb_oscillator_tdm_bank

add wave -divider {Scheduler control}
add wave sim:/tb_oscillator_tdm_bank/start_tick
add wave sim:/tb_oscillator_tdm_bank/waveform_select
add wave sim:/tb_oscillator_tdm_bank/debug_busy
add wave -radix unsigned sim:/tb_oscillator_tdm_bank/debug_slot
add wave sim:/tb_oscillator_tdm_bank/debug_slot_commit
add wave sim:/tb_oscillator_tdm_bank/schedule_overrun

add wave -divider {Mixed output}
add wave sim:/tb_oscillator_tdm_bank/sample_valid
add wave -radix decimal sim:/tb_oscillator_tdm_bank/sample_out

run -all
