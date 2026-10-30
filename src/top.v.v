// 双振荡器、每组32槽位时分复用与MAX98357A音频输出顶层。
module top #(
    parameter integer UART_BAUD_RATE = 31250,
    parameter integer CONTROL_UART_BAUD_RATE = 31250,
    parameter integer KEYBOARD_UART_BAUD_RATE = 31250,
    parameter integer DEFAULT_UNISON_COUNT = 1,
    parameter integer OSC_ENGINE_COUNT = 1,
    parameter integer SLOTS_PER_ENGINE = 32,
    parameter integer EXTERNAL_WAVETABLE_ENABLE = 1
)(
    input  wire sys_clk,       // 50 MHz板载时钟，引脚V22
    input  wire rst_n,         // 低电平有效的板载复位，引脚AA13
    input  wire control_uart_rx, // C19; 独立音色控制UART RX，3.3 V，空闲高电平
    input  wire keyboard_uart_rx, // E19; 实体MIDI键盘转换后的3.3 V UART RX
    input  wire uart_rx,       // 板载USB-UART接收，引脚V14
    output wire MAX_SD,        // MAX98357A使能，引脚AB20
    output wire MAX_GAIN,      // MAX98357A增益选择，引脚AA21
    output wire MAX_DIN,       // MAX98357A串行音频数据，引脚AB22
    output wire MAX_BCLK,      // MAX98357A位时钟，引脚Y22
    output wire MAX_LRC,       // MAX98357A左右声道时钟，引脚Y21
    output wire VIS_BCLK,      // 音频可视化从机位时钟，引脚R19
    output wire VIS_LRC,       // 音频可视化从机左右声道时钟，引脚U21
    output wire VIS_DIN,       // 音频可视化从机串行数据，引脚R17
    output wire HP_BCK,        // 板载PT8211位时钟，引脚Y17
    output wire HP_WS,         // 板载PT8211字选择信号，引脚AB17
    output wire HP_DIN,        // 板载PT8211串行数据，引脚AA16
    output wire PA_EN,         // 板载NS4263使能，低电平有效，引脚AB16

    output wire        sd_clk,
    inout  wire        sd_cmd,
    input  wire        sd_dat0,
    output wire [14:0] ddr_addr,
    output wire [2:0]  ddr_bank,
    output wire        ddr_cs,
    output wire        ddr_ras,
    output wire        ddr_cas,
    output wire        ddr_we,
    output wire        ddr_ck,
    output wire        ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_reset_n,
    output wire [3:0]  ddr_dm,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dqs,
    inout  wire [3:0]  ddr_dqs_n
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
    wire signed [26:0]  oscillator_mix_shifted;
    wire signed [15:0]  oscillator_mix;
    wire                oscillator_mix_clip_now;
    reg                 oscillator_mix_valid;
    wire                oscillator_schedule_overrun;
    wire signed [15:0]  fir_input_sample;
    wire signed [15:0]  fir_filtered_sample;
    wire signed [15:0]  global_filtered_sample;
    wire signed [15:0]  effect_processed_sample;
    reg  signed [15:0]  master_output_sample;
    wire signed [25:0]  master_scaled_product;
    wire signed [26:0]  master_scaled_product_extended;
    wire signed [26:0]  master_scaled_shifted;
    wire                master_output_clip_now;
    wire                filter_output_limit_now;
    reg                 oscillator_mix_clip;
    reg                 filter_output_limit;
    reg                 master_output_clip;
    reg  [31:0]         audio_clip_count;

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
    wire [31:0] osc_a_task_update_base_step;
    wire [31:0] osc_a_task_update_initial_phase;
    wire [34:0] osc_a_task_update_detune_unit;
    wire [2:0]  osc_a_task_update_detune_magnitude;
    wire osc_a_task_update_detune_negative;
    wire [6:0]  osc_a_task_update_velocity;
    wire        osc_a_task_update_enable;
    wire        osc_a_task_update_phase_reset;
    wire        osc_a_scheduler_busy;

    wire        osc_b_task_update_valid;
    wire [7:0]  osc_b_task_update_slot;
    wire [31:0] osc_b_task_update_phase_step;
    wire [31:0] osc_b_task_update_base_step;
    wire [31:0] osc_b_task_update_initial_phase;
    wire [34:0] osc_b_task_update_detune_unit;
    wire [2:0]  osc_b_task_update_detune_magnitude;
    wire osc_b_task_update_detune_negative;
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
    wire       shared_note_event_valid;
    wire       shared_note_event_on;
    wire [3:0] shared_note_event_channel;
    wire [6:0] shared_note_event_note;
    wire [6:0] shared_note_event_velocity;
    wire       keyboard_note_event_valid;
    wire       keyboard_note_event_on;
    wire [3:0] keyboard_note_event_channel;
    wire [6:0] keyboard_note_event_note;
    wire [6:0] keyboard_note_event_velocity;
    wire       midi_control_change_valid;
    wire [3:0] midi_control_change_channel;
    wire [6:0] midi_control_change_number;
    wire [6:0] midi_control_change_value;
    wire       highres_parameter_valid;
    wire [6:0] highres_parameter_id;
    wire [13:0] highres_parameter_value;
    wire       filter_cutoff_interpolation_busy;
    wire        lfo_route_overrun;
    wire       routed_note_event_valid;
    wire       routed_note_event_on;
    wire [6:0] routed_note_event_note;
    wire [6:0] routed_note_event_velocity;
    wire       pitch_note_event_valid;
    wire       pitch_note_event_on;
    wire [6:0] pitch_note_event_note;
    wire [6:0] pitch_note_event_velocity;
    wire       glide_override_enable;
    wire [31:0] glide_base_step;
    wire signed [12:0] vibrato_ratio_delta_q16;
    wire [23:0] debug_glide_current_pitch_q16;
    wire [23:0] debug_glide_target_pitch_q16;
    wire [6:0] pan_target;
    wire [2:0] filter_mode_target;
    reg  [2:0] filter_mode_active;
    wire [6:0] filter_cutoff_target;
    wire [14:0] filter_cutoff_current_q8;
    wire [6:0] filter_resonance_target;
    reg  [6:0] filter_resonance_current;
    wire [6:0] filter_mix_target;
    reg  [6:0] filter_mix_current;
    wire [6:0] master_level_target;
    wire [1:0] effect_mode_target;
    wire [6:0] delay_time_target;
    wire [6:0] delay_feedback_target;
    wire [6:0] delay_mix_target;
    wire [6:0] reverb_size_target;
    wire [6:0] reverb_decay_target;
    wire [6:0] reverb_mix_target;
    wire       distortion_enable_target;
    wire [1:0] distortion_type_target;
    wire [6:0] distortion_drive_target;
    wire [6:0] distortion_tone_target;
    wire [6:0] distortion_mix_target;
    wire       chorus_enable_target;
    wire [6:0] chorus_rate_target;
    wire [6:0] chorus_depth_target;
    wire [6:0] chorus_delay_target;
    wire [6:0] chorus_feedback_target;
    wire [6:0] chorus_mix_target;
    wire       phaser_enable_target;
    wire [6:0] phaser_rate_target;
    wire [6:0] phaser_depth_target;
    wire [6:0] phaser_center_target;
    wire [6:0] phaser_feedback_target;
    wire [6:0] phaser_mix_target;
    wire       compressor_enable_target;
    wire [6:0] compressor_threshold_target;
    wire [6:0] compressor_ratio_target;
    wire [6:0] compressor_attack_target;
    wire [6:0] compressor_release_target;
    wire [6:0] compressor_makeup_target;
    wire [6:0] compressor_mix_target;
    reg  [8:0] master_gain_q8;
    wire [8:0] master_gain_target_q8;
    wire       vibrato_enable;
    wire [6:0] vibrato_rate;
    wire [6:0] vibrato_depth;
    wire       portamento_enable;
    wire [6:0] portamento_time;

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
    wire [6:0]  osc_a_level;
    wire [3:0]  osc_a_wavetable_index;
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
    wire [6:0]  osc_b_level;
    wire [3:0]  osc_b_wavetable_index;
    wire [3:0]  osc_b_warp_mode;
    reg  [3:0]  osc_b_warp_mode_active;
    wire [6:0]  osc_b_warp_amount_target;
    reg  [6:0]  osc_b_warp_amount_current;

    wire [6:0] lfo_osc_a_wt_target;
    wire [6:0] lfo_osc_a_warp_target;
    wire [6:0] lfo_osc_a_level_target;
    wire [6:0] lfo_osc_b_wt_target;
    wire [6:0] lfo_osc_b_warp_target;
    wire [6:0] lfo_osc_b_level_target;
    wire [6:0] lfo_pan_target;
    wire [6:0] lfo_filter_resonance_target;
    wire [6:0] lfo_filter_mix_target;

    wire fir_input_ready;
    wire fir_output_valid;
    wire fir_input_overrun;
    wire global_filter_input_ready;
    wire global_filter_output_valid;
    wire global_filter_input_overrun;
    wire global_effects_input_ready;
    wire global_effects_output_valid;
    wire global_effects_input_overrun;

    wire cache_load_clk;
    wire cache_load_rst_n;
    wire cache_a_write_enable;
    wire cache_a_write_bank;
    wire cache_a_write_frame;
    wire [7:0] cache_a_write_address;
    wire [15:0] cache_a_write_data;
    wire cache_a_commit_toggle;
    wire cache_a_commit_bank;
    wire [7:0] cache_a_commit_fraction;
    wire cache_b_write_enable;
    wire cache_b_write_bank;
    wire cache_b_write_frame;
    wire [7:0] cache_b_write_address;
    wire [15:0] cache_b_write_data;
    wire cache_b_commit_toggle;
    wire cache_b_commit_bank;
    wire [7:0] cache_b_commit_fraction;
    wire ddr_init_done;
    wire wavetable_storage_ready;
    wire wavetable_storage_error;
    wire [4:0] wavetable_table_count;
    wire cache_a_ready;
    wire cache_b_ready;

    // 两个DAC并行输出同一个96 kHz单声道样本。板载NS4263低电平使能。
    assign PA_EN    = 1'b0;
    assign MAX_SD   = 1'b1;
    assign MAX_GAIN = 1'b1;
    // 第二组排针直接镜像同一组I2S信号，不增加采样、缓存或时钟域。
    assign VIS_BCLK = MAX_BCLK;
    assign VIS_LRC  = MAX_LRC;
    assign VIS_DIN  = MAX_DIN;

    sys_clock_manager u_sys_clock_manager (
        .clk_ref_50m(sys_clk),
        .rst_n_async(rst_n),
        .clk_sys    (clk_sys),
        .rst_n_sys  (rst_n_sys),
        .pll_locked (pll_locked)
    );

    generate
        if (EXTERNAL_WAVETABLE_ENABLE != 0) begin : GEN_WAVETABLE_STORAGE
            wavetable_storage_system u_wavetable_storage_system (
                .sys_clk(sys_clk), .rst_n(rst_n),
                .osc_a_table(osc_a_wavetable_index),
                .osc_a_position(osc_a_wt_position_current),
                .osc_b_table(osc_b_wavetable_index),
                .osc_b_position(osc_b_wt_position_current),
                .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0),
                .ddr_addr(ddr_addr), .ddr_bank(ddr_bank), .ddr_cs(ddr_cs),
                .ddr_ras(ddr_ras), .ddr_cas(ddr_cas), .ddr_we(ddr_we),
                .ddr_ck(ddr_ck), .ddr_ck_n(ddr_ck_n), .ddr_cke(ddr_cke),
                .ddr_odt(ddr_odt), .ddr_reset_n(ddr_reset_n), .ddr_dm(ddr_dm),
                .ddr_dq(ddr_dq), .ddr_dqs(ddr_dqs), .ddr_dqs_n(ddr_dqs_n),
                .cache_load_clk(cache_load_clk),
                .cache_load_rst_n(cache_load_rst_n),
                .cache_a_write_enable(cache_a_write_enable),
                .cache_a_write_bank(cache_a_write_bank),
                .cache_a_write_frame(cache_a_write_frame),
                .cache_a_write_address(cache_a_write_address),
                .cache_a_write_data(cache_a_write_data),
                .cache_a_commit_toggle(cache_a_commit_toggle),
                .cache_a_commit_bank(cache_a_commit_bank),
                .cache_a_commit_fraction(cache_a_commit_fraction),
                .cache_b_write_enable(cache_b_write_enable),
                .cache_b_write_bank(cache_b_write_bank),
                .cache_b_write_frame(cache_b_write_frame),
                .cache_b_write_address(cache_b_write_address),
                .cache_b_write_data(cache_b_write_data),
                .cache_b_commit_toggle(cache_b_commit_toggle),
                .cache_b_commit_bank(cache_b_commit_bank),
                .cache_b_commit_fraction(cache_b_commit_fraction),
                .ddr_init_done(ddr_init_done),
                .wavetable_storage_ready(wavetable_storage_ready),
                .wavetable_storage_error(wavetable_storage_error),
                .wavetable_table_count(wavetable_table_count),
                .cache_a_ready(cache_a_ready), .cache_b_ready(cache_b_ready)
            );
        end else begin : GEN_NO_WAVETABLE_STORAGE
            assign sd_clk = 1'b0;
            assign sd_cmd = 1'bz;
            assign ddr_addr = 15'd0; assign ddr_bank = 3'd0;
            assign ddr_cs = 1'b1; assign ddr_ras = 1'b1;
            assign ddr_cas = 1'b1; assign ddr_we = 1'b1;
            assign ddr_ck = 1'b0; assign ddr_ck_n = 1'b1;
            assign ddr_cke = 1'b0; assign ddr_odt = 1'b0;
            assign ddr_reset_n = 1'b0; assign ddr_dm = 4'hF;
            assign ddr_dq = 32'bz; assign ddr_dqs = 4'bz;
            assign ddr_dqs_n = 4'bz;
            assign cache_load_clk = clk_sys;
            assign cache_load_rst_n = rst_n_sys;
            assign cache_a_write_enable = 1'b0;
            assign cache_a_write_bank = 1'b0;
            assign cache_a_write_frame = 1'b0;
            assign cache_a_write_address = 8'd0;
            assign cache_a_write_data = 16'd0;
            assign cache_a_commit_toggle = 1'b0;
            assign cache_a_commit_bank = 1'b0;
            assign cache_a_commit_fraction = 8'd0;
            assign cache_b_write_enable = 1'b0;
            assign cache_b_write_bank = 1'b0;
            assign cache_b_write_frame = 1'b0;
            assign cache_b_write_address = 8'd0;
            assign cache_b_write_data = 16'd0;
            assign cache_b_commit_toggle = 1'b0;
            assign cache_b_commit_bank = 1'b0;
            assign cache_b_commit_fraction = 8'd0;
            assign ddr_init_done = 1'b0;
            assign wavetable_storage_ready = 1'b0;
            assign wavetable_storage_error = 1'b0;
            assign wavetable_table_count = 5'd0;
            assign cache_a_ready = 1'b0;
            assign cache_b_ready = 1'b0;
        end
    endgenerate

    assign oscillator_start_tick = oversample_tick;


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
            if (osc_a_wt_position_current < lfo_osc_a_wt_target)
                osc_a_wt_position_current <= osc_a_wt_position_current + 7'd1;
            else if (osc_a_wt_position_current > lfo_osc_a_wt_target)
                osc_a_wt_position_current <= osc_a_wt_position_current - 7'd1;

            if (osc_b_wt_position_current < lfo_osc_b_wt_target)
                osc_b_wt_position_current <= osc_b_wt_position_current + 7'd1;
            else if (osc_b_wt_position_current > lfo_osc_b_wt_target)
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
            end else if (osc_a_warp_amount_current < lfo_osc_a_warp_target) begin
                osc_a_warp_amount_current <= osc_a_warp_amount_current + 7'd1;
            end else if (osc_a_warp_amount_current > lfo_osc_a_warp_target) begin
                osc_a_warp_amount_current <= osc_a_warp_amount_current - 7'd1;
            end

            if (osc_b_warp_mode_active != osc_b_warp_mode) begin
                if (osc_b_warp_amount_current != 7'd0)
                    osc_b_warp_amount_current <= osc_b_warp_amount_current - 7'd1;
                else
                    osc_b_warp_mode_active <= osc_b_warp_mode;
            end else if (osc_b_warp_mode_active == 4'd0) begin
                osc_b_warp_amount_current <= 7'd0;
            end else if (osc_b_warp_amount_current < lfo_osc_b_warp_target) begin
                osc_b_warp_amount_current <= osc_b_warp_amount_current + 7'd1;
            end else if (osc_b_warp_amount_current > lfo_osc_b_warp_target) begin
                osc_b_warp_amount_current <= osc_b_warp_amount_current - 7'd1;
            end

            if (filter_resonance_current < lfo_filter_resonance_target)
                filter_resonance_current <= filter_resonance_current + 7'd1;
            else if (filter_resonance_current > lfo_filter_resonance_target)
                filter_resonance_current <= filter_resonance_current - 7'd1;

            // 模式切换时先退回全干声，再切换算法并恢复目标Mix，避免状态跳变。
            if (filter_mode_active != filter_mode_target) begin
                if (filter_mix_current != 7'd0)
                    filter_mix_current <= filter_mix_current - 7'd1;
                else
                    filter_mode_active <= filter_mode_target;
            end else if (filter_mix_current < lfo_filter_mix_target) begin
                filter_mix_current <= filter_mix_current + 7'd1;
            end else if (filter_mix_current > lfo_filter_mix_target) begin
                filter_mix_current <= filter_mix_current - 7'd1;
            end
        end
    end

    // 把0～127线性映射为Q1.8的0～0.5。最大值精确为128，
    // 其余点的误差不超过一个Q1.8最低位，不需要推断除法器。
    function [8:0] level_to_half_gain_q8;
        input [6:0] level;
        begin
            level_to_half_gain_q8 = {2'b00, level}
                                  + (level >= 7'd64 ? 9'd1 : 9'd0);
        end
    endfunction

    // 把0～127线性映射为Q1.8的0～1.0。32和96是对2/127余数
    // 进行四舍五入的分界点，最大值精确为256。
    function [8:0] level_to_unity_gain_q8;
        input [6:0] level;
        begin
            level_to_unity_gain_q8 = {1'b0, level, 1'b0}
                                   + (level >= 7'd32 ? 9'd1 : 9'd0)
                                   + (level >= 7'd96 ? 9'd1 : 9'd0);
        end
    endfunction

    // Bank已经按活动任务数做1/N归一化。这里为后级FIR和滤波器固定保留6 dB：
    // 只开启一路时最大增益0.5；两路都开启时每路最大增益0.25。
    // OSC Level与开关共用该平滑增益，目标总增益始终不超过0.5。
    assign osc_a_mix_gain_target_q8 = !osc_a_enabled ? 9'd0
        : osc_b_enabled ? (level_to_half_gain_q8(lfo_osc_a_level_target) >> 1)
        : level_to_half_gain_q8(lfo_osc_a_level_target);
    assign osc_b_mix_gain_target_q8 = !osc_b_enabled ? 9'd0
        : osc_a_enabled ? (level_to_half_gain_q8(lfo_osc_b_level_target) >> 1)
        : level_to_half_gain_q8(lfo_osc_b_level_target);
    assign master_gain_target_q8 = level_to_unity_gain_q8(lfo_master_level_target);

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            osc_a_mix_gain_q8 <= 9'd64;
            osc_b_mix_gain_q8 <= 9'd64;
            master_gain_q8    <= 9'd256;
        end else if (sample_tick) begin
            if (osc_a_mix_gain_q8 < osc_a_mix_gain_target_q8)
                osc_a_mix_gain_q8 <= osc_a_mix_gain_q8 + 9'd1;
            else if (osc_a_mix_gain_q8 > osc_a_mix_gain_target_q8)
                osc_a_mix_gain_q8 <= osc_a_mix_gain_q8 - 9'd1;

            if (osc_b_mix_gain_q8 < osc_b_mix_gain_target_q8)
                osc_b_mix_gain_q8 <= osc_b_mix_gain_q8 + 9'd1;
            else if (osc_b_mix_gain_q8 > osc_b_mix_gain_target_q8)
                osc_b_mix_gain_q8 <= osc_b_mix_gain_q8 - 9'd1;

            if (master_gain_q8 < master_gain_target_q8)
                master_gain_q8 <= master_gain_q8 + 9'd1;
            else if (master_gain_q8 > master_gain_target_q8)
                master_gain_q8 <= master_gain_q8 - 9'd1;
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

    wire  shared_cc_valid;
    wire [3:0] shared_cc_channel;
    wire [6:0] shared_cc_number;
    wire [6:0] shared_cc_value;
    wire  shared_hr_valid;
    wire [6:0] shared_hr_id;
    wire [13:0] shared_hr_value;
    wire  external_cc_valid;
    wire [3:0] external_cc_channel;
    wire [6:0] external_cc_number;
    wire [6:0] external_cc_value;
    wire  external_hr_valid;
    wire [6:0] external_hr_id;
    wire [13:0] external_hr_value;
    wire [7:0] control_uart_byte;
    wire control_uart_byte_valid, control_uart_framing_error;
    wire control_event_overflow;
    wire [7:0] keyboard_uart_byte;
    wire keyboard_uart_byte_valid, keyboard_uart_framing_error;
    wire [21:0] merged_note_event;
    wire merged_note_event_valid;
    wire midi_note_event_overflow;
    midi_note_parser u_midi_note_parser (
        .clk                   (clk_sys),
        .rst_n                 (rst_n_sys),
        .byte_data             (uart_byte),
        .byte_valid            (uart_byte_valid),
        .note_event_valid      (shared_note_event_valid),
        .note_event_on         (shared_note_event_on),
        .note_event_channel    (shared_note_event_channel),
        .note_event_note       (shared_note_event_note),
        .note_event_velocity   (shared_note_event_velocity),
        .control_change_valid  (shared_cc_valid),
        .control_change_channel(shared_cc_channel),
        .control_change_number (shared_cc_number),
        .control_change_value  (shared_cc_value)
    );

    highres_parameter_parser u_highres_parameter_parser (
        .clk            (clk_sys),
        .rst_n          (rst_n_sys),
        .byte_data      (uart_byte),
        .byte_valid     (uart_byte_valid),
        .parameter_valid(shared_hr_valid),
        .parameter_id   (shared_hr_id),
        .parameter_value(shared_hr_value)
    );

    // 实体键盘使用独立UART与MIDI状态机，避免两路Running Status互相污染。
    // 第一版只合并Note On/Off、通道、音高和力度；键盘CC不进入音色控制链。
    uart_rx #(
        .CLK_HZ   (50000000),
        .BAUD_RATE(KEYBOARD_UART_BAUD_RATE)
    ) u_keyboard_uart_rx (
        .clk          (clk_sys),
        .rst_n        (rst_n_sys),
        .rx           (keyboard_uart_rx),
        .data         (keyboard_uart_byte),
        .data_valid   (keyboard_uart_byte_valid),
        .framing_error(keyboard_uart_framing_error)
    );

    midi_note_parser u_keyboard_midi_note_parser (
        .clk                   (clk_sys),
        .rst_n                 (rst_n_sys),
        .byte_data             (keyboard_uart_byte),
        .byte_valid            (keyboard_uart_byte_valid),
        .note_event_valid      (keyboard_note_event_valid),
        .note_event_on         (keyboard_note_event_on),
        .note_event_channel    (keyboard_note_event_channel),
        .note_event_note       (keyboard_note_event_note),
        .note_event_velocity   (keyboard_note_event_velocity),
        .control_change_valid  (),
        .control_change_channel(),
        .control_change_number (),
        .control_change_value  ()
    );

    // 复用现有8项双入口事件FIFO。先保留板载USB-UART事件，再保留实体键盘事件。
    control_event_merge u_midi_note_event_merge (
        .clk      (clk_sys),
        .rst_n    (rst_n_sys),
        .valid_a  (shared_note_event_valid),
        .data_a   ({3'd0, shared_note_event_on,
                    shared_note_event_channel, shared_note_event_note,
                    shared_note_event_velocity}),
        .valid_b  (keyboard_note_event_valid),
        .data_b   ({3'd0, keyboard_note_event_on,
                    keyboard_note_event_channel, keyboard_note_event_note,
                    keyboard_note_event_velocity}),
        .out_valid(merged_note_event_valid),
        .out_data (merged_note_event),
        .overflow (midi_note_event_overflow)
    );

    assign midi_note_event_valid = merged_note_event_valid;
    assign midi_note_event_on = merged_note_event[18];
    assign midi_note_event_channel = merged_note_event[17:14];
    assign midi_note_event_note = merged_note_event[13:7];
    assign midi_note_event_velocity = merged_note_event[6:0];

    uart_rx #(.CLK_HZ(50000000), .BAUD_RATE(CONTROL_UART_BAUD_RATE)) u_control_uart_rx (
        .clk(clk_sys), .rst_n(rst_n_sys), .rx(control_uart_rx),
        .data(control_uart_byte), .data_valid(control_uart_byte_valid),
        .framing_error(control_uart_framing_error)
    );
    midi_note_parser u_control_cc_parser (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .byte_data(control_uart_byte), .byte_valid(control_uart_byte_valid),
        .note_event_valid(), .note_event_on(), .note_event_channel(),
        .note_event_note(), .note_event_velocity(),
        .control_change_valid(external_cc_valid), .control_change_channel(external_cc_channel),
        .control_change_number(external_cc_number), .control_change_value(external_cc_value)
    );
    highres_parameter_parser u_control_highres_parser (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .byte_data(control_uart_byte), .byte_valid(control_uart_byte_valid),
        .parameter_valid(external_hr_valid), .parameter_id(external_hr_id),
        .parameter_value(external_hr_value)
    );
    wire [21:0] merged_control_event;
    wire merged_control_valid;
    control_event_merge u_control_event_merge (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .valid_a(shared_cc_valid || shared_hr_valid),
        .data_a(shared_hr_valid ? {1'b1,shared_hr_id,shared_hr_value}
               : {4'd0,shared_cc_channel,shared_cc_number,shared_cc_value}),
        .valid_b(external_cc_valid || external_hr_valid),
        .data_b(external_hr_valid ? {1'b1,external_hr_id,external_hr_value}
               : {4'd0,external_cc_channel,external_cc_number,external_cc_value}),
        .out_valid(merged_control_valid), .out_data(merged_control_event),
        .overflow(control_event_overflow)
    );
    assign midi_control_change_valid = merged_control_valid && !merged_control_event[21];
    assign midi_control_change_channel = merged_control_event[17:14];
    assign midi_control_change_number = merged_control_event[13:7];
    assign midi_control_change_value = merged_control_event[6:0];
    assign highres_parameter_valid = merged_control_valid && merged_control_event[21];
    assign highres_parameter_id = merged_control_event[20:14];
    assign highres_parameter_value = merged_control_event[13:0];

    // V2：每个UI目标一个固定槽；无音频对应的槽只保存绑定，不连到其他参数。
    wire [370:0] lfo_v2_base, lfo_v2_mod;
    wire lfo_v2_output_valid, lfo_v2_config_busy, lfo_v2_config_error, lfo_v2_config_applied;
    wire [26:0] lfo_v2_phase_indices;
    wire [20:0] lfo_v2_waves;
    wire [6:0] osc_a_phase_target, osc_a_rand_target, osc_b_phase_target, osc_b_rand_target;
    assign lfo_v2_base[0+:7]=7'd0; // 目标0：预留
    assign lfo_v2_base[7+:7]=7'd0; // 目标1：预留
    assign lfo_v2_base[14+:7]=7'd0; // 目标2：预留
    assign lfo_v2_base[21+:7]=7'd0; // 目标3：预留
    wire [6:0] lfo_master_level_target;
    assign lfo_v2_base[28+:7]=master_level_target;
    assign lfo_master_level_target=lfo_v2_mod[28+:7];
    assign lfo_v2_base[35+:7]=7'd0; // 目标5：预留
    wire [6:0] lfo_osc_a_detune_target;
    assign lfo_v2_base[42+:7]=osc_a_detune_amount;
    assign lfo_osc_a_detune_target=lfo_v2_mod[42+:7];
    assign lfo_v2_base[49+:7]=7'd0; // 目标7：预留
    wire [6:0] lfo_osc_a_phase_target;
    assign lfo_v2_base[56+:7]=osc_a_phase_target;
    assign lfo_osc_a_phase_target=lfo_v2_mod[56+:7];
    wire [6:0] lfo_osc_a_rand_target;
    assign lfo_v2_base[63+:7]=osc_a_rand_target;
    assign lfo_osc_a_rand_target=lfo_v2_mod[63+:7];
    assign lfo_v2_base[70+:7]=osc_a_wt_position_target;
    assign lfo_osc_a_wt_target=lfo_v2_mod[70+:7];
    assign lfo_v2_base[77+:7]=osc_a_warp_amount_target;
    assign lfo_osc_a_warp_target=lfo_v2_mod[77+:7];
    assign lfo_v2_base[84+:7]=7'd0; // 目标12：预留
    assign lfo_v2_base[91+:7]=osc_a_level;
    assign lfo_osc_a_level_target=lfo_v2_mod[91+:7];
    assign lfo_v2_base[98+:7]=7'd0; // 目标14：预留
    wire [6:0] lfo_osc_b_detune_target;
    assign lfo_v2_base[105+:7]=osc_b_detune_amount;
    assign lfo_osc_b_detune_target=lfo_v2_mod[105+:7];
    assign lfo_v2_base[112+:7]=7'd0; // 目标16：预留
    wire [6:0] lfo_osc_b_phase_target;
    assign lfo_v2_base[119+:7]=osc_b_phase_target;
    assign lfo_osc_b_phase_target=lfo_v2_mod[119+:7];
    wire [6:0] lfo_osc_b_rand_target;
    assign lfo_v2_base[126+:7]=osc_b_rand_target;
    assign lfo_osc_b_rand_target=lfo_v2_mod[126+:7];
    assign lfo_v2_base[133+:7]=osc_b_wt_position_target;
    assign lfo_osc_b_wt_target=lfo_v2_mod[133+:7];
    assign lfo_v2_base[140+:7]=osc_b_warp_amount_target;
    assign lfo_osc_b_warp_target=lfo_v2_mod[140+:7];
    assign lfo_v2_base[147+:7]=7'd0; // 目标21：预留
    assign lfo_v2_base[154+:7]=osc_b_level;
    assign lfo_osc_b_level_target=lfo_v2_mod[154+:7];
    wire [6:0] lfo_filter_cutoff_target;
    assign lfo_v2_base[161+:7]=filter_cutoff_target;
    assign lfo_filter_cutoff_target=lfo_v2_mod[161+:7];
    assign lfo_v2_base[168+:7]=filter_resonance_target;
    assign lfo_filter_resonance_target=lfo_v2_mod[168+:7];
    assign lfo_v2_base[175+:7]=7'd0; // 目标25：预留
    assign lfo_v2_base[182+:7]=7'd0; // 目标26：预留
    assign lfo_v2_base[189+:7]=7'd0; // 目标27：预留
    assign lfo_v2_base[196+:7]=filter_mix_target;
    assign lfo_filter_mix_target=lfo_v2_mod[196+:7];
    assign lfo_v2_base[203+:7]=7'd0; // 目标29：预留
    assign lfo_v2_base[210+:7]=7'd0; // 目标30：预留
    assign lfo_v2_base[217+:7]=7'd0; // 目标31：预留
    assign lfo_v2_base[224+:7]=7'd0; // 目标32：预留
    assign lfo_v2_base[231+:7]=7'd0; // 目标33：预留
    wire [6:0] lfo_delay_feedback_target;
    assign lfo_v2_base[238+:7]=delay_feedback_target;
    assign lfo_delay_feedback_target=lfo_v2_mod[238+:7];
    wire [6:0] lfo_delay_time_target;
    assign lfo_v2_base[245+:7]=delay_time_target;
    assign lfo_delay_time_target=lfo_v2_mod[245+:7];
    assign lfo_v2_base[252+:7]=7'd0; // 目标36：预留
    assign lfo_v2_base[259+:7]=7'd0; // 目标37：预留
    assign lfo_v2_base[266+:7]=7'd0; // 目标38：预留
    wire [6:0] lfo_delay_mix_target;
    assign lfo_v2_base[273+:7]=delay_mix_target;
    assign lfo_delay_mix_target=lfo_v2_mod[273+:7];
    wire [6:0] lfo_reverb_size_target;
    assign lfo_v2_base[280+:7]=reverb_size_target;
    assign lfo_reverb_size_target=lfo_v2_mod[280+:7];
    wire [6:0] lfo_reverb_decay_target;
    assign lfo_v2_base[287+:7]=reverb_decay_target;
    assign lfo_reverb_decay_target=lfo_v2_mod[287+:7];
    assign lfo_v2_base[294+:7]=7'd0; // 目标42：预留
    assign lfo_v2_base[301+:7]=7'd0; // 目标43：预留
    assign lfo_v2_base[308+:7]=7'd0; // 目标44：预留
    assign lfo_v2_base[315+:7]=7'd0; // 目标45：预留
    wire [6:0] lfo_reverb_mix_target;
    assign lfo_v2_base[322+:7]=reverb_mix_target;
    assign lfo_reverb_mix_target=lfo_v2_mod[322+:7];
    assign lfo_v2_base[329+:7]=7'd0; // 目标47：预留
    assign lfo_v2_base[336+:7]=7'd0; // 目标48：预留
    assign lfo_v2_base[343+:7]=7'd0; // 目标49：预留
    assign lfo_v2_base[350+:7]=7'd0; // 目标50：预留
    assign lfo_v2_base[357+:7]=7'd0; // 目标51：预留
    assign lfo_v2_base[364+:7]=7'd0; // 目标52：预留
    wire [6:0] lfo_distortion_drive_target=distortion_drive_target;
    wire [6:0] lfo_distortion_mix_target=distortion_mix_target;
    wire [6:0] lfo_chorus_depth_target=chorus_depth_target;
    wire [6:0] lfo_chorus_mix_target=chorus_mix_target;
    wire [6:0] lfo_phaser_depth_target=phaser_depth_target;
    wire [6:0] lfo_phaser_mix_target=phaser_mix_target;
    assign lfo_pan_target=pan_target;
    lfo_v2_engine u_lfo_v2_engine (
        .clk(clk_sys), .rst_n(rst_n_sys), .sample_tick(sample_tick),
        .parameter_valid(highres_parameter_valid), .parameter_id(highres_parameter_id),
        .parameter_value(highres_parameter_value), .base_values(lfo_v2_base),
        .mod_values(lfo_v2_mod), .output_valid(lfo_v2_output_valid),
        .route_overrun(lfo_route_overrun), .config_busy(lfo_v2_config_busy),
        .config_error(lfo_v2_config_error), .config_applied(lfo_v2_config_applied),
        .phase_indices(lfo_v2_phase_indices), .wave_values(lfo_v2_waves)
    );
    // 调制发生在原始CC域，随后统一进入原有5.33 ms线性平滑器。
    // 只有目标改变时重装插值，避免恒定目标每样本重启平滑。
    reg [6:0] lfo_cutoff_previous;
    wire lfo_cutoff_changed=lfo_v2_output_valid && lfo_filter_cutoff_target!=lfo_cutoff_previous;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) lfo_cutoff_previous<=7'd127;
        else if (lfo_cutoff_changed) lfo_cutoff_previous<=lfo_filter_cutoff_target;
    end
    parameter_linear_interpolator #(
        .VALUE_WIDTH(15), .INTERPOLATION_SHIFT(9), .RESET_VALUE({7'd127,8'd0})
    ) u_filter_cutoff_interpolator (
        .clk(clk_sys), .rst_n(rst_n_sys), .sample_tick(sample_tick),
        .target_valid(lfo_cutoff_changed), .target_value({lfo_filter_cutoff_target,8'd0}),
        .current_value(filter_cutoff_current_q8), .busy(filter_cutoff_interpolation_busy)
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
        .master_level              (master_level_target),
        .effect_mode               (effect_mode_target),
        .delay_time                (delay_time_target),
        .delay_feedback            (delay_feedback_target),
        .delay_mix                 (delay_mix_target),
        .reverb_size               (reverb_size_target),
        .reverb_decay              (reverb_decay_target),
        .reverb_mix                (reverb_mix_target),
        .distortion_enable         (distortion_enable_target),
        .distortion_type           (distortion_type_target),
        .distortion_drive          (distortion_drive_target),
        .distortion_tone           (distortion_tone_target),
        .distortion_mix            (distortion_mix_target),
        .chorus_enable             (chorus_enable_target),
        .chorus_rate               (chorus_rate_target),
        .chorus_depth              (chorus_depth_target),
        .chorus_delay              (chorus_delay_target),
        .chorus_feedback           (chorus_feedback_target),
        .chorus_mix                (chorus_mix_target),
        .phaser_enable             (phaser_enable_target),
        .phaser_rate               (phaser_rate_target),
        .phaser_depth              (phaser_depth_target),
        .phaser_center             (phaser_center_target),
        .phaser_feedback           (phaser_feedback_target),
        .phaser_mix                (phaser_mix_target),
        .compressor_enable         (compressor_enable_target),
        .compressor_threshold      (compressor_threshold_target),
        .compressor_ratio          (compressor_ratio_target),
        .compressor_attack         (compressor_attack_target),
        .compressor_release        (compressor_release_target),
        .compressor_makeup         (compressor_makeup_target),
        .compressor_mix            (compressor_mix_target),
        .vibrato_enable            (vibrato_enable),
        .vibrato_rate              (vibrato_rate),
        .vibrato_depth             (vibrato_depth),
        .portamento_enable         (portamento_enable),
        .portamento_time           (portamento_time),
        .osc_a_wt_position_target  (osc_a_wt_position_target),
        .osc_a_waveform_select     (osc_a_waveform_select),
        .osc_a_phase(osc_a_phase_target), .osc_a_rand(osc_a_rand_target),
        .osc_a_detune_amount       (osc_a_detune_amount),
        .osc_a_unison_count        (osc_a_unison_count),
        .osc_a_attack_control      (osc_a_attack_control),
        .osc_a_decay_control       (osc_a_decay_control),
        .osc_a_sustain_control     (osc_a_sustain_control_target),
        .osc_a_release_control     (osc_a_release_control),
        .osc_a_enabled             (osc_a_enabled),
        .osc_a_warp_mode           (osc_a_warp_mode),
        .osc_a_warp_amount         (osc_a_warp_amount_target),
        .osc_a_level               (osc_a_level),
        .osc_a_wavetable_index     (osc_a_wavetable_index),
        .osc_b_wt_position_target  (osc_b_wt_position_target),
        .osc_b_waveform_select     (osc_b_waveform_select),
        .osc_b_phase(osc_b_phase_target), .osc_b_rand(osc_b_rand_target),
        .osc_b_detune_amount       (osc_b_detune_amount),
        .osc_b_unison_count        (osc_b_unison_count),
        .osc_b_attack_control      (osc_b_attack_control),
        .osc_b_decay_control       (osc_b_decay_control),
        .osc_b_sustain_control     (osc_b_sustain_control_target),
        .osc_b_release_control     (osc_b_release_control),
        .osc_b_enabled             (osc_b_enabled),
        .osc_b_warp_mode           (osc_b_warp_mode),
        .osc_b_warp_amount         (osc_b_warp_amount_target),
        .osc_b_level               (osc_b_level),
        .osc_b_wavetable_index     (osc_b_wavetable_index)
    );

    // 共享演奏音高层：Portamento开启时把Note流转换为最后音符优先的
    // 单音Legato；同一条滑音基础步进同时供给OSC A和OSC B。
    performance_pitch_controller u_performance_pitch_controller (
        .clk                       (clk_sys),
        .rst_n                     (rst_n_sys),
        .sample_tick               (sample_tick),
        .note_event_valid          (routed_note_event_valid),
        .note_event_on             (routed_note_event_on),
        .note_event_note           (routed_note_event_note),
        .note_event_velocity       (routed_note_event_velocity),
        .vibrato_enable            (vibrato_enable),
        .vibrato_rate              (vibrato_rate),
        .vibrato_depth             (vibrato_depth),
        .portamento_enable         (portamento_enable),
        .portamento_time           (portamento_time),
        .routed_note_event_valid   (pitch_note_event_valid),
        .routed_note_event_on      (pitch_note_event_on),
        .routed_note_event_note    (pitch_note_event_note),
        .routed_note_event_velocity(pitch_note_event_velocity),
        .glide_override_enable     (glide_override_enable),
        .glide_base_step           (glide_base_step),
        .vibrato_ratio_delta_q16   (vibrato_ratio_delta_q16),
        .debug_current_pitch_q16   (debug_glide_current_pitch_q16),
        .debug_target_pitch_q16    (debug_glide_target_pitch_q16)
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
        .INITIAL_PHASE_ENABLE(1),
        .ENGINE_COUNT    (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_osc_a_task_scheduler (
        .clk                     (clk_sys),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (pitch_note_event_valid),
        .note_event_on           (pitch_note_event_on),
        .note_event_note         (pitch_note_event_note),
        .note_event_velocity     (pitch_note_event_velocity),
        .unison_count            (osc_a_unison_count),
        .detune_amount           (lfo_osc_a_detune_target),
        .phase_control(lfo_osc_a_phase_target), .rand_control(lfo_osc_a_rand_target),
        .task_idle_mask          (osc_a_task_idle_mask),
        .task_update_valid       (osc_a_task_update_valid),
        .task_update_slot        (osc_a_task_update_slot),
        .task_update_phase_step  (osc_a_task_update_phase_step),
        .task_update_base_step(osc_a_task_update_base_step),
        .task_update_detune_unit(osc_a_task_update_detune_unit),
        .task_update_detune_magnitude(
            osc_a_task_update_detune_magnitude),
        .task_update_detune_negative(osc_a_task_update_detune_negative),
        .task_update_velocity    (osc_a_task_update_velocity),
        .task_update_enable      (osc_a_task_update_enable),
        .task_update_phase_reset (osc_a_task_update_phase_reset),
        .task_update_initial_phase(osc_a_task_update_initial_phase),
        .active_task_count       (osc_a_active_task_count),
        .scheduler_busy          (osc_a_scheduler_busy)
    );

    oscillator_task_scheduler #(
        .INITIAL_PHASE_ENABLE(1), .RANDOM_SEED(32'hA511E9B3),
        .ENGINE_COUNT    (OSC_ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_osc_b_task_scheduler (
        .clk                     (clk_sys),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (pitch_note_event_valid),
        .note_event_on           (pitch_note_event_on),
        .note_event_note         (pitch_note_event_note),
        .note_event_velocity     (pitch_note_event_velocity),
        .unison_count            (osc_b_unison_count),
        .detune_amount           (lfo_osc_b_detune_target),
        .phase_control(lfo_osc_b_phase_target), .rand_control(lfo_osc_b_rand_target),
        .task_idle_mask          (osc_b_task_idle_mask),
        .task_update_valid       (osc_b_task_update_valid),
        .task_update_slot        (osc_b_task_update_slot),
        .task_update_phase_step  (osc_b_task_update_phase_step),
        .task_update_base_step(osc_b_task_update_base_step),
        .task_update_detune_unit(osc_b_task_update_detune_unit),
        .task_update_detune_magnitude(
            osc_b_task_update_detune_magnitude),
        .task_update_detune_negative(osc_b_task_update_detune_negative),
        .task_update_velocity    (osc_b_task_update_velocity),
        .task_update_enable      (osc_b_task_update_enable),
        .task_update_phase_reset (osc_b_task_update_phase_reset),
        .task_update_initial_phase(osc_b_task_update_initial_phase),
        .active_task_count       (osc_b_active_task_count),
        .scheduler_busy          (osc_b_scheduler_busy)
    );

    oscillator_tdm_bank #(
        .INITIAL_PHASE_ENABLE(1),
        .REALTIME_DETUNE_ENABLE(1),
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
        .external_wavetable_enable (EXTERNAL_WAVETABLE_ENABLE != 0),
        .cache_load_clk            (cache_load_clk),
        .cache_load_rst_n          (cache_load_rst_n),
        .cache_write_enable        (cache_a_write_enable),
        .cache_write_bank          (cache_a_write_bank),
        .cache_write_frame         (cache_a_write_frame),
        .cache_write_address       (cache_a_write_address),
        .cache_write_data          (cache_a_write_data),
        .cache_commit_toggle       (cache_a_commit_toggle),
        .cache_commit_bank         (cache_a_commit_bank),
        .cache_commit_fraction     (cache_a_commit_fraction),
        .task_update_valid         (osc_a_task_update_valid),
        .task_update_slot          (osc_a_task_update_slot),
        .task_update_phase_step    (osc_a_task_update_phase_step),
        .detune_amount(lfo_osc_a_detune_target),
        .task_update_base_step(osc_a_task_update_base_step),
        .task_update_detune_unit(osc_a_task_update_detune_unit),
        .task_update_detune_magnitude(
            osc_a_task_update_detune_magnitude),
        .task_update_detune_negative(osc_a_task_update_detune_negative),
        .glide_override_enable(glide_override_enable),
        .glide_override_base_step(glide_base_step),
        .vibrato_ratio_delta_q16(vibrato_ratio_delta_q16),
        .task_update_velocity      (osc_a_task_update_velocity),
        .task_update_enable        (osc_a_task_update_enable),
        .task_update_phase_reset   (osc_a_task_update_phase_reset),
        .task_update_initial_phase(osc_a_task_update_initial_phase),
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
        .INITIAL_PHASE_ENABLE(1),
        .REALTIME_DETUNE_ENABLE(1),
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
        .external_wavetable_enable (EXTERNAL_WAVETABLE_ENABLE != 0),
        .cache_load_clk            (cache_load_clk),
        .cache_load_rst_n          (cache_load_rst_n),
        .cache_write_enable        (cache_b_write_enable),
        .cache_write_bank          (cache_b_write_bank),
        .cache_write_frame         (cache_b_write_frame),
        .cache_write_address       (cache_b_write_address),
        .cache_write_data          (cache_b_write_data),
        .cache_commit_toggle       (cache_b_commit_toggle),
        .cache_commit_bank         (cache_b_commit_bank),
        .cache_commit_fraction     (cache_b_commit_fraction),
        .task_update_valid         (osc_b_task_update_valid),
        .task_update_slot          (osc_b_task_update_slot),
        .task_update_phase_step    (osc_b_task_update_phase_step),
        .detune_amount(lfo_osc_b_detune_target),
        .task_update_base_step(osc_b_task_update_base_step),
        .task_update_detune_unit(osc_b_task_update_detune_unit),
        .task_update_detune_magnitude(
            osc_b_task_update_detune_magnitude),
        .task_update_detune_negative(osc_b_task_update_detune_negative),
        .glide_override_enable(glide_override_enable),
        .glide_override_base_step(glide_base_step),
        .vibrato_ratio_delta_q16(vibrato_ratio_delta_q16),
        .task_update_velocity      (osc_b_task_update_velocity),
        .task_update_enable        (osc_b_task_update_enable),
        .task_update_phase_reset   (osc_b_task_update_phase_reset),
        .task_update_initial_phase(osc_b_task_update_initial_phase),
        .active_task_count         (osc_b_active_task_count),
        .sample_out                (osc_b_mix),
        .sample_valid              (osc_b_mix_valid),
        .schedule_overrun          (osc_b_schedule_overrun),
        .task_idle_mask            (osc_b_task_idle_mask),
        .debug_engine0_busy        (debug_osc_b_busy),
        .debug_engine0_slot        (debug_osc_b_slot),
        .debug_engine0_slot_commit (debug_osc_b_slot_commit)
    );

    // 每组Bank已经按自己的活动任务数归一化。这里应用开关和Level共用的
    // 平滑增益，两路目标增益之和始终不超过0.5，给FIR与滤波器保留6 dB。
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
    assign oscillator_mix_shifted = oscillator_scaled_sum >>> 8;
    assign oscillator_mix_clip_now = (oscillator_mix_shifted > 32767)
                                   || (oscillator_mix_shifted < -32768);

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

    global_effects u_global_effects (
        .clk             (clk_sys),
        .rst_n           (rst_n_sys),
        .in_valid        (global_filter_output_valid),
        .sample_in       (global_filtered_sample),
        .in_ready        (global_effects_input_ready),
        .distortion_enable(distortion_enable_target),
        .distortion_type  (distortion_type_target),
        .distortion_drive (lfo_distortion_drive_target),
        .distortion_tone  (distortion_tone_target),
        .distortion_mix   (lfo_distortion_mix_target),
        .phaser_enable    (phaser_enable_target),
        .phaser_rate      (phaser_rate_target),
        .phaser_depth     (lfo_phaser_depth_target),
        .phaser_center    (phaser_center_target),
        .phaser_feedback  (phaser_feedback_target),
        .phaser_mix       (lfo_phaser_mix_target),
        .chorus_enable    (chorus_enable_target),
        .chorus_rate      (chorus_rate_target),
        .chorus_depth     (lfo_chorus_depth_target),
        .chorus_delay     (chorus_delay_target),
        .chorus_feedback  (chorus_feedback_target),
        .chorus_mix       (lfo_chorus_mix_target),
        .effect_mode     (effect_mode_target),
        .delay_time      (lfo_delay_time_target),
        .delay_feedback  (lfo_delay_feedback_target),
        .delay_mix       (lfo_delay_mix_target),
        .reverb_size     (lfo_reverb_size_target),
        .reverb_decay    (lfo_reverb_decay_target),
        .reverb_mix      (lfo_reverb_mix_target),
        .compressor_enable   (compressor_enable_target),
        .compressor_threshold(compressor_threshold_target),
        .compressor_ratio    (compressor_ratio_target),
        .compressor_attack   (compressor_attack_target),
        .compressor_release  (compressor_release_target),
        .compressor_makeup   (compressor_makeup_target),
        .compressor_mix      (compressor_mix_target),
        .out_valid       (global_effects_output_valid),
        .sample_out      (effect_processed_sample),
        .input_overrun   (global_effects_input_overrun)
    );

    // Master Level位于全局滤波器和效果器之后。Q1.8乘法结果先保持宽位，再在一个
    // 50 MHz周期内完成饱和和寄存；该延迟远小于一个96 kHz采样周期。
    assign master_scaled_product =
        $signed(effect_processed_sample) * $signed({1'b0, master_gain_q8});
    assign master_scaled_product_extended = {master_scaled_product[25],
                                              master_scaled_product};
    assign master_scaled_shifted = master_scaled_product_extended >>> 8;
    assign master_output_clip_now = (master_scaled_shifted > 32767)
                                  || (master_scaled_shifted < -32768);
    // 现有滤波器接口已经在内部压回16位。端点命中可用于发现可能的
    // 滤波器饱和；后续若需要精确峰值限制器，再单独扩宽滤波器接口。
    assign filter_output_limit_now = (global_filtered_sample == 16'sh7FFF)
                                   || (global_filtered_sample == 16'sh8000);

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            master_output_sample <= 16'sd0;
            oscillator_mix_clip  <= 1'b0;
            filter_output_limit  <= 1'b0;
            master_output_clip   <= 1'b0;
            audio_clip_count     <= 32'd0;
        end else begin
            if (global_effects_output_valid) begin
                master_output_sample
                    <= saturate_mix_q8(master_scaled_product_extended);
                if (filter_output_limit_now)
                    filter_output_limit <= 1'b1;
                if (master_output_clip_now)
                    master_output_clip <= 1'b1;
            end

            if (oscillator_mix_valid && oscillator_mix_clip_now)
                oscillator_mix_clip <= 1'b1;

            if ((oscillator_mix_valid && oscillator_mix_clip_now)
                || (global_effects_output_valid
                    && (filter_output_limit_now || master_output_clip_now)))
                audio_clip_count <= audio_clip_count + 32'd1;
        end
    end

    i2s_tx u_max98357a_i2s_tx (
        .sys_clk        (clk_sys),
        .rst_n          (rst_n_sys),
        .sample_data    (master_output_sample),
        .bclk           (MAX_BCLK),
        .lrck           (MAX_LRC),
        .sdata          (MAX_DIN),
        .sample_tick    (sample_tick),
        .oversample_tick(oversample_tick)
    );

    // PT8211使用日本格式（LSBJ），不能直接复制标准I2S的数据和字选择信号。
    // 两个发送器使用相同的系统时钟、复位和BCK相位增量，帧边界保持一致；
    // 音频调度仍只由上面的MAX98357A发送器产生sample_tick。
    pt8211_tx u_onboard_pt8211_tx (
        .sys_clk        (clk_sys),
        .rst_n          (rst_n_sys),
        .sample_data    (master_output_sample),
        .bck            (HP_BCK),
        .ws             (HP_WS),
        .din            (HP_DIN),
        .sample_tick    (),
        .oversample_tick()
    );

endmodule
