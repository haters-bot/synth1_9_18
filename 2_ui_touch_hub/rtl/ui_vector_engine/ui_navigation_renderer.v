`include "params.vh"
`include "font_3x5.vh"
`include "pixel_coverage.vh"
// Five stages after raster entry; native navigation font and visual examples.
module ui_navigation_renderer(
 input wire clk,rst_n,
 input wire [13:0] in_x,in_y,
 input wire [1:0] view,
 input wire [7:0] settings_section_id,
 input wire show_diagnostics,usb_connected,usb_error,
 input wire [27:0] macro_values,
 output reg out_hit,
 output reg [23:0] out_rgb
);
 `include "navigation_font_hd.vh"
 `include "navigation_labels.vh"
 reg hit;reg [23:0] bg;
 reg [1:0] macro_row;
 reg macro_number;
 reg [6:0] number;
 reg [5:0] number_char;
 wire master_hole=view==0 && in_x>=1140 && in_x<=1230 && in_y<44;
 wire [23:0] tile_color[0:5];
 wire [23:0] tile_demo_color[0:5];
 wire [5:0] tile_demo_hit;
 wire [5:0] tile_hit;
 genvar tile;
 generate for(tile=0;tile<6;tile=tile+1)begin: visual_tile
  localparam X=24+(tile%3)*418,Y=96+(tile/3)*296;
  wire inside_tile=in_x>=X && in_x<=X+396 && in_y>=Y && in_y<=Y+278;
  wire border=in_x==X || in_x==X+396 || in_y==Y || in_y==Y+278;
  wire plot=in_y>=Y+72 && in_y<Y+232 && in_x>=X+16 && in_x<X+380;
  wire axis=in_x==X+198 || in_y==Y+140;
  wire grid=in_x[5:0]==0 || in_y[5:0]==0;
  wire [8:0] gx=in_x-(X+16);
  wire [7:0] gy=in_y-(Y+80);
  wire graph_area=plot && in_y>=Y+80 && in_y<Y+232;
  if(tile==0)begin: demo_notes
   wire bars=(in_x>=X+48 && in_x<=X+176 && in_y>=Y+106 && in_y<=Y+114) ||
             (in_x>=X+96 && in_x<=X+232 && in_y>=Y+130 && in_y<=Y+138) ||
             (in_x>=X+144 && in_x<=X+320 && in_y>=Y+154 && in_y<=Y+162);
   wire keys=in_y>=Y+176 && in_y<=Y+220 && in_x>=X+24 && in_x<=X+372;
   wire black_key=keys && in_y<Y+205 &&
      ((in_x>=X+42&&in_x<=X+53)||(in_x>=X+72&&in_x<=X+83)||
       (in_x>=X+132&&in_x<=X+143)||(in_x>=X+162&&in_x<=X+173)||
       (in_x>=X+192&&in_x<=X+203)||(in_x>=X+252&&in_x<=X+263)||
       (in_x>=X+282&&in_x<=X+293)||(in_x>=X+312&&in_x<=X+323));
   assign tile_demo_hit[tile]=graph_area&&(bars||keys);
   assign tile_demo_color[tile]=bars?24'h57C9C0:black_key?24'h35536A:24'hB8CADB;
  end else if(tile==1)begin: demo_waveform
   wire [7:0] sample=demo_wave(gx[6:2]);
   wire [7:0] target=sample;
   wire [7:0] distance=gy>target ? gy-target : target-gy;
   assign tile_demo_hit[tile]=graph_area&&distance<=4;
   assign tile_demo_color[tile]=24'h61DED1;
  end else if(tile==2)begin: demo_phase
   wire [7:0] ax=gx>182 ? gx-182 : 182-gx;
   wire [7:0] ay=gy>68 ? gy-68 : 68-gy;
   reg [7:0] ellipse_x;
   always @* case(ay[6:2])
    0:ellipse_x=166;1:ellipse_x=166;2:ellipse_x=165;3:ellipse_x=163;4:ellipse_x=160;
    5:ellipse_x=157;6:ellipse_x=154;7:ellipse_x=150;8:ellipse_x=146;9:ellipse_x=141;
    10:ellipse_x=136;11:ellipse_x=130;12:ellipse_x=124;13:ellipse_x=117;14:ellipse_x=109;
    15:ellipse_x=100;16:ellipse_x=90;17:ellipse_x=79;18:ellipse_x=66;19:ellipse_x=50;
    20:ellipse_x=28;default:ellipse_x=0;
   endcase
   wire [7:0] ellipse_distance=ax>ellipse_x ? ax-ellipse_x : ellipse_x-ax;
   assign tile_demo_hit[tile]=graph_area&&ay<=8'd72&&ellipse_x!=0&&ellipse_distance<=2;
   assign tile_demo_color[tile]=24'h67CDE0;
  end else if(tile==3)begin: demo_spectrum
   reg [6:0] height;
   always @* case(gx[8:5])
    0:height=18;1:height=30;2:height=46;3:height=62;4:height=78;5:height=94;
    6:height=82;7:height=67;8:height=51;9:height=39;10:height=27;default:height=17;
   endcase
   assign tile_demo_hit[tile]=graph_area&&gx[4:0]>=6&&gx[4:0]<=24&&in_y>=Y+224-height;
   assign tile_demo_color[tile]=24'h65CDA4;
  end else if(tile==4)begin: demo_spectrogram
   wire [2:0] tone=(gx[8:5]+gy[7:5]);
   assign tile_demo_hit[tile]=graph_area&&gx[4:0]>=4&&gx[4:0]<=27&&gy<8'd136&&gy[4:0]>=4&&gy[4:0]<=25;
   assign tile_demo_color[tile]=tone[1]?(tone[0]?24'hDBA65F:24'hD16E64):(tone[0]?24'h66CBAE:24'h4A819D);
  end else begin: demo_levels
   wire bar1=in_y>=Y+108&&in_y<=Y+125&&in_x>=X+52&&in_x<=X+344;
   wire bar2=in_y>=Y+144&&in_y<=Y+161&&in_x>=X+52&&in_x<=X+344;
   wire bar3=in_y>=Y+180&&in_y<=Y+197&&in_x>=X+52&&in_x<=X+344;
   wire fill1=bar1&&in_x<=X+258,fill2=bar2&&in_x<=X+294,fill3=bar3&&in_x<=X+188;
   assign tile_demo_hit[tile]=graph_area&&(bar1||bar2||bar3);
   assign tile_demo_color[tile]=(fill1||fill2||fill3)?24'h65CDA4:24'h26394B;
  end
  assign tile_hit[tile]=inside_tile;
  assign tile_color[tile]=!inside_tile ? 24'd0 : border ? 24'h35495F :
   in_y<Y+48 ? 24'h1B2B3C : plot ? (tile_demo_hit[tile] ? tile_demo_color[tile] : (axis ? 24'h26394B : grid ? 24'h152331 : 24'h0B131D)) : 24'h111B28;
 end endgenerate
 wire [23:0] visual_bg=(|tile_hit) ? tile_color[0]|tile_color[1]|tile_color[2]|tile_color[3]|tile_color[4]|tile_color[5] : 24'h101318;
 reg [11:0] bcd[0:3];
 genvar n;
 generate for(n=0;n<4;n=n+1)begin: decimal_cache
  wire [6:0] value=macro_values[n*7+:7];
  wire [3:0] hundreds=value/7'd100,tens=(value%7'd100)/7'd10,ones=value%7'd10;
  always @(posedge clk)bcd[n]<={hundreds,tens,ones};
 end endgenerate
 always @(*)begin
  hit=(in_y<44 && !master_hole) || view!=0;
  bg=24'h101318;
  if(in_y<44)begin
   bg=24'h151D29;
   if(in_y==42)bg=24'h2C94A8;
   if(in_x>=20 && in_x<=40 && (in_y==14 || in_y==19 || in_y==24 || in_y==29))bg=24'hC4D7E8;
   if((view==0 && in_x>=128 && in_x<320) ||
      (view==1 && in_x>=336 && in_x<576) ||
      (view==2 && in_x>=592 && in_x<800))bg=24'h204152;
  end else if(view==1)begin
   // Clearly labeled static examples. No live sound data is claimed.
   bg=visual_bg;
  end else if(view==2 && settings_section_id==8'd1)begin
   if(in_x>=32 && in_x<=680 && in_y>=120 && in_y<=616)bg=24'h142030;
   if(in_x>=712 && in_x<=1248 && in_y>=120 && in_y<=616)bg=24'h142030;
   if(in_x>=240 && in_x<=640 && in_y>=232 && in_y<=480)begin
    if((in_y-232)%64<=56)bg=24'h22374C;
    if(in_x>304 && in_x<576)bg=24'h101A27;
   end
   if(in_x>=880 && in_x<=1216 && in_y>=520 && in_y<=584)
    bg=show_diagnostics ? 24'h205148 : 24'h25384D;
  end else if(view==3)begin
   if(in_y>=160 && in_y<=480)begin
    if((in_x>=48 && in_x<=416)||(in_x>=456 && in_x<=824)||(in_x>=864 && in_x<=1232))begin
     bg=24'h17283B;
     if(in_y==160 || in_y==480)bg=24'h3E8495;
     if(in_y>=280 && in_y<=336 && in_x[5:0]>=16 && in_x[5:0]<=48)bg=24'h25465C;
    end
   end
  end else if(view==2)begin
   bg=24'h101820;
   if(in_x>=32&&in_x<=680&&in_y>=120&&in_y<=616)bg=24'h142030;
   if(in_x>=712&&in_x<=1248&&in_y>=120&&in_y<=616)bg=24'h142030;
   if(in_x==32||in_x==680||in_x==712||in_x==1248||in_y==120||in_y==616)bg=24'h35495F;
   if(settings_section_id!=8'd1 && in_x>=736 && in_x<=1216 && in_y>=196 && in_y<=552)bg=24'h192A3B;
   if(in_x>=712&&in_x<=1248&&in_y>=120&&in_y<=616&&
      (in_x==712||in_x==1248||in_y==120||in_y==616))bg=24'h35495F;
  end
  if(view==2 && in_y>=88 && in_y<120)begin
   bg=24'h1A2735;
   if((settings_section_id==8'd1&&in_x>=32&&in_x<336)||(settings_section_id==8'd2&&in_x>=336&&in_x<632)||
      (settings_section_id==8'd3&&in_x>=632&&in_x<928)||(settings_section_id==8'd4&&in_x>=928&&in_x<=1248))bg=24'h285064;
   if(in_y==119)bg=24'h347B90;
  end
  macro_row=(in_y-248)>>6;
  macro_number=view==2 && settings_section_id==8'd1 && in_y>=248 && in_y<460 && ((in_y-248)&63)<16 && in_x>=416 && in_x<464;
  case(macro_row)
   0:number=macro_values[0+:7];1:number=macro_values[7+:7];
   2:number=macro_values[14+:7];default:number=macro_values[21+:7];
  endcase
  case((in_x-416)>>4)
   0:number_char=number>=100 ? `CH_1 : `CH_SPACE;
   1:number_char=`CH_0+bcd[macro_row][7:4];
   default:number_char=`CH_0+bcd[macro_row][3:0];
  endcase
 end
 reg h0,h1,h2,h3;
 reg [23:0] b0,b1,b2,b3,fg0,fg1,fg2;
 reg [6:0] id0;reg [5:0] col0,ch1;
 reg [3:0] rx0,rx1;reg [4:0] ry0,ry1;
 reg large0,large1;
 reg tv0,tv1;reg [5:0] digit0;
 reg number0;
 reg [1:0] coverage2;
 function [7:0] demo_wave;input [4:0] phase;begin case(phase)
 0:demo_wave=72;1:demo_wave=84;2:demo_wave=96;3:demo_wave=105;4:demo_wave=111;5:demo_wave=117;6:demo_wave=120;7:demo_wave=121;
 8:demo_wave=121;9:demo_wave=120;10:demo_wave=117;11:demo_wave=111;12:demo_wave=105;13:demo_wave=96;14:demo_wave=84;15:demo_wave=72;
 16:demo_wave=72;17:demo_wave=60;18:demo_wave=48;19:demo_wave=39;20:demo_wave=33;21:demo_wave=27;22:demo_wave=24;23:demo_wave=23;
 24:demo_wave=23;25:demo_wave=24;26:demo_wave=27;27:demo_wave=33;28:demo_wave=39;29:demo_wave=48;30:demo_wave=60;default:demo_wave=72;
 endcase end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin h0<=0;h1<=0;h2<=0;h3<=0;out_hit<=0;out_rgb<=0;end
  else begin
   h0<=hit;b0<=bg;fg0<=text_color;id0<=text_id;col0<=text_col;
   tv0<=text_valid||macro_number;number0<=macro_number;digit0<=number_char;
   rx0<=macro_number ? in_x[3:0] : text_rx;ry0<=macro_number ? ((in_y-248)&63) : text_ry;
   large0<=!macro_number && text_large;
   h1<=h0;b1<=b0;fg1<=fg0;tv1<=tv0;
   ch1<=number0 ? digit0 : navigation_char(id0,col0);rx1<=rx0;ry1<=ry0;large1<=large0;
   h2<=h1;b2<=b1;fg2<=fg1;coverage2<=tv1 ? navigation_font(ch1,large1,rx1,ry1) : 0;
   h3<=h2;b3<=blend_rgb_q4(fg2,b2,font_alpha_q4(coverage2));
   out_hit<=h3;out_rgb<=b3;
  end
 end
endmodule
