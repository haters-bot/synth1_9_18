`timescale 1ns/1ps
module tb_fx_lfo_routing;
    reg clk=0,rst_n=0,tv=0,td=0;
    reg [13:0] x=0,y=0;
    reg ext=0;reg [7:0] eid=0;reg [6:0] ev=0;
    reg [1:0] tab=0;
    reg [7:0] last_fx_id=0;
    reg [6:0] last_fx_value=0;
    wire armed,dragging,capture,rv,fv;
    wire [5:0] selected,hover;
    wire [105:0] sources;wire [423:0] depths;
    wire [132:0] fx_values;wire [10:0] switches;
    wire [7:0] rt,fi;wire [1:0] rs;wire signed [7:0] rd;wire [6:0] fval;
    integer i,before_events=0,route_events=0,fx_events=0;
    reg [48:0] curve;
    reg step=0;reg [8:0] read_index=0;
    wire [12:0] curve_q6;wire [6:0] sample_v;
    reg [370:0] base_values=0;
    wire [370:0] preview;
    wire [12:0] unused;
    wire [48:0] edited_nodes;
    `include "mod_targets.vh"
    `include "fx_controls.vh"
    always #8 clk=~clk;
    always @(posedge clk) begin
        if(rv) route_events=route_events+1;
        if(fv) begin fx_events=fx_events+1;last_fx_id=fi;last_fx_value=fval;end
    end
    lfo_binding_state #(.WATCHDOG_CYCLES(128)) binding(
        .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),.active_tab(tab),
        .armed(armed),.dragging(dragging),.capture_active(capture),.selected_target(selected),.hover_target(hover),
        .sources(sources),.depths(depths),.event_valid(rv),.event_target(rt),.event_source(rs),.event_depth(rd));
    lfo_editor_state editor(.clk(clk),.rst_n(rst_n),.touch_valid(tv),
        .touch_down(td && !capture),.touch_x(x),.touch_y(y),.nodes(edited_nodes));
    fx_editor_state #(.WATCHDOG_CYCLES(128)) fx(
        .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td && !capture),.touch_x(x),.touch_y(y),
        .external_valid(ext),.external_id(eid),.external_value(ev),.values(fx_values),.switches(switches),
        .event_valid(fv),.event_id(fi),.event_value(fval));
    lfo_smooth_table smooth(.clk(clk),.rst_n(rst_n),.nodes(curve),.stepped(step),
        .raster_index(read_index),.preview_index(read_index),.raster_q6(curve_q6),.preview_value(sample_v));
    modulation_preview #(.PREVIEW_BASE_TICKS(2000)) preview_dut(.clk(clk),.rst_n(rst_n),
        .nodes({curve,curve,curve}),.rates(9'd0),.stepped(3'd0),.active_tab(tab),.active_phase(read_index),
        .raster_index(read_index),.sources(sources),.depths(depths),.base_values(base_values),
        .preview_values(preview),.raster_q6(unused));
    task packet;
        input integer px,py;input pressed;
        begin @(negedge clk);x=px;y=py;td=pressed;tv=1;
            @(negedge clk);tv=0;repeat(6) @(negedge clk);end
    endtask
    task click;
        input integer px,py;
        begin packet(px,py,1);packet(px,py,0);end
    endtask
    // No drain cycles between packets: exercise the decoder's throughput and
    // packet metadata alignment, independently of normal USB report spacing.
    task burst_packet;
        input integer px,py;input pressed;
        begin @(negedge clk);x=px;y=py;td=pressed;tv=1;end
    endtask
    task drain_packets;
        begin @(negedge clk);tv=0;ext=0;repeat(6) @(negedge clk);end
    endtask
    task external_set;
        input integer id,value;
        begin @(negedge clk);ext=1;eid=id;ev=value;
            @(negedge clk);ext=0;repeat(3) @(negedge clk);end
    endtask
    task bind_target;
        input integer idx;
        begin click(1140,385);if(!armed) $fatal(1,"BIND did not arm");
            packet(980,485,1);if(!dragging) $fatal(1,"Curve drag did not capture");
            packet(mod_cx(idx),mod_cy(idx),1);
            if(hover!=idx) $fatal(1,"Wrong target hit at %d: %d",idx,hover);
            packet(0,0,0);
            if(armed || dragging || sources[idx*2+:2]!=tab+1) $fatal(1,"Binding missing %d",idx);
        end
    endtask
    integer seg,lo,hi,prev_value,v,fx_before;
    reg [48:0] saved_nodes;
    initial begin
        curve={7'd0,7'd42,7'd85,7'd127,7'd85,7'd42,7'd0};
        repeat(5) @(negedge clk);rst_n=1;repeat(500) @(negedge clk);
        // Every target is reachable and a zero-coordinate UP commits last hover.
        for(i=0;i<53;i=i+1) begin tab=i%3;bind_target(i);end
        if(edited_nodes!={7'd0,7'd42,7'd85,7'd127,7'd85,7'd42,7'd0})
            $fatal(1,"Dragging a bound curve modified its nodes");
        if(route_events!=53 || fx_events!=0) $fatal(1,"Binding leaked FX mutation or duplicate events");
        before_events=route_events;
        click(1140,385);packet(980,485,1);packet(790,350,1);packet(0,0,0);
        if(route_events!=before_events || armed) $fatal(1,"Invalid drop changed routing");
        click(1140,385);packet(980,485,1);packet(950,268,1);
        repeat(140) @(negedge clk);
        if(dragging || armed || route_events!=before_events+1 || sources[23*2+:2]!=tab+1)
            $fatal(1,"Quiet release did not preserve valid destination");
        before_events=route_events;
        packet(0,0,0);
        if(route_events!=before_events) $fatal(1,"Late UP duplicated quiet-release binding");
        click(950,268); // select Cutoff's route
        if(selected!=23) $fatal(1,"Bound knob did not select route");
        for(i=0;i<30;i=i+1) click(1100,675);
        if($signed(depths[23*8+:8])!=127) $fatal(1,"Positive depth clamp failed");
        for(i=0;i<40;i=i+1) click(1030,675);
        if($signed(depths[23*8+:8])!=-127) $fatal(1,"Negative depth clamp failed");
        click(1190,675);if(sources[23*2+:2]!=0) $fatal(1,"Clear failed");
        for(i=0;i<19;i=i+1) begin
            external_set(8'h60+i,40);
            if(fx_values[i*7+:7]!=40) $fatal(1,"External FX parameter missing %d",i);
            packet(fx_cx(i),fx_cy(i),1);
            if(fx_values[i*7+:7]!=40) $fatal(1,"FX press jumped");
            external_set(8'h60+i,99);
            if(fx_values[i*7+:7]!=40) $fatal(1,"External input stole captured FX knob");
            packet(fx_cx(i),fx_cy(i)-20,1);packet(0,0,0);
            if(fx_values[i*7+:7]!=50) $fatal(1,"FX drag failed %d %d",i,fx_values[i*7+:7]);
        end
        for(i=0;i<9;i=i+1) begin
            external_set(8'h80+i,0);if(switches[i]!=0) $fatal(1,"FX switch off failed");
            external_set(8'h80+i,1);if(switches[i]!=1) $fatal(1,"FX switch on failed");
        end
        packet(760,385,1);packet(760,385,1);packet(760,385,0);
        if(switches[0]!=0) $fatal(1,"Held FX button repeated");
        external_set(8'h84,1);external_set(8'h61,90);
        if(fx_values[7+:7]!=90 || fx_values[14+:7]!=90) $fatal(1,"Delay link did not follow external input");
        packet(fx_cx(2),fx_cy(2),1);packet(fx_cx(2),fx_cy(2)-20,1);packet(0,0,0);
        if(fx_values[7+:7]!=100 || fx_values[14+:7]!=100) $fatal(1,"Delay linked touch failed");
        external_set(8'h87,0);click(552,600);click(552,600);
        if(!switches[9] || switches[7]) $fatal(1,"EQ low cut type missing");
        click(552,600);if(switches[9] || switches[7]) $fatal(1,"EQ type wrap failed");
        external_set(8'h87,2);
        if(last_fx_id!=8'h87 || last_fx_value!=2 || !switches[9] || switches[7])
            $fatal(1,"EQ low cut event disagrees with snapshot");
        external_set(8'h88,127);
        if(last_fx_id!=8'h88 || last_fx_value!=2 || !switches[10] || switches[8])
            $fatal(1,"EQ high cut clamp event disagrees with snapshot");
        // Consecutive BIND/UP/graph/target/UP must neither edit the curve nor
        // touch the destination's base value. Source belongs to graph press,
        // even if the active tab changes before the destination arrives.
        before_events=route_events;fx_before=fx_events;saved_nodes=edited_nodes;
        tab=0;
        burst_packet(1140,385,1);burst_packet(0,0,0);
        tab=1;burst_packet(980,485,1);
        burst_packet(mod_cx(34),mod_cy(34),1);tab=2;burst_packet(0,0,0);
        drain_packets();
        if(route_events!=before_events+1 || sources[34*2+:2]!=2 || armed || dragging)
            $fatal(1,"Back-to-back binding lost metadata or release");
        if(fx_events!=fx_before || edited_nodes!=saved_nodes)
            $fatal(1,"Back-to-back binding leaked into another editor");
        external_set(8'h60,40);fx_before=fx_events;
        burst_packet(fx_cx(0),fx_cy(0),1);
        burst_packet(fx_cx(0),fx_cy(0)-20,1);burst_packet(0,0,0);
        drain_packets();
        if(fx_values[0+:7]!=50 || fx_events!=fx_before+1)
            $fatal(1,"Back-to-back FX drag lost anchor/move/release");
        // Same input cycle external and touch events retain the old contract:
        // press captures the previous base; later external writes cannot steal
        // a drag, including the cycle containing its release packet.
        external_set(8'h60,40);fx_before=fx_events;
        burst_packet(fx_cx(0),fx_cy(0),1);ext=1;eid=8'h60;ev=99;
        burst_packet(fx_cx(0),fx_cy(0)-20,1);ev=88;
        burst_packet(0,0,0);ev=77;
        drain_packets();
        if(fx_values[0+:7]!=50 || fx_events!=fx_before+2)
            $fatal(1,"Same-cycle FX/external arbitration changed with decode latency");
        external_set(8'h60,66);
        if(fx_values[0+:7]!=66) $fatal(1,"FX release failed to return external ownership");
        // Independent shape properties: endpoints, boundedness and monotonicity.
        prev_value=-1;
        for(i=0;i<=384;i=i+1) begin
            @(negedge clk);read_index=i;#1;
            seg=i==384 ? 5 : i/64;
            lo=(curve>>(seg*7))&127;hi=(curve>>((seg+1)*7))&127;
            v=curve_q6;
            if(v<(lo<hi?lo:hi)*64 || v>(lo>hi?lo:hi)*64) $fatal(1,"Cubic overshoot %d %d",i,v);
            if(i%64==0 && v!=((curve>>((i/64)*7))&127)*64) $fatal(1,"Node not interpolated");
            if(i>0 && ((i<=192 && v<prev_value)||(i>192 && v>prev_value))) $fatal(1,"Nonmonotone segment");
            prev_value=v;
        end
        step=1;repeat(500) @(negedge clk);
        for(i=0;i<=384;i=i+1) begin
            @(negedge clk);read_index=i;#1;
            if(sample_v!=((curve>>((i/64)*7))&127)) $fatal(1,"Stepped mode changed");
        end
        // Base parameter state stays untouched by dynamic preview and clearing.
        step=0;curve={7{7'd127}};base_values={53{7'd20}};
        tab=0;bind_target(23);repeat(500) @(negedge clk);
        if(preview[23*7+:7]!=127 || base_values[23*7+:7]!=20) $fatal(1,"Preview corrupted base or amplitude");
        click(1190,675);repeat(5) @(negedge clk);
        if(preview[23*7+:7]!=20) $fatal(1,"Clearing did not restore base");
        // Distinct bases exercise shared-multiplier destination alignment.
        for(i=0;i<53;i=i+1) base_values[i*7+:7]=i;
        repeat(500) @(negedge clk);
        for(i=0;i<53;i=i+1) begin
            v=i==23 ? i : 127;
            if(preview[i*7+:7]!=v) $fatal(1,"Shared preview index mismatch %d: %d != %d",i,preview[i*7+:7],v);
        end
        tab=0;bind_target(23);base_values[23*7+:7]=100;
        for(i=0;i<32;i=i+1) click(1030,675);
        repeat(500) @(negedge clk);
        if(preview[23*7+:7]!=0) $fatal(1,"Shared preview negative-depth rounding failed");
        $display("PASS: 53 route targets, three LFO sources, release-zero, invalid drop/watchdog, depth +/- saturation, clear, 19 FX knobs/external arbitration, nine switches, back-to-back binding/drag/source metadata and simultaneous external arbitration, bounded smooth curve and separate preview/base");
        $finish;
    end
    initial begin #5000000;$fatal(1,"Routing test timeout");end
endmodule
