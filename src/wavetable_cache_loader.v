// 从DDR中读取当前波表位置相邻的两帧，并装入振荡器本地双缓冲。
// DDR布局：每张表256帧，每帧256个16位小端采样，共128 KiB。
module wavetable_cache_loader(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         storage_ready,
    input  wire [4:0]   table_count,
    input  wire [3:0]   desired_table,
    input  wire [6:0]   desired_position,

    output reg          req_valid,
    input  wire         req_ready,
    output wire         req_write,
    output reg  [28:0]  req_addr,
    output wire [255:0] req_wdata,
    output wire [31:0]  req_wmask,
    input  wire         rsp_valid,
    input  wire         rsp_write,
    input  wire [255:0] rsp_rdata,
    input  wire         rsp_error,

    output reg          cache_write_enable,
    output reg          cache_write_bank,
    output reg          cache_write_frame,
    output reg  [7:0]   cache_write_address,
    output reg  [15:0]  cache_write_data,
    output reg          cache_commit_toggle,
    output reg          cache_commit_bank,
    output reg  [7:0]   cache_commit_fraction,
    output reg          cache_ready,
    output reg          cache_load_error
);

    localparam [2:0] CACHE_IDLE      = 3'd0;
    localparam [2:0] CACHE_ISSUE     = 3'd1;
    localparam [2:0] CACHE_WAIT_RSP  = 3'd2;
    localparam [2:0] CACHE_WRITE     = 3'd3;
    localparam [2:0] CACHE_ERROR     = 3'd4;

    reg [2:0] state;
    reg [5:0] block_index;
    reg [3:0] sample_index;
    reg [255:0] read_block;
    reg fetch_bank;
    reg [3:0] fetch_table;
    reg [7:0] fetch_frame_0;
    reg [7:0] fetch_frame_1;
    reg [7:0] fetch_fraction;
    reg [3:0] loaded_table;
    reg [7:0] loaded_frame_0;
    reg [7:0] loaded_fraction;

    wire [15:0] position_product = desired_position * 10'd514;
    wire [7:0] desired_frame_0 = desired_position == 7'd127
                               ? 8'd255 : position_product[15:8];
    wire [7:0] desired_fraction = desired_position == 7'd127
                                ? 8'd0 : position_product[7:0];
    wire [7:0] desired_frame_1 = desired_frame_0 == 8'd255
                               ? 8'd255 : desired_frame_0 + 8'd1;
    wire [3:0] clamped_table = (table_count == 5'd0)
                             ? 4'd0
                             : ({1'b0, desired_table} >= table_count)
                               ? table_count[3:0] - 4'd1
                               : desired_table;
    wire [7:0] selected_fetch_frame = block_index[4]
                                     ? fetch_frame_1 : fetch_frame_0;

    assign req_write = 1'b0;
    assign req_wdata = 256'd0;
    assign req_wmask = 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= CACHE_IDLE;
            block_index <= 6'd0;
            sample_index <= 4'd0;
            read_block <= 256'd0;
            fetch_bank <= 1'b1;
            fetch_table <= 4'd0;
            fetch_frame_0 <= 8'd0;
            fetch_frame_1 <= 8'd1;
            fetch_fraction <= 8'd0;
            loaded_table <= 4'd0;
            loaded_frame_0 <= 8'd0;
            loaded_fraction <= 8'd0;
            req_valid <= 1'b0;
            req_addr <= 29'd0;
            cache_write_enable <= 1'b0;
            cache_write_bank <= 1'b0;
            cache_write_frame <= 1'b0;
            cache_write_address <= 8'd0;
            cache_write_data <= 16'd0;
            cache_commit_toggle <= 1'b0;
            cache_commit_bank <= 1'b0;
            cache_commit_fraction <= 8'd0;
            cache_ready <= 1'b0;
            cache_load_error <= 1'b0;
        end else begin
            cache_write_enable <= 1'b0;

            case (state)
                CACHE_IDLE: begin
                    req_valid <= 1'b0;
                    if (storage_ready && (table_count != 5'd0)) begin
                        if (!cache_ready
                            || (clamped_table != loaded_table)
                            || (desired_frame_0 != loaded_frame_0)) begin
                            fetch_bank <= ~cache_commit_bank;
                            fetch_table <= clamped_table;
                            fetch_frame_0 <= desired_frame_0;
                            fetch_frame_1 <= desired_frame_1;
                            fetch_fraction <= desired_fraction;
                            block_index <= 6'd0;
                            state <= CACHE_ISSUE;
                        end else if (desired_fraction != loaded_fraction) begin
                            loaded_fraction <= desired_fraction;
                            cache_commit_fraction <= desired_fraction;
                            cache_commit_toggle <= ~cache_commit_toggle;
                        end
                    end
                end

                CACHE_ISSUE: begin
                    // table*32768 + frame*128 + block*8，均为DDR用户地址。
                    // 一帧含16个32字节事务，每个事务地址递增8，所以帧跨度为128。
                    req_addr <= {fetch_table, 15'd0}
                              + {selected_fetch_frame, 7'd0}
                              + {22'd0, block_index[3:0], 3'd0};
                    req_valid <= 1'b1;
                    if (req_valid && req_ready) begin
                        req_valid <= 1'b0;
                        state <= CACHE_WAIT_RSP;
                    end
                end

                CACHE_WAIT_RSP: begin
                    if (rsp_valid) begin
                        if (rsp_error || rsp_write) begin
                            cache_load_error <= 1'b1;
                            state <= CACHE_ERROR;
                        end else begin
                            read_block <= rsp_rdata;
                            sample_index <= 4'd0;
                            state <= CACHE_WRITE;
                        end
                    end
                end

                CACHE_WRITE: begin
                    cache_write_enable <= 1'b1;
                    cache_write_bank <= fetch_bank;
                    cache_write_frame <= block_index[4];
                    cache_write_address <= {block_index[3:0], sample_index};
                    cache_write_data <= read_block[sample_index*16 +: 16];

                    if (sample_index == 4'd15) begin
                        if (block_index == 6'd31) begin
                            cache_commit_bank <= fetch_bank;
                            cache_commit_fraction <= fetch_fraction;
                            cache_commit_toggle <= ~cache_commit_toggle;
                            cache_ready <= 1'b1;
                            loaded_table <= fetch_table;
                            loaded_frame_0 <= fetch_frame_0;
                            loaded_fraction <= fetch_fraction;
                            state <= CACHE_IDLE;
                        end else begin
                            block_index <= block_index + 6'd1;
                            state <= CACHE_ISSUE;
                        end
                    end else begin
                        sample_index <= sample_index + 4'd1;
                    end
                end

                default: begin
                    req_valid <= 1'b0;
                    cache_load_error <= 1'b1;
                    state <= CACHE_ERROR;
                end
            endcase
        end
    end

endmodule
