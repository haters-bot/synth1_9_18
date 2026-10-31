transcript on

if {![file isdirectory sim/work_global_reverb_v2]} {
    vlib sim/work_global_reverb_v2
}
vmap work_global_reverb_v2 sim/work_global_reverb_v2

vlog -work work_global_reverb_v2 \
    src/global_reverb.v \
    sim/tb_global_reverb_v2.v

vsim -c -voptargs=+acc -lib work_global_reverb_v2 tb_global_reverb_v2
run -all
