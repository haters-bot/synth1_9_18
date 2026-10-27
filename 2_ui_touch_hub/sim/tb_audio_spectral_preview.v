`timescale 1ns/1ps
// Accelerated, explicitly synthetic PCM stimulus. This is neither a camera
// frame nor evidence of physical audio-board behavior.
module tb_audio_spectral_preview;
 reg clk=0,rst_n=0,valid=0;
 reg signed [15:0] sample=0,right_sample=0;
 reg [13:0] x=0,y=0;
 wire hit;wire [23:0] rgb;
 integer n,frame,px,py,fd,count=0,k,j,checks=0,tone;
 reg rendering=0,checking=0;reg [4:0] pixels_valid=0;
 reg [23:0] expected,expected_history[0:4];
 ui_navigation_renderer dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.view(2'd1),
  .settings_section_id(8'd1),.show_diagnostics(1'b0),.usb_connected(1'b1),.usb_error(1'b0),
  .knob_steps(64'd0),.knob_page(2'd0),.apply_step(2'd0),.plot_scales(24'd0),.macro_values(28'd0),.audio_sample_valid(valid),.audio_sample(sample),.audio_link_up(1'b1),
  .audio_right_sample(right_sample),.audio_stereo_valid(valid),.out_hit(hit),.out_rgb(rgb));
 // Fill history quickly for an inspectable synthetic preview, while leaving
 // production HISTORY_HOP=8 unchanged in the actual build.
 defparam dut.u_spectrum.HISTORY_HOP=1;
 always #10 clk=~clk;
 always @(posedge clk)begin
  pixels_valid={pixels_valid[3:0],rendering};
  if(checking)begin
   for(j=4;j>0;j=j-1)expected_history[j]=expected_history[j-1];
   expected_history[0]=expected;checks=checks+1;
  end
  #2;
  if(checking && checks>5 && rgb!==expected_history[4])
   $fatal(1,"New PCM plot pixel pipeline shifted at check %0d expected %h got %h",checks,expected_history[4],rgb);
  if(pixels_valid[4])begin
   if(^rgb===1'bx)$fatal(1,"Unknown spectral preview pixel");
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;
  end
 end
 function [23:0] reference;
  input integer sx,sy;
  integer tile,tx,ty,col,row,level,addr;reg active;reg [23:0] color;
  begin
   tile=sx<420 ? (sy<376 ? 0 : 3) : sx>=860 ? 2 : 4;
   tx=24+(tile%3)*418;ty=96+(tile/3)*296;
   color=(sx==tx+198 || sy==ty+140) ? 24'h26394B :
          (sx%64==0 || sy%64==0) ? 24'h152331 : 24'h0B131D;
   if(tile==0)begin
    addr=(sx-140)*(sx-140)+(sy-248)*(sy-248);
    level=8+((dut.metrics_rms_l>dut.metrics_rms_r ? dut.metrics_rms_l : dut.metrics_rms_r)>>10);
    if(addr>=2809&&addr<=3600)
     color=dut.metrics_clip!=0 ? 24'hE87565 : dut.metrics_transient!=0 ? 24'hF5D36A : 24'h368DAC;
    if((dut.metrics_rms_l>=8||dut.metrics_rms_r>=8)&&addr<=level*level)color=24'h61DED1;
   end else if(tile==2)begin
    addr=((sy-184)/2)*128+(sx-930)/2;
    if(dut.u_phase.memory[dut.u_phase.display_bank*8192+addr])color=24'h67CDE0;
   end else if(tile==3)begin
    col=(sx-94)/8;level=dut.u_spectrum.spectrum_memory[dut.u_spectrum.spectrum_bank*32+col];
    if((sx-94)%8<6 && level!=0 && sy>616-2*level &&
       col==dut.u_spectrum.peak_band)color=24'hF5D36A;
    else if((sx-94)%8<6 && level!=0 && sy>616-2*level)color=24'h65CDA4;
   end else begin
    col=(sx-512)/4;row=31-(sy-480)/4;
    addr=((dut.u_spectrum.history_write+col)%64)*32+row;
    level=dut.u_spectrum.history_memory[addr];
    if(level!=0)begin
     case(level/8)
      0:color=24'h17344D;1:color=24'h245C83;2:color=24'h368DAC;3:color=24'h4ABCB9;
      4:color=24'h70D6A2;5:color=24'hD6CF79;6:color=24'hE7A466;7:color=24'hEF7060;
     endcase
    end
   end
   reference=color;
  end
 endfunction
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(frame=0;frame<64;frame=frame+1)begin
   tone=frame<56 ? 4+frame*2 : 11;
   for(n=0;n<1024;n=n+1)begin
    while(dut.u_spectrum.state!=0)@(negedge clk);
    valid=1;sample=$rtoi(21000.0*$sin(6.28318530718*tone*n/1024.0)+
                         4500.0*$sin(6.28318530718*3*tone*n/1024.0));
    right_sample=$rtoi(10500.0*$cos(6.28318530718*tone*n/1024.0));
    @(negedge clk);valid=0;repeat(6)@(negedge clk);
   end
   while(!dut.u_spectrum.frame_valid)@(negedge clk);
   @(negedge clk);
  end
  if(!dut.phase_ready || !dut.spectrum_ready || dut.u_spectrum.history_count!=64)
   $fatal(1,"Preview did not fill real PCM data structures");
  checking=1;
  for(k=0;k<4096;k=k+1)begin
   case(k%4)
    0:begin x=930+(k*37)%256;y=184+(k*13)%128;end
    1:begin x=94+(k*29)%256;y=480+(k*17)%137;end
    2:begin x=512+(k*19)%256;y=480+(k*23)%128;end
    3:begin x=64+(k*11)%152;y=184+(k*7)%128;end
   endcase
   expected=reference(x,y);@(negedge clk);
  end
  checking=0;
  $display("PASS: 4096 per-clock energy/phase/spectrum/history raster alignment checks");
  x=94+dut.spectrum_peak_band*8+2;
  y=80;repeat(7)@(negedge clk);if(rgb!==24'h101318)$fatal(1,"Peak marker leaked above tiles");
  y=384;repeat(7)@(negedge clk);if(rgb!==24'h101318)$fatal(1,"Peak marker leaked across tile gap");
  y=680;repeat(7)@(negedge clk);if(rgb!==24'h101318)$fatal(1,"Peak marker leaked below tiles");
  fd=$fopen("frame.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");
  for(py=0;py<720;py=py+1)for(px=0;px<1280;px=px+1)begin
   @(negedge clk);x=px;y=py;rendering=1;
  end
  @(negedge clk);rendering=0;repeat(8)@(negedge clk);$fclose(fd);
  if(count!=921600)$fatal(1,"Wrong preview pixel count %0d",count);
  $display("PASS: 921600 real RTL pixels, synthetic stereo PCM sweep/history preview (not hardware evidence)");
  $finish;
 end
 initial begin #200000000;$fatal(1,"Spectral preview watchdog");end
endmodule
