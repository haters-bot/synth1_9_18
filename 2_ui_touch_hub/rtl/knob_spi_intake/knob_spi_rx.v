// ============================================================================
// TXE8148 dual-chip EC11 intake
//
// Two TXE8148 devices are read through independent CS# lines. SCLK and SDI
// are shared, while SDO is shared by the two devices. Each device contributes
// 48 GPIO bits (P0.0..P5.7). Every encoder uses three consecutive GPIOs:
// A, B, then the active-low push switch.
//
// TXE8148 SPI is mode 0, MSB first. An input-port read uses 0x82 as the first
// byte, the port number in bits 6:4 of the second byte, then a dummy byte.
// The first two returned bytes are status/padding; the third is GPIO data.
// ============================================================================

`include "params.vh"

module knob_spi_rx #(
    parameter integer CLK_HZ = 62500000,
    parameter integer SPI_HZ = 2000000,
    parameter integer RESET_HOLD_CYCLES = 62500
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        spi_sdo,
    input  wire        spi_int_n,

    output wire        spi_2cs_n,
    output wire        spi_1cs_n,
    output wire        spi_sclk,
    output wire        spi_sdi,
    output wire        panel_reset_n,

    output reg         param_valid,
    output reg  [7:0]  param_id,
    output reg  [6:0]  param_val,

    output reg         button_valid,
    output reg  [7:0]  button_id,
    output reg  [1:0]  button_action
);

    localparam integer HALF_DIV = (CLK_HZ / (SPI_HZ * 2)) < 1
                                ? 1 : (CLK_HZ / (SPI_HZ * 2));

    localparam [2:0] ST_RESET = 3'd0;
    localparam [2:0] ST_LOW   = 3'd1;
    localparam [2:0] ST_HIGH  = 3'd2;
    localparam [2:0] ST_END   = 3'd3;
    localparam [2:0] ST_GAP   = 3'd4;

    reg [2:0]  state;
    reg [31:0] reset_count;
    reg [31:0] gap_count;
    reg [31:0] div_count;
    reg        chip_sel;       // 0: 1CS# / knobs 1..16, 1: 2CS# / knobs 17..32
    reg [2:0]  port_idx;
    reg [4:0]  bit_idx;
    reg [23:0] tx_frame;
    reg [23:0] rx_shift;

    reg sdo_d1, sdo_d2;
    reg int_d1, int_d2;

    reg [47:0] chip1_gpio;
    reg [47:0] chip2_gpio;
    reg [47:0] prev_chip1_gpio;
    reg [47:0] prev_chip2_gpio;
    reg        snapshot_valid;
    reg        commit_pending;

    reg [31:0] pending_mask;
    reg [31:0] button_pending_mask;
    reg [6:0]  knob_value [0:31];

    reg [31:0] next_pending_mask;
    reg [31:0] next_button_pending_mask;
    reg [31:0] emitted_mask;
    reg [31:0] emitted_button_mask;
    reg [1:0]  qstep;
    reg        old_a, old_b, new_a, new_b;
    reg        old_sw, new_sw;
    integer i;

    assign panel_reset_n = (state != ST_RESET);
    assign spi_1cs_n = !((state == ST_LOW || state == ST_HIGH || state == ST_END)
                         && chip_sel == 1'b0);
    assign spi_2cs_n = !((state == ST_LOW || state == ST_HIGH || state == ST_END)
                         && chip_sel == 1'b1);
    assign spi_sclk = (state == ST_HIGH);
    assign spi_sdi = (state == ST_LOW || state == ST_HIGH)
                   ? tx_frame[23-bit_idx] : 1'b0;

    function [7:0] map_knob_to_param_id;
        input [4:0] knob;
        begin
            // Keep the earlier 16-channel mapping, then extend it to the
            // remaining primary synthesis and FX controls.
            case (knob)
                5'd0:  map_knob_to_param_id = `PARAM_ID_FLT_CUTOFF;
                5'd1:  map_knob_to_param_id = `PARAM_ID_FLT_RES;
                5'd2:  map_knob_to_param_id = `PARAM_ID_OSCA_WT_POS;
                5'd3:  map_knob_to_param_id = `PARAM_ID_OSCA_DETUNE;
                5'd4:  map_knob_to_param_id = `PARAM_ID_OSCA_UNISON;
                5'd5:  map_knob_to_param_id = `PARAM_ID_OSCA_PAN;
                5'd6:  map_knob_to_param_id = `PARAM_ID_OSCA_VOL;
                5'd7:  map_knob_to_param_id = `PARAM_ID_ENV1_ATTACK;
                5'd8:  map_knob_to_param_id = `PARAM_ID_ENV1_DECAY;
                5'd9:  map_knob_to_param_id = `PARAM_ID_ENV1_SUSTAIN;
                5'd10: map_knob_to_param_id = `PARAM_ID_ENV1_RELEASE;
                5'd11: map_knob_to_param_id = `PARAM_ID_MASTER_VOL;
                5'd12: map_knob_to_param_id = `PARAM_ID_MACRO1;
                5'd13: map_knob_to_param_id = `PARAM_ID_MACRO2;
                5'd14: map_knob_to_param_id = `PARAM_ID_MACRO3;
                5'd15: map_knob_to_param_id = `PARAM_ID_MACRO4;
                5'd16: map_knob_to_param_id = `PARAM_ID_OSCB_WT_POS;
                5'd17: map_knob_to_param_id = `PARAM_ID_OSCB_DETUNE;
                5'd18: map_knob_to_param_id = `PARAM_ID_OSCB_UNISON;
                5'd19: map_knob_to_param_id = `PARAM_ID_OSCB_PAN;
                5'd20: map_knob_to_param_id = `PARAM_ID_OSCB_VOL;
                5'd21: map_knob_to_param_id = `PARAM_ID_OSCB_BLEND;
                5'd22: map_knob_to_param_id = `PARAM_ID_OSCB_PHASE;
                5'd23: map_knob_to_param_id = `PARAM_ID_OSCB_RAND;
                5'd24: map_knob_to_param_id = `PARAM_ID_FLT_PAN;
                5'd25: map_knob_to_param_id = `PARAM_ID_FLT_DRIVE;
                5'd26: map_knob_to_param_id = `PARAM_ID_FLT_FAT;
                5'd27: map_knob_to_param_id = `PARAM_ID_FLT_MIX;
                5'd28: map_knob_to_param_id = `PARAM_ID_ENV1_HOLD;
                5'd29: map_knob_to_param_id = `PARAM_ID_FX_REVERB;
                5'd30: map_knob_to_param_id = `PARAM_ID_FX_DELAY;
                5'd31: map_knob_to_param_id = `PARAM_ID_FX_CHORUS;
                default: map_knob_to_param_id = `PARAM_ID_NONE;
            endcase
        end
    endfunction

    function [7:0] map_switch_to_button_id;
        input [4:0] sw;
        begin
            case (sw)
                5'd0: map_switch_to_button_id = `PARAM_ID_OSCA_POWER;
                5'd1: map_switch_to_button_id = `PARAM_ID_OSCA_WAVE;
                5'd2: map_switch_to_button_id = `PARAM_ID_OSCB_POWER;
                5'd3: map_switch_to_button_id = `PARAM_ID_OSCB_WAVE;
                5'd4: map_switch_to_button_id = `PARAM_ID_FLT_POWER;
                5'd5: map_switch_to_button_id = `PARAM_ID_FLT_TYPE;
                default: map_switch_to_button_id = `PARAM_ID_NONE;
            endcase
        end
    endfunction

    // 00 -> 01 -> 11 -> 10 -> 00 is positive rotation.
    function [1:0] quad_step;
        input oa, ob, na, nb;
        begin
            case ({oa, ob, na, nb})
                4'b0001, 4'b0111, 4'b1110, 4'b1000: quad_step = 2'd1;
                4'b0010, 4'b1011, 4'b1101, 4'b0100: quad_step = 2'd2;
                default: quad_step = 2'd0;
            endcase
        end
    endfunction

    function [23:0] make_read_frame;
        input [2:0] port;
        begin
            make_read_frame = {8'h82, {port, 4'b0000}, 8'h00};
        end
    endfunction

    function get_gpio;
        input [47:0] value;
        input integer bit_number;
        begin
            get_gpio = value[bit_number];
        end
    endfunction

    // INT# is not needed for the first polling implementation. Synchronizing
    // it here keeps the input safe and leaves the interface ready for an
    // interrupt-driven scan in a later revision.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdo_d1 <= 1'b0;
            sdo_d2 <= 1'b0;
            int_d1 <= 1'b1;
            int_d2 <= 1'b1;
        end else begin
            sdo_d1 <= spi_sdo;
            sdo_d2 <= sdo_d1;
            int_d1 <= spi_int_n;
            int_d2 <= int_d1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_RESET;
            reset_count            <= 32'd0;
            gap_count              <= 32'd0;
            div_count              <= 32'd0;
            chip_sel               <= 1'b0;
            port_idx               <= 3'd0;
            bit_idx                <= 5'd0;
            tx_frame               <= make_read_frame(3'd0);
            rx_shift               <= 24'd0;
            chip1_gpio             <= 48'd0;
            chip2_gpio             <= 48'd0;
            prev_chip1_gpio        <= 48'd0;
            prev_chip2_gpio        <= 48'd0;
            snapshot_valid         <= 1'b0;
            commit_pending         <= 1'b0;
            pending_mask           <= 32'd0;
            button_pending_mask    <= 32'd0;
            param_valid            <= 1'b0;
            param_id               <= `PARAM_ID_NONE;
            param_val              <= 7'd64;
            button_valid           <= 1'b0;
            button_id              <= `PARAM_ID_NONE;
            button_action          <= 2'd0;
            for (i = 0; i < 32; i = i + 1)
                knob_value[i] <= 7'd64;
        end else begin
            param_valid  <= 1'b0;
            button_valid <= 1'b0;

            if (state == ST_RESET) begin
                if (reset_count >= RESET_HOLD_CYCLES - 1) begin
                    state       <= ST_GAP;
                    gap_count   <= 32'd0;
                    chip_sel    <= 1'b0;
                    port_idx    <= 3'd0;
                    bit_idx     <= 5'd0;
                    tx_frame    <= make_read_frame(3'd0);
                end else begin
                    reset_count <= reset_count + 32'd1;
                end
            end else if (state == ST_GAP) begin
                if (gap_count >= HALF_DIV - 1) begin
                    state     <= ST_LOW;
                    div_count <= 32'd0;
                    bit_idx   <= 5'd0;
                    rx_shift  <= 24'd0;
                end else begin
                    gap_count <= gap_count + 32'd1;
                end
            end else if (state == ST_LOW) begin
                if (div_count >= HALF_DIV - 1) begin
                    div_count <= 32'd0;
                    state     <= ST_HIGH;
                    // SPI mode 0 samples SDO on the rising edge.
                    rx_shift  <= {rx_shift[22:0], sdo_d2};
                end else begin
                    div_count <= div_count + 32'd1;
                end
            end else if (state == ST_HIGH) begin
                if (div_count >= HALF_DIV - 1) begin
                    div_count <= 32'd0;
                    if (bit_idx == 5'd23) begin
                        state <= ST_END;
                    end else begin
                        bit_idx <= bit_idx + 5'd1;
                        state   <= ST_LOW;
                    end
                end else begin
                    div_count <= div_count + 32'd1;
                end
            end else if (state == ST_END) begin
                // The final shifted byte is the input-port value.
                if (chip_sel == 1'b0) begin
                    case (port_idx)
                        3'd0: chip1_gpio[7:0]   <= rx_shift[7:0];
                        3'd1: chip1_gpio[15:8]  <= rx_shift[7:0];
                        3'd2: chip1_gpio[23:16] <= rx_shift[7:0];
                        3'd3: chip1_gpio[31:24] <= rx_shift[7:0];
                        3'd4: chip1_gpio[39:32] <= rx_shift[7:0];
                        default: begin
                            chip1_gpio[47:40] <= rx_shift[7:0];
                        end
                    endcase
                end else begin
                    case (port_idx)
                        3'd0: chip2_gpio[7:0]   <= rx_shift[7:0];
                        3'd1: chip2_gpio[15:8]  <= rx_shift[7:0];
                        3'd2: chip2_gpio[23:16] <= rx_shift[7:0];
                        3'd3: chip2_gpio[31:24] <= rx_shift[7:0];
                        3'd4: chip2_gpio[39:32] <= rx_shift[7:0];
                        default: begin
                            chip2_gpio[47:40] <= rx_shift[7:0];
                            commit_pending <= 1'b1;
                        end
                    endcase
                end

                if (port_idx == 3'd5) begin
                    if (chip_sel == 1'b0) begin
                        chip_sel <= 1'b1;
                        port_idx <= 3'd0;
                        tx_frame <= make_read_frame(3'd0);
                    end else begin
                        chip_sel  <= 1'b0;
                        port_idx  <= 3'd0;
                        tx_frame  <= make_read_frame(3'd0);
                        gap_count <= 32'd0;
                        state     <= ST_GAP;
                    end
                end else begin
                    port_idx  <= port_idx + 3'd1;
                    tx_frame  <= make_read_frame(port_idx + 3'd1);
                    state     <= ST_GAP;
                    gap_count <= 32'd0;
                end
            end

            // Process one complete two-chip snapshot after the final byte has
            // been stored. The first snapshot establishes the baseline.
            if (commit_pending) begin
                commit_pending          <= 1'b0;
                next_pending_mask       = pending_mask;
                next_button_pending_mask = button_pending_mask;
                if (!snapshot_valid) begin
                    prev_chip1_gpio <= chip1_gpio;
                    prev_chip2_gpio <= chip2_gpio;
                    snapshot_valid  <= 1'b1;
                end else begin
                    for (i = 0; i < 32; i = i + 1) begin
                        if (i < 16) begin
                            old_a  = get_gpio(prev_chip1_gpio, (i * 3));
                            old_b  = get_gpio(prev_chip1_gpio, (i * 3) + 1);
                            new_a  = get_gpio(chip1_gpio, (i * 3));
                            new_b  = get_gpio(chip1_gpio, (i * 3) + 1);
                            old_sw = get_gpio(prev_chip1_gpio, (i * 3) + 2);
                            new_sw = get_gpio(chip1_gpio, (i * 3) + 2);
                        end else begin
                            old_a  = get_gpio(prev_chip2_gpio, ((i-16) * 3));
                            old_b  = get_gpio(prev_chip2_gpio, ((i-16) * 3) + 1);
                            new_a  = get_gpio(chip2_gpio, ((i-16) * 3));
                            new_b  = get_gpio(chip2_gpio, ((i-16) * 3) + 1);
                            old_sw = get_gpio(prev_chip2_gpio, ((i-16) * 3) + 2);
                            new_sw = get_gpio(chip2_gpio, ((i-16) * 3) + 2);
                        end

                        qstep = quad_step(old_a, old_b, new_a, new_b);
                        if (qstep == 2'd1) begin
                            if (knob_value[i] != 7'd127)
                                knob_value[i] <= knob_value[i] + 7'd1;
                            next_pending_mask[i] = 1'b1;
                        end else if (qstep == 2'd2) begin
                            if (knob_value[i] != 7'd0)
                                knob_value[i] <= knob_value[i] - 7'd1;
                            next_pending_mask[i] = 1'b1;
                        end

                        // EC11 switches are active low: emit on press only.
                        if (old_sw && !new_sw && map_switch_to_button_id(i[4:0]) != `PARAM_ID_NONE)
                            next_button_pending_mask[i] = 1'b1;
                    end
                    prev_chip1_gpio <= chip1_gpio;
                    prev_chip2_gpio <= chip2_gpio;
                end
                pending_mask        <= next_pending_mask;
                button_pending_mask <= next_button_pending_mask;
            end else begin
                emitted_mask = 32'd0;
                for (i = 0; i < 32; i = i + 1) begin
                    if (!emitted_mask[i] && pending_mask[i]) begin
                        param_valid     <= 1'b1;
                        param_id        <= map_knob_to_param_id(i[4:0]);
                        param_val       <= knob_value[i];
                        emitted_mask[i] = 1'b1;
                    end
                end
                pending_mask <= pending_mask & ~emitted_mask;

                emitted_button_mask = 32'd0;
                for (i = 0; i < 32; i = i + 1) begin
                    if (!emitted_button_mask[i] && button_pending_mask[i]) begin
                        button_valid           <= 1'b1;
                        button_id              <= map_switch_to_button_id(i[4:0]);
                        button_action          <= 2'd0;
                        emitted_button_mask[i] = 1'b1;
                    end
                end
                button_pending_mask <= button_pending_mask & ~emitted_button_mask;
            end
        end
    end

endmodule
