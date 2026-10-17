# Separate project/top keeps normal MIDI firmware and diagnostic firmware distinct.
set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir 2_ui_touch_hub_debug.gprj]
run all
exit
