`timescale 1ns/1ps

module tb_top_fixed_note;

    reg sys_clk;
    reg rst_n;

    wire HP_BCK;
    wire HP_WS;
    wire HP_DIN;
    wire PA_EN;

    integer errors;
    integer note_event_count;
    integer task_update_count;
    integer sample_count;
    reg saw_nonzero_sample;
    reg [7:0] task_slot_log [0:2];
    reg [31:0] task_phase_step_log [0:2];

    top #(
        .FIXED_MIDI_NOTE(7'd69),
        .DEFAULT_UNISON_COUNT(3)
    ) dut (
        .sys_clk(sys_clk),
        .rst_n  (rst_n),
        .HP_BCK (HP_BCK),
        .HP_WS  (HP_WS),
        .HP_DIN (HP_DIN),
        .PA_EN  (PA_EN)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.fixed_note_event_valid)
            note_event_count = note_event_count + 1;

        if (dut.task_update_valid) begin
            task_slot_log[task_update_count] = dut.task_update_slot;
            task_phase_step_log[task_update_count]
                = dut.task_update_phase_step;
            task_update_count = task_update_count + 1;
        end

        if (dut.oscillator_mix_valid) begin
            sample_count = sample_count + 1;
            if (dut.oscillator_mix != 16'sd0)
                saw_nonzero_sample = 1'b1;
        end
    end

    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        errors = 0;
        note_event_count = 0;
        task_update_count = 0;
        sample_count = 0;
        saw_nonzero_sample = 1'b0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;

        repeat (2000) @(posedge sys_clk);
        #1;

        if (note_event_count != 1) begin
            $display("ERROR: expected one fixed Note On, got %0d",
                     note_event_count);
            errors = errors + 1;
        end

        if (task_update_count != 3) begin
            $display("ERROR: expected three Unison tasks, got %0d",
                     task_update_count);
            errors = errors + 1;
        end

        if (task_slot_log[0] !== 8'd0
            || task_phase_step_log[0] !== 32'h002575AA
            || task_slot_log[1] !== 8'd8
            || task_phase_step_log[1] !== 32'h00258BF2
            || task_slot_log[2] !== 8'd16
            || task_phase_step_log[2] !== 32'h0025A23A) begin
            $display("ERROR: A4 Unison task parameters are incorrect");
            errors = errors + 1;
        end

        if (dut.u_oscillator_task_scheduler.slot_note[0] !== 7'd69
            || dut.u_oscillator_task_scheduler.slot_note[8] !== 7'd69
            || dut.u_oscillator_task_scheduler.slot_note[16] !== 7'd69
            || !dut.u_oscillator_task_scheduler.slot_active[0]
            || !dut.u_oscillator_task_scheduler.slot_active[8]
            || !dut.u_oscillator_task_scheduler.slot_active[16]) begin
            $display("ERROR: A4 Unison ownership state is incorrect");
            errors = errors + 1;
        end

        if (dut.active_task_count !== 6'd3) begin
            $display("ERROR: active task count is %0d",
                     dut.active_task_count);
            errors = errors + 1;
        end

        if (sample_count == 0 || !saw_nonzero_sample) begin
            $display("ERROR: fixed note produced no nonzero audio samples");
            errors = errors + 1;
        end

        if (dut.oscillator_schedule_overrun !== 1'b0) begin
            $display("ERROR: oscillator schedule overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: fixed A4 three-member Unison scheduling");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

endmodule
