// MIDI字节流解析器。
// 当前处理所有通道的Note On、Note Off和Control Change，并支持Running Status。
// 0xF8～0xFF实时消息会被忽略，而且不会破坏Running Status。
module midi_note_parser(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] byte_data,
    input  wire       byte_valid,
    output reg        note_event_valid,
    output reg        note_event_on,
    output reg [3:0]  note_event_channel,
    output reg [6:0]  note_event_note,
    output reg [6:0]  note_event_velocity,
    output reg        control_change_valid,
    output reg [3:0]  control_change_channel,
    output reg [6:0]  control_change_number,
    output reg [6:0]  control_change_value
);

    reg [7:0] running_status;
    reg       waiting_for_data2;
    reg [6:0] pending_data1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running_status       <= 8'd0;
            waiting_for_data2    <= 1'b0;
            pending_data1        <= 7'd0;
            note_event_valid     <= 1'b0;
            note_event_on        <= 1'b0;
            note_event_channel   <= 4'd0;
            note_event_note      <= 7'd0;
            note_event_velocity  <= 7'd0;
            control_change_valid <= 1'b0;
            control_change_channel <= 4'd0;
            control_change_number <= 7'd0;
            control_change_value <= 7'd0;
        end else begin
            note_event_valid <= 1'b0;
            control_change_valid <= 1'b0;

            if (byte_valid) begin
                if (byte_data[7]) begin
                    if ((byte_data[7:4] == 4'h8)
                        || (byte_data[7:4] == 4'h9)
                        || (byte_data[7:4] == 4'hB)) begin
                        running_status       <= byte_data;
                        waiting_for_data2    <= 1'b0;
                    end else if (byte_data < 8'hF8) begin
                        // 当前版本不处理其他通道消息和系统消息。
                        running_status       <= 8'd0;
                        waiting_for_data2    <= 1'b0;
                    end
                end else if ((running_status[7:4] == 4'h8)
                             || (running_status[7:4] == 4'h9)
                             || (running_status[7:4] == 4'hB)) begin
                    if (!waiting_for_data2) begin
                        pending_data1     <= byte_data[6:0];
                        waiting_for_data2 <= 1'b1;
                    end else begin
                        if (running_status[7:4] == 4'hB) begin
                            control_change_valid  <= 1'b1;
                            control_change_channel <= running_status[3:0];
                            control_change_number <= pending_data1;
                            control_change_value  <= byte_data[6:0];
                        end else begin
                            note_event_valid    <= 1'b1;
                            note_event_channel  <= running_status[3:0];
                            note_event_note     <= pending_data1;
                            note_event_velocity <= byte_data[6:0];
                            note_event_on       <= (running_status[7:4] == 4'h9)
                                                && (byte_data[6:0] != 7'd0);
                        end
                        waiting_for_data2 <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
