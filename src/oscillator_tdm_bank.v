// 参数化的时分复用振荡器引擎组。
//
// 当前验证配置：
//   ENGINE_COUNT       = 1
//   SLOTS_PER_ENGINE   = 4
//   TOTAL_SLOTS        = 4
//
// 所有引擎接收同一个 start_tick，因此会同时完成调度。
// 每个引擎产生一个部分和；本模块将所有部分和相加，再按活动声部数执行
// 平滑的1/N归一化，然后向FIR输出一个采样值。
module oscillator_tdm_bank #(
    parameter integer ENGINE_COUNT        = 1,
    parameter integer SLOTS_PER_ENGINE    = 4,
    parameter integer CORE_SUM_WIDTH      = 24,
    parameter integer BANK_SUM_WIDTH      = 32,
    parameter integer GAIN_SMOOTH_SHIFT   = 12,
    parameter integer INITIAL_PHASE_ENABLE = 0,
    parameter integer REALTIME_DETUNE_ENABLE = 0,
    parameter integer ENVELOPE_UPDATE_DIV = 16
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

    // 当前振荡器组的外部波表双帧缓存装载广播。
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

    // 全局单槽位状态更新接口。Bank根据槽位编号把更新发送给对应引擎。
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
    // 8 个复音各使用 8 个 Unison 成员时共有 64 个任务，活动计数使用 7 位。
    input  wire [6:0]            active_task_count,

    output reg signed [15:0] sample_out,
    output reg               sample_valid,
    output wire              schedule_overrun,
    output wire [(ENGINE_COUNT*SLOTS_PER_ENGINE)-1:0] task_idle_mask,

    // 导出引擎0的调试信号，使仿真器无需探查与实现相关的内部路径，
    // 即可直接观察槽位验证调度过程。
    output wire       debug_engine0_busy,
    output wire [7:0] debug_engine0_slot,
    output wire       debug_engine0_slot_commit
);

    wire [(ENGINE_COUNT*CORE_SUM_WIDTH)-1:0] core_partial_sum_bus;
    wire [ENGINE_COUNT-1:0]                  core_partial_valid;
    wire [ENGINE_COUNT-1:0]                  core_busy;
    wire [(ENGINE_COUNT*8)-1:0]              core_debug_slot_bus;
    wire [ENGINE_COUNT-1:0]                  core_slot_commit;
    wire [ENGINE_COUNT-1:0]                  core_schedule_overrun;
    wire [ENGINE_COUNT-1:0]                  core_task_idle_valid;
    wire [(ENGINE_COUNT*8)-1:0]              core_task_idle_slot_bus;

    genvar engine_index;
    generate
        for (engine_index = 0;
             engine_index < ENGINE_COUNT;
             engine_index = engine_index + 1) begin : GEN_ENGINE

            localparam [7:0] ENGINE_BASE_SLOT =
                engine_index * SLOTS_PER_ENGINE;
            localparam [7:0] ENGINE_END_SLOT =
                (engine_index + 1) * SLOTS_PER_ENGINE;
            wire engine_update_selected;
            wire [7:0] engine_local_slot;

            assign engine_update_selected = task_update_valid
                && (task_update_slot >= ENGINE_BASE_SLOT)
                && (task_update_slot < ENGINE_END_SLOT);
            assign engine_local_slot = task_update_slot
                                     - ENGINE_BASE_SLOT;

            oscillator_tdm_core #(
                .INITIAL_PHASE_ENABLE(INITIAL_PHASE_ENABLE),
                .REALTIME_DETUNE_ENABLE(REALTIME_DETUNE_ENABLE),
                .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
                .PARTIAL_SUM_WIDTH(CORE_SUM_WIDTH),
                .ENVELOPE_UPDATE_DIV(ENVELOPE_UPDATE_DIV)
            ) u_oscillator_tdm_core (
                .clk              (clk),
                .rst_n            (rst_n),
                .start_tick       (start_tick),
                .clear_phase      (clear_phase),
                .waveform_select  (waveform_select),
                .wt_position      (wt_position),
                .warp_mode        (warp_mode),
                .warp_amount      (warp_amount),
                .attack_phase_step(attack_phase_step),
                .decay_phase_step (decay_phase_step),
                .sustain_level    (sustain_level),
                .release_phase_step(release_phase_step),
                .external_wavetable_enable(external_wavetable_enable),
                .cache_load_clk    (cache_load_clk),
                .cache_load_rst_n  (cache_load_rst_n),
                .cache_write_enable(cache_write_enable),
                .cache_write_bank  (cache_write_bank),
                .cache_write_frame (cache_write_frame),
                .cache_write_address(cache_write_address),
                .cache_write_data  (cache_write_data),
                .cache_commit_toggle(cache_commit_toggle),
                .cache_commit_bank (cache_commit_bank),
                .cache_commit_fraction(cache_commit_fraction),
                .task_update_valid(engine_update_selected),
                .task_update_slot(engine_local_slot),
                .task_update_phase_step(task_update_phase_step),
                .task_update_base_step(task_update_base_step),
                .task_update_detune_unit(task_update_detune_unit),
                .task_update_detune_magnitude(
                    task_update_detune_magnitude),
                .task_update_detune_negative(task_update_detune_negative),
                .detune_amount(detune_amount),
                .glide_override_enable(glide_override_enable),
                .glide_override_base_step(glide_override_base_step),
                .vibrato_ratio_delta_q16(vibrato_ratio_delta_q16),
                .task_update_velocity(task_update_velocity),
                .task_update_enable(task_update_enable),
                .task_update_phase_reset(task_update_phase_reset),
                .task_update_initial_phase(task_update_initial_phase),
                .partial_sum      (
                    core_partial_sum_bus[engine_index*CORE_SUM_WIDTH
                                         +: CORE_SUM_WIDTH]),
                .partial_valid    (core_partial_valid[engine_index]),
                .busy             (core_busy[engine_index]),
                .debug_slot       (
                    core_debug_slot_bus[engine_index*8 +: 8]),
                .debug_slot_commit(core_slot_commit[engine_index]),
                .schedule_overrun (
                    core_schedule_overrun[engine_index]),
                .task_idle_valid(core_task_idle_valid[engine_index]),
                .task_idle_slot(
                    core_task_idle_slot_bus[engine_index*8 +: 8])
            );

            assign task_idle_mask[
                engine_index*SLOTS_PER_ENGINE +: SLOTS_PER_ENGINE]
                = core_task_idle_valid[engine_index]
                ? ({{(SLOTS_PER_ENGINE-1){1'b0}}, 1'b1}
                   << core_task_idle_slot_bus[engine_index*8 +: 8])
                : {SLOTS_PER_ENGINE{1'b0}};
        end
    endgenerate

    localparam integer NORMALIZED_WIDTH = BANK_SUM_WIDTH + 18;
    localparam [16:0] UNITY_GAIN_Q16 = 17'd65536;

    reg signed [BANK_SUM_WIDTH-1:0] combined_sum;
    reg [16:0] mix_gain_q16;
    reg [6:0] active_task_count_batch;
    reg signed [BANK_SUM_WIDTH-1:0] normalization_input_sum;
    reg signed [17:0] normalization_input_gain;
    reg normalization_input_valid;
    wire [16:0] target_gain_q16;
    wire [16:0] applied_gain_q16;
    wire signed [17:0] signed_mix_gain_q16;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_product;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_rounded;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_sum;
    wire all_engines_valid;
    integer sum_index;

    // Q1.16倒数表。0个声部时保持单位增益，使下一次单音可以立即满增益启动。
    // 表项使用round(65536/N)，避免在音频路径中推断动态除法器。
    function [16:0] reciprocal_gain_q16;
        input [6:0] voice_count;
        begin
            case (voice_count)
                7'd0, 7'd1: reciprocal_gain_q16 = 17'd65536;
                7'd2:  reciprocal_gain_q16 = 17'd32768;
                7'd3:  reciprocal_gain_q16 = 17'd21845;
                7'd4:  reciprocal_gain_q16 = 17'd16384;
                7'd5:  reciprocal_gain_q16 = 17'd13107;
                7'd6:  reciprocal_gain_q16 = 17'd10923;
                7'd7:  reciprocal_gain_q16 = 17'd9362;
                7'd8:  reciprocal_gain_q16 = 17'd8192;
                7'd9:  reciprocal_gain_q16 = 17'd7282;
                7'd10: reciprocal_gain_q16 = 17'd6554;
                7'd11: reciprocal_gain_q16 = 17'd5958;
                7'd12: reciprocal_gain_q16 = 17'd5461;
                7'd13: reciprocal_gain_q16 = 17'd5041;
                7'd14: reciprocal_gain_q16 = 17'd4681;
                7'd15: reciprocal_gain_q16 = 17'd4369;
                7'd16: reciprocal_gain_q16 = 17'd4096;
                7'd17: reciprocal_gain_q16 = 17'd3855;
                7'd18: reciprocal_gain_q16 = 17'd3641;
                7'd19: reciprocal_gain_q16 = 17'd3449;
                7'd20: reciprocal_gain_q16 = 17'd3277;
                7'd21: reciprocal_gain_q16 = 17'd3121;
                7'd22: reciprocal_gain_q16 = 17'd2979;
                7'd23: reciprocal_gain_q16 = 17'd2849;
                7'd24: reciprocal_gain_q16 = 17'd2731;
                7'd25: reciprocal_gain_q16 = 17'd2621;
                7'd26: reciprocal_gain_q16 = 17'd2521;
                7'd27: reciprocal_gain_q16 = 17'd2427;
                7'd28: reciprocal_gain_q16 = 17'd2341;
                7'd29: reciprocal_gain_q16 = 17'd2260;
                7'd30: reciprocal_gain_q16 = 17'd2185;
                7'd31: reciprocal_gain_q16 = 17'd2114;
                7'd32: reciprocal_gain_q16 = 17'd2048;
                7'd33: reciprocal_gain_q16 = 17'd1986;
                7'd34: reciprocal_gain_q16 = 17'd1928;
                7'd35: reciprocal_gain_q16 = 17'd1872;
                7'd36: reciprocal_gain_q16 = 17'd1820;
                7'd37: reciprocal_gain_q16 = 17'd1771;
                7'd38: reciprocal_gain_q16 = 17'd1725;
                7'd39: reciprocal_gain_q16 = 17'd1680;
                7'd40: reciprocal_gain_q16 = 17'd1638;
                7'd41: reciprocal_gain_q16 = 17'd1598;
                7'd42: reciprocal_gain_q16 = 17'd1560;
                7'd43: reciprocal_gain_q16 = 17'd1524;
                7'd44: reciprocal_gain_q16 = 17'd1489;
                7'd45: reciprocal_gain_q16 = 17'd1456;
                7'd46: reciprocal_gain_q16 = 17'd1425;
                7'd47: reciprocal_gain_q16 = 17'd1394;
                7'd48: reciprocal_gain_q16 = 17'd1365;
                7'd49: reciprocal_gain_q16 = 17'd1337;
                7'd50: reciprocal_gain_q16 = 17'd1311;
                7'd51: reciprocal_gain_q16 = 17'd1285;
                7'd52: reciprocal_gain_q16 = 17'd1260;
                7'd53: reciprocal_gain_q16 = 17'd1237;
                7'd54: reciprocal_gain_q16 = 17'd1214;
                7'd55: reciprocal_gain_q16 = 17'd1192;
                7'd56: reciprocal_gain_q16 = 17'd1170;
                7'd57: reciprocal_gain_q16 = 17'd1150;
                7'd58: reciprocal_gain_q16 = 17'd1129;
                7'd59: reciprocal_gain_q16 = 17'd1111;
                7'd60: reciprocal_gain_q16 = 17'd1092;
                7'd61: reciprocal_gain_q16 = 17'd1074;
                7'd62: reciprocal_gain_q16 = 17'd1057;
                7'd63: reciprocal_gain_q16 = 17'd1040;
                7'd64: reciprocal_gain_q16 = 17'd1024;
                default: reciprocal_gain_q16 = 17'd1024;
            endcase
        end
    endfunction

    // 使用组合逻辑归并各引擎的部分和。ENGINE_COUNT=1 时这里只进行符号扩展；
    // 每增加一个引擎，就会增加一个求和项。
    always @(*) begin
        combined_sum = {BANK_SUM_WIDTH{1'b0}};
        for (sum_index = 0;
             sum_index < ENGINE_COUNT;
             sum_index = sum_index + 1)
            combined_sum = combined_sum
                         + $signed(core_partial_sum_bus[
                               sum_index*CORE_SUM_WIDTH +: CORE_SUM_WIDTH]);
    end

    // 活动槽位数只在一批TDM任务开始时锁存。这样32槽位统计逻辑不会
    // 继续穿过倒数增益、乘法器和顶层混音器形成单周期长路径。
    assign target_gain_q16 = reciprocal_gain_q16(active_task_count_batch);
    // 声部数增加时目标增益会突然降低。乘法路径立即采用较小值，
    // 避免寄存器尚未更新的首个采样仍以旧增益输出并发生饱和。
    // 声部数减少时仍使用mix_gain_q16缓慢恢复，防止音量跳变。
    assign applied_gain_q16 = (target_gain_q16 < mix_gain_q16)
                            ? target_gain_q16 : mix_gain_q16;
    assign signed_mix_gain_q16 = $signed({1'b0, applied_gain_q16});
    // 先寄存部分和及其对应增益，再进入DSP乘法器。该边界切断了
    // 波表/包络提交逻辑到归一化乘法器之间的跨模块长路径。
    assign normalized_product = $signed(normalization_input_sum)
                                * $signed(normalization_input_gain);
    assign normalized_rounded = normalized_product
                              + $signed({{(NORMALIZED_WIDTH-16){1'b0}},
                                         16'h8000});
    assign normalized_sum = normalized_rounded >>> 16;
    assign all_engines_valid = &core_partial_valid;
    assign schedule_overrun = |core_schedule_overrun;

    assign debug_engine0_busy = core_busy[0];
    assign debug_engine0_slot = core_debug_slot_bus[7:0];
    assign debug_engine0_slot_commit = core_slot_commit[0];

    function signed [15:0] saturate_to_s16;
        input signed [NORMALIZED_WIDTH-1:0] value;
        begin
            if (value > 32767)
                saturate_to_s16 = 16'sh7FFF;
            else if (value < -32768)
                saturate_to_s16 = 16'sh8000;
            else
                saturate_to_s16 = value[15:0];
        end
    endfunction

    // 核心的部分和在其时钟沿之后生效。本级寄存器在下一个时钟沿读取这些结果，
    // 并向FIR封装模块提供时序清晰的 sample_valid/sample_out 信号对。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out   <= 16'sd0;
            sample_valid <= 1'b0;
            mix_gain_q16 <= UNITY_GAIN_Q16;
            active_task_count_batch <= 7'd0;
            normalization_input_sum <= {BANK_SUM_WIDTH{1'b0}};
            normalization_input_gain <= 18'sd0;
            normalization_input_valid <= 1'b0;
        end else begin
            sample_valid <= normalization_input_valid;
            normalization_input_valid <= all_engines_valid;
            if (start_tick)
                active_task_count_batch <= active_task_count;

            if (all_engines_valid) begin
                normalization_input_sum <= combined_sum;
                normalization_input_gain <= signed_mix_gain_q16;

                // 仅在完成一个内部音频采样时更新一次增益。
                if (active_task_count_batch == 7'd0) begin
                    mix_gain_q16 <= UNITY_GAIN_Q16;
                end else if (mix_gain_q16 < target_gain_q16) begin
                    if (((target_gain_q16 - mix_gain_q16)
                         >> GAIN_SMOOTH_SHIFT) == 17'd0)
                        mix_gain_q16 <= mix_gain_q16 + 17'd1;
                    else
                        mix_gain_q16 <= mix_gain_q16
                                      + ((target_gain_q16 - mix_gain_q16)
                                         >> GAIN_SMOOTH_SHIFT);
                end else if (mix_gain_q16 > target_gain_q16) begin
                    mix_gain_q16 <= target_gain_q16;
                end
            end

            if (normalization_input_valid) begin
                sample_out <= saturate_to_s16(normalized_sum);
            end
        end
    end

endmodule
