// Acid波表单周期请求接口。
// req_valid所在时钟沿锁存地址；下一拍sample_valid有效并输出帧间插值结果。
module acid_wavetable_reader(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              req_valid,
    input  wire [7:0]        phase_address,
    input  wire [6:0]        wt_position,
    output reg               sample_valid,
    output wire signed [15:0] sample_data
);

    wire [3:0] current_frame;
    wire [3:0] next_frame;
    wire [11:0] current_address;
    wire [11:0] next_address;
    wire signed [15:0] current_sample;
    wire signed [15:0] next_sample;

    reg [2:0] fraction_d1;
    wire signed [16:0] current_extended;
    wire signed [16:0] sample_difference;
    wire signed [3:0] fraction_signed;
    wire signed [20:0] interpolation_product;
    wire signed [17:0] interpolation_sum;

    assign current_frame = wt_position[6:3];
    assign next_frame = (current_frame == 4'd15)
                      ? 4'd15 : current_frame + 4'd1;
    assign current_address = {current_frame, phase_address};
    assign next_address = {next_frame, phase_address};

    acid_wavetable_rom u_acid_wavetable_rom (
        .clk   (clk),
        .addr_a(current_address),
        .addr_b(next_address),
        .data_a(current_sample),
        .data_b(next_sample)
    );

    assign current_extended
        = $signed({current_sample[15], current_sample});
    assign sample_difference
        = $signed({next_sample[15], next_sample}) - current_extended;
    assign fraction_signed = $signed({1'b0, fraction_d1});
    assign interpolation_product = sample_difference * fraction_signed;
    assign interpolation_sum = current_extended
                             + (interpolation_product >>> 3);
    assign sample_data = interpolation_sum[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fraction_d1 <= 3'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= req_valid;
            if (req_valid)
                fraction_d1 <= wt_position[2:0];
        end
    end

endmodule
