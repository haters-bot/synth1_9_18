transcript on

if {![file isdirectory sim/work_acid_wavetable]} {
    vlib sim/work_acid_wavetable
}
vmap work_acid_wavetable sim/work_acid_wavetable

vlog -work work_acid_wavetable \
    src/acid_wavetable_rom.v \
    src/acid_wavetable_reader.v \
    sim/tb_acid_wavetable_reader.v

vsim -voptargs=+acc -lib work_acid_wavetable tb_acid_wavetable_reader
run -all
