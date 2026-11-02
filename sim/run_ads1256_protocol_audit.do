transcript on
if {![file isdirectory sim/work_ads1256_audit]} {
    vlib sim/work_ads1256_audit
}
vmap work_ads1256_audit sim/work_ads1256_audit
vlog -work work_ads1256_audit src/ads1256_scanner.v sim/tb_ads1256_protocol_audit.v
vsim -voptargs=+acc -lib work_ads1256_audit tb_ads1256_protocol_audit
run -all
