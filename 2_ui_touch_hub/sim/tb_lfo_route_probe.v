`timescale 1ns/1ps
module tb_lfo_route_probe;
 reg clk=0,rst_n=0,touch_valid=0,touch_down=0;
 reg [15:0] raw_x=0,raw_y=0;
 reg [1:0] active_tab=0;
 reg [6:0] point3=0;
 wire uart_tx,sysex_req,binding_armed,binding_dragging;
 wire [47:0] sysex_msgs;
 wire [1:0] source6,source13;
 wire [7:0] depth6,depth13;
 lfo_route_probe dut(.*);
 always #10 clk=~clk;
 reg [7:0] sb;
 reg [47:0] frame=0,last6=0,last13=0,lastpoint=0;
 integer i,bytes=0,frames=0,commits=0,n,previous_commit;
 initial forever begin
  @(negedge uart_tx);#100;
  if(uart_tx!==0)$fatal(1,"start");
  for(i=0;i<8;i=i+1)begin #200;sb[i]=uart_tx;end
  #200;if(uart_tx!==1)$fatal(1,"stop");
  frame={frame[39:0],sb};bytes=bytes+1;
  if(bytes==6)begin
   bytes=0;frames=frames+1;
   if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)$fatal(1,"frame %h",frame);
   if(frame[31:24]==8'h4F)begin last6=frame;$display("UART: target6 %h",frame);end
   if(frame[31:24]==8'h56)begin last13=frame;$display("UART: target13 %h",frame);end
   if(frame[31:24]==8'h33)begin lastpoint=frame;$display("UART: point3 %h",frame);end
   if(frame==48'hF07D7E0000F7)begin commits=commits+1;$display("UART: commit=%0d",commits);end
  end
 end
 task packet(input integer px,py,input bit down);
  begin
   @(negedge clk);raw_x=(px*65536+5119)/5120;raw_y=(py*65536+4914)/4915;
   touch_down=down;touch_valid=1;
   @(negedge clk);touch_valid=0;repeat(8)@(negedge clk);
  end
 endtask
 task bind_to(input integer px,py);
  begin
   packet(1140,385,1);packet(1140,385,1);packet(0,0,0);
   packet(980,485,1);packet(800,360,1);
   packet(px,py,1);packet(px,py,1);packet(0,0,0);
  end
 endtask
 initial begin
  // Allow Gowin primitive startup and GSR initialization before reset release.
  #1000;repeat(8)@(negedge clk);rst_n=1;
  wait(commits==1);repeat(100)@(negedge clk);
  $display("CHECK: boot sources=%h/%h depths=%h/%h",source6,source13,depth6,depth13);
  if(last6!==48'hF07D4F007FF7 || last13!==48'hF07D56007FF7)
   $fatal(1,"boot route serialization incorrect: %h %h",last6,last13);
  bind_to(134,268);
  repeat(20)@(negedge clk);
  $display("CHECK: bound6 source=%h depth=%h",source6,depth6);
  if(source6!==1 || depth6!==127)$fatal(1,"binding6 state");
  wait(commits==2);repeat(100)@(negedge clk);
  if(last6!==48'hF07D4F027FF7)$fatal(1,"route6 %h",last6);
  bind_to(344,326);
  repeat(20)@(negedge clk);
  $display("CHECK: bound13 source=%h depth=%h",source13,depth13);
  if(source13!==1 || depth13!==127)$fatal(1,"binding13 state");
  wait(commits==3);repeat(100)@(negedge clk);
  if(last13!==48'hF07D56027FF7)$fatal(1,"route13 %h",last13);
  point3=126;wait(commits==4);repeat(100)@(negedge clk);
  if(lastpoint!==48'hF07D33007EF7)$fatal(1,"point3 %h",lastpoint);
  point3=80;wait(commits==5);repeat(100)@(negedge clk);
  if(lastpoint!==48'hF07D330050F7)$fatal(1,"point3 %h",lastpoint);
  active_tab=1;bind_to(134,268);
  wait(commits==6);repeat(100)@(negedge clk);
  if(source6!==2 || depth6!==127 || last6!==48'hF07D4F047FF7)
   $fatal(1,"LFO2 rebind6 %h source=%h depth=%h",last6,source6,depth6);
  active_tab=2;bind_to(344,326);
  wait(commits==7);repeat(100)@(negedge clk);
  if(source13!==3 || depth13!==127 || last13!==48'hF07D56067FF7)
   $fatal(1,"LFO3 rebind13 %h",last13);
  // Real AMOUNT-minus contacts cover signed depth through the binding FSM.
  for(n=0;n<32;n=n+1)begin packet(1040,675,1);packet(0,0,0);end
  repeat(20)@(negedge clk);
  if(source13!==3 || depth13!==8'h81)$fatal(1,"negative depth state %h/%h",source13,depth13);
  wait(last13==48'hF07D560701F7);previous_commit=commits;
  wait(commits>previous_commit);repeat(100)@(negedge clk);
  packet(1200,675,1);packet(0,0,0);
  repeat(20)@(negedge clk);
  if(source13!==0 || depth13!==8'h81)$fatal(1,"clear must only remove source");
  wait(last13==48'hF07D560101F7);previous_commit=commits;
  wait(commits>previous_commit);repeat(100)@(negedge clk);
  // Drop without UP: only the production binding watchdog commits the route.
  packet(1140,385,1);packet(1140,385,1);packet(0,0,0);
  packet(980,485,1);packet(800,360,1);packet(134,268,1);packet(134,268,1);
  wait(binding_dragging==0);packet(0,0,0);
  wait(last6==48'hF07D4F067FF7);previous_commit=commits;
  wait(commits>previous_commit);repeat(100)@(negedge clk);
  if(source6!==3 || depth6!==127)$fatal(1,"timeout rebind6 state");
  $display("PASS: real binding routes6/13, LFO1/2/3, signed depth, clear, no-UP timeout, curve UART; frames=%0d",frames);$finish;
 end
 initial begin #5000000;$fatal(1,"timeout commits=%0d",commits);end
endmodule
