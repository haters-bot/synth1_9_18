// 50 MHz board oscillator: 20 ns period.
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]
