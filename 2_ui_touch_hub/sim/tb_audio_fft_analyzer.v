`timescale 1ns/1ps
module tb_audio_fft_analyzer;
 reg clk=0,rst_n=0,link_up=0,sample_valid=0;
 reg signed [15:0] sample=0;
 reg [4:0] spectrum_address=0,history_band=0;
 reg [5:0] history_column=63;
 wire [5:0] spectrum_value,history_value;
 wire ready,frame_valid;
 wire [4:0] peak_band;
 wire peak_valid;
 wire [9:0] peak_bin;
 wire [15:0] peak_hz,centroid_hz;
 reg [15:0] stimuli[0:7167];
 integer frame,n,bin,fd,fd_levels,band,column,cycles=0,last_sample,latency,max_latency=0;
 audio_fft_analyzer #(.HISTORY_HOP(1)) dut(.*);
 always #10 clk=~clk;
 always @(posedge clk)cycles=cycles+1;
 initial begin
  $readmemh("fft_input.hex",stimuli);
  fd=$fopen("fft_bins.txt","w");
  fd_levels=$fopen("fft_levels.txt","w");
  repeat(5)@(negedge clk);rst_n=1;link_up=1;
  for(frame=0;frame<71;frame=frame+1)begin
   for(n=0;n<1024;n=n+1)begin
    while(dut.state!=0)@(negedge clk);
    sample=frame<7 ? stimuli[frame*1024+n] : 16'd0;sample_valid=1;
    @(negedge clk);sample_valid=0;
    // Actual sample period is much longer; this deliberately also tests
    // capture/window/store completion with only seven clocks per sample.
    repeat(6)@(negedge clk);
   end
   last_sample=cycles;
   while(!frame_valid)@(negedge clk);
   latency=cycles-last_sample;
   if(latency>max_latency)max_latency=latency;
   if(latency>50000)$fatal(1,"FFT exceeded 1 ms processing budget: %0d",latency);
   if(!ready)$fatal(1,"Missing frame ready");
   if(frame==0 && peak_band!==5'd7)$fatal(1,"8-bin tone peak band mismatch: %0d",peak_band);
   if(frame==1 && peak_band!==5'd20)$fatal(1,"64-bin tone peak band mismatch: %0d",peak_band);
   if(frame==5 && peak_band!==5'd2)$fatal(1,"3-bin tone peak band mismatch: %0d",peak_band);
   if(frame==0 && (!peak_valid || peak_bin!=8 || peak_hz!=750))$fatal(1,"Exact 8-bin peak frequency failed");
   if(frame==1 && (!peak_valid || peak_bin!=64 || peak_hz!=6000))$fatal(1,"Exact 64-bin peak frequency failed");
   if(frame==5 && (!peak_valid || peak_bin!=3 || peak_hz!=281))$fatal(1,"Exact 3-bin peak frequency failed");
   if(frame==6 && (!peak_valid || peak_bin!=500 || peak_band!=31 || peak_hz!=46875))$fatal(1,"High frequency peak overflowed: %0d Hz",peak_hz);
   if((frame==3 || frame>=7) && (peak_valid || peak_hz || centroid_hz))$fatal(1,"Silent peak/centroid is valid");
   if(frame<7)$fdisplay(fd_levels,"F %0d %0d %0d %0d %0d",frame,peak_valid,peak_bin,peak_hz,centroid_hz);
   if(frame<7)for(bin=0;bin<1024;bin=bin+1)
    $fdisplay(fd,"%0d %0d %0d %0d",frame,bin,
       $signed(dut.source_bank ? dut.real_memory1[bin] : dut.real_memory0[bin]),
       $signed(dut.source_bank ? dut.imag_memory1[bin] : dut.imag_memory0[bin]));
   for(band=0;band<32;band=band+1)begin
    spectrum_address=band;history_band=band;
    repeat(2)@(negedge clk);
    if(frame<7)$fdisplay(fd_levels,"%0d %0d %0d",frame,band,spectrum_value);
    if(spectrum_value!==history_value)$fatal(1,"Newest history column differs from spectrum frame %0d band %0d",frame,band);
    if(frame>=7 && spectrum_value!==0)$fatal(1,"Silence retained spectrum data");
   end
  end
  $fclose(fd);
  $fclose(fd_levels);
  if(dut.history_count!=64 || dut.history_write!=7)$fatal(1,"History ring did not wrap");
  for(column=0;column<64;column=column+1)
   for(band=0;band<32;band=band+1)begin
    history_column=column;history_band=band;repeat(2)@(negedge clk);
    if(history_value!==0)$fatal(1,"Old spectrum survived 64 silent history columns");
   end
  link_up=0;repeat(3)@(negedge clk);
  if(ready || frame_valid || history_value!==0)$fatal(1,"Disconnect retained valid history");
  link_up=1;repeat(8)@(negedge clk);
  if(ready)$fatal(1,"Reconnect displayed data before a complete new FFT frame");
  $display("PASS: 71 FFT frames, max processing %0d clocks (<1 ms), spectrum/history consistency, 64-column wrap, silence and disconnect",max_latency);
  $finish;
 end
 initial begin #200000000;$fatal(1,"FFT test watchdog");end
endmodule
