// 96 kHz全局效果链：Distortion -> Phaser -> Chorus -> Delay/Reverb -> Compressor。
// busy覆盖整条链，避免上游在下游尚未完成时接受下一份样本。
module global_effects (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,

    input  wire               distortion_enable,
    input  wire [1:0]         distortion_type,
    input  wire [6:0]         distortion_drive,
    input  wire [6:0]         distortion_tone,
    input  wire [6:0]         distortion_mix,

    input  wire               phaser_enable,
    input  wire [6:0]         phaser_rate,
    input  wire [6:0]         phaser_depth,
    input  wire [6:0]         phaser_center,
    input  wire [6:0]         phaser_feedback,
    input  wire [6:0]         phaser_mix,

    input  wire               chorus_enable,
    input  wire [6:0]         chorus_rate,
    input  wire [6:0]         chorus_depth,
    input  wire [6:0]         chorus_delay,
    input  wire [6:0]         chorus_feedback,
    input  wire [6:0]         chorus_mix,

    input  wire [1:0]         effect_mode,
    input  wire [6:0]         delay_time,
    input  wire [6:0]         delay_feedback,
    input  wire [6:0]         delay_mix,
    input  wire [6:0]         reverb_size,
    input  wire [6:0]         reverb_decay,
    input  wire [6:0]         reverb_mix,

    input  wire               compressor_enable,
    input  wire [6:0]         compressor_threshold,
    input  wire [6:0]         compressor_ratio,
    input  wire [6:0]         compressor_attack,
    input  wire [6:0]         compressor_release,
    input  wire [6:0]         compressor_makeup,
    input  wire [6:0]         compressor_mix,

    output wire               out_valid,
    output wire signed [15:0] sample_out,
    output reg                input_overrun
);

    reg chain_busy;
    wire accept_input = in_valid && in_ready;

    wire distortion_ready;
    wire distortion_valid;
    wire signed [15:0] distortion_sample;
    wire distortion_overrun;
    wire phaser_ready;
    wire phaser_valid;
    wire signed [15:0] phaser_sample;
    wire phaser_overrun;
    wire chorus_ready;
    wire chorus_valid;
    wire signed [15:0] chorus_sample;
    wire chorus_overrun;
    wire delay_reverb_ready;
    wire delay_reverb_valid;
    wire signed [15:0] delay_reverb_sample;
    wire delay_reverb_overrun;
    wire compressor_ready;
    wire compressor_valid;
    wire signed [15:0] compressor_sample;
    wire compressor_overrun;

    assign in_ready = !chain_busy
                    && distortion_ready
                    && phaser_ready
                    && chorus_ready
                    && delay_reverb_ready
                    && compressor_ready;
    assign out_valid = compressor_valid;
    assign sample_out = compressor_sample;

    global_distortion u_global_distortion (
        .clk(clk), .rst_n(rst_n),
        .in_valid(accept_input), .sample_in(sample_in),
        .in_ready(distortion_ready),
        .enable(distortion_enable), .distortion_type(distortion_type),
        .drive_control(distortion_drive), .tone_control(distortion_tone),
        .mix_control(distortion_mix),
        .out_valid(distortion_valid), .sample_out(distortion_sample),
        .input_overrun(distortion_overrun)
    );

    global_phaser u_global_phaser (
        .clk(clk), .rst_n(rst_n),
        .in_valid(distortion_valid), .sample_in(distortion_sample),
        .in_ready(phaser_ready),
        .enable(phaser_enable), .rate_control(phaser_rate),
        .depth_control(phaser_depth), .center_control(phaser_center),
        .feedback_control(phaser_feedback), .mix_control(phaser_mix),
        .out_valid(phaser_valid), .sample_out(phaser_sample),
        .input_overrun(phaser_overrun)
    );

    global_chorus u_global_chorus (
        .clk(clk), .rst_n(rst_n),
        .in_valid(phaser_valid), .sample_in(phaser_sample),
        .in_ready(chorus_ready),
        .enable(chorus_enable), .rate_control(chorus_rate),
        .depth_control(chorus_depth), .delay_control(chorus_delay),
        .feedback_control(chorus_feedback), .mix_control(chorus_mix),
        .out_valid(chorus_valid), .sample_out(chorus_sample),
        .input_overrun(chorus_overrun)
    );

    global_delay_reverb u_global_delay_reverb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(chorus_valid), .sample_in(chorus_sample),
        .in_ready(delay_reverb_ready), .effect_mode(effect_mode),
        .delay_time(delay_time), .delay_feedback(delay_feedback),
        .delay_mix(delay_mix), .reverb_size(reverb_size),
        .reverb_decay(reverb_decay), .reverb_mix(reverb_mix),
        .out_valid(delay_reverb_valid), .sample_out(delay_reverb_sample),
        .input_overrun(delay_reverb_overrun)
    );

    global_compressor u_global_compressor (
        .clk(clk), .rst_n(rst_n),
        .in_valid(delay_reverb_valid), .sample_in(delay_reverb_sample),
        .in_ready(compressor_ready),
        .enable(compressor_enable),
        .threshold_control(compressor_threshold),
        .ratio_control(compressor_ratio),
        .attack_control(compressor_attack),
        .release_control(compressor_release),
        .makeup_control(compressor_makeup),
        .mix_control(compressor_mix),
        .out_valid(compressor_valid), .sample_out(compressor_sample),
        .input_overrun(compressor_overrun)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chain_busy <= 1'b0;
            input_overrun <= 1'b0;
        end else begin
            if (accept_input)
                chain_busy <= 1'b1;
            if (compressor_valid)
                chain_busy <= 1'b0;
            if ((in_valid && !in_ready)
                || distortion_overrun || phaser_overrun || chorus_overrun
                || delay_reverb_overrun || compressor_overrun)
                input_overrun <= 1'b1;
        end
    end

endmodule
