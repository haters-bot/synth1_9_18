// ==============================================================================
// Module: hspi_touch_rx.v
// Description: High-Speed Parallel Interface (HSPI) Touch Intake Receiver
//              Connects to onboard CH569 USB Host MCU on Tang Mega 138K Dock.
//              Decodes 16-bit parallel stream (16'h5454, X, Y) from USB touch screen.
//              Robust Clock Domain Crossing (CDC) to Pixel Clock (62.5MHz) with
//              watchdog auto-release and activity strobe.
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

module hspi_touch_rx (
    // HSPI Physical Interface (CH569 domain)
    input  wire        hspi_clk,        // L20: ch569_htclk
    input  wire        rst_n,           // Active-low asynchronous reset
    input  wire        hspi_req,        // N20: ch569_htreq
    input  wire        hspi_vld,        // L15: ch569_htvld
    input  wire [15:0] hspi_data,       // G17..L16: hspi_hd[15:0]
    output wire        hspi_rdy,        // J22: ch569_htrdy (always ready)

    // Synchronous Video Domain Interface (clk_pixel domain)
    input  wire        pixel_clk,       // 62.5MHz Pixel Clock
    input  wire        pixel_rst_n,     // Synchronous pixel reset
    output reg         touch_valid,     // 1-cycle strobe per new touch report
    output reg  [15:0] touch_x,         // X coordinate (0..1279 or 0..1920)
    output reg  [15:0] touch_y,         // Y coordinate (0..719 or 0..1080)
    output reg         touch_state      // 1: Contact down, 0: Lifted
);

    assign hspi_rdy = 1'b1;

    // --------------------------------------------------------------------------
    // 1. CH569 HSPI Domain Frame Parser
    // --------------------------------------------------------------------------
    reg [1:0]  word_index;
    reg [15:0] x_hold;
    reg [15:0] y_hold;
    reg        frame_active;
    reg        toggle_hspi;

    always @(posedge hspi_clk or negedge rst_n) begin
        if (!rst_n) begin
            word_index   <= 2'd0;
            x_hold       <= 16'd0;
            y_hold       <= 16'd0;
            frame_active <= 1'b0;
            toggle_hspi  <= 1'b0;
        end else begin
            if (hspi_req && !frame_active) begin
                frame_active <= 1'b1;
                word_index   <= 2'd0;
            end

            if (frame_active && hspi_vld) begin
                case (word_index)
                    2'd0: begin
                        if (hspi_data == 16'h5454)
                            word_index <= 2'd1;
                        else
                            frame_active <= 1'b0;
                    end
                    2'd1: begin
                        x_hold     <= hspi_data;
                        word_index <= 2'd2;
                    end
                    2'd2: begin
                        y_hold       <= hspi_data;
                        toggle_hspi  <= ~toggle_hspi; // Signal new frame
                        frame_active <= 1'b0;
                        word_index   <= 2'd0;
                    end
                    default: begin
                        frame_active <= 1'b0;
                        word_index   <= 2'd0;
                    end
                endcase
            end

            if (!hspi_req && frame_active && !hspi_vld) begin
                frame_active <= 1'b0;
                word_index   <= 2'd0;
            end
        end
    end

    // --------------------------------------------------------------------------
    // 2. Clock Domain Crossing (CDC) into Pixel Clock Domain
    // --------------------------------------------------------------------------
    reg [2:0]  toggle_sync;
    reg [15:0] sync_x, sync_y;
    reg [23:0] watchdog_cnt;

    wire new_packet = (toggle_sync[2] ^ toggle_sync[1]);

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            toggle_sync  <= 3'd0;
            sync_x       <= 16'd0;
            sync_y       <= 16'd0;
            touch_valid  <= 1'b0;
            touch_x      <= 16'd0;
            touch_y      <= 16'd0;
            touch_state  <= 1'b0;
            watchdog_cnt <= 24'd0;
        end else begin
            toggle_sync <= {toggle_sync[1:0], toggle_hspi};
            touch_valid <= 1'b0;

            if (new_packet) begin
                // Pass raw coordinates to touch_event_router for unified, glitch-free normalization
                touch_x      <= x_hold;
                touch_y      <= y_hold;
                touch_state  <= 1'b1;
                touch_valid  <= 1'b1;
                watchdog_cnt <= 24'd0;
            end else begin
                // Auto-release contact if no new packet received for 50ms (3,125,000 cycles)
                if (watchdog_cnt < 24'd2_500_000) begin
                    watchdog_cnt <= watchdog_cnt + 24'd1;
                end else begin
                    touch_state <= 1'b0;
                end
            end
        end
    end

endmodule
