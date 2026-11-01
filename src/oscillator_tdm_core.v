// 一个物理引擎每拍接收一个槽位，八个寄存器级分别承担：
// 读槽位、Warp操作数、Warp乘积、ROM地址、ROM返回、插值样本、增益乘积、累加提交。
// 每级携带槽位编号和取消标志；同槽位更新使旧任务失效，避免覆盖新音符。
// 32槽位的核心提交在start_tick后39拍完成，需由仿真检查整条bank的65拍预算。
module oscillator_tdm_core #(
    parameter integer SLOTS_PER_ENGINE = 4,
    parameter integer PARTIAL_SUM_WIDTH = 24,
    parameter integer INITIAL_PHASE_ENABLE = 0,
    parameter integer REALTIME_DETUNE_ENABLE = 0,
    parameter integer ENVELOPE_UPDATE_DIV = 16,
    // 1：使用平滑固定曲线；0：保留线性曲线，便于对照验证。
    parameter integer CURVED_ENVELOPE_ENABLE = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_tick,
    input  wire clear_phase,
    input  wire [2:0] waveform_select,
    input  wire [6:0] wt_position,
    input  wire [3:0] warp_mode,
    input  wire [6:0] warp_amount,
    input  wire [31:0] attack_phase_step,
    input  wire [31:0] decay_phase_step,
    input  wire [15:0] sustain_level,
    input  wire [31:0] release_phase_step,

    // 从DDR预取的外部波表缓存。所有逻辑槽位共享同一对相邻帧。
    input  wire        external_wavetable_enable,
    input  wire        cache_load_clk,
    input  wire        cache_load_rst_n,
    input  wire        cache_write_enable,
    input  wire        cache_write_bank,
    input  wire        cache_write_frame,
    input  wire [7:0]  cache_write_address,
    input  wire [15:0] cache_write_data,
    input  wire        cache_commit_toggle,
    input  wire        cache_commit_bank,
    input  wire [7:0]  cache_commit_fraction,

    input  wire                  task_update_valid,
    input  wire [7:0]            task_update_slot,
    input  wire [31:0]           task_update_phase_step,
    input wire [31:0] task_update_base_step,
    input wire [34:0] task_update_detune_unit,
    input wire [2:0] task_update_detune_magnitude,
    input wire task_update_detune_negative,
    input wire [6:0] detune_amount,
    input wire glide_override_enable,
    input wire [31:0] glide_override_base_step,
    input wire signed [12:0] vibrato_ratio_delta_q16,
    input  wire [6:0]            task_update_velocity,
    input  wire                  task_update_enable,
    input  wire                  task_update_phase_reset,
    input wire [31:0] task_update_initial_phase,

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
    localparam [15:0] ENVELOPE_DIV_LAST = ENVELOPE_UPDATE_DIV - 1;

    reg [31:0] phase_state [0:SLOTS_PER_ENGINE-1];
    // 实时Detune：请求级做乘法，返回级舍入加减，提交级累加相位。
    // 系数仅在新音符分配时更新，Note Off不改系数，Release期间仍可调制。
    reg [31:0] base_step_state [0:SLOTS_PER_ENGINE-1];
    reg [34:0] detune_unit_state [0:SLOTS_PER_ENGINE-1];
    reg [2:0] detune_magnitude_state [0:SLOTS_PER_ENGINE-1];
    reg detune_negative_state [0:SLOTS_PER_ENGINE-1];
    reg [6:0] detune_batch;
    reg glide_override_enable_batch;
    reg [31:0] glide_override_base_step_batch;
    reg signed [12:0] vibrato_ratio_delta_batch;
    reg [41:0] request_detune_product;
    reg signed [45:0] request_vibrato_product;
    reg request_detune_negative;
    wire [41:0] rounded_live_detune = request_detune_product + 42'd32;
    wire signed [32:0] request_vibrato_delta
        = request_vibrato_product >>> 16;
    wire signed [34:0] signed_live_detune_delta
        = request_detune_negative
        ? -$signed({3'd0, rounded_live_detune[37:6]})
        :  $signed({3'd0, rounded_live_detune[37:6]});
    wire signed [34:0] signed_live_phase_step
        = $signed({3'd0, request_phase_step})
        + {{2{request_vibrato_delta[32]}}, request_vibrato_delta}
        + signed_live_detune_delta;
    reg [31:0] phase_step_state [0:SLOTS_PER_ENGINE-1];
    reg        enable_state [0:SLOTS_PER_ENGINE-1];
    reg        gate_state [0:SLOTS_PER_ENGINE-1];
    reg [2:0]  envelope_stage [0:SLOTS_PER_ENGINE-1];
    reg [15:0] envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [15:0] velocity_envelope_level [0:SLOTS_PER_ENGINE-1];
    reg [6:0]  velocity_state [0:SLOTS_PER_ENGINE-1];
    reg [31:0] envelope_phase [0:SLOTS_PER_ENGINE-1];
    reg [15:0] release_start_level [0:SLOTS_PER_ENGINE-1];

    reg [7:0] issue_slot;
    reg       issue_active;
    reg [2:0] waveform_select_batch;
    reg [6:0] wt_position_batch;
    reg [3:0] warp_mode_batch;
    reg [6:0] warp_amount_batch;
    reg [31:0] attack_phase_step_batch;
    reg [31:0] decay_phase_step_batch;
    reg [15:0] sustain_level_batch;
    reg [31:0] release_phase_step_batch;
    reg signed [PARTIAL_SUM_WIDTH-1:0] mix_accumulator;
    reg [15:0] envelope_divider;
    reg        envelope_update_active;

    // ROM地址级：Warp已完成；当前上下文与这一拍发出的同步读取对应。
    reg        request_valid;
    reg        request_cancel;
    reg [7:0]  request_slot;
    reg [31:0] request_phase;
    reg [7:0]  request_wave_address;
    reg [31:0] request_phase_step;
    reg        request_enable;
    reg        request_gate;
    reg [2:0]  request_envelope_stage;
    reg [15:0] request_envelope_level;
    reg [15:0] request_velocity_envelope_level;
    reg [6:0]  request_velocity;
    reg [2:0]  request_waveform_select;
    reg [31:0] request_envelope_phase;
    reg [15:0] request_release_start_level;

    // ROM返回级：帧间插值在本级完成，下一拍保存完整样本。
    reg        pipe_valid;
    reg        pipe_cancel;
    reg [7:0]  pipe_slot;
    reg [31:0] pipe_phase;
    reg [7:0]  pipe_wave_address;
    reg [31:0] pipe_phase_step;
    reg        pipe_enable;
    reg        pipe_gate;
    reg [2:0]  pipe_envelope_stage;
    reg [15:0] pipe_envelope_level;
    reg [15:0] pipe_velocity_envelope_level;
    reg [6:0]  pipe_velocity;
    reg [2:0]  pipe_waveform_select;
    reg [31:0] pipe_envelope_phase;
    reg [15:0] pipe_release_start_level;


    // 读槽位 → Warp准备 → Warp乘法 → 地址 → ROM返回 → 样本 → 提交。
    reg  read_valid;
    reg  read_cancel;
    reg [7:0] read_slot;
    reg [31:0] read_phase;
    reg [7:0] read_wave_address;
    reg [31:0] read_phase_step;
    reg  read_enable;
    reg  read_gate;
    reg [2:0] read_envelope_stage;
    reg [15:0] read_envelope_level;
    reg [15:0] read_velocity_envelope_level;
    reg [6:0] read_velocity;
    reg [2:0] read_waveform_select;
    reg [31:0] read_envelope_phase;
    reg [15:0] read_release_start_level;
    reg  prepare_valid;
    reg  prepare_cancel;
    reg [7:0] prepare_slot;
    reg [31:0] prepare_phase;
    reg [31:0] prepare_phase_step;
    reg  prepare_enable;
    reg  prepare_gate;
    reg [2:0] prepare_envelope_stage;
    reg [15:0] prepare_envelope_level;
    reg [15:0] prepare_velocity_envelope_level;
    reg [6:0] prepare_velocity;
    reg [2:0] prepare_waveform_select;
    reg [31:0] prepare_envelope_phase;
    reg [15:0] prepare_release_start_level;
    reg  multiply_valid;
    reg  multiply_cancel;
    reg [7:0] multiply_slot;
    reg [31:0] multiply_phase;
    reg [31:0] multiply_phase_step;
    reg  multiply_enable;
    reg  multiply_gate;
    reg [2:0] multiply_envelope_stage;
    reg [15:0] multiply_envelope_level;
    reg [15:0] multiply_velocity_envelope_level;
    reg [6:0] multiply_velocity;
    reg [2:0] multiply_waveform_select;
    reg [31:0] multiply_envelope_phase;
    reg [15:0] multiply_release_start_level;
    reg  sample_valid;
    reg  sample_cancel;
    reg [7:0] sample_slot;
    reg [31:0] sample_phase;
    reg [31:0] sample_phase_step;
    reg  sample_enable;
    reg  sample_gate;
    reg [2:0] sample_envelope_stage;
    reg [15:0] sample_envelope_level;
    reg [15:0] sample_velocity_envelope_level;
    reg  commit_valid;
    reg  commit_cancel;
    reg [7:0] commit_slot;
    reg [31:0] commit_phase;
    reg [31:0] commit_phase_step;
    reg  commit_enable;
    reg  commit_gate;
    reg [2:0] commit_envelope_stage;
    reg [15:0] commit_envelope_level;
    reg [34:0] read_detune_unit;
    reg [31:0] read_base_step;
    reg read_detune_negative;
    reg prepare_detune_negative;
    reg multiply_detune_negative;
    reg [41:0] prepare_detune_product;
    reg signed [45:0] prepare_vibrato_product;
    reg [41:0] multiply_detune_product;
    reg signed [45:0] multiply_vibrato_product;
    reg signed [15:0] sample_wave;
    reg signed [33:0] commit_envelope_product;
    reg [15:0] sample_velocity_scaled_envelope;
    reg [31:0] sample_envelope_phase_next;
    reg  sample_envelope_phase_complete;
    reg [15:0] sample_attack_level_next;
    reg [15:0] sample_segment_multiplicand;
    reg [15:0] sample_segment_factor;

    reg [15:0] commit_velocity_scaled_envelope;
    reg [31:0] commit_envelope_phase_next;
    reg  commit_envelope_phase_complete;
    reg [15:0] commit_attack_level_next;
    reg [15:0] commit_decay_level_next;
    reg [15:0] commit_release_level_next;

    wire [31:0] issue_phase;
    wire [7:0] issue_raw_wave_address;
    wire [7:0] issue_warped_wave_address;
    wire acid_sample_valid;
    wire signed [15:0] acid_wave_sample;
    wire external_sample_valid;
    wire signed [15:0] external_wave_sample;
    wire external_cache_ready;
    wire selected_wavetable_valid;
    wire signed [15:0] selected_wavetable_sample;
    wire signed [15:0] sine_wave_sample;
    wire signed [15:0] triangle_wave_sample;
    wire signed [15:0] square_wave_sample;
    wire signed [15:0] sawtooth_wave_sample;
    wire [31:0] issue_live_base_step;
    wire [34:0] issue_live_detune_unit;
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
    reg [31:0] selected_phase_step;
    wire [32:0] envelope_phase_sum;
    wire [31:0] envelope_phase_next;
    wire envelope_phase_complete;
    wire [15:0] envelope_phase_fraction;
    wire [15:0] decay_span;
    wire [15:0] release_fraction_remaining;
    wire [15:0] curve_input;
    wire [31:0] curve_square_product;
    wire [32:0] curve_square_rounded;
    wire [15:0] curve_square_fraction;
    wire [16:0] attack_curve_wide;
    wire [15:0] attack_level_next;
    reg  [15:0] segment_multiplicand;
    reg  [15:0] segment_factor;
    wire [31:0] segment_product;
    wire [15:0] decay_level_next;
    wire [15:0] release_level_next;
    wire commit_enabled;
    wire signed [PARTIAL_SUM_WIDTH-1:0] extended_sample;
    wire signed [PARTIAL_SUM_WIDTH-1:0] sum_with_current_slot;

    integer reset_index;

    function [34:0] make_live_detune_unit;
        input [31:0] base_step;
        input [2:0] magnitude;
        reg [31:0] unit_step;
        begin
            unit_step = (base_step >> 10)
                      + (base_step >> 13)
                      + (base_step >> 14);
            case (magnitude)
                3'd0: make_live_detune_unit = 35'd0;
                3'd1: make_live_detune_unit = unit_step;
                3'd2: make_live_detune_unit = unit_step << 1;
                3'd3: make_live_detune_unit = unit_step
                                               + (unit_step << 1);
                3'd4: make_live_detune_unit = unit_step << 2;
                3'd5: make_live_detune_unit = unit_step
                                               + (unit_step << 2);
                3'd6: make_live_detune_unit = (unit_step << 1)
                                               + (unit_step << 2);
                default: make_live_detune_unit = unit_step
                                               + (unit_step << 1)
                                               + (unit_step << 2);
            endcase
        end
    endfunction

    function [31:0] saturate_live_phase_step;
        input signed [34:0] value;
        begin
            if (value <= 35'sd0)
                saturate_live_phase_step = 32'd1;
            else if (value > $signed({3'd0, 32'hFFFFFFFF}))
                saturate_live_phase_step = 32'hFFFFFFFF;
            else
                saturate_live_phase_step = value[31:0];
        end
    endfunction

    assign issue_live_base_step = glide_override_enable_batch
                                ? glide_override_base_step_batch
                                : base_step_state[issue_slot];
    assign issue_live_detune_unit = glide_override_enable_batch
                                  ? make_live_detune_unit(
                                        glide_override_base_step_batch,
                                        detune_magnitude_state[issue_slot])
                                  : detune_unit_state[issue_slot];

    assign issue_phase = phase_state[issue_slot];
    assign issue_raw_wave_address = issue_phase[31:24];

    wavetable_phase_warp_pipeline u_wavetable_phase_warp (
        .clk(clk), .rst_n(rst_n),
        .raw_address   (read_wave_address),
        .warp_mode     (warp_mode_batch),
        .warp_amount   (warp_amount_batch),
        .warped_address(issue_warped_wave_address)
    );

    // Acid读取器在发出地址后一拍给出数据。两个地址端口同时读取相邻帧，
    // 因此帧间插值不会降低每拍一个槽位的吞吐率。
    acid_wavetable_reader u_acid_wavetable_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (request_valid),
        .phase_address(request_wave_address),
        .wt_position  (wt_position_batch),
        .sample_valid (acid_sample_valid),
        .sample_data  (acid_wave_sample)
    );

    wavetable_frame_cache u_external_wavetable_cache (
        .audio_clk              (clk),
        .audio_rst_n            (rst_n),
        .req_valid              (request_valid),
        .phase_address          (request_wave_address),
        .sample_valid           (external_sample_valid),
        .sample_data            (external_wave_sample),
        .load_clk               (cache_load_clk),
        .load_rst_n             (cache_load_rst_n),
        .load_write_enable      (cache_write_enable),
        .load_write_bank        (cache_write_bank),
        .load_write_frame       (cache_write_frame),
        .load_write_address     (cache_write_address),
        .load_write_data        (cache_write_data),
        .load_commit_toggle     (cache_commit_toggle),
        .load_commit_bank       (cache_commit_bank),
        .load_commit_fraction   (cache_commit_fraction),
        .ready                  (external_cache_ready)
    );

    assign selected_wavetable_valid = external_wavetable_enable
                                    && external_cache_ready
                                    ? external_sample_valid
                                    : acid_sample_valid;
    assign selected_wavetable_sample = external_wavetable_enable
                                     && external_cache_ready
                                     ? external_wave_sample
                                     : acid_wave_sample;

    // 基础波形使用ROM返回级地址，与Acid/外部波表返回数据对齐。
    sine_lut u_shared_sine_lut (
        .addr(pipe_wave_address),
        .data(sine_wave_sample)
    );

    triangle_lut u_shared_triangle_lut (
        .addr(pipe_wave_address),
        .data(triangle_wave_sample)
    );

    square_lut u_shared_square_lut (
        .addr(pipe_wave_address),
        .data(square_wave_sample)
    );

    sawtooth_lut u_shared_sawtooth_lut (
        .addr(pipe_wave_address),
        .data(sawtooth_wave_sample)
    );

    always @(*) begin
        case (pipe_waveform_select)
            3'd0: current_wave_sample = sine_wave_sample;
            3'd1: current_wave_sample = triangle_wave_sample;
            3'd2: current_wave_sample = square_wave_sample;
            3'd3: current_wave_sample = sawtooth_wave_sample;
            WAVE_ACID: current_wave_sample = selected_wavetable_sample;
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
        = $signed({sample_wave[15], sample_wave});
    assign current_envelope_gain
        = $signed({1'b0, sample_velocity_envelope_level});
    assign envelope_product = $signed(current_wave_extended)
                            * $signed(current_envelope_gain);
    assign envelope_rounded = commit_envelope_product + 34'sd32768;
    assign envelope_scaled = envelope_rounded >>> 16;
    assign enveloped_wave_sample = envelope_scaled[15:0];

    // A、D、R都使用0～2^32的阶段进度。改变时间参数只会改变进度速度，
    // 不会直接改写当前电平。固定曲线在相邻寄存器级间计算，不增加调度延迟。
    always @(*) begin
        case (pipe_envelope_stage)
            ENV_ATTACK:  selected_phase_step = attack_phase_step_batch;
            ENV_DECAY:   selected_phase_step = decay_phase_step_batch;
            ENV_RELEASE: selected_phase_step = release_phase_step_batch;
            default:     selected_phase_step = 32'd0;
        endcase
    end

    assign envelope_phase_sum
        = {1'b0, pipe_envelope_phase} + {1'b0, selected_phase_step};
    assign envelope_phase_next = envelope_phase_sum[31:0];
    assign envelope_phase_complete = envelope_phase_sum[32]
                                   || (&envelope_phase_next[31:16]);
    assign envelope_phase_fraction = envelope_phase_next[31:16];
    assign decay_span = 16'hFFFF - sustain_level_batch;
    assign release_fraction_remaining
        = 16'hFFFF - envelope_phase_fraction;

    // 固定平滑曲线：
    // Attack  = 2p - p^2，使峰值附近的斜率逐渐降为0；
    // Decay   = 1 - (1-S)p^2，使Attack到Decay的连接更平滑；
    // Release = R0(1-p)^2，使尾部逐渐贴近静音。
    // Release对剩余进度求平方；Attack和Decay对正向进度求平方。
    assign curve_input = (pipe_envelope_stage == ENV_RELEASE)
                       ? release_fraction_remaining
                       : envelope_phase_fraction;

    always @(*) begin
        if (pipe_envelope_stage == ENV_RELEASE) begin
            segment_multiplicand = pipe_release_start_level;
            segment_factor = CURVED_ENVELOPE_ENABLE
                           ? curve_square_fraction
                           : release_fraction_remaining;
        end else begin
            segment_multiplicand = decay_span;
            segment_factor = CURVED_ENVELOPE_ENABLE
                           ? curve_square_fraction
                           : envelope_phase_fraction;
        end
    end

    assign curve_square_product = curve_input * curve_input;
    assign curve_square_rounded
        = {1'b0, curve_square_product} + 33'd32768;
    assign curve_square_fraction = curve_square_rounded[31:16];
    assign attack_curve_wide
        = {envelope_phase_fraction, 1'b0}
        - {1'b0, curve_square_fraction};
    assign attack_level_next = CURVED_ENVELOPE_ENABLE
        ? (attack_curve_wide[16] ? 16'hFFFF : attack_curve_wide[15:0])
        : envelope_phase_fraction;

    // Decay与Release互斥，继续复用原有16×16阶段插值乘法器。
    assign segment_product = sample_segment_multiplicand * sample_segment_factor;
    assign decay_level_next = 16'hFFFF - segment_product[31:16];
    assign release_level_next = segment_product[31:16];

    assign commit_enabled = commit_valid && commit_enable && !commit_cancel
                          && !clear_phase
                          && !(task_update_valid && task_update_slot == commit_slot);
    assign extended_sample = commit_enabled
        ? {{(PARTIAL_SUM_WIDTH-16){enveloped_wave_sample[15]}},
           enveloped_wave_sample}
        : {PARTIAL_SUM_WIDTH{1'b0}};
    assign sum_with_current_slot = mix_accumulator + extended_sample;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_valid <= 0;
            read_cancel <= 0;
            read_slot <= 0;
            read_phase <= 0;
            read_wave_address <= 0;
            read_phase_step <= 0;
            read_enable <= 0;
            read_gate <= 0;
            read_envelope_stage <= 0;
            read_envelope_level <= 0;
            read_velocity_envelope_level <= 0;
            read_velocity <= 0;
            read_waveform_select <= 0;
            read_envelope_phase <= 0;
            read_release_start_level <= 0;
            prepare_valid <= 0;
            prepare_cancel <= 0;
            prepare_slot <= 0;
            prepare_phase <= 0;
            prepare_phase_step <= 0;
            prepare_enable <= 0;
            prepare_gate <= 0;
            prepare_envelope_stage <= 0;
            prepare_envelope_level <= 0;
            prepare_velocity_envelope_level <= 0;
            prepare_velocity <= 0;
            prepare_waveform_select <= 0;
            prepare_envelope_phase <= 0;
            prepare_release_start_level <= 0;
            multiply_valid <= 0;
            multiply_cancel <= 0;
            multiply_slot <= 0;
            multiply_phase <= 0;
            multiply_phase_step <= 0;
            multiply_enable <= 0;
            multiply_gate <= 0;
            multiply_envelope_stage <= 0;
            multiply_envelope_level <= 0;
            multiply_velocity_envelope_level <= 0;
            multiply_velocity <= 0;
            multiply_waveform_select <= 0;
            multiply_envelope_phase <= 0;
            multiply_release_start_level <= 0;
            sample_valid <= 0;
            sample_cancel <= 0;
            sample_slot <= 0;
            sample_phase <= 0;
            sample_phase_step <= 0;
            sample_enable <= 0;
            sample_gate <= 0;
            sample_envelope_stage <= 0;
            sample_envelope_level <= 0;
            sample_velocity_envelope_level <= 0;
            commit_valid <= 0;
            commit_cancel <= 0;
            commit_slot <= 0;
            commit_phase <= 0;
            commit_phase_step <= 0;
            commit_enable <= 0;
            commit_gate <= 0;
            commit_envelope_stage <= 0;
            commit_envelope_level <= 0;
            read_detune_unit <= 0;
            read_base_step <= 0;
            read_detune_negative <= 0;
            prepare_detune_negative <= 0;
            multiply_detune_negative <= 0;
            prepare_detune_product <= 0;
            prepare_vibrato_product <= 0;
            multiply_detune_product <= 0;
            multiply_vibrato_product <= 0;
            sample_wave <= 0;
            commit_envelope_product <= 0;
            sample_velocity_scaled_envelope <= 0;
            sample_envelope_phase_next <= 0;
            sample_envelope_phase_complete <= 0;
            sample_attack_level_next <= 0;
            sample_segment_multiplicand <= 0;
            sample_segment_factor <= 0;

            commit_velocity_scaled_envelope <= 0;
            commit_envelope_phase_next <= 0;
            commit_envelope_phase_complete <= 0;
            commit_attack_level_next <= 0;
            commit_decay_level_next <= 0;
            commit_release_level_next <= 0;
            issue_slot        <= 8'd0;
            issue_active      <= 1'b0;
            waveform_select_batch <= 3'd2;
            wt_position_batch <= 7'd0;
            warp_mode_batch <= 4'd0;
            warp_amount_batch <= 7'd0;
            attack_phase_step_batch <= 32'd0;
            decay_phase_step_batch <= 32'd0;
            sustain_level_batch <= 16'd0;
            release_phase_step_batch <= 32'd0;
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
            request_valid     <= 1'b0;
            request_cancel    <= 1'b0;
            request_slot      <= 8'd0;
            request_phase     <= 32'd0;
            request_wave_address <= 8'd0;
            request_phase_step <= 32'd0;
            detune_batch <= 0;
            glide_override_enable_batch <= 1'b0;
            glide_override_base_step_batch <= 32'd0;
            vibrato_ratio_delta_batch <= 13'sd0;
            request_detune_product <= 0;
            request_vibrato_product <= 0;
            request_detune_negative <= 0;
            request_enable    <= 1'b0;
            request_gate      <= 1'b0;
            request_envelope_stage <= ENV_IDLE;
            request_envelope_level <= 16'd0;
            request_velocity_envelope_level <= 16'd0;
            request_velocity  <= 7'd0;
            request_waveform_select <= 3'd2;
            request_envelope_phase <= 32'd0;
            request_release_start_level <= 16'd0;
            pipe_valid        <= 1'b0;
            pipe_cancel       <= 1'b0;
            pipe_slot         <= 8'd0;
            pipe_phase        <= 32'd0;
            pipe_wave_address <= 8'd0;
            pipe_phase_step   <= 32'd0;
            pipe_enable       <= 1'b0;
            pipe_gate         <= 1'b0;
            pipe_envelope_stage <= ENV_IDLE;
            pipe_envelope_level <= 16'd0;
            pipe_velocity_envelope_level <= 16'd0;
            pipe_velocity     <= 7'd0;
            pipe_waveform_select <= 3'd2;
            pipe_envelope_phase <= 32'd0;
            pipe_release_start_level <= 16'd0;

            for (reset_index = 0;
                 reset_index < SLOTS_PER_ENGINE;
                 reset_index = reset_index + 1) begin
                phase_state[reset_index] <= 32'd0;
                phase_step_state[reset_index] <= 32'd0;
                base_step_state[reset_index] <= 0;
                detune_unit_state[reset_index] <= 0;
                detune_magnitude_state[reset_index] <= 3'd0;
                detune_negative_state[reset_index] <= 0;
                enable_state[reset_index] <= 1'b0;
                gate_state[reset_index] <= 1'b0;
                envelope_stage[reset_index] <= ENV_IDLE;
                envelope_level[reset_index] <= 16'd0;
                velocity_envelope_level[reset_index] <= 16'd0;
                velocity_state[reset_index] <= 7'd0;
                envelope_phase[reset_index] <= 32'd0;
                release_start_level[reset_index] <= 16'd0;
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
                request_valid <= 1'b0;
                pipe_valid <= 1'b0;
                read_valid <= 0;
                // 读槽位 → Warp操作数级。
                prepare_valid <= 0;
                // Warp操作数 → 乘积级。
                multiply_valid <= 0;
                sample_valid <= 0;
                commit_valid <= 0;
                if (start_tick) begin
                    busy             <= 1'b1;
                    issue_active     <= 1'b1;
                    issue_slot       <= 8'd0;
                    mix_accumulator  <= {PARTIAL_SUM_WIDTH{1'b0}};
                    waveform_select_batch <= waveform_select;
                    wt_position_batch <= wt_position;
                    warp_mode_batch <= warp_mode;
                    warp_amount_batch <= warp_amount;
                    detune_batch <= detune_amount;
                    glide_override_enable_batch <= glide_override_enable;
                    glide_override_base_step_batch
                        <= glide_override_base_step;
                    vibrato_ratio_delta_batch
                        <= vibrato_ratio_delta_q16;
                    attack_phase_step_batch <= attack_phase_step;
                    decay_phase_step_batch <= decay_phase_step;
                    sustain_level_batch <= sustain_level;
                    release_phase_step_batch <= release_phase_step;

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
                // 地址级每拍向ROM返回级推进一次。波表在同一拍读取请求级地址，
                // 因而其返回数据会与这里复制的槽位上下文保持对齐。
                pipe_valid <= request_valid;
                if (request_valid) begin
                    pipe_cancel <= request_cancel || clear_phase
                                || (task_update_valid
                                    && (task_update_slot == request_slot));
                    pipe_slot <= request_slot;
                    pipe_phase <= request_phase;
                    pipe_wave_address <= request_wave_address;
                    if (REALTIME_DETUNE_ENABLE)
                        pipe_phase_step
                            <= saturate_live_phase_step(
                                   signed_live_phase_step);
                    else pipe_phase_step <= request_phase_step;
                    pipe_enable <= request_enable;
                    pipe_gate <= request_gate;
                    pipe_envelope_stage <= request_envelope_stage;
                    pipe_envelope_level <= request_envelope_level;
                    pipe_velocity_envelope_level
                        <= request_velocity_envelope_level;
                    pipe_velocity <= request_velocity;
                    pipe_waveform_select <= request_waveform_select;
                    pipe_envelope_phase <= request_envelope_phase;
                    pipe_release_start_level
                        <= request_release_start_level;
                end

                // 每拍推进上下文，暂停发出后valid自然排空；绝不等待整批槽位。
                read_valid <= 0;
                prepare_valid <= read_valid;
                prepare_cancel <= read_cancel || clear_phase || (task_update_valid && task_update_slot == read_slot);
                prepare_slot <= read_slot;
                prepare_phase <= read_phase;
                prepare_phase_step <= read_phase_step;
                prepare_enable <= read_enable;
                prepare_gate <= read_gate;
                prepare_envelope_stage <= read_envelope_stage;
                prepare_envelope_level <= read_envelope_level;
                prepare_velocity_envelope_level <= read_velocity_envelope_level;
                prepare_velocity <= read_velocity;
                prepare_waveform_select <= read_waveform_select;
                prepare_envelope_phase <= read_envelope_phase;
                prepare_release_start_level <= read_release_start_level;
                multiply_valid <= prepare_valid;
                multiply_cancel <= prepare_cancel || clear_phase || (task_update_valid && task_update_slot == prepare_slot);
                multiply_slot <= prepare_slot;
                multiply_phase <= prepare_phase;
                multiply_phase_step <= prepare_phase_step;
                multiply_enable <= prepare_enable;
                multiply_gate <= prepare_gate;
                multiply_envelope_stage <= prepare_envelope_stage;
                multiply_envelope_level <= prepare_envelope_level;
                multiply_velocity_envelope_level <= prepare_velocity_envelope_level;
                multiply_velocity <= prepare_velocity;
                multiply_waveform_select <= prepare_waveform_select;
                multiply_envelope_phase <= prepare_envelope_phase;
                multiply_release_start_level <= prepare_release_start_level;
                // Warp乘积 → ROM地址级。
                request_valid <= multiply_valid;
                request_cancel <= multiply_cancel || clear_phase || (task_update_valid && task_update_slot == multiply_slot);
                request_slot <= multiply_slot;
                request_phase <= multiply_phase;
                request_wave_address <= issue_warped_wave_address;
                request_phase_step <= multiply_phase_step;
                request_enable <= multiply_enable;
                request_gate <= multiply_gate;
                request_envelope_stage <= multiply_envelope_stage;
                request_envelope_level <= multiply_envelope_level;
                request_velocity_envelope_level <= multiply_velocity_envelope_level;
                request_velocity <= multiply_velocity;
                request_waveform_select <= multiply_waveform_select;
                request_envelope_phase <= multiply_envelope_phase;
                request_release_start_level <= multiply_release_start_level;
                // ROM返回/插值 → 样本寄存器。
                sample_valid <= pipe_valid;
                sample_cancel <= pipe_cancel || clear_phase || (task_update_valid && task_update_slot == pipe_slot);
                sample_slot <= pipe_slot;
                sample_phase <= pipe_phase;
                sample_phase_step <= pipe_phase_step;
                sample_enable <= pipe_enable && ((pipe_waveform_select != WAVE_ACID) || selected_wavetable_valid);
                sample_gate <= pipe_gate;
                sample_envelope_stage <= pipe_envelope_stage;
                sample_envelope_level <= pipe_envelope_level;
                sample_velocity_envelope_level <= pipe_velocity_envelope_level;
                // 样本 → 增益乘积/提交上下文。
                commit_valid <= sample_valid;
                commit_cancel <= sample_cancel || clear_phase || (task_update_valid && task_update_slot == sample_slot);
                commit_slot <= sample_slot;
                commit_phase <= sample_phase;
                commit_phase_step <= sample_phase_step;
                commit_enable <= sample_enable;
                commit_gate <= sample_gate;
                commit_envelope_stage <= sample_envelope_stage;
                commit_envelope_level <= sample_envelope_level;
                prepare_detune_negative <= read_detune_negative;
                multiply_detune_negative <= prepare_detune_negative;
                prepare_detune_product <= read_detune_unit * detune_batch;
                prepare_vibrato_product <= $signed({1'b0, read_base_step}) * $signed(vibrato_ratio_delta_batch);
                multiply_detune_product <= prepare_detune_product;
                multiply_vibrato_product <= prepare_vibrato_product;
                request_detune_product <= multiply_detune_product;
                request_vibrato_product <= multiply_vibrato_product;
                request_detune_negative <= multiply_detune_negative;
                sample_wave <= current_wave_sample;
                commit_envelope_product <= envelope_product;
                sample_velocity_scaled_envelope <= velocity_scaled_envelope;
                commit_velocity_scaled_envelope <= sample_velocity_scaled_envelope;
                sample_envelope_phase_next <= envelope_phase_next;
                commit_envelope_phase_next <= sample_envelope_phase_next;
                sample_envelope_phase_complete <= envelope_phase_complete;
                commit_envelope_phase_complete <= sample_envelope_phase_complete;
                sample_attack_level_next <= attack_level_next;
                commit_attack_level_next <= sample_attack_level_next;
                sample_segment_multiplicand <= segment_multiplicand;
                sample_segment_factor <= segment_factor;
                commit_decay_level_next <= decay_level_next;
                commit_release_level_next <= release_level_next;


                // 提交已完成全部计算的槽位。失效任务仍提交序号，但不写状态、不贡献混音。
                if (commit_valid) begin
                    debug_slot        <= commit_slot;
                    debug_slot_commit <= 1'b1;

                    if (commit_enabled && !clear_phase)
                        phase_state[commit_slot]
                            <= commit_phase + commit_phase_step;

                    if (commit_enabled && envelope_update_active) begin
                        velocity_envelope_level[commit_slot]
                            <= commit_velocity_scaled_envelope;
                        case (commit_envelope_stage)
                            ENV_ATTACK: begin
                                if (!commit_gate) begin
                                    envelope_stage[commit_slot] <= ENV_RELEASE;
                                    envelope_phase[commit_slot] <= 32'd0;
                                    release_start_level[commit_slot]
                                        <= commit_envelope_level;
                                end else if (commit_envelope_phase_complete) begin
                                    envelope_level[commit_slot] <= 16'hFFFF;
                                    envelope_stage[commit_slot] <= ENV_DECAY;
                                    envelope_phase[commit_slot] <= 32'd0;
                                end else begin
                                    envelope_level[commit_slot]
                                        <= commit_attack_level_next;
                                    envelope_phase[commit_slot]
                                        <= commit_envelope_phase_next;
                                end
                            end

                            ENV_DECAY: begin
                                if (!commit_gate) begin
                                    envelope_stage[commit_slot] <= ENV_RELEASE;
                                    envelope_phase[commit_slot] <= 32'd0;
                                    release_start_level[commit_slot]
                                        <= commit_envelope_level;
                                end else if (commit_envelope_phase_complete) begin
                                    envelope_level[commit_slot]
                                        <= sustain_level_batch;
                                    envelope_stage[commit_slot] <= ENV_SUSTAIN;
                                    envelope_phase[commit_slot] <= 32'd0;
                                end else begin
                                    envelope_level[commit_slot]
                                        <= commit_decay_level_next;
                                    envelope_phase[commit_slot]
                                        <= commit_envelope_phase_next;
                                end
                            end

                            ENV_SUSTAIN: begin
                                if (!commit_gate) begin
                                    envelope_stage[commit_slot] <= ENV_RELEASE;
                                    envelope_phase[commit_slot] <= 32'd0;
                                    release_start_level[commit_slot]
                                        <= commit_envelope_level;
                                end else begin
                                    envelope_level[commit_slot]
                                        <= sustain_level_batch;
                                end
                            end

                            ENV_RELEASE: begin
                                if (commit_envelope_phase_complete) begin
                                    envelope_level[commit_slot] <= 16'd0;
                                    envelope_stage[commit_slot] <= ENV_IDLE;
                                    envelope_phase[commit_slot] <= 32'd0;
                                    enable_state[commit_slot] <= 1'b0;
                                    task_idle_valid <= 1'b1;
                                    task_idle_slot  <= commit_slot;
                                end else begin
                                    envelope_level[commit_slot]
                                        <= commit_release_level_next;
                                    envelope_phase[commit_slot]
                                        <= commit_envelope_phase_next;
                                end
                            end

                            default: begin
                                envelope_level[commit_slot] <= 16'd0;
                                envelope_stage[commit_slot] <= ENV_IDLE;
                                envelope_phase[commit_slot] <= 32'd0;
                                enable_state[commit_slot] <= 1'b0;
                            end
                        endcase
                    end

                    if (commit_slot == (SLOTS_PER_ENGINE-1)) begin
                        partial_sum     <= sum_with_current_slot;
                        partial_valid   <= 1'b1;
                        mix_accumulator <= {PARTIAL_SUM_WIDTH{1'b0}};
                        commit_valid      <= 1'b0;
                        busy            <= 1'b0;
                    end else begin
                        mix_accumulator <= sum_with_current_slot;
                    end
                end

                // 与提交并行，只读取下一个槽位。最后一个读出后，等待所有在途级排空。
                if (issue_active) begin
                    read_valid  <= 1'b1;
                    read_cancel <= clear_phase || (task_update_valid
                                   && (task_update_slot == issue_slot));
                    read_slot   <= issue_slot;
                    read_phase  <= phase_state[issue_slot];
                    read_wave_address <= issue_raw_wave_address;
                    read_phase_step <= REALTIME_DETUNE_ENABLE
                        ? issue_live_base_step : phase_step_state[issue_slot];
                    read_detune_unit <= issue_live_detune_unit;
                    read_base_step <= issue_live_base_step;

                    read_detune_negative <= detune_negative_state[issue_slot];
                    read_enable <= enable_state[issue_slot];
                    read_gate   <= gate_state[issue_slot];
                    read_envelope_stage <= envelope_stage[issue_slot];
                    read_envelope_level <= envelope_level[issue_slot];
                    read_velocity_envelope_level
                        <= velocity_envelope_level[issue_slot];
                    read_velocity <= velocity_state[issue_slot];
                    read_waveform_select <= waveform_select_batch;
                    read_envelope_phase <= envelope_phase[issue_slot];
                    read_release_start_level
                        <= release_start_level[issue_slot];

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

                // Gate On和连续音高更新都会刷新实时Detune基准；只有
                // phase_reset=1的首次触发才重置相位并重新进入Attack。
                if (task_update_enable) begin
                    base_step_state[task_update_slot] <= task_update_base_step;
                    detune_unit_state[task_update_slot] <= task_update_detune_unit;
                    detune_magnitude_state[task_update_slot]
                        <= task_update_detune_magnitude;
                    detune_negative_state[task_update_slot] <= task_update_detune_negative;
                end
                if (task_update_enable && task_update_phase_reset) begin
                    enable_state[task_update_slot] <= 1'b1;
                    gate_state[task_update_slot] <= 1'b1;
                    envelope_stage[task_update_slot] <= ENV_ATTACK;
                    envelope_level[task_update_slot] <= 16'd0;
                    velocity_envelope_level[task_update_slot] <= 16'd0;
                    envelope_phase[task_update_slot] <= 32'd0;
                    release_start_level[task_update_slot] <= 16'd0;
                    velocity_state[task_update_slot]
                        <= task_update_velocity;

                    if (task_update_phase_reset && !clear_phase)
                        phase_state[task_update_slot] <= INITIAL_PHASE_ENABLE
                            ? task_update_initial_phase : 32'd0;
                end else if (!task_update_enable
                             && enable_state[task_update_slot]) begin
                    gate_state[task_update_slot] <= 1'b0;
                    envelope_stage[task_update_slot] <= ENV_RELEASE;
                    envelope_phase[task_update_slot] <= 32'd0;
                    release_start_level[task_update_slot]
                        <= envelope_level[task_update_slot];
                end
            end
        end
    end

endmodule
