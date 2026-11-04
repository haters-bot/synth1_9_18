`timescale 1ns/1ps
module tb_ws2812_serial;
reg clk=0,rst_n=0,we=0,latch=0;
reg [4:0] index=0;
reg [23:0] rgb=0;
wire data,busy,done;
always #10 clk=~clk;
ws2812_driver #(.LED_COUNT(24)) dut(.clk(clk),.rst_n(rst_n),.frame_we(we),.frame_index(index),
 .frame_rgb(rgb),.latch(latch),.data(data),.busy(busy),.frame_done(done));
integer n,b,highs,low_cycles,frames=0,bits=0;
reg [23:0] expected;
task step;begin @(posedge clk);#1;end endtask
task write_pixel;input integer address;input [23:0] color;begin
 @(negedge clk);we=1;index=address;rgb=color;step;
 @(negedge clk);we=0;
end endtask
task receive_frame;input integer black;begin
 for(n=0;n<24;n=n+1)begin
  // Independent RGB -> physical G,R,B wire bytes.
  expected=(black) ? 24'd0 : {8'(n^8'hA5),8'(n+1),8'(255-n)};
  for(b=23;b>=0;b=b-1)begin
   wait(data===1'b1);highs=0;
   while(data===1'b1)begin highs=highs+1;step;end
   if(highs!==(expected[b] ? 40 : 20))
    $fatal(1,"pixel %0d bit %0d high=%0d expected=%0d",n,b,highs,expected[b] ? 40 : 20);
   bits=bits+1;
   // During transmission writes must not mutate the buffered frame.
   if(n==0 && b==20)begin we=1;index=23;rgb=0;end
   if(n==0 && b==19)we=0;
  end
 end
 low_cycles=0;
 while(!done)begin
  if(data!==0)$fatal(1,"unexpected data during reset interval");
  low_cycles=low_cycles+1;step;
 end
 if(low_cycles<15000)$fatal(1,"reset low shorter than 300us: %0d",low_cycles);
 if(busy!==0)$fatal(1,"done while busy");
 step;if(done)$fatal(1,"done not a pulse");
 frames=frames+1;
end endtask
initial begin
 repeat(3)step;@(negedge clk);rst_n=1;
 low_cycles=0;
 while(busy)begin
  if(data!==0)$fatal(1,"startup line must remain low");
  low_cycles=low_cycles+1;step;
 end
 if(low_cycles<15000)$fatal(1,"startup reset too short");
 for(n=0;n<24;n=n+1)write_pixel(n,{8'(n+1),8'(n^8'hA5),8'(255-n)});
 @(negedge clk);latch=1;step;@(negedge clk);latch=0;
 receive_frame(0);
 for(n=0;n<24;n=n+1)write_pixel(n,0);
 @(negedge clk);latch=1;step;@(negedge clk);latch=0;
 receive_frame(1);
 if(frames!=2 || bits!=1152)$fatal(1,"coverage");
 $display("PASS: 24-pixel direct GRB chain decode, 1152 exact high pulses, 300us startup/latch, busy-write isolation and all-dark frame");
 $finish;
end
initial begin #3000000;$fatal(1,"serial timeout");end
endmodule
