`timescale 1ns/1ps
module tb_audio_visual_windows;
 reg clk=0,rst_n=0,audio_sample_valid=0,audio_link_up=0;
 reg signed [15:0] audio_sample=0;
 reg [13:0] x=0,y=0;
 wire hit;wire [23:0] rgb;
 integer i;
 integer glyph,heading,px,py,cell_checks=0;
 reg [1:0] expected_coverage,actual_coverage;
 integer stream_checks=0,j;
 reg stream_check=0;
 reg [23:0] expected_pixel;
 reg [23:0] pixel_history[0:4];
 ui_navigation_renderer dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),
  .view(2'd1),.settings_section_id(8'd1),.show_diagnostics(1'b0),
  .usb_connected(1'b0),.usb_error(1'b0),.macro_values(28'd0),
  .audio_sample_valid(audio_sample_valid),.audio_sample(audio_sample),
  .audio_right_sample(audio_sample),.audio_stereo_valid(audio_sample_valid),
  .audio_link_up(audio_link_up),.out_hit(hit),.out_rgb(rgb));
 always #10 clk=~clk;
 always @(posedge clk)if(stream_check)begin
  for(j=4;j>0;j=j-1)pixel_history[j]=pixel_history[j-1];
  pixel_history[0]=expected_pixel;stream_checks=stream_checks+1;
  #2;if(stream_checks>5 && rgb!==pixel_history[4])
   $fatal(1,"Live waveform pipeline shifted: expected %h got %h",pixel_history[4],rgb);
 end
 task send_samples;
  input signed [15:0] value;input integer count;integer n;
  begin
   for(n=0;n<count;n=n+1)begin
    @(negedge clk);audio_sample=value;audio_sample_valid=1;
    @(negedge clk);audio_sample_valid=0;
   end
  end
 endtask
 task pixel;
  input [13:0] px,py;input [23:0] expected;
  begin
   @(negedge clk);x=px;y=py;repeat(7)@(negedge clk);
   if(!hit || rgb!==expected) $fatal(1,"Pixel (%0d,%0d) expected %h got %h",px,py,expected,rgb);
  end
 endtask
 initial begin
  // Exhaustively preserve every old font pixel while redistributing its
  // row/column lookup across the existing five navigation pipeline stages.
  for(glyph=0;glyph<64;glyph=glyph+1)
   for(heading=0;heading<2;heading=heading+1)
    for(px=0;px<16;px=px+1)for(py=0;py<32;py=py+1)begin
     expected_coverage=dut.navigation_font(glyph,heading,px,py);
     if(heading ? (px>=14 || py>=20) : (px>=12 || py>=16))actual_coverage=0;
     else actual_coverage=dut.glyph_column(
       dut.get_font_7x10_row(glyph,dut.glyph_y(heading,py)),dut.glyph_x(heading,px));
     if(actual_coverage!==expected_coverage)$fatal(1,"Font mapping changed ch=%0d heading=%0d x=%0d y=%0d",glyph,heading,px,py);
     cell_checks=cell_checks+1;
    end
  if(cell_checks!=65536)$fatal(1,"Incomplete font coverage");
  $display("PASS: all 65536 normal/heading glyph coverage cells match the unchanged navigation font");
  #1;
  for(i=0;i<8192;i=i+1)
   if(dut.navigation_char_rom[i]!==dut.navigation_char(i>>6,i&63))
    $fatal(1,"Character ROM differs from reference at address %0d",i);
  $display("PASS: all 8192 synchronous character ROM entries match the original decoder");
  repeat(5)@(negedge clk);rst_n=1;audio_link_up=1;
  send_samples(16'sd4096,1023);
  if(dut.waveform_ready || dut.metrics_ready) $fatal(1,"History/meter became ready too early");
  send_samples(16'sd4096,1);
  if(!dut.waveform_ready) $fatal(1,"History did not become ready after 1024 source samples");
  for(i=0;i<128;i=i+1)if(dut.u_waveform.memory[{dut.u_waveform.display_bank,7'd0}+i]!==8'h10)
   $fatal(1,"Snapshot location %0d invalid",i);
  pixel(496,240,24'h61DED1);pixel(750,240,24'h61DED1);
  pixel(496,260,24'h0B131D);
  repeat(200)@(negedge clk);
  if(!dut.metrics_ready || dut.metrics_rms_l!=4096 || dut.metrics_rms_r!=4096)
   $fatal(1,"Real stereo metrics not integrated");
  if(dut.audio_digits[0]!==20'h00181 || dut.audio_digits[1]!==20'h00181 ||
     dut.audio_digits[5]!==20'h00100 || dut.audio_digits[6]!==20'h00000)
   $fatal(1,"Cached displayed numbers are incorrect");
  if(dut.correlation_x!=1184)$fatal(1,"Positive stereo cursor overflowed");
  pixel(140,248,24'h61DED1);pixel(140,200,24'h0B131D);
  pixel(1064,500,24'h65CDA4);pixel(1220,500,24'h26394B);
  pixel(1064,536,24'h61DED1);pixel(1064,572,24'h26394B);
  @(negedge clk);audio_link_up=0;repeat(3)@(negedge clk);audio_link_up=1;
  send_samples(-16'sd32768,1024);
  repeat(200)@(negedge clk);
  pixel(496,312,24'h61DED1);pixel(1220,500,24'h65CDA4);
  if(dut.metrics_clip!=48)$fatal(1,"New clipping indicator missing");
  send_samples(16'sd0,2048); // auto-trigger then a complete silent capture
  repeat(200)@(negedge clk);
  pixel(496,248,24'h61DED1);pixel(1064,536,24'h26394B);
  // A nonuniform snapshot verifies read addressing and both plotted edges.
  @(negedge clk);audio_link_up=0;repeat(3)@(negedge clk);audio_link_up=1;
  for(i=0;i<128;i=i+1) send_samples(i*256,8);
  pixel(496,248,24'h61DED1);pixel(750,185,24'h61DED1);
  send_samples(-16'sd16384,8);
  pixel(496,248,24'h61DED1);pixel(750,185,24'h61DED1);
  // Vary addresses and expected colors on every pixel clock: a misplaced
  // RAM-read stage must fail even when the output later settles correctly.
  @(negedge clk);stream_check=1;
  for(i=0;i<80;i=i+1)begin
   case(i%4)
    0:begin x=496;y=248;expected_pixel=24'h61DED1;end
    1:begin x=750;y=185;expected_pixel=24'h61DED1;end
    2:begin x=496;y=260;expected_pixel=24'h0B131D;end
    3:begin x=750;y=320;expected_pixel=24'h152331;end // y=320 is a grid line
   endcase
   @(negedge clk);
  end
  stream_check=0;
  @(negedge clk);audio_link_up=0;repeat(8)@(negedge clk);
  if(dut.waveform_ready || dut.metrics_ready || dut.metrics_clip) $fatal(1,"Stale audio remained after disconnect");
  pixel(496,248,24'hD5AD78);pixel(1064,500,24'h26394B);
  pixel(140,248,24'h0B131D); // no fabricated notes/energy on disconnect
  pixel(169,400,24'h1B2B3C); // peak marker must not cross tile headings
  $display("PASS: immutable triggered PCM snapshots, energy ring, RMS/dBFS digits, stereo cursor, meters and disconnect clearing");
  $finish;
 end
 initial begin #2000000;$fatal(1,"Visual windows watchdog");end
endmodule
