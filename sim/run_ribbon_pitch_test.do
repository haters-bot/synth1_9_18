transcript on

if {![file isdirectory sim/work_ribbon_pitch]} {
    vlib sim/work_ribbon_pitch
}
vmap work_ribbon_pitch sim/work_ribbon_pitch

vlog -work work_ribbon_pitch \
    src/freq_lut.v \
    src/ribbon_pitch_processor.v \
    src/ribbon_pitch_to_step.v \
    sim/tb_ribbon_pitch_path.v

vsim -voptargs=+acc -lib work_ribbon_pitch tb_ribbon_pitch_path
run -all
