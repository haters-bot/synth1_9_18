// 顶层功能仿真使用的PLL替代模型。
// 频率保持1:1；解除PLL复位后立即报告锁定，系统同步复位仍延迟两拍释放。
module sys_pll_50m_ip(
    input  wire clkin,
    input  wire init_clk,
    output wire clkout0,
    output wire lock,
    input  wire reset
);

    assign clkout0 = clkin;
    assign lock = ~reset;

    wire unused_init_clk;
    assign unused_init_clk = init_clk;

endmodule
