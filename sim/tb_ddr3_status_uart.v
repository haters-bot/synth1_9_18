`timescale 1ns/1ps

module tb_ddr3_status_uart;

    localparam integer CLK_HZ        = 10000000;
    localparam integer BAUD_RATE     = 1000000;
    localparam integer BIT_PERIOD_NS = 1000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg init_done_async = 1'b0;
    reg test_finished_async = 1'b0;
    reg test_passed_async = 1'b0;
    wire uart_tx;

    integer i;
    reg [7:0] received_byte;

    always #50 clk = ~clk;

    ddr3_status_uart #(
        .CLK_HZ   (CLK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut(
        .clk                (clk),
        .rst_n              (rst_n),
        .init_done_async    (init_done_async),
        .test_finished_async(test_finished_async),
        .test_passed_async  (test_passed_async),
        .uart_tx            (uart_tx)
    );

    function integer expected_length;
        input integer kind;
        begin
            case (kind)
                0: expected_length = 16;
                1: expected_length = 13;
                default: expected_length = 15;
            endcase
        end
    endfunction

    function [7:0] expected_byte;
        input integer kind;
        input integer index;
        begin
            expected_byte = 8'h3F;
            case (kind)
                0: begin
                    case (index)
                        0: expected_byte="D"; 1: expected_byte="D";
                        2: expected_byte="R"; 3: expected_byte=" ";
                        4: expected_byte="T"; 5: expected_byte="E";
                        6: expected_byte="S"; 7: expected_byte="T";
                        8: expected_byte=" "; 9: expected_byte="S";
                        10: expected_byte="T"; 11: expected_byte="A";
                        12: expected_byte="R"; 13: expected_byte="T";
                        14: expected_byte=8'h0D; 15: expected_byte=8'h0A;
                    endcase
                end
                1: begin
                    case (index)
                        0: expected_byte="D"; 1: expected_byte="D";
                        2: expected_byte="R"; 3: expected_byte=" ";
                        4: expected_byte="I"; 5: expected_byte="N";
                        6: expected_byte="I"; 7: expected_byte="T";
                        8: expected_byte=" "; 9: expected_byte="O";
                        10: expected_byte="K";
                        11: expected_byte=8'h0D; 12: expected_byte=8'h0A;
                    endcase
                end
                2: begin
                    case (index)
                        0: expected_byte="D"; 1: expected_byte="D";
                        2: expected_byte="R"; 3: expected_byte=" ";
                        4: expected_byte="B"; 5: expected_byte="I";
                        6: expected_byte="S"; 7: expected_byte="T";
                        8: expected_byte=" "; 9: expected_byte="P";
                        10: expected_byte="A"; 11: expected_byte="S";
                        12: expected_byte="S";
                        13: expected_byte=8'h0D; 14: expected_byte=8'h0A;
                    endcase
                end
                default: begin
                    case (index)
                        0: expected_byte="D"; 1: expected_byte="D";
                        2: expected_byte="R"; 3: expected_byte=" ";
                        4: expected_byte="B"; 5: expected_byte="I";
                        6: expected_byte="S"; 7: expected_byte="T";
                        8: expected_byte=" "; 9: expected_byte="F";
                        10: expected_byte="A"; 11: expected_byte="I";
                        12: expected_byte="L";
                        13: expected_byte=8'h0D; 14: expected_byte=8'h0A;
                    endcase
                end
            endcase
        end
    endfunction

    task receive_byte;
        begin
            @(negedge uart_tx);
            #(BIT_PERIOD_NS / 2);
            if (uart_tx !== 1'b0) begin
                $display("FAIL: UART start bit is invalid at %0t", $time);
                $fatal;
            end

            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD_NS;
                received_byte[i] = uart_tx;
            end

            #BIT_PERIOD_NS;
            if (uart_tx !== 1'b1) begin
                $display("FAIL: UART stop bit is invalid at %0t", $time);
                $fatal;
            end
        end
    endtask

    task check_message;
        input integer kind;
        integer byte_index;
        begin
            for (byte_index = 0;
                 byte_index < expected_length(kind);
                 byte_index = byte_index + 1) begin
                receive_byte();
                if (received_byte !== expected_byte(kind, byte_index)) begin
                    $display("FAIL: message %0d byte %0d expected %02h got %02h",
                             kind, byte_index,
                             expected_byte(kind, byte_index), received_byte);
                    $fatal;
                end
            end
        end
    endtask

    task apply_reset;
        begin
            rst_n = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        apply_reset();
        check_message(0);

        init_done_async = 1'b1;
        check_message(1);

        test_passed_async = 1'b1;
        test_finished_async = 1'b1;
        check_message(2);

        init_done_async = 1'b0;
        test_finished_async = 1'b0;
        test_passed_async = 1'b0;
        apply_reset();
        check_message(0);

        init_done_async = 1'b1;
        check_message(1);

        test_finished_async = 1'b1;
        check_message(3);

        $display("PASS: DDR3 status UART reports boot, init, pass and fail messages");
        $finish;
    end

    initial begin
        #1500000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

endmodule
