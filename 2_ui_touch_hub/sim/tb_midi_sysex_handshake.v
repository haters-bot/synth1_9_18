`timescale 1ns/1ps
`include "params.vh"
// Serial oracle for the raw-request SysEx arbiter, including FIFO saturation.
module tb_midi_sysex_handshake;
 reg clk=0,rst_n=0;
 always #10 clk=~clk;
 reg note_on_req=0,note_off_req=0,cc_req=0,sysex_req=0;
 reg [6:0] note_number=29,note_velocity=100,cc_val=99;
 reg [7:0] cc_param_id=8'hff;
 reg [47:0] sysex_msgs=48'hf07d4f027ff7;
 wire uart_tx,tx_busy,note_ready,sysex_accept,cc_accept;
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(6250000)) dut(.*);
 reg [7:0] expected[0:255],actual;
 integer queued=0,received=0,accepted=0,i;
 task word_expected(input [23:0] word_value);
  begin
   expected[queued]=word_value[23:16];expected[queued+1]=word_value[15:8];
   expected[queued+2]=word_value[7:0];queued=queued+3;
  end
 endtask
 task frame_expected;
  begin word_expected(sysex_msgs[47:24]);word_expected(sysex_msgs[23:0]);end
 endtask
 task drain;
  begin wait(received==queued && !tx_busy);repeat(20)@(negedge clk);end
 endtask
 initial forever begin
  @(negedge uart_tx);#80;
  for(integer k=0;k<8;k=k+1)begin #160;actual[k]=uart_tx;end
  #160;
  if(uart_tx!==1 || received>=queued || actual!==expected[received])
   $fatal(1,"UART byte %0d actual=%h expected=%h queued=%0d",received,actual,expected[received],queued);
  received=received+1;
 end
 always @(posedge clk)if(rst_n && sysex_accept)begin
  if(!sysex_req || note_on_req || note_off_req || cc_req || dut.fifo_count>6)
   $fatal(1,"accept without an exclusive two-word FIFO write");
  accepted=accepted+1;
  sysex_req<=0; // Same edge as the real producer's request retirement.
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  // Unsupported CC defers SysEx while requested, then emits exactly one frame.
  frame_expected;cc_req=1;sysex_req=1;
  repeat(4)begin @(negedge clk);if(accepted || tx_busy)$fatal(1,"unsupported CC handling");end
  cc_req=0;wait(accepted==1);drain;
  // Notes and supported CC win on successive cycles; the held SysEx survives.
  @(negedge clk);sysex_msgs=48'hf07d56027ff7;
  word_expected(24'h901d64);word_expected(24'hbf1863);frame_expected;
  note_on_req=1;sysex_req=1;
  @(negedge clk);note_on_req=0;cc_param_id=`PARAM_ID_ENV1_ATTACK;cc_req=1;
  @(negedge clk);cc_req=0;wait(accepted==2);drain;
  // Fill all eight FIFO entries behind a transmitting message.
  @(negedge clk);word_expected(24'h801d00);note_off_req=1;
  @(negedge clk);note_off_req=0;wait(dut.byte_active);
  @(negedge clk);
  for(i=0;i<8;i=i+1)begin
   if(!note_ready)$fatal(1,"unexpected FIFO fill boundary");
   note_number=30+i;word_expected({8'h90,1'b0,note_number,8'h64});note_on_req=1;
   @(negedge clk);
  end
  note_on_req=0;
  if(dut.fifo_count!=8)$fatal(1,"full FIFO not reached");
  sysex_msgs=48'hf07d7e0000f7;frame_expected;sysex_req=1;
  repeat(20)begin @(negedge clk);if(accepted!=2)$fatal(1,"SysEx accepted into full FIFO");end
  wait(accepted==3);drain;
  if(received!=queued || accepted!=3)$fatal(1,"missing or duplicate SysEx");
  $display("PASS: %0d actual UART bytes, unsupported CC deferral, Note/CC priority, two-slot FIFO backpressure, exact-once SysEx and Commit",received);
  $finish;
 end
 initial begin #1000000;$fatal(1,"UART handshake watchdog");end
endmodule
