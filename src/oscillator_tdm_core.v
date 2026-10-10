// 一个物理波表振荡器由多个逻辑振荡器槽位共享。
//
// 同步波表ROM需要一拍读取延迟，因此调度分成两个并行阶段：
//   发出阶段：每拍读取一个槽位状态，并向波表ROM提交地址；
//   提交阶段：下一拍取得波表数据，更新该槽位并累加采样。
//
// 流水线填满后仍然每拍处理一个槽位。SLOTS_PER_ENGINE=8时，
// 一次内部采样从start_tick到partial_valid需要10拍左右，远小于
// 50 MHz系统时钟下两个768 kHz采样脉冲之间约65拍的预算。
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
    input  wire start_tick,
    input  wire clear_phase,
    input  wire [2:0] waveform_select,
    input  wire [6:0] wt_position,

    input  wire                  task_update_valid,
    input  wire [7:0]            task_update_slot,
    input  wire [31:0]           task_update_phase_step,
    input  wire [6:0]            task_update_velocity,
    input  wire                  task_update_enable,
    input  wire                  task_update_phase_reset,

    output reg signed [PARTIAL_SUM_WIDTH-1:0] partial_sum,
    output reg                                partial_valid,
    output reg       busy,
    output reg [7:0] debug_slot,
    output reg       debug_slot_commit,
    output reg       schedule_overrun,
    output reg       task_idle_valid,
    output reg [7:0] task_idle_slot
);

    localparam [2:0] ENV_IDLE    = 3'd0;
    localparam [2:0] ENV_ATTACK  = 3'd1;
    localparam [2:0] ENV_DECAY   = 3'd2;
    localparam [2:0] ENV_SUSTAIN = 3'd3;
    localparam [2:0] ENV_RELEASE = 3'd4;
    localparam [2:0] WAVE_ACID   = 3'd4;
    localparam [15:0] ENVELOPE_MAX = 16'hFFFF;
    localparam [15:0] ENVELOPE_DIV_LAST = ENVELOPE_UPDATE_DIV - 1;

    reg [31:0] phase_state [0:SLOTS_PER_ENGINE-1];
    reg [31:0] phase_step_state [0:SLOTS_PER_ENGINE-1];
    reg        enable_state [0:SLOTS_PER_ENGINE-1];
    reg        gate_state [0:SLOTS_PER_ENGINE-1];
    reg [2:0]  envelope_stage [0:SLOTS_PER_ENGINE-1];
    reg [15:0] envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [15:0] velocity_envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [6:0]  velocity_state [0:SLOTS_PER_ENGINE-1];

    reg [7:0] issue_slot;
    reg       issue_active;
    reg [2:0] waveform_select_batch;
    reg [6:0] wt_position_batch;
    reg signed [PARTIAL_SUM_WIDTH-1:0] mix_accumulator;
    reg [15:0] envelope_divider;
    reg        envelope_update_active;

    // 发出阶段与提交阶段之间的槽位上下文寄存器。
    reg        pipe_valid;
    reg        pipe_cancel;
    reg [7:0]  pipe_slot;
    reg [31:0] pipe_phase;
    reg [31:0] pipe_phase_step;
    reg        pipe_enable;
    reg        pipe_gate;
    reg [2:0]  pipe_envelope_stage;
    reg [15:0] pipe_envelope_level;
    reg [15:0] pipe_velocity_envelope_level;
    reg [6:0]  pipe_velocity;
    reg [2:0]  pipe_waveform_select;

    wire issue_request;
    wire [31:0] issue_phase;
    wire [7:0] issue_wave_address;
    wire acid_sample_valid;
    wire signed [15:0] acid_wave_sample;
    wire signed [15:0] sine_wave_sample;
    wire signed [15:0] triangle_wave_sample;
    wire signed [15:0] square_wave_sample;
    wire signed [15:0] sawtooth_wave_sample;
    reg  signed [15:0] current_wave_sample;

    wire [22:0] velocity_product;
    wire [22:0] velocity_rounded;
    wire [15:0] velocity_scaled_envelope;
    wire signed [16:0] current_wave_extended;
    wire signed [16:0] current_envelope_gain;
    wire signed [33:0] envelope_product;
    wire signed [33:0] envelope_rounded;
    wire signed [33:0] envelope_scaled;
    wire signed [15:0] enveloped_wave_sample;
    wire [15:0] current_release_delta;
    wire commit_enabled;
    wire signed [PARTIAL_SUM_WIDTH-1:0] extended_sample;
    wire signed [PARTIAL_SUM_WIDTH-1:0] sum_with_current_slot;

    integer reset_index;

    assign issue_request = busy && issue_active;
    assign issue_phase = phase_state[issue_slot];
    assign issue_wave_address = issue_phase[31:24];

    // Acid读取器在发出地址后一拍给出数据。两个地址端口同时读取相邻帧，
    // 因此帧间插值不会降低每拍一个槽位的吞吐率。
    acid_wavetable_reader u_acid_wavetable_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (issue_request),
        .phase_address(issue_wave_address),
        .wt_position  (wt_position_batch),
        .sample_valid (acid_sample_valid),
        .sample_data  (acid_wave_sample)
    );

    // 旧有四种波形保持组合读取，但地址改为流水线中的待提交相位，
    // 从而与同步Acid波表的数据在同一提交拍对齐。
    sine_lut u_shared_sine_lut (
        .addr(pipe_phase[31:24]),
        .data(sine_wave_sample)
    );

    triangle_lut u_shared_triangle_lut (
        .addr(pipe_phase[31:24]),
        .data(triangle_wave_sample)
    );

    square_lut u_shared_square_lut (
        .addr(pipe_phase[31:24]),
        .data(square_wave_sample)
    );

    sawtooth_lut u_shared_sawtooth_lut (
        .addr(pipe_phase[31:24]),
        .data(sawtooth_wave_sample)
    );

    always @(*) begin
        case (pipe_waveform_select)
            3'd0: current_wave_sample = sine_wave_sample;
            3'd1: current_wave_sample = triangle_wave_sample;
            3'd2: current_wave_sample = square_wave_sample;
            3'd3: current_wave_sample = sawtooth_wave_sample;
            WAVE_ACID: current_wave_sample = acid_wave_sample;
            default: current_wave_sample = square_wave_sample;
        endcase
    end

    assign velocity_product = pipe_envelope_level * pipe_velocity;
    assign velocity_rounded = velocity_product + 23'd64;
    assign velocity_scaled_envelope
        = (pipe_velocity == 7'd127)
        ? pipe_envelope_level
        : velocity_rounded[22:7];

    assign current_wave_extended
        = $signed({current_wave_sample[15], current_wave_sample});
    assign current_envelope_gain
        = $signed({1'b0, pipe_velocity_envelope_level});
    assign envelope_product = $signed(current_wave_extended)
                            * $signed(current_envelope_gain);
    assign envelope_rounded = envelope_product + 34'sd32768;
    assign envelope_scaled = envelope_rounded >>> 16;
    assign enveloped_wave_sample = envelope_scaled[15:0];
    assign current_release_delta = pipe_envelope_level >> RELEASE_SHIFT;

    assign commit_enabled = pipe_valid && pipe_enable && !pipe_cancel
                          && ((pipe_waveform_select != WAVE_ACID)
                              || acid_sample_valid);
    assign extended_sample = commit_enabled
        ? {{(PARTIAL_SUM_WIDTH-16){enveloped_wave_sample[15]}},
           enveloped_wave_sample}
        : {PARTIAL_SUM_WIDTH{1'b0}};
    assign sum_with_current_slot = mix_accumulator + extended_sample;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_slot        <= 8'd0;
            issue_active      <= 1'b0;
            waveform_select_batch <= 3'd2;
            wt_position_batch <= 7'd0;
            mix_accumulator   <= {PARTIAL_SUM_WIDTH{1'b0}};
            partial_sum       <= {PARTIAL_SUM_WIDTH{1'b0}};
            partial_valid     <= 1'b0;
            busy              <= 1'b0;
            debug_slot        <= 8'd0;
            debug_slot_commit <= 1'b0;
            schedule_overrun  <= 1'b0;
            task_idle_valid   <= 1'b0;
            task_idle_slot    <= 8'd0;
            envelope_divider  <= 16'd0;
            envelope_update_active <= 1'b0;
            pipe_valid        <= 1'b0;
            pipe_cancel       <= 1'b0;
            pipe_slot         <= 8'd0;
            pipe_phase        <= 32'd0;
            pipe_phase_step   <= 32'd0;
            pipe_enable       <= 1'b0;
            pipe_gate         <= 1'b0;
            pipe_envelope_stage <= ENV_IDLE;
            pipe_envelope_level <= 16'd0;
            pipe_velocity_envelope_level <= 16'd0;
            pipe_velocity     <= 7'd0;
            pipe_waveform_select <= 3'd2;

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
            partial_valid     <= 1'b0;
            debug_slot_commit <= 1'b0;
            task_idle_valid   <= 1'b0;

            if (clear_phase) begin
                for (reset_index = 0;
                     reset_index < SLOTS_PER_ENGINE;
                     reset_index = reset_index + 1)
                    phase_state[reset_index] <= 32'd0;
            end

            if (start_tick && busy)
                schedule_overrun <= 1'b1;

            if (!busy) begin
                pipe_valid <= 1'b0;
                if (start_tick) begin
                    busy             <= 1'b1;
                    issue_active     <= 1'b1;
                    issue_slot       <= 8'd0;
                    mix_accumulator  <= {PARTIAL_SUM_WIDTH{1'b0}};
                    waveform_select_batch <= waveform_select;
                    wt_position_batch <= wt_position;

                    // 一次包络更新请求保持到整批槽位提交完毕。
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
                // 提交上一拍发出的槽位。
                if (pipe_valid) begin
                    debug_slot        <= pipe_slot;
                    debug_slot_commit <= 1'b1;

                    if (commit_enabled && !clear_phase)
                        phase_state[pipe_slot]
                            <= pipe_phase + pipe_phase_step;

                    if (commit_enabled && envelope_update_active) begin
                        velocity_envelope_level[pipe_slot]
                            <= velocity_scaled_envelope;
                        case (pipe_envelope_stage)
                            ENV_ATTACK: begin
                                if (!pipe_gate) begin
                                    envelope_stage[pipe_slot] <= ENV_RELEASE;
                                end else if (pipe_envelope_level
                                             >= ENVELOPE_MAX - ATTACK_STEP) begin
                                    envelope_level[pipe_slot] <= ENVELOPE_MAX;
                                    envelope_stage[pipe_slot] <= ENV_DECAY;
                                end else begin
                                    envelope_level[pipe_slot]
                                        <= pipe_envelope_level + ATTACK_STEP;
                                end
                            end

                            ENV_DECAY: begin
                                if (!pipe_gate) begin
                                    envelope_stage[pipe_slot] <= ENV_RELEASE;
                                end else if (pipe_envelope_level
                                             <= SUSTAIN_LEVEL) begin
                                    envelope_level[pipe_slot] <= SUSTAIN_LEVEL;
                                    envelope_stage[pipe_slot] <= ENV_SUSTAIN;
                                end else if ((pipe_envelope_level
                                              - SUSTAIN_LEVEL) <= DECAY_STEP) begin
                                    envelope_level[pipe_slot] <= SUSTAIN_LEVEL;
                                    envelope_stage[pipe_slot] <= ENV_SUSTAIN;
                                end else begin
                                    envelope_level[pipe_slot]
                                        <= pipe_envelope_level - DECAY_STEP;
                                end
                            end

                            ENV_SUSTAIN: begin
                                envelope_level[pipe_slot] <= SUSTAIN_LEVEL;
                                if (!pipe_gate)
                                    envelope_stage[pipe_slot] <= ENV_RELEASE;
                            end

                            ENV_RELEASE: begin
                                if (pipe_envelope_level <= RELEASE_END_LEVEL) begin
                                    envelope_level[pipe_slot] <= 16'd0;
                                    envelope_stage[pipe_slot] <= ENV_IDLE;
                                    enable_state[pipe_slot] <= 1'b0;
                                    task_idle_valid <= 1'b1;
                                    task_idle_slot  <= pipe_slot;
                                end else if (current_release_delta == 16'd0) begin
                                    envelope_level[pipe_slot]
                                        <= pipe_envelope_level - 16'd1;
                                end else begin
                                    envelope_level[pipe_slot]
                                        <= pipe_envelope_level
                                         - current_release_delta;
                                end
                            end

                            default: begin
                                envelope_level[pipe_slot] <= 16'd0;
                                envelope_stage[pipe_slot] <= ENV_IDLE;
                                enable_state[pipe_slot] <= 1'b0;
                            end
                        endcase
                    end

                    if (pipe_slot == (SLOTS_PER_ENGINE-1)) begin
                        partial_sum     <= sum_with_current_slot;
                        partial_valid   <= 1'b1;
                        mix_accumulator <= {PARTIAL_SUM_WIDTH{1'b0}};
                        pipe_valid      <= 1'b0;
                        busy            <= 1'b0;
                    end else begin
                        mix_accumulator <= sum_with_current_slot;
                    end
                end

                // 与提交并行，向ROM发出下一个槽位。最后一个槽位发出后，
                // 再留一拍只用于提交流水线尾部。
                if (issue_active) begin
                    pipe_valid  <= 1'b1;
                    pipe_cancel <= task_update_valid
                                && (task_update_slot == issue_slot);
                    pipe_slot   <= issue_slot;
                    pipe_phase  <= phase_state[issue_slot];
                    pipe_phase_step <= phase_step_state[issue_slot];
                    pipe_enable <= enable_state[issue_slot];
                    pipe_gate   <= gate_state[issue_slot];
                    pipe_envelope_stage <= envelope_stage[issue_slot];
                    pipe_envelope_level <= envelope_level[issue_slot];
                    pipe_velocity_envelope_level
                        <= velocity_envelope_level[issue_slot];
                    pipe_velocity <= velocity_state[issue_slot];
                    pipe_waveform_select <= waveform_select_batch;

                    if (issue_slot == (SLOTS_PER_ENGINE-1)) begin
                        issue_active <= 1'b0;
                    end else begin
                        issue_slot <= issue_slot + 8'd1;
                    end
                end
            end

            // 配置写入位于提交逻辑之后，同拍冲突时由新任务状态优先。
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
                    gate_state[task_update_slot] <= 1'b0;
                    envelope_stage[task_update_slot] <= ENV_RELEASE;
                end
            end
        end
    end

endmodule
