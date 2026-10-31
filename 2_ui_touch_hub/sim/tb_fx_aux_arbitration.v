`timescale 1ns/1ps
module tb_fx_aux_arbitration;
 reg clk=0,rst_n=0,ev=0,av=0,owned=0;
 reg [7:0] eid=0,aid=0,owner=0;reg [6:0] value=0,aux=0;
 wire [132:0] bank;
 always #10 clk=~clk;
 fx_editor_state #(.AUX_ENABLE(1)) dut(.clk(clk),.rst_n(rst_n),.touch_valid(1'b0),.touch_down(1'b0),.touch_x(14'd0),.touch_y(14'd0),
  .external_valid(ev),.external_id(eid),.external_value(value),.aux_valid(av),.aux_id(aid),.aux_value(aux),
  .aux_owner_valid(owned),.aux_owner_id(owner),.values(bank));
 task writes(input [7:0] a,b,input [6:0] v,w);begin
  @(negedge clk);ev=1;av=1;eid=a;aid=b;value=v;aux=w;
  @(negedge clk);ev=0;av=0;repeat(4)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  writes(8'h60,8'h66,90,100);
  if(bank[0+:7]!==90 || bank[42+:7]!==100)$fatal(1,"simultaneous independent FX edits dropped");
  owned=1;owner=8'h66;writes(8'h66,8'h66,15,101);
  if(bank[42+:7]!==101)$fatal(1,"touch must own captured parameter");
  writes(8'h60,8'h66,91,102);
  if(bank[0+:7]!==91 || bank[42+:7]!==102)$fatal(1,"touch incorrectly blocked different physical knob");
  @(negedge clk);ev=1;eid=8'h84;value=1;@(negedge clk);ev=0;repeat(4)@(negedge clk);
  owner=8'h61;writes(8'h62,8'h61,30,80);
  if(bank[7+:7]!==80 || bank[14+:7]!==80)$fatal(1,"linked alias ownership");
  owned=0;@(negedge clk);ev=1;eid=8'h66;value=17;@(negedge clk);ev=0;repeat(4)@(negedge clk);
  if(bank[42+:7]!==17)$fatal(1,"physical knob did not regain ownership after release");
  $display("PASS: parallel new FX touch/physical writes preserve different IDs; captured touch wins own/linked parameter and physical control resumes after release");$finish;
 end
endmodule
