// 在固定数量的音频样本内，把参数从当前值线性移动到新目标。
// INTERPOLATION_SAMPLES必须为2的幂；当前512点对应96 kHz下约5.33 ms。
// 使用商和余数的Bresenham分配方法，避免综合出除法器或乘法器。
module parameter_linear_interpolator #(
    parameter integer VALUE_WIDTH = 15,
    parameter integer INTERPOLATION_SHIFT = 9,
    parameter [VALUE_WIDTH-1:0] RESET_VALUE = {VALUE_WIDTH{1'b0}}
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   sample_tick,
    input  wire                   target_valid,
    input  wire [VALUE_WIDTH-1:0] target_value,
    output reg  [VALUE_WIDTH-1:0] current_value,
    output wire                   busy
);

    localparam integer COUNT_WIDTH = INTERPOLATION_SHIFT + 1;

    reg [VALUE_WIDTH-1:0] target_latched;
    reg [VALUE_WIDTH-1:0] base_step;
    reg [INTERPOLATION_SHIFT-1:0] remainder_step;
    reg [INTERPOLATION_SHIFT-1:0] remainder_accumulator;
    reg [COUNT_WIDTH-1:0] samples_remaining;
    reg direction_up;

    wire [VALUE_WIDTH-1:0] target_difference;
    wire [INTERPOLATION_SHIFT:0] remainder_sum;
    wire [VALUE_WIDTH-1:0] step_this_sample;

    assign target_difference = (target_value >= current_value)
                             ? target_value - current_value
                             : current_value - target_value;
    assign remainder_sum = {1'b0, remainder_accumulator}
                         + {1'b0, remainder_step};
    assign step_this_sample = base_step
                            + {{(VALUE_WIDTH-1){1'b0}},
                               remainder_sum[INTERPOLATION_SHIFT]};
    assign busy = (samples_remaining != {COUNT_WIDTH{1'b0}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_value         <= RESET_VALUE;
            target_latched        <= RESET_VALUE;
            base_step             <= {VALUE_WIDTH{1'b0}};
            remainder_step        <= {INTERPOLATION_SHIFT{1'b0}};
            remainder_accumulator <= {INTERPOLATION_SHIFT{1'b0}};
            samples_remaining     <= {COUNT_WIDTH{1'b0}};
            direction_up          <= 1'b1;
        end else if (target_valid) begin
            target_latched        <= target_value;
            direction_up          <= (target_value >= current_value);
            base_step             <= target_difference
                                   >> INTERPOLATION_SHIFT;
            remainder_step        <= target_difference[
                INTERPOLATION_SHIFT-1:0
            ];
            remainder_accumulator <= {INTERPOLATION_SHIFT{1'b0}};
            samples_remaining     <= {1'b1,
                                      {INTERPOLATION_SHIFT{1'b0}}};
        end else if (sample_tick && busy) begin
            if (samples_remaining == {{(COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
                current_value         <= target_latched;
                remainder_accumulator <= {INTERPOLATION_SHIFT{1'b0}};
                samples_remaining     <= {COUNT_WIDTH{1'b0}};
            end else begin
                current_value <= direction_up
                               ? current_value + step_this_sample
                               : current_value - step_this_sample;
                remainder_accumulator
                    <= remainder_sum[INTERPOLATION_SHIFT-1:0];
                samples_remaining <= samples_remaining
                                   - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end

endmodule
