`timescale 1ns/1ps
`include "params.vh"
module tb_static_startup_uart74;
 reg clk=0,rst_n=0,sv=0,bv=0,cv=0,dv=0;
 reg [7:0] sid=0,bid=0,did=0;reg [6:0] value=0;reg signed [7:0] delta=0;
 reg [1:0] action=0,ct=0;reg [34:0] cvalues=0;
 reg ext=0;reg [7:0] eid=0;reg [6:0] ev=0;
 wire [237:0] bank_values;wire [132:0] fx_values;wire [517:0] values;
 wire [237:0] extras={7'd80,7'd0,7'd0,7'd52,7'd0,7'd127,7'd0,7'd80,7'd20,7'd64,7'd96,7'd0,7'd64,7'd20,7'd64,7'd48,7'd20,7'd0,7'd64,7'd20,7'd48,7'd32,7'd20,7'd0,7'd64,7'd127,7'd32,7'd0,7'd0,7'd0,7'd0,7'd0,7'd0,7'd0};
 wire req,accept,done,uart,busy,ready,sreq,saccept,sbusy;wire [7:0] id;wire [6:0] val;wire [47:0] msgs;
 reg note_req=0;integer note_sent=0;
 always #10 clk=~clk;
 param_merger bank(.clk(clk),.rst_n(rst_n),.spi_param_valid(sv),.spi_param_id(sid),.spi_param_val(value),
  .touch_delta_valid(dv),.touch_selected_id(did),.touch_delta_val(delta),
  .btn_tap_valid(bv),.btn_tap_id(bid),.btn_tap_action(action),
  .curve_update_valid(cv),.curve_update_filter(1'b0),.curve_update_tab(ct),.curve_update_mask(5'b11111),.curve_update_values(cvalues),
  .midi_tx_busy(busy),.static_cc_values(bank_values));
 fx_editor_state fx(.clk(clk),.rst_n(rst_n),.touch_valid(1'b0),.touch_down(1'b0),.touch_x(14'd0),.touch_y(14'd0),
  .external_valid(ext),.external_id(eid),.external_value(ev),.values(fx_values));
 // Same exported live banks as the production top; assertions below use an
 // independent table of wire CC numbers and defaults, not decoder functions.
 assign values={extras,fx_values[84+:7],fx_values[49+:7],fx_values[42+:7],fx_values[35+:7],fx_values[7+:7],fx_values[0+:7],bank_values};
 static_cc_sync sync(.clk(clk),.rst_n(rst_n),.values(values),.cc_accept(accept),.uart_busy(busy),
  .cc_req(req),.cc_param_id(id),.cc_val(val),.startup_sync_done(done));
 lfo_sysex_tx #(.HOLD_CYCLES(20),.FIRST_HOLD_CYCLES(20)) sx(.clk(clk),.rst_n(rst_n && done),
  .cfg_nodes(147'd0),.cfg_rates(9'b010010010),.cfg_steps(3'd0),.cfg_once(3'd0),
  .cfg_sources(106'd0),.cfg_depths({53{8'h7F}}),.tx_accept(saccept),.sysex_req(sreq),.sysex_msgs(msgs),.busy(sbusy));
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(.clk(clk),.rst_n(rst_n),
  .note_on_req(note_req),.note_off_req(1'b0),.note_number(7'd29),.note_velocity(7'd100),
  .cc_req(req),.cc_param_id(id),.cc_val(val),.cc_accept(accept),.sysex_req(sreq),.sysex_msgs(msgs),.sysex_accept(saccept),
  .uart_tx(uart),.tx_busy(busy),.note_ready(ready));
 integer counts[0:127],seen[0:127],expected_cc[0:73],defaults[0:73];
 integer bytes=0,need=0,bi,n,cc_total=0,note_count=0,commits=0,frames=0,cc;
 reg [7:0] sb;reg [47:0] frame=0;reg boot_check=1;integer run=0;
 initial forever begin
  @(negedge uart);#100;
  for(bi=0;bi<8;bi=bi+1)begin #200;sb[bi]=uart;end
  #200;if(uart!==1)$fatal(1,"UART stop");
  if(bytes==0)need=sb==8'hF0 ? 6 : 3;
  frame={frame[39:0],sb};bytes=bytes+1;
  if(bytes==need)begin
   bytes=0;
   if(need==6)begin
    if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)$fatal(1,"SysEx split by CC/Note %h",frame);
    if(!done || cc_total<74)$fatal(1,"LFO precedes static drain");
    frames=frames+1;if(frame==48'hF07D7E0000F7)commits=commits+1;
   end else if(frame[23:16]==8'h90)begin
    if(frame[23:0]!==24'h901D64)$fatal(1,"Note corruption");note_count=note_count+1;
   end else begin
    if(frame[23:16]!==8'hBF)$fatal(1,"status/frame broken %h",frame);
    cc=frame[15:8];counts[cc]=counts[cc]+1;seen[cc]=frame[7:0];
    if(boot_check)begin
     if(cc_total>=74 || cc!==expected_cc[cc_total])$fatal(1,"boot order/duplicate at %0d CC%0d",cc_total,cc);
     if(frame[7:0]!==defaults[cc_total][7:0])$fatal(1,"boot displayed value differs slot%0d got%0d expected%0d",cc_total,frame[7:0],defaults[cc_total]);
    end
    cc_total=cc_total+1;
    $display("UART: run%0d BF %02h %02h",run,frame[15:8],frame[7:0]);
   end
  end
 end
 task step;begin @(negedge clk);end endtask
 task absolute(input [7:0] p,input [6:0] v);begin step;sid=p;value=v;sv=1;step;sv=0;repeat(5)step;end endtask
 task button(input [7:0] p,input [1:0] a);begin step;bid=p;action=a;bv=1;step;bv=0;repeat(5)step;end endtask
 task curve(input [1:0] bank_id,input [34:0] v);begin step;ct=bank_id;cvalues=v;cv=1;step;cv=0;repeat(7)step;end endtask
 task note;begin wait(ready);step;note_req=1;step;note_req=0;note_sent=note_sent+1;end endtask
 task drain;integer z,quiet;begin
  // Idle for a complete scan window, not a single gap between requests.
  // This covers the registered slot-read stage at the accelerated test baud.
  z=0;quiet=0;
  while(quiet<200 && z<100000)begin
   step;z=z+1;if(busy || sbusy || req)quiet=0;else quiet=quiet+1;
  end
  if(quiet<200)$fatal(1,"failed to drain");
 end endtask
 task reset;begin
  rst_n=0;repeat(5)step;
  for(n=0;n<128;n=n+1)begin counts[n]=0;seen[n]=-1;end
  cc_total=0;commits=0;frames=0;note_count=0;note_sent=0;bytes=0;frame=0;
  rst_n=1;
 end endtask
 initial begin
  // Independent expected UART numbers/defaults. Waveform B is UI enum1 ->96.
  expected_cc='{48,10,36,21,23,22,87,88,20,39,91,46,37,29,31,30,89,90,28,41,92,47,42,43,44,45,24,25,26,27,32,33,34,35,53,52,54,55,56,57,38,40,49,50,51,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86};
  defaults='{100,64,127,0,1,64,0,64,0,64,64,100,127,96,1,64,0,64,64,64,64,100,1,80,32,127,10,40,90,35,10,40,90,35,64,64,32,64,64,32,0,0,0,0,0,0,0,32,127,64,0,20,32,48,20,64,0,20,48,64,20,64,0,96,64,20,80,0,127,0,52,0,0,80};
  reset;
  // A real full FIFO reserves its last slot for this Note; CC must wait/retry.
  wait(tx.fifo_count==7 && req);note;
  if(accept)$fatal(1,"CC incorrectly accepted with full FIFO");
  wait(done);wait(commits==1);drain;
  if(cc_total!=74 || note_count!=1 || frames!=81)$fatal(1,"boot/Note/full LFO count %0d/%0d/%0d",cc_total,note_count,frames);
  for(n=0;n<74;n=n+1)if(counts[expected_cc[n]]!=1)$fatal(1,"boot CC not exactly once");
  // Start over and edit a not-yet-sent value while UART applies backpressure.
  run=1;defaults[16]=91;defaults[18]=77;reset;
  wait(tx.fifo_count==7 && req);note;
  absolute(`PARAM_ID_OSCB_PHASE,91);absolute(`PARAM_ID_OSCB_WT_POS,77);
  wait(done);wait(frames>=5 && sbusy);boot_check=0;
  absolute(`PARAM_ID_MASTER_VOL,85);note;
  wait(commits==1);drain;
  if(cc_total!=75 || seen[48]!=85 || seen[89]!=91 || seen[28]!=77)$fatal(1,"stale boot/concurrent CC count=%0d master=%0d Bphase=%0d Bwt=%0d live=%0d sent=%0d",cc_total,seen[48],seen[89],seen[28],bank.val_master_vol,sync.sent[0]);
  boot_check=0;
  // Concurrent live changes, including fixed bank ENV2 and actual FX state.
  absolute(`PARAM_ID_OSCA_PHASE,11);absolute(`PARAM_ID_OSCA_RAND,12);
  absolute(`PARAM_ID_OSCB_PHASE,13);absolute(`PARAM_ID_OSCB_RAND,14);
  did=`PARAM_ID_MASTER_VOL;delta=-3;dv=1;step;dv=0;repeat(5)step;
  button(`PARAM_ID_ENV_TAB,1);absolute(`PARAM_ID_ENV1_ATTACK,61);button(`PARAM_ID_ENV_TAB,0);
  curve(0,{7'd74,7'd73,7'd72,7'd0,7'd71});button(`PARAM_ID_ENV_TAB,1);
  button(`PARAM_ID_FLT_POWER,0);button(`PARAM_ID_FLT_TYPE,1); // off mode must remain0
  step;ext=1;eid=`PARAM_ID_DELAY_FEEDBACK;ev=83;step;ext=0;
  note;drain;
  if(seen[87]!=11 || seen[88]!=12 || seen[89]!=13 || seen[90]!=14)$fatal(1,"Phase/Rand CC87..90 lost");
  if(seen[32]!=61 || seen[24]!=71 || seen[25]!=72 || seen[26]!=73 || seen[27]!=74)$fatal(1,"live ENV bank lost");
  if(seen[42]!=0 || seen[53]!=83 || seen[48]!=82)$fatal(1,"filter power/FX/touch-delta static mismatch");
  button(`PARAM_ID_FLT_POWER,0);drain;if(seen[42]!=2)$fatal(1,"filter reenable/type mismatch");
  // Hold, ENV3 and switching pages generate no CC changes.
  n=cc_total;button(`PARAM_ID_ENV_TAB,2);absolute(`PARAM_ID_ENV1_ATTACK,99);absolute(`PARAM_ID_ENV1_HOLD,80);drain;
  if(cc_total!=n || note_count!=note_sent)$fatal(1,"local-only CC leak or lost Note");
  $display("PASS: 74 boot CC exactly once/in order, 81 full LFO frames afterwards; FIFO pressure/Note priority, newest boot values, Phase/Rand, ENV banks/curve, filter off/type/reenable, FX and no local-only leaks");$finish;
 end
 initial begin #16000000;$fatal(1,"startup watchdog");end
endmodule
