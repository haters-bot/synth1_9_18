// 将业务侧的单事务ready/valid接口转换为Gowin DDR3控制器用户接口。
//
// 约束：
// 1. 一次只允许一个未完成事务，便于第一阶段板级验证。
// 2. 写命令和写数据分别握手；二者不要求在同一拍被控制器接收。
// 3. 当前配置为1:4时钟比、BL8、256位用户数据，一次事务传输32字节。
module ddr3_user_port_adapter #(
    parameter integer ADDR_WIDTH = 29,
    parameter integer DATA_WIDTH = 256,
    parameter integer MASK_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  init_done,

    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_write,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [MASK_WIDTH-1:0] req_wmask,

    output reg                   rsp_valid,
    output reg                   rsp_write,
    output reg  [DATA_WIDTH-1:0] rsp_rdata,
    output reg                   rsp_error,

    input  wire                  mc_cmd_ready,
    output wire [2:0]            mc_cmd,
    output wire                  mc_cmd_en,
    output wire [ADDR_WIDTH-1:0] mc_addr,

    input  wire                  mc_wr_data_rdy,
    output wire [DATA_WIDTH-1:0] mc_wr_data,
    output wire                  mc_wr_data_en,
    output wire                  mc_wr_data_end,
    output wire [MASK_WIDTH-1:0] mc_wr_data_mask,

    input  wire [DATA_WIDTH-1:0] mc_rd_data,
    input  wire                  mc_rd_data_valid,
    input  wire                  mc_rd_data_end
);

    reg                  busy;
    reg                  request_is_write;
    reg                  command_pending;
    reg                  write_data_pending;
    reg [ADDR_WIDTH-1:0] address_latched;
    reg [DATA_WIDTH-1:0] write_data_latched;
    reg [MASK_WIDTH-1:0] write_mask_latched;

    wire accept_request = req_valid && req_ready;
    wire accept_command = command_pending && mc_cmd_ready;
    wire accept_write_data = write_data_pending && mc_wr_data_rdy;

    assign req_ready = init_done && !busy;

    assign mc_cmd    = request_is_write ? 3'b000 : 3'b001;
    assign mc_cmd_en = command_pending;
    assign mc_addr   = address_latched;

    assign mc_wr_data      = write_data_latched;
    assign mc_wr_data_mask = write_mask_latched;
    assign mc_wr_data_en   = write_data_pending;
    assign mc_wr_data_end  = write_data_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy               <= 1'b0;
            request_is_write   <= 1'b0;
            command_pending    <= 1'b0;
            write_data_pending <= 1'b0;
            address_latched    <= {ADDR_WIDTH{1'b0}};
            write_data_latched <= {DATA_WIDTH{1'b0}};
            write_mask_latched <= {MASK_WIDTH{1'b0}};
            rsp_valid          <= 1'b0;
            rsp_write          <= 1'b0;
            rsp_rdata          <= {DATA_WIDTH{1'b0}};
            rsp_error          <= 1'b0;
        end else begin
            rsp_valid <= 1'b0;
            rsp_error <= 1'b0;

            // Sample payload on every idle edge, including acceptance, then
            // hold it throughout the transaction. Keep the wide load enable
            // off accept_request: ready/valid must not drive all 317 payload
            // registers as well as both FSMs. Idle samples without req_valid
            // are never exposed as commands.
            if (!busy) begin
                address_latched    <= req_addr;
                write_data_latched <= req_wdata;
                write_mask_latched <= req_wmask;
            end

            if (accept_request) begin
                busy               <= 1'b1;
                request_is_write   <= req_write;
                command_pending    <= 1'b1;
                write_data_pending <= req_write;
            end else begin
                if (accept_command)
                    command_pending <= 1'b0;

                if (accept_write_data)
                    write_data_pending <= 1'b0;

                // 写命令和写数据可以在不同周期完成握手。
                if (busy && request_is_write
                        && (!command_pending || accept_command)
                        && (!write_data_pending || accept_write_data)) begin
                    busy      <= 1'b0;
                    rsp_valid <= 1'b1;
                    rsp_write <= 1'b1;
                end

                // 当前只允许一个未完成读事务，因此返回数据必然属于当前请求。
                if (busy && !request_is_write && mc_rd_data_valid) begin
                    busy      <= 1'b0;
                    rsp_valid <= 1'b1;
                    rsp_write <= 1'b0;
                    rsp_rdata <= mc_rd_data;
                    rsp_error <= !mc_rd_data_end;
                end
            end
        end
    end

endmodule
