`timescale 1ns/1ps

module tb_top_midi_input;

    localparam integer TEST_UART_BAUD = 2500000;
    localparam integer CLKS_PER_BIT   = 50000000 / TEST_UART_BAUD;

    reg sys_clk;
    reg rst_n;
    reg uart_rx;
    reg control_uart_rx;
    reg keyboard_uart_rx;

    wire MAX_SD;
    wire MAX_GAIN;
    wire HP_BCK;
    wire HP_WS;
    wire HP_DIN;
    wire MAX_DIN;
    wire MAX_BCLK;
    wire MAX_LRC;
    wire VIS_BCLK;
    wire VIS_LRC;
    wire VIS_DIN;
    wire PA_EN;
    wire sd_clk;
    tri  sd_cmd;
    reg  sd_dat0;
    wire [14:0] ddr_addr;
    wire [2:0] ddr_bank;
    wire ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_ck, ddr_ck_n;
    wire ddr_cke, ddr_odt, ddr_reset_n;
    wire [3:0] ddr_dm;
    tri [31:0] ddr_dq;
    tri [3:0] ddr_dqs, ddr_dqs_n;

    integer errors;
    integer osc_a_update_count;
    integer osc_b_update_count;
    integer release_wait_cycles;
    integer silence_check_count;
    integer consecutive_silent_samples;
    integer wt_a_before;
    integer wt_b_before;
    integer warp_a_before;
    integer warp_b_before;
    integer valid_mismatch_count;
    integer switch_wait_samples;
    integer clip_count_before;
    integer c19_a_update_before;
    integer c19_b_update_before;

    reg [7:0]  osc_a_slot_log [0:15];
    reg [31:0] osc_a_step_log [0:15];
    reg        osc_a_enable_log [0:15];
    reg [7:0]  osc_b_slot_log [0:15];
    reg [31:0] osc_b_step_log [0:15];
    reg        osc_b_enable_log [0:15];

    top #(
        .UART_BAUD_RATE(TEST_UART_BAUD),
        .CONTROL_UART_BAUD_RATE(TEST_UART_BAUD),
        .KEYBOARD_UART_BAUD_RATE(TEST_UART_BAUD),
        .DEFAULT_UNISON_COUNT(1),
        // 本测试专注 MIDI 路由顺序；容量由独立的 2×32 测试覆盖。
        .OSC_ENGINE_COUNT(1),
        .SLOTS_PER_ENGINE(32),
        .EXTERNAL_WAVETABLE_ENABLE(0)
    ) dut (
        .sys_clk (sys_clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .control_uart_rx(control_uart_rx),
        .keyboard_uart_rx(keyboard_uart_rx),
        .MAX_SD  (MAX_SD),
        .MAX_GAIN(MAX_GAIN),
        .HP_BCK  (HP_BCK),
        .HP_WS   (HP_WS),
        .HP_DIN  (HP_DIN),
        .MAX_DIN (MAX_DIN),
        .MAX_BCLK(MAX_BCLK),
        .MAX_LRC (MAX_LRC),
        .VIS_BCLK(VIS_BCLK),
        .VIS_LRC (VIS_LRC),
        .VIS_DIN (VIS_DIN),
        .PA_EN   (PA_EN),
        .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0),
        .ddr_addr(ddr_addr), .ddr_bank(ddr_bank), .ddr_cs(ddr_cs),
        .ddr_ras(ddr_ras), .ddr_cas(ddr_cas), .ddr_we(ddr_we),
        .ddr_ck(ddr_ck), .ddr_ck_n(ddr_ck_n), .ddr_cke(ddr_cke),
        .ddr_odt(ddr_odt), .ddr_reset_n(ddr_reset_n), .ddr_dm(ddr_dm),
        .ddr_dq(ddr_dq), .ddr_dqs(ddr_dqs), .ddr_dqs_n(ddr_dqs_n)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.osc_a_task_update_valid) begin
            osc_a_slot_log[osc_a_update_count]
                = dut.osc_a_task_update_slot;
            osc_a_step_log[osc_a_update_count]
                = dut.osc_a_task_update_phase_step;
            osc_a_enable_log[osc_a_update_count]
                = dut.osc_a_task_update_enable;
            osc_a_update_count = osc_a_update_count + 1;
        end

        if (dut.osc_b_task_update_valid) begin
            osc_b_slot_log[osc_b_update_count]
                = dut.osc_b_task_update_slot;
            osc_b_step_log[osc_b_update_count]
                = dut.osc_b_task_update_phase_step;
            osc_b_enable_log[osc_b_update_count]
                = dut.osc_b_task_update_enable;
            osc_b_update_count = osc_b_update_count + 1;
        end

        if (dut.osc_a_mix_valid != dut.osc_b_mix_valid)
            valid_mismatch_count = valid_mismatch_count + 1;
    end

    task send_uart_byte;
        input [7:0] value;
        integer bit_number;
        begin
            @(negedge sys_clk);
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);

            for (bit_number = 0; bit_number < 8;
                 bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(negedge sys_clk);
            end

            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
        end
    endtask

    task send_control_uart_byte;
        input [7:0] value;
        integer bit_number;
        begin
            @(negedge sys_clk);
            control_uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);

            for (bit_number = 0; bit_number < 8;
                 bit_number = bit_number + 1) begin
                control_uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(negedge sys_clk);
            end

            control_uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
        end
    endtask

    task send_cc;
        input [6:0] controller;
        input [6:0] value;
        begin
            send_uart_byte(8'hBF);
            send_uart_byte({1'b0, controller});
            send_uart_byte({1'b0, value});
        end
    endtask

    task send_highres_parameter;
        input [6:0] parameter_id;
        input [13:0] value;
        begin
            send_uart_byte(8'hF0);
            send_uart_byte(8'h7D);
            send_uart_byte({1'b0, parameter_id});
            send_uart_byte({1'b0, value[13:7]});
            send_uart_byte({1'b0, value[6:0]});
            send_uart_byte(8'hF7);
        end
    endtask

    task expect_a_update;
        input integer index;
        input [7:0] expected_slot;
        input [31:0] expected_step;
        input expected_enable;
        begin
            if (osc_a_slot_log[index] !== expected_slot
                || osc_a_step_log[index] !== expected_step
                || osc_a_enable_log[index] !== expected_enable) begin
                $display("ERROR: OSC A update %0d got slot=%0d step=%08x enable=%0d",
                         index, osc_a_slot_log[index],
                         osc_a_step_log[index],
                         osc_a_enable_log[index]);
                errors = errors + 1;
            end
        end
    endtask

    task expect_b_update;
        input integer index;
        input [7:0] expected_slot;
        input [31:0] expected_step;
        input expected_enable;
        begin
            if (osc_b_slot_log[index] !== expected_slot
                || osc_b_step_log[index] !== expected_step
                || osc_b_enable_log[index] !== expected_enable) begin
                $display("ERROR: OSC B update %0d got slot=%0d step=%08x enable=%0d",
                         index, osc_b_slot_log[index],
                         osc_b_step_log[index],
                         osc_b_enable_log[index]);
                errors = errors + 1;
            end
        end
    endtask

    task expect_pipelined_mix;
        input signed [15:0] sample_a;
        input signed [15:0] sample_b;
        input signed [15:0] expected_mix;
        begin
            force dut.osc_a_mix = sample_a;
            force dut.osc_b_mix = sample_b;
            force dut.osc_a_mix_valid = 1'b1;
            force dut.osc_b_mix_valid = 1'b1;
            @(posedge sys_clk);
            #1;
            if (dut.oscillator_mix !== expected_mix) begin
                $display("ERROR: pipelined mix got %0d, expected %0d",
                         dut.oscillator_mix, expected_mix);
                errors = errors + 1;
            end
            release dut.osc_a_mix;
            release dut.osc_b_mix;
            release dut.osc_a_mix_valid;
            release dut.osc_b_mix_valid;
            @(posedge sys_clk);
        end
    endtask

    task expect_master_output;
        input signed [15:0] filter_sample;
        input [8:0] gain_q8;
        input signed [15:0] expected_output;
        begin
            while (!dut.stereo_output_input_ready)
                @(posedge sys_clk);
            force dut.effect_processed_sample = filter_sample;
            force dut.global_effects_output_valid = 1'b1;
            force dut.global_filtered_sample = filter_sample;
            force dut.master_gain_q8 = gain_q8;
            force dut.stereo_side_latched = 16'sd0;
            force dut.lfo_pan_target = 7'd64;
            @(posedge sys_clk);
            #1;
            release dut.global_effects_output_valid;
            while (!dut.stereo_output_valid)
                @(posedge sys_clk);
            #1;
            if (dut.master_output_left !== expected_output
                || dut.master_output_right !== expected_output) begin
                $display("ERROR: master gain got %0d, expected %0d",
                         dut.master_output_sample, expected_output);
                errors = errors + 1;
            end
            release dut.effect_processed_sample;
            release dut.global_filtered_sample;
            release dut.master_gain_q8;
            release dut.stereo_side_latched;
            release dut.lfo_pan_target;
            @(posedge sys_clk);
        end
    endtask

    task expect_mix_clip_protection;
        begin
            clip_count_before = dut.audio_clip_count;
            force dut.osc_a_mix = 16'sh7FFF;
            force dut.osc_b_mix = 16'sh7FFF;
            force dut.osc_a_mix_valid = 1'b1;
            force dut.osc_b_mix_valid = 1'b1;
            force dut.osc_a_mix_gain_q8 = 9'd256;
            force dut.osc_b_mix_gain_q8 = 9'd256;
            @(posedge sys_clk);
            #1;
            @(posedge sys_clk);
            #1;
            if (dut.oscillator_mix !== 16'sh7FFF
                || dut.oscillator_mix_clip !== 1'b1
                || dut.audio_clip_count <= clip_count_before) begin
                $display("ERROR: mixer saturation or clip monitor failed");
                errors = errors + 1;
            end
            release dut.osc_a_mix;
            release dut.osc_b_mix;
            release dut.osc_a_mix_valid;
            release dut.osc_b_mix_valid;
            release dut.osc_a_mix_gain_q8;
            release dut.osc_b_mix_gain_q8;
            @(posedge sys_clk);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        uart_rx = 1'b1;
        control_uart_rx = 1'b1;
        keyboard_uart_rx = 1'b1;
        sd_dat0 = 1'b1;
        errors = 0;
        osc_a_update_count = 0;
        osc_b_update_count = 0;
        valid_mismatch_count = 0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (6) @(posedge sys_clk);

        // 演奏通道上的CC不能修改控制参数。
        send_uart_byte(8'hB0);
        send_uart_byte(8'h17);
        send_uart_byte(8'h07);
        repeat (3) @(posedge sys_clk);
        if (dut.osc_a_unison_count !== 4'd1
            || dut.osc_b_unison_count !== 4'd1) begin
            $display("ERROR: performance-channel CC changed oscillator controls");
            errors = errors + 1;
        end

        // OSC A：3成员Unison和默认Detune；OSC B：2成员且Detune为0。
        send_cc(7'd20, 7'd85);
        send_cc(7'd21, 7'd127);
        send_cc(7'd22, 7'd64);
        send_cc(7'd23, 7'd3);
        send_cc(7'd24, 7'd12);
        send_cc(7'd25, 7'd34);
        send_cc(7'd26, 7'd56);
        send_cc(7'd27, 7'd0);
        send_cc(7'd38, 7'd5);
        send_cc(7'd39, 7'd96);

        send_cc(7'd28, 7'd42);
        send_cc(7'd29, 7'd0);
        send_cc(7'd30, 7'd0);
        send_cc(7'd31, 7'd2);
        send_cc(7'd32, 7'd7);
        send_cc(7'd33, 7'd8);
        send_cc(7'd34, 7'd100);
        send_cc(7'd35, 7'd0);
        send_cc(7'd40, 7'd11);
        send_cc(7'd41, 7'd127);
        send_cc(7'd42, 7'd1);
        send_cc(7'd43, 7'd80);
        send_cc(7'd44, 7'd48);
        send_cc(7'd45, 7'd72);
        send_cc(7'd46, 7'd100);
        send_cc(7'd47, 7'd60);
        send_cc(7'd48, 7'd96);
        send_cc(7'd49, 7'd3);
        send_cc(7'd50, 7'd7);
        send_cc(7'd10, 7'd23);
        send_cc(7'd91, 7'd0);
        send_cc(7'd92, 7'd127);

        repeat (3) @(posedge sys_clk);
        if (dut.osc_a_wt_position_target !== 7'd85
            || dut.osc_a_waveform_select !== 3'd4
            || dut.osc_a_detune_amount !== 7'd64
            || dut.osc_a_unison_count !== 4'd3
            || dut.osc_a_attack_control !== 7'd12
            || dut.osc_a_decay_control !== 7'd34
            || dut.osc_a_sustain_control_target !== 7'd56
            || dut.osc_a_release_control !== 7'd0
            || dut.osc_a_warp_mode !== 4'd5
            || dut.osc_a_warp_amount_target !== 7'd96) begin
            $display("ERROR: OSC A controls were not routed independently");
            errors = errors + 1;
        end

        if (dut.osc_b_wt_position_target !== 7'd42
            || dut.osc_b_waveform_select !== 3'd0
            || dut.osc_b_detune_amount !== 7'd0
            || dut.osc_b_unison_count !== 4'd2
            || dut.osc_b_attack_control !== 7'd7
            || dut.osc_b_decay_control !== 7'd8
            || dut.osc_b_sustain_control_target !== 7'd100
            || dut.osc_b_release_control !== 7'd0
            || dut.osc_b_warp_mode !== 4'd11
            || dut.osc_b_warp_amount_target !== 7'd127) begin
            $display("ERROR: OSC B controls were not routed independently");
            errors = errors + 1;
        end

        if (dut.filter_mode_target !== 3'd1
            || dut.filter_cutoff_target !== 7'd80
            || dut.filter_resonance_target !== 7'd48
            || dut.filter_mix_target !== 7'd72
            || dut.osc_a_level !== 7'd100
            || dut.osc_b_level !== 7'd60
            || dut.master_level_target !== 7'd96
            || dut.osc_a_mix_gain_target_q8 !== 9'd50
            || dut.osc_b_mix_gain_target_q8 !== 9'd30
            || dut.master_gain_target_q8 !== 9'd194
            || dut.osc_a_wavetable_index !== 4'd3
             || dut.osc_b_wavetable_index !== 4'd7
             || dut.pan_target !== 7'd23
             || dut.osc_a_pan_target !== 7'd0
             || dut.osc_b_pan_target !== 7'd127) begin
            $display("ERROR: global filter controls were not routed");
            errors = errors + 1;
        end

        // Master乘法保持宽位并在最后压回16位；0.5增益应精确减半。
        expect_master_output(16'sd16000, 9'd128, 16'sd8000);

        // 后续音频回归使用中心声像。
        send_cc(7'd10, 7'd64);
        send_cc(7'd91, 7'd64);
        send_cc(7'd92, 7'd64);

        // 后续音符调度回归保持效果器旁路，避免Delay/Reverb尾音干扰静音判定。
        send_cc(7'd51, 7'd0);

        // 后续开关交叉渐变测试使用最大Level和Master。
        send_cc(7'd46, 7'd127);
        send_cc(7'd47, 7'd127);
        send_cc(7'd48, 7'd127);

        // V2固定目标23为Cutoff，配置只在后台构表完成后生效。
        send_highres_parameter(7'd96, 14'h140);
        send_highres_parameter(7'd72, 14'd4);
        send_highres_parameter(7'd126, 14'd0);
        repeat (6000) @(posedge sys_clk);
        if (dut.u_lfo_v2_engine.active_sources[46+:2] !== 2'd1
            || dut.u_lfo_v2_engine.active_depths[184+:8] !== 8'd64
            || dut.lfo_v2_config_error) begin
            $display("ERROR: V2 LFO route configuration was not committed");
            errors = errors + 1;
        end

        // 两组平滑器未到目标时前进一步，到达后保持。构表等待时间增加后，
        // WT B可能已到42，不能继续要求它无条件加1。
        wt_a_before = dut.osc_a_wt_position_current;
        wt_b_before = dut.osc_b_wt_position_current;
        warp_a_before = dut.osc_a_warp_amount_current;
        warp_b_before = dut.osc_b_warp_amount_current;
        @(posedge dut.sample_tick);
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_wt_position_current !== (wt_a_before < 85 ? wt_a_before + 1 : 85)
            || dut.osc_b_wt_position_current !== (wt_b_before < 42 ? wt_b_before + 1 : 42)
            || dut.osc_a_warp_amount_current !== (warp_a_before < 96 ? warp_a_before + 1 : 96)
            || dut.osc_b_warp_amount_current !== (warp_b_before < 127 ? warp_b_before + 1 : 127)) begin
            $display("ERROR: independent parameter smoothing failed");
            errors = errors + 1;
        end

        // 效果器参数使用CC51～57；验证后回到旁路，保持后续音频回归的原条件。
        send_cc(7'd51, 7'd3);
        send_cc(7'd52, 7'd80);
        send_cc(7'd53, 7'd70);
        send_cc(7'd54, 7'd60);
        send_cc(7'd55, 7'd90);
        send_cc(7'd56, 7'd75);
        send_cc(7'd57, 7'd55);
        send_cc(7'd58, 7'd127);
        send_cc(7'd59, 7'd2);
        send_cc(7'd60, 7'd91);
        send_cc(7'd61, 7'd92);
        send_cc(7'd62, 7'd93);
        send_cc(7'd63, 7'd127);
        send_cc(7'd64, 7'd41);
        send_cc(7'd65, 7'd42);
        send_cc(7'd66, 7'd43);
        send_cc(7'd67, 7'd44);
        send_cc(7'd68, 7'd45);
        send_cc(7'd69, 7'd127);
        send_cc(7'd70, 7'd51);
        send_cc(7'd71, 7'd52);
        send_cc(7'd72, 7'd53);
        send_cc(7'd73, 7'd54);
        send_cc(7'd74, 7'd55);
        send_cc(7'd75, 7'd127);
        send_cc(7'd76, 7'd61);
        send_cc(7'd77, 7'd62);
        send_cc(7'd78, 7'd63);
        send_cc(7'd79, 7'd64);
        send_cc(7'd80, 7'd65);
        send_cc(7'd81, 7'd66);
        repeat (3) @(posedge sys_clk);
        if (dut.effect_mode_target !== 2'd3
            || dut.delay_time_target !== 7'd80
            || dut.delay_feedback_target !== 7'd70
            || dut.delay_mix_target !== 7'd60
            || dut.reverb_size_target !== 7'd90
            || dut.reverb_decay_target !== 7'd75
            || dut.reverb_mix_target !== 7'd55
            || !dut.distortion_enable_target
            || dut.distortion_type_target !== 2'd2
            || dut.distortion_drive_target !== 7'd91
            || dut.distortion_tone_target !== 7'd92
            || dut.distortion_mix_target !== 7'd93
            || !dut.chorus_enable_target
            || dut.chorus_rate_target !== 7'd41
            || dut.chorus_depth_target !== 7'd42
            || dut.chorus_delay_target !== 7'd43
            || dut.chorus_feedback_target !== 7'd44
            || dut.chorus_mix_target !== 7'd45
            || !dut.phaser_enable_target
            || dut.phaser_rate_target !== 7'd51
            || dut.phaser_depth_target !== 7'd52
            || dut.phaser_center_target !== 7'd53
            || dut.phaser_feedback_target !== 7'd54
            || dut.phaser_mix_target !== 7'd55
            || !dut.compressor_enable_target
            || dut.compressor_threshold_target !== 7'd61
            || dut.compressor_ratio_target !== 7'd62
            || dut.compressor_attack_target !== 7'd63
            || dut.compressor_release_target !== 7'd64
            || dut.compressor_makeup_target !== 7'd65
            || dut.compressor_mix_target !== 7'd66) begin
            $display("ERROR: global effect controls were not routed");
            errors = errors + 1;
        end
        send_cc(7'd51, 7'd0);
        send_cc(7'd58, 7'd0);
        send_cc(7'd63, 7'd0);
        send_cc(7'd69, 7'd0);
        send_cc(7'd75, 7'd0);

        // 非零深度下切换Warp模式时，必须先退回深度0，再提交新模式。
        if (dut.osc_a_warp_mode_active !== 4'd5) begin
            $display("ERROR: OSC A initial active warp mode is incorrect");
            errors = errors + 1;
        end
        send_cc(7'd38, 7'd3);
        if ((dut.osc_a_warp_amount_current != 7'd0)
            && (dut.osc_a_warp_mode_active != 4'd5)) begin
            $display("ERROR: warp mode changed before amount returned to zero");
            errors = errors + 1;
        end

        switch_wait_samples = 0;
        while ((dut.osc_a_warp_mode_active != 4'd3)
               && (switch_wait_samples < 140)) begin
            @(posedge dut.sample_tick);
            @(posedge sys_clk);
            #1;
            switch_wait_samples = switch_wait_samples + 1;
        end
        if (dut.osc_a_warp_mode_active !== 4'd3
            || dut.osc_a_warp_amount_current !== 7'd0) begin
            $display("ERROR: clickless warp mode transition failed");
            errors = errors + 1;
        end

        @(posedge dut.sample_tick);
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_warp_amount_current !== 7'd1) begin
            $display("ERROR: warp amount did not rise after mode transition");
            errors = errors + 1;
        end

        // 关闭OSC A后，A平滑降到0，B升到带6 dB余量的0.5增益。
        send_cc(7'd36, 7'd0);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd0)
                || (dut.osc_b_mix_gain_q8 != 9'd128))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b0
            || dut.osc_b_enabled !== 1'b1
            || dut.osc_a_mix_gain_q8 !== 9'd0
            || dut.osc_b_mix_gain_q8 !== 9'd128) begin
            $display("ERROR: OSC A switch did not reach muted crossfade state");
            errors = errors + 1;
        end
        expect_pipelined_mix(16'sd16000, -16'sd12000, -16'sd6000);

        // 从“仅B”切换到“仅A”，验证两个开关互相独立。
        send_cc(7'd36, 7'd127);
        send_cc(7'd37, 7'd0);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd128)
                || (dut.osc_b_mix_gain_q8 != 9'd0))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b1
            || dut.osc_b_enabled !== 1'b0
            || dut.osc_a_mix_gain_q8 !== 9'd128
            || dut.osc_b_mix_gain_q8 !== 9'd0) begin
            $display("ERROR: OSC B switch did not reach muted crossfade state");
            errors = errors + 1;
        end
        expect_pipelined_mix(16'sd16000, -16'sd12000, 16'sd8000);

        // 后续音符测试恢复两路开启，各自回到0.25增益。
        send_cc(7'd37, 7'd127);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd64)
                || (dut.osc_b_mix_gain_q8 != 9'd64))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b1
            || dut.osc_b_enabled !== 1'b1
            || dut.osc_a_mix_gain_q8 !== 9'd64
            || dut.osc_b_mix_gain_q8 !== 9'd64) begin
            $display("ERROR: dual oscillator gain did not return to 0.25 each");
            errors = errors + 1;
        end
        expect_pipelined_mix(16'sd16000, -16'sd12000, 16'sd1000);

        // 控制通道上的Note必须被丢弃。
        send_uart_byte(8'h9F);
        send_uart_byte(8'h30);
        send_uart_byte(8'h7F);
        repeat (40) @(posedge sys_clk);
        if (osc_a_update_count !== 0 || osc_b_update_count !== 0) begin
            $display("ERROR: control-channel note reached a scheduler");
            errors = errors + 1;
        end

        // 同一个中央C事件扇出到两个独立调度器。
        send_uart_byte(8'h90);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h64);
        repeat (80) @(posedge sys_clk);

        if (osc_a_update_count !== 3 || osc_b_update_count !== 2) begin
            $display("ERROR: dual allocation counts A=%0d B=%0d",
                     osc_a_update_count, osc_b_update_count);
            errors = errors + 1;
        end

        expect_a_update(0, 8'd0, 32'h0016460E, 1'b1);
        expect_a_update(1, 8'd1, 32'h0016534C, 1'b1);
        expect_a_update(2, 8'd2, 32'h0016608A, 1'b1);
        expect_b_update(0, 8'd0, 32'h0016534C, 1'b1);
        expect_b_update(1, 8'd1, 32'h0016534C, 1'b1);

        if (dut.osc_a_active_task_count !== 6'd3
            || dut.osc_b_active_task_count !== 6'd2) begin
            $display("ERROR: active task counts A=%0d B=%0d",
                     dut.osc_a_active_task_count,
                     dut.osc_b_active_task_count);
            errors = errors + 1;
        end

        if (dut.u_osc_a_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[2] !== 1'b1
            || dut.u_osc_b_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[1] !== 1'b1) begin
            $display("ERROR: independent TDM banks did not receive updates");
            errors = errors + 1;
        end

        // Note Off也必须分别释放A的3个任务和B的2个任务。
        send_uart_byte(8'h80);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h00);
        repeat (80) @(posedge sys_clk);

        if (osc_a_update_count !== 6 || osc_b_update_count !== 4) begin
            $display("ERROR: dual release counts A=%0d B=%0d",
                     osc_a_update_count, osc_b_update_count);
            errors = errors + 1;
        end
        expect_a_update(3, 8'd0, 32'h0016460E, 1'b0);
        expect_a_update(4, 8'd1, 32'h0016534C, 1'b0);
        expect_a_update(5, 8'd2, 32'h0016608A, 1'b0);
        expect_b_update(2, 8'd0, 32'h0016534C, 1'b0);
        expect_b_update(3, 8'd1, 32'h0016534C, 1'b0);

        release_wait_cycles = 0;
        while (((dut.osc_a_active_task_count != 6'd0)
                || (dut.osc_b_active_task_count != 6'd0))
               && (release_wait_cycles < 200000)) begin
            @(posedge sys_clk);
            release_wait_cycles = release_wait_cycles + 1;
        end

        if (dut.osc_a_active_task_count !== 6'd0
            || dut.osc_b_active_task_count !== 6'd0) begin
            $display("ERROR: released tasks did not return both banks to idle");
            errors = errors + 1;
        end

        // Bank流水线允许少量在途数据，随后双Bank混音必须稳定静音。
        silence_check_count = 0;
        consecutive_silent_samples = 0;
        while ((silence_check_count < 16)
               && (consecutive_silent_samples < 4)) begin
            @(posedge dut.oscillator_mix_valid);
            #1;
            if (dut.oscillator_mix === 16'sd0)
                consecutive_silent_samples
                    = consecutive_silent_samples + 1;
            else
                consecutive_silent_samples = 0;
            silence_check_count = silence_check_count + 1;
        end

        if (consecutive_silent_samples < 4) begin
            $display("ERROR: dual oscillator mix did not settle to silence");
            errors = errors + 1;
        end

        // C19控制口与原UART、实体键盘口并行工作。验证其Note On/Off
        // 使用同一性能通道过滤和双振荡器调度路径。
        c19_a_update_before = osc_a_update_count;
        c19_b_update_before = osc_b_update_count;
        send_control_uart_byte(8'h90);
        send_control_uart_byte(8'h3E);
        send_control_uart_byte(8'h5A);
        repeat (80) @(posedge sys_clk);
        if (osc_a_update_count !== c19_a_update_before + 3
            || osc_b_update_count !== c19_b_update_before + 2) begin
            $display("ERROR: C19 Note On did not reach both schedulers A=%0d B=%0d",
                     osc_a_update_count - c19_a_update_before,
                     osc_b_update_count - c19_b_update_before);
            errors = errors + 1;
        end

        send_control_uart_byte(8'h80);
        send_control_uart_byte(8'h3E);
        send_control_uart_byte(8'h00);
        repeat (80) @(posedge sys_clk);
        if (osc_a_update_count !== c19_a_update_before + 6
            || osc_b_update_count !== c19_b_update_before + 4) begin
            $display("ERROR: C19 Note Off did not reach both schedulers A=%0d B=%0d",
                     osc_a_update_count - c19_a_update_before,
                     osc_b_update_count - c19_b_update_before);
            errors = errors + 1;
        end

        if (valid_mismatch_count != 0) begin
            $display("ERROR: OSC A/B valid pulses were misaligned %0d times",
                     valid_mismatch_count);
            errors = errors + 1;
        end

        if (dut.oscillator_schedule_overrun !== 1'b0) begin
            $display("ERROR: a 1x32 oscillator bank overran its schedule");
            errors = errors + 1;
        end

        if (dut.uart_framing_error !== 1'b0
            || MAX_SD !== 1'b1 || MAX_GAIN !== 1'b1
            || PA_EN !== 1'b0) begin
            $display("ERROR: UART or audio output control state is incorrect");
            errors = errors + 1;
        end

        // 故意制造超量输入，确认最终饱和不会二进制回绕，且调试计数有效。
        expect_mix_clip_protection();
        expect_master_output(16'sh7FFF, 9'd256, 16'sh7FFF);
        if (dut.filter_output_limit !== 1'b1) begin
            $display("ERROR: filter endpoint monitor did not latch");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: independent OSC A/B routing, scheduling, and mixing");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: dual-oscillator top test timed out");
        $finish;
    end

endmodule
