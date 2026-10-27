`timescale 1ns/1ps
module tb_audio_dbfs_encoder;
 reg clk=0,drive_valid=0;
 reg [15:0] amplitude=0;
 wire signed [11:0] db10;
 reg [2:0] valid=0;
 reg [15:0] history[0:2];
 integer n,j,fd,checked=0;
 audio_dbfs_encoder dut(.*);
 always #10 clk=~clk;
 always @(posedge clk)begin
  for(j=2;j>0;j=j-1)history[j]=history[j-1];history[0]=amplitude;
  valid={valid[1:0],drive_valid};
  #2;if(valid[2])begin
   if(^db10===1'bx)$fatal(1,"Unknown dBFS output after pipeline fill");
   $fdisplay(fd,"%0d %0d",history[2],db10);checked=checked+1;
  end
 end
 initial begin
  fd=$fopen("dbfs_all_amplitudes.txt","w");
  for(n=0;n<=32768;n=n+1)begin @(negedge clk);drive_valid=1;amplitude=n;end
  @(negedge clk);drive_valid=0;repeat(5)@(negedge clk);
  $fclose(fd);if(checked!=32769)$fatal(1,"Incomplete encoder sweep %0d",checked);
  $display("PASS: all 32769 physical PCM amplitudes through three-stage dBFS encoder");$finish;
 end
 initial begin #1000000;$fatal(1,"dBFS encoder watchdog");end
endmodule
