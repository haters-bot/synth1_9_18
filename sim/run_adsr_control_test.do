transcript on

if {![file isdirectory sim/work_adsr_control]} {
    vlib sim/work_adsr_control
}
vmap work_adsr_control sim/work_adsr_control

vlog -work work_adsr_control \
    src/adsr_parameter_mapper.v \
    src/sine_lut.v \
    src/triangle_lut.v \
    src/square_lut.v \
    src/sawtooth_lut.v \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
    src/oscillator_tdm_core.v \
    sim/tb_adsr_control.v

vsim -voptargs=+acc -lib work_adsr_control tb_adsr_control
run -all
