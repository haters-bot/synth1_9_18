`timescale 1ns/1ps
module tb_audio_waveform_capture;
 reg clk=0,rst_n=0,link_up=0,sample_valid=0;
 reg signed [15:0] sample=0;
 reg [6:0] read_address=0;
 wire [7:0] plot_sample,plot_previous;
 wire ready,frame_valid,triggered;
 integer n,saved_bank;
 audio_waveform_capture dut(.*);
 always #10 clk=~clk;
 task send;
  input signed [15:0] value;input integer count;integer i;
  begin for(i=0;i<count;i=i+1)begin
   sample=value;sample_valid=1;@(negedge clk);sample_valid=0;@(negedge clk);
  end end
 endtask
 task check_read;
  input integer address;input [7:0] value,prev;
  begin
   read_address=address;repeat(2)@(negedge clk);
   if(plot_sample!==value || plot_previous!==prev)
    $fatal(1,"Wave RAM read addr=%0d got %h/%h expected %h/%h",address,plot_sample,plot_previous,value,prev);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;link_up=1;
  send(0,1023);if(ready)$fatal(1,"Incomplete first capture ready");
  send(0,1);if(!ready || triggered)$fatal(1,"Initial auto capture missing");
  saved_bank=dut.display_bank;
  send(4096,1024);if(dut.display_bank!=saved_bank)$fatal(1,"Partial capture published");
  check_read(0,0,0);check_read(127,0,0);
  send(4096,1016);if(dut.display_bank==saved_bank || triggered)$fatal(1,"DC auto trigger failed");
  for(n=0;n<128;n=n+1)check_read(n,8'h10,8'h10);
  saved_bank=dut.display_bank;
  send(-4096,8);if(!dut.armed || dut.capturing)$fatal(1,"Negative threshold did not arm");
  send(8192,8);if(!dut.capturing || dut.write_index!=1)$fatal(1,"Rising crossing did not trigger");
  for(n=1;n<128;n=n+1)begin
   send(n*256,8);
   if(n<127 && dut.display_bank!=saved_bank)$fatal(1,"Active waveform bank was overwritten");
  end
  if(!triggered || dut.display_bank==saved_bank)$fatal(1,"Triggered frame not published");
  check_read(0,8'h20,8'h20);
  for(n=1;n<128;n=n+1)check_read(n,n,n==1 ? 8'h20 : n-1);
  link_up=0;repeat(4)@(negedge clk);
  if(ready || frame_valid || triggered)$fatal(1,"Disconnected waveform valid");
  link_up=1;send(0,1023);if(ready)$fatal(1,"Stale frame on reconnect");
  send(0,1);for(n=0;n<128;n=n+1)check_read(n,0,0);
  $display("PASS: trigger hysteresis, immutable double buffering, 128 synchronous samples/segments, DC auto trigger and reconnect");$finish;
 end
 initial begin #2000000;$fatal(1,"Waveform capture watchdog");end
endmodule
