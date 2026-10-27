`timescale 1ns/1ps
module tb_audio_phase_plot;
 reg clk=0,rst_n=0,link_up=0,pair_valid=0;
 reg signed [15:0] left_sample=0,right_sample=0;
 reg [12:0] read_address=0;
 wire pixel,ready;
 reg expected[0:8191];
 integer frame,n,index,x,y,a,value;
 audio_phase_plot dut(.*);
 always #10 clk=~clk;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;link_up=1;
  for(frame=0;frame<3;frame=frame+1)begin
   while(dut.clearing)@(negedge clk);
   for(a=0;a<8192;a=a+1)expected[a]=0;
   for(n=0;n<2048;n=n+1)begin
    index=(n/8)%128;value=(index-64)*512;
    if(value==-32768)value=-32767;
    left_sample=frame==2 ? 0 : value;
    right_sample=frame==2 ? 0 : frame==0 ? value : -value;
    if(n%8==7)begin
     x=64+($signed(left_sample)>>>9);y=31-($signed(right_sample)>>>10);
     expected[y*128+x]=1;
    end
    pair_valid=1;@(negedge clk);pair_valid=0;@(negedge clk);
   end
   if(!ready)$fatal(1,"Phase frame missing");
   for(a=0;a<8192;a=a+1)begin
    read_address=a;repeat(2)@(negedge clk);
    if(pixel!==expected[a])$fatal(1,"Phase point mismatch frame %0d address %0d",frame,a);
   end
  end
  link_up=0;repeat(3)@(negedge clk);
  if(ready)$fatal(1,"Disconnected phase remained valid");
  link_up=1;repeat(9000)@(negedge clk);
  if(ready)$fatal(1,"Phase reused old data after reconnect");
  $display("PASS: 24576 phase pixels, mono diagonal, opposite phase, silence, bank clearing and disconnect");
  $finish;
 end
 initial begin #20000000;$fatal(1,"Phase test watchdog");end
endmodule
