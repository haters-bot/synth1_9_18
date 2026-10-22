// 三主机、单未完成事务的DDR请求仲裁器。
// 轮询顺序避免两个波表缓存持续重载时饿死SD装载器。
module ddr3_transaction_arbiter(
    input  wire         clk,
    input  wire         rst_n,

    input  wire         m0_req_valid,
    output wire         m0_req_ready,
    input  wire         m0_req_write,
    input  wire [28:0]  m0_req_addr,
    input  wire [255:0] m0_req_wdata,
    input  wire [31:0]  m0_req_wmask,
    output wire         m0_rsp_valid,
    output wire         m0_rsp_write,
    output wire [255:0] m0_rsp_rdata,
    output wire         m0_rsp_error,

    input  wire         m1_req_valid,
    output wire         m1_req_ready,
    input  wire         m1_req_write,
    input  wire [28:0]  m1_req_addr,
    input  wire [255:0] m1_req_wdata,
    input  wire [31:0]  m1_req_wmask,
    output wire         m1_rsp_valid,
    output wire         m1_rsp_write,
    output wire [255:0] m1_rsp_rdata,
    output wire         m1_rsp_error,

    input  wire         m2_req_valid,
    output wire         m2_req_ready,
    input  wire         m2_req_write,
    input  wire [28:0]  m2_req_addr,
    input  wire [255:0] m2_req_wdata,
    input  wire [31:0]  m2_req_wmask,
    output wire         m2_rsp_valid,
    output wire         m2_rsp_write,
    output wire [255:0] m2_rsp_rdata,
    output wire         m2_rsp_error,

    output wire         ddr_req_valid,
    input  wire         ddr_req_ready,
    output wire         ddr_req_write,
    output wire [28:0]  ddr_req_addr,
    output wire [255:0] ddr_req_wdata,
    output wire [31:0]  ddr_req_wmask,
    input  wire         ddr_rsp_valid,
    input  wire         ddr_rsp_write,
    input  wire [255:0] ddr_rsp_rdata,
    input  wire         ddr_rsp_error
);

    reg busy;
    reg [1:0] owner;
    reg [1:0] next_priority;
    reg [1:0] selected_owner;
    reg selected_valid;

    always @(*) begin
        selected_owner = 2'd0;
        selected_valid = 1'b0;
        case (next_priority)
            2'd0: begin
                if (m0_req_valid) begin selected_owner=2'd0; selected_valid=1'b1; end
                else if (m1_req_valid) begin selected_owner=2'd1; selected_valid=1'b1; end
                else if (m2_req_valid) begin selected_owner=2'd2; selected_valid=1'b1; end
            end
            2'd1: begin
                if (m1_req_valid) begin selected_owner=2'd1; selected_valid=1'b1; end
                else if (m2_req_valid) begin selected_owner=2'd2; selected_valid=1'b1; end
                else if (m0_req_valid) begin selected_owner=2'd0; selected_valid=1'b1; end
            end
            default: begin
                if (m2_req_valid) begin selected_owner=2'd2; selected_valid=1'b1; end
                else if (m0_req_valid) begin selected_owner=2'd0; selected_valid=1'b1; end
                else if (m1_req_valid) begin selected_owner=2'd1; selected_valid=1'b1; end
            end
        endcase
    end

    assign ddr_req_valid = !busy && selected_valid;
    assign ddr_req_write = selected_owner == 2'd0 ? m0_req_write
                         : selected_owner == 2'd1 ? m1_req_write
                         : m2_req_write;
    assign ddr_req_addr = selected_owner == 2'd0 ? m0_req_addr
                        : selected_owner == 2'd1 ? m1_req_addr
                        : m2_req_addr;
    assign ddr_req_wdata = selected_owner == 2'd0 ? m0_req_wdata
                         : selected_owner == 2'd1 ? m1_req_wdata
                         : m2_req_wdata;
    assign ddr_req_wmask = selected_owner == 2'd0 ? m0_req_wmask
                         : selected_owner == 2'd1 ? m1_req_wmask
                         : m2_req_wmask;

    assign m0_req_ready = !busy && selected_valid
                        && (selected_owner == 2'd0) && ddr_req_ready;
    assign m1_req_ready = !busy && selected_valid
                        && (selected_owner == 2'd1) && ddr_req_ready;
    assign m2_req_ready = !busy && selected_valid
                        && (selected_owner == 2'd2) && ddr_req_ready;

    assign m0_rsp_valid = ddr_rsp_valid && (owner == 2'd0);
    assign m1_rsp_valid = ddr_rsp_valid && (owner == 2'd1);
    assign m2_rsp_valid = ddr_rsp_valid && (owner == 2'd2);
    assign m0_rsp_write = ddr_rsp_write;
    assign m1_rsp_write = ddr_rsp_write;
    assign m2_rsp_write = ddr_rsp_write;
    assign m0_rsp_rdata = ddr_rsp_rdata;
    assign m1_rsp_rdata = ddr_rsp_rdata;
    assign m2_rsp_rdata = ddr_rsp_rdata;
    assign m0_rsp_error = ddr_rsp_error;
    assign m1_rsp_error = ddr_rsp_error;
    assign m2_rsp_error = ddr_rsp_error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            owner <= 2'd0;
            next_priority <= 2'd0;
        end else begin
            if (!busy && ddr_req_valid && ddr_req_ready) begin
                busy <= 1'b1;
                owner <= selected_owner;
            end
            if (busy && ddr_rsp_valid) begin
                busy <= 1'b0;
                next_priority <= owner == 2'd2 ? 2'd0 : owner + 2'd1;
            end
        end
    end

endmodule
