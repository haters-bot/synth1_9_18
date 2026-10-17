// ==============================================================================
// Timing Constraints: ui_touch_hub.sdc
// ==============================================================================

create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]

// Generated PLL clocks
create_clock -name clk_pixel  -period 16.000 -waveform {0.000 8.000}  [get_pins {u_pll/PLL_inst/CLKOUT0}]
create_clock -name clk_5x_bit -period 3.200  -waveform {0.000 1.600}  [get_pins {u_pll/PLL_inst/CLKOUT1}]
create_clock -name clk_usb    -period 16.667 -waveform {0.000 8.333}  [get_pins {u_pll_usb/PLL_inst/CLKOUT0}]

// Board CH569 HSPI clock (~50MHz)
create_clock -name ch569_htclk -period 20.000 -waveform {0.000 10.000} [get_ports {ch569_htclk}]

set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {clk_pixel clk_5x_bit}] -group [get_clocks {clk_usb}] -group [get_clocks {ch569_htclk}]
