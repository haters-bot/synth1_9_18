// DDR3厂商IP封装层。
// 业务模块只连接单事务接口，不直接依赖Gowin IP的命令和数据端口。
// 本模块依赖用户按ip/ddr3_wavetable与ip/ddr3_pll_400m中的配置手动生成IP。
module ddr3_wavetable_wrapper(
    input  wire         clk_ref,
    input  wire         rst_n_async,

    output wire         user_clk,
    output wire         user_rst_n,
    output wire         pll_locked,
    output wire         init_done,

    input  wire         req_valid,
    output wire         req_ready,
    input  wire         req_write,
    input  wire [28:0]  req_addr,
    input  wire [255:0] req_wdata,
    input  wire [31:0]  req_wmask,
    output wire         rsp_valid,
    output wire         rsp_write,
    output wire [255:0] rsp_rdata,
    output wire         rsp_error,

    output wire [14:0]  ddr_addr,
    output wire [2:0]   ddr_bank,
    output wire         ddr_cs,
    output wire         ddr_ras,
    output wire         ddr_cas,
    output wire         ddr_we,
    output wire         ddr_ck,
    output wire         ddr_ck_n,
    output wire         ddr_cke,
    output wire         ddr_odt,
    output wire         ddr_reset_n,
    output wire [3:0]   ddr_dm,
    inout  wire [31:0]  ddr_dq,
    inout  wire [3:0]   ddr_dqs,
    inout  wire [3:0]   ddr_dqs_n
);

    wire memory_clk;
    wire pll_stop;
    wire rst_n_ddr_ip;
    wire ddr_rst;
    wire init_calib_complete;

    wire        mc_cmd_ready;
    wire [2:0]  mc_cmd;
    wire        mc_cmd_en;
    wire [28:0] mc_addr;
    wire        mc_wr_data_rdy;
    wire [255:0] mc_wr_data;
    wire         mc_wr_data_en;
    wire         mc_wr_data_end;
    wire [31:0]  mc_wr_data_mask;
    wire [255:0] mc_rd_data;
    wire         mc_rd_data_valid;
    wire         mc_rd_data_end;

    // DDR PLL在外部复位期间保持复位。PLL锁定之后，再同步释放DDR IP复位。
    ddr3_pll_400m_ip u_ddr_pll(
        .clkin   (clk_ref),
        .init_clk(clk_ref),
        .enclk0  (1'b1),
        .enclk1  (1'b1),
        .enclk2  (pll_stop),
        .clkout0 (),
        .clkout1 (),
        .clkout2 (memory_clk),
        .lock    (pll_locked),
        .reset   (!rst_n_async)
    );

    reset_release_sync u_ddr_ip_reset_sync(
        .clk                 (clk_ref),
        .rst_n_async         (rst_n_async),
        .release_enable_async(pll_locked),
        .rst_n_sync          (rst_n_ddr_ip)
    );

    DDR3_Memory_Interface_Top u_ddr3_ip(
        .clk                (clk_ref),
        .pll_stop           (pll_stop),
        .memory_clk         (memory_clk),
        .pll_lock           (pll_locked),
        .rst_n              (rst_n_ddr_ip),
        .clk_out            (user_clk),
        .ddr_rst            (ddr_rst),
        .init_calib_complete(init_calib_complete),

        .cmd_ready          (mc_cmd_ready),
        .cmd                (mc_cmd),
        .cmd_en             (mc_cmd_en),
        .addr               (mc_addr),
        .wr_data_rdy        (mc_wr_data_rdy),
        .wr_data            (mc_wr_data),
        .wr_data_en         (mc_wr_data_en),
        .wr_data_end        (mc_wr_data_end),
        .wr_data_mask       (mc_wr_data_mask),
        .rd_data            (mc_rd_data),
        .rd_data_valid      (mc_rd_data_valid),
        .rd_data_end        (mc_rd_data_end),

        .sr_req             (1'b0),
        .ref_req            (1'b0),
        .sr_ack             (),
        .ref_ack            (),
        .burst              (1'b0),

        .O_ddr_addr         (ddr_addr),
        .O_ddr_ba           (ddr_bank),
        .O_ddr_cs_n         (ddr_cs),
        .O_ddr_ras_n        (ddr_ras),
        .O_ddr_cas_n        (ddr_cas),
        .O_ddr_we_n         (ddr_we),
        .O_ddr_clk          (ddr_ck),
        .O_ddr_clk_n        (ddr_ck_n),
        .O_ddr_cke          (ddr_cke),
        .O_ddr_odt          (ddr_odt),
        .O_ddr_reset_n      (ddr_reset_n),
        .O_ddr_dqm          (ddr_dm),
        .IO_ddr_dq          (ddr_dq),
        .IO_ddr_dqs         (ddr_dqs),
        .IO_ddr_dqs_n       (ddr_dqs_n)
    );

    // 校准完成后，在控制器输出时钟域内同步释放业务侧复位。
    reset_release_sync u_ddr_user_reset_sync(
        .clk                 (user_clk),
        .rst_n_async         (rst_n_async),
        .release_enable_async(init_calib_complete && pll_locked),
        .rst_n_sync          (user_rst_n)
    );

    assign init_done = init_calib_complete && user_rst_n;

    ddr3_user_port_adapter u_user_port_adapter(
        .clk             (user_clk),
        .rst_n           (user_rst_n),
        .init_done       (init_done),
        .req_valid       (req_valid),
        .req_ready       (req_ready),
        .req_write       (req_write),
        .req_addr        (req_addr),
        .req_wdata       (req_wdata),
        .req_wmask       (req_wmask),
        .rsp_valid       (rsp_valid),
        .rsp_write       (rsp_write),
        .rsp_rdata       (rsp_rdata),
        .rsp_error       (rsp_error),
        .mc_cmd_ready    (mc_cmd_ready),
        .mc_cmd          (mc_cmd),
        .mc_cmd_en       (mc_cmd_en),
        .mc_addr         (mc_addr),
        .mc_wr_data_rdy  (mc_wr_data_rdy),
        .mc_wr_data      (mc_wr_data),
        .mc_wr_data_en   (mc_wr_data_en),
        .mc_wr_data_end  (mc_wr_data_end),
        .mc_wr_data_mask (mc_wr_data_mask),
        .mc_rd_data      (mc_rd_data),
        .mc_rd_data_valid(mc_rd_data_valid),
        .mc_rd_data_end  (mc_rd_data_end)
    );

endmodule
