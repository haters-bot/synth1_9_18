transcript on

if {![file isdirectory sim/work_filter_curve_lfo]} {
    vlib sim/work_filter_curve_lfo
}
vmap work_filter_curve_lfo sim/work_filter_curve_lfo

vlog -work work_filter_curve_lfo \
    src/filter_curve_lfo.v \
    sim/tb_filter_curve_lfo.v

vsim -voptargs=+acc -lib work_filter_curve_lfo tb_filter_curve_lfo
run -all
