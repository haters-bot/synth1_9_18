// 仅用于仿真的接口桩模块，用于语法和展开检查。
//
// 高云Advanced FIR生成的源文件采用厂商加密封装，ModelSim 10.6d无法解密。
// 本桩模块仅保留生成模块的端口位宽和方向，并且不会加入高云工程。
// 它不能替代FIR的行为仿真模型。
module fir_decimator_8x_ip(
    input  wire               clk,
    input  wire               rstn,
    output wire               fir_rfi_o,
    input  wire               fir_valid_i,
    input  wire               fir_sync_i,
    input  wire signed [15:0] fir_data_i,
    output wire               fir_valid_o,
    output wire               fir_sync_o,
    output wire signed [32:0] fir_data_o
);

    assign fir_rfi_o   = 1'b1;
    assign fir_valid_o = 1'b0;
    assign fir_sync_o  = 1'b0;
    assign fir_data_o  = 33'sd0;

endmodule
