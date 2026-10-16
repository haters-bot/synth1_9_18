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
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    sim/tb_dual_osc_capacity.v

proc run_capacity {engines slots} {
    puts "--- capacity ${engines}x${slots} ---"
    vsim -quiet -voptargs=+acc -lib work_capacity \
        -gENGINE_COUNT=${engines} -gSLOTS_PER_ENGINE=${slots} \
        tb_dual_osc_capacity
    run -all
    quit -sim
}

run_capacity 1 64
run_capacity 2 32
run_capacity 4 16
run_capacity 8 8

quit -f
