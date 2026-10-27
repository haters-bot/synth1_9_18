transcript on

if {![file isdirectory sim/work_performance_pitch]} {
    vlib sim/work_performance_pitch
}
vmap work_performance_pitch sim/work_performance_pitch

vlog -work work_performance_pitch \
    src/freq_lut.v \
    src/sine_lut.v \
    src/performance_pitch_controller.v \
    sim/tb_performance_pitch_controller.v

vsim -c -voptargs=+acc -lib work_performance_pitch \
    tb_performance_pitch_controller
run -all
