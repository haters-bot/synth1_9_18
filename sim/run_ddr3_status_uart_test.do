transcript on

if {![file isdirectory sim/work_ddr3_status_uart]} {
    vlib sim/work_ddr3_status_uart
}
vmap work_ddr3_status_uart sim/work_ddr3_status_uart

vlog -work work_ddr3_status_uart \
    src/ddr3_status_uart.v \
    sim/tb_ddr3_status_uart.v

vsim -c -lib work_ddr3_status_uart tb_ddr3_status_uart
onfinish exit
run -all
