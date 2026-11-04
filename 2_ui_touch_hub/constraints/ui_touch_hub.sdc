// ==============================================================================
// Timing Constraints: ui_touch_hub.sdc
// ==============================================================================

create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]

// Generated PLL clocks
create_clock -name clk_pixel  -period 20.000 -waveform {0.000 10.000}  [get_pins {u_pll/PLL_inst/CLKOUT0}]
create_clock -name clk_5x_bit -period 4.000  -waveform {0.000 2.000}  [get_pins {u_pll/PLL_inst/CLKOUT1}]
create_clock -name clk_usb    -period 16.667 -waveform {0.000 8.333}  [get_pins {u_pll_usb/PLL_inst/CLKOUT0}]

// Board CH569 HSPI clock (~50MHz)
create_clock -name ch569_htclk -period 20.000 -waveform {0.000 10.000} [get_ports {ch569_htclk}]

# GW5AST-138B official DDR3 1:4 reference separates the PHY and user clocks.
# These are IP-defined domain boundaries, not ordinary single-cycle paths.
# Source and reviewed scope: doc/DDR_OFFICIAL_TIMING_REFERENCE_2026-10-29.md.
# PCM crosses to the 100 MHz user port through Gray-pointer FIFOs.
create_clock -name ddr_clk400 -period 2.500 -waveform {0.000 1.250} [get_nets {u_ddr3_wrapper/memory_clk}]
create_clock -name ddr_user_clk100 -period 10.000 -waveform {0.000 5.000} [get_pins {u_ddr3_wrapper/u_ddr3_ip/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {clk_pixel clk_5x_bit}] -group [get_clocks {clk_usb}] -group [get_clocks {ch569_htclk}] -group [get_clocks {ddr_clk400}] -group [get_clocks {ddr_user_clk100}]

# Serializer reset deassertion is synchronized locally to clk_5x_bit.
# Do not exempt OSER10 RESET: recovery/removal must remain in STA.

# SUG940 section 5.5.1: report the pixel path even when DDR dominates the
# global list. Extra reports only affect diagnostics, never timing exceptions.
report_timing -setup -max_paths 200
report_timing -hold -max_paths 50
report_timing -recovery -max_paths 256
report_timing -removal -max_paths 256
report_timing -setup -from_clock [get_clocks {clk_pixel}] -to_clock [get_clocks {clk_pixel}] -max_paths 50
report_timing -recovery -from_clock [get_clocks {clk_5x_bit}] -to_clock [get_clocks {clk_5x_bit}] -max_paths 25
report_timing -removal -from_clock [get_clocks {clk_5x_bit}] -to_clock [get_clocks {clk_5x_bit}] -max_paths 25
