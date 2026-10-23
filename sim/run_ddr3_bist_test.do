transcript on

if {![file isdirectory sim/work_ddr3_bist]} {
    vlib sim/work_ddr3_bist
}
vmap work_ddr3_bist sim/work_ddr3_bist

vlog -work work_ddr3_bist \
    src/ddr3_user_port_adapter.v \
    src/ddr3_bist.v \
    sim/tb_ddr3_bist.v

vsim -voptargs=+acc -lib work_ddr3_bist tb_ddr3_bist
onfinish stop

add wave sim:/tb_ddr3_bist/init_done
add wave sim:/tb_ddr3_bist/start
add wave sim:/tb_ddr3_bist/req_valid
add wave sim:/tb_ddr3_bist/req_ready
add wave sim:/tb_ddr3_bist/req_write
add wave -radix hex sim:/tb_ddr3_bist/req_addr
add wave sim:/tb_ddr3_bist/mc_cmd_ready
add wave sim:/tb_ddr3_bist/mc_wr_data_rdy
add wave sim:/tb_ddr3_bist/rsp_valid
add wave sim:/tb_ddr3_bist/bist_done
add wave sim:/tb_ddr3_bist/bist_pass
add wave -radix unsigned sim:/tb_ddr3_bist/error_count

run -all
quit -sim
