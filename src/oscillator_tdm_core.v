// 一个物理波表振荡器由多个逻辑振荡器槽位共享。
//
// SLOTS_PER_ENGINE=32 时的调度顺序：
//
//   start_tick -> 槽位0 -> 槽位1 -> ... -> 槽位31 -> partial_valid
//
// 每个槽位拥有独立的32位相位累加器和相位步进。调度器已经把音符、
// Unison和Detune转换为普通相位步进，本实体不区分任务来源。
//
// 验证版本使用寄存器保存 phase_state，便于观察状态与调度。后续可替换为
// 同步BSRAM，但届时需要增加一级读流水线。
module oscillator_tdm_core #(
    parameter integer SLOTS_PER_ENGINE = 4,
    parameter integer PARTIAL_SUM_WIDTH = 24,
    parameter integer ENVELOPE_UPDATE_DIV = 16,
    parameter [15:0] ATTACK_STEP       = 16'd137,
    parameter [15:0] DECAY_STEP        = 16'd4,
    parameter [15:0] SUSTAIN_LEVEL     = 16'd45875,
    parameter integer RELEASE_SHIFT    = 12,
    parameter [15:0] RELEASE_END_LEVEL = 16'd1024
)(
    input  wire clk,
    input  wire rst_n,

    // 768 kHz内部采样时序中的单时钟脉冲。
    input  wire start_tick,

    // 清除所有槽位保存的相位，但不会改变音符与使能状态。
    input  wire clear_phase,
    input  wire [1:0] waveform_select,

    // 单槽位状态更新接口。全局任务调度器通过该接口修改指定槽位。
    input  wire                  task_update_valid,
    input  wire [7:0]            task_update_slot,
    input  wire [31:0]           task_update_phase_step,
    input  wire [6:0]            task_update_velocity,
    input  wire                  task_update_enable,
    input  wire                  task_update_phase_reset,

    // 本核心所处理的全部逻辑振荡器之和，尚未进行增益缩放。
    output reg signed [PARTIAL_SUM_WIDTH-1:0] partial_sum,
    output reg                                partial_valid,

    // 导出调度器状态，便于仿真以及后续片上调试。
    output reg       busy,
    output reg [7:0] debug_slot,
    output reg       debug_slot_commit,
    output reg       schedule_overrun,

    // Release归零后给全局任务调度器的单周期完成脉冲。
    output reg       task_idle_valid,
    output reg [7:0] task_idle_slot
);

    localparam [2:0] ENV_IDLE    = 3'd0;
    localparam [2:0] ENV_ATTACK  = 3'd1;
    localparam [2:0] ENV_DECAY   = 3'd2;
    localparam [2:0] ENV_SUSTAIN = 3'd3;
    localparam [2:0] ENV_RELEASE = 3'd4;
    localparam [15:0] ENVELOPE_MAX = 16'hFFFF;
    localparam [15:0] ENVELOPE_DIV_LAST = ENVELOPE_UPDATE_DIV - 1;

    reg [31:0] phase_state [0:SLOTS_PER_ENGINE-1];
    reg [31:0] phase_step_state [0:SLOTS_PER_ENGINE-1];
    reg                  enable_state [0:SLOTS_PER_ENGINE-1];
    reg                  gate_state [0:SLOTS_PER_ENGINE-1];
    reg [2:0]            envelope_stage [0:SLOTS_PER_ENGINE-1];
    reg [15:0]           envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [15:0]           velocity_envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [6:0]            velocity_state [0:SLOTS_PER_ENGINE-1];
    reg [7:0]  slot_index;
    reg signed [PARTIAL_SUM_WIDTH-1:0] mix_accumulator;
    reg [15:0] envelope_divider;
    reg        envelope_update_active;

    wire                  current_slot_enabled;
    wire [31:0]           current_phase;
    wire [31:0]           current_phase_step;
    wire [7:0]            current_wave_address;
    reg  signed [15:0]    current_wave_sample;
    wire signed [15:0]    sine_wave_sample;
    wire signed [15:0]    triangle_wave_sample;
    wire signed [15:0]    square_wave_sample;
    wire signed [15:0]    sawtooth_wave_sample;
    wire [2:0]            current_envelope_stage;
    wire [15:0]           current_envelope_level;
    wire [15:0]           current_velocity_envelope_level;
    wire [6:0]            current_velocity;
    wire [22:0]           velocity_product;
    wire [22:0]           velocity_rounded;
    wire [15:0]           velocity_scaled_envelope;
    wire signed [16:0]    current_wave_extended;
    wire signed [16:0]    current_envelope_gain;
    wire signed [33:0]    envelope_product;
    wire signed [33:0]    envelope_rounded;
    wire signed [33:0]    envelope_scaled;
    wire signed [15:0]    enveloped_wave_sample;
    wire [15:0]           current_release_delta;

    wire signed [PARTIAL_SUM_WIDTH-1:0] extended_sample;
    wire signed [PARTIAL_SUM_WIDTH-1:0] sum_with_current_slot;

    integer reset_index;

    assign current_slot_enabled = enable_state[slot_index];
    assign current_phase = phase_state[slot_index];
    assign current_phase_step = phase_step_state[slot_index];
    assign current_wave_address = current_phase[31:24];
    assign current_envelope_stage = envelope_stage[slot_index];
    assign current_envelope_level = envelope_level[slot_index];
    assign current_velocity_envelope_level
        = velocity_envelope_level[slot_index];
    assign current_velocity = velocity_state[slot_index];

    // MIDI力度采用近似Q0.7增益：velocity/128。最大力度127单独旁路，
    // 从而保持原有满幅输出；乘法结果只在包络更新时写回寄存器，避免
    // 与波形乘包络的音频路径形成两个乘法器的组合级联。
    assign velocity_product = current_envelope_level * current_velocity;
    assign velocity_rounded = velocity_product + 23'd64;
    assign velocity_scaled_envelope
        = (current_velocity == 7'd127)
        ? current_envelope_level
        : velocity_rounded[22:7];

    // 包络为无符号Q0.16增益。前置0扩展后显式转为正的有符号数，
    // 与16位有符号波形相乘，再算术右移16位恢复PCM量纲。
    assign current_wave_extended = $signed({current_wave_sample[15],
                                            current_wave_sample});
    assign current_envelope_gain
        = $signed({1'b0, current_velocity_envelope_level});
    assign envelope_product = $signed(current_wave_extended)
                            * $signed(current_envelope_gain);
    // 加半个Q0.16 LSB后再右移，避免直接算术截断对负半波产生偏置。
    assign envelope_rounded = envelope_product + 34'sd32768;
    assign envelope_scaled = envelope_rounded >>> 16;
    assign enveloped_wave_sample = envelope_scaled[15:0];
    assign current_release_delta
        = current_envelope_level >> RELEASE_SHIFT;

    // 一个物理引擎中的所有槽位共享下面四个波形读取单元。
    // 全局选择只改变采样来源，不改变槽位调度和相位累加时序。
    sine_lut u_shared_sine_lut (
        .addr(current_wave_address),
        .data(sine_wave_sample)
    );

    triangle_lut u_shared_triangle_lut (
        .addr(current_wave_address),
        .data(triangle_wave_sample)
    );

    square_lut u_shared_square_lut (
        .addr(current_wave_address),
        .data(square_wave_sample)
    );

    sawtooth_lut u_shared_sawtooth_lut (
        .addr(current_wave_address),
        .data(sawtooth_wave_sample)
    );

    always @(*) begin
        case (waveform_select)
            2'd0: current_wave_sample = sine_wave_sample;
            2'd1: current_wave_sample = triangle_wave_sample;
            2'd2: current_wave_sample = square_wave_sample;
            2'd3: current_wave_sample = sawtooth_wave_sample;
            default: current_wave_sample = square_wave_sample;
        endcase
    end

    assign extended_sample = current_slot_enabled
                           ? {{(PARTIAL_SUM_WIDTH-16){enveloped_wave_sample[15]}},
                              enveloped_wave_sample}
                           : {PARTIAL_SUM_WIDTH{1'b0}};

    assign sum_with_current_slot = mix_accumulator + extended_sample;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_index        <= 8'd0;
            mix_accumulator   <= {PARTIAL_SUM_WIDTH{1'b0}};
            partial_sum       <= {PARTIAL_SUM_WIDTH{1'b0}};
            partial_valid     <= 1'b0;
            busy              <= 1'b0;
            debug_slot        <= 8'd0;
            debug_slot_commit <= 1'b0;
            schedule_overrun  <= 1'b0;
            task_idle_valid  <= 1'b0;
            task_idle_slot   <= 8'd0;
            envelope_divider  <= 16'd0;
            envelope_update_active <= 1'b0;

            for (reset_index = 0;
                 reset_index < SLOTS_PER_ENGINE;
                 reset_index = reset_index + 1) begin
                phase_state[reset_index] <= 32'd0;
                phase_step_state[reset_index] <= 32'd0;
                enable_state[reset_index] <= 1'b0;
                gate_state[reset_index] <= 1'b0;
                envelope_stage[reset_index] <= ENV_IDLE;
                envelope_level[reset_index] <= 16'd0;
                velocity_envelope_level[reset_index] <= 16'd0;
                velocity_state[reset_index] <= 7'd0;
            end
        end else begin
            // 脉冲输出默认拉低，仅在提交槽位或完成一次引擎调度的对应时钟拉高。
            partial_valid     <= 1'b0;
            debug_slot_commit <= 1'b0;
            task_idle_valid  <= 1'b0;

            if (clear_phase) begin
                for (reset_index = 0;
                     reset_index < SLOTS_PER_ENGINE;
                     reset_index = reset_index + 1)
                    phase_state[reset_index] <= 32'd0;
            end

            // 上一内部采样的全部槽位处理完成前，不应到达新的内部采样请求。
            // 使用粘滞错误标志暴露这种情况，避免任务被静默丢弃。
            if (start_tick && busy)
                schedule_overrun <= 1'b1;

            if (!busy) begin
                if (start_tick) begin
                    // 此处仅启动调度：槽位0在随后的时钟周期内进行组合计算，
                    // 并在下一个时钟沿提交结果。
                    busy            <= 1'b1;
                    slot_index      <= 8'd0;
                    mix_accumulator <= {PARTIAL_SUM_WIDTH{1'b0}};

                    // 将一次包络更新请求保持整个32槽位调度，使所有声部在
                    // 同一个音频采样中各更新一次，而不是只更新某一个槽位。
                    if (ENVELOPE_UPDATE_DIV <= 1) begin
                        envelope_divider       <= 16'd0;
                        envelope_update_active <= 1'b1;
                    end else if (envelope_divider == ENVELOPE_DIV_LAST) begin
                        envelope_divider       <= 16'd0;
                        envelope_update_active <= 1'b1;
                    end else begin
                        envelope_divider       <= envelope_divider + 16'd1;
                        envelope_update_active <= 1'b0;
                    end
                end
            end else begin
                // 提交本时钟周期内完成计算的槽位。
                // debug_slot 指示当前正在提交的槽位。
                debug_slot        <= slot_index;
                debug_slot_commit <= 1'b1;

                if (current_slot_enabled && !clear_phase)
                    phase_state[slot_index]
                        <= current_phase + current_phase_step;

                if (current_slot_enabled && envelope_update_active) begin
                    // 缩放后的包络比原包络晚一个包络更新周期，默认配置下
                    // 约为20.8 us，不影响演奏响应，并切断乘法器级联路径。
                    velocity_envelope_level[slot_index]
                        <= velocity_scaled_envelope;
                    case (current_envelope_stage)
                        ENV_ATTACK: begin
                            if (!gate_state[slot_index]) begin
                                envelope_stage[slot_index] <= ENV_RELEASE;
                            end else if (current_envelope_level
                                         >= ENVELOPE_MAX - ATTACK_STEP) begin
                                envelope_level[slot_index] <= ENVELOPE_MAX;
                                envelope_stage[slot_index] <= ENV_DECAY;
                            end else begin
                                envelope_level[slot_index]
                                    <= current_envelope_level + ATTACK_STEP;
                            end
                        end

                        ENV_DECAY: begin
                            if (!gate_state[slot_index]) begin
                                envelope_stage[slot_index] <= ENV_RELEASE;
                            end else if (current_envelope_level
                                         <= SUSTAIN_LEVEL) begin
                                envelope_level[slot_index] <= SUSTAIN_LEVEL;
                                envelope_stage[slot_index] <= ENV_SUSTAIN;
                            end else if ((current_envelope_level
                                          - SUSTAIN_LEVEL) <= DECAY_STEP) begin
                                envelope_level[slot_index] <= SUSTAIN_LEVEL;
                                envelope_stage[slot_index] <= ENV_SUSTAIN;
                            end else begin
                                envelope_level[slot_index]
                                    <= current_envelope_level - DECAY_STEP;
                            end
                        end

                        ENV_SUSTAIN: begin
                            envelope_level[slot_index] <= SUSTAIN_LEVEL;
                            if (!gate_state[slot_index])
                                envelope_stage[slot_index] <= ENV_RELEASE;
                        end

                        ENV_RELEASE: begin
                            // 指数Release：每次减去当前电平的固定比例。
                            // 低于约-60 dB的阈值后直接归零，避免整数长尾。
                            if (current_envelope_level <= RELEASE_END_LEVEL) begin
                                envelope_level[slot_index] <= 16'd0;
                                envelope_stage[slot_index] <= ENV_IDLE;
                                enable_state[slot_index] <= 1'b0;
                                task_idle_valid <= 1'b1;
                                task_idle_slot  <= slot_index;
                            end else if (current_release_delta == 16'd0) begin
                                envelope_level[slot_index]
                                    <= current_envelope_level - 16'd1;
                            end else begin
                                envelope_level[slot_index]
                                    <= current_envelope_level
                                     - current_release_delta;
                            end
                        end

                        default: begin
                            envelope_level[slot_index] <= 16'd0;
                            envelope_stage[slot_index] <= ENV_IDLE;
                            enable_state[slot_index] <= 1'b0;
                        end
                    endcase
                end

                if (slot_index == (SLOTS_PER_ENGINE-1)) begin
                    // 由于 mix_accumulator 的非阻塞赋值要在时钟沿后才生效，
                    // 因此这里直接把最后一个槽位计入输出结果。
                    partial_sum     <= sum_with_current_slot;
                    partial_valid   <= 1'b1;
                    mix_accumulator <= {PARTIAL_SUM_WIDTH{1'b0}};
                    slot_index      <= 8'd0;
                    busy            <= 1'b0;
                end else begin
                    mix_accumulator <= sum_with_current_slot;
                    slot_index      <= slot_index + 8'd1;
                end
            end

            // 配置写入放在调度逻辑之后，使单槽位相位复位在同拍冲突时优先。
            if (task_update_valid
                && (task_update_slot < SLOTS_PER_ENGINE)) begin
                phase_step_state[task_update_slot]
                    <= task_update_phase_step;

                if (task_update_enable) begin
                    enable_state[task_update_slot] <= 1'b1;
                    gate_state[task_update_slot] <= 1'b1;
                    envelope_stage[task_update_slot] <= ENV_ATTACK;
                    envelope_level[task_update_slot] <= 16'd0;
                    velocity_envelope_level[task_update_slot] <= 16'd0;
                    velocity_state[task_update_slot]
                        <= task_update_velocity;

                    if (task_update_phase_reset && !clear_phase)
                        phase_state[task_update_slot] <= 32'd0;
                end else if (enable_state[task_update_slot]) begin
                    // Note Off只关闭Gate并进入Release；振荡器继续运行到包络归零。
                    gate_state[task_update_slot] <= 1'b0;
                    envelope_stage[task_update_slot] <= ENV_RELEASE;
                end
            end
        end
    end

endmodule
