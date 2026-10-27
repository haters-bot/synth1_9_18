`timescale 1ns/1ps
// Use the production audio transmitter, independently clocked UI receiver,
// exact sample scoreboard, reset during traffic and stop/restart recovery.
module tb_i2s_visual_loopback;
 reg tx_clk=0,clk=0,rst_n=0,tx_rst_n=0,connected=1;
 reg signed [15:0] input_sample=16'hA55A;
 wire bclk,lrc,din,tx_tick,oversample_tick;
 wire signed [15:0] sample;
 wire sample_valid,link_up;
 wire signed [15:0] sample_right;
 wire stereo_valid;
 integer pairs=0;
 reg [15:0] expected[0:511];
 integer writes=0,reads=0,checked=0,errors=0,phase_checks;
 i2s_tx tx(.sys_clk(tx_clk),.rst_n(tx_rst_n),.sample_data(input_sample),
  .bclk(bclk),.lrck(lrc),.sdata(din),.sample_tick(tx_tick),
  .oversample_tick(oversample_tick));
 i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(2000)) rx(
  .clk(clk),.rst_n(rst_n),.i2s_bclk(connected&&bclk),
  .i2s_lrc(connected&&lrc),.i2s_din(connected&&din),
  .sample(sample),.sample_valid(sample_valid),.link_up(link_up),
  .sample_right(sample_right),.stereo_valid(stereo_valid));
 always #10 tx_clk=~tx_clk;
 // Same nominal frequency, unrelated phase as on the two real boards.
 initial begin #3;forever #10 clk=~clk;end
 always @(posedge tx_clk) begin
  #1;
  if(tx_tick && connected && rst_n) begin
   expected[writes]=input_sample;writes=writes+1;
  end
 end
 always @(negedge tx_clk) if(tx_tick) begin
  case(writes%8)
   0:input_sample=16'h0000;1:input_sample=16'h0001;
   2:input_sample=16'h7FFF;3:input_sample=16'h8000;
   4:input_sample=16'hFFFF;5:input_sample=16'hA55A;
   6:input_sample=16'h5AA5;7:input_sample=16'h1234;
  endcase
 end
 always @(posedge clk) begin
  #2;
  if(stereo_valid)begin
   if(sample_right!==sample)$fatal(1,"Production mono L/R pair mismatch");
   pairs=pairs+1;
  end
  if(sample_valid) begin
   // At startup/reconnect the receiver discards a partial channel. Match
   // the next complete frame, then require exact order with no skips.
   if(reads==0) begin
    while(reads<writes && expected[reads]!==sample) reads=reads+1;
   end
   if(reads>=writes || sample!==expected[reads]) begin
    $display("ERROR sample=%h expected[%0d]=%h writes=%0d",sample,reads,expected[reads],writes);
    errors=errors+1;
   end
   reads=reads+1;checked=checked+1;
  end
 end
 task clear_queue;
  begin writes=0;reads=0;end
 endtask
 initial begin
  repeat(6)@(negedge tx_clk);tx_rst_n=1;rst_n=1;
  #900000;
  if(checked<70) $fatal(1,"Too few decoded production samples: %0d",checked);
  phase_checks=checked;
  @(negedge tx_clk);rst_n=0;clear_queue();
  #139;rst_n=1;
  #300000;
  if(checked-phase_checks<20) $fatal(1,"No recovery after mid-word reset");
  @(negedge tx_clk);connected=0;
  #45000;
  if(link_up) $fatal(1,"Link did not time out");
  if(sample_valid) $fatal(1,"Sample while link stopped");
  // Restore between frames; the first partial word must be discarded.
  @(negedge tx_clk);clear_queue();phase_checks=checked;connected=1;
  #300000;
  if(checked-phase_checks<20) $fatal(1,"No recovery after link restart");
  if(!link_up) $fatal(1,"Link did not recover");
  if(errors) $fatal(1,"Production I2S loopback failed: %0d errors",errors);
  if(pairs<120)$fatal(1,"Too few complete production stereo pairs");
  $display("PASS: production 96 kHz / 3.072 MHz I2S loopback, %0d exact samples, reset and timeout recovery",checked);
  $finish;
 end
 initial begin #2000000;$fatal(1,"I2S loopback watchdog");end
endmodule
