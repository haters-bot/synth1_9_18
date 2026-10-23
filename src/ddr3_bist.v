// DDR3小范围写入/读回自检。
// 每个测试事务对应一个BL8访问，地址必须按8递增。
module ddr3_bist #(
    parameter integer ADDR_WIDTH = 29,
    parameter integer DATA_WIDTH = 256,
    parameter integer MASK_WIDTH = DATA_WIDTH / 8,
    parameter integer TEST_WORDS = 64,
    parameter [ADDR_WIDTH-1:0] BASE_ADDR = {ADDR_WIDTH{1'b0}}
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  init_done,
    input  wire                  start,

    output reg                   req_valid,
    input  wire                  req_ready,
    output reg                   req_write,
    output reg  [ADDR_WIDTH-1:0] req_addr,
    output reg  [DATA_WIDTH-1:0] req_wdata,
    output wire [MASK_WIDTH-1:0] req_wmask,

    input  wire                  rsp_valid,
    input  wire                  rsp_write,
    input  wire [DATA_WIDTH-1:0] rsp_rdata,
    input  wire                  rsp_error,

    output reg                   busy,
    output reg                   done,
    output reg                   pass,
    output reg  [15:0]           error_count,
    output reg  [15:0]           debug_word_index,
    output reg  [ADDR_WIDTH-1:0] first_error_addr,
    output reg  [DATA_WIDTH-1:0] first_error_expected,
    output reg  [DATA_WIDTH-1:0] first_error_actual
);

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_WRITE_REQ  = 3'd1;
    localparam [2:0] STATE_WRITE_WAIT = 3'd2;
    localparam [2:0] STATE_READ_REQ   = 3'd3;
    localparam [2:0] STATE_READ_WAIT  = 3'd4;
    localparam [2:0] STATE_FINISH     = 3'd5;

    reg [2:0] state;
    reg [15:0] word_index;
    reg any_error;

    function [DATA_WIDTH-1:0] make_test_pattern;
        input [15:0] index;
        integer lane;
        reg [15:0] lane_value;
        begin
            make_test_pattern = {DATA_WIDTH{1'b0}};
            for (lane = 0; lane < DATA_WIDTH / 16; lane = lane + 1) begin
                lane_value = 16'hA500 ^ index ^ (lane * 16'h0111);
                make_test_pattern[lane*16 +: 16] = lane_value;
            end
        end
    endfunction

    assign req_wmask = {MASK_WIDTH{1'b0}};

    always @(*) begin
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr  = BASE_ADDR + (word_index << 3);
        req_wdata = make_test_pattern(word_index);

        case (state)
            STATE_WRITE_REQ: begin
                req_valid = 1'b1;
                req_write = 1'b1;
            end

            STATE_READ_REQ: begin
                req_valid = 1'b1;
                req_write = 1'b0;
            end

            default: begin
                req_valid = 1'b0;
                req_write = 1'b0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= STATE_IDLE;
            word_index           <= 16'd0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            pass                 <= 1'b0;
            any_error            <= 1'b0;
            error_count          <= 16'd0;
            debug_word_index     <= 16'd0;
            first_error_addr     <= {ADDR_WIDTH{1'b0}};
            first_error_expected <= {DATA_WIDTH{1'b0}};
            first_error_actual   <= {DATA_WIDTH{1'b0}};
        end else begin
            done             <= 1'b0;
            debug_word_index <= word_index;

            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;
                    if (start && init_done) begin
                        state                <= STATE_WRITE_REQ;
                        word_index           <= 16'd0;
                        busy                 <= 1'b1;
                        pass                 <= 1'b0;
                        any_error            <= 1'b0;
                        error_count          <= 16'd0;
                        first_error_addr     <= {ADDR_WIDTH{1'b0}};
                        first_error_expected <= {DATA_WIDTH{1'b0}};
                        first_error_actual   <= {DATA_WIDTH{1'b0}};
                    end
                end

                STATE_WRITE_REQ: begin
                    if (req_valid && req_ready)
                        state <= STATE_WRITE_WAIT;
                end

                STATE_WRITE_WAIT: begin
                    if (rsp_valid) begin
                        if (!rsp_write || rsp_error) begin
                            any_error   <= 1'b1;
                            error_count <= error_count + 16'd1;
                        end

                        if (word_index == TEST_WORDS - 1) begin
                            word_index <= 16'd0;
                            state      <= STATE_READ_REQ;
                        end else begin
                            word_index <= word_index + 16'd1;
                            state      <= STATE_WRITE_REQ;
                        end
                    end
                end

                STATE_READ_REQ: begin
                    if (req_valid && req_ready)
                        state <= STATE_READ_WAIT;
                end

                STATE_READ_WAIT: begin
                    if (rsp_valid) begin
                        if (rsp_write || rsp_error
                                || (rsp_rdata != make_test_pattern(word_index))) begin
                            any_error   <= 1'b1;
                            error_count <= error_count + 16'd1;

                            if (!any_error) begin
                                first_error_addr     <= BASE_ADDR + (word_index << 3);
                                first_error_expected <= make_test_pattern(word_index);
                                first_error_actual   <= rsp_rdata;
                            end
                        end

                        if (word_index == TEST_WORDS - 1) begin
                            state <= STATE_FINISH;
                        end else begin
                            word_index <= word_index + 16'd1;
                            state      <= STATE_READ_REQ;
                        end
                    end
                end

                STATE_FINISH: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    pass <= !any_error;
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
