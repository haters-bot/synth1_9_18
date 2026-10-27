`timescale 1ns/1ps

module tb_pitch_modulated_core;
    reg clk;
    reg rst_n;
    reg start_tick;
    reg task_update_valid;
    reg glide_override_enable;
    reg [31:0] glide_override_base_step;
    reg signed [12:0] vibrato_ratio_delta_q16;
    wire signed [23:0] partial_sum;
    wire partial_valid;
    wire busy;
    integer errors;

    oscillator_tdm_core #(
        .SLOTS_PER_ENGINE(1),
        .PARTIAL_SUM_WIDTH(24),
        .REALTIME_DETUNE_ENABLE(1),
        .ENVELOPE_UPDATE_DIV(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start_tick(start_tick),
        .clear_phase(1'b0), .waveform_select(3'd0),
        .wt_position(7'd0), .warp_mode(4'd0), .warp_amount(7'd0),
        .attack_phase_step(32'hFFFFFFFF),
        .decay_phase_step(32'd0), .sustain_level(16'hFFFF),
        .release_phase_step(32'hFFFFFFFF),
        .external_wavetable_enable(1'b0),
        .cache_load_clk(clk), .cache_load_rst_n(rst_n),
        .cache_write_enable(1'b0), .cache_write_bank(1'b0),
        .cache_write_frame(1'b0), .cache_write_address(8'd0),
        .cache_write_data(16'd0), .cache_commit_toggle(1'b0),
        .cache_commit_bank(1'b0), .cache_commit_fraction(8'd0),
        .task_update_valid(task_update_valid), .task_update_slot(8'd0),
        .task_update_phase_step(32'd1000000),
        .task_update_base_step(32'd1000000),
        .task_update_detune_unit(35'd0),
        .task_update_detune_magnitude(3'd0),
        .task_update_detune_negative(1'b0), .detune_amount(7'd64),
        .glide_override_enable(glide_override_enable),
        .glide_override_base_step(glide_override_base_step),
        .vibrato_ratio_delta_q16(vibrato_ratio_delta_q16),
        .task_update_velocity(7'd127), .task_update_enable(1'b1),
        .task_update_phase_reset(1'b1),
        .partial_sum(partial_sum), .partial_valid(partial_valid), .busy(busy),
        .debug_slot(), .debug_slot_commit(), .schedule_overrun(),
        .task_idle_valid(), .task_idle_slot()
    );

    always #10 clk = ~clk;

    task run_batch;
        begin
            @(negedge clk);
            start_tick = 1'b1;
            @(negedge clk);
            start_tick = 1'b0;
            wait (dut.pipe_valid);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_tick = 1'b0;
        task_update_valid = 1'b0;
        glide_override_enable = 1'b0;
        glide_override_base_step = 32'd0;
        vibrato_ratio_delta_q16 = 13'sd0;
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        task_update_valid = 1'b1;
        @(negedge clk);
        task_update_valid = 1'b0;

        run_batch();
        if (dut.pipe_phase_step !== 32'd1000000) begin
            $display("ERROR: zero modulation changed base phase step");
            errors = errors + 1;
        end
        wait (!busy);

        vibrato_ratio_delta_q16 = 13'sd2048;
        run_batch();
        if (dut.pipe_phase_step !== 32'd1031250) begin
            $display("ERROR: vibrato ratio was not applied, got %0d",
                     dut.pipe_phase_step);
            errors = errors + 1;
        end
        wait (!busy);

        vibrato_ratio_delta_q16 = 13'sd0;
        glide_override_enable = 1'b1;
        glide_override_base_step = 32'd2000000;
        run_batch();
        if (dut.pipe_phase_step !== 32'd2000000) begin
            $display("ERROR: shared glide base step was not applied, got %0d",
                     dut.pipe_phase_step);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: realtime vibrato ratio and shared glide base step");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
