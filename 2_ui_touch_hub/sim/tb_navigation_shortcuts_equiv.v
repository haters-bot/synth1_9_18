`timescale 1ns/1ps
`include "params.vh"
`include "font_3x5.vh"
// Reference frozen from 2a73052; test the exact production include in isolation.
module shortcut_reference(input wire [13:0] in_x,in_y,input wire [2:0] view,
 input wire [23:0] plot_scales,output wire [15:0] result);
 reg shortcut;
 reg [5:0] shortcut_char;
 reg [3:0] shortcut_x;reg [4:0] shortcut_y;
 integer st,sc,cc;reg [1:0] code;
 always @*begin
  shortcut=0;shortcut_char=0;shortcut_x=0;shortcut_y=0;code=0;cc=0;
  for(st=0;st<6;st=st+1)for(sc=0;sc<4;sc=sc+1)begin
   if(view==1 && !((st==0||st==5)&&sc>=2) &&
      in_y>=96+(st/3)*296+260 && in_y<96+(st/3)*296+276 &&
      in_x>=24+(st%3)*418+24+sc*92 && in_x<24+(st%3)*418+88+sc*92)begin
    shortcut=1;shortcut_x=(in_x-(24+(st%3)*418+24+sc*92))%8;
    shortcut_y=in_y-(96+(st/3)*296+260);
    code=plot_scales[st*4+(sc>=2 ? 2 : 0)+:2];cc=(in_x-(24+(st%3)*418+24+sc*92))/8;
    case(cc)
     0:shortcut_char=sc<2 ? `CH_Y : `CH_X;
     1:shortcut_char=(sc==0||sc==2) ? `CH_MINUS : `CH_PLUS;
     3:shortcut_char=`CH_0+(4'd1<<code);
     4:shortcut_char=`CH_X;
     default:shortcut_char=`CH_SPACE;
    endcase
   end
  end
  if(view==2 && in_y>=142 && in_y<162)begin
   for(st=0;st<3;st=st+1)begin
    if(in_x>=328+st*176 && in_x<440+st*176)begin
     shortcut=1;shortcut_char=mode_caption(st,(in_x-(328+st*176))/14);
     shortcut_x=((in_x-(328+st*176))%14)>>1;shortcut_y=(in_y-142)>>1;
    end
   end
  end
 end
 // Three visible mode labels use the existing registered glyph pipeline.
 function [5:0] mode_caption;
  input [1:0] mode_index;input [3:0] pos;
  begin
   mode_caption=`CH_SPACE;
   case(mode_index)
    0:case(pos)0:mode_caption=`CH_A;1:mode_caption=`CH_U;2:mode_caption=`CH_D;3:mode_caption=`CH_I;4:mode_caption=`CH_T;5:mode_caption=`CH_I;6:mode_caption=`CH_O;7:mode_caption=`CH_N;endcase
    1:case(pos)0:mode_caption=`CH_F;1:mode_caption=`CH_O;2,3:mode_caption=`CH_L;4:mode_caption=`CH_O;5:mode_caption=`CH_W;endcase
    2:case(pos)0:mode_caption=`CH_P;1:mode_caption=`CH_E;2:mode_caption=`CH_R;3:mode_caption=`CH_F;4:mode_caption=`CH_O;5:mode_caption=`CH_R;6:mode_caption=`CH_M;endcase
   endcase
  end
 endfunction

 assign result={shortcut,shortcut_char,shortcut_x,shortcut_y};
endmodule
module shortcut_production(input wire [13:0] in_x,in_y,input wire [2:0] view,
 input wire [23:0] plot_scales,output wire [15:0] result);
 localparam PERFORMANCE_CALIBRATION_ENABLE=0;
 wire [6:0] performance_base_note=41;wire [2:0] performance_calibration_state=0;
 `include "navigation_shortcuts.vh"
 assign result={shortcut,shortcut_char,shortcut_x,shortcut_y};
endmodule
module tb_navigation_shortcuts_equiv;
 reg [13:0] in_x=0,in_y=0;reg [2:0] view=0;reg [23:0] plot_scales=24'he4e4e4;
 wire [15:0] actual,expected;
 shortcut_reference ref_dut(in_x,in_y,view,plot_scales,expected);
 shortcut_production dut(in_x,in_y,view,plot_scales,actual);
 integer x,y,v,g,checks=0,hits=0;
 task check;begin
  #1;
  if(actual!==expected)$fatal(1,"Shortcut mismatch view=%0d x=%0d y=%0d gain=%h actual=%h expected=%h",view,in_x,in_y,plot_scales,actual,expected);
  checks=checks+1;if(actual[15])hits=hits+1;
 end endtask
 initial begin
  // Every active and blanking pixel on both pages containing shortcuts.
  for(v=1;v<=2;v=v+1)begin
   view=v;
   for(y=0;y<750;y=y+1)for(x=0;x<1650;x=x+1)begin in_x=x;in_y=y;check;end
  end
  // Every gain at every pixel of each shortcut band, including both edges.
  view=1;
  for(g=0;g<4;g=g+1)begin
   plot_scales={12{g[1:0]}};
   for(y=355;y<=372;y=y+1)for(x=0;x<1280;x=x+1)begin in_x=x;in_y=y;check;end
   for(y=651;y<=668;y=y+1)for(x=0;x<1280;x=x+1)begin in_x=x;in_y=y;check;end
  end
  // Other pages can never expose a shortcut. Include off-screen coordinates.
  for(v=0;v<8;v=v+1)if(v!=1 && v!=2)begin
   view=v;
   for(y=0;y<800;y=y+13)for(x=0;x<1700;x=x+7)begin in_x=x;in_y=y;check;end
  end
  $display("PASS: parallel shortcut selector equals frozen production logic for %0d raster/gain/page cases (%0d hits), including mode glyph cells and blanking",checks,hits);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Shortcut equivalence watchdog");end
endmodule
