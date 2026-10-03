transcript on

if {![file isdirectory sim/work_unison_scheduler]} {
    vlib sim/work_unison_scheduler
}
vmap work_unison_scheduler sim/work_unison_scheduler

vlog -work work_unison_scheduler \
    src/freq_lut.v \
    src/square_lut.v \
    src/midi_voice_allocator.v \
    src/oscillator_tdm_core.v \
    src/oscillator_tdm_bank.v \
    sim/tb_unison_scheduler_load.v

vsim -voptargs=+acc -lib work_unison_scheduler tb_unison_scheduler_load

add wave sim:/tb_unison_scheduler_load/start_tick
add wave sim:/tb_unison_scheduler_load/active_voice_count
add wave sim:/tb_unison_scheduler_load/voice_update_valid
add wave -radix unsigned sim:/tb_unison_scheduler_load/voice_update_slot
add wave -radix unsigned sim:/tb_unison_scheduler_load/voice_update_unison_lane
add wave sim:/tb_unison_scheduler_load/sample_valid
add wave sim:/tb_unison_scheduler_load/schedule_overrun

run -all
