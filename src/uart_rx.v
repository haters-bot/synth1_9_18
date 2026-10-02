// 异步串口接收器。
// 默认参数对应板载50 MHz系统时钟和标准MIDI串口速率31250 bit/s。
module uart_rx #(
    parameter integer CLK_HZ    = 50000000,
    parameter integer BAUD_RATE = 31250
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg [7:0]  data,
    output reg        data_valid,
    output reg        framing_error
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam [1:0] STATE_IDLE  = 2'd0;
    localparam [1:0] STATE_START = 2'd1;
    localparam [1:0] STATE_DATA  = 2'd2;
    localparam [1:0] STATE_STOP  = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [15:0] clock_count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    // 外部UART输入与系统时钟异步，先使用两级触发器同步。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data          <= 8'd0;
            data_valid    <= 1'b0;
            framing_error <= 1'b0;
            state         <= STATE_IDLE;
            clock_count   <= 16'd0;
            bit_index     <= 3'd0;
            shift_reg     <= 8'd0;
        end else begin
            data_valid    <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    clock_count <= 16'd0;
                    bit_index   <= 3'd0;
                    if (!rx_sync) begin
                        clock_count <= (CLKS_PER_BIT / 2) - 1;
                        state       <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (clock_count != 0)
                        clock_count <= clock_count - 16'd1;
                    else if (!rx_sync) begin
                        clock_count <= CLKS_PER_BIT - 1;
                        state       <= STATE_DATA;
                    end else begin
                        // 起始位中点已经回到高电平，视为毛刺。
                        state <= STATE_IDLE;
                    end
                end

                STATE_DATA: begin
                    if (clock_count != 0)
                        clock_count <= clock_count - 16'd1;
                    else begin
                        shift_reg[bit_index] <= rx_sync;
                        clock_count <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7)
                            state <= STATE_STOP;
                        else
                            bit_index <= bit_index + 3'd1;
                    end
                end

                STATE_STOP: begin
                    if (clock_count != 0)
                        clock_count <= clock_count - 16'd1;
                    else begin
                        if (rx_sync) begin
                            data       <= shift_reg;
                            data_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
