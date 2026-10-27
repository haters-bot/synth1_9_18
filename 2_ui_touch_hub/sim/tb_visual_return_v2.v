`timescale 1ns/1ps
// Real serializers and asynchronous UI receiver. Expected samples are derived
// from the external frame boundary, never from a DUT shift register.
module tb_visual_return_v2;
 reg tx_clk=0,clk=0,rst_n=0,enable=1,v2=1,checking=0,tone=0;
 reg signed [15:0] final_l=0,final_r=0,a=0,b=0;
 wire vb,vl,vd,lb,ll,ld;
 wire signed [15:0] sample,sample_right,osc_a_sample,osc_b_sample;
 wire sample_valid,stereo_valid,xy_valid,xy_available,link_up;
 reg signed [15:0] expected_l=0,expected_r=0,expected_a=0,expected_b=0;
 reg signed [15:0] previous_a=0,previous_b=0;
 integer frames=0,left_checks=0,right_checks=0,xy_checks=0,n,angle=0;
 real theta;
 wire bclk=enable && (v2 ? vb : lb);
 wire lrck=v2 ? vl : ll;
 wire din=v2 ? vd : ld;
 always #10 tx_clk=~tx_clk;
 // 49.75 MHz sampling clock, independent phase/frequency from the audio FPGA.
 always #10.05 clk=~clk;
 i2s_visual_tx tx(.clk(tx_clk),.rst_n(rst_n),.final_left(final_l),
  .final_right(final_r),.osc_a(a),.osc_b(b),.bclk(vb),.lrck(vl),.sdata(vd));
 i2s_tx legacy(.sys_clk(tx_clk),.rst_n(rst_n),.sample_data(final_l),
  .bclk(lb),.lrck(ll),.sdata(ld));
 i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(1000)) rx(.clk(clk),.rst_n(rst_n),
  .i2s_bclk(bclk),.i2s_lrc(lrck),.i2s_din(din),.*);
 always @(negedge vl)if(rst_n && v2)begin
  previous_a=expected_a;previous_b=expected_b;
  expected_a=a;expected_b=b;expected_l=final_l;expected_r=final_r;frames=frames+1;
  if(tone)begin
   // Deliberately keep final output silent while the analysis taps oscillate.
   #1;theta=6.283185307179586*angle/128.0;
   a=$rtoi(14000*$sin(theta));b=$rtoi(11000*$cos(theta));
   angle=(angle+1)%128;
  end
 end
 always @(posedge clk)begin
  #1;
  if(checking && v2)begin
   if(sample_valid)begin
    if(sample!==expected_l)$fatal(1,"V2 final L polluted by oscillator payload: %h vs %h",sample,expected_l);
    left_checks=left_checks+1;
   end
   if(stereo_valid)begin
    if(sample_right!==expected_r)$fatal(1,"V2 final R mismatch");
    right_checks=right_checks+1;
   end
   if(xy_valid)begin
    if(!xy_available || osc_a_sample!==previous_a || osc_b_sample!==previous_b)
     $fatal(1,"A/B pair is shifted or torn: %d,%d expected %d,%d",osc_a_sample,osc_b_sample,previous_a,previous_b);
    xy_checks=xy_checks+1;
   end
  end
 end
 // Exercise the complete navigation renderer, including its production
 // routing to XY, FFT, waveform, energy and final-output meters.
 wire phase_pixel,phase_ready,metrics_ready,metrics_frame_valid;
 reg [12:0] read_address=0;
 wire [15:0] rms_l,rms_r;
 wire [13:0] pixel_x=14'd930+{6'd0,read_address[6:0],1'b0};
 wire [13:0] pixel_y=14'd184+{7'd0,read_address[12:7],1'b0};
 wire [23:0] pixel_rgb;
 ui_navigation_renderer display(.clk(clk),.rst_n(rst_n),.in_x(pixel_x),.in_y(pixel_y),
  .view(2'd1),.settings_section_id(8'd0),.show_diagnostics(1'b0),
  .usb_connected(1'b0),.usb_error(1'b0),.macro_values(28'd0),
  .knob_steps(64'd0),.knob_page(2'd0),.apply_step(2'd0),.plot_scales(24'd0),
  .audio_sample_valid(sample_valid),.audio_sample(sample),.audio_right_sample(sample_right),
  .audio_stereo_valid(stereo_valid),.audio_link_up(link_up),
  .audio_xy_a(osc_a_sample),.audio_xy_b(osc_b_sample),
  .audio_xy_valid(xy_valid),.audio_xy_available(xy_available),.out_rgb(pixel_rgb));
 assign phase_pixel=pixel_rgb==24'h67CDE0;
 assign phase_ready=display.phase_ready;
 assign metrics_ready=display.metrics_ready;
 assign rms_l=display.metrics_rms_l;
 assign rms_r=display.metrics_rms_r;
 integer occupied=0,off_diagonal=0;
 initial begin
  repeat(10)@(negedge clk);rst_n=1;
  // Distinct channels and sign/LSB corners expose slot and word swaps.
  for(n=0;n<12;n=n+1)begin
   checking=0;
   final_l=n==0 ? 16'sh8000 : n==1 ? 16'sh7fff : n*193-1729;
   final_r=n==0 ? 16'sh7fff : n==1 ? 16'sh8000 : 9023-n*409;
   a=n==2 ? 16'sh8001 : -16001+n*307;
   b=n==2 ? 16'sh7ffe : 12002-n*719;
   #50000;checking=1;#180000;
  end
  checking=0;final_l=0;final_r=0;tone=1;
  #50000;checking=1;
  // 2048 pairs complete one plot bank after the RAM clear interval.
  #24000000;
  if(!phase_ready || !metrics_ready || rms_l!=0 || rms_r!=0)
   $fatal(1,"Analysis taps changed final-output measurements or plot not ready");
  if(!display.waveform_ready || !display.spectrum_ready || display.spectrum_peak_valid)
   $fatal(1,"Waveform/FFT did not retain the silent final-output stream");
  for(n=0;n<8192;n=n+1)begin
   read_address=n;repeat(8)@(negedge clk);
   if(phase_pixel)begin
    occupied=occupied+1;
    if((n%128)<56 && (n/128)<28)off_diagonal=off_diagonal+1;
   end
  end
  if(occupied<12 || off_diagonal<2)$fatal(1,"Quadrature OSC A/B did not draw an ellipse");
  checking=0;tone=0;enable=0;#30000;
  if(link_up || xy_available || phase_ready)$fatal(1,"Disconnect kept old XY data live");
  v2=0;enable=1;final_l=1234;#100000;
  if(!link_up || sample!=1234 || sample_right!=1234 || xy_available)
   $fatal(1,"Legacy PCM fallback invented OSC A/B or lost final audio");
  enable=0;#30000;v2=1;enable=1;#100000;
  if(!xy_available)$fatal(1,"V2 reconnect did not reacquire OSC A/B");
  if(left_checks<2200 || right_checks<2200 || xy_checks<2200)$fatal(1,"Incomplete transport coverage");
  $display("PASS: V2 async I2S %0d final-L / %0d final-R / %0d coherent OSC A:B pairs; real ellipse %0d pixels, final-output silence isolated, legacy fallback/disconnect/reconnect",left_checks,right_checks,xy_checks,occupied);
  $finish;
 end
 initial begin #40000000;$fatal(1,"Visual return V2 watchdog");end
endmodule
