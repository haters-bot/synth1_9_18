// MIDI字节流解析器。
// 当前处理所有通道的Note On和Note Off，并支持Running Status。
// 0xF8～0xFF实时消息会被忽略，而且不会破坏Running Status。
module midi_note_parser(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] byte_data,
    input  wire       byte_valid,
    output reg        note_event_valid,
    output reg        note_event_on,
    output reg [6:0]  note_event_note,
    output reg [6:0]  note_event_velocity
);

    reg [7:0] running_status;
    reg       waiting_for_velocity;
    reg [6:0] pending_note;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running_status       <= 8'd0;
            waiting_for_velocity <= 1'b0;
            pending_note         <= 7'd0;
            note_event_valid     <= 1'b0;
            note_event_on        <= 1'b0;
            note_event_note      <= 7'd0;
            note_event_velocity  <= 7'd0;
        end else begin
            note_event_valid <= 1'b0;

            if (byte_valid) begin
                if (byte_data[7]) begin
                    if ((byte_data[7:4] == 4'h8)
                        || (byte_data[7:4] == 4'h9)) begin
                        running_status       <= byte_data;
                        waiting_for_velocity <= 1'b0;
                    end else if (byte_data < 8'hF8) begin
                        // 当前版本不处理其他通道消息和系统消息。
                        running_status       <= 8'd0;
                        waiting_for_velocity <= 1'b0;
                    end
                end else if ((running_status[7:4] == 4'h8)
                             || (running_status[7:4] == 4'h9)) begin
                    if (!waiting_for_velocity) begin
                        pending_note         <= byte_data[6:0];
                        waiting_for_velocity <= 1'b1;
                    end else begin
                        note_event_valid    <= 1'b1;
                        note_event_note     <= pending_note;
                        note_event_velocity <= byte_data[6:0];
                        note_event_on       <= (running_status[7:4] == 4'h9)
                                            && (byte_data[6:0] != 7'd0);
                        waiting_for_velocity <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
