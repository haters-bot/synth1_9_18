// 小容量双时钟异步FIFO。
// 写指针和读指针使用Gray码跨时钟域，数据存储使用双口RAM形式。
module async_fifo #(
    parameter integer DATA_WIDTH = 256,
    parameter integer ADDR_WIDTH = 3
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output reg                   rd_valid,
    output wire                  rd_empty
);

    localparam integer DEPTH = 1 << ADDR_WIDTH;

    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [ADDR_WIDTH:0] wr_binary;
    reg [ADDR_WIDTH:0] wr_gray;
    reg [ADDR_WIDTH:0] rd_binary;
    reg [ADDR_WIDTH:0] rd_gray;
    reg [ADDR_WIDTH:0] rd_gray_sync_1;
    reg [ADDR_WIDTH:0] rd_gray_sync_2;
    reg [ADDR_WIDTH:0] wr_gray_sync_1;
    reg [ADDR_WIDTH:0] wr_gray_sync_2;
    reg wr_full_reg;

    wire [ADDR_WIDTH:0] wr_binary_next = wr_binary
                                           + ((wr_en && !wr_full_reg) ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_binary_next >> 1)
                                         ^ wr_binary_next;
    wire [ADDR_WIDTH:0] rd_binary_next = rd_binary
                                           + ((rd_en && !rd_empty) ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_binary_next >> 1)
                                         ^ rd_binary_next;

    wire wr_full_next = wr_gray_next
                      == {~rd_gray_sync_2[ADDR_WIDTH:ADDR_WIDTH-1],
                          rd_gray_sync_2[ADDR_WIDTH-2:0]};
    assign wr_full = wr_full_reg;
    assign rd_empty = rd_gray == wr_gray_sync_2;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_binary <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray_sync_1 <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray_sync_2 <= {(ADDR_WIDTH+1){1'b0}};
            wr_full_reg <= 1'b0;
        end else begin
            rd_gray_sync_1 <= rd_gray;
            rd_gray_sync_2 <= rd_gray_sync_1;
            wr_full_reg <= wr_full_next;
            if (wr_en && !wr_full) begin
                memory[wr_binary[ADDR_WIDTH-1:0]] <= wr_data;
                wr_binary <= wr_binary_next;
                wr_gray <= wr_gray_next;
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_binary <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray_sync_1 <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray_sync_2 <= {(ADDR_WIDTH+1){1'b0}};
            rd_data <= {DATA_WIDTH{1'b0}};
            rd_valid <= 1'b0;
        end else begin
            wr_gray_sync_1 <= wr_gray;
            wr_gray_sync_2 <= wr_gray_sync_1;
            rd_valid <= 1'b0;
            if (rd_en && !rd_empty) begin
                rd_data <= memory[rd_binary[ADDR_WIDTH-1:0]];
                rd_valid <= 1'b1;
                rd_binary <= rd_binary_next;
                rd_gray <= rd_gray_next;
            end
        end
    end

endmodule
