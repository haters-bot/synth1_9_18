`timescale 1ns/1ps
module tb_audio_phase_plot;
 reg clk=0,rst_n=0,link_up=0,pair_valid=0;
 reg signed [15:0] left_sample=0,right_sample=0;
 reg [12:0] read_address=0;
 reg [1:0] gain_x=0,gain_y=0;
 wire pixel,ready;
 reg expected[0:8191];
 integer frame,n,index,x,y,a,value,hits,off_diagonal,raw_l,raw_r,scaled_l,scaled_r;
 real angle;
 audio_phase_plot dut(.*);
 always #10 clk=~clk;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;link_up=1;
  for(frame=0;frame<6;frame=frame+1)begin
   gain_x=frame==4 ? 1 : frame==5 ? 2 : 0;gain_y=frame==5 ? 1 : 0;
   repeat(2)@(negedge clk);
   while(dut.clearing)@(negedge clk);
   for(a=0;a<8192;a=a+1)expected[a]=0;
   for(n=0;n<2048;n=n+1)begin
    index=(n/8)%128;value=(index-64)*512;
    if(value==-32768)value=-32767;
    angle=6.283185307179586*index/128.0;
    raw_l=frame>=3 ? $rtoi(12000.0*$sin(angle)) : frame==2 ? 0 : value;
    raw_r=frame>=3 ? $rtoi(12000.0*$cos(angle)) : frame==2 ? 0 : frame==0 ? value : -value;
    left_sample=raw_l;right_sample=raw_r;
    if(n%8==7)begin
     scaled_l=raw_l*(1<<gain_x);scaled_r=raw_r*(1<<gain_y);
     if(scaled_l>32767)scaled_l=32767;if(scaled_l< -32768)scaled_l=-32768;
     if(scaled_r>32767)scaled_r=32767;if(scaled_r< -32768)scaled_r=-32768;
     x=64+(scaled_l>>>9);y=31-(scaled_r>>>10);
     expected[y*128+x]=1;
    end
    pair_valid=1;@(negedge clk);pair_valid=0;@(negedge clk);
   end
   if(!ready)$fatal(1,"Phase frame missing");
   hits=0;off_diagonal=0;
   for(a=0;a<8192;a=a+1)begin
    if(expected[a])begin hits=hits+1;if((a%128)<60 && (a/128)<28)off_diagonal=off_diagonal+1;end
    read_address=a;repeat(2)@(negedge clk);
    if(pixel!==expected[a])$fatal(1,"Phase point mismatch frame %0d address %0d",frame,a);
   end
   if(frame==3 && (hits<64 || off_diagonal<8))$fatal(1,"Orthogonal stereo failed to create ellipse");
  end
  link_up=0;repeat(3)@(negedge clk);
  if(ready)$fatal(1,"Disconnected phase remained valid");
  link_up=1;repeat(9000)@(negedge clk);
  if(ready)$fatal(1,"Phase reused old data after reconnect");
  $display("PASS: 49152 phase pixels, mono/opposite/silence, true sin/cos ellipse, independent X/Y gain, saturation, bank clearing and disconnect");
  $finish;
 end
 initial begin #20000000;$fatal(1,"Phase test watchdog");end
endmodule
