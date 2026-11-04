// Small fixed-rate UART receiver for the phone/gateway performance link.
// The input is the UI-board debug header RX (E13), not the audio-board E19.
module performance_uart_rx #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg        byte_valid,
    output reg [7:0]  byte_data,
    output reg        framing_error
);
    localparam integer CLKS_PER_BIT = (CLK_FREQ / BAUD < 2) ? 2 : CLK_FREQ / BAUD;
    localparam integer HALF_BIT     = (CLKS_PER_BIT / 2 < 1) ? 1 : CLKS_PER_BIT / 2;
    localparam integer TIMER_BITS   = (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);

    reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [TIMER_BITS-1:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift;
    localparam ST_IDLE=2'd0, ST_START=2'd1, ST_DATA=2'd2, ST_STOP=2'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta       <= 1'b1;
            rx_sync       <= 1'b1;
            state         <= ST_IDLE;
            timer         <= {TIMER_BITS{1'b0}};
            bit_index     <= 3'd0;
            shift         <= 8'd0;
            byte_valid    <= 1'b0;
            byte_data     <= 8'd0;
            framing_error <= 1'b0;
        end else begin
            rx_meta       <= uart_rx;
            rx_sync       <= rx_meta;
            byte_valid    <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!rx_sync) begin
                        timer <= HALF_BIT - 1;
                        state <= ST_START;
                    end
                end
                ST_START: begin
                    if (timer == 0) begin
                        if (!rx_sync) begin
                            timer     <= CLKS_PER_BIT - 1;
                            bit_index <= 3'd0;
                            state     <= ST_DATA;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end
                ST_DATA: begin
                    if (timer == 0) begin
                        shift[bit_index] <= rx_sync;
                        timer <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end
                ST_STOP: begin
                    if (timer == 0) begin
                        if (rx_sync) begin
                            byte_data  <= shift;
                            byte_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
