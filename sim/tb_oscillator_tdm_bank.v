`timescale 1ns/1ps

module tb_oscillator_tdm_bank;

    localparam integer ENGINE_COUNT       = 1;
    localparam integer SLOTS_PER_ENGINE   = 32;
    localparam integer TOTAL_SLOTS        = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam integer NOTE_WIDTH         = 7;
    localparam integer OUTPUT_SHIFT       = 5;
    localparam integer ENABLED_SCHEDULES  = 32;
    localparam integer TICK_PERIOD_CLOCKS = 65;

    reg clk;
    reg rst_n;
    reg start_tick;
    reg clear_phase;
    reg voice_update_valid;
    reg [7:0] voice_update_slot;
    reg [NOTE_WIDTH-1:0] voice_update_note;
    reg voice_update_enable;
    reg voice_update_phase_reset;

    wire signed [15:0] sample_out;
    wire sample_valid;
    wire schedule_overrun;
    wire [TOTAL_SLOTS-1:0] voice_idle_mask;
    wire debug_busy;
    wire [7:0] debug_slot;
    wire debug_slot_commit;

    integer errors;
    integer expected_slot;
    integer commit_count;
    integer valid_count;
    integer enabled_schedule_count;
    integer init_index;
    integer check_index;
    reg     saw_nonzero_sample;
    reg     saw_slot5_idle;

    oscillator_tdm_bank #(
        .ENGINE_COUNT(ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
        .NOTE_WIDTH(NOTE_WIDTH),
        .OUTPUT_SHIFT(OUTPUT_SHIFT),
        // 单元测试加速包络；板级默认参数保持约10/100/70%/190 ms。
        .ENVELOPE_UPDATE_DIV(1),
        .ATTACK_STEP(16'hFFFF),
        .DECAY_STEP(16'hFFFF),
        .SUSTAIN_LEVEL(16'h8000),
        .RELEASE_SHIFT(11),
        .RELEASE_END_LEVEL(16'hFFFF)
    ) dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .start_tick                (start_tick),
        .clear_phase               (clear_phase),
        .voice_update_valid        (voice_update_valid),
        .voice_update_slot         (voice_update_slot),
        .voice_update_note         (voice_update_note),
        .voice_update_enable       (voice_update_enable),
        .voice_update_phase_reset  (voice_update_phase_reset),
        .sample_out                (sample_out),
        .sample_valid              (sample_valid),
        .schedule_overrun          (schedule_overrun),
        .voice_idle_mask           (voice_idle_mask),
        .debug_engine0_busy        (debug_busy),
        .debug_engine0_slot        (debug_slot),
        .debug_engine0_slot_commit (debug_slot_commit)
    );

    always #10 clk = ~clk; // 50 MHz时钟

    task launch_internal_sample;
        begin
            @(negedge clk);
            start_tick = 1'b1;
            @(negedge clk);
            start_tick = 1'b0;
        end
    endtask

    task update_voice_slot;
        input integer slot_number;
        input [NOTE_WIDTH-1:0] note_number;
        input enable_value;
        input phase_reset_value;
        begin
            @(negedge clk);
            voice_update_valid       = 1'b1;
            voice_update_slot        = slot_number[7:0];
            voice_update_note        = note_number;
            voice_update_enable      = enable_value;
            voice_update_phase_reset = phase_reset_value;
            @(negedge clk);
            voice_update_valid       = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;

        if (debug_slot_commit) begin
            if (debug_slot !== expected_slot[7:0]) begin
                $display("ERROR: expected slot %0d, got %0d at %0t",
                         expected_slot, debug_slot, $time);
                errors = errors + 1;
            end

            expected_slot = (expected_slot + 1) % SLOTS_PER_ENGINE;
            commit_count = commit_count + 1;
        end

        if (sample_valid) begin
            valid_count = valid_count + 1;
            if (sample_out !== 16'sd0)
                saw_nonzero_sample = 1'b1;
        end


        if (voice_idle_mask[5])
            saw_slot5_idle = 1'b1;
    end

    initial begin
        clk             = 1'b0;
        rst_n           = 1'b0;
        start_tick      = 1'b0;
        clear_phase     = 1'b1;
        voice_update_valid       = 1'b0;
        voice_update_slot        = 8'd0;
        voice_update_note        = {NOTE_WIDTH{1'b0}};
        voice_update_enable      = 1'b0;
        voice_update_phase_reset = 1'b0;
        errors          = 0;
        expected_slot   = 0;
        commit_count    = 0;
        valid_count     = 0;
        enabled_schedule_count = 0;
        saw_nonzero_sample = 1'b0;
        saw_slot5_idle = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 即使槽位均未启用，也必须按可观察的0～31顺序执行，
        // 并输出零值采样，使FIR能够持续刷新。
        launch_internal_sample();
        wait (sample_valid);
        #1;
        if (sample_out !== 16'sd0) begin
            $display("ERROR: disabled schedule produced %0d", sample_out);
            errors = errors + 1;
        end

        // 通过单槽位更新接口依次配置MIDI 48～79，并启用全部32个槽位。
        for (init_index = 0;
             init_index < TOTAL_SLOTS;
             init_index = init_index + 1)
            update_voice_slot(init_index, 7'd48 + init_index, 1'b1, 1'b1);

        for (check_index = 0;
             check_index < TOTAL_SLOTS;
             check_index = check_index + 1) begin
            if (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                    .note_state[check_index] !== (7'd48 + check_index)) begin
                $display("ERROR: slot %0d note update failed", check_index);
                errors = errors + 1;
            end

            if (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                    .enable_state[check_index] !== 1'b1) begin
                $display("ERROR: slot %0d enable update failed", check_index);
                errors = errors + 1;
            end
        end

        // 启用全部32个槽位。由于所有相位累加器均从零相位开始，
        // 第一个输出采样为零。
        @(negedge clk);
        clear_phase = 1'b0;
        launch_internal_sample();
        wait (sample_valid);

        // 相邻768 kHz采样请求约间隔65个50 MHz时钟。每次32槽位调度完成后
        // 再等待剩余时钟，以验证实际请求速率下不会发生调度超时。
        for (enabled_schedule_count = 0;
             enabled_schedule_count < ENABLED_SCHEDULES;
             enabled_schedule_count = enabled_schedule_count + 1) begin
            repeat (TICK_PERIOD_CLOCKS - SLOTS_PER_ENGINE - 2)
                @(posedge clk);
            launch_internal_sample();
            wait (sample_valid);
        end

        #1;
        if (!saw_nonzero_sample) begin
            $display("ERROR: enabled schedules never advanced to a nonzero sample");
            errors = errors + 1;
        end

        // Note Off进入Release而不是立即关断；在下一次包络更新调度后
        // 电平归零、振荡器停用，并向分配器给出槽位完成脉冲。
        update_voice_slot(5, 7'd53, 1'b0, 1'b0);
        #1;
        if (dut.GEN_ENGINE[0].u_oscillator_tdm_core.enable_state[5]
            !== 1'b1) begin
            $display("ERROR: Note Off disabled slot before Release");
            errors = errors + 1;
        end

        repeat (TICK_PERIOD_CLOCKS - SLOTS_PER_ENGINE - 2)
            @(posedge clk);
        launch_internal_sample();
        wait (sample_valid);
        #1;
        if (dut.GEN_ENGINE[0].u_oscillator_tdm_core.enable_state[5]
            !== 1'b0) begin
            $display("ERROR: released slot did not become idle");
            errors = errors + 1;
        end

        if (!saw_slot5_idle) begin
            $display("ERROR: released slot did not emit idle completion");
            errors = errors + 1;
        end

        if (commit_count !== ((ENABLED_SCHEDULES + 3) * TOTAL_SLOTS)) begin
            $display("ERROR: expected %0d slot commits, got %0d",
                     (ENABLED_SCHEDULES + 3) * TOTAL_SLOTS,
                     commit_count);
            errors = errors + 1;
        end

        if (valid_count !== (ENABLED_SCHEDULES + 3)) begin
            $display("ERROR: expected %0d output samples, got %0d",
                     ENABLED_SCHEDULES + 3, valid_count);
            errors = errors + 1;
        end

        // 所有槽位都应拥有非零且互不相同的相位状态。
        for (check_index = 0;
             check_index < TOTAL_SLOTS;
             check_index = check_index + 1) begin
            if (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                    .phase_state[check_index] === 32'd0) begin
                $display("ERROR: slot %0d phase did not advance", check_index);
                errors = errors + 1;
            end

            if ((check_index > 0)
                && (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                        .phase_state[check_index]
                    === dut.GEN_ENGINE[0].u_oscillator_tdm_core
                        .phase_state[check_index-1])) begin
                $display("ERROR: slots %0d and %0d share the same phase state",
                         check_index-1, check_index);
                errors = errors + 1;
            end
        end

        // 单独重触发槽位5，确认更新接口不会清除其他槽位的相位。
        update_voice_slot(5, 7'd53, 1'b1, 1'b1);
        #1;
        if (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                .phase_state[5] !== 32'd0) begin
            $display("ERROR: slot 5 phase reset update failed");
            errors = errors + 1;
        end

        if (dut.GEN_ENGINE[0].u_oscillator_tdm_core
                .phase_state[4] === 32'd0) begin
            $display("ERROR: slot 5 phase reset disturbed slot 4");
            errors = errors + 1;
        end

        if (schedule_overrun) begin
            $display("ERROR: unexpected schedule overrun");
            errors = errors + 1;
        end

        // 错误路径检查：在第一次调度仍忙碌时再次发起采样请求。
        // 第二个请求会被有意拒绝，粘滞 overrun 标志必须反映该请求已丢失。
        launch_internal_sample();
        launch_internal_sample();
        repeat (2) @(posedge clk);
        if (!schedule_overrun) begin
            $display("ERROR: overlapping start_tick did not set overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: 32-slot updates, scheduler, phase state, and timing");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

endmodule
