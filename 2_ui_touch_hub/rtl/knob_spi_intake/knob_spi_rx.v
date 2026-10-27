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
    reg [2:0] port_idx;
    reg [4:0] bit_idx;
    reg [23:0] tx_frame,rx_shift;
    reg sdo_d1,sdo_d2,int_d1,int_d2;
    reg [47:0] chip1_gpio,chip2_gpio,prev_chip1_gpio,prev_chip2_gpio;
    reg snapshot_valid,commit_pending;
    reg [31:0] pending_mask,next_pending_mask,emitted_mask;
    reg direction_cw [0:31];
    reg signed [2:0] detent_accum [0:31];
    reg [6:0] knob_value [0:31];
    reg switch_stable [0:31],switch_last_raw [0:31];
    reg [2:0] switch_debounce [0:31];
    reg [1:0] link_known,link_up_state;
    reg [1:0] qstep;
    reg old_a,old_b,new_a,new_b,old_sw,new_sw;
    integer i;

    assign panel_reset_n = (state != ST_RESET);
    assign spi_1cs_n = !((state==ST_LOW || state==ST_HIGH || state==ST_END) && !chip_sel);
    assign spi_2cs_n = !((state==ST_LOW || state==ST_HIGH || state==ST_END) && chip_sel);
    assign spi_sclk = (state==ST_HIGH);
    assign spi_sdi = (state==ST_LOW || state==ST_HIGH) ? tx_frame[23-bit_idx] : 1'b0;

    function [23:0] make_read_frame;
        input [2:0] port;
        begin make_read_frame={8'h82,{port,4'b0000},8'h00}; end
    endfunction
    function get_gpio;
        input [47:0] gpio;
        input integer bit_number;
        begin get_gpio=gpio[bit_number]; end
    endfunction
    function [7:0] map_knob_to_param_id;
        input [4:0] knob;
        begin
            case(knob)
                5'd0:map_knob_to_param_id=`PARAM_ID_OSCA_WT_POS;
                5'd1:map_knob_to_param_id=`PARAM_ID_OSCA_WARP;
                5'd2:map_knob_to_param_id=`PARAM_ID_OSCA_PAN;
                5'd3:map_knob_to_param_id=`PARAM_ID_OSCA_VOL;
                5'd4:map_knob_to_param_id=`PARAM_ID_OSCA_UNISON;
                5'd5:map_knob_to_param_id=`PARAM_ID_OSCA_DETUNE;
                5'd6:map_knob_to_param_id=`PARAM_ID_OSCA_BLEND;
                5'd7:map_knob_to_param_id=`PARAM_ID_OSCA_PHASE;
                5'd8:map_knob_to_param_id=`PARAM_ID_ENV1_ATTACK;
                5'd9:map_knob_to_param_id=`PARAM_ID_ENV1_HOLD;
                5'd10:map_knob_to_param_id=`PARAM_ID_ENV1_DECAY;
                5'd11:map_knob_to_param_id=`PARAM_ID_ENV1_SUSTAIN;
                5'd12:map_knob_to_param_id=`PARAM_ID_ENV1_RELEASE;
                5'd13:map_knob_to_param_id=`PARAM_ID_MASTER_VOL;
                5'd14:map_knob_to_param_id=`PARAM_ID_MACRO1;
                5'd15:map_knob_to_param_id=`PARAM_ID_MACRO2;
                5'd16:map_knob_to_param_id=`PARAM_ID_OSCB_WT_POS;
                5'd17:map_knob_to_param_id=`PARAM_ID_OSCB_WARP;
                5'd18:map_knob_to_param_id=`PARAM_ID_OSCB_PAN;
                5'd19:map_knob_to_param_id=`PARAM_ID_OSCB_VOL;
                5'd20:map_knob_to_param_id=`PARAM_ID_OSCB_UNISON;
                5'd21:map_knob_to_param_id=`PARAM_ID_OSCB_DETUNE;
                5'd22:map_knob_to_param_id=`PARAM_ID_OSCB_BLEND;
                5'd23:map_knob_to_param_id=`PARAM_ID_OSCB_PHASE;
                5'd24:map_knob_to_param_id=`PARAM_ID_FLT_CUTOFF;
                5'd25:map_knob_to_param_id=`PARAM_ID_FLT_RES;
                5'd26:map_knob_to_param_id=`PARAM_ID_FLT_PAN;
                5'd27:map_knob_to_param_id=`PARAM_ID_FLT_DRIVE;
                5'd28:map_knob_to_param_id=`PARAM_ID_FLT_FAT;
                5'd29:map_knob_to_param_id=`PARAM_ID_FLT_MIX;
                5'd30:map_knob_to_param_id=`PARAM_ID_FX_REVERB;
                5'd31:map_knob_to_param_id=`PARAM_ID_FX_DELAY;
                default:map_knob_to_param_id=`PARAM_ID_NONE;
            endcase
        end
    endfunction
    function [1:0] quad_step;
        input oa,ob,na,nb;
        begin
            case({oa,ob,na,nb})
                4'b0001,4'b0111,4'b1110,4'b1000:quad_step=2'd1;
                4'b0010,4'b1011,4'b1101,4'b0100:quad_step=2'd2;
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
            port_idx<=0;bit_idx<=0;tx_frame<=make_read_frame(0);rx_shift<=0;
            chip1_gpio<=0;chip2_gpio<=0;prev_chip1_gpio<=0;prev_chip2_gpio<=0;
            snapshot_valid<=0;commit_pending<=0;pending_mask<=0;link_known<=0;link_up_state<=0;
            param_valid<=0;param_id<=`PARAM_ID_NONE;param_val<=64;param_cw<=1;
            select_valid<=0;select_id<=`PARAM_ID_NONE;select_action<=0;
            spi_link_valid<=0;spi_link_chip<=0;spi_link_up<=0;
            for(i=0;i<32;i=i+1) begin
                direction_cw[i]<=1;detent_accum[i]<=0;knob_value[i]<=64;
                switch_stable[i]<=1;switch_last_raw[i]<=1;switch_debounce[i]<=5;
            end
        end else begin
            param_valid<=0;select_valid<=0;spi_link_valid<=0;
            if(state==ST_RESET) begin
                if(reset_count>=RESET_HOLD_CYCLES-1) begin
                    reset_count<=0;chip_sel<=0;port_idx<=0;bit_idx<=0;tx_frame<=make_read_frame(0);state<=ST_GAP;
                end else reset_count<=reset_count+1'b1;
            end else if(state==ST_GAP) begin
                if(gap_count>=HALF_DIV-1) begin gap_count<=0;div_count<=0;bit_idx<=0;rx_shift<=0;state<=ST_LOW;end
                else gap_count<=gap_count+1'b1;
            end else if(state==ST_START) begin
                bit_idx<=0;rx_shift<=0;div_count<=0;tx_frame<=make_read_frame(port_idx);state<=ST_LOW;
            end else if(state==ST_LOW) begin
                if(div_count>=HALF_DIV-1) begin div_count<=0;state<=ST_HIGH;end
                else div_count<=div_count+1'b1;
            end else if(state==ST_HIGH) begin
                if(div_count>=HALF_DIV-1) begin
                    div_count<=0;
                    rx_shift<={rx_shift[22:0],sdo_d2};
                    if(bit_idx==5'd23) state<=ST_END;
                    else begin bit_idx<=bit_idx+1'b1;state<=ST_LOW;end
                end else div_count<=div_count+1'b1;
            end else if(state==ST_END) begin
                if(!chip_sel) begin
                    case(port_idx)
                        0:chip1_gpio[7:0]<=rx_shift[7:0];
                        1:chip1_gpio[15:8]<=rx_shift[7:0];
                        2:chip1_gpio[23:16]<=rx_shift[7:0];
                        3:chip1_gpio[31:24]<=rx_shift[7:0];
                        4:chip1_gpio[39:32]<=rx_shift[7:0];
                        default:chip1_gpio[47:40]<=rx_shift[7:0];
                    endcase
                end else begin
                    case(port_idx)
                        0:chip2_gpio[7:0]<=rx_shift[7:0];
                        1:chip2_gpio[15:8]<=rx_shift[7:0];
                        2:chip2_gpio[23:16]<=rx_shift[7:0];
                        3:chip2_gpio[31:24]<=rx_shift[7:0];
                        4:chip2_gpio[39:32]<=rx_shift[7:0];
                        default:begin chip2_gpio[47:40]<=rx_shift[7:0];commit_pending<=1;end
                    endcase
                end
                if(port_idx==5) begin
                    // Judge connection only once per complete six-port chip
                    // scan. This avoids link flapping on one noisy register.
                    if(rx_shift[23:22]!=2'b11 || rx_shift[15:8]!=8'h00) begin
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
                    if(!chip_sel) begin chip_sel<=1;port_idx<=0;state<=ST_START;end
                    else begin chip_sel<=0;port_idx<=0;gap_count<=0;state<=ST_GAP;end
                end else begin
                    port_idx<=port_idx+1'b1;
                    tx_frame<=make_read_frame(port_idx+1'b1);
                    gap_count<=0;state<=ST_GAP;
                end
            end

            if(commit_pending) begin
                commit_pending<=0;next_pending_mask=pending_mask;
                if(!snapshot_valid || link_up_state!=2'b11) begin
                    prev_chip1_gpio<=chip1_gpio;prev_chip2_gpio<=chip2_gpio;
                    snapshot_valid<=(link_up_state==2'b11);
                    next_pending_mask=0;
                    for(i=0;i<32;i=i+1) begin
                        detent_accum[i]<=0;
                        if(i<16) begin
                            switch_stable[i]<=get_gpio(chip1_gpio,3*i+2);
                            switch_last_raw[i]<=get_gpio(chip1_gpio,3*i+2);
                        end else begin
                            switch_stable[i]<=get_gpio(chip2_gpio,3*(i-16)+2);
                            switch_last_raw[i]<=get_gpio(chip2_gpio,3*(i-16)+2);
                        end
                        switch_debounce[i]<=5;
                    end
                end else begin
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
                        end
                        if(new_sw==switch_last_raw[i]) begin
                            if(switch_debounce[i]<SWITCH_DEBOUNCE_SCANS) begin
                                switch_debounce[i]<=switch_debounce[i]+1'b1;
                                if(switch_debounce[i]==SWITCH_DEBOUNCE_SCANS-1 && switch_stable[i]!=new_sw) begin
                                    switch_stable[i]<=new_sw;select_valid<=1;
                                    select_id<=map_knob_to_param_id(i[4:0]);
                                    select_action<=new_sw?2'd2:2'd1;
                                end
                            end
                        end else begin switch_last_raw[i]<=new_sw;switch_debounce[i]<=0;end
                    end
                    prev_chip1_gpio<=chip1_gpio;prev_chip2_gpio<=chip2_gpio;
                end
                pending_mask<=next_pending_mask;
            end else begin
                emitted_mask=0;
                for(i=0;i<32;i=i+1) begin
                    if(!emitted_mask[i] && pending_mask[i]) begin
                        param_valid<=1;param_id<=map_knob_to_param_id(i[4:0]);
                        param_val<=knob_value[i];param_cw<=direction_cw[i];emitted_mask[i]=1;
                    end
                end
                pending_mask<=pending_mask & ~emitted_mask;
            end
        end
    end
endmodule
