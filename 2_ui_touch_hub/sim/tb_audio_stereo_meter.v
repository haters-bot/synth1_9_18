`timescale 1ns/1ps
module tb_audio_stereo_meter;
 reg clk=0,rst_n=0,link_up=0,frame_valid=0;
 reg [15:0] rms_l=0,rms_r=0,peak_l=0,peak_r=0;
 reg [1:0] gain=0;
 wire signed [11:0] db_l,db_r;
 wire [7:0] width_l,width_r,hold_width_l,hold_width_r;
 integer i;
 audio_stereo_meter dut(.*);
 always #10 clk=~clk;
 task frame;
  begin frame_valid=1;@(negedge clk);frame_valid=0;repeat(20)@(negedge clk);end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;link_up=1;repeat(12)@(negedge clk);
  if(width_l!==0 || width_r!==0)$fatal(1,"Initial silence leaked X/nonzero bars");
  rms_l=4096;rms_r=16384;peak_l=8192;peak_r=32768;
  repeat(12)@(negedge clk);frame();
  if(db_l!=-181 || db_r!=-60 || width_l!=129 || width_r!=150)
   $fatal(1,"Independent meter dB/width failed L=%0d/%0d R=%0d/%0d",db_l,width_l,db_r,width_r);
  if(hold_width_l!=140 || hold_width_r!=160)$fatal(1,"Independent peak holds failed");
  gain=2;repeat(12)@(negedge clk);
  if(db_l!=-181 || db_r!=-60 || width_l!=149 || width_r!=160)$fatal(1,"Display gain changed measured dB or wrong bar gain");
  rms_l=0;rms_r=0;peak_l=0;peak_r=0;
  repeat(12)@(negedge clk);
  frame();if(width_l>=149 || width_r>=160)$fatal(1,"Release did not animate");
  for(i=0;i<80;i=i+1)frame();
  if(width_l!=0 || width_r!=0)$fatal(1,"Silent bars failed to reach zero");
  if(hold_width_l==0 || hold_width_r==0)$fatal(1,"Peak hold vanished before timeout");
  for(i=0;i<240;i=i+1)frame();
  if(dut.held_l!=0 || dut.held_r!=0 || hold_width_l!=0 || hold_width_r!=0)$fatal(1,"Peak hold did not decay to zero");
  rms_l=32768;rms_r=0;peak_l=32768;repeat(12)@(negedge clk);frame();
  if(width_l!=160 || width_r!=0)$fatal(1,"Single left channel was duplicated");
  link_up=0;repeat(4)@(negedge clk);
  if({width_l,width_r,hold_width_l,hold_width_r}!==0)$fatal(1,"Disconnected meters stayed visible");
  $display("PASS: independent L/R dBFS, RMS bars and holds, display-only gain, attack/release, one-second hold/decay, silence and disconnect");$finish;
 end
 initial begin #500000;$fatal(1,"Stereo meter watchdog");end
endmodule
