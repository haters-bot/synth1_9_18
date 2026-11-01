`timescale 1ns/1ps

// 调度器容量验证：2 个实体引擎、每个 32 个槽位，共 64 个任务。
// 8 个独立音符各分配 Unison=8，检查分配、计数和跨引擎均衡。
module tb_scheduler_unison8_capacity;
    localparam integer ENGINE_COUNT = 2;
    localparam integer SLOTS_PER_ENGINE = 32;
    localparam integer TOTAL_SLOTS = ENGINE_COUNT * SLOTS_PER_ENGINE;

    reg clk;
    reg rst_n;
    reg note_event_valid;
    reg note_event_on;
    reg [6:0] note_event_note;
    reg [6:0] note_event_velocity;
    reg [3:0] unison_count;
    reg [6:0] detune_amount;
    reg [TOTAL_SLOTS-1:0] task_idle_mask;
    wire task_update_valid;
    wire [7:0] task_update_slot;
    wire [31:0] task_update_phase_step;
    wire [6:0] task_update_velocity;
    wire task_update_enable;
    wire task_update_phase_reset;
    wire [6:0] active_task_count;
    wire scheduler_busy;

    integer errors;
    integer note_index;
    integer slot_index;
    integer update_count;
    integer count_for_note;
    integer engine_count;

    oscillator_task_scheduler #(
        .ENGINE_COUNT(ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE),
        .MAX_UNISON(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .note_event_valid(note_event_valid),
        .note_event_on(note_event_on),
        .note_event_note(note_event_note),
        .note_event_velocity(note_event_velocity),
        .unison_count(unison_count),
        .detune_amount(detune_amount),
        .task_idle_mask(task_idle_mask),
        .continuous_event_valid(1'b0),
        .continuous_event_on(1'b0),
        .continuous_event_source(3'd0),
        .continuous_event_base_step(32'd0),
        .continuous_event_velocity(7'd0),
        .task_update_valid(task_update_valid),
        .task_update_slot(task_update_slot),
        .task_update_phase_step(task_update_phase_step),
        .task_update_velocity(task_update_velocity),
        .task_update_enable(task_update_enable),
        .task_update_phase_reset(task_update_phase_reset),
        .active_task_count(active_task_count),
        .scheduler_busy(scheduler_busy)
    );

    always #10 clk = ~clk;
    always @(posedge clk)
        if (task_update_valid)
            update_count = update_count + 1;

    task send_note;
        input [6:0] note;
        begin
            while (scheduler_busy)
                @(posedge clk);
            @(negedge clk);
            note_event_on = 1'b1;
            note_event_note = note;
            note_event_velocity = 7'd127;
            unison_count = 4'd8;
            detune_amount = 7'd32;
            note_event_valid = 1'b1;
            @(negedge clk);
            note_event_valid = 1'b0;
            while (scheduler_busy)
                @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        note_event_valid = 1'b0;
        note_event_on = 1'b0;
        note_event_note = 7'd0;
        note_event_velocity = 7'd127;
        unison_count = 4'd8;
        detune_amount = 7'd32;
        task_idle_mask = {TOTAL_SLOTS{1'b0}};
        errors = 0;
        update_count = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (note_index = 0; note_index < 8; note_index = note_index + 1)
            send_note(7'd48 + note_index);

        if (active_task_count !== 7'd64) begin
            $display("ERROR: expected 64 active tasks, got %0d",
                     active_task_count);
            errors = errors + 1;
        end
        if (update_count !== 64) begin
            $display("ERROR: expected 64 updates, got %0d", update_count);
            errors = errors + 1;
        end

        for (note_index = 0; note_index < 8; note_index = note_index + 1) begin
            count_for_note = 0;
            for (slot_index = 0; slot_index < TOTAL_SLOTS; slot_index = slot_index + 1)
                if (dut.slot_active[slot_index]
                    && dut.slot_note[slot_index] == (7'd48 + note_index))
                    count_for_note = count_for_note + 1;
            if (count_for_note != 8) begin
                $display("ERROR: note %0d has %0d tasks", 48+note_index,
                         count_for_note);
                errors = errors + 1;
            end
        end

        for (engine_count = 0; engine_count < ENGINE_COUNT; engine_count = engine_count + 1) begin
            count_for_note = 0;
            for (slot_index = 0; slot_index < SLOTS_PER_ENGINE; slot_index = slot_index + 1)
                if (dut.slot_active[engine_count*SLOTS_PER_ENGINE+slot_index])
                    count_for_note = count_for_note + 1;
            if (count_for_note != SLOTS_PER_ENGINE) begin
                $display("ERROR: engine %0d has %0d tasks", engine_count,
                         count_for_note);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: 2x32 scheduler allocates 8 notes at Unison=8 (64 tasks)");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #300000;
        $display("FAIL: scheduler Unison=8 capacity test timed out");
        $finish;
    end
endmodule
