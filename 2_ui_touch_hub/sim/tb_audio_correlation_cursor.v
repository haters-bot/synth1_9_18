`timescale 1ns/1ps
module tb_audio_correlation_cursor;
 reg clk=0,rst_n=0,link_up=0,value_valid=0;
 reg signed [7:0] correlation=0;
 wire [13:0] position;
 wire position_valid;
 reg [2:0] expected_valid=0;
 integer expected[0:2];
 integer held=1058,n,bounded,checks=0;
 audio_correlation_cursor dut(.*);
 always #10 clk=~clk;
 always @(posedge clk)begin
  if(!rst_n || !link_up)begin expected_valid=0;held=1058;end
  else begin
   expected_valid={expected_valid[1:0],value_valid};
   expected[2]=expected[1];expected[1]=expected[0];
   bounded=$signed(correlation);
   if(bounded>100)bounded=100;
   if(bounded< -100)bounded= -100;
   expected[0]=1058+(126*bounded)/100;
   if(expected_valid[2])begin held=expected[2];checks=checks+1;end
  end
  #1;
  if(position_valid!==expected_valid[2] || position!==held)
   $fatal(1,"Cursor got %0d/%b expected %0d/%b",position,position_valid,held,expected_valid[2]);
 end
 initial begin
  repeat(3)@(negedge clk);rst_n=1;link_up=1;
  // Back-to-back values exercise every signed input and endpoint saturation.
  for(n=-128;n<128;n=n+1)begin correlation=n;value_valid=1;@(negedge clk);end
  value_valid=0;repeat(5)@(negedge clk);
  // Valid bubbles must retain the last coordinate, including negative rounding.
  for(n=-128;n<128;n=n+1)begin
   correlation=n;value_valid=1;@(negedge clk);value_valid=0;repeat(n&3)@(negedge clk);
  end
  value_valid=0;repeat(5)@(negedge clk);
  correlation=100;value_valid=1;@(negedge clk);link_up=0;
  repeat(3)@(negedge clk);link_up=1;value_valid=0;repeat(5)@(negedge clk);
  correlation=-100;value_valid=1;@(negedge clk);rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;value_valid=0;repeat(5)@(negedge clk);
  if(checks!=512)$fatal(1,"Incomplete cursor sweep %0d",checks);
  $display("PASS: 512 correlation coordinates, signed rounding, saturation, valid bubbles and reset/disconnect pipeline flush");
  $finish;
 end
 initial begin #100000;$fatal(1,"Cursor watchdog");end
endmodule
