// 256相位、16位有符号锯齿波查找模块。
//
// 输出从-32640线性上升到+32640，正负平均值相同，因此没有直流偏置。
// 当前为非带限诊断波形；高音区的混叠主要由768 kHz过采样和FIR抑制。
module sawtooth_lut(
    input  wire [7:0]         addr,
    output wire signed [15:0] data
);

    wire signed [16:0] centered_ramp;

    assign centered_ramp = $signed({1'b0, addr, 8'b0}) - 17'sd32640;
    assign data = centered_ramp[15:0];

endmodule
