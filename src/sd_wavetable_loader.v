// 把SD文件读取器输出的WTB1字节流打包为256位数据并写入DDR3。
// 文件头在50 MHz域解析，负载通过异步FIFO送到DDR用户时钟域。
module sd_wavetable_loader(
    input  wire         sd_clk,
    input  wire         sd_rst_n,
    input  wire         file_byte_valid,
    input  wire [7:0]   file_byte,
    input  wire         file_done,

    input  wire         ddr_clk,
    input  wire         ddr_rst_n,
    output reg          req_valid,
    input  wire         req_ready,
    output wire         req_write,
    output wire [28:0]  req_addr,
    output reg  [255:0] req_wdata,
    output wire [31:0]  req_wmask,
    input  wire         rsp_valid,
    input  wire         rsp_write,
    input  wire         rsp_error,

    output reg          storage_ready,
    output reg          load_error,
    output wire [4:0]   table_count,
    output reg  [16:0]  words_written
);

    localparam [2:0] LOAD_WAIT_HEADER = 3'd0;
    localparam [2:0] LOAD_POP        = 3'd1;
    localparam [2:0] LOAD_WAIT_DATA  = 3'd2;
    localparam [2:0] LOAD_ISSUE      = 3'd3;
    localparam [2:0] LOAD_WAIT_RSP   = 3'd4;
    localparam [2:0] LOAD_DONE       = 3'd5;
    localparam [2:0] LOAD_ERROR      = 3'd6;

    reg [31:0] file_byte_index;
    reg [24:0] payload_byte_count;
    reg [4:0]  table_count_sd;
    reg        header_error_sd;
    reg        header_complete_sd;
    reg        stream_done_sd;
    reg        file_done_d;
    reg [4:0]  pack_index;
    reg [255:0] pack_word;
    reg         fifo_wr_en;
    reg [255:0] fifo_wr_data;
    wire        fifo_wr_full;

    reg [4:0] table_count_sync_1;
    reg [4:0] table_count_sync_2;
    reg header_complete_sync_1;
    reg header_complete_sync_2;
    reg header_error_sync_1;
    reg header_error_sync_2;
    reg stream_done_sync_1;
    reg stream_done_sync_2;

    reg fifo_rd_en;
    wire [255:0] fifo_rd_data;
    wire fifo_rd_valid;
    wire fifo_rd_empty;
    reg [2:0] load_state;

    wire [16:0] expected_words = {table_count_sync_2, 12'd0};
    wire [24:0] expected_payload_bytes_sd = {table_count_sd, 17'd0};

    assign table_count = table_count_sync_2;
    assign req_write = 1'b1;
    assign req_addr = {words_written, 3'b000};
    assign req_wmask = 32'd0;

    async_fifo #(
        .DATA_WIDTH(256),
        .ADDR_WIDTH(3)
    ) u_payload_fifo (
        .wr_clk  (sd_clk),
        .wr_rst_n(sd_rst_n),
        .wr_en   (fifo_wr_en),
        .wr_data (fifo_wr_data),
        .wr_full (fifo_wr_full),
        .rd_clk  (ddr_clk),
        .rd_rst_n(ddr_rst_n),
        .rd_en   (fifo_rd_en),
        .rd_data (fifo_rd_data),
        .rd_valid(fifo_rd_valid),
        .rd_empty(fifo_rd_empty)
    );

    // WTB1头固定32字节：
    // 0..3="WTB1"，4=版本1，5=波表数，6..7=256帧，
    // 8..9=每帧256采样，10=16 bit，11=小端标志1。
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if (!sd_rst_n) begin
            file_byte_index <= 32'd0;
            payload_byte_count <= 25'd0;
            table_count_sd <= 5'd0;
            header_error_sd <= 1'b0;
            header_complete_sd <= 1'b0;
            stream_done_sd <= 1'b0;
            file_done_d <= 1'b0;
            pack_index <= 5'd0;
            pack_word <= 256'd0;
            fifo_wr_en <= 1'b0;
            fifo_wr_data <= 256'd0;
        end else begin
            fifo_wr_en <= 1'b0;
            file_done_d <= file_done;

            if (file_byte_valid) begin
                file_byte_index <= file_byte_index + 32'd1;
                if (file_byte_index < 32'd32) begin
                    case (file_byte_index[4:0])
                        5'd0:  if (file_byte != 8'h57) header_error_sd <= 1'b1;
                        5'd1:  if (file_byte != 8'h54) header_error_sd <= 1'b1;
                        5'd2:  if (file_byte != 8'h42) header_error_sd <= 1'b1;
                        5'd3:  if (file_byte != 8'h31) header_error_sd <= 1'b1;
                        5'd4:  if (file_byte != 8'd1)  header_error_sd <= 1'b1;
                        5'd5: begin
                            if ((file_byte == 8'd0) || (file_byte > 8'd16))
                                header_error_sd <= 1'b1;
                            table_count_sd <= file_byte[4:0];
                        end
                        5'd6:  if (file_byte != 8'h00) header_error_sd <= 1'b1;
                        5'd7:  if (file_byte != 8'h01) header_error_sd <= 1'b1;
                        5'd8:  if (file_byte != 8'h00) header_error_sd <= 1'b1;
                        5'd9:  if (file_byte != 8'h01) header_error_sd <= 1'b1;
                        5'd10: if (file_byte != 8'd16) header_error_sd <= 1'b1;
                        5'd11: if (file_byte != 8'd1)  header_error_sd <= 1'b1;
                        default: begin
                        end
                    endcase
                    if (file_byte_index == 32'd31)
                        header_complete_sd <= 1'b1;
                end else begin
                    payload_byte_count <= payload_byte_count + 25'd1;
                    if (pack_index == 5'd31) begin
                        if (fifo_wr_full) begin
                            header_error_sd <= 1'b1;
                        end else begin
                            fifo_wr_data <= {file_byte, pack_word[247:0]};
                            fifo_wr_en <= 1'b1;
                        end
                        pack_index <= 5'd0;
                    end else begin
                        pack_word[pack_index*8 +: 8] <= file_byte;
                        pack_index <= pack_index + 5'd1;
                    end
                end
            end

            if (file_done && !file_done_d) begin
                stream_done_sd <= 1'b1;
                if (!header_complete_sd
                    || (pack_index != 5'd0)
                    || (payload_byte_count != expected_payload_bytes_sd))
                    header_error_sd <= 1'b1;
            end
        end
    end

    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            table_count_sync_1 <= 5'd0;
            table_count_sync_2 <= 5'd0;
            header_complete_sync_1 <= 1'b0;
            header_complete_sync_2 <= 1'b0;
            header_error_sync_1 <= 1'b0;
            header_error_sync_2 <= 1'b0;
            stream_done_sync_1 <= 1'b0;
            stream_done_sync_2 <= 1'b0;
            fifo_rd_en <= 1'b0;
            req_valid <= 1'b0;
            req_wdata <= 256'd0;
            storage_ready <= 1'b0;
            load_error <= 1'b0;
            words_written <= 17'd0;
            load_state <= LOAD_WAIT_HEADER;
        end else begin
            table_count_sync_1 <= table_count_sd;
            table_count_sync_2 <= table_count_sync_1;
            header_complete_sync_1 <= header_complete_sd;
            header_complete_sync_2 <= header_complete_sync_1;
            header_error_sync_1 <= header_error_sd;
            header_error_sync_2 <= header_error_sync_1;
            stream_done_sync_1 <= stream_done_sd;
            stream_done_sync_2 <= stream_done_sync_1;
            fifo_rd_en <= 1'b0;

            if (header_error_sync_2 || (rsp_valid && rsp_error)) begin
                req_valid <= 1'b0;
                load_error <= 1'b1;
                load_state <= LOAD_ERROR;
            end else begin
                case (load_state)
                    LOAD_WAIT_HEADER: begin
                        if (header_complete_sync_2)
                            load_state <= LOAD_POP;
                    end
                    LOAD_POP: begin
                        if (!fifo_rd_empty) begin
                            fifo_rd_en <= 1'b1;
                            load_state <= LOAD_WAIT_DATA;
                        end else if (stream_done_sync_2
                                     && (words_written != expected_words)) begin
                            load_error <= 1'b1;
                            load_state <= LOAD_ERROR;
                        end
                    end
                    LOAD_WAIT_DATA: begin
                        if (fifo_rd_valid) begin
                            req_wdata <= fifo_rd_data;
                            req_valid <= 1'b1;
                            load_state <= LOAD_ISSUE;
                        end
                    end
                    LOAD_ISSUE: begin
                        if (req_valid && req_ready) begin
                            req_valid <= 1'b0;
                            load_state <= LOAD_WAIT_RSP;
                        end
                    end
                    LOAD_WAIT_RSP: begin
                        if (rsp_valid) begin
                            if (!rsp_write) begin
                                load_error <= 1'b1;
                                load_state <= LOAD_ERROR;
                            end else begin
                                words_written <= words_written + 17'd1;
                                if ((words_written + 17'd1) == expected_words) begin
                                    storage_ready <= 1'b1;
                                    load_state <= LOAD_DONE;
                                end else begin
                                    load_state <= LOAD_POP;
                                end
                            end
                        end
                    end
                    LOAD_DONE: begin
                        storage_ready <= 1'b1;
                    end
                    default: begin
                        req_valid <= 1'b0;
                        load_error <= 1'b1;
                        load_state <= LOAD_ERROR;
                    end
                endcase
            end
        end
    end

endmodule
