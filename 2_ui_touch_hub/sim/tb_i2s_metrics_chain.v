`timescale 1ns/1ps
// Production serial transmitter -> asynchronous receiver -> new PCM statistics.
module tb_i2s_metrics_chain;
 reg clk=0,tx_clk=0,rst_n=0,connected=1;
 reg signed [15:0] source_sample=4096;
 wire bclk,lrc,din;
 wire sample_valid,stereo_valid,link_up,ready,frame_valid;
 wire signed [15:0] sample,sample_right;
 wire [15:0] rms_left,rms_right,peak_left,peak_right;
 wire signed [11:0] rms_db10,peak_db10;
 wire signed [7:0] correlation,balance;
 integer frames=0;
 i2s_tx tx(.sys_clk(tx_clk),.rst_n(rst_n),.sample_data(source_sample),
  .bclk(bclk),.lrck(lrc),.sdata(din),.sample_tick(),.oversample_tick());
 i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(2000)) rx(.clk(clk),.rst_n(rst_n),
  .i2s_bclk(connected&&bclk),.i2s_lrc(connected&&lrc),.i2s_din(connected&&din),
  .sample(sample),.sample_right(sample_right),.sample_valid(sample_valid),
  .stereo_valid(stereo_valid),.link_up(link_up));
 audio_pcm_metrics metrics(.clk(clk),.rst_n(rst_n),.link_up(link_up),
  .pair_valid(stereo_valid),.left_sample(sample),.right_sample(sample_right),
  .ready(ready),.frame_valid(frame_valid),.rms_left(rms_left),.rms_right(rms_right),
  .peak_left(peak_left),.peak_right(peak_right),.rms_db10(rms_db10),.peak_db10(peak_db10),
  .correlation(correlation),.balance(balance));
 always #10 tx_clk=~tx_clk;
 initial begin #3;forever #10 clk=~clk;end
 always @(negedge clk)if(frame_valid)frames=frames+1;
 initial begin
  repeat(6)@(negedge clk);rst_n=1;
  wait(frame_valid);@(negedge clk);
  if(rms_left!=4096 || rms_right!=4096 || peak_left!=4096 || peak_right!=4096 ||
     rms_db10!=-181 || peak_db10!=-181 || correlation!=100 || balance!=0)
   $fatal(1,"Production serial RMS/dBFS chain incorrect");
  connected=0;repeat(2200)@(negedge clk);
  if(link_up || ready || rms_left || rms_right)$fatal(1,"Serial timeout failed to clear metrics");
  source_sample=-32768;connected=1;
  wait(frame_valid);@(negedge clk);
  // The resumed stream may start with an old TX register word; use the next
  // complete statistics window to require all samples from the new source.
  @(negedge clk);wait(frame_valid);@(negedge clk);
  if(rms_left!=32768 || rms_right!=32768 || rms_db10!=0 || peak_db10!=0)
   $fatal(1,"Fresh serial full-scale window incorrect");
  $display("PASS: production I2S transmitter -> async receiver -> stereo RMS/dBFS; serial timeout and fresh reconnect");$finish;
 end
 initial begin #50000000;$fatal(1,"I2S metrics chain watchdog");end
endmodule
