// 组合兼容接口与两级流水接口共用同一套变形公式。
module wavetable_phase_warp(
    input wire [7:0] raw_address,
    input wire [3:0] warp_mode,
    input wire [6:0] warp_amount,
    output wire [7:0] warped_address
);
    wire signed [9:0] a;
    wire signed [8:0] b;
    wire [7:0] target, mask;
    wire signed [18:0] product = a * b;
    wavetable_warp_prepare u_prepare(raw_address, warp_mode, warp_amount, a, b, target, mask);
    wavetable_warp_finish u_finish(raw_address, warp_mode, warp_amount, target, mask, product, warped_address);
endmodule

// 接收原始地址后，第一级保存操作数，第二级保存乘积；每拍可接收一个地址。
// 槽位valid、取消标志由TDM核心以相同级数推进。
module wavetable_phase_warp_pipeline(
    input wire clk, rst_n,
    input wire [7:0] raw_address,
    input wire [3:0] warp_mode,
    input wire [6:0] warp_amount,
    output wire [7:0] warped_address
);
    wire signed [9:0] a;
    wire signed [8:0] b;
    wire [7:0] target, mask;
    reg signed [9:0] a1;
    reg signed [8:0] b1;
    reg signed [18:0] product2;
    reg [7:0] raw1, raw2, target1, target2, mask1, mask2;
    reg [3:0] mode1, mode2;
    reg [6:0] amount1, amount2;
    wavetable_warp_prepare u_prepare(raw_address, warp_mode, warp_amount, a, b, target, mask);
    wavetable_warp_finish u_finish(raw2, mode2, amount2, target2, mask2, product2, warped_address);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a1 <= 0; b1 <= 0; product2 <= 0;
            raw1 <= 0; raw2 <= 0; target1 <= 0; target2 <= 0;
            mask1 <= 0; mask2 <= 0; mode1 <= 0; mode2 <= 0;
            amount1 <= 0; amount2 <= 0;
        end else begin
            a1 <= a; b1 <= b;
            raw1 <= raw_address; target1 <= target; mask1 <= mask;
            mode1 <= warp_mode; amount1 <= warp_amount;
            product2 <= a1 * b1;
            raw2 <= raw1; target2 <= target1; mask2 <= mask1;
            mode2 <= mode1; amount2 <= amount1;
        end
    end
endmodule

