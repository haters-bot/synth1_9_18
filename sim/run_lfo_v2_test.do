onerror {quit -code 1 -force}
if {![file isdirectory sim/work_lfo_v2]} {vlib sim/work_lfo_v2}
vmap work_lfo_v2 sim/work_lfo_v2
vlog -sv -work work_lfo_v2 src/lfo_hermite_table.v src/lfo_target_router_v2.v src/lfo_v2_engine.v sim/tb_lfo_v2.v
vsim -voptargs=+acc -lib work_lfo_v2 tb_lfo_v2
run -all
