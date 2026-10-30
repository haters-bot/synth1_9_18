transcript on

if {![file isdirectory sim/work_stereo_pan]} {
    vlib sim/work_stereo_pan
}
vmap work_stereo_pan sim/work_stereo_pan

vlog -work work_stereo_pan \
    src/stereo_pan_mixer.v \
    src/stereo_output_stage.v \
    sim/tb_stereo_pan_path.v

vsim -c -voptargs=+acc -lib work_stereo_pan tb_stereo_pan_path
run -all
