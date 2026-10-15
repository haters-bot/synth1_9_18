`timescale 1ns/1ps

module tb_adsr_control;

    reg clk;
    reg rst_n;
    reg start_tick;
    reg task_update_valid;
    reg task_update_enable;
    reg [6:0] attack_control;
    reg [6:0] decay_control;
    reg [6:0] sustain_control;
    reg [6:0] release_control;
    wire [31:0] mapped_attack_step;
    wire [31:0] mapped_decay_step;
    wire [15:0] mapped_sustain_level;
    wire [31:0] mapped_release_step;
    wire signed [23:0] partial_sum;
    wire partial_valid;
    wire busy;
    wire task_idle_valid;
    integer errors;

    adsr_parameter_mapper mapper (
        .attack_control(attack_control),
        .decay_control(decay_control),
        .sustain_control(sustain_control),
        .release_control(release_control),
        .attack_phase_step(mapped_attack_step),
        .decay_phase_step(mapped_decay_step),
        .sustain_level(mapped_sustain_level),
        .release_phase_step(mapped_release_step)
    );

    oscillator_tdm_core #(
        .SLOTS_PER_ENGINE(1),
        .PARTIAL_SUM_WIDTH(24),
        .ENVELOPE_UPDATE_DIV(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_tick(start_tick),
        .clear_phase(1'b0),
        .waveform_select(3'd2),
        .wt_position(7'd0),
        .warp_mode(4'd0),
        .warp_amount(7'd0),
        .attack_phase_step(32'hFFFFFFFF),
        .decay_phase_step(32'hFFFFFFFF),
        .sustain_level(16'd0),
        .release_phase_step(32'hFFFFFFFF),
        .task_update_valid(task_update_valid),
        .task_update_slot(8'd0),
        .task_update_phase_step(32'h01000000),
        .task_update_velocity(7'd127),
        .task_update_enable(task_update_enable),
        .task_update_phase_reset(1'b1),
        .partial_sum(partial_sum),
        .partial_valid(partial_valid),
        .busy(busy),
        .debug_slot(),
        .debug_slot_commit(),
        .schedule_overrun(),
        .task_idle_valid(task_idle_valid),
        .task_idle_slot()
    );

    always #10 clk = ~clk;

    task update_gate;
        input enable_value;
        begin
            @(negedge clk);
            task_update_enable = enable_value;
            task_update_valid = 1'b1;
            @(negedge clk);
            task_update_valid = 1'b0;
        end
    endtask

    task run_envelope_sample;
        begin
            @(negedge clk);
            start_tick = 1'b1;
            @(negedge clk);
            start_tick = 1'b0;
            wait (partial_valid);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_tick = 1'b0;
        task_update_valid = 1'b0;
        task_update_enable = 1'b0;
        attack_control = 7'd27;
        decay_control = 7'd54;
        sustain_control = 7'd89;
        release_control = 7'd67;
        errors = 0;

        #1;
        if (mapped_attack_step !== 32'd9087659
            || mapped_decay_step !== 32'd873814
            || mapped_sustain_level !== 16'd45924
            || mapped_release_step !== 32'd283990) begin
            $display("ERROR: default ADSR control mapping is incorrect");
            errors = errors + 1;
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        update_gate(1'b1);
        run_envelope_sample();
        if (dut.envelope_stage[0] !== 3'd2
            || dut.envelope_level[0] !== 16'hFFFF) begin
            $display("ERROR: Attack did not reach Decay at full level");
            errors = errors + 1;
        end

        run_envelope_sample();
        if (dut.envelope_stage[0] !== 3'd3
            || dut.envelope_level[0] !== 16'd0
            || dut.gate_state[0] !== 1'b1
            || dut.enable_state[0] !== 1'b1) begin
            $display("ERROR: zero Sustain did not become silent while gate stayed active");
            errors = errors + 1;
        end

        update_gate(1'b0);
        run_envelope_sample();
        if (dut.envelope_stage[0] !== 3'd0
            || dut.enable_state[0] !== 1'b0
            || !task_idle_valid) begin
            $display("ERROR: Release did not return the slot to IDLE");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: ADSR mapping, zero Sustain, and Release behavior");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
