// DDR3 独立测试的串口状态输出。
// 串口格式为 115200 baud、8 数据位、无校验、1 停止位（8N1）。
module ddr3_status_uart #(
    parameter integer CLK_HZ    = 50000000,
    parameter integer BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire init_done_async,
    input  wire test_finished_async,
    input  wire test_passed_async,
    output reg  uart_tx
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD_RATE;

    localparam [1:0] MSG_BOOT = 2'd0;
    localparam [1:0] MSG_INIT = 2'd1;
    localparam [1:0] MSG_PASS = 2'd2;
    localparam [1:0] MSG_FAIL = 2'd3;

    reg init_done_meta;
    reg init_done_sync;
    reg test_finished_meta;
    reg test_finished_sync;
    reg test_finished_sync_d;
    reg test_passed_meta;
    reg test_passed_sync;

    reg boot_sent;
    reg init_sent;
    reg result_sent;
    reg message_active;
    reg [1:0] message_kind;
    reg [4:0] message_index;

    reg [7:0] tx_data;
    reg tx_start;
    reg tx_busy;
    reg [7:0] tx_shift;
    reg [3:0] tx_bit_index;
    reg [15:0] baud_counter;

    // 三个状态量都来自 100 MHz DDR 用户时钟域。
    // 完成信号在目标域额外等待一拍，再读取保持稳定的通过标志。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_done_meta       <= 1'b0;
            init_done_sync       <= 1'b0;
            test_finished_meta   <= 1'b0;
            test_finished_sync   <= 1'b0;
            test_finished_sync_d <= 1'b0;
            test_passed_meta     <= 1'b0;
            test_passed_sync     <= 1'b0;
        end else begin
            init_done_meta       <= init_done_async;
            init_done_sync       <= init_done_meta;
            test_finished_meta   <= test_finished_async;
            test_finished_sync   <= test_finished_meta;
            test_finished_sync_d <= test_finished_sync;
            test_passed_meta     <= test_passed_async;
            test_passed_sync     <= test_passed_meta;
        end
    end

    function [5:0] message_length;
        input [1:0] kind;
        begin
            case (kind)
                MSG_BOOT: message_length = 6'd16;
                MSG_INIT: message_length = 6'd13;
                MSG_PASS: message_length = 6'd15;
                default:  message_length = 6'd15;
            endcase
        end
    endfunction

    function [7:0] message_byte;
        input [1:0] kind;
        input [4:0] index;
        begin
            message_byte = 8'h3F;
            case (kind)
                MSG_BOOT: begin
                    case (index)
                        5'd0:  message_byte = "D";
                        5'd1:  message_byte = "D";
                        5'd2:  message_byte = "R";
                        5'd3:  message_byte = " ";
                        5'd4:  message_byte = "T";
                        5'd5:  message_byte = "E";
                        5'd6:  message_byte = "S";
                        5'd7:  message_byte = "T";
                        5'd8:  message_byte = " ";
                        5'd9:  message_byte = "S";
                        5'd10: message_byte = "T";
                        5'd11: message_byte = "A";
                        5'd12: message_byte = "R";
                        5'd13: message_byte = "T";
                        5'd14: message_byte = 8'h0D;
                        5'd15: message_byte = 8'h0A;
                        default: message_byte = 8'h3F;
                    endcase
                end
                MSG_INIT: begin
                    case (index)
                        5'd0:  message_byte = "D";
                        5'd1:  message_byte = "D";
                        5'd2:  message_byte = "R";
                        5'd3:  message_byte = " ";
                        5'd4:  message_byte = "I";
                        5'd5:  message_byte = "N";
                        5'd6:  message_byte = "I";
                        5'd7:  message_byte = "T";
                        5'd8:  message_byte = " ";
                        5'd9:  message_byte = "O";
                        5'd10: message_byte = "K";
                        5'd11: message_byte = 8'h0D;
                        5'd12: message_byte = 8'h0A;
                        default: message_byte = 8'h3F;
                    endcase
                end
                MSG_PASS: begin
                    case (index)
                        5'd0:  message_byte = "D";
                        5'd1:  message_byte = "D";
                        5'd2:  message_byte = "R";
                        5'd3:  message_byte = " ";
                        5'd4:  message_byte = "B";
                        5'd5:  message_byte = "I";
                        5'd6:  message_byte = "S";
                        5'd7:  message_byte = "T";
                        5'd8:  message_byte = " ";
                        5'd9:  message_byte = "P";
                        5'd10: message_byte = "A";
                        5'd11: message_byte = "S";
                        5'd12: message_byte = "S";
                        5'd13: message_byte = 8'h0D;
                        5'd14: message_byte = 8'h0A;
                        default: message_byte = 8'h3F;
                    endcase
                end
                default: begin
                    case (index)
                        5'd0:  message_byte = "D";
                        5'd1:  message_byte = "D";
                        5'd2:  message_byte = "R";
                        5'd3:  message_byte = " ";
                        5'd4:  message_byte = "B";
                        5'd5:  message_byte = "I";
                        5'd6:  message_byte = "S";
                        5'd7:  message_byte = "T";
                        5'd8:  message_byte = " ";
                        5'd9:  message_byte = "F";
                        5'd10: message_byte = "A";
                        5'd11: message_byte = "I";
                        5'd12: message_byte = "L";
                        5'd13: message_byte = 8'h0D;
                        5'd14: message_byte = 8'h0A;
                        default: message_byte = 8'h3F;
                    endcase
                end
            endcase
        end
    endfunction

    // 消息调度器按“启动、初始化、测试结果”的固定顺序各发送一次。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_sent      <= 1'b0;
            init_sent      <= 1'b0;
            result_sent    <= 1'b0;
            message_active <= 1'b0;
            message_kind   <= MSG_BOOT;
            message_index  <= 5'd0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (message_active) begin
                if (!tx_busy && !tx_start) begin
                    tx_data  <= message_byte(message_kind, message_index);
                    tx_start <= 1'b1;

                    if (message_index == message_length(message_kind) - 6'd1) begin
                        message_active <= 1'b0;
                        message_index  <= 5'd0;
                    end else begin
                        message_index <= message_index + 5'd1;
                    end
                end
            end else if (!tx_busy && !tx_start) begin
                if (!boot_sent) begin
                    boot_sent      <= 1'b1;
                    message_active <= 1'b1;
                    message_kind   <= MSG_BOOT;
                    message_index  <= 5'd0;
                end else if (init_done_sync && !init_sent) begin
                    init_sent      <= 1'b1;
                    message_active <= 1'b1;
                    message_kind   <= MSG_INIT;
                    message_index  <= 5'd0;
                end else if (test_finished_sync && test_finished_sync_d
                             && !result_sent) begin
                    result_sent    <= 1'b1;
                    message_active <= 1'b1;
                    message_kind   <= test_passed_sync ? MSG_PASS : MSG_FAIL;
                    message_index  <= 5'd0;
                end
            end
        end
    end

    // 单字节 UART 发送器：1 位起始位、8 位数据（低位先发）、1 位停止位。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx      <= 1'b1;
            tx_busy      <= 1'b0;
            tx_shift     <= 8'd0;
            tx_bit_index <= 4'd0;
            baud_counter <= 16'd0;
        end else if (!tx_busy) begin
            uart_tx <= 1'b1;
            if (tx_start) begin
                uart_tx      <= 1'b0;
                tx_busy      <= 1'b1;
                tx_shift     <= tx_data;
                tx_bit_index <= 4'd0;
                baud_counter <= 16'd0;
            end
        end else if (baud_counter == CLKS_PER_BIT - 1) begin
            baud_counter <= 16'd0;
            if (tx_bit_index <= 4'd7) begin
                uart_tx      <= tx_shift[tx_bit_index];
                tx_bit_index <= tx_bit_index + 4'd1;
            end else if (tx_bit_index == 4'd8) begin
                uart_tx      <= 1'b1;
                tx_bit_index <= 4'd9;
            end else begin
                uart_tx <= 1'b1;
                tx_busy <= 1'b0;
            end
        end else begin
            baud_counter <= baud_counter + 16'd1;
        end
    end

endmodule
