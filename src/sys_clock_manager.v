// 系统时钟管理：板载50 MHz参考时钟经PLL后仍输出50 MHz。
// 外部复位异步拉低系统复位；PLL锁定状态进入clk_sys域后同步控制释放。
module sys_clock_manager(
    input  wire clk_ref_50m,
    input  wire rst_n_async,
    output wire clk_sys,
    output wire rst_n_sys,
    output wire pll_locked
);

    sys_pll_50m_ip u_sys_pll_50m_ip (
        .clkin   (clk_ref_50m),
        .init_clk(clk_ref_50m),
        .clkout0 (clk_sys),
        .lock    (pll_locked),
        .reset   (~rst_n_async)
    );

    reset_release_sync u_reset_release_sync (
        .clk                 (clk_sys),
        .rst_n_async         (rst_n_async),
        .release_enable_async(pll_locked),
        .rst_n_sync          (rst_n_sys)
    );

endmodule
