transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory sim/work_ribbon_fault]} {vlib sim/work_ribbon_fault}
vmap work_ribbon_fault sim/work_ribbon_fault
vlog -sv -work work_ribbon_fault src/freq_lut.v src/ads1256_scanner.v src/ribbon_pitch_processor.v src/ribbon_pitch_to_step.v src/ribbon_controller_6ch.v sim/tb_ribbon_adc_fault.v
vsim -voptargs=+acc -lib work_ribbon_fault tb_ribbon_adc_fault
run -all
