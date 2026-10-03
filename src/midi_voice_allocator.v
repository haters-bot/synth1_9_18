// Allocate each MIDI note to a fixed group of adjacent oscillator slots.
// With VOICE_COUNT=32 and UNISON_COUNT=3, ten logical notes use slots 0..29;
// slots 30 and 31 remain unused. Updates are serialized over consecutive
// system clocks because the oscillator bank accepts one slot update per clock.
module midi_voice_allocator #(
    parameter integer VOICE_COUNT  = 32,
    parameter integer UNISON_COUNT = 3,
    parameter [6:0] MIN_NOTE       = 7'd21,
    parameter [6:0] MAX_NOTE       = 7'd108
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       note_event_valid,
    input  wire       note_event_on,
    input  wire [6:0] note_event_note,
    input  wire [VOICE_COUNT-1:0] voice_idle_mask,

    output reg        voice_update_valid,
    output reg [7:0]  voice_update_slot,
    output reg [6:0]  voice_update_note,
    output reg        voice_update_enable,
    output reg        voice_update_phase_reset,
    output reg [1:0]  voice_update_unison_lane,
    // Physical oscillator count, including every lane in active groups.
    output reg [5:0]  active_voice_count
);

    localparam integer LOGICAL_VOICE_COUNT = VOICE_COUNT / UNISON_COUNT;
    localparam [7:0] LAST_GROUP = LOGICAL_VOICE_COUNT - 1;

    reg [6:0] group_note [0:LOGICAL_VOICE_COUNT-1];
    reg       group_active [0:LOGICAL_VOICE_COUNT-1];
    reg       group_releasing [0:LOGICAL_VOICE_COUNT-1];
    reg [7:0] steal_pointer;

    reg       matching_found;
    reg [7:0] matching_group;
    reg       free_found;
    reg [7:0] free_group;

    // Pending lanes for a group update.
    reg       update_busy;
    reg [1:0] update_lane;
    reg [7:0] update_group;
    reg [6:0] pending_note;
    reg       pending_enable;
    reg       pending_phase_reset;

    integer search_index;
    integer reset_index;

    always @(*) begin
        matching_found = 1'b0;
        matching_group = 8'd0;
        free_found = 1'b0;
        free_group = 8'd0;
        active_voice_count = 6'd0;

        for (search_index = 0;
             search_index < LOGICAL_VOICE_COUNT;
             search_index = search_index + 1) begin
            if (group_active[search_index])
                active_voice_count = active_voice_count + UNISON_COUNT;

            if (!matching_found
                && group_active[search_index]
                && (group_note[search_index] == note_event_note)) begin
                matching_found = 1'b1;
                matching_group = search_index[7:0];
            end

            if (!free_found && !group_active[search_index]) begin
                free_found = 1'b1;
                free_group = search_index[7:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voice_update_valid       <= 1'b0;
            voice_update_slot        <= 8'd0;
            voice_update_note        <= 7'd0;
            voice_update_enable      <= 1'b0;
            voice_update_phase_reset <= 1'b0;
            voice_update_unison_lane <= 2'd1;
            steal_pointer            <= 8'd0;
            update_busy              <= 1'b0;
            update_lane              <= 2'd0;
            update_group             <= 8'd0;
            pending_note             <= 7'd0;
            pending_enable           <= 1'b0;
            pending_phase_reset      <= 1'b0;

            for (reset_index = 0;
                 reset_index < LOGICAL_VOICE_COUNT;
                 reset_index = reset_index + 1) begin
                group_note[reset_index]      <= 7'd0;
                group_active[reset_index]    <= 1'b0;
                group_releasing[reset_index] <= 1'b0;
            end
        end else begin
            voice_update_valid <= 1'b0;

            // All lanes use identical envelope parameters and are scheduled
            // in ascending order. The last lane is therefore the group-level
            // Release completion indication.
            for (reset_index = 0;
                 reset_index < LOGICAL_VOICE_COUNT;
                 reset_index = reset_index + 1) begin
                if (voice_idle_mask[
                        reset_index*UNISON_COUNT + UNISON_COUNT-1]
                    && group_releasing[reset_index]) begin
                    group_active[reset_index] <= 1'b0;
                    group_releasing[reset_index] <= 1'b0;
                end
            end

            if (update_busy) begin
                voice_update_valid       <= 1'b1;
                voice_update_slot        <= update_group*UNISON_COUNT
                                          + update_lane;
                voice_update_note        <= pending_note;
                voice_update_enable      <= pending_enable;
                voice_update_phase_reset <= pending_phase_reset;
                voice_update_unison_lane <= update_lane;

                if (update_lane == UNISON_COUNT-1) begin
                    update_busy <= 1'b0;
                    update_lane <= 2'd0;
                end else begin
                    update_lane <= update_lane + 2'd1;
                end
            end else if (note_event_valid
                         && (note_event_note >= MIN_NOTE)
                         && (note_event_note <= MAX_NOTE)) begin
                if (note_event_on) begin
                    voice_update_valid       <= 1'b1;
                    voice_update_note        <= note_event_note;
                    voice_update_enable      <= 1'b1;
                    voice_update_phase_reset <= 1'b1;
                    voice_update_unison_lane <= 2'd0;

                    pending_note        <= note_event_note;
                    pending_enable      <= 1'b1;
                    pending_phase_reset <= 1'b1;
                    update_lane         <= 2'd1;
                    update_busy         <= (UNISON_COUNT > 1);

                    if (matching_found) begin
                        voice_update_slot <= matching_group*UNISON_COUNT;
                        update_group <= matching_group;
                        group_note[matching_group] <= note_event_note;
                        group_active[matching_group] <= 1'b1;
                        group_releasing[matching_group] <= 1'b0;
                    end else if (free_found) begin
                        voice_update_slot <= free_group*UNISON_COUNT;
                        update_group <= free_group;
                        group_note[free_group] <= note_event_note;
                        group_active[free_group] <= 1'b1;
                        group_releasing[free_group] <= 1'b0;
                    end else begin
                        voice_update_slot <= steal_pointer*UNISON_COUNT;
                        update_group <= steal_pointer;
                        group_note[steal_pointer] <= note_event_note;
                        group_active[steal_pointer] <= 1'b1;
                        group_releasing[steal_pointer] <= 1'b0;

                        if (steal_pointer == LAST_GROUP)
                            steal_pointer <= 8'd0;
                        else
                            steal_pointer <= steal_pointer + 8'd1;
                    end
                end else if (matching_found) begin
                    voice_update_valid       <= 1'b1;
                    voice_update_slot        <= matching_group*UNISON_COUNT;
                    voice_update_note        <= note_event_note;
                    voice_update_enable      <= 1'b0;
                    voice_update_phase_reset <= 1'b0;
                    voice_update_unison_lane <= 2'd0;

                    pending_note        <= note_event_note;
                    pending_enable      <= 1'b0;
                    pending_phase_reset <= 1'b0;
                    update_group        <= matching_group;
                    update_lane         <= 2'd1;
                    update_busy         <= (UNISON_COUNT > 1);
                    group_releasing[matching_group] <= 1'b1;
                end
            end
        end
    end

endmodule
