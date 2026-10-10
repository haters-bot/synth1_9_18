// Acid波表同步双读口ROM。
// 地址格式：{frame_index[3:0], phase_index[7:0]}。
module acid_wavetable_rom(
    input  wire              clk,
    input  wire [11:0]       addr_a,
    input  wire [11:0]       addr_b,
    output reg signed [15:0] data_a,
    output reg signed [15:0] data_b
);

    // 提示综合器优先采用块RAM；实际映射必须以Gowin综合报告为准。
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [15:0] memory [0:4095];

    initial begin
        $readmemh("src/acid_wavetable_16x256.hex", memory);
    end

    always @(posedge clk) begin
        data_a <= memory[addr_a];
        data_b <= memory[addr_b];
    end

endmodule
