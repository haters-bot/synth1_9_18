module basic_osc_v1(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        phase_reset,
    input  wire [6:0]  freq_addr,
    input  wire        cnt_enable,
    output wire [7:0]  tune_phase,
    output wire signed [15:0] sine_sample
);
    wire [31:0] phase_step;
    reg  [31:0] phase_acc;

    freq_lut freq_lut_inst (
        .addr(freq_addr),
        .data(phase_step)
    );

    // Advance the phase once per internal sample.
    // cnt_enable must be a one-clock-wide 768 kHz oversample tick.
    assign tune_phase = phase_acc[31:24];

    // The wavetable is addressed by the oscillator phase.  The sample is
    // held combinationally between phase updates and is therefore stable
    // for the complete audio sample interval.
    sine_lut sine_lut_inst (
        .addr (tune_phase),
        .data (sine_sample)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc <= 32'd0;
        else if (phase_reset)
            phase_acc <= 32'd0;
        else if (cnt_enable)
            phase_acc <= phase_acc + phase_step;
    end
endmodule
