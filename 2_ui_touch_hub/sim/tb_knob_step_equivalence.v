`timescale 1ns/1ps
`include "params.vh"
module tb_knob_step_equivalence;
 `include "knob_param_map.vh"
 reg clk=0,rst_n=0,cw=0;reg [7:0] id=0;reg [63:0] steps=0;
 wire signed [7:0] actual;
 knob_ui_control dut(.clk(clk),.rst_n(rst_n),.motion_valid(1'b0),.motion_cw(cw),.button_valid(1'b0),
  .motion_id(id),.button_id(8'd0),.button_action(2'd0),.fx_touch_focus_valid(1'b0),.fx_touch_focus_id(8'd0),
  .touch_focus_valid(1'b0),.touch_down(1'b0),.touch_focus_id(8'd0),.steps(steps),.delta(actual),.focus_id());
 integer pattern,p,d,k,j,checks=0;reg [1:0] code;reg signed [7:0] expected;
 task check;begin
  code=0;for(k=0;k<32;k=k+1)if(knob_param_id(k)==id)code=steps[k*2+:2];
  expected=8'sd1<<code;if(!cw)expected=-expected;
  #1;if(actual!==expected)$fatal(1,"step changed id=%h steps=%h cw=%d got=%d expected=%d",id,steps,cw,actual,expected);
  checks=checks+1;
 end endtask
 initial begin
  for(k=0;k<32;k=k+1)for(j=k+1;j<32;j=j+1)
   if(knob_param_id(k)==knob_param_id(j))$fatal(1,"masked reduction requires unique physical IDs");
  // All IDs/directions for every uniform code, each independently selected
  // knob/code, and 128 unrelated settings words against the old priority mux.
  for(pattern=0;pattern<260;pattern=pattern+1)begin
   if(pattern<4)steps={32{pattern[1:0]}};
   else if(pattern<132)begin steps=0;steps[((pattern-4)/4)*2+:2]=(pattern-4)%4;end
   else steps={$urandom,$urandom};
   for(p=0;p<256;p=p+1)for(d=0;d<2;d=d+1)begin id=p;cw=d;check;end
  end
  $display("PASS: balanced physical step decoder equals old priority mux in %0d ID/setting/direction cases; all32 IDs unique",checks);$finish;
 end
endmodule
