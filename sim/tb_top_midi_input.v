`timescale 1ns/1ps

module tb_top_midi_input;

    localparam integer TEST_UART_BAUD = 2500000;
    localparam integer CLKS_PER_BIT   = 50000000 / TEST_UART_BAUD;

    reg sys_clk;
    reg rst_n;
    reg uart_rx;

    wire MAX_SD;
    wire MAX_GAIN;
    wire MAX_DIN;
    wire MAX_BCLK;
    wire MAX_LRC;
    wire PA_EN;

    integer errors;
    integer update_count;
    integer check_index;
    integer observed_active_count;
    integer release_wait_cycles;
    integer silence_check_count;
    integer consecutive_silent_samples;
    integer wt_position_before;
    reg [7:0]  update_slot_log [0:31];
    reg [31:0] update_phase_step_log [0:31];
    reg [6:0]  update_velocity_log [0:31];
    reg        update_enable_log [0:31];
    reg        update_reset_log [0:31];

    top #(
        .UART_BAUD_RATE(TEST_UART_BAUD),
        .DEFAULT_UNISON_COUNT(1)
    ) dut (
        .sys_clk(sys_clk),
        .rst_n  (rst_n),
        .uart_rx(uart_rx),
        .MAX_SD  (MAX_SD),
        .MAX_GAIN(MAX_GAIN),
        .MAX_DIN (MAX_DIN),
        .MAX_BCLK(MAX_BCLK),
        .MAX_LRC (MAX_LRC),
        .PA_EN   (PA_EN)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.task_update_valid) begin
            update_slot_log[update_count] = dut.task_update_slot;
            update_phase_step_log[update_count]
                = dut.task_update_phase_step;
            update_velocity_log[update_count]
                = dut.task_update_velocity;
            update_enable_log[update_count] = dut.task_update_enable;
            update_reset_log[update_count]
                = dut.task_update_phase_reset;
            update_count = update_count + 1;
        end
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

    task expect_update;
        input integer log_index;
        input [7:0] expected_slot;
        input [31:0] expected_phase_step;
        input [6:0] expected_velocity;
        input expected_enable;
        input expected_reset;
        begin
            if (update_slot_log[log_index] !== expected_slot
                || update_phase_step_log[log_index]
                    !== expected_phase_step
                || update_velocity_log[log_index] !== expected_velocity
                || update_enable_log[log_index] !== expected_enable
                || update_reset_log[log_index] !== expected_reset) begin
                $display("ERROR: update %0d got slot=%0d phase=%08x velocity=%0d enable=%0d reset=%0d",
                         log_index,
                         update_slot_log[log_index],
                         update_phase_step_log[log_index],
                         update_velocity_log[log_index],
                         update_enable_log[log_index],
                         update_reset_log[log_index]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        sys_clk      = 1'b0;
        rst_n        = 1'b0;
        uart_rx      = 1'b1;
        errors       = 0;
        update_count = 0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (6) @(posedge sys_clk);

        // 演奏通道上的CC不能修改全局合成参数。
        send_uart_byte(8'hB0);
        send_uart_byte(8'h0A);
        send_uart_byte(8'h00);
        repeat (3) @(posedge sys_clk);
        if (dut.pan_target !== 7'd64) begin
            $display("ERROR: performance-channel CC changed synth control");
            errors = errors + 1;
        end

        // 通道16承载全局参数，并支持Running Status。
        send_uart_byte(8'hBF);
        send_uart_byte(8'h0A);
        send_uart_byte(8'h20);
        send_uart_byte(8'h14);
        send_uart_byte(8'h55);
        send_uart_byte(8'h16);
        send_uart_byte(8'h40);
        send_uart_byte(8'h17);
        send_uart_byte(8'h03);
        send_uart_byte(8'h18);
        send_uart_byte(8'h0C);
        send_uart_byte(8'h19);
        send_uart_byte(8'h22);
        send_uart_byte(8'h1A);
        send_uart_byte(8'h38);
        send_uart_byte(8'h1B);
        // 使用约1 ms Release缩短顶层回归等待时间。
        send_uart_byte(8'h00);
        repeat (3) @(posedge sys_clk);
        if (dut.pan_target !== 7'd32
            || dut.wt_position_target !== 7'd85
            || dut.detune_amount !== 7'd64
            || dut.unison_count !== 4'd3
            || dut.attack_control !== 7'd12
            || dut.decay_control !== 7'd34
            || dut.sustain_control_target !== 7'd56
            || dut.release_control !== 7'd0) begin
            $display("ERROR: channel-16 synth controls were not routed");
            errors = errors + 1;
        end

        // 目标值经96 kHz采样脉冲逐级逼近，不能直接跳到85。
        wt_position_before = dut.wt_position_current;
        @(posedge dut.sample_tick);
        @(posedge sys_clk);
        #1;
        if (dut.wt_position_current !== (wt_position_before + 1)) begin
            $display("ERROR: WT Position smoother did not advance by one step");
            errors = errors + 1;
        end

        send_uart_byte(8'h17);
        send_uart_byte(8'h00);
        repeat (3) @(posedge sys_clk);
        if (dut.unison_count !== 4'd1) begin
            $display("ERROR: zero Unison value was not clamped to one");
            errors = errors + 1;
        end

        send_uart_byte(8'h17);
        send_uart_byte(8'h7F);
        repeat (3) @(posedge sys_clk);
        if (dut.unison_count !== 4'd8) begin
            $display("ERROR: large Unison value was not clamped to eight");
            errors = errors + 1;
        end

        // 恢复为3成员，供后续声部分配回归使用。
        send_uart_byte(8'h17);
        send_uart_byte(8'h03);
        repeat (3) @(posedge sys_clk);

        // CC21使用数值高两位选择正弦、三角、方波、锯齿。
        send_uart_byte(8'h15);
        send_uart_byte(8'h00);
        repeat (3) @(posedge sys_clk);
        if (dut.waveform_select !== 3'd0) begin
            $display("ERROR: CC21 did not select sine");
            errors = errors + 1;
        end

        send_uart_byte(8'h15);
        send_uart_byte(8'h20);
        repeat (3) @(posedge sys_clk);
        if (dut.waveform_select !== 3'd1) begin
            $display("ERROR: running-status CC21 did not select triangle");
            errors = errors + 1;
        end

        send_uart_byte(8'h15);
        send_uart_byte(8'hF8);
        send_uart_byte(8'h40);
        repeat (3) @(posedge sys_clk);
        if (dut.waveform_select !== 3'd2) begin
            $display("ERROR: realtime-interleaved CC21 did not select square");
            errors = errors + 1;
        end

        send_uart_byte(8'h15);
        send_uart_byte(8'h60);
        repeat (3) @(posedge sys_clk);
        if (dut.waveform_select !== 3'd3) begin
            $display("ERROR: running-status CC21 did not select sawtooth");
            errors = errors + 1;
        end

        send_uart_byte(8'h15);
        send_uart_byte(8'h7F);
        repeat (3) @(posedge sys_clk);
        if (dut.waveform_select !== 3'd4) begin
            $display("ERROR: CC21 value 127 did not select Acid wavetable");
            errors = errors + 1;
        end

        // 后续音频回归继续使用旧版本的默认方波。
        send_uart_byte(8'h15);
        send_uart_byte(8'h40);
        repeat (3) @(posedge sys_clk);

        // 控制通道上的音符必须被路由器丢弃。
        send_uart_byte(8'h9F);
        send_uart_byte(8'h30);
        send_uart_byte(8'h7F);
        repeat (10) @(posedge sys_clk);
        if (update_count !== 0) begin
            $display("ERROR: control-channel note reached scheduler");
            errors = errors + 1;
        end

        // Note On 60. Three ordinary tasks are spread across engines.
        send_uart_byte(8'h90);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h64);

        // Running status Note On 64.
        send_uart_byte(8'h40);
        send_uart_byte(8'h50);

        // A realtime Clock byte may be interleaved without breaking status.
        send_uart_byte(8'h43);
        send_uart_byte(8'hF8);
        send_uart_byte(8'h60);

        // Note On with velocity zero is Note Off for note 60.
        send_uart_byte(8'h3C);
        send_uart_byte(8'h00);

        // Explicit Note Off for note 64.
        send_uart_byte(8'h80);
        send_uart_byte(8'h40);
        send_uart_byte(8'h00);

        // Outside the supported 88-key lookup-table range: ignored.
        send_uart_byte(8'h90);
        send_uart_byte(8'h05);
        send_uart_byte(8'h64);

        repeat (50) @(posedge sys_clk);

        if (update_count !== 15) begin
            $display("ERROR: expected 15 task updates, got %0d",
                     update_count);
            errors = errors + 1;
        end

        expect_update(0,  8'd0,  32'h0016460E, 7'd100, 1'b1, 1'b1);
        expect_update(1,  8'd8,  32'h0016534C, 7'd100, 1'b1, 1'b1);
        expect_update(2,  8'd16, 32'h0016608A, 7'd100, 1'b1, 1'b1);
        expect_update(3,  8'd24, 32'h001C1021, 7'd80, 1'b1, 1'b1);
        expect_update(4,  8'd1,  32'h001C20D3, 7'd80, 1'b1, 1'b1);
        expect_update(5,  8'd9,  32'h001C3185, 7'd80, 1'b1, 1'b1);
        expect_update(6,  8'd17, 32'h00215F6D, 7'd96, 1'b1, 1'b1);
        expect_update(7,  8'd25, 32'h00217345, 7'd96, 1'b1, 1'b1);
        expect_update(8,  8'd2,  32'h0021871D, 7'd96, 1'b1, 1'b1);
        expect_update(9,  8'd0,  32'h0016460E, 7'd100, 1'b0, 1'b0);
        expect_update(10, 8'd8,  32'h0016534C, 7'd100, 1'b0, 1'b0);
        expect_update(11, 8'd16, 32'h0016608A, 7'd100, 1'b0, 1'b0);
        expect_update(12, 8'd1,  32'h001C20D3, 7'd80, 1'b0, 1'b0);
        expect_update(13, 8'd9,  32'h001C3185, 7'd80, 1'b0, 1'b0);
        expect_update(14, 8'd24, 32'h001C1021, 7'd80, 1'b0, 1'b0);

        if (dut.u_oscillator_task_scheduler.slot_active[2] !== 1'b1
            || dut.u_oscillator_task_scheduler.slot_active[17] !== 1'b1
            || dut.u_oscillator_task_scheduler.slot_active[25] !== 1'b1
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[2] !== 1'b1
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[2]
                .u_oscillator_tdm_core.enable_state[1] !== 1'b1
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[3]
                .u_oscillator_tdm_core.enable_state[1] !== 1'b1
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.velocity_state[2] !== 7'd96
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[2]
                .u_oscillator_tdm_core.velocity_state[1] !== 7'd96
            || dut.u_oscillator_tdm_bank.GEN_ENGINE[3]
                .u_oscillator_tdm_core.velocity_state[1] !== 7'd96) begin
            $display("ERROR: held three-task note did not remain active");
            errors = errors + 1;
        end

        for (check_index = 0; check_index < 32;
             check_index = check_index + 1) begin
            if (dut.u_oscillator_task_scheduler.slot_active[check_index]
                && (dut.u_oscillator_task_scheduler.slot_note[check_index]
                    == 7'd60
                    || dut.u_oscillator_task_scheduler.slot_note[check_index]
                       == 7'd64)
                && !dut.u_oscillator_task_scheduler
                    .slot_releasing[check_index]) begin
                $display("ERROR: released task %0d is not in Release",
                         check_index);
                errors = errors + 1;
            end
        end

        observed_active_count = 0;
        for (check_index = 0; check_index < 32;
             check_index = check_index + 1)
            if (dut.u_oscillator_task_scheduler.slot_active[check_index])
                observed_active_count = observed_active_count + 1;

        if (dut.active_task_count !== observed_active_count[5:0]) begin
            $display("ERROR: active task count got %0d, expected %0d",
                     dut.active_task_count, observed_active_count);
            errors = errors + 1;
        end

        if (dut.active_task_count < 6'd3
            || dut.active_task_count > 6'd9) begin
            $display("ERROR: active task count outside expected range: %0d",
                     dut.active_task_count);
            errors = errors + 1;
        end

        if (dut.uart_framing_error !== 1'b0) begin
            $display("ERROR: unexpected UART framing error");
            errors = errors + 1;
        end

        if (dut.oscillator_schedule_overrun !== 1'b0) begin
            $display("ERROR: four-engine oscillator schedule overrun");
            errors = errors + 1;
        end

        if (MAX_SD !== 1'b1 || MAX_GAIN !== 1'b1
            || PA_EN !== 1'b1) begin
            $display("ERROR: MAX98357A control outputs are incorrect");
            errors = errors + 1;
        end

        // 最后释放仍保持的音符67，验证所有Unison任务最终结束Release。
        send_uart_byte(8'h80);
        send_uart_byte(8'h43);
        send_uart_byte(8'h00);

        release_wait_cycles = 0;
        while ((dut.active_task_count != 6'd0)
               && (release_wait_cycles < 200000)) begin
            @(posedge sys_clk);
            release_wait_cycles = release_wait_cycles + 1;
        end

        if (update_count !== 18) begin
            $display("ERROR: expected 18 task updates after final Note Off, got %0d",
                     update_count);
            errors = errors + 1;
        end

        if (dut.active_task_count !== 6'd0) begin
            $display("ERROR: released MIDI notes did not return all tasks to idle");
            errors = errors + 1;
        end

        // Bank具有输出流水线，任务清零后允许残留少量已经在途的采样。
        // 在16个内部采样内必须进入静音，并连续保持4个采样为零。
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
            $display("ERROR: oscillator mix did not settle to silence after all Note Off events");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: UART MIDI parsing and generic task scheduling");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #5000000;
        $display("FAIL: top MIDI input test timed out");
        $finish;
    end

endmodule
