// 两路完整控制事件的同步队列。每拍最多入队两项、出队一项。
// 同拍碰撞先保留原USB-UART事件，再保留独立控制口事件；溢出标志保持到复位。
module control_event_merge (
    input wire clk, rst_n,
    input wire valid_a, valid_b,
    input wire [21:0] data_a, data_b,
    output reg out_valid,
    output reg [21:0] out_data,
    output reg overflow
);
    reg [21:0] memory [0:7];
    reg [2:0] read_ptr, write_ptr;
    reg [3:0] count;
    wire pop = count != 0;
    wire accept_a = valid_a && ((count < 8) || pop);
    wire accept_b = valid_b && (({1'b0,count} - pop + accept_a) < 8);
    wire [1:0] pushed = {1'b0,accept_a} + {1'b0,accept_b};
    wire [2:0] second_ptr = write_ptr + 3'd1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr <= 0; write_ptr <= 0; count <= 0;
            out_valid <= 0; out_data <= 0; overflow <= 0;
        end else begin
            out_valid <= pop;
            if (pop) begin
                out_data <= memory[read_ptr];
                read_ptr <= read_ptr + 3'd1;
            end
            if (accept_a) memory[write_ptr] <= data_a;
            if (accept_b) memory[accept_a ? second_ptr : write_ptr] <= data_b;
            write_ptr <= write_ptr + pushed;
            count <= count - pop + pushed;
            if ((valid_a && !accept_a) || (valid_b && !accept_b)) overflow <= 1;
        end
    end
endmodule
