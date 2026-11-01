// 六条滑条的完整前端：ADS1256扫描、滤波/Gate、连续音高映射和DDS步进转换。
// scheduler_ready应在OSC A/B调度器都空闲时拉高；输出事件会保持到被接收。
module ribbon_controller_6ch #(
    parameter integer SYS_CLK_HZ = 50000000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        adc_drdy_n,
    input  wire        adc_dout,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_din,
    output wire        adc_reset_n,

    input  wire        scheduler_ready,
    output wire        continuous_event_valid,
    output wire        continuous_event_on,
    output wire [2:0]  continuous_event_source,
    output wire [31:0] continuous_event_base_step,
    output wire [6:0]  continuous_event_velocity,
    output wire        adc_initialized
);

    wire sample_valid;
    wire sample_ready;
    wire [2:0] sample_channel;
    wire signed [23:0] sample_data;
    wire pitch_event_valid;
    wire pitch_event_ready;
    wire pitch_event_on;
    wire [2:0] pitch_event_source;
    wire [14:0] pitch_event_q8;
    wire [6:0] pitch_event_velocity;

    ads1256_scanner #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .CHANNEL_COUNT(6)
    ) u_ads1256_scanner (
        .clk(clk),
        .rst_n(rst_n),
        .adc_drdy_n(adc_drdy_n),
        .adc_dout(adc_dout),
        .adc_cs_n(adc_cs_n),
        .adc_sclk(adc_sclk),
        .adc_din(adc_din),
        .adc_reset_n(adc_reset_n),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .initialized(adc_initialized)
    );

    ribbon_pitch_processor #(
        .CHANNEL_COUNT(6)
    ) u_ribbon_pitch_processor (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .sample_ready(sample_ready),
        .event_valid(pitch_event_valid),
        .event_ready(pitch_event_ready),
        .event_on(pitch_event_on),
        .event_source(pitch_event_source),
        .event_pitch_q8(pitch_event_q8),
        .event_velocity(pitch_event_velocity)
    );

    ribbon_pitch_to_step u_ribbon_pitch_to_step (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(pitch_event_valid),
        .in_ready(pitch_event_ready),
        .in_on(pitch_event_on),
        .in_source(pitch_event_source),
        .in_pitch_q8(pitch_event_q8),
        .in_velocity(pitch_event_velocity),
        .out_valid(continuous_event_valid),
        .out_ready(scheduler_ready),
        .out_on(continuous_event_on),
        .out_source(continuous_event_source),
        .out_base_step(continuous_event_base_step),
        .out_velocity(continuous_event_velocity)
    );

endmodule
