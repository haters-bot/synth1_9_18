transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
file mkdir tmp
foreach {name module} {ribbon_pitch_processor ribbon_pitch_processor_reference performance_pitch_controller performance_pitch_controller_reference} {
    set source [exec git show 0dbd8a7:src/$name.v]
    set source [string map [list "module $name" "module $module"] $source]
    set out [open tmp/${module}.v w]
    puts $out $source
    close $out
}
if {![file isdirectory sim/work_timing_equivalence]} {vlib sim/work_timing_equivalence}
vmap work_timing_equivalence sim/work_timing_equivalence
vlog -sv -work work_timing_equivalence src/freq_lut.v src/sine_lut.v src/ribbon_pitch_processor.v tmp/ribbon_pitch_processor_reference.v src/performance_pitch_controller.v tmp/performance_pitch_controller_reference.v sim/tb_ribbon_timing_equivalence.v sim/tb_vibrato_timing_equivalence.v
