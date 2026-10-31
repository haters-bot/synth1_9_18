`timescale 1ns/1ps
module tb_audio_controls_pixels;
 reg clk=0,rst_n=0;reg [13:0] x=0,y=0;reg [2:0] page=0;reg [1:0] menu=0;
 reg [237:0] extras=0;reg [132:0] legacy=0;reg [105:0] sources=0;
 wire hit;wire [23:0] rgb;
 always #10 clk=~clk;
 `include "audio_extra_controls.vh"
 audio_controls_renderer dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.extra_values(extras),.legacy_values(legacy),
  .fx_page(page),.warp_menu(menu),.wave_a(3'd4),.wave_b(3'd1),.sources(sources),.out_hit(hit),.out_rgb(rgb));
 integer i,p,fh,t,n,px,py,checks=0;
 task point(input integer a,b,input bit expected);begin
  @(negedge clk);x=a;y=b;repeat(6)@(negedge clk);
  if(hit!==expected || (hit && ^rgb===1'bx))$fatal(1,"render hit/unknown at%0d,%0d",a,b);
  checks=checks+1;
 end endtask
 task image(input integer left,top,width,height,input [255:0] filename);begin
  fh=$fopen(filename,"w");$fdisplay(fh,"P3\n%0d %0d\n255",width,height);n=width*height;
  for(t=0;t<n+4;t=t+1)begin
   @(negedge clk);x=t<n ? left+t%width : 0;y=t<n ? top+t/width : 0;
   @(posedge clk);#1;
   if(t>=4)begin
    if(!hit || ^rgb===1'bx)$fatal(1,"pipeline alignment pixel%0d",t-4);
    $fdisplay(fh,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
   end
  end
  $fclose(fh);
 end endtask
 initial begin
  for(i=0;i<34;i=i+1)extras[i*7+:7]=audio_extra_default(i);
  extras[35+:7]=127;extras[70+:7]=127;extras[112+:7]=127;extras[154+:7]=127;extras[28+:7]=3;
  for(i=0;i<19;i=i+1)legacy[i*7+:7]=64;
  sources[70+:2]=1;
  repeat(5)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
  point(419,450,0);point(420,368,1);point(780,707,1);point(781,500,0);point(500,708,0);
  if(dut.cell_values[0]!==32 || dut.cell_values[1]!==127)$fatal(1,"initial control values frozen");
  page=5;point(450,462,1);
  if(dut.cell_values[0]!==52 || dut.cell_values[1]!==80 || dut.cell_values[2]!==0)$fatal(1,"pitch controls not displayed on sixth tab");
  page=0;repeat(6)@(negedge clk);
  extras[49+:7]=0;point(450,481,1);
  if(dut.cell_values[0]!==0 || rgb!==24'h111822)$fatal(1,"same-page edit did not refresh numeric/bar state");
  extras[49+:7]=32;point(450,481,1);if(rgb!==24'h38C4CC)$fatal(1,"same-page bar did not refresh");
  page=3;point(450,481,1);if(rgb!==24'hC98BFF)$fatal(1,"LFO source colour");
  sources[70+:2]=2;point(450,481,1);if(rgb!==24'hF7BB62)$fatal(1,"same-page source edit did not refresh");
  for(p=0;p<6;p=p+1)begin
   page=p;repeat(10)@(negedge clk);
   case(p)
    0:image(420,368,361,340,"fx_dist.ppm");1:image(420,368,361,340,"fx_phaser.ppm");
    2:image(420,368,361,340,"fx_chorus.ppm");3:image(420,368,361,340,"fx_delay_reverb.ppm");
    4:image(420,368,361,340,"fx_comp.ppm");5:image(420,368,361,340,"fx_pitch.ppm");
   endcase
  end
  menu=1;image(40,108,372,128,"warp_menu.ppm");menu=0;image(40,108,372,128,"sd_bank.ppm");
  $display("PASS: five FX plus sixth PITCH page, 12-mode WARP menu and honest SD placeholder, %0d pipeline-aligned RGB pixels, edge/dynamic value/route checks=%0d",6*361*340+2*372*128,checks);$finish;
 end
 initial begin #30000000;$fatal(1,"pixel watchdog");end
endmodule
