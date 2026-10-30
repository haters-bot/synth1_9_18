module performance_touch_controls (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        page_active,
    input  wire        touch_valid,
    input  wire        touch_down,
    input  wire [13:0] touch_x,
    input  wire [13:0] touch_y,
    output wire        play,
    output wire        pause_toggle,
    output wire        stop,
    output wire        record_toggle
);
    reg touch_prev;
    wire touch_edge = touch_valid && touch_down && !touch_prev;
    // The global page-navigation bar owns y=0..43.
    wire button_row = touch_y >= 14'd136 && touch_y < 14'd168;

    assign play = page_active && touch_edge && button_row &&
                  touch_x >= 14'd48 && touch_x < 14'd112;
    assign pause_toggle = page_active && touch_edge && button_row &&
                          touch_x >= 14'd120 && touch_x < 14'd184;
    assign stop = page_active && touch_edge && button_row &&
                  touch_x >= 14'd192 && touch_x < 14'd256;
    assign record_toggle = page_active && touch_edge && button_row &&
                           touch_x >= 14'd1010 && touch_x < 14'd1170;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            touch_prev <= 1'b0;
        else if (touch_valid)
            touch_prev <= touch_down;
    end
endmodule
