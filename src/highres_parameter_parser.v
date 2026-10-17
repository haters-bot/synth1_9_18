// 从与MIDI共用的UART字节流中提取高精度合成参数。
//
// 第一版帧格式：
//   F0 7D parameter value_msb value_lsb F7
//
// 7D是MIDI规范为非商业开发保留的制造商编号。所有负载字节均小于80，
// 因此消息可以与普通MIDI消息共用一条链路。value采用14位无符号数，
// 由value_msb[6:0]和value_lsb[6:0]组成。
module highres_parameter_parser(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  byte_data,
    input  wire        byte_valid,
    output reg         parameter_valid,
    output reg  [6:0]  parameter_id,
    output reg  [13:0] parameter_value
);

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_VENDOR     = 3'd1;
    localparam [2:0] STATE_PARAMETER  = 3'd2;
    localparam [2:0] STATE_VALUE_MSB  = 3'd3;
    localparam [2:0] STATE_VALUE_LSB  = 3'd4;
    localparam [2:0] STATE_END        = 3'd5;

    reg [2:0] state;
    reg [6:0] pending_parameter_id;
    reg [6:0] pending_value_msb;
    reg [6:0] pending_value_lsb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= STATE_IDLE;
            pending_parameter_id <= 7'd0;
            pending_value_msb    <= 7'd0;
            pending_value_lsb    <= 7'd0;
            parameter_valid      <= 1'b0;
            parameter_id         <= 7'd0;
            parameter_value      <= 14'd0;
        end else begin
            parameter_valid <= 1'b0;

            if (byte_valid) begin
                // MIDI实时消息允许插入任意消息内部，不能破坏当前组帧状态。
                if (byte_data >= 8'hF8) begin
                    // 保持当前状态。
                // 任意位置收到新的F0都重新开始组帧，便于从丢字节后恢复。
                end else if (byte_data == 8'hF0) begin
                    state <= STATE_VENDOR;
                end else begin
                    case (state)
                        STATE_IDLE: begin
                            state <= STATE_IDLE;
                        end

                        STATE_VENDOR: begin
                            state <= (byte_data == 8'h7D)
                                   ? STATE_PARAMETER : STATE_IDLE;
                        end

                        STATE_PARAMETER: begin
                            if (!byte_data[7]) begin
                                pending_parameter_id <= byte_data[6:0];
                                state <= STATE_VALUE_MSB;
                            end else begin
                                state <= STATE_IDLE;
                            end
                        end

                        STATE_VALUE_MSB: begin
                            if (!byte_data[7]) begin
                                pending_value_msb <= byte_data[6:0];
                                state <= STATE_VALUE_LSB;
                            end else begin
                                state <= STATE_IDLE;
                            end
                        end

                        STATE_VALUE_LSB: begin
                            if (!byte_data[7]) begin
                                pending_value_lsb <= byte_data[6:0];
                                state <= STATE_END;
                            end else begin
                                state <= STATE_IDLE;
                            end
                        end

                        STATE_END: begin
                            if (byte_data == 8'hF7) begin
                                parameter_id    <= pending_parameter_id;
                                parameter_value <= {
                                    pending_value_msb,
                                    pending_value_lsb
                                };
                                parameter_valid <= 1'b1;
                            end
                            state <= STATE_IDLE;
                        end

                        default: begin
                            state <= STATE_IDLE;
                        end
                    endcase
                end
            end
        end
    end

endmodule
