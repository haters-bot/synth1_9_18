// Map the chromatic key bitmap to sequential LEDs for white notes only.
// The UI key state remains one bit per semitone; black-note LEDs stay off.
module performance_led_white_mapper #(
    parameter integer KEY_COUNT = 32,
    parameter integer LED_COUNT = 24,
    parameter integer BASE_NOTE = 60
)(
    input  wire [KEY_COUNT-1:0] active_keys,
    input  wire [KEY_COUNT-1:0] guide_keys,
    output wire [LED_COUNT-1:0] led_active,
    output wire [LED_COUNT-1:0] led_guide
);
    function integer find_white_key;
        input integer white_ordinal;
        integer key_index;
        integer pitch_class;
        integer count;
        begin
            find_white_key = -1;
            count = 0;
            for (key_index = 0; key_index < KEY_COUNT; key_index = key_index + 1) begin
                pitch_class = (BASE_NOTE + key_index) % 12;
                if ((pitch_class == 0) || (pitch_class == 2) || (pitch_class == 4) ||
                    (pitch_class == 5) || (pitch_class == 7) || (pitch_class == 9) ||
                    (pitch_class == 11)) begin
                    if (count == white_ordinal)
                        find_white_key = key_index;
                    count = count + 1;
                end
            end
        end
    endfunction

    genvar led;
    generate
        for (led = 0; led < LED_COUNT; led = led + 1) begin: g_white_key_led
            localparam integer SOURCE_KEY = find_white_key(led);
            if (SOURCE_KEY >= 0) begin: g_assigned
                assign led_active[led] = active_keys[SOURCE_KEY];
                assign led_guide[led] = guide_keys[SOURCE_KEY];
            end else begin: g_unused
                assign led_active[led] = 1'b0;
                assign led_guide[led] = 1'b0;
            end
        end
    endgenerate
endmodule
