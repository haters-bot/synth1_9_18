transcript on

if {![file isdirectory sim/work_phase_warp]} {
    vlib sim/work_phase_warp
}
vmap work_phase_warp sim/work_phase_warp

vlog -work work_phase_warp \
    src/wavetable_phase_warp.v \
    sim/tb_wavetable_phase_warp.v

vsim -c -lib work_phase_warp tb_wavetable_phase_warp
run -all
quit -f
