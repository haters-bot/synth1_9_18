`timescale 1ns/1ps

module tb_unison_scheduler_load;

    localparam integer TOTAL_SLOTS = 32;
    localparam integer UNISON_COUNT = 3;
    localparam integer TICK_PERIOD_CLOCKS = 65;

    reg clk;
    reg rst_n;
    reg start_tick;
    reg [6:0] tick_counter;
    reg note_event_valid;
    reg note_event_on;
    reg [6:0] note_event_note;

    wire voice_update_valid;
    wire [7:0] voice_update_slot;
    wire [6:0] voice_update_note;
    wire voice_update_enable;
    wire voice_update_phase_reset;
    wire [1:0] voice_update_unison_lane;
    wire [5:0] active_voice_count;
    wire [TOTAL_SLOTS-1:0] voice_idle_mask;
    wire signed [15:0] sample_out;
    wire sample_valid;
    wire schedule_overrun;

    integer errors;
    integer note_index;
    integer slot_index;
    integer sample_count;

    midi_voice_allocator #(
        .VOICE_COUNT (TOTAL_SLOTS),
        .UNISON_COUNT(UNISON_COUNT)
    ) allocator (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .note_event_valid        (note_event_valid),
        .note_event_on           (note_event_on),
        .note_event_note         (note_event_note),
        .voice_idle_mask         (voice_idle_mask),
        .voice_update_valid      (voice_update_valid),
        .voice_update_slot       (voice_update_slot),
        .voice_update_note       (voice_update_note),
        .voice_update_enable     (voice_update_enable),
        .voice_update_phase_reset(voice_update_phase_reset),
        .voice_update_unison_lane(voice_update_unison_lane),
        .active_voice_count      (active_voice_count)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT       (1),
        .SLOTS_PER_ENGINE   (TOTAL_SLOTS),
        .ENVELOPE_UPDATE_DIV(1),
        .ATTACK_STEP        (16'hFFFF),
        .DECAY_STEP         (16'hFFFF),
        .SUSTAIN_LEVEL      (16'h8000),
        .RELEASE_SHIFT      (11),
        .RELEASE_END_LEVEL  (16'hFFFF)
    ) oscillator_bank (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .start_tick                (start_tick),
        .clear_phase               (1'b0),
        .voice_update_valid        (voice_update_valid),
        .voice_update_slot         (voice_update_slot),
        .voice_update_note         (voice_update_note),
        .voice_update_enable       (voice_update_enable),
        .voice_update_phase_reset  (voice_update_phase_reset),
        .voice_update_unison_lane  (voice_update_unison_lane),
        .active_voice_count        (active_voice_count),
        .sample_out                (sample_out),
        .sample_valid              (sample_valid),
        .schedule_overrun          (schedule_overrun),
        .voice_idle_mask           (voice_idle_mask),
        .debug_engine0_busy        (),
        .debug_engine0_slot        (),
        .debug_engine0_slot_commit ()
    );

    always #10 clk = ~clk;

    // Real board request spacing: approximately 65 clocks at 50 MHz for each
    // 768 kHz internal audio sample.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter <= 7'd0;
            start_tick <= 1'b0;
        end else if (tick_counter == TICK_PERIOD_CLOCKS-1) begin
            tick_counter <= 7'd0;
            start_tick <= 1'b1;
        end else begin
            tick_counter <= tick_counter + 7'd1;
            start_tick <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (sample_valid)
            sample_count = sample_count + 1;
    end

    task send_note_event;
        input event_on;
        input [6:0] event_note;
        begin
            @(negedge clk);
            note_event_valid = 1'b1;
            note_event_on = event_on;
            note_event_note = event_note;
            @(negedge clk);
            note_event_valid = 1'b0;
            // Allow the two queued lanes to follow lane zero.
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_tick = 1'b0;
        tick_counter = 7'd0;
        note_event_valid = 1'b0;
        note_event_on = 1'b0;
        note_event_note = 7'd0;
        errors = 0;
        sample_count = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Ten MIDI notes occupy thirty physical oscillator slots.
        for (note_index = 0; note_index < 10; note_index = note_index + 1)
            send_note_event(1'b1, 7'd60 + note_index);

        #1;
        if (active_voice_count !== 6'd30) begin
            $display("ERROR: ten Unison groups reported %0d active slots",
                     active_voice_count);
            errors = errors + 1;
        end

        for (slot_index = 0; slot_index < 30; slot_index = slot_index + 1) begin
            if (!oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                    .enable_state[slot_index]) begin
                $display("ERROR: active Unison slot %0d is disabled", slot_index);
                errors = errors + 1;
            end

            if (oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                    .unison_lane_state[slot_index] !== (slot_index % 3)) begin
                $display("ERROR: slot %0d has wrong Unison lane", slot_index);
                errors = errors + 1;
            end
        end

        if (oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                .enable_state[30]
            || oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                .enable_state[31]) begin
            $display("ERROR: reserved slots 30 or 31 were allocated");
            errors = errors + 1;
        end

        // Run long enough to exercise repeated full 32-slot schedules.
        repeat (TICK_PERIOD_CLOCKS * 20) @(posedge clk);

        if (sample_count < 15 || schedule_overrun) begin
            $display("ERROR: loaded scheduler samples=%0d overrun=%0d",
                     sample_count, schedule_overrun);
            errors = errors + 1;
        end

        // An eleventh note steals logical group zero as one atomic group.
        send_note_event(1'b1, 7'd72);
        if (allocator.group_note[0] !== 7'd72
            || oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                .note_state[0] !== 7'd72
            || oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                .note_state[1] !== 7'd72
            || oscillator_bank.GEN_ENGINE[0].u_oscillator_tdm_core
                .note_state[2] !== 7'd72) begin
            $display("ERROR: group stealing did not replace all three lanes");
            errors = errors + 1;
        end

        // Release group five and wait for its final lane to report idle.
        send_note_event(1'b0, 7'd65);
        repeat (TICK_PERIOD_CLOCKS * 3) @(posedge clk);

        if (allocator.group_active[5] !== 1'b0
            || active_voice_count !== 6'd27) begin
            $display("ERROR: group Release count=%0d group_active=%0d",
                     active_voice_count, allocator.group_active[5]);
            errors = errors + 1;
        end

        if (schedule_overrun) begin
            $display("ERROR: scheduler overrun under 30-oscillator load");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: 3-Unison allocation, stealing, Release, and load");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: Unison scheduler load test timed out");
        $finish;
    end

endmodule
