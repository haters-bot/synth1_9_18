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
    parameter integer ENVELOPE_UPDATE_DIV = 16,
    parameter [15:0] ATTACK_STEP           = 16'd137,
    parameter [15:0] DECAY_STEP            = 16'd4,
    parameter [15:0] SUSTAIN_LEVEL         = 16'd45875,
    parameter integer RELEASE_SHIFT        = 12,
    parameter [15:0] RELEASE_END_LEVEL     = 16'd1024
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_tick,
    input  wire clear_phase,

    // 全局单槽位状态更新接口。Bank根据槽位编号把更新发送给对应引擎。
    input  wire                  task_update_valid,
    input  wire [7:0]            task_update_slot,
    input  wire [31:0]           task_update_phase_step,
    input  wire [6:0]            task_update_velocity,
    input  wire                  task_update_enable,
    input  wire                  task_update_phase_reset,
    input  wire [5:0]            active_task_count,

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

            wire engine_update_selected;
            wire [7:0] engine_local_slot;

            assign engine_update_selected = task_update_valid
                && (task_update_slot >= engine_index*SLOTS_PER_ENGINE)
                && (task_update_slot < (engine_index+1)*SLOTS_PER_ENGINE);
            assign engine_local_slot = task_update_slot
                                     - engine_index*SLOTS_PER_ENGINE;

            oscillator_tdm_core #(
                .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
                .PARTIAL_SUM_WIDTH(CORE_SUM_WIDTH),
                .ENVELOPE_UPDATE_DIV(ENVELOPE_UPDATE_DIV),
                .ATTACK_STEP(ATTACK_STEP),
                .DECAY_STEP(DECAY_STEP),
                .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
                .RELEASE_SHIFT(RELEASE_SHIFT),
                .RELEASE_END_LEVEL(RELEASE_END_LEVEL)
            ) u_oscillator_tdm_core (
                .clk              (clk),
                .rst_n            (rst_n),
                .start_tick       (start_tick),
                .clear_phase      (clear_phase),
                .task_update_valid(engine_update_selected),
                .task_update_slot(engine_local_slot),
                .task_update_phase_step(task_update_phase_step),
                .task_update_velocity(task_update_velocity),
                .task_update_enable(task_update_enable),
                .task_update_phase_reset(task_update_phase_reset),
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
    wire [16:0] target_gain_q16;
    wire signed [17:0] signed_mix_gain_q16;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_product;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_rounded;
    wire signed [NORMALIZED_WIDTH-1:0] normalized_sum;
    wire all_engines_valid;
    integer sum_index;

    // Q1.16倒数表。0个声部时保持单位增益，使下一次单音可以立即满增益启动。
    // 表项使用round(65536/N)，避免在音频路径中推断动态除法器。
    function [16:0] reciprocal_gain_q16;
        input [5:0] voice_count;
        begin
            case (voice_count)
                6'd0, 6'd1: reciprocal_gain_q16 = 17'd65536;
                6'd2:  reciprocal_gain_q16 = 17'd32768;
                6'd3:  reciprocal_gain_q16 = 17'd21845;
                6'd4:  reciprocal_gain_q16 = 17'd16384;
                6'd5:  reciprocal_gain_q16 = 17'd13107;
                6'd6:  reciprocal_gain_q16 = 17'd10923;
                6'd7:  reciprocal_gain_q16 = 17'd9362;
                6'd8:  reciprocal_gain_q16 = 17'd8192;
                6'd9:  reciprocal_gain_q16 = 17'd7282;
                6'd10: reciprocal_gain_q16 = 17'd6554;
                6'd11: reciprocal_gain_q16 = 17'd5958;
                6'd12: reciprocal_gain_q16 = 17'd5461;
                6'd13: reciprocal_gain_q16 = 17'd5041;
                6'd14: reciprocal_gain_q16 = 17'd4681;
                6'd15: reciprocal_gain_q16 = 17'd4369;
                6'd16: reciprocal_gain_q16 = 17'd4096;
                6'd17: reciprocal_gain_q16 = 17'd3855;
                6'd18: reciprocal_gain_q16 = 17'd3641;
                6'd19: reciprocal_gain_q16 = 17'd3449;
                6'd20: reciprocal_gain_q16 = 17'd3277;
                6'd21: reciprocal_gain_q16 = 17'd3121;
                6'd22: reciprocal_gain_q16 = 17'd2979;
                6'd23: reciprocal_gain_q16 = 17'd2849;
                6'd24: reciprocal_gain_q16 = 17'd2731;
                6'd25: reciprocal_gain_q16 = 17'd2621;
                6'd26: reciprocal_gain_q16 = 17'd2521;
                6'd27: reciprocal_gain_q16 = 17'd2427;
                6'd28: reciprocal_gain_q16 = 17'd2341;
                6'd29: reciprocal_gain_q16 = 17'd2260;
                6'd30: reciprocal_gain_q16 = 17'd2185;
                6'd31: reciprocal_gain_q16 = 17'd2114;
                default: reciprocal_gain_q16 = 17'd2048;
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

    assign target_gain_q16 = reciprocal_gain_q16(active_task_count);
    assign signed_mix_gain_q16 = $signed({1'b0, mix_gain_q16});
    assign normalized_product = $signed(combined_sum)
                                * $signed(signed_mix_gain_q16);
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
        end else begin
            sample_valid <= all_engines_valid;
            if (all_engines_valid) begin
                sample_out <= saturate_to_s16(normalized_sum);

                // 仅在完成一个内部音频采样时更新一次增益。声部数为0时
                // 在静音期间立即恢复单位增益，为下一次单音做好准备。
                if (active_task_count == 6'd0) begin
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
                    // A rising task count can make phase-coherent oscillators
                    // add immediately. Apply attenuation on the first complete
                    // sample; only gain recovery is smoothed.
                    mix_gain_q16 <= target_gain_q16;
                end
            end
        end
    end

endmodule
