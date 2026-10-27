`timescale 1ns/1ps
module tb_knob_spi_rx;
    reg clk=0,rst_n=0,sdo=1,int_n=1;
    wire cs2,cs1,sclk,sdi,reset_n;
    wire pv,pcw,sv,linkv,linkchip,linkup;
    wire [7:0] pid,sid;
    wire [6:0] pval;
    wire [1:0] sa;
    wire [6:0] ui_osca_wt_pos;
    wire midi_req;
    wire [7:0] midi_id;
    wire [6:0] midi_value;
    reg [7:0] p0_u1=8'hFF,p1_u1=8'hFF,p2_u1=8'hFF,p3_u1=8'hFF,p4_u1=8'hFF,p5_u1=8'hFF;
    reg [7:0] p0_u2=8'hFF,p1_u2=8'hFF,p2_u2=8'hFF,p3_u2=8'hFF,p4_u2=8'hFF,p5_u2=8'hFF;
    reg link_ok=1'b1;
    reg [63:0] reply=0;
    integer bitpos=0;
    integer cw_count=0,ccw_count=0,press_count=0,released_count=0,link_up_count=0,link_down_count=0;

    always #500 clk=~clk; // 1 MHz simulation clock

    knob_spi_rx #(.CLK_HZ(1000000),.SPI_HZ(100000),.RESET_HOLD_CYCLES(10),.SWITCH_DEBOUNCE_SCANS(5)) dut(
        .clk(clk),.rst_n(rst_n),.spi_sdo(sdo),.spi_int_n(int_n),
        .spi_2cs_n(cs2),.spi_1cs_n(cs1),.spi_sclk(sclk),.spi_sdi(sdi),.panel_reset_n(reset_n),
        .param_valid(pv),.param_id(pid),.param_val(pval),.param_cw(pcw),
        .select_valid(sv),.select_id(sid),.select_action(sa),
        .spi_link_valid(linkv),.spi_link_chip(linkchip),.spi_link_up(linkup));

    param_merger merge(
        .clk(clk),.rst_n(rst_n),
        .spi_param_valid(1'b0),.spi_param_id(8'd0),.spi_param_val(7'd0),
        .touch_delta_valid(pv),.touch_selected_id(pid),
        .touch_delta_val(pcw?8'sd1:-8'sd1),
        .curve_update_valid(1'b0),.curve_update_filter(1'b0),.curve_update_tab(2'd0),
        .curve_update_mask(5'd0),.curve_update_values(35'd0),.midi_tx_busy(1'b0),
        .btn_tap_valid(1'b0),.btn_tap_id(8'd0),.btn_tap_action(2'd0),
        .val_osca_wt_pos(ui_osca_wt_pos),.midi_cc_req(midi_req),
        .midi_cc_param_id(midi_id),.midi_cc_val(midi_value));

    task load_reply;
        begin
            if(!cs1) reply={link_ok?8'hC0:8'h00,8'h00,p0_u1,p1_u1,p2_u1,p3_u1,p4_u1,p5_u1};
            else reply={link_ok?8'hC0:8'h00,8'h00,p0_u2,p1_u2,p2_u2,p3_u2,p4_u2,p5_u2};
            bitpos=0;
            sdo=reply[63];
        end
    endtask

    always @(negedge cs1) load_reply();
    always @(negedge cs2) load_reply();
    always @(negedge sclk) begin
        if(!cs1 || !cs2) begin
            if(bitpos<63) bitpos=bitpos+1;
            sdo=reply[63-bitpos];
        end
    end

    always @(posedge clk) if(rst_n) begin
        if(pv && pid==8'h17) begin
            if(pcw) cw_count=cw_count+1; else ccw_count=ccw_count+1;
        end
        if(sv && sid==8'h17) begin
            if(sa==1) press_count=press_count+1;
            if(sa==2) released_count=released_count+1;
        end
        if(linkv) begin
            if(linkup) link_up_count=link_up_count+1; else link_down_count=link_down_count+1;
        end
    end

    task wait_ms(input integer ms);
        begin repeat(ms*1000) @(negedge clk); end
    endtask

    initial begin
        #2500;rst_n=1;
        wait_ms(8); // reset release and baseline snapshot
        // One CW detent: AB 11 -> 10 -> 00 -> 01 -> 11. SW stays high.
        p0_u1=8'hFD;wait_ms(3);
        p0_u1=8'hFC;wait_ms(3);
        p0_u1=8'hFE;wait_ms(3);
        p0_u1=8'hFF;wait_ms(5);
        if(cw_count!=1 || ccw_count!=0) $fatal(1,"K01 CW detent decode failed CW=%0d CCW=%0d",cw_count,ccw_count);
        if(ui_osca_wt_pos!==7'd1) $fatal(1,"K01 did not update live UI parameter: %0d",ui_osca_wt_pos);
        // Active-low K01 switch press and release, debounced over 5 snapshots.
        p0_u1=8'hFB;wait_ms(25);
        p0_u1=8'hFF;wait_ms(25);
        if(press_count!=1 || released_count!=1) $fatal(1,"K01 switch edges failed press=%0d release=%0d",press_count,released_count);
        if(link_up_count!=2 || link_down_count!=0) $fatal(1,"Initial dual-chip link report failed up=%0d down=%0d",link_up_count,link_down_count);
        // Simulate both expanders unplugged and restored. Link reports are
        // transition-only: one event per chip per transition, no heartbeat.
        link_ok=0;wait_ms(10);
        if(link_down_count!=2) $fatal(1,"Disconnect reports failed: %0d",link_down_count);
        link_ok=1;wait_ms(10);
        if(link_up_count!=4 || link_down_count!=2) $fatal(1,"Reconnect reports failed up=%0d down=%0d",link_up_count,link_down_count);
        $display("PASS: TXE8148 SPI timing/status, K01 CW, press/release and link transition checks");
        $display("COUNTS CW=%0d CCW=%0d PRESS=%0d RELEASE=%0d LINK_UP=%0d LINK_DOWN=%0d",cw_count,ccw_count,press_count,released_count,link_up_count,link_down_count);
        $finish;
    end
    initial begin #200000000;$fatal(1,"Timeout");end
endmodule
