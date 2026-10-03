// 256相位、16位有符号三角波查找模块。
//
// 相位布局：
//   0x00:      0
//   0x40: +32767
//   0x80:      0
//   0xC0: -32768
//
// 使用相位象限和线性斜坡生成等价波表数据，避免展开256项case。
module triangle_lut(
    input  wire [7:0]         addr,
    output reg signed [15:0]  data
);

    wire signed [15:0] quadrant_ramp;

    // 低6位每增加1，幅值增加512；最高值为32256。
    assign quadrant_ramp = $signed({1'b0, addr[5:0], 9'b0});

    always @(*) begin
        case (addr[7:6])
            2'b00: data = quadrant_ramp;
            2'b01: data = 16'sh7FFF - quadrant_ramp;
            2'b10: data = -quadrant_ramp;
            2'b11: data = 16'sh8000 + quadrant_ramp;
            default: data = 16'sd0;
        endcase
    end

endmodule
