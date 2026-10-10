transcript on

if {![file isdirectory sim/work_i2s_tx]} {
    vlib sim/work_i2s_tx
}
vmap work_i2s_tx sim/work_i2s_tx

vlog -work work_i2s_tx \
    src/i2s_tx.v \
    sim/tb_i2s_tx.v

vsim -voptargs=+acc -lib work_i2s_tx tb_i2s_tx

add wave sim:/tb_i2s_tx/bclk
add wave sim:/tb_i2s_tx/lrck
add wave sim:/tb_i2s_tx/sdata
add wave sim:/tb_i2s_tx/sample_tick
add wave sim:/tb_i2s_tx/oversample_tick

run -all
