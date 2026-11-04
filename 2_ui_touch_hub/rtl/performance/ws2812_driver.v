// WS2812/NeoPixel one-wire transmitter.
// The frame RAM is written while idle; latch starts a complete buffered frame.
module ws2812_driver #(
    parameter integer CLK_HZ = 50000000,
    parameter integer LED_COUNT = 24,
    parameter integer RESET_CYCLES = (CLK_HZ / 1000000) * 300,
    parameter integer GRB_ORDER = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         frame_we,
    input  wire [$clog2(LED_COUNT)-1:0] frame_index,
    input  wire [23:0]                  frame_rgb,
    input  wire                         latch,
    output reg                          data,
    output reg                          busy,
    output reg                          frame_done
);
    localparam integer BIT_CYCLES = (CLK_HZ / 800000 < 2) ? 2 : CLK_HZ / 800000;
    localparam integer T0H_CYCLES = CLK_HZ / 2500000;
    localparam integer T1H_CYCLES = CLK_HZ / 1250000;
    localparam integer LED_BITS = (LED_COUNT <= 1) ? 1 : $clog2(LED_COUNT);
    localparam integer BIT_COUNTER = (BIT_CYCLES <= 2) ? 1 : $clog2(BIT_CYCLES);
    localparam integer RESET_COUNTER = (RESET_CYCLES <= 2) ? 1 : $clog2(RESET_CYCLES);

    reg [23:0] frame_mem [0:LED_COUNT-1];
    reg [LED_BITS-1:0] led_index;
    reg [4:0] bit_index;
    reg [BIT_COUNTER-1:0] bit_cycle;
    reg [RESET_COUNTER-1:0] reset_cycle;
    reg [1:0] state;
    localparam ST_IDLE=2'd0, ST_SEND=2'd1, ST_RESET=2'd2, ST_BOOT=2'd3;

    wire current_bit = frame_mem[led_index][bit_index];
    wire [BIT_COUNTER-1:0] high_cycles = current_bit ? T1H_CYCLES : T0H_CYCLES;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data       <= 1'b0;
            busy       <= 1'b1;
            frame_done <= 1'b0;
            led_index  <= {LED_BITS{1'b0}};
            bit_index  <= 5'd23;
            bit_cycle  <= {BIT_COUNTER{1'b0}};
            reset_cycle<= {RESET_COUNTER{1'b0}};
            state      <= ST_BOOT;
        end else begin
            frame_done <= 1'b0;
            if (frame_we && !busy && (frame_index < LED_COUNT))
                frame_mem[frame_index] <= GRB_ORDER ?
                    {frame_rgb[15:8],frame_rgb[23:16],frame_rgb[7:0]} : frame_rgb;

            case (state)
                ST_IDLE: begin
                    data <= 1'b0;
                    busy <= 1'b0;
                    if (latch) begin
                        busy      <= 1'b1;
                        led_index <= {LED_BITS{1'b0}};
                        bit_index <= 5'd23;
                        bit_cycle <= {BIT_COUNTER{1'b0}};
                        state     <= ST_SEND;
                    end
                end
                ST_SEND: begin
                    busy <= 1'b1;
                    data <= bit_cycle < high_cycles;
                    if (bit_cycle == BIT_CYCLES-1) begin
                        bit_cycle <= {BIT_COUNTER{1'b0}};
                        if (bit_index == 0) begin
                            bit_index <= 5'd23;
                            if (led_index == LED_COUNT-1) begin
                                reset_cycle <= {RESET_COUNTER{1'b0}};
                                data  <= 1'b0;
                                state <= ST_RESET;
                            end else begin
                                led_index <= led_index + 1'b1;
                            end
                        end else begin
                            bit_index <= bit_index - 1'b1;
                        end
                    end else begin
                        bit_cycle <= bit_cycle + 1'b1;
                    end
                end
                ST_RESET: begin
                    data <= 1'b0;
                    busy <= 1'b1;
                    if (reset_cycle == RESET_CYCLES-1) begin
                        busy       <= 1'b0;
                        frame_done <= 1'b1;
                        state      <= ST_IDLE;
                    end else begin
                        reset_cycle <= reset_cycle + 1'b1;
                    end
                end
                ST_BOOT: begin
                    data <= 1'b0;
                    busy <= 1'b1;
                    if (reset_cycle == RESET_CYCLES-1) begin
                        busy <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        reset_cycle <= reset_cycle + 1'b1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
