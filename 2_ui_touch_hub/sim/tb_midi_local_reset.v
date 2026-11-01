`timescale 1ns/1ps
// Exercise the production reset distributor, including a stopped pixel clock.
module tb_midi_local_reset;
 reg clk=0,run_clock=1,parent_n=0;
 wire tx_n,sync_n,preset_n,lfo_n;
 wire [3:0] all_n={tx_n,sync_n,preset_n,lfo_n};
 always #5 if(run_clock)clk=~clk;
 midi_reset_distribution dut(.clk(clk),.rst_n(parent_n),.tx_rst_n(tx_n),
  .sync_rst_n(sync_n),.preset_rst_n(preset_n),.lfo_rst_n(lfo_n));
 integer i,checks=0;
 initial begin
  #1;if(all_n!==0)$fatal(1,"FAIL: initial reset must assert all local copies");
  for(i=0;i<12;i=i+1)begin
   @(negedge clk);#2;parent_n=1;
   #1;if(all_n!==0)$fatal(1,"FAIL: asynchronous reset release leaked");
   @(posedge clk);#1;if(all_n!==15)$fatal(1,"FAIL: local reset copies do not release together on first edge");
   #2;parent_n=0;#1;if(all_n!==0)$fatal(1,"FAIL: off-edge reset assertion was not immediate");
   checks=checks+1;
  end
  @(negedge clk);run_clock=0;#2;parent_n=1;
  #23;if(all_n!==0)$fatal(1,"FAIL: local resets released with stopped clock");
  run_clock=1;@(posedge clk);#1;if(all_n!==15)$fatal(1,"FAIL: reset did not release when pixel clock resumed");
  @(negedge clk);run_clock=0;#2;parent_n=0;
  #1;if(all_n!==0)$fatal(1,"FAIL: stopped-clock reset assertion failed");
  $display("PASS: 12 reset/lock cycles, immediate asynchronous assertion, simultaneous one-edge release, stopped pixel clock and resume");$finish;
 end
 initial begin #10000;$fatal(1,"FAIL: reset watchdog");end
endmodule
