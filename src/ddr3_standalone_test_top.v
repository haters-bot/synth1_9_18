// 独立DDR3板级验证顶层，不接入现有音频顶层。
// 上电校准完成后自动测试64个256位数据块，共2 KiB。
module ddr3_standalone_test_top(
    input  wire        sys_clk,
    input  wire        rst_n,
    output wire        ddr_status_led_n,

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
    reg [23:0] status_counter;

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

    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            start_bist    <= 1'b0;
            bist_started  <= 1'b0;
            test_finished <= 1'b0;
            test_passed   <= 1'b0;
            status_counter <= 24'd0;
        end else begin
            start_bist     <= 1'b0;
            status_counter <= status_counter + 24'd1;

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

    // LED低有效：初始化时熄灭，测试时慢闪，通过后常亮，失败后快闪。
    assign ddr_status_led_n = !init_done     ? 1'b1 :
                              !test_finished ? status_counter[22] :
                              test_passed    ? 1'b0 : status_counter[20];

endmodule
