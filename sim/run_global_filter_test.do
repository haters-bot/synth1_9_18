transcript on

if {![file isdirectory sim/work_global_filter]} {
    vlib sim/work_global_filter
}
vmap work_global_filter sim/work_global_filter

vlog -work work_global_filter \
    src/global_svf_filter.v \
    sim/tb_global_svf_filter.v

vsim -voptargs=+acc -lib work_global_filter tb_global_svf_filter

add wave sim:/tb_global_svf_filter/filter_mode
add wave -radix unsigned sim:/tb_global_svf_filter/cutoff_control
add wave -radix unsigned sim:/tb_global_svf_filter/resonance_control
add wave sim:/tb_global_svf_filter/in_valid
add wave sim:/tb_global_svf_filter/in_ready
add wave -radix decimal sim:/tb_global_svf_filter/sample_in
add wave sim:/tb_global_svf_filter/out_valid
add wave -radix decimal sim:/tb_global_svf_filter/sample_out
add wave -radix decimal sim:/tb_global_svf_filter/dut/low_state_q16
add wave -radix decimal sim:/tb_global_svf_filter/dut/band_state_q16

run -all
