// 波表读取地址变换。原始32位相位累加器保持不变，因此Warp不会改变基音。
// mode=0：关闭；mode=1：PWM式分段相位弯曲；mode=2：1～8倍Sync。
module wavetable_phase_warp(
    input  wire [7:0] raw_address,
    input  wire [1:0] warp_mode,
    input  wire [6:0] warp_amount,
    output reg  [7:0] warped_address
);

    localparam [1:0] WARP_OFF  = 2'd0;
    localparam [1:0] WARP_PWM  = 2'd1;
    localparam [1:0] WARP_SYNC = 2'd2;

    // PWM使用到波形两端的三角距离产生连续、单调的分段线性映射。
    // amount=0时保持原地址；amount=127时，方波高电平占空比约为25%。
    wire [7:0] pwm_distance;
    wire [7:0] pwm_offset;
    wire [8:0] pwm_address_sum;

    assign pwm_distance = raw_address[7]
                        ? (8'hFF - raw_address)
                        : raw_address;
    // Sync深度映射为Q4.4倍率：amount=0对应1.0倍，127对应8.0倍。
    // 113/128近似把0～127线性映射为0～112个Q4.4增量。
    wire [14:0] warp_amount_extended;
    wire [14:0] sync_depth_scaled;
    wire [7:0] sync_factor_q4;
    wire [7:0] warp_multiplicand;
    wire [7:0] warp_multiplier;
    wire [15:0] warp_product;

    assign warp_amount_extended = {8'd0, warp_amount};
    assign sync_depth_scaled = (warp_amount_extended << 7)
                             - (warp_amount_extended << 4)
                             + warp_amount_extended;
    assign sync_factor_q4 = 8'd16 + sync_depth_scaled[14:7];

    // 两种模式互斥，先选择乘数再做一次8×8乘法，避免每个实体引擎
    // 为PWM和Sync分别推断一个乘法器。
    assign warp_multiplicand = (warp_mode == WARP_PWM)
                             ? pwm_distance : raw_address;
    assign warp_multiplier = (warp_mode == WARP_PWM)
                           ? {1'b0, warp_amount} : sync_factor_q4;
    assign warp_product = warp_multiplicand * warp_multiplier;
    assign pwm_offset = warp_product[14:7];
    assign pwm_address_sum = {1'b0, raw_address}
                           + {1'b0, pwm_offset};

    always @(*) begin
        case (warp_mode)
            WARP_PWM:
                warped_address = pwm_address_sum[7:0];
            WARP_SYNC:
                warped_address = warp_product[11:4];
            default:
                warped_address = raw_address;
        endcase
    end

endmodule
