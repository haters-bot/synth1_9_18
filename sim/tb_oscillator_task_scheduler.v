`timescale 1ns/1ps

module tb_oscillator_task_scheduler;

    localparam integer ENGINE_COUNT = 4;
    localparam integer SLOTS_PER_ENGINE = 8;
    localparam integer TOTAL_SLOTS = 32;

    reg clk;
    reg rst_n;
    reg note_event_valid;
    reg note_event_on;
    reg [6:0] note_event_note;
    reg [6:0] note_event_velocity;
    reg [3:0] unison_count;
    reg [6:0] detune_amount;
    reg [TOTAL_SLOTS-1:0] task_idle_mask;
    reg continuous_event_valid;
    reg continuous_event_on;
    reg [2:0] continuous_event_source;
    reg [31:0] continuous_event_base_step;
    reg [6:0] continuous_event_velocity;

    wire task_update_valid;
    wire [7:0] task_update_slot;
    wire [31:0] task_update_phase_step;
    wire [6:0] task_update_velocity;
    wire task_update_enable;
    wire task_update_phase_reset;
    wire [6:0] active_task_count;
    wire scheduler_busy;

    integer errors;
    integer i;
    integer note_index;
    integer engine_index;
    integer engine_task_count;
    integer update_count;

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
        .continuous_event_valid(continuous_event_valid),
        .continuous_event_on(continuous_event_on),
        .continuous_event_source(continuous_event_source),
        .continuous_event_base_step(continuous_event_base_step),
        .continuous_event_velocity(continuous_event_velocity),
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

    always @(posedge clk) begin
        if (task_update_valid)
            update_count = update_count + 1;
    end

    task reset_dut;
        begin
            rst_n = 1'b0;
            note_event_valid = 1'b0;
            note_event_velocity = 7'd100;
            detune_amount = 7'd64;
            task_idle_mask = {TOTAL_SLOTS{1'b0}};
            continuous_event_valid = 1'b0;
            continuous_event_on = 1'b0;
            continuous_event_source = 3'd0;
            continuous_event_base_step = 32'd0;
            continuous_event_velocity = 7'd100;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_continuous;
        input event_on;
        input [2:0] source;
        input [31:0] base_step;
        input [3:0] members;
        begin
            while (scheduler_busy)
                @(posedge clk);
            @(negedge clk);
            continuous_event_on = event_on;
            continuous_event_source = source;
            continuous_event_base_step = base_step;
            continuous_event_velocity = 7'd100;
            unison_count = members;
            continuous_event_valid = 1'b1;
            @(negedge clk);
            continuous_event_valid = 1'b0;
            @(posedge clk);
            while (scheduler_busy)
                @(posedge clk);
            #1;
        end
    endtask

    task send_note;
        input event_on;
        input [6:0] note;
        input [3:0] members;
        begin
            while (scheduler_busy)
                @(posedge clk);
            @(negedge clk);
            note_event_on = event_on;
            note_event_note = note;
            unison_count = members;
            note_event_valid = 1'b1;
            @(negedge clk);
            note_event_valid = 1'b0;
            @(posedge clk);
            while (scheduler_busy)
                @(posedge clk);
            #1;
        end
    endtask

    function integer count_note;
        input [6:0] note;
        integer slot;
        begin
            count_note = 0;
            for (slot = 0; slot < TOTAL_SLOTS; slot = slot + 1)
                if (dut.slot_active[slot] && dut.slot_note[slot] == note)
                    count_note = count_note + 1;
        end
    endfunction

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        note_event_valid = 1'b0;
        note_event_on = 1'b0;
        note_event_note = 7'd0;
        unison_count = 4'd1;
        task_idle_mask = 32'd0;
        continuous_event_valid = 1'b0;
        continuous_event_on = 1'b0;
        continuous_event_source = 3'd0;
        continuous_event_base_step = 32'd0;
        continuous_event_velocity = 7'd100;
        errors = 0;
        update_count = 0;

        reset_dut();

        // 连续音高源首次触发分配4个成员，滑动时只更新step而不改变任务数。
        detune_amount = 7'd0;
        send_continuous(1'b1, 3'd2, 32'h0016534C, 4'd4);
        if (active_task_count != 7'd4) begin
            $display("ERROR: ribbon Gate On did not allocate four tasks");
            errors = errors + 1;
        end
        send_continuous(1'b1, 3'd2, 32'h00170000, 4'd4);
        if (active_task_count != 7'd4) begin
            $display("ERROR: ribbon pitch update changed task count");
            errors = errors + 1;
        end
        for (i = 0; i < TOTAL_SLOTS; i = i + 1)
            if (dut.slot_active[i] && dut.slot_continuous[i]
                && dut.slot_source[i] == 3'd2
                && dut.slot_phase_step[i] != 32'h00170000) begin
                $display("ERROR: ribbon pitch update missed task %0d", i);
                errors = errors + 1;
            end
        send_continuous(1'b0, 3'd2, 32'h00170000, 4'd4);
        for (i = 0; i < TOTAL_SLOTS; i = i + 1)
            if (dut.slot_active[i] && dut.slot_continuous[i]
                && dut.slot_source[i] == 3'd2
                && !dut.slot_releasing[i]) begin
                $display("ERROR: ribbon Gate Off missed task %0d", i);
                errors = errors + 1;
            end

        reset_dut();

        // Detune=0时，三个Unison成员必须保持完全同频。
        detune_amount = 7'd0;
        send_note(1'b1, 7'd60, 4'd3);
        if (dut.slot_phase_step[0] !== 32'h0016534C
            || dut.slot_phase_step[8] !== 32'h0016534C
            || dut.slot_phase_step[16] !== 32'h0016534C) begin
            $display("ERROR: zero detune did not keep Unison members in tune");
            errors = errors + 1;
        end

        // Detune增大后，同一音符的低、中、高成员应形成对称频差。
        reset_dut();
        detune_amount = 7'd127;
        send_note(1'b1, 7'd60, 4'd3);
        if (!(dut.slot_phase_step[0] < dut.slot_phase_step[8]
              && dut.slot_phase_step[8] < dut.slot_phase_step[16])) begin
            $display("ERROR: variable detune did not spread Unison members");
            errors = errors + 1;
        end

        reset_dut();

        // Changing Unison count retriggers/reuses the old generic task and
        // allocates the remaining ordinary tasks from the shared pool.
        note_event_velocity = 7'd37;
        send_note(1'b1, 7'd60, 4'd1);
        if (count_note(7'd60) != 1) begin
            $display("ERROR: one-member allocation failed");
            errors = errors + 1;
        end
        for (i = 0; i < TOTAL_SLOTS; i = i + 1)
            if (dut.slot_active[i] && dut.slot_note[i] == 7'd60
                && dut.slot_velocity[i] != 7'd37) begin
                $display("ERROR: MIDI velocity was not stored for task %0d", i);
                errors = errors + 1;
            end

        note_event_velocity = 7'd100;
        send_note(1'b1, 7'd60, 4'd5);
        if (count_note(7'd60) != 5) begin
            $display("ERROR: same-note resize to five tasks failed");
            errors = errors + 1;
        end

        send_note(1'b0, 7'd60, 4'd5);
        for (i = 0; i < TOTAL_SLOTS; i = i + 1) begin
            if (dut.slot_active[i] && dut.slot_note[i] == 7'd60
                && !dut.slot_releasing[i]) begin
                $display("ERROR: Note Off missed task %0d", i);
                errors = errors + 1;
            end
        end

        // Start a clean full-load test: eight four-member notes consume all
        // 32 task contexts, with each group distributed over all engines.
        reset_dut();
        update_count = 0;
        for (note_index = 0; note_index < 8;
             note_index = note_index + 1)
            send_note(1'b1, 7'd60 + note_index, 4'd4);

        if (active_task_count != 7'd32) begin
            $display("ERROR: full pool count is %0d", active_task_count);
            errors = errors + 1;
        end

        for (engine_index = 0; engine_index < ENGINE_COUNT;
             engine_index = engine_index + 1) begin
            engine_task_count = 0;
            for (i = 0; i < SLOTS_PER_ENGINE; i = i + 1)
                if (dut.slot_active[engine_index*SLOTS_PER_ENGINE+i])
                    engine_task_count = engine_task_count + 1;
            if (engine_task_count != SLOTS_PER_ENGINE) begin
                $display("ERROR: engine %0d has %0d tasks",
                         engine_index, engine_task_count);
                errors = errors + 1;
            end
        end

        // With no free task, the scheduler replaces one complete old note.
        // Three contexts become note 72 and the fourth enters Release.
        send_note(1'b1, 7'd72, 4'd3);
        if (count_note(7'd72) != 3) begin
            $display("ERROR: full-pool note replacement failed");
            errors = errors + 1;
        end
        if (count_note(7'd60) != 1) begin
            $display("ERROR: victim group was not replaced as a group");
            errors = errors + 1;
        end
        for (i = 0; i < TOTAL_SLOTS; i = i + 1)
            if (dut.slot_active[i] && dut.slot_note[i] == 7'd60
                && !dut.slot_releasing[i]) begin
                $display("ERROR: unused victim task did not enter Release");
                errors = errors + 1;
            end

        if (update_count != 36) begin
            $display("ERROR: expected 36 full-load updates, got %0d",
                     update_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: variable Unison, balanced full load, and group stealing");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: oscillator task scheduler test timed out");
        $finish;
    end

endmodule
