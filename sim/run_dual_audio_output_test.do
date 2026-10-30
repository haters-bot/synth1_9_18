transcript on

if {![file isdirectory sim/work_dual_audio]} {
    vlib sim/work_dual_audio
}
vmap work_dual_audio sim/work_dual_audio

vlog -work work_dual_audio \
    src/i2s_tx.v \
    src/pt8211_tx.v \
    sim/tb_dual_audio_output.v

vsim -c -voptargs=+acc -lib work_dual_audio tb_dual_audio_output
run -all
