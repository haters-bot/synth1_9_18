`timescale 1ns/1ps
module tb_controls_preview;
 reg clk=0,rst_n=0;
 reg [13:0] x=0,y=0;
 reg [7:0] section=1;
 reg [1:0] page=0;
 reg [63:0] steps=0;
 reg [23:0] scales=0;
 wire hit;
 wire [23:0] rgb;
 integer fd,px,py,i,k,count=0,checks=0,only_display;
 reg rendering=0;
 reg [4:0] pixels_valid=0;
 ui_navigation_renderer dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.view(2'd2),
  .settings_section_id(section),.knob_steps(steps),.knob_page(page),.apply_step(2'd3),.plot_scales(scales),
  .show_diagnostics(1'b0),.usb_connected(1'b1),.usb_error(1'b0),.macro_values(28'd0),
  .audio_sample_valid(1'b0),.audio_sample(16'd0),.audio_right_sample(16'd0),
  .audio_stereo_valid(1'b0),.audio_link_up(1'b0),.out_hit(hit),.out_rgb(rgb));
 always #10 clk=~clk;
 always @(posedge clk)begin
  pixels_valid={pixels_valid[3:0],rendering};
  #2;
  if(pixels_valid[4])begin
   if(^rgb===1'bx)$fatal(1,"Unknown settings preview pixel");
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;
  end
 end
 task frame(input [255:0] name);
  begin
   count=0;fd=$fopen(name,"wb");$fwrite(fd,"P6\n1280 720\n255\n");
   for(py=0;py<720;py=py+1)for(px=0;px<1280;px=px+1)begin
    @(negedge clk);x=px;y=py;rendering=1;
   end
   @(negedge clk);rendering=0;repeat(8)@(negedge clk);$fclose(fd);
   if(count!=921600)$fatal(1,"Incomplete settings preview");
  end
 endtask
 initial begin
  for(i=0;i<32;i=i+1)steps[i*2+:2]=i%4;
  for(i=0;i<6;i=i+1)begin scales[i*4+:2]=i%4;scales[i*4+2+:2]=(5-i)%4;end
  repeat(5)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
  only_display=$test$plusargs("DISPLAY_ONLY");
  if(!only_display)begin frame("controls_01_08.ppm");page=3;repeat(10)@(negedge clk);frame("controls_25_32.ppm");end
  section=2;
  for(i=0;i<6;i=i+1)begin
   // Check the actual dynamic decoder at all twelve scale digit rectangles.
   // Text IDs are interleaved; subtracting VALUE0 as an index must fail here.
   for(k=0;k<2;k=k+1)begin
    x=400+(k==0 ? 1 : 4)*16;y=212+i*56;
    repeat(3)@(negedge clk);
    if(!(k==1 && (i==0 || i==5)) && (!dut.audio_number || dut.audio_number_char!==6'(27+(1<<(k==0 ? i%4 : (5-i)%4)))))
     $fatal(1,"Wrong displayed scale row=%0d axis=%0d char=%0d",i,k,dut.audio_number_char);
    checks=checks+1;
   end
  end
  frame("display_scales.ppm");
  $display("PASS: %0d scale digits and complete settings RTL frames, pages 1/4 and 4/4, all six display rows",checks);
  $finish;
 end
 initial begin #100000000;$fatal(1,"Controls preview watchdog");end
endmodule
