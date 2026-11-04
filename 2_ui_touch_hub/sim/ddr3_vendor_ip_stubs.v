// 仅用于RTL语法与层次检查，不代表DDR3或PLL的真实时序行为。
module ddr3_pll_400m_ip(
    input  wire clkin,
    input  wire init_clk,
    input  wire enclk0,
    input  wire enclk1,
    input  wire enclk2,
    output wire clkout0,
    output wire clkout1,
    output wire clkout2,
    output wire lock,
    input  wire reset
);
    assign clkout0 = clkin;
    assign clkout1 = clkin;
    assign clkout2 = clkin;
    assign lock = !reset;
endmodule

module DDR3_Memory_Interface_Top(
    input  wire         clk,
    output wire         pll_stop,
    input  wire         memory_clk,
    input  wire         pll_lock,
    input  wire         rst_n,
    output wire         clk_out,
    output wire         ddr_rst,
    output wire         init_calib_complete,
    output wire         cmd_ready,
    input  wire [2:0]   cmd,
    input  wire         cmd_en,
    input  wire [28:0]  addr,
    output wire         wr_data_rdy,
    input  wire [255:0] wr_data,
    input  wire         wr_data_en,
    input  wire         wr_data_end,
    input  wire [31:0]  wr_data_mask,
    output wire [255:0] rd_data,
    output wire         rd_data_valid,
    output wire         rd_data_end,
    input  wire         sr_req,
    input  wire         ref_req,
    output wire         sr_ack,
    output wire         ref_ack,
    input  wire         burst,
    output wire [14:0]  O_ddr_addr,
    output wire [2:0]   O_ddr_ba,
    output wire         O_ddr_cs_n,
    output wire         O_ddr_ras_n,
    output wire         O_ddr_cas_n,
    output wire         O_ddr_we_n,
    output wire         O_ddr_clk,
    output wire         O_ddr_clk_n,
    output wire         O_ddr_cke,
    output wire         O_ddr_odt,
    output wire         O_ddr_reset_n,
    output wire [3:0]   O_ddr_dqm,
    inout  wire [31:0]  IO_ddr_dq,
    inout  wire [3:0]   IO_ddr_dqs,
    inout  wire [3:0]   IO_ddr_dqs_n
);
    assign pll_stop = 1'b1;
    assign clk_out = clk;
    assign ddr_rst = !rst_n;
    assign init_calib_complete = rst_n && pll_lock;
    assign cmd_ready = 1'b0;
    assign wr_data_rdy = 1'b0;
    assign rd_data = 256'd0;
    assign rd_data_valid = 1'b0;
    assign rd_data_end = 1'b0;
    assign sr_ack = 1'b0;
    assign ref_ack = 1'b0;
    assign O_ddr_addr = 15'd0;
    assign O_ddr_ba = 3'd0;
    assign O_ddr_cs_n = 1'b1;
    assign O_ddr_ras_n = 1'b1;
    assign O_ddr_cas_n = 1'b1;
    assign O_ddr_we_n = 1'b1;
    assign O_ddr_clk = 1'b0;
    assign O_ddr_clk_n = 1'b1;
    assign O_ddr_cke = 1'b0;
    assign O_ddr_odt = 1'b0;
    assign O_ddr_reset_n = rst_n;
    assign O_ddr_dqm = 4'hF;
    assign IO_ddr_dq = 32'hzzzzzzzz;
    assign IO_ddr_dqs = 4'hz;
    assign IO_ddr_dqs_n = 4'hz;
endmodule
