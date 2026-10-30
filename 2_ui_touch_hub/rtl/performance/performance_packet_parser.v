// CRC-checked parser for the phone/gateway performance protocol V1.
// Payload capacity is intentionally bounded so the parser stays register
// based and cannot allocate a large inferred RAM in the UI compositor.
module performance_packet_parser #(
    parameter integer MAX_PAYLOAD = 64,
    parameter integer TIMEOUT_CYCLES = 0
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     byte_valid,
    input  wire [7:0]               byte_data,
    output reg                      packet_valid,
    output reg [7:0]                packet_type,
    output reg [7:0]                packet_sequence,
    output reg [6:0]                packet_length,
    output reg [MAX_PAYLOAD*8-1:0]  packet_payload,
    output reg [15:0]               packet_crc,
    output reg                      crc_error
);
    localparam [7:0] SYNC_BYTE = 8'hA5;
    localparam [7:0] VERSION   = 8'h01;
    localparam [2:0] ST_SYNC=3'd0, ST_HEADER=3'd1, ST_PAYLOAD=3'd2,
                     ST_CRC_LO=3'd3, ST_CRC_HI=3'd4;

    reg [2:0] state;
    reg [2:0] header_index;
    reg [6:0] payload_index;
    reg [7:0] frame_type;
    reg [7:0] frame_sequence;
    reg [7:0] frame_length_lo;
    reg [7:0] frame_length_hi;
    reg [7:0] frame_length;
    reg [7:0] payload_mem [0:MAX_PAYLOAD-1];
    reg [15:0] crc_calc;
    reg [7:0] crc_rx_lo;
    integer copy_index;
    localparam IDLE_BITS=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES+1);
    reg [IDLE_BITS-1:0] idle_cycles;

    function [15:0] crc_next;
        input [15:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [15:0] value;
        begin
            value = crc_in ^ {data_in,8'd0};
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                value = value[15] ? ((value << 1) ^ 16'h1021) : (value << 1);
            crc_next = value;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_SYNC;
            header_index    <= 3'd0;
            payload_index   <= 7'd0;
            frame_type      <= 8'd0;
            frame_sequence  <= 8'd0;
            frame_length_lo <= 8'd0;
            frame_length_hi <= 8'd0;
            frame_length    <= 8'd0;
            crc_calc        <= 16'hFFFF;
            crc_rx_lo       <= 8'd0;
            packet_valid    <= 1'b0;
            packet_type     <= 8'd0;
            packet_sequence <= 8'd0;
            packet_length   <= 7'd0;
            packet_payload  <= {(MAX_PAYLOAD*8){1'b0}};
            packet_crc      <= 16'd0;
            crc_error       <= 1'b0;
            idle_cycles     <= 0;
        end else begin
            packet_valid <= 1'b0;
            crc_error    <= 1'b0;
            if(byte_valid || state==ST_SYNC)idle_cycles<=0;
            else if(TIMEOUT_CYCLES!=0)begin
                if(idle_cycles==TIMEOUT_CYCLES-1)begin state<=ST_SYNC;idle_cycles<=0;crc_error<=1;end
                else idle_cycles<=idle_cycles+1'b1;
            end
            if (byte_valid) begin
                case (state)
                    ST_SYNC: begin
                        if (byte_data == SYNC_BYTE) begin
                            state        <= ST_HEADER;
                            header_index <= 3'd0;
                            crc_calc     <= 16'hFFFF;
                        end
                    end
                    ST_HEADER: begin
                        crc_calc <= crc_next(crc_calc, byte_data);
                        case (header_index)
                            3'd0: begin
                                if (byte_data != VERSION) begin
                                    state <= ST_SYNC;
                                    crc_error <= 1'b1;
                                end else begin
                                    header_index <= 3'd1;
                                end
                            end
                            3'd1: begin
                                frame_type <= byte_data;
                                header_index <= 3'd2;
                            end
                            3'd2: begin
                                frame_sequence <= byte_data;
                                header_index <= 3'd3;
                            end
                            3'd3: begin
                                frame_length_lo <= byte_data;
                                header_index <= 3'd4;
                            end
                            default: begin
                                frame_length_hi <= byte_data;
                                frame_length <= frame_length_lo;
                                if (byte_data != 0 || frame_length_lo > MAX_PAYLOAD) begin
                                    state <= ST_SYNC;
                                    crc_error <= 1'b1;
                                end else if (frame_length_lo == 0) begin
                                    state <= ST_CRC_LO;
                                end else begin
                                    payload_index <= 7'd0;
                                    state <= ST_PAYLOAD;
                                end
                            end
                        endcase
                    end
                    ST_PAYLOAD: begin
                        payload_mem[payload_index] <= byte_data;
                        crc_calc <= crc_next(crc_calc, byte_data);
                        if (payload_index + 1'b1 >= frame_length)
                            state <= ST_CRC_LO;
                        else
                            payload_index <= payload_index + 1'b1;
                    end
                    ST_CRC_LO: begin
                        crc_rx_lo <= byte_data;
                        state <= ST_CRC_HI;
                    end
                    ST_CRC_HI: begin
                        state <= ST_SYNC;
                        if ({byte_data,crc_rx_lo} == crc_calc) begin
                            packet_valid    <= 1'b1;
                            packet_crc      <= crc_calc;
                            packet_type     <= frame_type;
                            packet_sequence <= frame_sequence;
                            packet_length   <= frame_length;
                            for (copy_index=0; copy_index<MAX_PAYLOAD; copy_index=copy_index+1)
                                packet_payload[copy_index*8 +: 8] <= (copy_index < frame_length) ? payload_mem[copy_index] : 8'd0;
                        end else begin
                            crc_error <= 1'b1;
                        end
                    end
                    default: state <= ST_SYNC;
                endcase
            end
        end
    end
endmodule
