`timescale 1ns/1ps
module tb_lfo_binding_release;
    reg clk=0,rst_n=0,tv=0,td=0,cancel=0;
    reg [13:0] x=0,y=0,px=0,py=0;
    reg [1:0] tab=1;
    wire armed,dragging,capture,ev,hit;
    wire [5:0] selected,hover;
    wire [105:0] sources;
    wire [423:0] depths;
    wire [23:0] rgb;
    integer events=0;
    `include "mod_targets.vh"
    always #10 clk=~clk;
    always @(posedge clk) if(ev) events=events+1;
    // Scale the quiet-contact grace for fast lifecycle checks. All decisions
    // still use actual clock edges and independently generated touch packets.
    lfo_binding_state #(.ENABLE_CANCEL(1),.WATCHDOG_CYCLES(1000)) dut(
        .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),.active_tab(tab),
        .cancel(cancel),
        .armed(armed),.dragging(dragging),.capture_active(capture),.selected_target(selected),
        .hover_target(hover),.sources(sources),.depths(depths),.event_valid(ev));
    modulation_overlay overlay(.clk(clk),.rst_n(rst_n),.in_x(px),.in_y(py),
        .sources(sources),.depths(depths),.preview_values(371'd0),.armed(armed),.dragging(dragging),
        .hover_target(hover),.selected_target(selected),.active_tab(tab),.touch_x(x),.touch_y(y),
        .curve_nodes({7{7'd64}}),.out_hit(hit),.out_rgb(rgb));
    task packet;
        input integer ax,ay;input pressed;
        begin @(negedge clk);x=ax;y=ay;td=pressed;tv=1;
            @(negedge clk);tv=0;repeat(6)@(negedge clk);end
    endtask
    task start_drag;
        begin packet(1140,385,1);packet(0,0,0);packet(980,485,1);
            if(!armed || !dragging || !capture)$fatal(1,"Drag not captured");end
    endtask
    task mark_pixel;
        input integer index;input expected_hit;input [23:0] expected;
        begin @(negedge clk);px=mod_cx(index)+22;py=mod_cy(index)+4;
            repeat(9)@(negedge clk);
            if(hit!==expected_hit || (expected_hit && rgb!==expected))
                $fatal(1,"Saved binding not reflected by persistent overlay: %d %b %h",index,hit,rgb);
        end
    endtask
    reg [105:0] saved_sources;
    reg [423:0] saved_depths;
    integer saved_events;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
        start_drag();packet(mod_cx(23),mod_cy(23),1);
        repeat(900)@(negedge clk);
        if(!dragging || sources!=0 || events!=0)$fatal(1,"Aiming pause ended gesture early");
        packet(mod_cx(34),mod_cy(34),1);
        repeat(1100)@(negedge clk);
        if(armed || dragging || capture || selected!=34 || sources[68+:2]!=2 || sources[46+:2]!=0 || events!=1)
            $fatal(1,"Missing-UP drop lost final target or duplicated event");
        mark_pixel(34,1,24'hEEB34D);mark_pixel(23,0,0);
        packet(0,0,0);repeat(1100)@(negedge clk);
        if(events!=1)$fatal(1,"Late UP/idle repeated binding");
        mark_pixel(34,1,24'hEEB34D);
        start_drag();packet(mod_cx(23),mod_cy(23),1);packet(790,350,1);
        repeat(1100)@(negedge clk);
        if(armed || dragging || sources[46+:2]!=0 || events!=1)$fatal(1,"Invalid quiet drop bound a stale hover");
        tab=2;start_drag();packet(mod_cx(23),mod_cy(23),1);packet(0,0,0);
        if(sources[46+:2]!=3 || events!=2)$fatal(1,"Explicit UP no longer commits immediately");
        mark_pixel(23,1,24'hDD88FF);
        tab=0;packet(1140,385,1);packet(0,0,0);packet(mod_cx(34),mod_cy(34),1);
        if(armed || selected!=34 || sources[68+:2]!=1 || events!=3 || !capture)
            $fatal(1,"Tap destination failed to commit/capture without editing base");
        packet(0,0,0);mark_pixel(34,1,24'h38E8FF);
        if(capture)$fatal(1,"Tap destination did not release capture");
        // The panel can omit UP. A fresh contact after the normal 50-ms gap
        // must not inherit the binder's much longer 500-ms aiming grace.
        packet(980,485,1); // ordinary curve edit, not a binding drag
        repeat(150)@(negedge clk);
        packet(1140,385,1);
        if(!armed)$fatal(1,"Stale curve contact swallowed BIND after normal contact timeout");
        // Rapid BIND -> graph handoff, with no UP and no quiet gap at all.
        // These are two deliberate stages of one bind operation.
        packet(980,485,1);
        if(!dragging)$fatal(1,"Missing BIND UP swallowed the graph drag");
        packet(mod_cx(24),mod_cy(24),1);packet(0,0,0);
        if(armed || dragging || sources[48+:2]!=1 || events!=4)
            $fatal(1,"Rapid missing-UP binding did not commit exactly once");
        // A control contact left behind by tap binding must stop capturing
        // the rest of the UI after 50 ms, without erasing routing or selection.
        packet(1140,385,1);packet(0,0,0);packet(mod_cx(23),mod_cy(23),1);
        repeat(150)@(negedge clk);
        if(capture || sources[46+:2]!=1 || events!=5)
            $fatal(1,"Tap binding still blocks other editors after contact timeout");
        packet(1140,385,1); // no UP from preceding tap
        if(!armed)$fatal(1,"Rapid repeated BIND was ignored");
        repeat(150)@(negedge clk);
        if(!armed || dut.finger || dut.control_contact)
            $fatal(1,"Armed mode must survive while stale button contact expires");
        packet(1140,385,1);packet(0,0,0);
        if(armed || capture)$fatal(1,"BIND cancel must release UI immediately on UP");
        saved_sources=sources;saved_depths=depths;saved_events=events;
        start_drag();packet(mod_cx(13),mod_cy(13),1);
        // Raw navigation cancellation and the header packet arrive together.
        // Cancellation must reach the state before its pipelined touch packet,
        // without committing the old hover during the subsequent release.
        @(negedge clk);cancel=1;tv=1;td=1;x=880;y=20;
        @(negedge clk);tv=0;repeat(6)@(negedge clk);packet(0,0,0);
        if(armed || dragging || capture || sources!==saved_sources || depths!==saved_depths || events!=saved_events)
            $fatal(1,"Navigation cancel committed a stale hover or erased bindings");
        cancel=0;repeat(6)@(negedge clk);
        start_drag();packet(mod_cx(13),mod_cy(13),1);packet(0,0,0);
        if(sources[26+:2]!=1 || depths[104+:8]!=127 || events!=saved_events+1)
            $fatal(1,"Binding did not resume after navigation cancel");
        $display("PASS: aiming pause, missing-UP final destination, late-UP deduplication, invalid drop, explicit-UP, tap fallback, state-driven marks, short contact expiry, rapid BIND-to-graph handoff and registered navigation cancel/rebind");
        $finish;
    end
    initial begin #2000000;$fatal(1,"Release regression timeout");end
endmodule
