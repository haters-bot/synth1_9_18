set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir 2_ui_touch_hub.gprj]
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
run all
exit
