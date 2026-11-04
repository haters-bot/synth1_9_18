`timescale 1ns/1ps
module tb_performance_note_flush;
 reg clk=0,rst_n=0,flush=0,ready=1,sv=0,rv=0,tv=0;
 reg son=1,ron=1,ton=1;reg [6:0] sn=41,rn=53,tn=65;
 wire valid,on,busy,overflow,sready;wire [6:0] n,v;
 always #5 clk=~clk;
 performance_note_arbiter dut(.clk(clk),.rst_n(rst_n),.flush(flush),.busy(busy),
  .score_valid(sv),.score_on(son),.score_note(sn),.score_velocity(7'd100),.score_ready(sready),
  .remote_valid(rv),.remote_on(ron),.remote_note(rn),.remote_velocity(7'd100),
  .touch_valid(tv),.touch_on(ton),.touch_note(tn),.touch_velocity(7'd100),
  .note_valid(valid),.note_ready(ready),.note_on(on),.note_number(n),.note_velocity(v),.overflow(overflow));
 reg [127:0] sounding=0;integer ons=0,offs=0;
 always @(posedge clk)if(rst_n && valid && ready)begin
  if(on && v!=0)begin
   if(sounding[n])$fatal(1,"duplicate accepted On");sounding[n]=1;ons=ons+1;
  end else begin
   if(!sounding[n])$fatal(1,"unexpected Off %d",n);sounding[n]=0;offs=offs+1;
   if(v!=0)$fatal(1,"flush Off velocity");
  end
 end
 task step;begin @(negedge clk);end endtask
 task drain;begin wait(!busy);repeat(5)step;if(sounding!=0)$fatal(1,"stuck Notes after flush");end endtask
 integer expected_ons;
 initial begin
  repeat(3)step;rst_n=1;
  // Three independent sources hold keys. Extra unsent requests are discarded.
  sv=1;rv=1;tv=1;step;sv=0;rv=0;tv=0;
  wait(ons==3);repeat(3)step;ready=0;
  sn=42;rn=54;tn=66;sv=1;rv=1;tv=1;step;sv=0;rv=0;tv=0;repeat(4)step;
  flush=1;step;flush=0;repeat(10)step;if(!busy || sready)$fatal(1,"flush ignored UART stall");
  ready=1;drain;if(ons!=3 || offs!=3)$fatal(1,"unsent notes leaked or missing releases");
  // On accepted on the very clock of flush must still get an Off.
  sn=77;sv=1;step;sv=0;wait(valid);step;
  flush=1;step;flush=0;
  if(ons!=4)$fatal(1,"flush edge accepted On");
  drain;if(offs!=4)$fatal(1,"flush edge On not released");
  // Restart cleanup while its output is stalled; no old absolute pitch lost.
  tn=108;tv=1;step;tv=0;wait(ons==5);step;
  ready=0;flush=1;step;flush=0;repeat(120)step;
  flush=1;step;flush=0;ready=1;drain;
  if(offs!=5 || overflow)$fatal(1,"repeated flush or overflow");
  $display("PASS: session flush releases held score/remote/touch Notes, discards unsent requests, survives UART stalls/flush-edge acceptance/repeated flush, no stuck pitches");$finish;
 end
 initial begin #100000;$fatal(1,"flush watchdog");end
endmodule
