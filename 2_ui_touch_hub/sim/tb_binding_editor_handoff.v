`timescale 1ns/1ps
// Real editor arbitration: touch packets feed the binder and capture-gated
// LFO/FX editors exactly as in ui_top_renderer. No internal state is forced.
module tb_binding_editor_handoff;
reg clk=0,rst_n=0,tv=0,td=0;
reg [13:0] x=0,y=0;
wire armed,dragging,capture;
wire [1:0] tab;
wire [48:0] nodes;
wire [105:0] sources;
wire [423:0] depths;
wire [10:0] switches;
wire [8:0] phase;
reg [48:0] saved_nodes;
reg [8:0] saved_phase;
reg saved_switch;
integer round;
always #10 clk=~clk;
lfo_binding_state #(.WATCHDOG_CYCLES(1000)) binder(
 .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
 .active_tab(tab),.armed(armed),.dragging(dragging),.capture_active(capture),
 .sources(sources),.depths(depths));
lfo_editor_state #(.WATCHDOG_CYCLES(100),.PREVIEW_BASE_TICKS(128)) editor(
 .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td && !capture),
 .touch_x(x),.touch_y(y),.active_tab(tab),.nodes(nodes),.phase(phase));
fx_editor_state #(.WATCHDOG_CYCLES(100)) fx(
 .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td && !capture),
 .touch_x(x),.touch_y(y),.external_valid(1'b0),.external_id(8'd0),
 .external_value(7'd0),.switches(switches));
task packet;
 input integer px,py;input down;
 begin @(negedge clk);x=px;y=py;td=down;tv=1;
 @(negedge clk);tv=0;repeat(8)@(negedge clk);end
endtask
initial begin
 repeat(6)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
 for(round=0;round<20;round=round+1)begin
  // Edit, omit UP, wait 75 ms scaled (shorter than 500-ms drag grace).
  packet(960,450+round,1);saved_nodes=nodes;
  repeat(150)@(negedge clk);
  packet(1140,385,1);
  if(!armed || !capture)$fatal(1,"Editor -> BIND failed round=%0d",round);
  // Even an immediate no-UP handoff into graph must preserve curve values.
  packet(980,500,1);
  if(!dragging || nodes!==saved_nodes)$fatal(1,"Graph handoff edited instead of lifting curve");
  packet(1030,268,1);packet(0,0,0);
  if(capture || sources[48+:2]!=1 || nodes!==saved_nodes)
   $fatal(1,"Drop did not release all editors or preserve curve");
  packet(1140,385,1);packet(0,0,0);packet(970,268,1);
  repeat(150)@(negedge clk); // omit target UP as well
  if(capture)$fatal(1,"Tap contact blocked independent FX editor");
  saved_switch=switches[0];packet(760,387,1);packet(0,0,0);
  if(switches[0]===saved_switch)$fatal(1,"FX not interactive after binding");
 end
 saved_phase=phase;repeat(40)@(negedge clk);
 if(phase===saved_phase)$fatal(1,"LFO preview stopped during control traffic");
 $display("PASS: 20 real LFO-edit/BIND/no-UP drag cycles, curve preservation, binding commit, tap-contact release, FX recovery and running preview");
 $finish;
end
initial begin #1000000;$fatal(1,"Binding/editor timeout");end
endmodule
