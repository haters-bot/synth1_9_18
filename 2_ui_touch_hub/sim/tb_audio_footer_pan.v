`timescale 1ns/1ps
`include "params.vh"
`include "font_3x5.vh"
module tb_audio_footer_pan;
 reg clk=0,rst_n=0,tv=0,td=0;reg [15:0] raw_x=0,raw_y=0;
 wire delta,button,focus;wire [7:0] selected;
 reg [13:0] x=264,y=326;reg [6:0] pan=64;
 wire hit;wire [23:0] rgb;
 integer events=0,i;
 always #10 clk=~clk;
 touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(tv),.raw_touch_x(raw_x),.raw_touch_y(raw_y),.touch_state(td),
  .curve_capture_active(1'b0),.curve_focus_valid(1'b0),.curve_focus_id(8'd0),
  .param_delta_valid(delta),.btn_tap_valid(button),.focus_event_valid(focus),.selected_param_id(selected));
 knob_vector_unit knobs(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.selected_param_id(8'd0),
  .val_osca_pan(pan),.val_oscb_pan(pan),.val_flt_pan(pan),.out_hit_knob(hit),.out_knob_rgb(rgb));
 always @(posedge clk)if(delta || button || focus)events=events+1;
 task packet(input integer px,py,input bit down);begin
  @(negedge clk);raw_x=(px*65536+5119)/5120;raw_y=(py*65536+4914)/4915;td=down;tv=1;
  @(negedge clk);tv=0;repeat(12)@(negedge clk);
 end endtask
 task check_pan(input integer px,py);begin
  @(negedge clk);x=px;y=py;pan=64;repeat(8)@(negedge clk);
  if(knobs.s1_ux!==6'sd0 || knobs.s1_uy!==-6'sd31 || knobs.value_ch1!==`CH_C)$fatal(1,"PAN64 is not vertical/C");
  pan=63;repeat(8)@(negedge clk);if(knobs.s1_ux!==-6'sd6)$fatal(1,"PAN63 should point left");
  pan=65;repeat(8)@(negedge clk);if(knobs.s1_ux!==6'sd6)$fatal(1,"PAN65 should point right");
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<8;i=i+1)begin
   packet(i<4 ? 80+i*90 : 496+(i-4)*90,230,1);
   packet(i<4 ? 90+i*90 : 506+(i-4)*90,220,1);packet(0,0,0);
  end
  if(events!=0)$fatal(1,"WARP/SD footer leaked into legacy knob/button events");
  packet(264,326,1);packet(280,316,1);packet(0,0,0);
  if(events==0 || selected!=`PARAM_ID_OSCA_PAN)$fatal(1,"ordinary PAN touch stopped working");
  check_pan(264,326);check_pan(680,326);check_pan(1130,268);
  $display("PASS: normalized real touch reserves WARP/SD footer without old knob writes; normal PAN touch retained, all three PAN64 needles vertical/C and 63/65 point left/right");$finish;
 end
 initial begin #1000000;$fatal(1,"footer/PAN watchdog");end
endmodule
