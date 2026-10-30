`timescale 1ns/1ps
// Compare the retimed background against the original combinational page mux
// on consecutive, changing pixels, independent of foreground glyph overlays.
module tb_navigation_background_pipeline;
 reg clk=0,rst_n=0;
 always #10 clk=~clk;
 reg [13:0] in_x=0,in_y=0;
 reg [2:0] view=0;
 reg [7:0] settings_section_id=1;
 reg show_diagnostics=0;
 reg [63:0] knob_steps=64'he4e4e4e4e4e4e4e4;
 reg [1:0] knob_page=0,performance_mode=0;
 reg [31:0] performance_active_keys=0,performance_guide_keys=0;
 reg [15:0] performance_progress=0;
 reg performance_running=0,performance_paused=0,performance_gateway_up=0,performance_recording=0;
 reg [3:0] performance_record_status=0;
 reg [5:0] performance_next_key=0;
 reg performance_next_key_valid=0;
 reg [8:0] performance_next_key_y=0;
 ui_navigation_renderer dut(
  .clk(clk),.rst_n(rst_n),.in_x(in_x),.in_y(in_y),.view(view),.settings_section_id(settings_section_id),
  .show_diagnostics(show_diagnostics),.usb_connected(1'b0),.usb_error(1'b0),
  .macro_values(28'd0),.knob_steps(knob_steps),.knob_page(knob_page),.apply_step(2'd0),.plot_scales(24'd0),
  .audio_sample_valid(1'b0),.audio_sample(16'd0),.audio_right_sample(16'd0),.audio_stereo_valid(1'b0),
  .audio_link_up(1'b0),.audio_xy_a(16'd0),.audio_xy_b(16'd0),.audio_xy_valid(1'b0),.audio_xy_available(1'b0),
  .performance_active_keys(performance_active_keys),.performance_guide_keys(performance_guide_keys),
  .performance_progress(performance_progress),.performance_running(performance_running),.performance_paused(performance_paused),
  .performance_mode(performance_mode),.performance_gateway_up(performance_gateway_up),.performance_recording(performance_recording),
  .performance_record_status(performance_record_status),.performance_next_key(performance_next_key),
  .performance_next_key_valid(performance_next_key_valid),.performance_next_key_y(performance_next_key_y),.out_hit(),.out_rgb());
 reg [23:0] bg_previous,bg_expected;
 reg hit_previous,hit_expected;
 integer warm=0,checks=0,i,x,y,section;
 always @(posedge clk)if(rst_n)begin
  bg_expected=bg_previous;bg_previous=dut.bg;
  hit_expected=hit_previous;hit_previous=dut.hit;
  warm=warm+1;
  #1;
  if(warm>1)begin
   if(dut.b1!==bg_expected || dut.h1!==hit_expected)
    $fatal(1,"background retiming changed pixel color/hit: actual=%h expected=%h",dut.b1,bg_expected);
   checks=checks+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<50000;i=i+1)begin
   @(negedge clk);in_x=$urandom_range(0,1290);in_y=$urandom_range(0,725);
   view=$urandom_range(0,4);settings_section_id=$urandom_range(1,4);
   show_diagnostics=i[0];knob_steps={$urandom,$urandom};knob_page=i[1:0];
   performance_mode=i%3;performance_active_keys=$urandom;performance_guide_keys=$urandom;
   performance_progress=$urandom;performance_running=i[0];performance_paused=i[1];
   performance_gateway_up=i[2];performance_recording=i[3];performance_record_status=i[3:0];
   performance_next_key=i%32;performance_next_key_y=i%384;performance_next_key_valid=i[4];
  end
  // Sweep the settings rectangles (including shared edges) in every section.
  view=3;
  for(section=1;section<=4;section=section+1)begin
   settings_section_id=section;
   for(y=85;y<620;y=y+3)for(x=16;x<1260;x=x+4)begin
    @(negedge clk);in_x=x;in_y=y;
   end
  end
  repeat(4)@(negedge clk);
  $display("PASS: %0d changing pixels match original backgrounds and hit flags at unchanged pipeline latency",checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"background pipeline watchdog");end
endmodule
