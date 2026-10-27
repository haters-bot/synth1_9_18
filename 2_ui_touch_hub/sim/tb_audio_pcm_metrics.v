`timescale 1ns/1ps
module tb_audio_pcm_metrics;
 reg clk=0,rst_n=0,link_up=0,pair_valid=0;
 reg signed [15:0] left_sample=0,right_sample=0;
 wire ready,frame_valid,correlation_valid;
 wire [15:0] rms_left,rms_right,peak_left,peak_right,peak_hold;
 wire signed [11:0] rms_db10,peak_db10,hold_db10;
 wire [11:0] crest_db10;
 wire signed [7:0] correlation,balance;
 wire [5:0] clip_hold;wire [3:0] transient_hold;
 reg [31:0] stimulus[0:16383];
 integer f,n,fd,frames_seen=0;
 reg logging=1;
 audio_pcm_metrics dut(.*);
 always #10 clk=~clk;
 always @(negedge clk)if(frame_valid&&logging)begin
  $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
   frames_seen,rms_left,rms_right,peak_left,peak_right,rms_db10,peak_db10,
   crest_db10,correlation,balance,correlation_valid,peak_hold,clip_hold,hold_db10);
  frames_seen=frames_seen+1;
 end
 task constant_window;
  input signed [15:0] value;integer j;
  begin
   left_sample=value;right_sample=value;pair_valid=1;
   repeat(1024)@(negedge clk);pair_valid=0;repeat(200)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("metrics_input.hex",stimulus);fd=$fopen("metrics_output.txt","w");
  repeat(5)@(negedge clk);rst_n=1;link_up=1;
  // No sample gaps: sqrt/division must run concurrently with next capture.
  for(f=0;f<16;f=f+1)for(n=0;n<1024;n=n+1)begin
   pair_valid=1;left_sample=stimulus[f*1024+n][31:16];right_sample=stimulus[f*1024+n][15:0];
   @(negedge clk);
  end
  pair_valid=0;repeat(200)@(negedge clk);
  if(frames_seen!=16 || !ready)$fatal(1,"Lost metric windows %0d",frames_seen);
  link_up=0;repeat(5)@(negedge clk);
  if(ready || frame_valid || rms_left || rms_right || peak_left || peak_right ||
     peak_hold || correlation_valid || correlation || balance || clip_hold || transient_hold ||
     rms_db10!=-960 || peak_db10!=-960)$fatal(1,"Stale metrics after disconnect");
  link_up=1;pair_valid=1;left_sample=1000;right_sample=1000;
  repeat(1023)@(negedge clk);pair_valid=0;repeat(200)@(negedge clk);
  if(ready)$fatal(1,"Partial reconnect window published");
  pair_valid=1;@(negedge clk);pair_valid=0;repeat(200)@(negedge clk);
  if(!ready || rms_left!=1000 || rms_right!=1000)$fatal(1,"Fresh reconnect window missing");
  logging=0;
  constant_window(-32768);
  if(peak_hold!=32768 || clip_hold!=48)$fatal(1,"Hold timers not loaded");
  for(f=0;f<94;f=f+1)begin
   constant_window(0);
   if(peak_hold!=32768 || hold_db10!=0)$fatal(1,"Peak hold amplitude/dBFS expired before 94 windows");
   if(f==47 && clip_hold!=0)$fatal(1,"Clip hold did not expire after 48 windows");
  end
  constant_window(0);
  if(peak_hold!=30720 || hold_db10!=0 || rms_db10!=-960 || peak_db10!=-960 || crest_db10 || correlation_valid || transient_hold)
   $fatal(1,"Peak release or silent metrics incorrect");
  constant_window(0);
  if(peak_hold!=28800 || hold_db10< -8 || hold_db10> -4)
   $fatal(1,"Released peak dBFS not based on prior held amplitude: %0d",hold_db10);
  $fclose(fd);$display("PASS: 16 contiguous stereo windows, reconnect validity, 94-window peak hold/decay and 48-window clip expiry");$finish;
 end
 initial begin #5000000;$fatal(1,"Metrics watchdog");end
endmodule
