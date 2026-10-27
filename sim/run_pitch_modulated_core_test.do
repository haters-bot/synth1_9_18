transcript on

if {![file isdirectory sim/work_pitch_modulated_core]} {
    vlib sim/work_pitch_modulated_core
}
vmap work_pitch_modulated_core sim/work_pitch_modulated_core

vlog -work work_pitch_modulated_core \
    src/sine_lut.v \
    src/triangle_lut.v \
    src/square_lut.v \
    src/sawtooth_lut.v \
    src/wavetable_phase_warp.v \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
    src/wavetable_frame_cache.v \
    src/oscillator_tdm_core.v \
    sim/tb_pitch_modulated_core.v

vsim -c -voptargs=+acc -lib work_pitch_modulated_core \
    tb_pitch_modulated_core
run -all
