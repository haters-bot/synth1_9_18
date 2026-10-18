// 板载参考时钟：V22，50 MHz。
create_clock -name clk50 -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

// DDR PLL输出：400 MHz。这里使用厂商例程相同的独立时钟建模方式，
// 避免STA把DDR PHY内部专用跨时钟结构当作普通同步逻辑分析。
create_clock -name clk400 -period 2.500 -waveform {0.000 1.250} [get_nets {u_ddr3_wrapper/memory_clk}]

// DDR控制器用户时钟：400 MHz经过IP内部CLKDIV四分频得到100 MHz。
create_clock -name clk100 -period 10.000 -waveform {0.000 5.000} [get_pins {u_ddr3_wrapper/u_ddr3_ip/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

// 这些时钟之间的相位关系由DDR PHY专用资源和校准逻辑管理。
// 按Gowin官方Tang Mega DDR3例程将三个时钟组声明为互斥。
set_clock_groups -exclusive -group [get_clocks {clk400}] -group [get_clocks {clk50}] -group [get_clocks {clk100}]
