// 将MIDI音符事件分配到振荡器槽位。
// 分配优先级：同音重触发 -> 最低编号空闲槽位 -> 循环偷音。
module midi_voice_allocator #(
    parameter integer VOICE_COUNT = 32,
    parameter [6:0] MIN_NOTE      = 7'd21,
    parameter [6:0] MAX_NOTE      = 7'd108
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
    output reg        voice_update_phase_reset
);

    reg [6:0] slot_note [0:VOICE_COUNT-1];
    reg       slot_active [0:VOICE_COUNT-1];
    reg       slot_releasing [0:VOICE_COUNT-1];
    reg [7:0] steal_pointer;

    localparam [7:0] LAST_VOICE = VOICE_COUNT - 1;

    reg       matching_found;
    reg [7:0] matching_slot;
    reg       free_found;
    reg [7:0] free_slot;
    integer search_index;
    integer reset_index;

    // 固定优先编码器。VOICE_COUNT=32时只形成很浅的控制组合逻辑，
    // MIDI事件之间有充足时间，不在音频采样的关键数据路径上。
    always @(*) begin
        matching_found = 1'b0;
        matching_slot  = 8'd0;
        free_found     = 1'b0;
        free_slot      = 8'd0;

        for (search_index = 0;
             search_index < VOICE_COUNT;
             search_index = search_index + 1) begin
            if (!matching_found
                && slot_active[search_index]
                && (slot_note[search_index] == note_event_note)) begin
                matching_found = 1'b1;
                matching_slot  = search_index[7:0];
            end

            if (!free_found && !slot_active[search_index]) begin
                free_found = 1'b1;
                free_slot  = search_index[7:0];
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
            steal_pointer            <= 8'd0;

            for (reset_index = 0;
                 reset_index < VOICE_COUNT;
                 reset_index = reset_index + 1) begin
                slot_note[reset_index]   <= 7'd0;
                slot_active[reset_index] <= 1'b0;
                slot_releasing[reset_index] <= 1'b0;
            end
        end else begin
            voice_update_valid <= 1'b0;

            // Release真正归零后才释放槽位。同音重触发会先清除
            // slot_releasing，因此过期的完成脉冲不会误释放新声部。
            for (reset_index = 0;
                 reset_index < VOICE_COUNT;
                 reset_index = reset_index + 1) begin
                if (voice_idle_mask[reset_index]
                    && slot_releasing[reset_index]) begin
                    slot_active[reset_index] <= 1'b0;
                    slot_releasing[reset_index] <= 1'b0;
                end
            end

            if (note_event_valid
                && (note_event_note >= MIN_NOTE)
                && (note_event_note <= MAX_NOTE)) begin
                if (note_event_on) begin
                    voice_update_valid       <= 1'b1;
                    voice_update_note        <= note_event_note;
                    voice_update_enable      <= 1'b1;
                    voice_update_phase_reset <= 1'b1;

                    if (matching_found)
                        voice_update_slot <= matching_slot;
                    else if (free_found)
                        voice_update_slot <= free_slot;
                    else
                        voice_update_slot <= steal_pointer;

                    if (matching_found) begin
                        slot_note[matching_slot]   <= note_event_note;
                        slot_active[matching_slot] <= 1'b1;
                        slot_releasing[matching_slot] <= 1'b0;
                    end else if (free_found) begin
                        slot_note[free_slot]   <= note_event_note;
                        slot_active[free_slot] <= 1'b1;
                        slot_releasing[free_slot] <= 1'b0;
                    end else begin
                        slot_note[steal_pointer]   <= note_event_note;
                        slot_active[steal_pointer] <= 1'b1;
                        slot_releasing[steal_pointer] <= 1'b0;
                        if (steal_pointer == LAST_VOICE)
                            steal_pointer <= 8'd0;
                        else
                            steal_pointer <= steal_pointer + 8'd1;
                    end
                end else if (matching_found) begin
                    voice_update_valid       <= 1'b1;
                    voice_update_slot        <= matching_slot;
                    voice_update_note        <= note_event_note;
                    voice_update_enable      <= 1'b0;
                    voice_update_phase_reset <= 1'b0;
                    slot_releasing[matching_slot] <= 1'b1;
                end
            end
        end
    end

endmodule
