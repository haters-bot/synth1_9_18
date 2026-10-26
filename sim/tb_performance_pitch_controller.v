`timescale 1ns/1ps

module tb_performance_pitch_controller;
    reg clk;
    reg rst_n;
    reg sample_tick;
    reg note_event_valid;
    reg note_event_on;
    reg [6:0] note_event_note;
    reg [6:0] note_event_velocity;
    reg vibrato_enable;
    reg [6:0] vibrato_rate;
    reg [6:0] vibrato_depth;
    reg portamento_enable;
    reg [6:0] portamento_time;

    wire routed_note_event_valid;
    wire routed_note_event_on;
    wire [6:0] routed_note_event_note;
    wire [6:0] routed_note_event_velocity;
    wire glide_override_enable;
    wire [31:0] glide_base_step;
    wire signed [12:0] vibrato_ratio_delta_q16;
    wire [23:0] debug_current_pitch_q16;
    wire [23:0] debug_target_pitch_q16;

    integer errors;
    integer routed_on_count;
    integer routed_off_count;
    integer positive_vibrato_seen;
    integer negative_vibrato_seen;
    integer tick_index;
    reg [6:0] last_routed_note;

    performance_pitch_controller dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .note_event_valid(note_event_valid),
        .note_event_on(note_event_on),
        .note_event_note(note_event_note),
        .note_event_velocity(note_event_velocity),
        .vibrato_enable(vibrato_enable),
        .vibrato_rate(vibrato_rate),
        .vibrato_depth(vibrato_depth),
        .portamento_enable(portamento_enable),
        .portamento_time(portamento_time),
        .routed_note_event_valid(routed_note_event_valid),
        .routed_note_event_on(routed_note_event_on),
        .routed_note_event_note(routed_note_event_note),
        .routed_note_event_velocity(routed_note_event_velocity),
        .glide_override_enable(glide_override_enable),
        .glide_base_step(glide_base_step),
        .vibrato_ratio_delta_q16(vibrato_ratio_delta_q16),
        .debug_current_pitch_q16(debug_current_pitch_q16),
        .debug_target_pitch_q16(debug_target_pitch_q16)
    );

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (routed_note_event_valid) begin
            last_routed_note = routed_note_event_note;
            if (routed_note_event_on)
                routed_on_count = routed_on_count + 1;
            else
                routed_off_count = routed_off_count + 1;
        end
        if (vibrato_ratio_delta_q16 > 0)
            positive_vibrato_seen = 1;
        if (vibrato_ratio_delta_q16 < 0)
            negative_vibrato_seen = 1;
    end

    task send_note;
        input event_on;
        input [6:0] note;
        begin
            @(negedge clk);
            note_event_valid = 1'b1;
            note_event_on = event_on;
            note_event_note = note;
            note_event_velocity = event_on ? 7'd100 : 7'd0;
            @(negedge clk);
            note_event_valid = 1'b0;
        end
    endtask

    task pulse_sample_tick;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_tick = 1'b0;
        note_event_valid = 1'b0;
        note_event_on = 1'b0;
        note_event_note = 7'd0;
        note_event_velocity = 7'd0;
        vibrato_enable = 1'b0;
        vibrato_rate = 7'd52;
        vibrato_depth = 7'd0;
        portamento_enable = 1'b1;
        portamento_time = 7'd48;
        errors = 0;
        routed_on_count = 0;
        routed_off_count = 0;
        positive_vibrato_seen = 0;
        negative_vibrato_seen = 0;
        last_routed_note = 7'd0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        send_note(1'b1, 7'd60);
        repeat (5) @(posedge clk);
        if (routed_on_count != 1 || !glide_override_enable
            || debug_current_pitch_q16 != {7'd60, 16'd0}) begin
            $display("ERROR: first mono note did not start directly");
            errors = errors + 1;
        end

        send_note(1'b1, 7'd64);
        repeat (5) @(posedge clk);
        if (routed_on_count != 1
            || debug_target_pitch_q16 != {7'd64, 16'd0}) begin
            $display("ERROR: legato note retriggered or target was not updated");
            errors = errors + 1;
        end

        for (tick_index = 0; tick_index < 100; tick_index = tick_index + 1)
            pulse_sample_tick();
        if (debug_current_pitch_q16 <= {7'd60, 16'd0}
            || debug_current_pitch_q16 >= {7'd64, 16'd0}) begin
            $display("ERROR: glide did not move smoothly between notes");
            errors = errors + 1;
        end

        for (tick_index = 0; tick_index < 1700; tick_index = tick_index + 1)
            pulse_sample_tick();
        if (debug_current_pitch_q16 != {7'd64, 16'd0}) begin
            $display("ERROR: glide did not reach target note");
            errors = errors + 1;
        end

        send_note(1'b0, 7'd64);
        repeat (5) @(posedge clk);
        if (routed_off_count != 0
            || debug_target_pitch_q16 != {7'd60, 16'd0}) begin
            $display("ERROR: releasing top note did not return to held note");
            errors = errors + 1;
        end

        send_note(1'b0, 7'd60);
        repeat (5) @(posedge clk);
        if (routed_off_count != 1 || last_routed_note != 7'd60) begin
            $display("ERROR: final release did not emit owner Note Off");
            errors = errors + 1;
        end

        // Vibrato使用完整正弦周期，必须出现正、负两侧的比例偏移。
        vibrato_enable = 1'b1;
        vibrato_rate = 7'd127;
        vibrato_depth = 7'd127;
        for (tick_index = 0; tick_index < 9000; tick_index = tick_index + 1)
            pulse_sample_tick();
        if (!positive_vibrato_seen || !negative_vibrato_seen) begin
            $display("ERROR: sine vibrato did not visit both polarities");
            errors = errors + 1;
        end

        // 关闭Portamento后恢复原始复音Note事件直通。
        portamento_enable = 1'b0;
        repeat (3) @(posedge clk);
        send_note(1'b1, 7'd67);
        repeat (3) @(posedge clk);
        if (routed_on_count != 2 || last_routed_note != 7'd67) begin
            $display("ERROR: polyphonic pass-through was not restored");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: vibrato and mono legato portamento controller");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
