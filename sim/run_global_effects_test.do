transcript on

if {![file isdirectory sim/work_global_effects]} {
    vlib sim/work_global_effects
}
vmap work_global_effects sim/work_global_effects

vlog -work work_global_effects \
    src/global_delay.v \
    src/global_reverb.v \
    src/global_delay_reverb.v \
    src/global_distortion.v \
    src/global_phaser.v \
    src/global_chorus.v \
    src/global_compressor.v \
    src/global_effects.v \
    sim/tb_global_effects.v

vsim -c -voptargs=+acc -lib work_global_effects tb_global_effects
run -all
