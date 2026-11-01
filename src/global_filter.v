// 全局滤波器统一外壳：使用基础SVF并完成Dry/Wet混合。
// 所有参数都在接收输入样本时锁存，控制值在运算途中变化不会破坏当前样本。
module global_filter(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,

    input  wire [2:0]         filter_mode,
    input  wire [14:0]        cutoff_control_q8,
    input  wire [6:0]         resonance_control,
    input  wire [6:0]         mix_control,

    output reg                out_valid,
    output reg  signed [15:0] sample_out,
    output reg                input_overrun
);

    reg busy;
    // 先保存乘法结果，再完成干湿求和，端点仍逐位旁路。
    reg mix_pending;
    reg signed [23:0] mix_registered;
    reg signed [15:0] wet_registered;
    reg signed [15:0] dry_sample_latched;
    reg [6:0] mix_latched;

    wire accept_input;
    wire svf_in_valid;
    wire svf_in_ready;
    wire svf_out_valid;
    wire signed [15:0] svf_sample_out;
    wire svf_input_overrun;

    wire signed [15:0] selected_wet_sample;
    wire selected_output_valid;
    wire signed [16:0] wet_dry_difference;
    wire signed [23:0] mix_product;
    wire signed [17:0] mixed_sample_wide;

    assign in_ready = !busy && svf_in_ready;
    assign accept_input = in_valid && in_ready;
    assign svf_in_valid = accept_input;
    assign selected_wet_sample = svf_sample_out;
    assign selected_output_valid = svf_out_valid;
    assign wet_dry_difference =
        $signed({selected_wet_sample[15], selected_wet_sample})
        - $signed({dry_sample_latched[15], dry_sample_latched});
    assign mix_product = wet_dry_difference * $signed({1'b0, mix_latched});
    assign mixed_sample_wide =
        $signed({{2{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_registered) >>> 7);

    global_svf_filter u_global_svf_filter (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_valid         (svf_in_valid),
        .sample_in        (sample_in),
        .in_ready         (svf_in_ready),
        .filter_mode      (filter_mode),
        .cutoff_control   (cutoff_control_q8[14:8]),
        .resonance_control(resonance_control),
        .out_valid        (svf_out_valid),
        .sample_out       (svf_sample_out),
        .input_overrun    (svf_input_overrun)
    );

    function signed [15:0] saturate_s18_to_s16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767)
                saturate_s18_to_s16 = 16'sh7FFF;
            else if (value < -18'sd32768)
                saturate_s18_to_s16 = 16'sh8000;
            else
                saturate_s18_to_s16 = value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy                    <= 1'b0;
            mix_pending <= 0; mix_registered <= 0; wet_registered <= 0;
            dry_sample_latched      <= 16'sd0;
            mix_latched             <= 7'd127;
            out_valid               <= 1'b0;
            sample_out              <= 16'sd0;
            input_overrun           <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            mix_pending <= 1'b0;

            if (in_valid && !in_ready)
                input_overrun <= 1'b1;
            if (svf_input_overrun)
                input_overrun <= 1'b1;

            if (accept_input) begin
                busy                  <= 1'b1;
                dry_sample_latched    <= sample_in;
                mix_latched           <= mix_control;
            end

            if (selected_output_valid && busy) begin
                mix_registered <= mix_product;
                wet_registered <= selected_wet_sample;
                mix_pending <= 1'b1;
            end
            if (mix_pending) begin
                // Mix=0和127单独处理，确保两个端点逐位精确。
                if (mix_latched == 7'd0) begin
                    sample_out <= dry_sample_latched;
                end else if (mix_latched == 7'd127) begin
                    sample_out <= wet_registered;
                end else begin
                    sample_out <= saturate_s18_to_s16(mixed_sample_wide);
                end
                out_valid <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

endmodule
