// 把7位外部ADSR控制值转换为FPGA包络核心使用的定点参数。
//
// 时间控制按近似指数刻度映射。每增加8个控制值，阶段时间约翻倍；
// 控制值0约为1 ms，控制值127约为58 s。包络核心以48 kHz更新，
// phase_step表示一个更新周期内32位阶段进度的增量。
module adsr_parameter_mapper(
    input  wire [6:0] attack_control,
    input  wire [6:0] decay_control,
    input  wire [6:0] sustain_control,
    input  wire [6:0] release_control,
    output wire [31:0] attack_phase_step,
    output wire [31:0] decay_phase_step,
    output wire [15:0] sustain_level,
    output wire [31:0] release_phase_step
);

    // round(2^32 / (0.001 s * 48000 Hz))，对应约1 ms阶段时间。
    localparam [31:0] BASE_PHASE_STEP = 32'd89478485;

    function [31:0] time_control_to_step;
        input [6:0] control_value;
        reg [3:0] octave;
        reg [2:0] fine;
        reg [31:0] octave_step;
        reg [31:0] half_step;
        reg [34:0] fine_product;
        reg [31:0] mapped_step;
        begin
            octave = control_value[6:3];
            fine = control_value[2:0];
            octave_step = BASE_PHASE_STEP >> octave;
            half_step = octave_step >> 1;
            fine_product = half_step * fine;
            mapped_step = octave_step - (fine_product >> 3);
            time_control_to_step = (mapped_step == 32'd0)
                                 ? 32'd1 : mapped_step;
        end
    endfunction

    assign attack_phase_step = time_control_to_step(attack_control);
    assign decay_phase_step = time_control_to_step(decay_control);
    assign release_phase_step = time_control_to_step(release_control);

    // 516 = 512 + 4，使0～126近似线性映射到Q0.16；127单独钳位满幅。
    assign sustain_level = (sustain_control == 7'd127)
                         ? 16'hFFFF
                         : ({9'd0, sustain_control} << 9)
                           + ({9'd0, sustain_control} << 2);

endmodule
