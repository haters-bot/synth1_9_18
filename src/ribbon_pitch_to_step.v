// 把Q7.8 MIDI音高转换为768 kHz DDS使用的32位相位步进。
// 相邻半音的phase step先查表，再按8位小数做线性插值。该转换只在
// 数百Hz的控制事件上运行，不进入768 kHz音频关键路径。
module ribbon_pitch_to_step (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_on,
    input  wire [2:0]  in_source,
    input  wire [14:0] in_pitch_q8,
    input  wire [6:0]  in_velocity,

    output reg         out_valid,
    input  wire        out_ready,
    output reg         out_on,
    output reg [2:0]   out_source,
    output reg [31:0]  out_base_step,
    output reg [6:0]   out_velocity
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_MULT = 2'd1;
    localparam [1:0] STATE_OUT  = 2'd2;
    reg [1:0] state;

    reg [6:0] note_low;
    reg [6:0] note_high;
    reg [7:0] fraction;
    reg pending_on;
    reg [2:0] pending_source;
    reg [6:0] pending_velocity;
    reg [31:0] low_step_latched;
    reg [39:0] interpolation_product;

    wire [31:0] low_step;
    wire [31:0] high_step;
    wire [31:0] step_delta = high_step - low_step;

    assign in_ready = (state == STATE_IDLE) && !out_valid;

    freq_lut u_ribbon_low_freq_lut (
        .addr(note_low),
        .data(low_step)
    );

    freq_lut u_ribbon_high_freq_lut (
        .addr(note_high),
        .data(high_step)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            note_low <= 7'd24;
            note_high <= 7'd25;
            fraction <= 8'd0;
            pending_on <= 1'b0;
            pending_source <= 3'd0;
            pending_velocity <= 7'd0;
            low_step_latched <= 32'd0;
            interpolation_product <= 40'd0;
            out_valid <= 1'b0;
            out_on <= 1'b0;
            out_source <= 3'd0;
            out_base_step <= 32'd0;
            out_velocity <= 7'd0;
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (in_valid && in_ready) begin
                        pending_on <= in_on;
                        pending_source <= in_source;
                        pending_velocity <= in_velocity;
                        if (in_pitch_q8[14:8] >= 7'd108) begin
                            note_low <= 7'd108;
                            note_high <= 7'd108;
                            fraction <= 8'd0;
                        end else if (in_pitch_q8[14:8] < 7'd21) begin
                            note_low <= 7'd21;
                            note_high <= 7'd22;
                            fraction <= 8'd0;
                        end else begin
                            note_low <= in_pitch_q8[14:8];
                            note_high <= in_pitch_q8[14:8] + 7'd1;
                            fraction <= in_pitch_q8[7:0];
                        end
                        state <= STATE_MULT;
                    end
                end

                STATE_MULT: begin
                    low_step_latched <= low_step;
                    interpolation_product <= step_delta * fraction;
                    state <= STATE_OUT;
                end

                STATE_OUT: begin
                    out_valid <= 1'b1;
                    out_on <= pending_on;
                    out_source <= pending_source;
                    out_base_step <= low_step_latched
                        + ((interpolation_product + 40'd128) >> 8);
                    out_velocity <= pending_velocity;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
