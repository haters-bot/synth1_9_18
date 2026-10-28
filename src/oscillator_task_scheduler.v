// Global note-to-oscillator task scheduler.
//
// Unison is an allocation policy only. Every generated task is an ordinary
// oscillator context containing a phase step and note ownership metadata.
// The physical oscillator engines do not know whether a task belongs to a
// Unison group.
module oscillator_task_scheduler #(
    parameter integer INITIAL_PHASE_ENABLE = 0,
    parameter [31:0] RANDOM_SEED = 32'h6D2B79F5,
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
    input wire [6:0] phase_control, rand_control,
    input  wire [(ENGINE_COUNT*SLOTS_PER_ENGINE)-1:0] task_idle_mask,

    output reg        task_update_valid,
    output reg [7:0]  task_update_slot,
    output reg [31:0] task_update_phase_step,
    output reg [31:0] task_update_base_step,
    output reg [34:0] task_update_detune_unit,
    output reg [2:0] task_update_detune_magnitude,
    output reg task_update_detune_negative,
    output reg [6:0]  task_update_velocity,
    output reg        task_update_enable,
    output reg        task_update_phase_reset,
    output reg [31:0] task_update_initial_phase,
    // 8 个复音各使用 8 个 Unison 成员时共有 64 个任务，6 位无法表示 64。
    output reg [6:0]  active_task_count,
    output reg        scheduler_busy
);

    localparam integer TOTAL_SLOTS = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_ALLOCATE     = 3'd1;
    localparam [2:0] STATE_REPLACE_NOTE = 3'd2;
    localparam [2:0] STATE_RELEASE_NOTE = 3'd3;
    localparam [2:0] STATE_LATCH_STEP   = 3'd4;
    localparam [2:0] STATE_DETUNE_PREP  = 3'd5;
    localparam [2:0] STATE_DETUNE_MULT  = 3'd6;
    localparam [2:0] STATE_DETUNE_STORE = 3'd7;

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
    // 触发时锁存参数；每个Unison成员计算独立随机相位，不额外占用音频TDM拍数。
    reg [6:0] pending_phase_control, pending_rand_control;
    reg [31:0] random_state;
    reg [39:0] random_product_stage;
    reg [31:0] pending_member_initial_phase [0:MAX_UNISON-1];
    wire [7:0] random_scale = pending_rand_control==7'd127
        ? 8'd128 : {1'b0,pending_rand_control};
    function [31:0] next_random;
        input [31:0] value;
        reg [31:0] x;
        begin x=value^(value<<13); x=x^(x>>17); next_random=x^(x<<5); end
    endfunction
    reg [3:0] pending_member_index;
    reg [6:0] victim_note;
    reg [5:0] scan_index;
    reg [5:0] scan_count;
    reg [5:0] allocation_cursor;
    reg [2:0] state_after_latch;
    reg [31:0] pending_base_phase_step_latched;
    reg [34:0] pending_member_detune_unit [0:MAX_UNISON-1];
    reg [2:0] pending_member_detune_magnitude [0:MAX_UNISON-1];
    reg pending_member_detune_negative [0:MAX_UNISON-1];
    reg [31:0] pending_member_phase_step [0:MAX_UNISON-1];
    reg [3:0] phase_calc_index;
    reg [34:0] detune_delta_stage;
    reg [31:0] detune_base_stage;
    reg        detune_negative_stage;
    reg [41:0] detune_product_stage;
    reg [31:0] detune_base_product_stage;
    reg        detune_negative_product_stage;

    wire [31:0] pending_base_phase_step;
    wire [7:0] allocation_candidate;
    wire [41:0] rounded_detune_product;
    wire [31:0] rounded_detune_delta;
    wire [31:0] calculated_phase_step;

    reg matching_note_found;
    reg steal_note_found;
    reg [6:0] steal_note;
    reg [6:0] retired_task_count;
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

    // 只计算Detune乘法之前的偏移量，乘法和最终加减由后续流水级完成。
    function [34:0] make_detune_delta;
        input [31:0] base_step;
        input [3:0] member_index;
        input [3:0] member_count;
        integer position;
        integer magnitude;
        reg [31:0] detune_unit;
        begin
            position = member_index*2 - (member_count - 1);
            magnitude = (position < 0) ? -position : position;
            detune_unit = (base_step >> 10)
                         + (base_step >> 13)
                         + (base_step >> 14);
            make_detune_delta
                = scale_detune_unit(detune_unit, magnitude);
        end
    endfunction

    function [2:0] make_detune_magnitude;
        input [3:0] member_index;
        input [3:0] member_count;
        integer position;
        integer magnitude;
        begin
            position = member_index*2 - (member_count - 1);
            magnitude = (position < 0) ? -position : position;
            make_detune_magnitude = magnitude[2:0];
        end
    endfunction

    assign allocation_candidate = balanced_slot(scan_index);
    assign rounded_detune_product = detune_product_stage + 42'd32;
    assign rounded_detune_delta = rounded_detune_product[37:6];
    assign calculated_phase_step
        = detune_negative_product_stage
            ? detune_base_product_stage - rounded_detune_delta
            : detune_base_product_stage + rounded_detune_delta;

    always @(*) begin
        matching_note_found = 1'b0;
        steal_note_found = 1'b0;
        steal_note = 7'd0;
        retired_task_count = 7'd0;

        for (search_index = 0;
             search_index < TOTAL_SLOTS;
             search_index = search_index + 1) begin
            if (task_idle_mask[search_index]
                && slot_releasing[search_index])
                retired_task_count = retired_task_count + 7'd1;

            if (slot_active[search_index]) begin
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
            task_update_base_step <= 0; task_update_detune_unit <= 0;
            task_update_detune_magnitude <= 3'd0;
            task_update_detune_negative <= 0;
            task_update_velocity <= 7'd0;
            task_update_enable <= 1'b0;
            task_update_phase_reset <= 1'b0;
            task_update_initial_phase<=0; pending_phase_control<=0; pending_rand_control<=0;
            random_product_stage<=0; random_state<=RANDOM_SEED==0 ? 32'd1 : RANDOM_SEED;
            pending_note <= 7'd0;
            pending_velocity <= 7'd0;
            pending_unison_count <= 4'd1;
            pending_detune_amount <= 7'd64;
            pending_member_index <= 4'd0;
            victim_note <= 7'd0;
            scan_index <= 6'd0;
            scan_count <= 6'd0;
            allocation_cursor <= 6'd0;
            state_after_latch <= STATE_IDLE;
            pending_base_phase_step_latched <= 32'd0;
            phase_calc_index <= 4'd0;
            detune_delta_stage <= 35'd0;
            detune_base_stage <= 32'd0;
            detune_negative_stage <= 1'b0;
            detune_product_stage <= 42'd0;
            detune_base_product_stage <= 32'd0;
            detune_negative_product_stage <= 1'b0;
            active_task_count <= 7'd0;

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

            // 活动任务数由分配和Release完成事件增量维护，避免每拍把32个
            // slot_active串接成组合计数器并直接送入后级音频乘法路径。
            if (retired_task_count != 7'd0)
                active_task_count
                    <= active_task_count - retired_task_count;

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
                        pending_phase_control<=phase_control; pending_rand_control<=rand_control;
                        pending_member_index <= 4'd0;
                        phase_calc_index <= 4'd0;
                        scan_index <= 6'd0;
                        scan_count <= 6'd0;
                        scheduler_busy <= 1'b1;

                        if (note_event_on) begin
                            if (matching_note_found) begin
                                victim_note <= note_event_note;
                                state_after_latch <= STATE_REPLACE_NOTE;
                            end else begin
                                scan_index <= allocation_cursor;
                                scan_count <= 6'd0;
                                state_after_latch <= STATE_ALLOCATE;
                            end
                            state <= STATE_LATCH_STEP;
                        end else if (matching_note_found) begin
                            victim_note <= note_event_note;
                            state_after_latch <= STATE_RELEASE_NOTE;
                            state <= STATE_LATCH_STEP;
                        end else begin
                            scheduler_busy <= 1'b0;
                        end
                    end
                end

                // MIDI音符先经过频率查表并锁存，下一拍再参与Detune计算。
                // 该边界切断pending_note到32个槽位相位步进寄存器的长路径。
                STATE_LATCH_STEP: begin
                    pending_base_phase_step_latched
                        <= pending_base_phase_step;

                    // Note Off沿用槽位中保存的相位步进，不需要重新计算Detune。
                    if (state_after_latch == STATE_RELEASE_NOTE)
                        state <= STATE_RELEASE_NOTE;
                    else
                        state <= STATE_DETUNE_PREP;
                end

                // 每个Unison成员先离线计算相位步进。三级流水把移位加法、
                // DSP乘法和最终舍入加减分开，分配状态只读取计算结果。
                STATE_DETUNE_PREP: begin
                    if (INITIAL_PHASE_ENABLE) begin
                        random_product_stage<=random_state*random_scale;
                        random_state<=next_random(random_state);
                    end
                    detune_delta_stage
                        <= make_detune_delta(
                               pending_base_phase_step_latched,
                               phase_calc_index,
                               pending_unison_count);
                    detune_base_stage
                        <= pending_base_phase_step_latched;
                    detune_negative_stage
                        <= ((phase_calc_index << 1)
                            < (pending_unison_count - 4'd1));
                    state <= STATE_DETUNE_MULT;
                end

                STATE_DETUNE_MULT: begin
                    detune_product_stage
                        <= detune_delta_stage * pending_detune_amount;
                    detune_base_product_stage <= detune_base_stage;
                    detune_negative_product_stage
                        <= detune_negative_stage;
                    state <= STATE_DETUNE_STORE;
                end

                STATE_DETUNE_STORE: begin
                    pending_member_initial_phase[phase_calc_index] <= INITIAL_PHASE_ENABLE
                        ? {pending_phase_control,25'd0}+random_product_stage[38:7] : 32'd0;
                    pending_member_detune_unit[phase_calc_index] <= detune_delta_stage;
                    pending_member_detune_magnitude[phase_calc_index]
                        <= make_detune_magnitude(
                               phase_calc_index,
                               pending_unison_count);
                    pending_member_detune_negative[phase_calc_index] <= detune_negative_product_stage;
                    pending_member_phase_step[phase_calc_index]
                        <= calculated_phase_step;

                    if (phase_calc_index
                        == pending_unison_count - 4'd1) begin
                        phase_calc_index <= 4'd0;
                        state <= state_after_latch;
                    end else begin
                        phase_calc_index <= phase_calc_index + 4'd1;
                        state <= STATE_DETUNE_PREP;
                    end
                end

                STATE_ALLOCATE: begin
                    if (!slot_active[allocation_candidate]) begin
                        task_update_valid <= 1'b1;
                        task_update_slot <= allocation_candidate;
                        task_update_phase_step
                            <= pending_member_phase_step[
                                   pending_member_index];
                        task_update_velocity <= pending_velocity;
                        task_update_enable <= 1'b1;
                        task_update_phase_reset <= 1'b1;
                        task_update_initial_phase<=pending_member_initial_phase[pending_member_index];
                        task_update_base_step <= pending_base_phase_step_latched;
                        task_update_detune_unit <= pending_member_detune_unit[pending_member_index];
                        task_update_detune_magnitude
                            <= pending_member_detune_magnitude[
                                   pending_member_index];
                        task_update_detune_negative <= pending_member_detune_negative[pending_member_index];

                        slot_note[allocation_candidate] <= pending_note;
                        slot_phase_step[allocation_candidate]
                            <= pending_member_phase_step[
                                   pending_member_index];
                        slot_velocity[allocation_candidate]
                            <= pending_velocity;
                        slot_active[allocation_candidate] <= 1'b1;
                        slot_releasing[allocation_candidate] <= 1'b0;
                        active_task_count
                            <= active_task_count - retired_task_count + 7'd1;

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
                                <= pending_member_phase_step[
                                       pending_member_index];
                            task_update_velocity <= pending_velocity;
                            task_update_enable <= 1'b1;
                            task_update_phase_reset <= 1'b1;
                            task_update_initial_phase<=pending_member_initial_phase[pending_member_index];
                            task_update_base_step <= pending_base_phase_step_latched;
                            task_update_detune_unit <= pending_member_detune_unit[pending_member_index];
                            task_update_detune_magnitude
                                <= pending_member_detune_magnitude[
                                       pending_member_index];
                            task_update_detune_negative <= pending_member_detune_negative[pending_member_index];
                            slot_note[scan_index] <= pending_note;
                            slot_phase_step[scan_index]
                                <= pending_member_phase_step[
                                       pending_member_index];
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
