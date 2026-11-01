`timescale 1ns/1ps
module tb_lfo_binding_sysex_e2e;
 reg clk=0,rst_n=0,tv=0,td=0; reg [13:0] x=0,y=0; reg [1:0] tab=0;
 wire [105:0] sources; wire [423:0] depths; wire armed,dragging,capture;
 wire req; wire [47:0] msg; integer seen6=0,seen13=0,commit=0;
 always #10 clk=~clk;
 lfo_binding_state #(.WATCHDOG_CYCLES(1000),.CONTACT_TIMEOUT_CYCLES(50)) b(
 .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.cancel(1'b0),.touch_x(x),.touch_y(y),.active_tab(tab),
 .armed(armed),.dragging(dragging),.capture_active(capture),.selected_target(),.hover_target(),.sources(sources),.depths(depths),.event_valid(),.event_target(),.event_source(),.event_depth());
 lfo_sysex_tx #(.HOLD_CYCLES(20),.FIRST_HOLD_CYCLES(10)) tx(.clk(clk),.rst_n(rst_n),.cfg_nodes(147'd0),.cfg_rates(9'd0),.cfg_steps(3'd0),.cfg_once(3'd0),.cfg_sources(sources),.cfg_depths(depths),.tx_accept(req),.sysex_req(req),.sysex_msgs(msg),.busy());
 task pkt(input integer px,input integer py,input bit down); begin @(negedge clk);x=px;y=py;td=down;tv=1;@(negedge clk);tv=0;repeat(8)@(negedge clk);end endtask
 always @(posedge clk) if(req) begin $display("FRAME %h",msg); if(msg==48'hF07D4F027FF7)seen6=1; if(msg==48'hF07D56027FF7)seen13=1; if(msg==48'hF07D7E0000F7)commit=commit+1; end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  // Wait for the actual initial snapshot/Commit, not a fixed scan-cycle
  // budget. Registered encoders may add preparation clocks without changing
  // any frame bytes or the atomic batch contract.
  wait(commit==1);repeat(5)@(negedge clk);
  pkt(1140,385,1);pkt(0,0,0);pkt(134,268,1);pkt(0,0,0);
  $display("CHECK6 src=%0d dep=%0d",sources[13:12],$signed(depths[55:48]));
  if(sources[13:12]!=1 || depths[55:48]!=127)$fatal(1,"target6 binding state");
  wait(seen6);wait(commit==2);
  pkt(1140,385,1);pkt(0,0,0);pkt(344,326,1);pkt(0,0,0);
  $display("CHECK13 src=%0d dep=%0d",sources[27:26],$signed(depths[111:104]));
  if(sources[27:26]!=1 || depths[111:104]!=127)$fatal(1,"target13 binding state");
  wait(seen13);wait(commit==3);
  $display("PASS: binder to SysEx target 6/13, exact payloads and atomic Commit");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
