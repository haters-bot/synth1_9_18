// Dual TXE8148 reader for the 32-EC11 panel.
// Wiring and quadrature format match the standalone, bench-verified probe.
// Within each chip, encoder k uses three consecutive GPIO bits:
// A=3*k, B=3*k+1, active-low SW=3*k+2.
`include "params.vh"

module knob_spi_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SPI_HZ = 1000000,
    parameter integer RESET_HOLD_CYCLES = 100000,
    parameter integer SWITCH_DEBOUNCE_SCANS = 5
) (
    input  wire clk,
    input  wire rst_n,
    input  wire spi_sdo,
    input  wire spi_int_n,
    output wire spi_2cs_n,
    output wire spi_1cs_n,
    output wire spi_sclk,
    output wire spi_sdi,
    output wire panel_reset_n,
    output reg param_valid,
    output reg [7:0] param_id,
    // Kept for trace compatibility; physical motion is applied as +/-1 delta.
    output reg [6:0] param_val,
    output reg param_cw,
    output reg select_valid,
    output reg [7:0] select_id,
    // 1=press, 2=release.
    output reg [1:0] select_action,
    // Status is emitted at startup and only when a chip changes link state.
    output reg spi_link_valid,
    output reg spi_link_chip,
    output reg spi_link_up
);
    localparam integer HALF_DIV = (CLK_HZ/(SPI_HZ*2)) < 1 ? 1 : CLK_HZ/(SPI_HZ*2);
    localparam [2:0] ST_RESET=3'd0, ST_START=3'd1, ST_LOW=3'd2,
                     ST_HIGH=3'd3, ST_END=3'd4, ST_GAP=3'd5;

    reg [2:0] state;
    reg [31:0] reset_count,gap_count,div_count;
    reg chip_sel;
    reg [2:0] byte_idx,bit_idx;
    reg [7:0] tx_byte,rx_byte,status_hi,status_lo;
    reg [7:0] last_byte;
    reg sdo_d1,sdo_d2,int_d1,int_d2;
    reg [47:0] chip1_gpio,chip2_gpio,prev_chip1_gpio,prev_chip2_gpio;
    reg [1:0] snapshot_valid;
    reg commit_pending;
    reg [31:0] pending_mask,next_pending_mask,emitted_mask;
    reg [31:0] pending_switch,next_pending_switch,emitted_switch;
    reg [1:0] switch_action [0:31];
    reg direction_cw [0:31];
    reg signed [2:0] detent_accum [0:31];
    reg [6:0] knob_value [0:31];
    reg switch_stable [0:31],switch_last_raw [0:31];
    reg [2:0] switch_debounce [0:31];
    reg [1:0] link_known,link_up_state;
    reg [1:0] qstep;
    reg old_a,old_b,new_a,new_b,new_sw;
    integer i;

    assign panel_reset_n = (state != ST_RESET);
    assign spi_1cs_n = !((state==ST_LOW || state==ST_HIGH || state==ST_END) && !chip_sel);
    assign spi_2cs_n = !((state==ST_LOW || state==ST_HIGH || state==ST_END) && chip_sel);
    assign spi_sclk = (state==ST_HIGH);
    assign spi_sdi = (state==ST_LOW || state==ST_HIGH) ? tx_byte[7-bit_idx] : 1'b0;
    function get_gpio;
        input [47:0] gpio;
        input integer bit_number;
        begin get_gpio=gpio[bit_number]; end
    endfunction
    `include "knob_param_map.vh"
    function [1:0] quad_step;
        input oa,ob,na,nb;
        begin
            case({oa,ob,na,nb})
                // Physical PCB A/B order: clockwise is 11->01->00->10->11.
                4'b0001,4'b0111,4'b1110,4'b1000:quad_step=2'd2;
                4'b0010,4'b1011,4'b1101,4'b0100:quad_step=2'd1;
                default:quad_step=2'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sdo_d1<=0;sdo_d2<=0;int_d1<=1;int_d2<=1;
        end else begin
            sdo_d1<=spi_sdo;sdo_d2<=sdo_d1;int_d1<=spi_int_n;int_d2<=int_d1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_RESET;reset_count<=0;gap_count<=0;div_count<=0;chip_sel<=0;
            byte_idx<=0;bit_idx<=0;tx_byte<=8'h82;rx_byte<=0;status_hi<=0;status_lo<=0;
            chip1_gpio<=0;chip2_gpio<=0;prev_chip1_gpio<=0;prev_chip2_gpio<=0;
            snapshot_valid<=0;commit_pending<=0;pending_mask<=0;link_known<=0;link_up_state<=0;
            pending_switch<=0;
            param_valid<=0;param_id<=`PARAM_ID_NONE;param_val<=64;param_cw<=1;
            select_valid<=0;select_id<=`PARAM_ID_NONE;select_action<=0;
            spi_link_valid<=0;spi_link_chip<=0;spi_link_up<=0;
            for(i=0;i<32;i=i+1) begin
                direction_cw[i]<=1;detent_accum[i]<=0;knob_value[i]<=64;
                switch_stable[i]<=1;switch_last_raw[i]<=1;switch_debounce[i]<=5;
                switch_action[i]<=0;
            end
        end else begin
            param_valid<=0;select_valid<=0;spi_link_valid<=0;
            if(state==ST_RESET) begin
                if(reset_count>=RESET_HOLD_CYCLES-1) begin
                    reset_count<=0;chip_sel<=0;state<=ST_GAP;
                end else reset_count<=reset_count+1'b1;
            end else if(state==ST_GAP) begin
                if(gap_count>=HALF_DIV-1) begin gap_count<=0;state<=ST_START;end
                else gap_count<=gap_count+1'b1;
            end else if(state==ST_START) begin
                // Match the bench-verified probe exactly: keep CS asserted for
                // 64 clocks, transmit 82 00 00 00 00 00 00 00, and receive
                // status high/low followed by P0, P1, P2, P3, P4 and P5.
                byte_idx<=0;bit_idx<=0;rx_byte<=0;div_count<=0;tx_byte<=8'h82;state<=ST_LOW;
            end else if(state==ST_LOW) begin
                if(div_count>=HALF_DIV-1) begin div_count<=0;state<=ST_HIGH;end
                else div_count<=div_count+1'b1;
            end else if(state==ST_HIGH) begin
                if(div_count>=HALF_DIV-1) begin
                    div_count<=0;
                    if(bit_idx==7) begin
                        last_byte={rx_byte[6:0],sdo_d2};
                        rx_byte<=0;bit_idx<=0;tx_byte<=0;
                        case(byte_idx)
                            0:status_hi<=last_byte;
                            1:status_lo<=last_byte;
                            default:begin
                                if(!chip_sel) chip1_gpio[(byte_idx-2)*8 +: 8]<=last_byte;
                                else chip2_gpio[(byte_idx-2)*8 +: 8]<=last_byte;
                            end
                        endcase
                        if(byte_idx==7) state<=ST_END;
                        else begin byte_idx<=byte_idx+1'b1;state<=ST_LOW;end
                    end else begin
                        rx_byte<={rx_byte[6:0],sdo_d2};
                        bit_idx<=bit_idx+1'b1;state<=ST_LOW;
                    end
                end else div_count<=div_count+1'b1;
            end else if(state==ST_END) begin
                // Report first detection and changes only, once per burst.
                if(status_hi[7:6]!=2'b11 || status_lo!=8'h00) begin
                    if(!link_known[chip_sel] || link_up_state[chip_sel]) begin
                        spi_link_valid<=1;spi_link_chip<=chip_sel;spi_link_up<=0;
                    end
                    link_known[chip_sel]<=1;link_up_state[chip_sel]<=0;
                end else begin
                    if(!link_known[chip_sel] || !link_up_state[chip_sel]) begin
                        spi_link_valid<=1;spi_link_chip<=chip_sel;spi_link_up<=1;
                    end
                    link_known[chip_sel]<=1;link_up_state[chip_sel]<=1;
                end
                if(chip_sel) commit_pending<=1;
                chip_sel<=!chip_sel;gap_count<=0;state<=ST_GAP;
            end

            if(commit_pending) begin
                commit_pending<=0;next_pending_mask=pending_mask;next_pending_switch=pending_switch;
                snapshot_valid<=link_up_state;
                    for(i=0;i<32;i=i+1) begin
                        if(i<16) begin
                            old_a=get_gpio(prev_chip1_gpio,3*i);old_b=get_gpio(prev_chip1_gpio,3*i+1);
                            new_a=get_gpio(chip1_gpio,3*i);new_b=get_gpio(chip1_gpio,3*i+1);
                            new_sw=get_gpio(chip1_gpio,3*i+2);
                        end else begin
                            old_a=get_gpio(prev_chip2_gpio,3*(i-16));old_b=get_gpio(prev_chip2_gpio,3*(i-16)+1);
                            new_a=get_gpio(chip2_gpio,3*(i-16));new_b=get_gpio(chip2_gpio,3*(i-16)+1);
                            new_sw=get_gpio(chip2_gpio,3*(i-16)+2);
                        end
                        // A failed U2 must not suppress U1. Rebaseline only the
                        // failed/reconnected chip to avoid phantom actions.
                        if(!snapshot_valid[i/16] || !link_up_state[i/16]) begin
                            detent_accum[i]<=0;next_pending_mask[i]=0;next_pending_switch[i]=0;
                            switch_stable[i]<=new_sw;switch_last_raw[i]<=new_sw;switch_debounce[i]<=0;
                        end else begin
                        qstep=quad_step(old_a,old_b,new_a,new_b);
                        if(qstep==1) begin
                            if(detent_accum[i]>=3) begin
                                detent_accum[i]<=0;direction_cw[i]<=1;next_pending_mask[i]=1;
                                if(knob_value[i]<127) knob_value[i]<=knob_value[i]+1'b1;
                            end else detent_accum[i]<=detent_accum[i]+1'b1;
                        end else if(qstep==2) begin
                            if(detent_accum[i]<=-3) begin
                                detent_accum[i]<=0;direction_cw[i]<=0;next_pending_mask[i]=1;
                                if(knob_value[i]>0) knob_value[i]<=knob_value[i]-1'b1;
                            end else detent_accum[i]<=detent_accum[i]-1'b1;
                        end else if({old_a,old_b}!={new_a,new_b}) detent_accum[i]<=0;
                        if(new_sw==switch_last_raw[i]) begin
                            if(switch_debounce[i]<SWITCH_DEBOUNCE_SCANS) begin
                                switch_debounce[i]<=switch_debounce[i]+1'b1;
                                if(switch_debounce[i]==SWITCH_DEBOUNCE_SCANS-1 && switch_stable[i]!=new_sw) begin
                                    switch_stable[i]<=new_sw;next_pending_switch[i]=1;
                                    switch_action[i]<=new_sw?2'd2:2'd1;
                                end
                            end
                        end else begin switch_last_raw[i]<=new_sw;switch_debounce[i]<=0;end
                        end
                    end
                    prev_chip1_gpio<=chip1_gpio;prev_chip2_gpio<=chip2_gpio;
                pending_mask<=next_pending_mask;
                pending_switch<=next_pending_switch;
            end else begin
                emitted_mask=0;emitted_switch=0;
                for(i=0;i<32;i=i+1) begin
                    // Select exactly one event per output per cycle. Clearing
                    // every pending bit here used to lose all but the last ID.
                    if(emitted_mask==0 && pending_mask[i]) begin
                        param_valid<=1;param_id<=knob_param_id(i[4:0]);
                        param_val<=knob_value[i];param_cw<=direction_cw[i];emitted_mask[i]=1;
                    end
                    if(emitted_switch==0 && pending_switch[i]) begin
                        select_valid<=1;select_id<=knob_param_id(i[4:0]);
                        select_action<=switch_action[i];emitted_switch[i]=1;
                    end
                end
                pending_mask<=pending_mask & ~emitted_mask;
                pending_switch<=pending_switch & ~emitted_switch;
            end
        end
    end
endmodule
