`timescale 1ns/1ps
`include "params.vh"
module tb_lfo_capabilities;
 `include "mod_targets.vh"
 reg clk=0,rst_n=0,touch_valid=0,touch_down=0,cancel=0;
 reg [13:0] touch_x=0,touch_y=0;reg [1:0] active_tab=0;
 wire [105:0] sources;wire [423:0] depths;
 lfo_binding_state #(.WATCHDOG_CYCLES(100),.CONTACT_TIMEOUT_CYCLES(30)) dut(
  .clk(clk),.rst_n(rst_n),.touch_valid(touch_valid),.touch_down(touch_down),
  .cancel(cancel),.touch_x(touch_x),.touch_y(touch_y),.active_tab(active_tab),.sources(sources),.depths(depths));
 always #10 clk=~clk;
 function connected(input integer n);
  case(n)
   4,6,8,9,10,11,12,13,15,17,18,19,20,21,22,23,24,28,34,35,39,40,41,46:connected=1;
   default:connected=0;
  endcase
 endfunction
 task packet(input integer x,y,input bit down);begin
  @(negedge clk);touch_x=x;touch_y=y;touch_down=down;touch_valid=1;
  @(negedge clk);touch_valid=0;repeat(6)@(negedge clk);
 end endtask
 task click(input integer x,y);begin packet(x,y,1);packet(0,0,0);end endtask
 integer n,supported=0,unsupported=0;reg [7:0] ids[0:52];
 initial begin
  $readmemh("target_ids_before.hex",ids);
  repeat(4)@(negedge clk);rst_n=1;
  for(n=0;n<53;n=n+1)begin
   if(mod_id(n)!==ids[n])$fatal(1,"protocol position changed %0d",n);
   // Real drag/drop, not assignment to cfg_sources.
   click(1140,385);packet(980,485,1);packet(mod_cx(n),mod_cy(n),1);packet(0,0,0);
   if(connected(n))begin
    supported=supported+1;
    if(sources[n*2+:2]!==1 || depths[n*8+:8]!==127)$fatal(1,"connected target blocked %0d",n);
   end else begin
    unsupported=unsupported+1;
    if(sources[n*2+:2]!==0)$fatal(1,"NC target bound %0d",n);
    // Optional tap path must also reject a new unsupported binding.
    click(1140,385);click(mod_cx(n),mod_cy(n));
    if(sources[n*2+:2]!==0)$fatal(1,"NC tap bound %0d",n);
   end
  end
  // Model an already saved unsupported route; capability gating must preserve it.
  @(negedge clk);dut.source[0]=2;dut.depth[0]=-63;
  click(1140,385);packet(980,485,1);packet(mod_cx(0),mod_cy(0),1);packet(0,0,0);
  if(sources[1:0]!==2 || depths[7:0]!==8'hC1)$fatal(1,"saved NC route erased/overwritten");
  if(supported!=24 || unsupported!=29)$fatal(1,"mask counts");
  $display("PASS: 53 indices unchanged; 24 real drag bindings; 29 NC drag/tap rejections; saved NC route preserved");$finish;
 end
 initial begin #2000000;$fatal(1,"capability watchdog");end
endmodule
