// ==============================================================================
// Module: uart_touch_rx.v
// Description: Robust UART Touch Packet Receiver with Timeout Self-Healing
//              Baud Rate: 115200 8-N-1 @ 62.5MHz Pixel Clock
//              Protocol: 0x54, 0x54, X_MSB, X_LSB, Y_MSB, Y_LSB, State (7 bytes)
// Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
// ==============================================================================

module uart_touch_rx #(
    parameter CLK_FREQ = 62500000,
    parameter BAUD     = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output reg         touch_valid,
    output reg  [15:0] touch_x,
    output reg  [15:0] touch_y,
    output reg         touch_state
);

    localparam CLK_DIV = CLK_FREQ / BAUD; // 62,500,000 / 115,200 = 542
    localparam TIMEOUT_CYCLES = CLK_FREQ / 100; // 10ms timeout = 625,000 cycles

    // 2-FF input synchronizer
    reg rx_d1, rx_d2;
    always @(posedge clk) begin
        rx_d1 <= uart_rx;
        rx_d2 <= rx_d1;
    end

    wire rx_falling = (~rx_d1) & rx_d2;

    // Byte Receiver FSM
    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_byte;
    reg        rx_done;
    reg        rx_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 16'd0;
            bit_idx  <= 4'd0;
            rx_shift <= 8'd0;
            rx_byte  <= 8'd0;
            rx_done  <= 1'b0;
            rx_busy  <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            if (!rx_busy) begin
                if (rx_falling) begin
                    rx_busy  <= 1'b1;
                    baud_cnt <= CLK_DIV / 2; // Sample at middle of start bit
                    bit_idx  <= 4'd0;
                end
            end else begin
                if (baud_cnt == 16'd0) begin
                    baud_cnt <= CLK_DIV - 1;
                    if (bit_idx == 4'd0) begin
                        if (rx_d2 == 1'b0) begin
                            bit_idx <= 4'd1;
                        end else begin
                            rx_busy <= 1'b0; // Filter glitch
                        end
                    end else if (bit_idx <= 4'd8) begin
                        rx_shift <= {rx_d2, rx_shift[7:1]};
                        bit_idx  <= bit_idx + 4'd1;
                    end else if (bit_idx == 4'd9) begin
                        rx_byte <= rx_shift;
                        rx_done <= 1'b1;
                        rx_busy <= 1'b0;
                        bit_idx <= 4'd0;
                    end
                end else begin
                    baud_cnt <= baud_cnt - 16'd1;
                end
            end
        end
    end

    // 7-Byte Frame Parser with 10ms Auto-Timeout
    localparam S_HDR1  = 3'd0;
    localparam S_HDR2  = 3'd1;
    localparam S_XH    = 3'd2;
    localparam S_XL    = 3'd3;
    localparam S_YH    = 3'd4;
    localparam S_YL    = 3'd5;
    localparam S_STATE = 3'd6;

    reg [2:0]  fsm_state;
    reg [19:0] timeout_cnt;
    reg [7:0]  tmp_xh, tmp_xl, tmp_yh, tmp_yl;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state   <= S_HDR1;
            timeout_cnt <= 20'd0;
            touch_valid <= 1'b0;
            touch_x     <= 16'd0;
            touch_y     <= 16'd0;
            touch_state <= 1'b0;
            tmp_xh      <= 8'd0;
            tmp_xl      <= 8'd0;
            tmp_yh      <= 8'd0;
            tmp_yl      <= 8'd0;
        end else begin
            touch_valid <= 1'b0;

            // Timeout watchdog
            if (fsm_state != S_HDR1) begin
                if (timeout_cnt >= TIMEOUT_CYCLES) begin
                    fsm_state   <= S_HDR1;
                    timeout_cnt <= 20'd0;
                end else begin
                    timeout_cnt <= timeout_cnt + 20'd1;
                end
            end else begin
                timeout_cnt <= 20'd0;
            end

            // Byte processing
            if (rx_done) begin
                timeout_cnt <= 20'd0;
                case (fsm_state)
                    S_HDR1: begin
                        if (rx_byte == 8'h54) fsm_state <= S_HDR2;
                    end
                    S_HDR2: begin
                        if (rx_byte == 8'h54) fsm_state <= S_XH;
                        else fsm_state <= S_HDR1;
                    end
                    S_XH: begin
                        tmp_xh    <= rx_byte;
                        fsm_state <= S_XL;
                    end
                    S_XL: begin
                        tmp_xl    <= rx_byte;
                        fsm_state <= S_YH;
                    end
                    S_YH: begin
                        tmp_yh    <= rx_byte;
                        fsm_state <= S_YL;
                    end
                    S_YL: begin
                        tmp_yl    <= rx_byte;
                        fsm_state <= S_STATE;
                    end
                    S_STATE: begin
                        touch_x     <= {tmp_xh, tmp_xl};
                        touch_y     <= {tmp_yh, tmp_yl};
                        touch_state <= rx_byte[0];
                        touch_valid <= 1'b1;
                        fsm_state   <= S_HDR1;
                    end
                    default: fsm_state <= S_HDR1;
                endcase
            end
        end
    end

endmodule
