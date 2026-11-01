// 低速诊断心跳：保存最近四个ADC原始码，不对采样链施加背压。
module ads1256_debug_uart #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD_RATE = 31250,
    parameter integer PERIOD_CYCLES = CLK_HZ / 4
)(
    input wire clk, rst_n, initialized, drdy,
    input wire [5:0] scanner_state,
    input wire sample_valid,
    input wire [2:0] sample_channel,
    input wire [23:0] sample_data,
    input wire midi_overflow,
    output reg uart_tx
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    reg [23:0] latest_sample [0:3];
    reg [23:0] snap_sample [0:3];
    reg [3:0] seen, snap_seen;
    reg snap_initialized, snap_drdy, snap_overflow;
    reg [7:0] snap_state;
    reg [31:0] interval_counter, baud_counter;
    reg active, tx_busy;
    reg [5:0] message_index;
    reg [3:0] bit_index;
    reg [7:0] tx_shift;
    localparam integer MSG_LENGTH = 57;
    integer k;
    function [7:0] hex_digit;
        input [7:0] v;
        begin hex_digit = (v[3:0] < 10) ? (8'h30 + v[3:0]) : (8'h37 + v[3:0]); end
    endfunction
    function [7:0] message_byte;
        input [5:0] index;
        begin
            case(index)
                6'd0: message_byte = "A";
                6'd1: message_byte = "D";
                6'd2: message_byte = "C";
                6'd3: message_byte = " ";
                6'd4: message_byte = "I";
                6'd5: message_byte = hex_digit({7'b0, snap_initialized});
                6'd6: message_byte = " ";
                6'd7: message_byte = "D";
                6'd8: message_byte = hex_digit({7'b0, snap_drdy});
                6'd9: message_byte = " ";
                6'd10: message_byte = "S";
                6'd11: message_byte = hex_digit(snap_state[7 -: 4]);
                6'd12: message_byte = hex_digit(snap_state[3 -: 4]);
                6'd13: message_byte = " ";
                6'd14: message_byte = "M";
                6'd15: message_byte = hex_digit({7'b0, snap_overflow});
                6'd16: message_byte = " ";
                6'd17: message_byte = "V";
                6'd18: message_byte = hex_digit({4'b0,snap_seen});
                6'd19: message_byte = " ";
                6'd20: message_byte = "0";
                6'd21: message_byte = ":";
                6'd22: message_byte = hex_digit(snap_sample[0][23 -: 4]);
                6'd23: message_byte = hex_digit(snap_sample[0][19 -: 4]);
                6'd24: message_byte = hex_digit(snap_sample[0][15 -: 4]);
                6'd25: message_byte = hex_digit(snap_sample[0][11 -: 4]);
                6'd26: message_byte = hex_digit(snap_sample[0][7 -: 4]);
                6'd27: message_byte = hex_digit(snap_sample[0][3 -: 4]);
                6'd28: message_byte = " ";
                6'd29: message_byte = "1";
                6'd30: message_byte = ":";
                6'd31: message_byte = hex_digit(snap_sample[1][23 -: 4]);
                6'd32: message_byte = hex_digit(snap_sample[1][19 -: 4]);
                6'd33: message_byte = hex_digit(snap_sample[1][15 -: 4]);
                6'd34: message_byte = hex_digit(snap_sample[1][11 -: 4]);
                6'd35: message_byte = hex_digit(snap_sample[1][7 -: 4]);
                6'd36: message_byte = hex_digit(snap_sample[1][3 -: 4]);
                6'd37: message_byte = " ";
                6'd38: message_byte = "2";
                6'd39: message_byte = ":";
                6'd40: message_byte = hex_digit(snap_sample[2][23 -: 4]);
                6'd41: message_byte = hex_digit(snap_sample[2][19 -: 4]);
                6'd42: message_byte = hex_digit(snap_sample[2][15 -: 4]);
                6'd43: message_byte = hex_digit(snap_sample[2][11 -: 4]);
                6'd44: message_byte = hex_digit(snap_sample[2][7 -: 4]);
                6'd45: message_byte = hex_digit(snap_sample[2][3 -: 4]);
                6'd46: message_byte = " ";
                6'd47: message_byte = "3";
                6'd48: message_byte = ":";
                6'd49: message_byte = hex_digit(snap_sample[3][23 -: 4]);
                6'd50: message_byte = hex_digit(snap_sample[3][19 -: 4]);
                6'd51: message_byte = hex_digit(snap_sample[3][15 -: 4]);
                6'd52: message_byte = hex_digit(snap_sample[3][11 -: 4]);
                6'd53: message_byte = hex_digit(snap_sample[3][7 -: 4]);
                6'd54: message_byte = hex_digit(snap_sample[3][3 -: 4]);
                6'd55: message_byte = 8'h0d;
                6'd56: message_byte = 8'h0a;
                default: message_byte = 8'h20;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interval_counter <= 0; baud_counter <= 0; active <= 0; tx_busy <= 0;
            message_index <= 0; bit_index <= 0; tx_shift <= 0; uart_tx <= 1;
            seen <= 0; snap_seen <= 0; snap_initialized <= 0; snap_drdy <= 1;
            snap_state <= 0; snap_overflow <= 0;
            for (k=0;k<4;k=k+1) begin latest_sample[k]<=0; snap_sample[k]<=0; end
        end else begin
            if (sample_valid && sample_channel < 4) begin
                latest_sample[sample_channel] <= sample_data;
                seen[sample_channel] <= 1'b1;
            end
            if (interval_counter == PERIOD_CYCLES-1) begin
                interval_counter <= 0;
                if (!active && !tx_busy) begin
                    active <= 1; message_index <= 0;
                    snap_seen <= seen; snap_initialized <= initialized; snap_drdy <= drdy;
                    snap_state <= {2'b0,scanner_state}; snap_overflow <= midi_overflow;
                    for (k=0;k<4;k=k+1) snap_sample[k] <= latest_sample[k];
                end
            end else interval_counter <= interval_counter + 1'b1;
            if (!tx_busy) begin
                uart_tx <= 1;
                if (active) begin
                    tx_shift <= message_byte(message_index);
                    uart_tx <= 0; tx_busy <= 1; bit_index <= 0; baud_counter <= 0;
                    if (message_index == MSG_LENGTH-1) active <= 0;
                    else message_index <= message_index + 1'b1;
                end
            end else if (baud_counter == CLKS_PER_BIT-1) begin
                baud_counter <= 0;
                if (bit_index < 8) begin
                    uart_tx <= tx_shift[bit_index]; bit_index <= bit_index + 1'b1;
                end else if (bit_index == 8) begin
                    uart_tx <= 1; bit_index <= 9;
                end else begin tx_busy <= 0; uart_tx <= 1; end
            end else baud_counter <= baud_counter + 1'b1;
        end
    end
endmodule
