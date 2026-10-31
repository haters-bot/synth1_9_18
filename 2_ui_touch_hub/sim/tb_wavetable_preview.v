`timescale 1ns/1ps
module tb_wavetable_preview;
 reg clk=0,rst_n=0,enable_a=1,enable_b=1;
 reg [6:0] bank_a=0,bank_b=9,position_a=0,position_b=127,phase_a=0,phase_b=0;
 wire signed [6:0] offset_a,offset_b;
 always #10 clk=~clk;
 ui_wavetable_preview dut(.*);
 reg [6:0] expected[0:163839];
 integer bank,pos,phase,cycles,checks=0;
 reg old_active;
 task settle;
 begin
  cycles=0;
  while(!(dut.valid_a && dut.valid_b && dut.cached_bank_a==(bank_a>9 ? 9 : bank_a) &&
    dut.cached_bank_b==(bank_b>9 ? 9 : bank_b) && dut.cached_position_a==position_a && dut.cached_position_b==position_b))begin
   @(negedge clk);cycles=cycles+1;if(cycles>3200)$fatal(1,"preview refresh/starvation watchdog");
  end
 end
 endtask
 task check_sample;
 begin
  @(posedge clk);#1;
  if(offset_a!==expected[(bank_a>9 ? 9 : bank_a)*16384+position_a*128+phase_a])
   $fatal(1,"A bank=%0d pos=%0d phase=%0d actual=%0d expected=%0d",bank_a,position_a,phase_a,offset_a,$signed(expected[(bank_a>9 ? 9 : bank_a)*16384+position_a*128+phase_a]));
  if(offset_b!==expected[(bank_b>9 ? 9 : bank_b)*16384+position_b*128+phase_b])
   $fatal(1,"B bank=%0d pos=%0d phase=%0d",bank_b,position_b,phase_b);
  checks=checks+2;
 end
 endtask
 initial begin
  $readmemh("preview_expected.hex",expected);
  repeat(5)@(negedge clk);rst_n=1;
  for(bank=0;bank<10;bank=bank+1)for(pos=0;pos<128;pos=pos+1)begin
   @(negedge clk);bank_a=bank;bank_b=9-bank;position_a=pos;position_b=127-pos;
   settle;
   for(phase=0;phase<128;phase=phase+1)begin
    @(negedge clk);phase_a=phase;phase_b=127-phase;check_sample;
   end
  end
  // Mid-build edits must not publish a partially updated cache; the final
  // request must eventually be rendered on both oscillators.
  @(negedge clk);position_a=20;position_b=100;old_active=dut.active_a;
  repeat(15)@(negedge clk);
  if(dut.active_a!==old_active)$fatal(1,"partial preview cache published");
  bank_a=3;position_a=42;bank_b=5;position_b=73;settle;
  for(phase=0;phase<128;phase=phase+1)begin
   @(negedge clk);phase_a=phase;phase_b=phase;check_sample;
  end
  @(negedge clk);bank_a=127;bank_b=127;settle;check_sample;
  @(negedge clk);enable_a=0;enable_b=0;repeat(1000)@(negedge clk);
  if(dut.state!==0)$fatal(1,"disabled preview keeps rebuilding");
  rst_n=0;repeat(5)@(negedge clk);
  if(offset_a!==0 || offset_b!==0)$fatal(1,"reset exposes uninitialized preview");
  rst_n=1;enable_a=1;enable_b=1;settle;check_sample;
  $display("PASS: %0d independent WTB-derived preview samples, 10 banks x 128 WT positions x 128 phase samples on both OSCs; signed interpolation, endpoints, clamp, cache atomicity, mid-build edits, fairness and reset",checks);
  $finish;
 end
 initial begin #100000000;$fatal(1,"preview global watchdog");end
endmodule
