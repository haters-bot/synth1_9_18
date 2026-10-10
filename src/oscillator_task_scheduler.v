// Global note-to-oscillator task scheduler.
//
// Unison is an allocation policy only. Every generated task is an ordinary
// oscillator context containing a phase step and note ownership metadata.
// The physical oscillator engines do not know whether a task belongs to a
// Unison group.
module oscillator_task_scheduler #(
    parameter integer ENGINE_COUNT     = 4,
    parameter integer SLOTS_PER_ENGINE = 8,
    parameter integer MAX_UNISON       = 8,
    parameter [6:0] MIN_NOTE           = 7'd21,
    parameter [6:0] MAX_NOTE           = 7'd108
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       note_event_valid,
    input  wire       note_event_on,
    input  wire [6:0] note_event_note,
    input  wire [6:0] note_event_velocity,
    input  wire [3:0] unison_count,
    input  wire [6:0] detune_amount,
    input  wire [(ENGINE_COUNT*SLOTS_PER_ENGINE)-1:0] task_idle_mask,

    output reg        task_update_valid,
    output reg [7:0]  task_update_slot,
    output reg [31:0] task_update_phase_step,
    output reg [6:0]  task_update_velocity,
    output reg        task_update_enable,
    output reg        task_update_phase_reset,
    output reg [5:0]  active_task_count,
    output reg        scheduler_busy
);

    localparam integer TOTAL_SLOTS = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_ALLOCATE     = 3'd1;
    localparam [2:0] STATE_REPLACE_NOTE = 3'd2;
    localparam [2:0] STATE_RELEASE_NOTE = 3'd3;

    reg [2:0] state;
    reg [6:0] slot_note [0:TOTAL_SLOTS-1];
    reg [31:0] slot_phase_step [0:TOTAL_SLOTS-1];
    reg [6:0] slot_velocity [0:TOTAL_SLOTS-1];
    reg slot_active [0:TOTAL_SLOTS-1];
    reg slot_releasing [0:TOTAL_SLOTS-1];

    reg [6:0] pending_note;
    reg [6:0] pending_velocity;
    reg [3:0] pending_unison_count;
    reg [6:0] pending_detune_amount;
    reg [3:0] pending_member_index;
    reg [6:0] victim_note;
    reg [5:0] scan_index;
    reg [5:0] scan_count;
    reg [5:0] allocation_cursor;

    wire [31:0] pending_base_phase_step;
    wire [7:0] allocation_candidate;

    reg matching_note_found;
    reg steal_note_found;
    reg [6:0] steal_note;
    integer search_index;
    integer reset_index;

    freq_lut u_scheduler_freq_lut (
        .addr(pending_note),
        .data(pending_base_phase_step)
    );

    // Convert round-robin task order into engine-major global slot numbering.
    // For 4x8, the order is 0,8,16,24,1,9,17,25,... so adjacent Unison
    // members are spread across physical engines before an engine gets a
    // second task.
    function [7:0] balanced_slot;
        input [5:0] order_index;
        integer engine_number;
        integer local_slot_number;
        begin
            engine_number = order_index % ENGINE_COUNT;
            local_slot_number = order_index / ENGINE_COUNT;
            balanced_slot = engine_number*SLOTS_PER_ENGINE
                          + local_slot_number;
        end
    endfunction

    function [3:0] clamp_unison_count;
        input [3:0] requested_count;
        begin
            if (requested_count < 4'd1)
                clamp_unison_count = 4'd1;
            else if (requested_count > MAX_UNISON)
                clamp_unison_count = MAX_UNISON;
            else
                clamp_unison_count = requested_count;
        end
    endfunction

    function [34:0] scale_detune_unit;
        input [31:0] detune_unit;
        input integer magnitude;
        begin
            case (magnitude)
                0: scale_detune_unit = 35'd0;
                1: scale_detune_unit = detune_unit;
                2: scale_detune_unit = detune_unit << 1;
                3: scale_detune_unit = detune_unit
                                            + (detune_unit << 1);
                4: scale_detune_unit = detune_unit << 2;
                5: scale_detune_unit = detune_unit
                                            + (detune_unit << 2);
                6: scale_detune_unit = (detune_unit << 1)
                                            + (detune_unit << 2);
                default: scale_detune_unit = detune_unit
                                            + (detune_unit << 1)
                                            + (detune_unit << 2);
            endcase
        end
    endfunction

    // 围绕目标音高对称展开Unison。detune_amount=64保持旧版本间距：
    // 每个position约2.006 cents；0使全部成员同频，127约为旧间距的两倍。
    function [31:0] make_phase_step;
        input [31:0] base_step;
        input [3:0] member_index;
        input [3:0] member_count;
        input [6:0] requested_detune;
        integer position;
        integer magnitude;
        reg [31:0] detune_unit;
        reg [34:0] detune_delta;
        reg [41:0] detune_product;
        begin
            position = member_index*2 - (member_count - 1);
            magnitude = (position < 0) ? -position : position;
            detune_unit = (base_step >> 10)
                         + (base_step >> 13)
                         + (base_step >> 14);
            detune_delta = scale_detune_unit(detune_unit, magnitude);
            detune_product = detune_delta * requested_detune;
            detune_delta = (detune_product + 42'd32) >> 6;

            if (position < 0)
                make_phase_step = base_step - detune_delta[31:0];
            else
                make_phase_step = base_step + detune_delta[31:0];
        end
    endfunction

    assign allocation_candidate = balanced_slot(scan_index);

    always @(*) begin
        matching_note_found = 1'b0;
        steal_note_found = 1'b0;
        steal_note = 7'd0;
        active_task_count = 6'd0;

        for (search_index = 0;
             search_index < TOTAL_SLOTS;
             search_index = search_index + 1) begin
            if (slot_active[search_index]) begin
                active_task_count = active_task_count + 6'd1;

                if (slot_note[search_index] == note_event_note)
                    matching_note_found = 1'b1;

                // Never choose a task that already belongs to the new note;
                // this prevents repeated partial steals when resources are
                // completely occupied.
                if (!steal_note_found
                    && (slot_note[search_index] != pending_note)) begin
                    steal_note_found = 1'b1;
                    steal_note = slot_note[search_index];
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            scheduler_busy <= 1'b0;
            task_update_valid <= 1'b0;
            task_update_slot <= 8'd0;
            task_update_phase_step <= 32'd0;
            task_update_velocity <= 7'd0;
            task_update_enable <= 1'b0;
            task_update_phase_reset <= 1'b0;
            pending_note <= 7'd0;
            pending_velocity <= 7'd0;
            pending_unison_count <= 4'd1;
            pending_detune_amount <= 7'd64;
            pending_member_index <= 4'd0;
            victim_note <= 7'd0;
            scan_index <= 6'd0;
            scan_count <= 6'd0;
            allocation_cursor <= 6'd0;

            for (reset_index = 0;
                 reset_index < TOTAL_SLOTS;
                 reset_index = reset_index + 1) begin
                slot_note[reset_index] <= 7'd0;
                slot_phase_step[reset_index] <= 32'd0;
                slot_velocity[reset_index] <= 7'd0;
                slot_active[reset_index] <= 1'b0;
                slot_releasing[reset_index] <= 1'b0;
            end
        end else begin
            task_update_valid <= 1'b0;

            // Release completion is reported independently by every physical
            // engine. A task remains part of normalization until its ADSR has
            // actually reached idle.
            for (reset_index = 0;
                 reset_index < TOTAL_SLOTS;
                 reset_index = reset_index + 1) begin
                if (task_idle_mask[reset_index]
                    && slot_releasing[reset_index]) begin
                    slot_active[reset_index] <= 1'b0;
                    slot_releasing[reset_index] <= 1'b0;
                end
            end

            case (state)
                STATE_IDLE: begin
                    scheduler_busy <= 1'b0;

                    if (note_event_valid
                        && (note_event_note >= MIN_NOTE)
                        && (note_event_note <= MAX_NOTE)) begin
                        pending_note <= note_event_note;
                        pending_velocity <= note_event_velocity;
                        pending_unison_count
                            <= clamp_unison_count(unison_count);
                        pending_detune_amount <= detune_amount;
                        pending_member_index <= 4'd0;
                        scan_index <= 6'd0;
                        scan_count <= 6'd0;
                        scheduler_busy <= 1'b1;

                        if (note_event_on) begin
                            if (matching_note_found) begin
                                victim_note <= note_event_note;
                                state <= STATE_REPLACE_NOTE;
                            end else begin
                                scan_index <= allocation_cursor;
                                scan_count <= 6'd0;
                                state <= STATE_ALLOCATE;
                            end
                        end else if (matching_note_found) begin
                            victim_note <= note_event_note;
                            state <= STATE_RELEASE_NOTE;
                        end else begin
                            scheduler_busy <= 1'b0;
                        end
                    end
                end

                STATE_ALLOCATE: begin
                    if (!slot_active[allocation_candidate]) begin
                        task_update_valid <= 1'b1;
                        task_update_slot <= allocation_candidate;
                        task_update_phase_step
                            <= make_phase_step(pending_base_phase_step,
                                               pending_member_index,
                                               pending_unison_count,
                                               pending_detune_amount);
                        task_update_velocity <= pending_velocity;
                        task_update_enable <= 1'b1;
                        task_update_phase_reset <= 1'b1;

                        slot_note[allocation_candidate] <= pending_note;
                        slot_phase_step[allocation_candidate]
                            <= make_phase_step(pending_base_phase_step,
                                               pending_member_index,
                                               pending_unison_count,
                                               pending_detune_amount);
                        slot_velocity[allocation_candidate]
                            <= pending_velocity;
                        slot_active[allocation_candidate] <= 1'b1;
                        slot_releasing[allocation_candidate] <= 1'b0;

                        if (scan_index == TOTAL_SLOTS-1)
                            allocation_cursor <= 6'd0;
                        else
                            allocation_cursor <= scan_index + 6'd1;

                        if (pending_member_index
                            == pending_unison_count-1) begin
                            state <= STATE_IDLE;
                            scheduler_busy <= 1'b0;
                        end else begin
                            pending_member_index
                                <= pending_member_index + 4'd1;
                            scan_index <= (scan_index == TOTAL_SLOTS-1)
                                        ? 6'd0 : scan_index + 6'd1;
                            scan_count <= 6'd0;
                        end
                    end else if (scan_count == TOTAL_SLOTS-1) begin
                        if (steal_note_found) begin
                            victim_note <= steal_note;
                            scan_index <= 6'd0;
                            scan_count <= 6'd0;
                            state <= STATE_REPLACE_NOTE;
                        end else begin
                            state <= STATE_IDLE;
                            scheduler_busy <= 1'b0;
                        end
                    end else begin
                        scan_index <= (scan_index == TOTAL_SLOTS-1)
                                    ? 6'd0 : scan_index + 6'd1;
                        scan_count <= scan_count + 6'd1;
                    end
                end

                STATE_REPLACE_NOTE: begin
                    if (slot_active[scan_index]
                        && (slot_note[scan_index] == victim_note)) begin
                        task_update_valid <= 1'b1;
                        task_update_slot <= scan_index;

                        if (pending_member_index
                            < pending_unison_count) begin
                            task_update_phase_step
                                <= make_phase_step(pending_base_phase_step,
                                                   pending_member_index,
                                                   pending_unison_count,
                                                   pending_detune_amount);
                            task_update_velocity <= pending_velocity;
                            task_update_enable <= 1'b1;
                            task_update_phase_reset <= 1'b1;
                            slot_note[scan_index] <= pending_note;
                            slot_phase_step[scan_index]
                                <= make_phase_step(pending_base_phase_step,
                                                   pending_member_index,
                                                   pending_unison_count,
                                                   pending_detune_amount);
                            slot_velocity[scan_index] <= pending_velocity;
                            slot_releasing[scan_index] <= 1'b0;
                            pending_member_index
                                <= pending_member_index + 4'd1;
                        end else begin
                            task_update_phase_step
                                <= slot_phase_step[scan_index];
                            task_update_velocity <= slot_velocity[scan_index];
                            task_update_enable <= 1'b0;
                            task_update_phase_reset <= 1'b0;
                            slot_releasing[scan_index] <= 1'b1;
                        end
                    end

                    if (scan_index == TOTAL_SLOTS-1) begin
                        if ((slot_active[scan_index]
                             && (slot_note[scan_index] == victim_note)
                             && (pending_member_index
                                 < pending_unison_count)
                             && (pending_member_index + 4'd1
                                 >= pending_unison_count))
                            || (pending_member_index
                                >= pending_unison_count)) begin
                            state <= STATE_IDLE;
                            scheduler_busy <= 1'b0;
                        end else begin
                            scan_index <= allocation_cursor;
                            scan_count <= 6'd0;
                            state <= STATE_ALLOCATE;
                        end
                    end else begin
                        scan_index <= scan_index + 6'd1;
                    end
                end

                STATE_RELEASE_NOTE: begin
                    if (slot_active[scan_index]
                        && (slot_note[scan_index] == victim_note)) begin
                        task_update_valid <= 1'b1;
                        task_update_slot <= scan_index;
                        task_update_phase_step <= slot_phase_step[scan_index];
                        task_update_velocity <= slot_velocity[scan_index];
                        task_update_enable <= 1'b0;
                        task_update_phase_reset <= 1'b0;
                        slot_releasing[scan_index] <= 1'b1;
                    end

                    if (scan_index == TOTAL_SLOTS-1) begin
                        state <= STATE_IDLE;
                        scheduler_busy <= 1'b0;
                    end else begin
                        scan_index <= scan_index + 6'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    scheduler_busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
