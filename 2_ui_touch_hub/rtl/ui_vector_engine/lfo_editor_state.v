// Local LFO editor state. No MIDI dispatch and no claim of audio modulation.
// Consumes the router's already normalized pixel-domain touch packets.
module lfo_editor_state #(
    parameter WATCHDOG_CYCLES = 3125000,
    parameter PREVIEW_BASE_TICKS = 651042 // 62.5 MHz / (384 pixels * 0.25 Hz)
)(
    input wire clk, rst_n,
    input wire touch_valid, touch_down,
    input wire [13:0] touch_x, touch_y,
    output reg [1:0] active_tab,
    output wire [48:0] nodes,
    output wire [2:0] rate,
    output wire once_mode,
    output wire stepped,
    output wire [1:0] preset,
    output reg [8:0] phase,
    output reg running
);
    reg [6:0] points [0:20];
    reg [2:0] rates [0:2];
    reg [2:0] once_bits, step_bits;
    reg [1:0] presets [0:2];
    reg finger_down, editing;
    reg [21:0] watchdog;
    reg [19:0] tick_count;
    wire [4:0] bank = active_tab == 0 ? 0 : active_tab == 1 ? 7 : 14;
    assign rate = rates[active_tab];
    assign once_mode = once_bits[active_tab];
    assign stepped = step_bits[active_tab];
    assign preset = presets[active_tab];
    genvar n;
    generate for(n=0;n<7;n=n+1) begin: node_out
        assign nodes[n*7 +: 7] = points[bank+n];
    end endgenerate

    function [6:0] preset_point;
        input [1:0] kind;
        input integer idx;
        begin
            if (kind == 1) begin
                case(idx)
                    0: preset_point=0; 1: preset_point=21; 2: preset_point=42;
                    3: preset_point=64; 4: preset_point=85; 5: preset_point=106;
                    default: preset_point=127;
                endcase
            end else if (kind == 2) preset_point = idx < 3 ? 127 : 0;
            else begin
                case(idx)
                    0,6: preset_point=0; 1,5: preset_point=42;
                    2,4: preset_point=85; default: preset_point=127;
                endcase
            end
        end
    endfunction

    // Seven fixed time positions at X=832+64*n, amplitude 0..127.
    wire graph_hit = touch_x >= 824 && touch_x <= 1224 &&
                     touch_y >= 408 && touch_y <= 552;
    wire [8:0] graph_x = touch_x < 832 ? 0 : touch_x > 1216 ? 384 : touch_x-832;
    wire [9:0] rounded_x = {1'b0,graph_x}+10'd32;
    wire [2:0] node_index = rounded_x[9:6] > 6 ? 3'd6 : rounded_x[8:6];
    wire [6:0] amplitude = touch_y <= 416 ? 127 : touch_y >= 543 ? 0 : 543-touch_y;
    wire [1:0] chosen_preset = touch_x < 940 ? 0 : touch_x < 1076 ? 1 : 2;
    integer i, b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_tab <= 0;
            finger_down <= 0; editing <= 0; watchdog <= 0;
            once_bits <= 0; step_bits <= 3'b100;
            phase <= 0; tick_count <= 0; running <= 1;
            for (b=0;b<3;b=b+1) begin
                rates[b] <= 2; presets[b] <= b;
                for(i=0;i<7;i=i+1) points[b*7+i] <= preset_point(b,i);
            end
        end else begin
            if (running) begin
                if (tick_count >= (PREVIEW_BASE_TICKS >> rate)-1) begin
                    tick_count <= 0;
                    if (phase == 383) begin
                        if (once_mode) running <= 0;
                        else phase <= 0;
                    end else phase <= phase+1'b1;
                end else tick_count <= tick_count+1'b1;
            end
            if (watchdog < WATCHDOG_CYCLES) watchdog <= watchdog+1'b1;
            else begin finger_down <= 0; editing <= 0; end

            if (touch_valid) begin
                watchdog <= 0;
                if (!touch_down) begin finger_down <= 0; editing <= 0; end
                else begin
                    finger_down <= 1;
                    // Capture the gesture at first contact; crossing the panel
                    // during an oscillator drag cannot edit the LFO or hit tabs.
                    if (!finger_down) begin
                        editing <= graph_hit;
                        if (touch_y >= 372 && touch_y <= 398) begin
                            if (touch_x >= 808 && touch_x <= 1064) begin
                                if(touch_x < 892) active_tab <= 0;
                                else if(touch_x < 980) active_tab <= 1;
                                else active_tab <= 2;
                                phase <= 0; tick_count <= 0; running <= 1;
                            end
                        end else if(graph_hit) begin
                            points[bank+node_index] <= amplitude;
                            presets[active_tab] <= 3; // custom; retain interpolation style
                            phase <= 0; tick_count <= 0; running <= 1;
                        end else if (touch_y >= 560 && touch_y <= 590 &&
                                     touch_x >= 808 && touch_x <= 1240) begin
                            for(i=0;i<7;i=i+1)
                                points[bank+i] <= preset_point(chosen_preset,i);
                            presets[active_tab] <= chosen_preset;
                            step_bits[active_tab] <= chosen_preset == 2;
                            phase <= 0; tick_count <= 0; running <= 1;
                        end else if(touch_y >= 608 && touch_y <= 652) begin
                            if(touch_x >= 808 && touch_x <= 936)
                                rates[active_tab] <= rate == 5 ? 0 : rate+1'b1;
                            else if(touch_x >= 944 && touch_x <= 1072)
                                once_bits[active_tab] <= !once_mode;
                            if(touch_x >= 808 && touch_x <= 1240) begin
                                phase <= 0; tick_count <= 0; running <= 1;
                            end
                        end
                    end else if(editing && graph_hit) begin
                        points[bank+node_index] <= amplitude;
                        presets[active_tab] <= 3;
                    end
                end
            end
        end
    end
endmodule
