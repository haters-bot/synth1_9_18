`timescale 1ns/1ps
// Exercise production navigation with NO OSC A/B transport. Distinct stereo
// PCM must reach both waveform traces and the phase occupancy RAM intact.
module tb_stereo_output_views;
reg clk=0,rst_n=0,link=0,pair_valid=0;
reg signed [15:0] left_pcm=0,right_pcm=0;
reg [13:0] x=0,y=0;
wire hit;wire [23:0] rgb;
integer i,j,phase_checks=0,wave_checks=0;
always #10 clk=~clk;
ui_navigation_renderer dut(
 .clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.view(3'd1),
 .settings_section_id(8'd1),.show_diagnostics(1'b0),.usb_connected(1'b0),.usb_error(1'b0),
 .macro_values(28'd0),.knob_steps(64'd0),.knob_page(2'd0),.apply_step(2'd0),.plot_scales(24'd0),
 .audio_sample_valid(pair_valid),.audio_sample(left_pcm),.audio_right_sample(right_pcm),
 .audio_stereo_valid(pair_valid),.audio_link_up(link),
 .audio_xy_a(16'sd12345),.audio_xy_b(-16'sd12345),.audio_xy_valid(1'b0),.audio_xy_available(1'b0),
 .performance_active_keys(32'd0),.performance_guide_keys(32'd0),.performance_progress(16'd0),
 .performance_running(1'b0),.performance_paused(1'b0),.performance_gateway_up(1'b0),
 .performance_recording(1'b0),.performance_record_status(4'd0),.performance_next_key(6'd0),
 .performance_next_key_valid(1'b0),.performance_next_key_y(9'd0),.out_hit(hit),.out_rgb(rgb));
task pixel;
 input integer px,py;input [23:0] expected;
 begin
  @(negedge clk);x=px;y=py;repeat(8)@(negedge clk);
  if(!hit || rgb!==expected)$fatal(1,"stereo pixel %0d,%0d got=%h expected=%h",px,py,rgb,expected);
  wave_checks=wave_checks+1;
 end
endtask
task scenario;
 input signed [15:0] l,r;
 input integer ly,ry,phase_x,phase_y;
 begin
  @(negedge clk);link=0;pair_valid=0;repeat(4)@(negedge clk);
  link=1;left_pcm=l;right_pcm=r;
  // Phase RAM must clear before acquiring one complete bank.
  repeat(8200)@(negedge clk);
  for(j=0;j<2048;j=j+1)begin
   pair_valid=1;@(negedge clk);pair_valid=0;@(negedge clk);
  end
  repeat(12)@(negedge clk);
  if(!dut.waveform_ready || !dut.phase_ready)$fatal(1,"stereo views need OSC transport or failed to fill");
  for(i=0;i<128;i=i+1)begin
   if(dut.u_waveform.memory[{dut.u_waveform.display_bank,7'd0}+i]!==l[15:8] ||
      dut.u_waveform.right_memory[{dut.u_waveform.display_bank,7'd0}+i]!==r[15:8])
    $fatal(1,"stereo snapshot mixed/dropped channel at %0d",i);
  end
  if(dut.u_phase.memory[{dut.u_phase.display_bank,13'd0}+phase_y*128+phase_x]!==1'b1)
   $fatal(1,"phase plot did not use final-output L/R");
  if(dut.u_phase.memory[{dut.u_phase.display_bank,13'd0}+31*128+64]!==1'b0)
   $fatal(1,"phase plot synthesized a center point");
  phase_checks=phase_checks+1;
  pixel(500,ly,ly==ry ? 24'hE6F4FF : 24'h61DED1);
  pixel(500,ry,ly==ry ? 24'hE6F4FF : 24'hF5AD78);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 scenario(16'sd4096,-16'sd8192,240,264,72,39);
 scenario(16'sd0,16'sd8192,248,232,64,23);
 scenario(16'sd8192,16'sd0,232,248,80,31);
 scenario(16'sd8192,-16'sd8192,232,264,80,39);
 scenario(16'sd8192,16'sd8192,232,232,80,23);
 @(negedge clk);link=0;repeat(5)@(negedge clk);
 if(dut.waveform_ready || dut.phase_ready)$fatal(1,"disconnect left stale stereo data");
 if(phase_checks!=5 || wave_checks!=10)$fatal(1,"coverage");
 $display("PASS: final-output L/R phase without OSC transport; synchronized 128-pair captures, distinct/right-only/left-only/anti-phase/mono traces, overlap color, disconnect reset");
 $finish;
end
initial begin #3000000;$fatal(1,"stereo view timeout");end
endmodule
