// Local LFO editor state. No MIDI dispatch and no claim of audio modulation.
// Consumes the router's already normalized pixel-domain touch packets.
module lfo_editor_state #(
    parameter WATCHDOG_CYCLES = 2500000,
    parameter PREVIEW_BASE_TICKS = 520833 // 50 MHz / (384 pixels * 0.25 Hz)
)(
    input wire clk, rst_n,
    input wire touch_valid, touch_down,
    input wire [13:0] touch_x, touch_y,
    output reg [1:0] active_tab,
    output wire [48:0] nodes,
    output wire [146:0] all_nodes,
    output wire [8:0] all_rates,
    output wire [2:0] all_stepped,
    output wire [2:0] all_once,
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
    reg touch_valid_r, touch_down_r;
    reg [13:0] touch_x_r, touch_y_r;
    reg [21:0] watchdog;
    reg [19:0] tick_count;
    // Evaluate each bank's fixed rate threshold in parallel. Selecting a bank
    // should select one result bit, not precede a wide shift/subtract/compare.
    // Keep 32-bit subtraction semantics for small simulation parameter values.
    function [31:0] rate_limit;
        input [2:0] r;
        begin case(r)
            0:rate_limit=(PREVIEW_BASE_TICKS>>0)-1;
            1:rate_limit=(PREVIEW_BASE_TICKS>>1)-1;
            2:rate_limit=(PREVIEW_BASE_TICKS>>2)-1;
            3:rate_limit=(PREVIEW_BASE_TICKS>>3)-1;
            4:rate_limit=(PREVIEW_BASE_TICKS>>4)-1;
            5:rate_limit=(PREVIEW_BASE_TICKS>>5)-1;
            6:rate_limit=(PREVIEW_BASE_TICKS>>6)-1;
            7:rate_limit=(PREVIEW_BASE_TICKS>>7)-1;
        endcase end
    endfunction
    wire [2:0] tick_expired;
    assign tick_expired[0]=tick_count>=rate_limit(rates[0]);
    assign tick_expired[1]=tick_count>=rate_limit(rates[1]);
    assign tick_expired[2]=tick_count>=rate_limit(rates[2]);
    wire [4:0] bank = active_tab == 0 ? 0 : active_tab == 1 ? 7 : 14;
    assign rate = rates[active_tab];
    assign once_mode = once_bits[active_tab];
    assign stepped = step_bits[active_tab];
    assign preset = presets[active_tab];
    assign all_rates={rates[2],rates[1],rates[0]};
    assign all_stepped=step_bits;
    assign all_once=once_bits;
    genvar n;
    generate for(n=0;n<7;n=n+1) begin: node_out
        // Each output has only three legal sources. Avoid a variable array
        // address/addition followed by a 21-entry read mux in the raster path.
        assign nodes[n*7 +: 7] = active_tab==0 ? points[n] :
                                 active_tab==1 ? points[n+7] : points[n+14];
    end endgenerate
    generate for(n=0;n<21;n=n+1) begin: all_node_out
        assign all_nodes[n*7+:7]=points[n];
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
    wire graph_hit = touch_x_r >= 824 && touch_x_r <= 1224 &&
                     touch_y_r >= 408 && touch_y_r <= 552;
    wire [8:0] graph_x = touch_x_r < 832 ? 0 : touch_x_r > 1216 ? 384 : touch_x_r-832;
    wire [9:0] rounded_x = {1'b0,graph_x}+10'd32;
    wire [2:0] node_index = rounded_x[9:6] > 6 ? 3'd6 : rounded_x[8:6];
    wire [6:0] amplitude = touch_y_r <= 416 ? 127 : touch_y_r >= 543 ? 0 : 543-touch_y_r;
    wire [1:0] chosen_preset = touch_x_r < 940 ? 0 : touch_x_r < 1076 ? 1 : 2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            touch_valid_r <= 1'b0;
            touch_down_r <= 1'b0;
            touch_x_r <= 14'd0;
            touch_y_r <= 14'd0;
        end else begin
            touch_valid_r <= touch_valid;
            touch_down_r <= touch_down;
            touch_x_r <= touch_x;
            touch_y_r <= touch_y;
        end
    end
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
                if (tick_expired[active_tab]) begin
                    tick_count <= 0;
                    if (phase == 383) begin
                        if (once_mode) running <= 0;
                        else phase <= 0;
                    end else phase <= phase+1'b1;
                end else tick_count <= tick_count+1'b1;
            end
            if (watchdog < WATCHDOG_CYCLES) watchdog <= watchdog+1'b1;
            else begin finger_down <= 0; editing <= 0; end

            if (touch_valid_r) begin
                watchdog <= 0;
                if (!touch_down_r) begin finger_down <= 0; editing <= 0; end
                else begin
                    finger_down <= 1;
                    // Capture the gesture at first contact; crossing the panel
                    // during an oscillator drag cannot edit the LFO or hit tabs.
                    if (!finger_down) begin
                        editing <= graph_hit;
                        if (touch_y_r >= 372 && touch_y_r <= 398) begin
                            if (touch_x_r >= 808 && touch_x_r <= 1064) begin
                                if(touch_x_r < 892) active_tab <= 0;
                                else if(touch_x_r < 980) active_tab <= 1;
                                else active_tab <= 2;
                                phase <= 0; tick_count <= 0; running <= 1;
                            end
                        end else if(graph_hit) begin
                            points[bank+node_index] <= amplitude;
                            presets[active_tab] <= 3; // custom smooth curve
                            step_bits[active_tab] <= 0;
                            phase <= 0; tick_count <= 0; running <= 1;
                        end else if (touch_y_r >= 560 && touch_y_r <= 590 &&
                                     touch_x_r >= 808 && touch_x_r <= 1240) begin
                            for(i=0;i<7;i=i+1)
                                points[bank+i] <= preset_point(chosen_preset,i);
                            presets[active_tab] <= chosen_preset;
                            step_bits[active_tab] <= chosen_preset == 2;
                            phase <= 0; tick_count <= 0; running <= 1;
                        end else if(touch_y_r >= 608 && touch_y_r <= 652) begin
                            if(touch_x_r >= 808 && touch_x_r <= 936)
                                rates[active_tab] <= rate == 5 ? 0 : rate+1'b1;
                            else if(touch_x_r >= 944 && touch_x_r <= 1072)
                                once_bits[active_tab] <= !once_mode;
                            if(touch_x_r >= 808 && touch_x_r <= 1240) begin
                                phase <= 0; tick_count <= 0; running <= 1;
                            end
                        end
                    end else if(editing && graph_hit) begin
                        points[bank+node_index] <= amplitude;
                        presets[active_tab] <= 3;
                        step_bits[active_tab] <= 0;
                    end
                end
            end
        end
    end
endmodule
