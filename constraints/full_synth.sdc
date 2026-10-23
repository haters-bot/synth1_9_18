// 板载50 MHz参考时钟。
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

// 音频系统复位同步器第一拍。
set_false_path -to [get_regs {u_sys_clock_manager/u_reset_release_sync/release_enable_pipe_0_s0}]

// DDR PLL输出和DDR用户时钟。
create_clock -name ddr_clk400 -period 2.500 -waveform {0.000 1.250} [get_nets {GEN_WAVETABLE_STORAGE/u_wavetable_storage_system/u_ddr3_wrapper/memory_clk}]
create_clock -name ddr_user_clk100 -period 10.000 -waveform {0.000 5.000} [get_pins {GEN_WAVETABLE_STORAGE/u_wavetable_storage_system/u_ddr3_wrapper/u_ddr3_ip/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

// DDR PHY专用时钟、DDR用户时钟与系统控制域通过专用逻辑或异步FIFO交互。
set_clock_groups -exclusive -group [get_clocks {ddr_clk400}] -group [get_clocks {sys_clk}] -group [get_clocks {ddr_user_clk100}]
