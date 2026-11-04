`timescale 1ns/1ps
`include "params.vh"
module tb_lfo_nc_overlay;
 `include "mod_targets.vh"
 reg clk=0,rst_n=0;reg [13:0] x=0,y=0;wire hit;wire [23:0] rgb;
 always #10 clk=~clk;
 modulation_overlay dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.sources(106'd0),
  .depths(424'd0),.preview_values(371'd0),.armed(1'b0),.dragging(1'b0),
  .hover_target(6'd63),.selected_target(6'd63),.active_tab(2'd0),
  .touch_x(14'd0),.touch_y(14'd0),.curve_nodes(49'd0),.out_hit(hit),.out_rgb(rgb));
 function connected(input integer n);
  case(n)
   4,6,8,9,10,11,12,13,15,17,18,19,20,21,22,23,24,28,34,35,39,40,41,46:connected=1;
   default:connected=0;
  endcase
 endfunction
 integer n,dx,dy,hits;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(n=0;n<53;n=n+1)begin
   hits=0;
   for(dx=0;dx<16;dx=dx+1)for(dy=0;dy<10;dy=dy+1)begin
    x=mod_cx(n)-8+dx;y=mod_cy(n)-22+dy;
    repeat(12)@(negedge clk);
    if(hit)begin
     hits=hits+1;
     if(rgb[23:16]>170 || rgb[15:8]>174 || rgb[7:0]>182)$fatal(1,"NC badge not gray");
    end
   end
   if(connected(n) && hits!=0)$fatal(1,"supported knob got NC %0d",n);
   if(!connected(n) && hits==0)$fatal(1,"unsupported knob lacks NC %0d",n);
  end
  $display("PASS: actual pixel output has gray NC at all 29 unsupported cells; all 24 unbound supported cells remain clear");$finish;
 end
 initial begin #4000000;$fatal(1,"NC raster watchdog");end
endmodule
