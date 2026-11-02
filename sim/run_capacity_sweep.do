transcript on

if {![file isdirectory sim/work_capacity]} {
    vlib sim/work_capacity
}
vmap work_capacity sim/work_capacity

vlog -work work_capacity \
    src/freq_lut.v \
    src/sine_lut.v \
    src/triangle_lut.v \
    src/square_lut.v \
    src/sawtooth_lut.v \
    src/wavetable_phase_warp.v \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
    src/wavetable_frame_cache.v \
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    sim/tb_dual_osc_capacity.v

proc run_capacity {engines slots voices unison tick_period expected_overrun external_test} {
    puts "--- capacity ${engines}x${slots}, voices=${voices}, unison=${unison}, tick=${tick_period} ---"
    vsim -quiet -voptargs=+acc -lib work_capacity \
        -gENGINE_COUNT=${engines} -gSLOTS_PER_ENGINE=${slots} \
        -gVOICE_COUNT=${voices} -gUNISON_COUNT=${unison} \
        -gEXPECT_OVERRUN=${expected_overrun} -gEXTERNAL_TEST=${external_test} \
        -gTICK_PERIOD_CLOCKS=${tick_period} \
        tb_dual_osc_capacity
    run -all
    quit -sim
}

run_capacity 1 64 8 8 65 1 0
run_capacity 2 32 8 8 65 0 0
run_capacity 4 16 8 8 65 0 0
run_capacity 8 8 8 8 65 0 0
run_capacity 2 32 64 1 64 0 0
run_capacity 2 32 8 8 65 0 1

quit -f
