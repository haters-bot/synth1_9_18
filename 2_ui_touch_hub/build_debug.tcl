# Separate project/top keeps normal MIDI firmware and diagnostic firmware distinct.
set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir 2_ui_touch_hub_debug.gprj]
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -synthesis_tool gowinsynthesis
set_option -place_option 3
set_option -route_option 1
set_option -timing_driven 1
run all
exit
