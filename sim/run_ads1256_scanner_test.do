transcript on

if {![file isdirectory sim/work_ads1256]} {
    vlib sim/work_ads1256
}
vmap work_ads1256 sim/work_ads1256
vlog -work work_ads1256 src/ads1256_scanner.v sim/tb_ads1256_scanner.v
vsim -voptargs=+acc -lib work_ads1256 tb_ads1256_scanner
run -all
