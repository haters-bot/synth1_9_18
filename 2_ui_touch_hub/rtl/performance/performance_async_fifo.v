// Small dual-clock ready/valid FIFO. Assert reset for BOTH domains together;
// each domain releases its local reset synchronously. The output register is
// an extra elastic slot beyond the 2**ADDR_BITS RAM entries.
module performance_async_fifo #(
    parameter integer WIDTH=323,
    parameter integer ADDR_BITS=3
)(
    input wire wr_clk, wr_rst_n, wr_valid,
    output wire wr_ready,
    input wire [WIDTH-1:0] wr_data,
    input wire rd_clk, rd_rst_n,
    output reg rd_valid,
    input wire rd_ready,
    output reg [WIDTH-1:0] rd_data
);
    localparam integer DEPTH=1<<ADDR_BITS;
    (* syn_ramstyle="block_ram", ram_style="block" *)
    reg [WIDTH-1:0] ram[0:DEPTH-1];
    reg [ADDR_BITS:0] wr_bin,wr_gray,rd_bin,rd_gray;
    (* ASYNC_REG="TRUE" *) reg [ADDR_BITS:0] rd_gray_meta,rd_gray_sync,wr_gray_meta,wr_gray_sync;
    reg full;
    wire push=wr_valid && wr_ready;
    wire empty=rd_gray==wr_gray_sync;
    wire prefetch=(!rd_valid || rd_ready) && !empty;
    wire [ADDR_BITS:0] next_wr_bin=wr_bin+push;
    wire [ADDR_BITS:0] next_wr_gray=(next_wr_bin>>1)^next_wr_bin;
    wire [ADDR_BITS:0] next_rd_bin=rd_bin+prefetch;
    assign wr_ready=!full;

    // No reset on either RAM port or data register: synchronous BSRAM template.
    always @(posedge wr_clk)if(push)ram[wr_bin[ADDR_BITS-1:0]]<=wr_data;
    always @(posedge rd_clk)if(prefetch)rd_data<=ram[rd_bin[ADDR_BITS-1:0]];
    always @(posedge wr_clk or negedge wr_rst_n)begin
        if(!wr_rst_n)begin
            wr_bin<=0;wr_gray<=0;full<=0;rd_gray_meta<=0;rd_gray_sync<=0;
        end else begin
            rd_gray_meta<=rd_gray;rd_gray_sync<=rd_gray_meta;
            wr_bin<=next_wr_bin;wr_gray<=next_wr_gray;
            full<=next_wr_gray=={~rd_gray_sync[ADDR_BITS:ADDR_BITS-1],rd_gray_sync[ADDR_BITS-2:0]};
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n)begin
        if(!rd_rst_n)begin
            rd_bin<=0;rd_gray<=0;rd_valid<=0;wr_gray_meta<=0;wr_gray_sync<=0;
        end else begin
            wr_gray_meta<=wr_gray;wr_gray_sync<=wr_gray_meta;
            rd_bin<=next_rd_bin;rd_gray<=(next_rd_bin>>1)^next_rd_bin;
            if(!rd_valid || rd_ready)rd_valid<=!empty;
        end
    end
    // synthesis translate_off
    initial if(ADDR_BITS<2)$fatal(1,"performance_async_fifo requires ADDR_BITS>=2");
    // synthesis translate_on
endmodule
