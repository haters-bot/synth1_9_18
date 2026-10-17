transcript on

if {![file isdirectory sim/work_parameter_control]} {
    vlib sim/work_parameter_control
}
vmap work_parameter_control sim/work_parameter_control

vlog -work work_parameter_control \
    src/highres_parameter_parser.v \
    src/parameter_linear_interpolator.v \
    sim/tb_parameter_control.v

vsim -voptargs=+acc -lib work_parameter_control tb_parameter_control

add wave sim:/tb_parameter_control/byte_data
add wave sim:/tb_parameter_control/byte_valid
add wave sim:/tb_parameter_control/parameter_valid
add wave -radix unsigned sim:/tb_parameter_control/parameter_id
add wave -radix unsigned sim:/tb_parameter_control/parameter_value
add wave -radix unsigned sim:/tb_parameter_control/current_value
add wave sim:/tb_parameter_control/busy

run -all
