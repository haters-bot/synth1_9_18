`timescale 1ns/1ps
`include "params.vh"
module tb_lfo_editor;
    reg clk=0,rst_n=0,valid=0,down=0;
    reg [15:0] raw_x=0,raw_y=0;
    wire uv,ud;
    wire [13:0] ux,uy;
    wire [1:0] tab,preset;
    wire [48:0] nodes;
    wire [2:0] rate;
    wire once_mode,stepped,running;
    wire [8:0] phase;
    wire delta,tap;
    wire [7:0] selected_id,tap_id;
    wire [1:0] tap_action;
    integer legacy_events=0;
    always #8 clk=~clk;
    always @(posedge clk) if(delta || tap) legacy_events=legacy_events+1;
    touch_event_router router(.clk(clk),.rst_n(rst_n),
        .touch_valid(valid),.touch_state(down),.raw_touch_x(raw_x),.raw_touch_y(raw_y),
        .ui_touch_valid(uv),.ui_touch_down(ud),.ui_touch_x(ux),.ui_touch_y(uy),
        .param_delta_valid(delta),.btn_tap_valid(tap),
        .selected_param_id(selected_id),.btn_tap_id(tap_id),.btn_tap_action(tap_action));
    lfo_editor_state #(.WATCHDOG_CYCLES(64),.PREVIEW_BASE_TICKS(32)) dut(
        .clk(clk),.rst_n(rst_n),.touch_valid(uv),.touch_down(ud),.touch_x(ux),.touch_y(uy),
        .active_tab(tab),.preset(preset),.nodes(nodes),.rate(rate),.once_mode(once_mode),
        .stepped(stepped),.phase(phase),.running(running));
    task packet;
        input integer px,py;
        input pressed;
        begin
            @(negedge clk);
            // Exact inverse of measured R15E panel mapping (round up).
            raw_x=(px*65536+5119)/5120;
            raw_y=(py*65536+4914)/4915;
            down=pressed;valid=1;
            @(negedge clk);valid=0;
            repeat(5) @(negedge clk);
        end
    endtask
    task click;
        input integer px,py;
        begin packet(px,py,1);packet(px,py,0);end
    endtask
    reg [48:0] saved;
    integer j;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        repeat(3) @(negedge clk);
        if(tab!==0 || rate!==2 || preset!==0 || nodes[27:21]!==127)
            $fatal(1,"Invalid initial LFO state");
        packet(896,416,1);
        if(nodes[13:7]!==127 || preset!==3) $fatal(1,"Touch did not edit node amplitude");
        packet(896,550,1);
        if(nodes[13:7]!==0) $fatal(1,"Bottom amplitude did not clamp to zero");
        packet(1216,408,1);
        if(nodes[48:42]!==127) $fatal(1,"Last node/top clamp failed");
        packet(1216,408,0);
        saved=nodes;
        click(930,385);
        if(tab!==1 || preset!==1 || nodes[48:42]!==127 || nodes[13:7]!==21)
            $fatal(1,"Independent second LFO missing");
        click(1015,385);
        if(tab!==2 || !stepped || preset!==2) $fatal(1,"Third LFO square preset missing");
        click(850,385);
        if(nodes!==saved) $fatal(1,"Tab switch lost edited curve");
        click(1140,575);
        if(!stepped || nodes[20:14]!==127 || nodes[27:21]!==0)
            $fatal(1,"Square preset failed");
        click(1000,575);
        if(stepped || preset!==1 || nodes[27:21]!==64) $fatal(1,"Ramp preset failed");
        click(860,575);
        if(stepped || preset!==0 || nodes[27:21]!==127) $fatal(1,"Triangle preset failed");
        packet(860,620,1);
        for(j=0;j<3;j=j+1) packet(860,620,1);
        if(rate!==3) $fatal(1,"Held rate button repeated unexpectedly");
        packet(860,620,0);
        click(860,620);click(860,620);click(860,620);
        if(rate!==0) $fatal(1,"Rate wrap failed");
        click(860,620);click(860,620); // default 1 Hz, accelerated test divider
        click(1000,620);
        if(!once_mode) $fatal(1,"One-shot mode not selected");
        repeat(3100) @(negedge clk);
        if(running || phase!==383) $fatal(1,"Single preview did not stop at end");
        click(1170,620);
        if(!running || phase>4) $fatal(1,"Manual restart did not reset preview");
        click(1000,620);
        repeat(3100) @(negedge clk);
        if(!running || phase>=383) $fatal(1,"Free preview did not loop");
        if(legacy_events!==0) $fatal(1,"LFO interaction emitted a legacy FX/button event");
        saved=nodes;
        packet(790,500,1);packet(896,416,1);packet(896,416,0);
        if(nodes!==saved) $fatal(1,"Gesture entering from outside edited LFO");
        if(legacy_events!==0) $fatal(1,"Retired matrix border still emitted FX events");
        packet(896,416,1); // lost release; watchdog must recover
        repeat(70) @(negedge clk);
        packet(930,385,1);
        if(tab!==1) $fatal(1,"Watchdog did not recover a lost release");
        packet(930,385,0);
        if(rate!==2 || once_mode) $fatal(1,"Rate/mode state leaked between LFO banks");
        click(168,385);
        if(router.btn_tap_id!==`PARAM_ID_ENV_TAB || router.btn_tap_action!==1)
            $fatal(1,"Existing ENV 2 routing regressed");
        packet(950,268,1);
        if(selected_id!==`PARAM_ID_FLT_CUTOFF) $fatal(1,"Existing cutoff selection regressed");
        packet(960,268,1);packet(960,268,0);
        if(legacy_events==0) $fatal(1,"Existing controls stopped generating events");
        $display("PASS: LFO 3 banks, 7 nodes, bounds, presets, rate, once/free preview, restart, capture/watchdog, no FX leakage, ENV/cutoff regression");
        $finish;
    end
endmodule
