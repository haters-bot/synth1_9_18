`timescale 1ns/1ps

module tb_ddr3_bist;

    localparam integer TEST_WORDS = 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg init_done = 1'b0;
    reg start = 1'b0;
    reg corrupt_read = 1'b0;

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

    reg          mc_cmd_ready = 1'b0;
    wire [2:0]   mc_cmd;
    wire         mc_cmd_en;
    wire [28:0]  mc_addr;
    reg          mc_wr_data_rdy = 1'b0;
    wire [255:0] mc_wr_data;
    wire         mc_wr_data_en;
    wire         mc_wr_data_end;
    wire [31:0]  mc_wr_data_mask;
    reg  [255:0] mc_rd_data = 256'd0;
    reg          mc_rd_data_valid = 1'b0;
    reg          mc_rd_data_end = 1'b0;

    wire         bist_busy;
    wire         bist_done;
    wire         bist_pass;
    wire [15:0]  error_count;
    wire [15:0]  debug_word_index;
    wire [28:0]  first_error_addr;
    wire [255:0] first_error_expected;
    wire [255:0] first_error_actual;

    reg [255:0] memory [0:TEST_WORDS-1];
    reg [7:0] cycle_count;
    reg write_command_pending;
    reg write_data_pending;
    reg [28:0] write_address_latched;
    reg [255:0] write_data_latched;
    reg [28:0] read_address_latched;
    reg [2:0] read_delay;
    integer i;

    wire command_handshake = mc_cmd_en && mc_cmd_ready;
    wire write_command_handshake = command_handshake && (mc_cmd == 3'b000);
    wire read_command_handshake = command_handshake && (mc_cmd == 3'b001);
    wire write_data_handshake = mc_wr_data_en && mc_wr_data_rdy;

    always #5 clk = ~clk;

    ddr3_user_port_adapter u_adapter(
        .clk             (clk),
        .rst_n           (rst_n),
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

    ddr3_bist #(
        .TEST_WORDS(TEST_WORDS)
    ) u_bist(
        .clk                 (clk),
        .rst_n               (rst_n),
        .init_done           (init_done),
        .start               (start),
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
        .error_count         (error_count),
        .debug_word_index    (debug_word_index),
        .first_error_addr    (first_error_addr),
        .first_error_expected(first_error_expected),
        .first_error_actual  (first_error_actual)
    );

    // 简化DDR模型：命令和写数据通道采用不同的背压节奏。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count            <= 8'd0;
            mc_cmd_ready           <= 1'b0;
            mc_wr_data_rdy         <= 1'b0;
            mc_rd_data             <= 256'd0;
            mc_rd_data_valid       <= 1'b0;
            mc_rd_data_end         <= 1'b0;
            write_command_pending  <= 1'b0;
            write_data_pending     <= 1'b0;
            write_address_latched  <= 29'd0;
            write_data_latched     <= 256'd0;
            read_address_latched   <= 29'd0;
            read_delay             <= 3'd0;
            for (i = 0; i < TEST_WORDS; i = i + 1)
                memory[i] <= 256'd0;
        end else begin
            cycle_count    <= cycle_count + 8'd1;
            mc_cmd_ready   <= (cycle_count[1:0] != 2'b01);
            mc_wr_data_rdy <= (cycle_count[2:0] == 3'b010)
                              || (cycle_count[2:0] == 3'b101);
            mc_rd_data_valid <= 1'b0;
            mc_rd_data_end   <= 1'b0;

            if (write_command_handshake) begin
                write_command_pending <= 1'b1;
                write_address_latched <= mc_addr;
            end

            if (write_data_handshake) begin
                write_data_pending <= 1'b1;
                write_data_latched <= mc_wr_data;
                if (!mc_wr_data_end || (mc_wr_data_mask != 32'd0)) begin
                    $display("FAIL: illegal write data control at %0t", $time);
                    $fatal;
                end
            end

            if ((write_command_pending || write_command_handshake)
                    && (write_data_pending || write_data_handshake)) begin
                memory[(write_command_handshake ? mc_addr
                                                : write_address_latched) >> 3]
                    <= write_data_handshake ? mc_wr_data : write_data_latched;
                write_command_pending <= 1'b0;
                write_data_pending    <= 1'b0;
            end

            if (read_command_handshake) begin
                read_address_latched <= mc_addr;
                read_delay <= 3'd3;
            end else if (read_delay != 3'd0) begin
                read_delay <= read_delay - 3'd1;
                if (read_delay == 3'd1) begin
                    mc_rd_data <= memory[read_address_latched >> 3]
                        ^ ((corrupt_read && (read_address_latched == 29'd40))
                           ? 256'd1 : 256'd0);
                    mc_rd_data_valid <= 1'b1;
                    mc_rd_data_end   <= 1'b1;
                end
            end
        end
    end

    task pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        init_done = 1'b1;

        pulse_start();
        @(posedge bist_done);
        if (!bist_pass || (error_count != 16'd0)) begin
            $display("FAIL: clean memory test did not pass");
            $fatal;
        end

        corrupt_read = 1'b1;
        pulse_start();
        @(posedge bist_done);
        if (bist_pass || (error_count != 16'd1)
                || (first_error_addr != 29'd40)) begin
            $display("FAIL: corruption was not reported correctly");
            $fatal;
        end

        $display("PASS: DDR3 adapter handles independent backpressure and BIST detects corruption");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

endmodule
