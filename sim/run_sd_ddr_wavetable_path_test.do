if {![file isdirectory sim/work_sd_ddr_wavetable]} {
    vlib sim/work_sd_ddr_wavetable
}
vmap work_sd_ddr_wavetable sim/work_sd_ddr_wavetable

vlog -work work_sd_ddr_wavetable \
    src/async_fifo.v \
    src/sd_wavetable_loader.v \
    src/ddr3_transaction_arbiter.v \
    src/wavetable_cache_loader.v \
    src/wavetable_frame_cache.v \
    sim/tb_sd_ddr_wavetable_path.v

vsim -c -voptargs=+acc -lib work_sd_ddr_wavetable tb_sd_ddr_wavetable_path
run -all
quit -f
