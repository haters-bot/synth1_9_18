transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory sim/work_ads1256_audit]} {
    vlib sim/work_ads1256_audit
}
vmap work_ads1256_audit sim/work_ads1256_audit
vlog -sv -work work_ads1256_audit src/ads1256_scanner.v sim/tb_ads1256_protocol_audit.v
for {set fault 0} {$fault <= 8} {incr fault} {
    vsim -voptargs=+acc -onfinish stop -gFAULT=$fault -lib work_ads1256_audit tb_ads1256_protocol_audit
    run 21 ms
    if {[examine -radix unsigned sim:/tb_ads1256_protocol_audit/test_passed] != 1} {quit -code 1 -f}
    quit -sim
}
