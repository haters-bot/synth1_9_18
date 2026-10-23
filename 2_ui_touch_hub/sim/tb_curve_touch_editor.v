`timescale 1ns/1ps
`include "params.vh"
module tb_curve_touch_editor;
    reg clk=0,rst_n=0,tv=0,td=0;
    reg [15:0] raw_x=0,raw_y=0;
    wire uv,ud,cap,fv,cv,cf,dv,bv,mreq,busy,uart;
    wire [13:0] ux,uy;
    wire [7:0] fid,selected,bid,mid;
    wire [1:0] ct,ba,tab,ft;
    wire [4:0] cm;
    wire [34:0] values;
    wire signed [7:0] delta;
    wire [6:0] cut,res,a,h,d,s,r,mval;
    reg spi_v=0;
    reg [7:0] spi_id=0;
    reg [6:0] spi_val=0;
    reg force_busy=0,manual_valid=0;
    reg [34:0] manual_values=0;
    integer cc_count=0,last_cc[0:127],byte_count=0,cc_num=0;
    reg [7:0] rxbyte;
    integer bit_i,j,nx,ny,saved_count,start_x,start_y,env1_a,env1_h,env1_d,env1_s,env1_r,env2_a;
    integer spans[0:5];
    always #8 clk=~clk;
    // Full-precision test geometry for the approved compact ENV layout.
    // Do not obtain gesture coordinates from internal DUT registers: that
    // could hide the same node-placement error in both renderer and editor.
    function integer attack_x;
        input integer value;
        begin attack_x=46+value*65/128;end
    endfunction
    function integer hold_x;
        input integer av,hv;
        begin hold_x=attack_x(av)+hv*30/128;end
    endfunction
    function integer decay_x;
        input integer av,hv,dv;
        begin decay_x=hold_x(av,hv)+12+dv*80/128;end
    endfunction
    function integer sustain_y;
        input integer value;
        begin sustain_y=568-value*144/128;end
    endfunction
    touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_state(td),
        .raw_touch_x(raw_x),.raw_touch_y(raw_y),
        .curve_capture_active(cap),.curve_focus_valid(fv),.curve_focus_id(fid),
        .ui_touch_valid(uv),.ui_touch_down(ud),.ui_touch_x(ux),.ui_touch_y(uy),
        .param_delta_valid(dv),.param_delta_val(delta),.selected_param_id(selected),
        .btn_tap_valid(bv),.btn_tap_id(bid),.btn_tap_action(ba));
    curve_touch_editor #(.WATCHDOG_CYCLES(1024)) editor(.clk(clk),.rst_n(rst_n),
        .touch_valid(uv),.touch_down(ud),.touch_x(ux),.touch_y(uy),
        .cutoff(cut),.resonance(res),.filter_type(ft),.env_tab(tab),
        .attack(a),.hold(h),.decay(d),.sustain(s),.release_v(r),
        .capture_active(cap),.focus_valid(fv),.focus_id(fid),
        .update_valid(cv),.update_filter(cf),.update_tab(ct),.update_mask(cm),.update_values(values));
    param_merger bank(.clk(clk),.rst_n(rst_n),
        .spi_param_valid(spi_v),.spi_param_id(spi_id),.spi_param_val(spi_val),
        .touch_delta_valid(dv),.touch_selected_id(selected),.touch_delta_val(delta),
        .btn_tap_valid(bv),.btn_tap_id(bid),.btn_tap_action(ba),
        .curve_update_valid(cv|manual_valid),.curve_update_filter(manual_valid ? 1'b1 : cf),
        .curve_update_tab(ct),.curve_update_mask(manual_valid ? 5'b00011 : cm),
        .curve_update_values(manual_valid ? manual_values : values),.midi_tx_busy(busy|force_busy),
        .val_flt_cutoff(cut),.val_flt_res(res),.val_flt_type(ft),.val_env_tab(tab),
        .val_env_attack(a),.val_env_hold(h),.val_env_decay(d),.val_env_sustain(s),.val_env_release(r),
        .midi_cc_req(mreq),.midi_cc_param_id(mid),.midi_cc_val(mval));
    // Real UART/FIFO, accelerated 200x while retaining the registered interface.
    midi_uart_tx #(.CLK_FREQ(1000000),.BAUD(100000)) tx(
        .clk(clk),.rst_n(rst_n),.note_on_req(1'b0),.note_off_req(1'b0),
        .note_number(7'd0),.note_velocity(7'd0),.cc_req(mreq),.cc_param_id(mid),.cc_val(mval),
        .uart_tx(uart),.tx_busy(busy));
    // Decode bytes from the actual serial pin, independent of internal FIFO state.
    initial forever begin
        @(negedge uart);
        if(rst_n) begin
            #80;
            if(uart!==0) $fatal(1,"Invalid UART start bit");
            for(bit_i=0;bit_i<8;bit_i=bit_i+1) begin #160;rxbyte[bit_i]=uart;end
            #160;if(uart!==1) $fatal(1,"Invalid UART stop bit");
            if(byte_count==0) begin
                if(rxbyte!==8'hBF) $fatal(1,"Wrong MIDI status %h",rxbyte);
                byte_count=1;
            end else if(byte_count==1) begin cc_num=rxbyte;byte_count=2;end
            else begin last_cc[cc_num]=rxbyte;cc_count=cc_count+1;byte_count=0;end
        end
    end
    task packet;
        input integer px,py;
        input pressed;
        begin
            @(negedge clk);raw_x=(px*65536+5119)/5120;raw_y=(py*65536+4914)/4915;
            tv=1;td=pressed;
            @(negedge clk);tv=0;
            repeat(20) @(negedge clk);
        end
    endtask
    task up;begin packet(0,0,0);end endtask
    task click;
        input integer px,py;
        begin packet(px,py,1);packet(px,py,0);end
    endtask
    task spi;
        input [7:0] id;
        input [6:0] value;
        begin
            @(negedge clk);spi_v=1;spi_id=id;spi_val=value;
            @(negedge clk);spi_v=0;repeat(3) @(negedge clk);
        end
    endtask
    task drain;
        begin
            repeat(9000) @(negedge clk);
            if(busy || bank.curve_midi_pending!=0) $fatal(1,"Pending curve MIDI did not drain");
        end
    endtask
    initial begin
        for(j=0;j<128;j=j+1) last_cc[j]=-1;
        repeat(4) @(negedge clk);rst_n=1;repeat(4) @(negedge clk);
        packet(1073,151,1);
        if(!cap || cut!=80 || res!=32) $fatal(1,"Filter press jumped parameters");
        packet(1101,151,1);
        if(cut!=93 || res!=32) $fatal(1,"Filter X moved wrong axis: %d %d",cut,res);
        packet(1101,140,1);
        if(cut!=93 || res!=64) $fatal(1,"Filter XY failed: %d %d",cut,res);
        packet(1073,151,1);
        if(cut!=80 || res!=32) $fatal(1,"Return-to-anchor did not restore exact parameter values");
        packet(1101,140,1);up;drain;
        if(last_cc[43]!=93 || last_cc[44]!=64) $fatal(1,"Filter XY MIDI lost a parameter");
        packet(1073,151,1);packet(168,385,1);
        if(tab!=0) $fatal(1,"Curve excursion activated ENV tab");
        packet(1279,0,1);
        if(cut!=127 || res!=127) $fatal(1,"Filter upper saturation failed");
        packet(0,719,1);
        if(cut!=0 || res!=0) $fatal(1,"Filter lower saturation failed");
        up;drain;

        packet(66,424,1);
        if(!cap || fid!=`PARAM_ID_ENV1_ATTACK) $fatal(1,"Attack handle not selected");
        packet(92,424,1);up;
        if(a!=61 || h!=0 || d!=40 || s!=90 || r!=35) $fatal(1,"Attack drag changed unrelated stages: %0d/%0d/%0d/%0d/%0d",a,h,d,s,r);
        start_x=hold_x(a,h);
        packet(start_x,412,1);
        if(fid!=`PARAM_ID_ENV1_HOLD) $fatal(1,"Zero-Hold handle could not be selected separately");
        packet(start_x+30,412,1);up;
        if(h!=127 || a!=61) $fatal(1,"Hold drag failed h=%d a=%d",h,a);
        start_x=decay_x(a,h,d);start_y=sustain_y(s);
        packet(start_x,start_y,1);packet(start_x+40,start_y-36,1);up;
        if(d!=104 || s!=122 || a!=61 || h!=127 || r!=35)
            $fatal(1,"Decay XY failed or changed unrelated stages: %0d/%0d/%0d/%0d/%0d",a,h,d,s,r);
        env1_d=d;env1_s=s;
        start_x=decay_x(a,h,d);start_y=sustain_y(s);
        packet(start_x,start_y,1);packet(start_x,start_y+36,1);up;
        if(d!=env1_d || s!=90) $fatal(1,"Decay handle vertical-only edit failed: %d %d",d,s);
        start_x=decay_x(a,h,d);start_y=sustain_y(s);
        packet(start_x,start_y,1);packet(start_x,start_y-36,1);up;
        if(d!=env1_d || s!=env1_s) $fatal(1,"Decay handle vertical restore failed: %d %d",d,s);
        env1_s=s;
        start_x=decay_x(a,h,d)+60;start_y=sustain_y(s);
        packet(start_x,start_y,1);packet(start_x,start_y+200,1);up;
        if(s!=0 || d!=env1_d) $fatal(1,"Sustain drag modified duration or failed saturation");
        start_x=decay_x(a,h,d)+60+12+r*80/128;
        packet(start_x,568,1);packet(start_x+80,568,1);up;
        if(r!=127 || a!=61 || h!=127) $fatal(1,"Release drag failed %d",r);
        env1_a=a;env1_h=h;env1_d=d;env1_s=s;env1_r=r;
        drain;
        if(last_cc[24]!=env1_a || last_cc[25]!=env1_d || last_cc[26]!=env1_s || last_cc[27]!=env1_r || last_cc[79]!=-1)
            $fatal(1,"ENV1 audio CC mapping mismatch or unsupported Hold was sent");
        saved_count=cc_count;
        click(168,385);
        if(tab!=1 || a!=10 || h!=0 || d!=40 || s!=90 || r!=35) $fatal(1,"ENV2 not independent");
        start_x=attack_x(a);
        packet(start_x,424,1);packet(start_x+20,424,1);up;
        spi(`PARAM_ID_ENV1_ATTACK,77);
        packet(60,652,1);packet(80,652,1);up;
        if(a!=85 || h!=0) $fatal(1,"ENV2 physical/touch knob did not edit active bank: a=%0d h=%0d",a,h);
        env2_a=a;
        drain;
        if(cc_count!=saved_count) $fatal(1,"Local ENV2/tab changes leaked onto ENV1 MIDI");
        click(250,385);
        if(tab!=2 || a!=10) $fatal(1,"ENV3 not independent");
        click(168,385);if(a!=env2_a) $fatal(1,"ENV2 values lost on tab switch");
        click(70,385);
        if(a!=env1_a || h!=env1_h || d!=env1_d || s!=env1_s || r!=env1_r) $fatal(1,"ENV1 values lost on tab switch");

        // A contact starting outside the scope cannot capture it on entry.
        packet(790,500,1);packet(91,424,1);
        if(cap || a!=env1_a) $fatal(1,"Outside gesture captured ENV");
        up;
        packet(91,424,1);repeat(1030) @(negedge clk);
        packet(168,385,1);
        if(tab!=1) $fatal(1,"Lost-release watchdog did not recover");
        up;click(70,385);
        // Notch resonance moves the dip DOWN, unlike LP/HP/BP peaks.
        click(1000,60);click(1000,60);click(1000,60);
        if(ft!=3) $fatal(1,"Could not select notch mode");
        spi(`PARAM_ID_FLT_CUTOFF,80);spi(`PARAM_ID_FLT_RES,32);drain;
        packet(1073,173,1);packet(1073,184,1);up;
        if(res!=64 || cut!=80) $fatal(1,"Notch resonance direction incorrect");
        drain;

        // Buffer one absolute XY update while higher-priority SPI is active.
        force_busy=1;
        @(negedge clk);manual_valid=1;manual_values={21'd0,7'd127,7'd126};
        spi_v=1;spi_id=`PARAM_ID_MASTER_VOL;spi_val=99;
        @(negedge clk);manual_valid=0;spi_v=0;
        repeat(8) @(negedge clk);
        if(cut!=126 || res!=127) $fatal(1,"Concurrent SPI lost curve transaction");
        // Latest values should coalesce while UART is unavailable.
        @(negedge clk);manual_valid=1;manual_values={21'd0,7'd63,7'd100};
        @(negedge clk);manual_valid=0;
        repeat(8) @(negedge clk);force_busy=0;drain;
        if(last_cc[43]!=100 || last_cc[44]!=63) $fatal(1,"Latest XY MIDI did not survive UART busy");
        spans[0]=280;spans[1]=44;spans[2]=65;spans[3]=30;spans[4]=80;spans[5]=144;
        for(ny=0;ny<6;ny=ny+1) begin
            for(j=-5;j<=spans[ny]+5;j=j+1) begin
                nx=j<=0 ? 0 : (j*128+spans[ny]/2)/spans[ny];if(nx>127) nx=127;
                if(editor.pixel_value(j,spans[ny])!==7'(nx))
                    $fatal(1,"Inverse scale mismatch at pixel %0d span %0d",j,spans[ny]);
            end
        end
        $display("PASS: direct FILTER XY/notch, A/H/D/S/R handles, independent ENV banks, no-jump/anchor return, saturation/capture/watchdog, SPI arbitration, real serial MIDI/coalescing, local ENV2/3 isolation");
        $finish;
    end
    initial begin #10000000;$fatal(1,"Curve test timeout");end
endmodule
