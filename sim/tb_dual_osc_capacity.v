`timescale 1ns/1ps

// 两个独立振荡器 Bank 的容量测试。
// 目标配置：8 个复音、每个复音 Unison=8，因此每个 Bank 需要 64 个任务。
// ENGINE_COUNT 和 SLOTS_PER_ENGINE 在仿真命令行中覆盖，用于比较实体数与时分槽位。
module tb_dual_osc_capacity #(
    parameter integer ENGINE_COUNT       = 2,
    parameter integer SLOTS_PER_ENGINE   = 32,
    parameter integer VOICE_COUNT        = 8,
    parameter integer UNISON_COUNT       = 8,
    parameter integer TICK_PERIOD_CLOCKS = 65,
    parameter integer TEST_SAMPLES        = 12
);

    localparam integer TOTAL_SLOTS = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam integer REQUIRED_SLOTS = VOICE_COUNT * UNISON_COUNT;

    reg clk;
    reg rst_n;
    reg start_tick;
    reg clear_phase;
    reg [2:0] waveform_a;
    reg [2:0] waveform_b;
    reg [6:0] wt_position_a;
    reg [6:0] wt_position_b;
    reg [3:0] warp_mode;
    reg [6:0] warp_amount;
    reg [31:0] attack_phase_step;
    reg [31:0] decay_phase_step;
    reg [15:0] sustain_level;
    reg [31:0] release_phase_step;
    reg task_update_valid;
    reg [7:0] task_update_slot;
    reg [31:0] task_update_phase_step;
    reg [6:0] task_update_velocity;
    reg task_update_enable;
    reg task_update_phase_reset;
    reg [6:0] active_task_count;

    wire signed [15:0] sample_a;
    wire signed [15:0] sample_b;
    wire valid_a;
    wire valid_b;
    wire overrun_a;
    wire overrun_b;
    wire [TOTAL_SLOTS-1:0] idle_a;
    wire [TOTAL_SLOTS-1:0] idle_b;
    wire debug_busy_a;
    wire debug_busy_b;
    wire [7:0] debug_slot_a;
    wire [7:0] debug_slot_b;
    wire debug_commit_a;
    wire debug_commit_b;

    integer errors;
    integer update_index;
    integer sample_index;
    integer valid_count;
    integer commit_count_a;
    integer commit_count_b;
    integer overrun_seen_a;
    integer overrun_seen_b;
    integer nonzero_seen_a;
    integer nonzero_seen_b;
    integer engine_index;

    oscillator_tdm_bank #(
        .ENGINE_COUNT(ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
        .ENVELOPE_UPDATE_DIV(1)
    ) dut_a (
        .clk(clk),
        .rst_n(rst_n),
        .start_tick(start_tick),
        .clear_phase(clear_phase),
        .waveform_select(waveform_a),
        .wt_position(wt_position_a),
        .warp_mode(warp_mode),
        .warp_amount(warp_amount),
        .attack_phase_step(attack_phase_step),
        .decay_phase_step(decay_phase_step),
        .sustain_level(sustain_level),
        .release_phase_step(release_phase_step),
        .external_wavetable_enable(1'b0),
        .cache_load_clk(clk), .cache_load_rst_n(rst_n),
        .cache_write_enable(1'b0), .cache_write_bank(1'b0),
        .cache_write_frame(1'b0), .cache_write_address(8'd0),
        .cache_write_data(16'd0), .cache_commit_toggle(1'b0),
        .cache_commit_bank(1'b0), .cache_commit_fraction(8'd0),
        .task_update_valid(task_update_valid),
        .task_update_slot(task_update_slot),
        .task_update_phase_step(task_update_phase_step),
        .task_update_velocity(task_update_velocity),
        .task_update_enable(task_update_enable),
        .task_update_phase_reset(task_update_phase_reset),
        .active_task_count(active_task_count),
        .sample_out(sample_a),
        .sample_valid(valid_a),
        .schedule_overrun(overrun_a),
        .task_idle_mask(idle_a),
        .debug_engine0_busy(debug_busy_a),
        .debug_engine0_slot(debug_slot_a),
        .debug_engine0_slot_commit(debug_commit_a)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT(ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
        .ENVELOPE_UPDATE_DIV(1)
    ) dut_b (
        .clk(clk),
        .rst_n(rst_n),
        .start_tick(start_tick),
        .clear_phase(clear_phase),
        .waveform_select(waveform_b),
        .wt_position(wt_position_b),
        .warp_mode(warp_mode),
        .warp_amount(warp_amount),
        .attack_phase_step(attack_phase_step),
        .decay_phase_step(decay_phase_step),
        .sustain_level(sustain_level),
        .release_phase_step(release_phase_step),
        .external_wavetable_enable(1'b0),
        .cache_load_clk(clk), .cache_load_rst_n(rst_n),
        .cache_write_enable(1'b0), .cache_write_bank(1'b0),
        .cache_write_frame(1'b0), .cache_write_address(8'd0),
        .cache_write_data(16'd0), .cache_commit_toggle(1'b0),
        .cache_commit_bank(1'b0), .cache_commit_fraction(8'd0),
        .task_update_valid(task_update_valid),
        .task_update_slot(task_update_slot),
        .task_update_phase_step(task_update_phase_step),
        .task_update_velocity(task_update_velocity),
        .task_update_enable(task_update_enable),
        .task_update_phase_reset(task_update_phase_reset),
        .active_task_count(active_task_count),
        .sample_out(sample_b),
        .sample_valid(valid_b),
        .schedule_overrun(overrun_b),
        .task_idle_mask(idle_b),
        .debug_engine0_busy(debug_busy_b),
        .debug_engine0_slot(debug_slot_b),
        .debug_engine0_slot_commit(debug_commit_b)
    );

    always #10 clk = ~clk; // 50 MHz

    task update_slot;
        input integer slot_number;
        begin
            @(negedge clk);
            task_update_valid      = 1'b1;
            task_update_slot       = slot_number[7:0];
            task_update_phase_step = 32'h00010000
                                   + slot_number * 32'h00000100;
            @(negedge clk);
            task_update_valid      = 1'b0;
        end
    endtask

    task pulse_sample_tick;
        begin
            @(negedge clk);
            start_tick = 1'b1;
            @(negedge clk);
            start_tick = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        for (engine_index = 0;
             engine_index < ENGINE_COUNT;
             engine_index = engine_index + 1) begin
            if (dut_a.core_slot_commit[engine_index])
                commit_count_a = commit_count_a + 1;
            if (dut_b.core_slot_commit[engine_index])
                commit_count_b = commit_count_b + 1;
        end
        if (valid_a && valid_b) begin
            valid_count = valid_count + 1;
            if (sample_a !== 16'sd0)
                nonzero_seen_a = 1;
            if (sample_b !== 16'sd0)
                nonzero_seen_b = 1;
        end
        if (overrun_a)
            overrun_seen_a = 1;
        if (overrun_b)
            overrun_seen_b = 1;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_tick = 1'b0;
        clear_phase = 1'b1;
        // Bank A 使用 Acid 三维波表；Bank B 使用锯齿波，验证参数彼此独立。
        waveform_a = 3'd4;
        waveform_b = 3'd3;
        wt_position_a = 7'd64;
        wt_position_b = 7'd0;
        warp_mode = 4'd0;
        warp_amount = 7'd0;
        attack_phase_step = 32'hFFFFFFFF;
        decay_phase_step = 32'hFFFFFFFF;
        sustain_level = 16'hFFFF;
        release_phase_step = 32'hFFFFFFFF;
        task_update_valid = 1'b0;
        task_update_slot = 8'd0;
        task_update_phase_step = 32'd0;
        task_update_velocity = 7'd127;
        task_update_enable = 1'b1;
        task_update_phase_reset = 1'b1;
        active_task_count = 7'd0;
        errors = 0;
        valid_count = 0;
        commit_count_a = 0;
        commit_count_b = 0;
        overrun_seen_a = 0;
        overrun_seen_b = 0;
        nonzero_seen_a = 0;
        nonzero_seen_b = 0;

        if (TOTAL_SLOTS < REQUIRED_SLOTS) begin
            $display("RESULT: INVALID capacity=%0dx%0d total=%0d required=%0d",
                     ENGINE_COUNT, SLOTS_PER_ENGINE, TOTAL_SLOTS,
                     REQUIRED_SLOTS);
            $stop;
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        for (update_index = 0;
             update_index < REQUIRED_SLOTS;
             update_index = update_index + 1)
            update_slot(update_index);
        active_task_count = REQUIRED_SLOTS;
        clear_phase = 1'b0;

        pulse_sample_tick();
        for (sample_index = 1;
             sample_index < TEST_SAMPLES;
             sample_index = sample_index + 1) begin
            // pulse_sample_tick consumes one negedge while clearing the
            // previous pulse, so wait N-1 further negedges for an N-cycle
            // start-to-start interval.
            repeat (TICK_PERIOD_CLOCKS-1) @(negedge clk);
            pulse_sample_tick();
        end
        repeat (TICK_PERIOD_CLOCKS + 20) @(posedge clk);

        if (overrun_a || overrun_b)
            errors = errors + 1;
        if (valid_count < TEST_SAMPLES-1)
            errors = errors + 1;
        if (commit_count_a < REQUIRED_SLOTS*(TEST_SAMPLES-1))
            errors = errors + 1;
        if (commit_count_b < REQUIRED_SLOTS*(TEST_SAMPLES-1))
            errors = errors + 1;
        if (!nonzero_seen_a || !nonzero_seen_b)
            errors = errors + 1;

        $display("RESULT: capacity=%0dx%0d voices=%0d unison=%0d total=%0d required=%0d valid=%0d commitsA=%0d commitsB=%0d overrunA=%0d overrunB=%0d errors=%0d",
                 ENGINE_COUNT, SLOTS_PER_ENGINE, VOICE_COUNT, UNISON_COUNT,
                 TOTAL_SLOTS, REQUIRED_SLOTS, valid_count,
                 commit_count_a, commit_count_b,
                 overrun_seen_a, overrun_seen_b, errors);
        $stop;
    end

endmodule
