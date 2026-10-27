`timescale 1ns/1ps
`include "params.vh"
module tb_knob_spi_burst;
    reg clk=0,rst_n=0,sdo=1;
    wire cs1,cs2,sclk,sdi,panel_reset,pv,pcw,sv,lv,lc,lu,tx;
    wire [7:0] pid,sid;
    wire [6:0] pval,ui_value;
    wire [1:0] action;
    reg [47:0] gpio[0:1];
    reg [1:0] connected=0;
    reg touch_valid=0;
    reg signed [7:0] touch_delta=0;
    reg [63:0] reply,command;
    integer bits=0,transactions=0,chip=0;
    integer motion[0:31],presses[0:31],releases[0:31];
    integer link_events=0,uart_lines=0,expected_count=0,uart_bytes=0;
    string expected_lines[0:511];
    reg expected_seen[0:511];
    string line_text="";
    integer b,k,idx,quiet_bytes,quiet_links,matched_line;
    reg [7:0] rx;
    always #500 clk=~clk;

    knob_spi_rx #(.CLK_HZ(1000000),.SPI_HZ(100000),.RESET_HOLD_CYCLES(10)) dut(
        .clk(clk),.rst_n(rst_n),.spi_sdo(sdo),.spi_int_n(1'b1),
        .spi_1cs_n(cs1),.spi_2cs_n(cs2),.spi_sclk(sclk),.spi_sdi(sdi),.panel_reset_n(panel_reset),
        .param_valid(pv),.param_id(pid),.param_val(pval),.param_cw(pcw),
        .select_valid(sv),.select_id(sid),.select_action(action),
        .spi_link_valid(lv),.spi_link_chip(lc),.spi_link_up(lu));
    param_merger merge(.clk(clk),.rst_n(rst_n),
        .spi_param_valid(1'b0),.spi_param_id(8'd0),.spi_param_val(7'd0),
        .touch_delta_valid(pv|touch_valid),.touch_selected_id(touch_valid?`PARAM_ID_OSCA_WT_POS:pid),
        .touch_delta_val(touch_valid?touch_delta:(pcw?8'sd1:-8'sd1)),
        .curve_update_valid(1'b0),.curve_update_filter(1'b0),.curve_update_tab(2'd0),
        .curve_update_mask(5'd0),.curve_update_values(35'd0),.midi_tx_busy(1'b0),
        .btn_tap_valid(1'b0),.btn_tap_id(8'd0),.btn_tap_action(2'd0),.val_osca_wt_pos(ui_value));
    knob_ascii_trace #(.CLK_FREQ(1000000),.BAUD(100000),.FIFO_BITS(7)) logger(
        .clk(clk),.rst_n(rst_n),.knob_valid(pv),.knob_id(pid),.knob_cw(pcw),
        .button_valid(sv),.button_id(sid),.button_action(action),
        .link_valid(lv),.link_chip(lc),.link_up(lu),.uart_tx(tx));

    // Board specification, independent of the DUT's internal state/port index.
    function [7:0] expected_id(input integer n);
        begin
            case(n)
                0:expected_id=`PARAM_ID_OSCA_WT_POS; 1:expected_id=`PARAM_ID_OSCA_WARP;
                2:expected_id=`PARAM_ID_OSCA_PAN; 3:expected_id=`PARAM_ID_OSCA_VOL;
                4:expected_id=`PARAM_ID_OSCA_UNISON; 5:expected_id=`PARAM_ID_OSCA_DETUNE;
                6:expected_id=`PARAM_ID_OSCA_BLEND; 7:expected_id=`PARAM_ID_OSCA_PHASE;
                8:expected_id=`PARAM_ID_ENV1_ATTACK; 9:expected_id=`PARAM_ID_ENV1_HOLD;
                10:expected_id=`PARAM_ID_ENV1_DECAY; 11:expected_id=`PARAM_ID_ENV1_SUSTAIN;
                12:expected_id=`PARAM_ID_ENV1_RELEASE; 13:expected_id=`PARAM_ID_MASTER_VOL;
                14:expected_id=`PARAM_ID_MACRO1; 15:expected_id=`PARAM_ID_MACRO2;
                16:expected_id=`PARAM_ID_OSCB_WT_POS; 17:expected_id=`PARAM_ID_OSCB_WARP;
                18:expected_id=`PARAM_ID_OSCB_PAN; 19:expected_id=`PARAM_ID_OSCB_VOL;
                20:expected_id=`PARAM_ID_OSCB_UNISON; 21:expected_id=`PARAM_ID_OSCB_DETUNE;
                22:expected_id=`PARAM_ID_OSCB_BLEND; 23:expected_id=`PARAM_ID_OSCB_PHASE;
                24:expected_id=`PARAM_ID_FLT_CUTOFF; 25:expected_id=`PARAM_ID_FLT_RES;
                26:expected_id=`PARAM_ID_FLT_PAN; 27:expected_id=`PARAM_ID_FLT_DRIVE;
                28:expected_id=`PARAM_ID_FLT_FAT; 29:expected_id=`PARAM_ID_FLT_MIX;
                30:expected_id=`PARAM_ID_FX_REVERB; 31:expected_id=`PARAM_ID_FX_DELAY;
            endcase
        end
    endfunction
    task start_frame(input integer n);
        begin
            if(!cs1 && !cs2) $fatal(1,"Both TXE8148 chips selected");
            chip=n;bits=0;command=0;
            // A real burst returns status high/low, then P0 through P5.
            reply=connected[n] ? {8'hC0,8'h00,gpio[n][7:0],gpio[n][15:8],gpio[n][23:16],
                                  gpio[n][31:24],gpio[n][39:32],gpio[n][47:40]} : 64'hFFFFFFFFFFFFFFFF;
            sdo=reply[63];
        end
    endtask
    always @(negedge cs1) if(rst_n) start_frame(0);
    always @(negedge cs2) if(rst_n) start_frame(1);
    always @(posedge sclk) if(rst_n && (!cs1 || !cs2)) begin
        if(bits>=64) $fatal(1,"More than 64 clocks in TXE8148 burst");
        command={command[62:0],sdi};bits=bits+1;
    end
    always @(negedge sclk) if(rst_n && (!cs1 || !cs2) && bits<64) sdo=reply[63-bits];
    task end_frame;
        begin
            if(bits!=64) $fatal(1,"TXE8148 requires 64 clocks under one CS; got %0d",bits);
            if(command!==64'h8200000000000000) $fatal(1,"Wrong TXE8148 command: %h",command);
            transactions=transactions+1;
        end
    endtask
    always @(posedge cs1) if(rst_n && bits>0) end_frame();
    always @(posedge cs2) if(rst_n && bits>0) end_frame();

    always @(posedge clk) if(rst_n) begin
        if(lv) link_events=link_events+1;
        if(pv || sv) begin
            idx=-1;
            for(integer n=0;n<32;n=n+1) if(expected_id(n)==(pv?pid:sid)) idx=n;
            if(idx<0) $fatal(1,"Unmapped knob event");
            if(pv) motion[idx]=motion[idx]+(pcw?1:-1);
            if(sv) begin
                // Rotation and switch channels may refer to different knobs.
                for(integer n=0;n<32;n=n+1) if(expected_id(n)==sid) idx=n;
                if(action==1) presses[idx]=presses[idx]+1;
                else if(action==2) releases[idx]=releases[idx]+1;
                else $fatal(1,"Invalid switch action");
            end
        end
    end
    always @(negedge tx) if(rst_n) begin
        #5000;
        for(b=0;b<8;b=b+1) begin #10000;rx[b]=tx;end
        #10000;
        uart_bytes=uart_bytes+1;
        if(rx==10) begin
            // The two chips are sampled sequentially, so simultaneous physical
            // actions may reach the next scan in either chip order.
            matched_line=-1;
            for(integer n=0;n<expected_count;n=n+1)
                if(matched_line<0 && !expected_seen[n] && line_text==expected_lines[n]) matched_line=n;
            if(matched_line<0) $fatal(1,"Unexpected or duplicate UART line: %s",line_text);
            expected_seen[matched_line]=1;
            uart_lines=uart_lines+1;line_text="";
        end else if(rx!=13) line_text={line_text,rx};
    end
    task expect_line(input string value);
        begin
            expected_lines[expected_count]=value;expected_seen[expected_count]=0;
            expected_count=expected_count+1;
        end
    endtask
    task wait_ms(input integer ms);
        begin repeat(ms*1000) @(negedge clk);end
    endtask
    task all_ab(input [1:0] ab);
        begin
            for(integer n=0;n<16;n=n+1) begin
                gpio[0][3*n]=ab[1];gpio[0][3*n+1]=ab[0];
                gpio[1][3*n]=ab[1];gpio[1][3*n+1]=ab[0];
            end
            wait_ms(3);
        end
    endtask
    task k01_detent(input bit clockwise);
        begin
            gpio[0][1:0]=clockwise?2'b01:2'b10;wait_ms(3);
            gpio[0][1:0]=0;wait_ms(3);
            gpio[0][1:0]=clockwise?2'b10:2'b01;wait_ms(3);
            gpio[0][1:0]=3;wait_ms(3);
        end
    endtask
    task touch_k01(input signed [7:0] delta);
        begin
            @(negedge clk);touch_valid=1;touch_delta=delta;
            @(negedge clk);touch_valid=0;repeat(5) @(negedge clk);
        end
    endtask
    task drain_and_quiet;
        begin
            wait_ms(100);
            if(uart_lines!=expected_count) $fatal(1,"Missing UART events: %0d/%0d",uart_lines,expected_count);
            quiet_bytes=uart_bytes;quiet_links=link_events;
            wait_ms(10);
            if(uart_bytes!=quiet_bytes || link_events!=quiet_links) $fatal(1,"Idle heartbeat/status repeated");
        end
    endtask
    initial begin
        gpio[0]=48'hFFFFFFFFFFFF;gpio[1]=48'hFFFFFFFFFFFF;
        for(k=0;k<32;k=k+1) begin motion[k]=0;presses[k]=0;releases[k]=0;end
        expect_line("U1 SPI DISCONNECTED");expect_line("U2 SPI DISCONNECTED");
        #2500;rst_n=1;wait_ms(10);
        expect_line("U1 SPI CONNECTED");expect_line("U2 SPI CONNECTED");
        connected=3;wait_ms(10);
        // All 32 detents in one scan must survive arbitration/FIFO buffering.
        for(k=0;k<32;k=k+1) expect_line($sformatf("K%02d CW U%0d",k+1,k<16?1:2));
        all_ab(2'b10);all_ab(2'b00);all_ab(2'b01);all_ab(2'b11);
        drain_and_quiet();
        if(ui_value!==1) $fatal(1,"Physical K01 did not increment the shared UI parameter");
        for(k=0;k<32;k=k+1) if(motion[k]!=1) $fatal(1,"Missing CW knob %0d",k+1);
        for(k=0;k<32;k=k+1) expect_line($sformatf("K%02d CCW U%0d",k+1,k<16?1:2));
        all_ab(2'b01);all_ab(2'b00);all_ab(2'b10);all_ab(2'b11);
        drain_and_quiet();
        if(ui_value!==0) $fatal(1,"Physical K01 did not decrement the same UI parameter");
        for(k=0;k<32;k=k+1) if(motion[k]!=0) $fatal(1,"Missing CCW knob %0d",k+1);
        for(k=0;k<32;k=k+1) begin
            expect_line($sformatf("K%02d PRESS U%0d",k+1,k<16?1:2));
            gpio[k/16][3*(k%16)+2]=0;
        end
        drain_and_quiet();
        for(k=0;k<32;k=k+1) begin
            expect_line($sformatf("K%02d RELEASE U%0d",k+1,k<16?1:2));
            gpio[k/16][3*(k%16)+2]=1;
        end
        drain_and_quiet();
        for(k=0;k<32;k=k+1) if(presses[k]!=1 || releases[k]!=1) $fatal(1,"Lost switch edge knob %0d",k+1);
        // One failed chip must not disable the other chip's controls.
        expect_line("U2 SPI DISCONNECTED");connected=1;wait_ms(10);
        expect_line("K01 CW U1");
        k01_detent(1);
        drain_and_quiet();
        if(ui_value!==1 || motion[0]!=1) $fatal(1,"Healthy U1 blocked by U2 failure");
        expect_line("U2 SPI CONNECTED");connected=3;drain_and_quiet();
        if(link_events!=6) $fatal(1,"Repeated/missing link transitions: %0d",link_events);
        // Touch and physical controls must use the SAME live value, including
        // saturation. The receiver's legacy cached value must never replace it.
        touch_k01(126);
        if(ui_value!==127) $fatal(1,"Touch did not set shared value to 127");
        expect_line("K01 CW U1");k01_detent(1);
        if(ui_value!==127) $fatal(1,"Physical CW did not saturate at 127");
        touch_k01(-100);
        expect_line("K01 CW U1");k01_detent(1);
        if(ui_value!==28) $fatal(1,"Physical CW jumped from the touch value");
        expect_line("K01 CCW U1");k01_detent(0);
        if(ui_value!==27) $fatal(1,"Physical CCW jumped from the touch value");
        touch_k01(-100);
        expect_line("K01 CCW U1");k01_detent(0);
        if(ui_value!==0) $fatal(1,"Physical CCW did not saturate at zero");
        drain_and_quiet();
        $display("PASS: strict 0x82 + seven-zero-byte/64-clock SPI bursts; all 32 CW/CCW/PRESS/RELEASE ASCII lines; shared touch/physical values and clamps; independent chip disconnect/reconnect; no idle output (%0d frames, %0d lines)",transactions,uart_lines);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"Integration timeout");end
endmodule
