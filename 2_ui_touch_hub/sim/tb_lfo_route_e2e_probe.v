`timescale 1ns/1ps
module tb_lfo_route_e2e_probe;
 reg clk=0,rst_n=0,tv=0,td=0; reg [13:0] x=0,y=0; reg [1:0] tab=0;
 wire armed,dragging,capture; wire [105:0] sources; wire [423:0] depths;
 lfo_binding_state #(.WATCHDOG_CYCLES(1000),.CONTACT_TIMEOUT_CYCLES(50)) b(
  .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.cancel(1'b0),.touch_x(x),.touch_y(y),.active_tab(tab),
  .armed(armed),.dragging(dragging),.capture_active(capture),.selected_target(),.hover_target(),.sources(sources),.depths(depths),
  .event_valid(),.event_target(),.event_source(),.event_depth());
 always #10 clk=~clk;
 task pkt(input integer px,input integer py,input bit down);
  begin @(negedge clk); x=px;y=py;td=down;tv=1; @(negedge clk);tv=0; repeat(8) @(negedge clk); end
 endtask
 initial begin
  repeat(4) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
  pkt(1140,385,1); pkt(0,0,0); pkt(134,268,1); pkt(0,0,0);
  #1; $display("T6 src=%0d dep=%0d bus=%h %h",sources[13:12],$signed(depths[55:48]),sources[13:12],depths[55:48]);
  pkt(1140,385,1); pkt(0,0,0); pkt(344,326,1); pkt(0,0,0);
  #1; $display("T13 src=%0d dep=%0d bus=%h %h",sources[27:26],$signed(depths[111:104]),sources[27:26],depths[111:104]);
  $finish;
 end
endmodule