module wavetable_warp_prepare(
    input wire [7:0] raw_address,
    input wire [3:0] warp_mode,
    input wire [6:0] warp_amount,
    output reg signed [9:0] multiplier_a,
    output reg signed [8:0] multiplier_b,
    output reg [7:0] bend_target,
    output reg [7:0] quantize_mask
);
    localparam [3:0] WARP_OFF          = 4'd0;
    localparam [3:0] WARP_PWM          = 4'd1;
    localparam [3:0] WARP_SYNC         = 4'd2;
    localparam [3:0] WARP_BEND_PLUS    = 4'd3;
    localparam [3:0] WARP_BEND_MINUS   = 4'd4;
    localparam [3:0] WARP_BEND_BOTH    = 4'd5;
    localparam [3:0] WARP_ASYM_PLUS    = 4'd6;
    localparam [3:0] WARP_ASYM_MINUS   = 4'd7;
    localparam [3:0] WARP_ASYM_BOTH    = 4'd8;
    localparam [3:0] WARP_FLIP         = 4'd9;
    localparam [3:0] WARP_MIRROR       = 4'd10;
    localparam [3:0] WARP_QUANTIZE     = 4'd11;

    wire [7:0] pwm_distance;
    wire [14:0] warp_amount_extended, sync_depth_scaled;
    wire [7:0] sync_factor_q4;
    assign pwm_distance = raw_address[7]
                        ? (8'hFF - raw_address)
                        : raw_address;

    // Sync深度为Q4.4倍率：amount=0对应1.0倍，127对应8.0倍。
    assign warp_amount_extended = {8'd0, warp_amount};
    assign sync_depth_scaled = (warp_amount_extended << 7)
                             - (warp_amount_extended << 4)
                             + warp_amount_extended;
    assign sync_factor_q4 = 8'd16 + sync_depth_scaled[14:7];

    // Bend和Asym的最大深度目标曲线由斜率0.5和1.5的线段组成。
    // 当前地址再按amount线性靠近目标曲线，因而amount=0严格旁路。
    always @(*) begin
        bend_target = raw_address;
        case (warp_mode)
            WARP_BEND_PLUS: begin
                if (!raw_address[7])
                    bend_target = raw_address >> 1;
                else if (raw_address == 8'hFF)
                    bend_target = 8'hFF;
                else
                    bend_target = 8'd64
                                + (raw_address - 8'd128)
                                + ((raw_address - 8'd128) >> 1);
            end

            WARP_BEND_MINUS: begin
                if (!raw_address[7])
                    bend_target = raw_address + (raw_address >> 1);
                else
                    bend_target = 8'd192
                                + ((raw_address - 8'd128) >> 1);
            end

            WARP_BEND_BOTH: begin
                case (raw_address[7:6])
                    2'd0: bend_target = raw_address >> 1;
                    2'd1: bend_target = 8'd32
                                      + (raw_address - 8'd64)
                                      + ((raw_address - 8'd64) >> 1);
                    2'd2: bend_target = 8'd128
                                      + (raw_address - 8'd128)
                                      + ((raw_address - 8'd128) >> 1);
                    default: bend_target = 8'd224
                                               + ((raw_address - 8'd192) >> 1);
                endcase
            end

            WARP_ASYM_PLUS: begin
                if (raw_address < 8'd64)
                    bend_target = raw_address + (raw_address >> 1);
                else if (!raw_address[7])
                    bend_target = 8'd96
                                + ((raw_address - 8'd64) >> 1);
            end

            WARP_ASYM_MINUS: begin
                if ((raw_address >= 8'd128) && (raw_address < 8'd192))
                    bend_target = 8'd128
                                + ((raw_address - 8'd128) >> 1);
                else if (raw_address >= 8'd192) begin
                    if (raw_address == 8'hFF)
                        bend_target = 8'hFF;
                    else
                        bend_target = 8'd160
                                    + (raw_address - 8'd192)
                                    + ((raw_address - 8'd192) >> 1);
                end
            end

            WARP_ASYM_BOTH: begin
                if (raw_address < 8'd64)
                    bend_target = raw_address + (raw_address >> 1);
                else if (raw_address < 8'd128)
                    bend_target = 8'd96
                                + ((raw_address - 8'd64) >> 1);
                else if (raw_address < 8'd192)
                    bend_target = 8'd128
                                + ((raw_address - 8'd128) >> 1);
                else if (raw_address == 8'hFF)
                    bend_target = 8'hFF;
                else
                    bend_target = 8'd160
                                + (raw_address - 8'd192)
                                + ((raw_address - 8'd192) >> 1);
            end

            WARP_FLIP:
                bend_target = 8'hFF - raw_address;

            WARP_MIRROR:
                bend_target = raw_address[7]
                            ? ((8'hFF - raw_address) << 1)
                            : (raw_address << 1);

            default:
                bend_target = raw_address;
        endcase
    end

    // PWM、Sync和曲线混合互斥，因此可以共用同一个乘法器。
    always @(*) begin
        if (warp_mode == WARP_PWM) begin
            multiplier_a = $signed({2'b00, pwm_distance});
            multiplier_b = $signed({2'b00, warp_amount});
        end else if (warp_mode == WARP_SYNC) begin
            multiplier_a = $signed({2'b00, raw_address});
            multiplier_b = $signed({1'b0, sync_factor_q4});
        end else begin
            multiplier_a = $signed({2'b00, bend_target})
                         - $signed({2'b00, raw_address});
            multiplier_b = $signed({2'b00, warp_amount});
        end
    end

    // Quantize逐步清除地址低位；最大深度只保留最高位，得到两级波形。
    always @(*) begin
        case (warp_amount[6:4])
            3'd0: quantize_mask = 8'hFF;
            3'd1: quantize_mask = 8'hFE;
            3'd2: quantize_mask = 8'hFC;
            3'd3: quantize_mask = 8'hF8;
            3'd4: quantize_mask = 8'hF0;
            3'd5: quantize_mask = 8'hE0;
            3'd6: quantize_mask = 8'hC0;
            default: quantize_mask = 8'h80;
        endcase
    end

endmodule

module wavetable_warp_finish(
    input wire [7:0] raw_address,
    input wire [3:0] warp_mode,
    input wire [6:0] warp_amount,
    input wire [7:0] bend_target, quantize_mask,
    input wire signed [18:0] shared_product,
    output reg [7:0] warped_address
);
    localparam [3:0] WARP_OFF          = 4'd0;
    localparam [3:0] WARP_PWM          = 4'd1;
    localparam [3:0] WARP_SYNC         = 4'd2;
    localparam [3:0] WARP_BEND_PLUS    = 4'd3;
    localparam [3:0] WARP_BEND_MINUS   = 4'd4;
    localparam [3:0] WARP_BEND_BOTH    = 4'd5;
    localparam [3:0] WARP_ASYM_PLUS    = 4'd6;
    localparam [3:0] WARP_ASYM_MINUS   = 4'd7;
    localparam [3:0] WARP_ASYM_BOTH    = 4'd8;
    localparam [3:0] WARP_FLIP         = 4'd9;
    localparam [3:0] WARP_MIRROR       = 4'd10;
    localparam [3:0] WARP_QUANTIZE     = 4'd11;

    wire signed [18:0] bend_scaled_delta;
    wire signed [10:0] bend_address_sum;
    wire [7:0] pwm_offset;
    wire [8:0] pwm_address_sum;
    assign pwm_offset = shared_product[14:7];
    assign pwm_address_sum = {1'b0, raw_address}
                           + {1'b0, pwm_offset};
    assign bend_scaled_delta = shared_product >>> 7;
    assign bend_address_sum = $signed({3'b000, raw_address})
                            + bend_scaled_delta[10:0];

    always @(*) begin
        case (warp_mode)
            WARP_PWM:
                warped_address = pwm_address_sum[7:0];
            WARP_SYNC:
                warped_address = shared_product[11:4];
            WARP_QUANTIZE:
                warped_address = raw_address & quantize_mask;
            WARP_BEND_PLUS,
            WARP_BEND_MINUS,
            WARP_BEND_BOTH,
            WARP_ASYM_PLUS,
            WARP_ASYM_MINUS,
            WARP_ASYM_BOTH,
            WARP_FLIP,
            WARP_MIRROR:
                warped_address = (warp_amount == 7'd127)
                               ? bend_target : bend_address_sum[7:0];
            default:
                warped_address = raw_address;
        endcase
    end

endmodule
