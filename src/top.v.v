// 双振荡器、每组32槽位时分复用与MAX98357A音频输出顶层。
module top #(
    parameter integer UART_BAUD_RATE = 31250,
    parameter integer DEFAULT_UNISON_COUNT = 1,
    parameter integer OSC_ENGINE_COUNT = 1,
    parameter integer SLOTS_PER_ENGINE = 32
)(
    input  wire sys_clk,       // 50 MHz板载时钟，引脚V22
    input  wire rst_n,         // 低电平有效的板载复位，引脚AA13
    input  wire uart_rx,       // 板载USB-UART接收，引脚V14
    output wire MAX_SD,        // MAX98357A使能，引脚AB20
    output wire MAX_GAIN,      // MAX98357A增益选择，引脚AA21
    output wire MAX_DIN,       // MAX98357A串行音频数据，引脚AB22
    output wire MAX_BCLK,      // MAX98357A位时钟，引脚Y22
    output wire MAX_LRC,       // MAX98357A左右声道时钟，引脚Y21
    output wire PA_EN          // 板载NS4263使能，低电平有效，引脚AB16
);

    // 验证阶段：OSC A和OSC B各使用1个实体引擎，每个引擎时分复用32个槽位。
    // 参数接口为后续扩展保留；当前活动计数与归一化路径按每组最多32任务验证。
    localparam integer OSC_TOTAL_SLOTS      =
        OSC_ENGINE_COUNT * SLOTS_PER_ENGINE;
    wire clk_sys;
    wire rst_n_sys;
    wire pll_locked;
    wire sample_tick;
    wire oversample_tick;
    wire oscillator_start_tick;

    wire signed [15:0] osc_a_mix;
    wire signed [15:0] osc_b_mix;
    wire               osc_a_mix_valid;
    wire               osc_b_mix_valid;
    wire               osc_a_schedule_overrun;
    wire               osc_b_schedule_overrun;
    reg  [8:0]          osc_a_mix_gain_q8;
    reg  [8:0]          osc_b_mix_gain_q8;
    wire [8:0]          osc_a_mix_gain_target_q8;
    wire [8:0]          osc_b_mix_gain_target_q8;
    wire signed [25:0]  osc_a_scaled_product_next;
    wire signed [25:0]  osc_b_scaled_product_next;
    reg  signed [25:0]  osc_a_scaled_product;
    reg  signed [25:0]  osc_b_scaled_product;
    wire signed [26:0]  oscillator_scaled_sum;
    wire signed [15:0]  oscillator_mix;
    reg                 oscillator_mix_valid;
    wire                oscillator_schedule_overrun;
    wire signed [15:0]  fir_input_sample;
    wire signed [15:0]  fir_filtered_sample;
    wire signed [15:0]  global_filtered_sample;

    wire [OSC_TOTAL_SLOTS-1:0] osc_a_task_idle_mask;
    wire [OSC_TOTAL_SLOTS-1:0] osc_b_task_idle_mask;
    wire [6:0] osc_a_active_task_count;
    wire [6:0] osc_b_active_task_count;

    wire       debug_osc_a_busy;
    wire [7:0] debug_osc_a_slot;
    wire       debug_osc_a_slot_commit;
    wire       debug_osc_b_busy;
    wire [7:0] debug_osc_b_slot;
    wire       debug_osc_b_slot_commit;

    wire        osc_a_task_update_valid;
    wire [7:0]  osc_a_task_update_slot;
    wire [31:0] osc_a_task_update_phase_step;
    wire [6:0]  osc_a_task_update_velocity;
    wire        osc_a_task_update_enable;
    wire        osc_a_task_update_phase_reset;
    wire        osc_a_scheduler_busy;

    wire        osc_b_task_update_valid;
    wire [7:0]  osc_b_task_update_slot;
    wire [31:0] osc_b_task_update_phase_step;
    wire [6:0]  osc_b_task_update_velocity;
    wire        osc_b_task_update_enable;
    wire        osc_b_task_update_phase_reset;
    wire        osc_b_scheduler_busy;

    wire [7:0] uart_byte;
    wire       uart_byte_valid;
    wire       uart_framing_error;
    wire       midi_note_event_valid;
    wire       midi_note_event_on;
    wire [3:0] midi_note_event_channel;
    wire [6:0] midi_note_event_note;
    wire [6:0] midi_note_event_velocity;
    wire       midi_control_change_valid;
    wire [3:0] midi_control_change_channel;
    wire [6:0] midi_control_change_number;
    wire [6:0] midi_control_change_value;
    wire       highres_parameter_valid;
    wire [6:0] highres_parameter_id;
    wire [13:0] highres_parameter_value;
    wire       filter_cutoff_cc_valid;
    wire       filter_cutoff_interpolation_busy;
    wire [14:0] filter_cutoff_manual_q8;
    wire        filter_lfo_enabled;
    wire        filter_lfo_active_segment;
    wire [23:0] filter_lfo_segment_phase;
    wire       routed_note_event_valid;
    wire       routed_note_event_on;
    wire [6:0] routed_note_event_note;
    wire [6:0] routed_note_event_velocity;
    wire [6:0] pan_target;
    wire [2:0] filter_mode_target;
    reg  [2:0] filter_mode_active;
    wire [6:0] filter_cutoff_target;
    wire [14:0] filter_cutoff_current_q8;
    wire [6:0] filter_resonance_target;
    reg  [6:0] filter_resonance_current;
    wire [6:0] filter_mix_target;
    reg  [6:0] filter_mix_current;

    wire [6:0] osc_a_wt_position_target;
    reg  [6:0] osc_a_wt_position_current;
    wire [2:0] osc_a_waveform_select;
    wire [6:0] osc_a_detune_amount;
    wire [3:0] osc_a_unison_count;
    wire [6:0] osc_a_attack_control;
    wire [6:0] osc_a_decay_control;
    wire [6:0] osc_a_sustain_control_target;
    reg  [6:0] osc_a_sustain_control_current;
    wire [6:0] osc_a_release_control;
    wire [31:0] osc_a_attack_phase_step;
    wire [31:0] osc_a_decay_phase_step;
    wire [15:0] osc_a_sustain_level;
    wire [31:0] osc_a_release_phase_step;
    wire        osc_a_enabled;
    wire [3:0]  osc_a_warp_mode;
    reg  [3:0]  osc_a_warp_mode_active;
    wire [6:0]  osc_a_warp_amount_target;
    reg  [6:0]  osc_a_warp_amount_current;

    wire [6:0] osc_b_wt_position_target;
    reg  [6:0] osc_b_wt_position_current;
    wire [2:0] osc_b_waveform_select;
    wire [6:0] osc_b_detune_amount;
    wire [3:0] osc_b_unison_count;
    wire [6:0] osc_b_attack_control;
    wire [6:0] osc_b_decay_control;
    wire [6:0] osc_b_sustain_control_target;
    reg  [6:0] osc_b_sustain_control_current;
    wire [6:0] osc_b_release_control;
    wire [31:0] osc_b_attack_phase_step;
    wire [31:0] osc_b_decay_phase_step;
    wire [15:0] osc_b_sustain_level;
    wire [31:0] osc_b_release_phase_step;
    wire        osc_b_enabled;
    wire [3:0]  osc_b_warp_mode;
    reg  [3:0]  osc_b_warp_mode_active;
    wire [6:0]  osc_b_warp_amount_target;
    reg  [6:0]  osc_b_warp_amount_current;

    wire fir_input_ready;
    wire fir_output_valid;
    wire fir_input_overrun;
    wire global_filter_input_ready;
    wire global_filter_output_valid;
    wire global_filter_input_overrun;

    // 使用外接MAX98357A，关闭板载NS4263。SD和GAIN保持高电平。
    assign PA_EN    = 1'b1;
    assign MAX_SD   = 1'b1;
    assign MAX_GAIN = 1'b1;

    sys_clock_manager u_sys_clock_manager (
        .clk_ref_50m(sys_clk),
        .rst_n_async(rst_n),
        .clk_sys    (clk_sys),
        .rst_n_sys  (rst_n_sys),
        .pll_locked (pll_locked)
    );

    assign oscillator_start_tick = oversample_tick;
    assign filter_cutoff_cc_valid = midi_control_change_valid
                                  && (midi_control_change_channel == 4'd15)
                                  && (midi_control_change_number == 7'd43);

    // 两组WT Position、Warp Amount和全局滤波参数均在96 kHz边界平滑。
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            osc_a_wt_position_current <= 7'd0;
            osc_b_wt_position_current <= 7'd0;
            osc_a_warp_mode_active <= 4'd0;
            osc_b_warp_mode_active <= 4'd0;
            osc_a_warp_amount_current <= 7'd0;
            osc_b_warp_amount_current <= 7'd0;
            filter_resonance_current <= 7'd0;
            filter_mode_active <= 3'd0;
            filter_mix_current <= 7'd127;
        end else if (sample_tick) begin
            if (osc_a_wt_position_current < osc_a_wt_position_target)
                osc_a_wt_position_current <= osc_a_wt_position_current + 7'd1;
            else if (osc_a_wt_position_current > osc_a_wt_position_target)
                osc_a_wt_position_current <= osc_a_wt_position_current - 7'd1;

            if (osc_b_wt_position_current < osc_b_wt_position_target)
                osc_b_wt_position_current <= osc_b_wt_position_current + 7'd1;
            else if (osc_b_wt_position_current > osc_b_wt_position_target)
                osc_b_wt_position_current <= osc_b_wt_position_current - 7'd1;

            // Warp模式只在深度为0时切换。切换过程中先平滑退回原始地址，
            // 再换模式并升到新目标，避免两种地址映射直接跳变产生咔哒声。
            if (osc_a_warp_mode_active != osc_a_warp_mode) begin
                if (osc_a_warp_amount_current != 7'd0)
                    osc_a_warp_amount_current <= osc_a_warp_amount_current - 7'd1;
                else
                    osc_a_warp_mode_active <= osc_a_warp_mode;
            end else if (osc_a_warp_mode_active == 4'd0) begin
                osc_a_warp_amount_current <= 7'd0;
            end else if (osc_a_warp_amount_current < osc_a_warp_amount_target) begin
                osc_a_warp_amount_current <= osc_a_warp_amount_current + 7'd1;
            end else if (osc_a_warp_amount_current > osc_a_warp_amount_target) begin
                osc_a_warp_amount_current <= osc_a_warp_amount_current - 7'd1;
            end

            if (osc_b_warp_mode_active != osc_b_warp_mode) begin
                if (osc_b_warp_amount_current != 7'd0)
                    osc_b_warp_amount_current <= osc_b_warp_amount_current - 7'd1;
                else
                    osc_b_warp_mode_active <= osc_b_warp_mode;
            end else if (osc_b_warp_mode_active == 4'd0) begin
                osc_b_warp_amount_current <= 7'd0;
            end else if (osc_b_warp_amount_current < osc_b_warp_amount_target) begin
                osc_b_warp_amount_current <= osc_b_warp_amount_current + 7'd1;
            end else if (osc_b_warp_amount_current > osc_b_warp_amount_target) begin
                osc_b_warp_amount_current <= osc_b_warp_amount_current - 7'd1;
            end

            if (filter_resonance_current < filter_resonance_target)
                filter_resonance_current <= filter_resonance_current + 7'd1;
            else if (filter_resonance_current > filter_resonance_target)
                filter_resonance_current <= filter_resonance_current - 7'd1;

            // 模式切换时先退回全干声，再切换算法并恢复目标Mix，避免状态跳变。
            if (filter_mode_active != filter_mode_target) begin
                if (filter_mix_current != 7'd0)
                    filter_mix_current <= filter_mix_current - 7'd1;
                else
                    filter_mode_active <= filter_mode_target;
            end else if (filter_mix_current < filter_mix_target) begin
                filter_mix_current <= filter_mix_current + 7'd1;
            end else if (filter_mix_current > filter_mix_target) begin
                filter_mix_current <= filter_mix_current - 7'd1;
            end
        end
    end

    // 两个振荡器都开启时各占一半增益；只开启一路时该路使用单位增益。
    // Q1.8增益在96 kHz边界每次移动1，完整0～1斜坡约为2.67 ms。
    assign osc_a_mix_gain_target_q8 = !osc_a_enabled ? 9'd0
                                         : osc_b_enabled ? 9'd128 : 9'd256;
    assign osc_b_mix_gain_target_q8 = !osc_b_enabled ? 9'd0
                                         : osc_a_enabled ? 9'd128 : 9'd256;

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            osc_a_mix_gain_q8 <= 9'd128;
            osc_b_mix_gain_q8 <= 9'd128;
        end else if (sample_tick) begin
            if (osc_a_mix_gain_q8 < osc_a_mix_gain_target_q8)
                osc_a_mix_gain_q8 <= osc_a_mix_gain_q8 + 9'd1;
            else if (osc_a_mix_gain_q8 > osc_a_mix_gain_target_q8)
                osc_a_mix_gain_q8 <= osc_a_mix_gain_q8 - 9'd1;

            if (osc_b_mix_gain_q8 < osc_b_mix_gain_target_q8)
                osc_b_mix_gain_q8 <= osc_b_mix_gain_q8 + 9'd1;
            else if (osc_b_mix_gain_q8 > osc_b_mix_gain_target_q8)
                osc_b_mix_gain_q8 <= osc_b_mix_gain_q8 - 9'd1;
        end
    end

    // Sustain会直接改变保持电平，因此同样在96 kHz边界逐级移动。
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            osc_a_sustain_control_current <= 7'd89;
            osc_b_sustain_control_current <= 7'd89;
        end else if (sample_tick) begin
            if (osc_a_sustain_control_current < osc_a_sustain_control_target)
                osc_a_sustain_control_current
                    <= osc_a_sustain_control_current + 7'd1;
            else if (osc_a_sustain_control_current
                     > osc_a_sustain_control_target)
                osc_a_sustain_control_current
                    <= osc_a_sustain_control_current - 7'd1;

            if (osc_b_sustain_control_current < osc_b_sustain_control_target)
                osc_b_sustain_control_current
                    <= osc_b_sustain_control_current + 7'd1;
            else if (osc_b_sustain_control_current
                     > osc_b_sustain_control_target)
                osc_b_sustain_control_current
                    <= osc_b_sustain_control_current - 7'd1;
        end
    end

    uart_rx #(
        .CLK_HZ   (50000000),
        .BAUD_RATE(UART_BAUD_RATE)
    ) u_uart_rx (
        .clk          (clk_sys),
        .rst_n        (rst_n_sys),
        .rx           (uart_rx),
        .data         (uart_byte),
        .data_valid   (uart_byte_valid),
        .framing_error(uart_framing_error)
    );

    midi_note_parser u_midi_note_parser (
        .clk                   (clk_sys),
        .rst_n                 (rst_n_sys),
        .byte_data             (uart_byte),
        .byte_valid            (uart_byte_valid),
        .note_event_valid      (midi_note_event_valid),
        .note_event_on         (midi_note_event_on),
        .note_event_channel    (midi_note_event_channel),
        .note_event_note       (midi_note_event_note),
        .note_event_velocity   (midi_note_event_velocity),
        .control_change_valid  (midi_control_change_valid),
        .control_change_channel(midi_control_change_channel),
        .control_change_number (midi_control_change_number),
        .control_change_value  (midi_control_change_value)
    );

    highres_parameter_parser u_highres_parameter_parser (
        .clk            (clk_sys),
        .rst_n          (rst_n_sys),
        .byte_data      (uart_byte),
        .byte_valid     (uart_byte_valid),
        .parameter_valid(highres_parameter_valid),
        .parameter_id   (highres_parameter_id),
        .parameter_value(highres_parameter_value)
    );

    // 静态CC43仍经过5.33 ms平滑器。高精度SysEx只负责写入LFO配置，
    // 不再周期性覆盖Cutoff目标。
    parameter_linear_interpolator #(
        .VALUE_WIDTH(15),
        .INTERPOLATION_SHIFT(9),
        .RESET_VALUE({7'd127, 8'd0})
    ) u_filter_cutoff_interpolator (
        .clk          (clk_sys),
        .rst_n        (rst_n_sys),
        .sample_tick  (sample_tick),
        .target_valid (filter_cutoff_cc_valid),
        .target_value ({midi_control_change_value, 8'd0}),
        .current_value(filter_cutoff_manual_q8),
        .busy         (filter_cutoff_interpolation_busy)
    );

    // 三点两曲率LFO在FPGA内部以96 kHz运行。SysEx参数先写影子寄存器，
    // 收到commit后同时生效，避免逐字段更新造成中间状态。
    filter_curve_lfo u_filter_curve_lfo (
        .clk            (clk_sys),
        .rst_n          (rst_n_sys),
        .sample_tick    (sample_tick),
        .parameter_valid(highres_parameter_valid),
        .parameter_id   (highres_parameter_id),
        .parameter_value(highres_parameter_value),
        .filter_mode    (filter_mode_active),
        .base_cutoff_q8 (filter_cutoff_manual_q8),
        .cutoff_q8      (filter_cutoff_current_q8),
        .lfo_enabled    (filter_lfo_enabled),
        .active_segment (filter_lfo_active_segment),
        .segment_phase  (filter_lfo_segment_phase)
    );

    synth_control_router #(
        .PERFORMANCE_CHANNEL  (4'd0),
        .CONTROL_CHANNEL      (4'd15),
        .DEFAULT_UNISON_COUNT (DEFAULT_UNISON_COUNT)
    ) u_synth_control_router (
        .clk                       (clk_sys),
        .rst_n                     (rst_n_sys),
        .raw_note_event_valid      (midi_note_event_valid),
        .raw_note_event_on         (midi_note_event_on),
        .raw_note_event_channel    (midi_note_event_channel),
        .raw_note_event_note       (midi_note_event_note),
        .raw_note_event_velocity   (midi_note_event_velocity),
        .raw_control_change_valid  (midi_control_change_valid),
        .raw_control_change_channel(midi_control_change_channel),
        .raw_control_change_number (midi_control_change_number),
        .raw_control_change_value  (midi_control_change_value),
        .note_event_valid          (routed_note_event_valid),
        .note_event_on             (routed_note_event_on),
        .note_event_note           (routed_note_event_note),
        .note_event_velocity       (routed_note_event_velocity),
        .pan_target                (pan_target),
        .filter_mode               (filter_mode_target),
        .filter_cutoff             (filter_cutoff_target),
        .filter_resonance          (filter_resonance_target),
        .filter_mix                (filter_mix_target),
        .osc_a_wt_position_target  (osc_a_wt_position_target),
        .osc_a_waveform_select     (osc_a_waveform_select),
        .osc_a_detune_amount       (osc_a_detune_amount),
        .osc_a_unison_count        (osc_a_unison_count),
        .osc_a_attack_control      (osc_a_attack_control),
        .osc_a_decay_control       (osc_a_decay_control),
        .osc_a_sustain_control     (osc_a_sustain_control_target),
        .osc_a_release_control     (osc_a_release_control),
        .osc_a_enabled             (osc_a_enabled),
        .osc_a_warp_mode           (osc_a_warp_mode),
        .osc_a_warp_amount         (osc_a_warp_amount_target),
        .osc_b_wt_position_target  (osc_b_wt_position_target),
        .osc_b_waveform_select     (osc_b_waveform_select),
        .osc_b_detune_amount       (osc_b_detune_amount),
        .osc_b_unison_count        (osc_b_unison_count),
        .osc_b_attack_control      (osc_b_attack_control),
        .osc_b_decay_control       (osc_b_decay_control),
        .osc_b_sustain_control     (osc_b_sustain_control_target),
        .osc_b_release_control     (osc_b_release_control),
        .osc_b_enabled             (osc_b_enabled),
        .osc_b_warp_mode           (osc_b_warp_mode),
        .osc_b_warp_amount         (osc_b_warp_amount_target)
    );

    adsr_parameter_mapper u_osc_a_adsr_parameter_mapper (
        .attack_control    (osc_a_attack_control),
        .decay_control     (osc_a_decay_control),
        .sustain_control   (osc_a_sustain_control_current),
        .release_control   (osc_a_release_control),
        .attack_phase_step (osc_a_attack_phase_step),
        .decay_phase_step  (osc_a_decay_phase_step),
        .sustain_level     (osc_a_sustain_level),
        .release_phase_step(osc_a_release_phase_step)
    );

    adsr_parameter_mapper u_osc_b_adsr_parameter_mapper (
        .attack_control    (osc_b_attack_control),
        .decay_control     (osc_b_decay_control),
        .sustain_control   (osc_b_sustain_control_current),
        .release_control   (osc_b_release_control),
        .attack_phase_step (osc_b_attack_phase_step),
        .decay_phase_step  (osc_b_decay_phase_step),
        .sustain_level     (osc_b_sustain_level),
        .release_phase_step(osc_b_release_phase_step)
    );

    oscillator_task_scheduler #(
        .ENGINE_COUNT    (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_osc_a_task_scheduler (
        .clk                     (clk_sys),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (routed_note_event_valid),
        .note_event_on           (routed_note_event_on),
        .note_event_note         (routed_note_event_note),
        .note_event_velocity     (routed_note_event_velocity),
        .unison_count            (osc_a_unison_count),
        .detune_amount           (osc_a_detune_amount),
        .task_idle_mask          (osc_a_task_idle_mask),
        .task_update_valid       (osc_a_task_update_valid),
        .task_update_slot        (osc_a_task_update_slot),
        .task_update_phase_step  (osc_a_task_update_phase_step),
        .task_update_velocity    (osc_a_task_update_velocity),
        .task_update_enable      (osc_a_task_update_enable),
        .task_update_phase_reset (osc_a_task_update_phase_reset),
        .active_task_count       (osc_a_active_task_count),
        .scheduler_busy          (osc_a_scheduler_busy)
    );

    oscillator_task_scheduler #(
        .ENGINE_COUNT    (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_osc_b_task_scheduler (
        .clk                     (clk_sys),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (routed_note_event_valid),
        .note_event_on           (routed_note_event_on),
        .note_event_note         (routed_note_event_note),
        .note_event_velocity     (routed_note_event_velocity),
        .unison_count            (osc_b_unison_count),
        .detune_amount           (osc_b_detune_amount),
        .task_idle_mask          (osc_b_task_idle_mask),
        .task_update_valid       (osc_b_task_update_valid),
        .task_update_slot        (osc_b_task_update_slot),
        .task_update_phase_step  (osc_b_task_update_phase_step),
        .task_update_velocity    (osc_b_task_update_velocity),
        .task_update_enable      (osc_b_task_update_enable),
        .task_update_phase_reset (osc_b_task_update_phase_reset),
        .active_task_count       (osc_b_active_task_count),
        .scheduler_busy          (osc_b_scheduler_busy)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT      (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE  (SLOTS_PER_ENGINE)
    ) u_osc_a_tdm_bank (
        .clk                       (clk_sys),
        .rst_n                     (rst_n_sys),
        .start_tick                (oscillator_start_tick),
        .clear_phase               (1'b0),
        .waveform_select           (osc_a_waveform_select),
        .wt_position               (osc_a_wt_position_current),
        .warp_mode                 (osc_a_warp_mode_active),
        .warp_amount               (osc_a_warp_amount_current),
        .attack_phase_step         (osc_a_attack_phase_step),
        .decay_phase_step          (osc_a_decay_phase_step),
        .sustain_level             (osc_a_sustain_level),
        .release_phase_step        (osc_a_release_phase_step),
        .task_update_valid         (osc_a_task_update_valid),
        .task_update_slot          (osc_a_task_update_slot),
        .task_update_phase_step    (osc_a_task_update_phase_step),
        .task_update_velocity      (osc_a_task_update_velocity),
        .task_update_enable        (osc_a_task_update_enable),
        .task_update_phase_reset   (osc_a_task_update_phase_reset),
        .active_task_count         (osc_a_active_task_count),
        .sample_out                (osc_a_mix),
        .sample_valid              (osc_a_mix_valid),
        .schedule_overrun          (osc_a_schedule_overrun),
        .task_idle_mask            (osc_a_task_idle_mask),
        .debug_engine0_busy        (debug_osc_a_busy),
        .debug_engine0_slot        (debug_osc_a_slot),
        .debug_engine0_slot_commit (debug_osc_a_slot_commit)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT      (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE  (SLOTS_PER_ENGINE)
    ) u_osc_b_tdm_bank (
        .clk                       (clk_sys),
        .rst_n                     (rst_n_sys),
        .start_tick                (oscillator_start_tick),
        .clear_phase               (1'b0),
        .waveform_select           (osc_b_waveform_select),
        .wt_position               (osc_b_wt_position_current),
        .warp_mode                 (osc_b_warp_mode_active),
        .warp_amount               (osc_b_warp_amount_current),
        .attack_phase_step         (osc_b_attack_phase_step),
        .decay_phase_step          (osc_b_decay_phase_step),
        .sustain_level             (osc_b_sustain_level),
        .release_phase_step        (osc_b_release_phase_step),
        .task_update_valid         (osc_b_task_update_valid),
        .task_update_slot          (osc_b_task_update_slot),
        .task_update_phase_step    (osc_b_task_update_phase_step),
        .task_update_velocity      (osc_b_task_update_velocity),
        .task_update_enable        (osc_b_task_update_enable),
        .task_update_phase_reset   (osc_b_task_update_phase_reset),
        .active_task_count         (osc_b_active_task_count),
        .sample_out                (osc_b_mix),
        .sample_valid              (osc_b_mix_valid),
        .schedule_overrun          (osc_b_schedule_overrun),
        .task_idle_mask            (osc_b_task_idle_mask),
        .debug_engine0_busy        (debug_osc_b_busy),
        .debug_engine0_slot        (debug_osc_b_slot),
        .debug_engine0_slot_commit (debug_osc_b_slot_commit)
    );

    // 每组Bank已经按自己的活动任务数归一化。这里应用开关平滑增益，
    // 两路目标增益之和始终不超过1.0，最后再饱和到16位。
    assign osc_a_scaled_product_next =
        $signed(osc_a_mix) * $signed({1'b0, osc_a_mix_gain_q8});
    assign osc_b_scaled_product_next =
        $signed(osc_b_mix) * $signed({1'b0, osc_b_mix_gain_q8});

    // 先寄存两路DSP乘法结果，再进行求和与饱和。增加一个50 MHz时钟延迟，
    // 但切断Bank归一化、开关增益乘法和FIR输入之间的长组合路径。
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            osc_a_scaled_product <= 26'sd0;
            osc_b_scaled_product <= 26'sd0;
            oscillator_mix_valid <= 1'b0;
        end else begin
            oscillator_mix_valid <= osc_a_mix_valid && osc_b_mix_valid;
            if (osc_a_mix_valid && osc_b_mix_valid) begin
                osc_a_scaled_product <= osc_a_scaled_product_next;
                osc_b_scaled_product <= osc_b_scaled_product_next;
            end
        end
    end

    assign oscillator_scaled_sum =
        $signed(osc_a_scaled_product) + $signed(osc_b_scaled_product);

    function signed [15:0] saturate_mix_q8;
        input signed [26:0] value;
        reg signed [26:0] shifted_value;
        begin
            shifted_value = value >>> 8;
            if (shifted_value > 32767)
                saturate_mix_q8 = 16'sh7FFF;
            else if (shifted_value < -32768)
                saturate_mix_q8 = 16'sh8000;
            else
                saturate_mix_q8 = shifted_value[15:0];
        end
    endfunction

    assign oscillator_mix = saturate_mix_q8(oscillator_scaled_sum);
    assign oscillator_schedule_overrun =
        osc_a_schedule_overrun || osc_b_schedule_overrun;
    assign fir_input_sample = oscillator_mix;

    fir_decimator_8x_wrapper u_fir_decimator_8x_wrapper (
        .clk          (clk_sys),
        .rst_n        (rst_n_sys),
        .in_valid     (oscillator_mix_valid),
        .sample_in    (fir_input_sample),
        .in_ready     (fir_input_ready),
        .out_valid    (fir_output_valid),
        .sample_out   (fir_filtered_sample),
        .input_overrun(fir_input_overrun)
    );

    global_filter u_global_filter (
        .clk              (clk_sys),
        .rst_n            (rst_n_sys),
        .in_valid         (fir_output_valid),
        .sample_in        (fir_filtered_sample),
        .in_ready         (global_filter_input_ready),
        .filter_mode      (filter_mode_active),
        .cutoff_control_q8(filter_cutoff_current_q8),
        .resonance_control(filter_resonance_current),
        .mix_control      (filter_mix_current),
        .out_valid        (global_filter_output_valid),
        .sample_out       (global_filtered_sample),
        .input_overrun    (global_filter_input_overrun)
    );

    i2s_tx u_max98357a_i2s_tx (
        .sys_clk        (clk_sys),
        .rst_n          (rst_n_sys),
        .sample_data    (global_filtered_sample),
        .bclk           (MAX_BCLK),
        .lrck           (MAX_LRC),
        .sdata          (MAX_DIN),
        .sample_tick    (sample_tick),
        .oversample_tick(oversample_tick)
    );

endmodule
