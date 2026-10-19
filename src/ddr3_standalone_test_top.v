// DDR3 板级独立验证顶层，不接入现有音频顶层。
// DDR3 校准完成后自动测试 64 个 256 位数据块，共 2 KiB。
module ddr3_standalone_test_top(
    input  wire        sys_clk,
    input  wire        rst_n,
    output wire        uart_tx,

    output wire [14:0] ddr_addr,
    output wire [2:0]  ddr_bank,
    output wire        ddr_cs,
    output wire        ddr_ras,
    output wire        ddr_cas,
    output wire        ddr_we,
    output wire        ddr_ck,
    output wire        ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_reset_n,
    output wire [3:0]  ddr_dm,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dqs,
    inout  wire [3:0]  ddr_dqs_n
);

    wire user_clk;
    wire user_rst_n;
    wire pll_locked;
    wire init_done;

    wire         req_valid;
    wire         req_ready;
    wire         req_write;
    wire [28:0]  req_addr;
    wire [255:0] req_wdata;
    wire [31:0]  req_wmask;
    wire         rsp_valid;
    wire         rsp_write;
    wire [255:0] rsp_rdata;
    wire         rsp_error;

    reg start_bist;
    reg bist_started;
    wire bist_busy;
    wire bist_done;
    wire bist_pass;
    wire [15:0] bist_error_count;
    wire [15:0] debug_word_index;
    wire [28:0] first_error_addr;
    wire [255:0] first_error_expected;
    wire [255:0] first_error_actual;

    reg test_finished;
    reg test_passed;

    ddr3_wavetable_wrapper u_ddr3_wrapper(
        .clk_ref         (sys_clk),
        .rst_n_async     (rst_n),
        .user_clk        (user_clk),
        .user_rst_n      (user_rst_n),
        .pll_locked      (pll_locked),
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
        .ddr_addr        (ddr_addr),
        .ddr_bank        (ddr_bank),
        .ddr_cs          (ddr_cs),
        .ddr_ras         (ddr_ras),
        .ddr_cas         (ddr_cas),
        .ddr_we          (ddr_we),
        .ddr_ck          (ddr_ck),
        .ddr_ck_n        (ddr_ck_n),
        .ddr_cke         (ddr_cke),
        .ddr_odt         (ddr_odt),
        .ddr_reset_n     (ddr_reset_n),
        .ddr_dm          (ddr_dm),
        .ddr_dq          (ddr_dq),
        .ddr_dqs         (ddr_dqs),
        .ddr_dqs_n       (ddr_dqs_n)
    );

    ddr3_bist #(
        .TEST_WORDS(64),
        .BASE_ADDR (29'd0)
    ) u_ddr3_bist(
        .clk                 (user_clk),
        .rst_n               (user_rst_n),
        .init_done           (init_done),
        .start               (start_bist),
        .req_valid           (req_valid),
        .req_ready           (req_ready),
        .req_write           (req_write),
        .req_addr            (req_addr),
        .req_wdata           (req_wdata),
        .req_wmask           (req_wmask),
        .rsp_valid           (rsp_valid),
        .rsp_write           (rsp_write),
        .rsp_rdata           (rsp_rdata),
        .rsp_error           (rsp_error),
        .busy                (bist_busy),
        .done                (bist_done),
        .pass                (bist_pass),
        .error_count         (bist_error_count),
        .debug_word_index    (debug_word_index),
        .first_error_addr    (first_error_addr),
        .first_error_expected(first_error_expected),
        .first_error_actual  (first_error_actual)
    );

    // BIST 运行在 DDR 用户时钟域。完成状态保持不变，供 50 MHz 域同步读取。
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            start_bist    <= 1'b0;
            bist_started  <= 1'b0;
            test_finished <= 1'b0;
            test_passed   <= 1'b0;
        end else begin
            start_bist <= 1'b0;

            if (init_done && !bist_started) begin
                start_bist   <= 1'b1;
                bist_started <= 1'b1;
            end

            if (bist_done) begin
                test_finished <= 1'b1;
                test_passed   <= bist_pass;
            end
        end
    end

    // NEO Dock 的 V13 是 USR_CLK_IN，不是状态 LED。
    // 使用板载 USB 串口 TX（U15）输出初始化和 BIST 结果。
    ddr3_status_uart #(
        .CLK_HZ   (50000000),
        .BAUD_RATE(115200)
    ) u_status_uart(
        .clk                (sys_clk),
        .rst_n              (rst_n),
        .init_done_async    (init_done),
        .test_finished_async(test_finished),
        .test_passed_async  (test_passed),
        .uart_tx            (uart_tx)
    );

endmodule
