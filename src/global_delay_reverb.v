// 全局效果器外壳。Delay 与 Reverb 始终在后台更新，切换模式时可保留尾音。
// 模式：0旁路，1 Delay，2 Reverb，3 Delay/Reverb等权并联。
module global_delay_reverb (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire [1:0]         effect_mode,
    input  wire [6:0]         delay_time,
    input  wire [6:0]         delay_feedback,
    input  wire [6:0]         delay_mix,
    input  wire [6:0]         reverb_size,
    input  wire [6:0]         reverb_decay,
    input  wire [6:0]         reverb_mix,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    reg busy;
    reg [1:0] mode_latched;
    reg signed [15:0] dry_sample_latched;
    reg signed [15:0] delay_result;
    reg signed [15:0] reverb_result;
    reg delay_done;
    reg reverb_done;

    wire delay_ready;
    wire reverb_ready;
    wire delay_valid;
    wire reverb_valid;
    wire signed [15:0] delay_sample;
    wire signed [15:0] reverb_sample;
    wire delay_overrun;
    wire reverb_overrun;
    wire accept_input = in_valid && in_ready;
    wire signed [16:0] parallel_sum =
        $signed({delay_result[15], delay_result})
        + $signed({reverb_result[15], reverb_result});
    wire signed [16:0] parallel_average = parallel_sum >>> 1;

    assign in_ready = !busy && delay_ready && reverb_ready;

    global_delay u_global_delay (
        .clk(clk), .rst_n(rst_n),
        .in_valid(accept_input), .sample_in(sample_in), .in_ready(delay_ready),
        .time_control(delay_time), .feedback_control(delay_feedback),
        .mix_control(delay_mix), .out_valid(delay_valid),
        .sample_out(delay_sample), .input_overrun(delay_overrun)
    );

    global_reverb u_global_reverb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(accept_input), .sample_in(sample_in), .in_ready(reverb_ready),
        .size_control(reverb_size), .decay_control(reverb_decay),
        .mix_control(reverb_mix), .out_valid(reverb_valid),
        .sample_out(reverb_sample), .input_overrun(reverb_overrun)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            mode_latched <= 2'd0;
            dry_sample_latched <= 16'sd0;
            delay_result <= 16'sd0;
            reverb_result <= 16'sd0;
            delay_done <= 1'b0;
            reverb_done <= 1'b0;
            out_valid <= 1'b0;
            sample_out <= 16'sd0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if ((in_valid && !in_ready) || delay_overrun || reverb_overrun)
                input_overrun <= 1'b1;

            if (accept_input) begin
                busy <= 1'b1;
                mode_latched <= effect_mode;
                dry_sample_latched <= sample_in;
                delay_done <= 1'b0;
                reverb_done <= 1'b0;
            end

            if (delay_valid) begin
                delay_result <= delay_sample;
                delay_done <= 1'b1;
            end
            if (reverb_valid) begin
                reverb_result <= reverb_sample;
                reverb_done <= 1'b1;
            end

            if (busy && delay_done && reverb_done) begin
                case (mode_latched)
                    2'd1: sample_out <= delay_result;
                    2'd2: sample_out <= reverb_result;
                    2'd3: sample_out <= parallel_average[15:0];
                    default: sample_out <= dry_sample_latched;
                endcase
                out_valid <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

endmodule

