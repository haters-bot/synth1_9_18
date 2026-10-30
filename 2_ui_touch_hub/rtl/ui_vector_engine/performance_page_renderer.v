// Dedicated performance page geometry. MIDI notes are rendered as 32
// independent semitone columns; key pitch class is based on BASE_NOTE.
module performance_page_renderer #(
    parameter integer KEY_COUNT = 32,
    parameter integer BASE_NOTE = 60
)(
    input  wire [13:0] in_x,
    input  wire [13:0] in_y,
    input  wire [KEY_COUNT-1:0] active_keys,
    input  wire [KEY_COUNT-1:0] guide_keys,
    input  wire [15:0] song_progress,
    input  wire        song_running,
    input  wire        song_paused,
    input  wire        gateway_up,
    input  wire        recording,
    input  wire [3:0]  record_status,
    input  wire [5:0]  next_key,
    input  wire        next_key_valid,
    input  wire [8:0]  next_key_y,
    output reg         out_hit,
    output reg  [23:0] out_rgb
);
    function integer is_black_note;
        input integer midi_note;
        integer pitch_class;
        begin
            pitch_class = midi_note % 12;
            is_black_note = (pitch_class == 1) || (pitch_class == 3) ||
                            (pitch_class == 6) || (pitch_class == 8) ||
                            (pitch_class == 10);
        end
    endfunction

    wire [KEY_COUNT-1:0] key_select;
    wire [KEY_COUNT-1:0] black_key_mask;
    wire [KEY_COUNT-1:0] key_edge_mask;
    wire [KEY_COUNT-1:0] next_key_mask;
    genvar key;
    generate
        for (key = 0; key < KEY_COUNT; key = key + 1) begin: g_key_geometry
            localparam integer KEY_LEFT  = (key * 1280) / KEY_COUNT;
            localparam integer KEY_RIGHT = ((key + 1) * 1280) / KEY_COUNT;
            localparam integer KEY_BLACK = is_black_note(BASE_NOTE + key);
            assign key_select[key] = (in_x >= KEY_LEFT) && (in_x < KEY_RIGHT);
            assign black_key_mask[key] = KEY_BLACK;
            assign key_edge_mask[key] = (in_x == KEY_LEFT) || (in_x == KEY_RIGHT - 1);
            assign next_key_mask[key] = (next_key == key);
        end
    endgenerate

    wire key_active = |(key_select & active_keys);
    wire key_guide = |(key_select & guide_keys);
    wire key_black = |(key_select & black_key_mask);
    wire key_edge = |(key_select & key_edge_mask);
    wire next_key_hit = next_key_valid && |(key_select & next_key_mask);
    wire [26:0] progress_product = {11'd0, song_progress} * 27'd1180;
    wire [10:0] progress_width = progress_product[26:16];

    always @(*) begin
        out_hit = 1'b1;
        out_rgb = 24'h081019;

        if (in_y >= 14'd128 && in_y < 14'd176) begin
            out_rgb = (in_y >= 14'd172) ? 24'h2C94A8 : 24'h152A38;
            if (in_x >= 14'd48 && in_x < 14'd112 && in_y >= 14'd136 && in_y < 14'd168)
                out_rgb = song_running && !song_paused ? 24'h246779 : 24'h254455;
            if (in_x >= 14'd120 && in_x < 14'd184 && in_y >= 14'd136 && in_y < 14'd168)
                out_rgb = song_paused ? 24'h8A6737 : 24'h254455;
            if (in_x >= 14'd192 && in_x < 14'd256 && in_y >= 14'd136 && in_y < 14'd168)
                out_rgb = 24'h4D3540;
            if (in_y >= 14'd144 && in_y < 14'd160 &&
                ((in_x >= 14'd72 && in_x < 14'd88 && in_x-14'd72 < ((in_y < 14'd152) ?
                  (in_y-14'd144)*2 : (14'd160-in_y)*2)) ||
                 ((in_x >= 14'd144 && in_x < 14'd151) || (in_x >= 14'd153 && in_x < 14'd160)) ||
                 (in_x >= 14'd216 && in_x < 14'd232)))
                out_rgb = 24'hE7F1F2;
            if (in_x >= 14'd840 && in_x < 14'd1000 && in_y >= 14'd140 && in_y < 14'd160)
                out_rgb = gateway_up ? 24'h2C8C72 : 24'h35495F;
            if (in_x >= 14'd1010 && in_x < 14'd1170 && in_y >= 14'd136 && in_y < 14'd168)
                out_rgb = record_status >= 4'd6 ? 24'hA7464B :
                          record_status == 4'd2 ? 24'hA7464B :
                          record_status == 4'd3 || record_status == 4'd5 ? 24'h8A6737 :
                          record_status == 4'd4 ? 24'h2C8C72 : 24'h35495F;
            if (in_x >= 14'd1024 && in_x < 14'd1032 && in_y >= 14'd148 && in_y < 14'd156)
                out_rgb = recording ? 24'hFF6B67 : 24'hB8C8CE;
        end else if (in_y >= 14'd64 && in_y < 14'd96) begin
            out_rgb = 24'h132333;
            if (in_x >= 14'd40 && in_x < 14'd1240 && in_y >= 14'd76 && in_y < 14'd84)
                out_rgb = (in_x - 14'd40 < {3'd0, progress_width}) ? 24'h62E0E8 : 24'h274255;
        end else if (in_y >= 14'd192 && in_y < 14'd400) begin
            // Each guidance lane uses the exact horizontal interval of its
            // corresponding chromatic key; no run-time division is used.
            out_rgb = key_edge ? 24'h1D3447 : next_key_hit ? 24'h153B4C : 24'h0C1824;
            if(next_key_hit && in_y>={5'd0,next_key_y} && in_y<{5'd0,next_key_y}+14'd16)
                out_rgb = 24'h7EBBE8;
            if (key_guide && in_y >= 14'd330 && in_y < 14'd390)
                out_rgb = 24'h62E0E8;
            if(in_y>=14'd394)out_rgb=24'h2C8794;
        end else if (in_y >= 14'd420) begin
            if (key_black)
                out_rgb = key_active ? 24'hF0AD55 : key_guide ? 24'h2C8794 : 24'h1C3040;
            else
                out_rgb = key_active ? 24'hF0AD55 : key_guide ? 24'hB9E6E9 : 24'hD8E4E8;
            if (key_edge || in_y == 14'd719)
                out_rgb = 24'h4A6474;
        end

        // Keep the status input explicit for future local playback controls.
        if (song_running && in_y == 14'd175)
            out_rgb = 24'h42B4C7;
    end
endmodule
