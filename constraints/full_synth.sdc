// Board 50 MHz reference clock.
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

// 在PLL输出引脚上显式建立系统50 MHz时钟，避免依赖时序分析阶段才生成的默认时钟名称。
create_clock -name clk_sys -period 20.000 -waveform {0.000 10.000} [get_pins {u_sys_clock_manager/u_sys_pll_50m_ip/u_pll/PLL_inst/CLKOUT0}]

// First stage of the audio-system reset synchronizer.
set_false_path -to [get_regs {u_sys_clock_manager/u_reset_release_sync/release_enable_pipe_0_s0}]

// DDR PLL output and DDR user clock.
create_clock -name ddr_clk400 -period 2.500 -waveform {0.000 1.250} [get_nets {GEN_WAVETABLE_STORAGE.u_wavetable_storage_system/u_ddr3_wrapper/memory_clk}]
create_clock -name ddr_user_clk100 -period 10.000 -waveform {0.000 5.000} [get_pins {GEN_WAVETABLE_STORAGE.u_wavetable_storage_system/u_ddr3_wrapper/u_ddr3_ip/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

// 系统PLL与DDR PLL之间按异步时钟域处理；所有跨域数据必须经过同步器或异步FIFO。
// DDR 400 MHz与DDR用户100 MHz属于同一个DDR时钟组，保留IP内部的时序分析。
set_clock_groups -asynchronous -group [get_clocks {sys_clk clk_sys}] -group [get_clocks {ddr_clk400 ddr_user_clk100}]

// Asynchronous control UART input, first synchronizer stage only.
set_false_path -from [get_ports {control_uart_rx}] -to [get_regs {u_control_uart_rx/rx_meta_s0}]

// Asynchronous physical-keyboard UART input, first synchronizer stage only.
set_false_path -from [get_ports {keyboard_uart_rx}] -to [get_regs {u_keyboard_uart_rx/rx_meta_s0}]

// Asynchronous board USB-UART input, first synchronizer stage only.
set_false_path -from [get_ports {uart_rx}] -to [get_regs {u_uart_rx/rx_meta_s0}]
