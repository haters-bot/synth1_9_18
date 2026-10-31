`timescale 1ns/1ps
`include "params.vh"
`include "font_3x5.vh"
module tb_lfo_rate_labels;
 lfo_panel_renderer panel(.clk(1'b0),.rst_n(1'b0),.in_x(14'd0),.in_y(14'd0),
  .active_tab(2'd0),.preset(2'd0),.nodes(49'd0),.rate(3'd0),
  .once_mode(1'b0),.stepped(1'b0),.phase(9'd0),.running(1'b0),.curve_q6(13'd0));
 reg [63:0] labels[0:7];reg [7:0] a;reg [5:0] expected;
 integer r,c;
 initial begin
  labels[0]="0.25 HZ ";labels[1]="0.5 HZ  ";labels[2]="1 HZ    ";labels[3]="2 HZ    ";
  labels[4]="4 HZ    ";labels[5]="8 HZ    ";labels[6]="16 HZ   ";labels[7]="32 HZ   ";
  #1;
  for(r=0;r<8;r=r+1)for(c=0;c<8;c=c+1)begin
   a=labels[r][63-c*8-:8];expected=0;
   if(a>=48 && a<=57)expected=`CH_0+a-48;
   else if(a==46)expected=`CH_DOT;
   else if(a==72)expected=`CH_H;
   else if(a==90)expected=`CH_Z;
   if(panel.label_char_at(11,c[4:0],r[2:0],0,0)!==expected)
    $fatal(1,"label index%0d column%0d",r,c);
  end
  $display("PASS: all eight UI rate labels, including 16/32 Hz");$finish;
 end
endmodule
