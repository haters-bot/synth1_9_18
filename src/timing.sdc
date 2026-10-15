// 50 MHz board oscillator: 20 ns period.
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

// pll_locked跨入clk_sys域时，第一拍是专门的亚稳态吸收寄存器。
// 只豁免异步源到同步器第一拍的Setup/Hold分析，第二拍及后续路径继续正常分析。
set_false_path -to [get_regs {u_sys_clock_manager/u_reset_release_sync/release_enable_pipe_0_s0}]
