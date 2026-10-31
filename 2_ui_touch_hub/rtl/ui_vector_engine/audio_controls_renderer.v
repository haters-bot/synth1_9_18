`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"
// Five raster stages, same input tap/latency as the retired production FX strip.
// Basic/SD wave pictures are illustrative; never pretend to have SD sample data.
module audio_controls_renderer(
 input wire clk,rst_n,
 input wire [13:0] in_x,in_y,
 input wire [237:0] extra_values,
 input wire [132:0] legacy_values,
 input wire [2:0] fx_page,
 input wire [1:0] warp_menu,
 input wire [2:0] wave_a,wave_b,
 input wire [105:0] sources,
 output reg out_hit,
 output reg [23:0] out_rgb
);
 `include "audio_extra_controls.vh"
 function [5:0] digit;input [6:0] value;begin digit=`CH_0+value;end endfunction
 function [143:0] number_line;input [6:0] value;
  begin number_line={digit(value/7'd100),digit((value%7'd100)/7'd10),digit(value%7'd10),126'd0};end
 endfunction
 function [6:0] read_value;
  input [7:0] id;input [237:0] extra_bank;input [132:0] legacy_bank;integer j;
  begin read_value=0;
   for(j=0;j<34;j=j+1)read_value=read_value | ({7{id==8'hA0+j}} & extra_bank[j*7+:7]);
   for(j=0;j<19;j=j+1)read_value=read_value | ({7{id==8'h60+j}} & legacy_bank[j*7+:7]);
  end
 endfunction
 function [143:0] caption;
  input [7:0] id;
  begin case(id)
   `PARAM_ID_DIST_DRIVE:caption=pack_font24("DRIVE                   ");
   `PARAM_ID_DIST_TONE:caption=pack_font24("TONE                    ");
   `PARAM_ID_DIST_MIX,`PARAM_ID_CHORUS_MIX,`PARAM_ID_PHASER_MIX,`PARAM_ID_COMP_MIX:caption=pack_font24("MIX                     ");
   `PARAM_ID_PHASER_RATE,`PARAM_ID_CHORUS_RATE:caption=pack_font24("RATE                    ");
   `PARAM_ID_PHASER_DEPTH,`PARAM_ID_CHORUS_DEPTH:caption=pack_font24("DEPTH                   ");
   `PARAM_ID_PHASER_CENTER:caption=pack_font24("CENTER                  ");
   `PARAM_ID_PHASER_FEEDBACK,`PARAM_ID_CHORUS_FEEDBACK:caption=pack_font24("FEEDBACK                ");
   `PARAM_ID_CHORUS_DELAY:caption=pack_font24("DELAY                   ");
   `PARAM_ID_DELAY_TIME:caption=pack_font24("DLY TIME                ");
   `PARAM_ID_DELAY_FEEDBACK:caption=pack_font24("DLY FDBK                ");
   `PARAM_ID_DELAY_MIX:caption=pack_font24("DLY MIX                 ");
   `PARAM_ID_REVERB_SIZE:caption=pack_font24("REV SIZE                ");
   `PARAM_ID_REVERB_DECAY:caption=pack_font24("REV DECAY               ");
   `PARAM_ID_REVERB_MIX:caption=pack_font24("REV MIX                 ");
   `PARAM_ID_COMP_THRESH:caption=pack_font24("THRESHOLD               ");
   `PARAM_ID_COMP_RATIO:caption=pack_font24("RATIO                   ");
   `PARAM_ID_COMP_ATTACK:caption=pack_font24("ATTACK                  ");
   `PARAM_ID_COMP_RELEASE:caption=pack_font24("RELEASE                 ");
   `PARAM_ID_COMP_MAKEUP:caption=pack_font24("MAKEUP                  ");
   `PARAM_ID_VIB_RATE:caption=pack_font24("VIB RATE                ");
   `PARAM_ID_VIB_DEPTH:caption=pack_font24("VIB DEPTH               ");
   `PARAM_ID_PORTA_TIME:caption=pack_font24("PORT TIME               ");
   default:caption=0;
  endcase end
 endfunction
 function [143:0] mode_label;
  input [6:0] mode;
  begin case(mode)
   0:mode_label=pack_font24("OFF                     ");
   1:mode_label=pack_font24("PWM                     ");
   2:mode_label=pack_font24("SYNC                    ");
   3:mode_label=pack_font24("BEND +                  ");
   4:mode_label=pack_font24("BEND -                  ");
   5:mode_label=pack_font24("BEND +/-                ");
   6:mode_label=pack_font24("ASYM +                  ");
   7:mode_label=pack_font24("ASYM -                  ");
   8:mode_label=pack_font24("ASYM +/-                ");
   9:mode_label=pack_font24("FLIP                    ");
   10:mode_label=pack_font24("MIRROR                  ");
   default:mode_label=pack_font24("QUANTIZE                ");
  endcase end
 endfunction
 function [143:0] warp_caption;
  input [6:0] mode;reg [143:0] name;
  begin name=mode_label(mode);warp_caption={`CH_W,`CH_A,`CH_R,`CH_P,`CH_SPACE,name[143:30]};end
 endfunction
 function [5:0] char_at;
  input [143:0] text;input [4:0] col;
  begin case(col)
   0:char_at=text[143:138];1:char_at=text[137:132];2:char_at=text[131:126];3:char_at=text[125:120];
   4:char_at=text[119:114];5:char_at=text[113:108];6:char_at=text[107:102];7:char_at=text[101:96];
   8:char_at=text[95:90];9:char_at=text[89:84];10:char_at=text[83:78];11:char_at=text[77:72];
   12:char_at=text[71:66];13:char_at=text[65:60];14:char_at=text[59:54];15:char_at=text[53:48];
   16:char_at=text[47:42];17:char_at=text[41:36];18:char_at=text[35:30];19:char_at=text[29:24];
   20:char_at=text[23:18];21:char_at=text[17:12];22:char_at=text[11:6];23:char_at=text[5:0];
   default:char_at=0;endcase end
 endfunction
 function [1:0] fx_source;
  input [7:0] id;input [105:0] route_sources;
  begin case(id)
   8'h60:fx_source=route_sources[68+:2];8'h61:fx_source=route_sources[70+:2];8'h65:fx_source=route_sources[78+:2];
   8'h66:fx_source=route_sources[80+:2];8'h67:fx_source=route_sources[82+:2];8'h6C:fx_source=route_sources[92+:2];
   default:fx_source=0;endcase end
 endfunction
 reg [6:0] cell_values[0:5];
 reg [143:0] cell_labels[0:5];
 reg [143:0] cell_numbers[0:5];
 reg [7:0] bar_width[0:5];
 reg [1:0] cell_sources[0:5];
 genvar g;
 generate for(g=0;g<6;g=g+1)begin:control_plane
  wire [7:0] id=audio_fx_cell_id(fx_page,g);
  wire [6:0] value=read_value(id,extra_values,legacy_values);
  always @(posedge clk)begin
   cell_values[g]<=value;cell_labels[g]<=caption(id);cell_sources[g]<=fx_source(id,sources);
   // Decimal conversion stays on the control plane, before raster selection.
   cell_numbers[g]<=number_line(value);
   bar_width[g]<=({8'd0,value}*15'd154)>>7;
  end
 end endgenerate
 reg [13:0] x0,y0;
 always @(posedge clk)begin x0<=in_x;y0<=in_y;end
 reg hit,text_hit;
 reg [23:0] bg;
 reg [143:0] line;
 reg [13:0] tx,ty;
 integer j,cx,cy,w,tab_col,osc_x,row,col,mode;
 reg [6:0] v,warp_rate,bank;
 reg enabled;
 always @(*)begin
  hit=0;text_hit=0;bg=24'h181C24;line=0;tx=0;ty=0;
  cx=0;cy=0;w=0;tab_col=0;osc_x=0;row=0;col=0;mode=0;v=0;enabled=0;warp_rate=0;bank=0;
  if(x0>=420 && x0<=780 && y0>=368 && y0<=707)begin
   hit=1;
   if(y0>=372 && y0<404 && x0>=424 && x0<772)begin
    tab_col=x0<482 ? 0 : x0<540 ? 1 : x0<598 ? 2 : x0<656 ? 3 : x0<714 ? 4 : 5;
    cx=424+tab_col*58;
    bg=fx_page==tab_col ? 24'h244C64 : 24'h222834;
    case(tab_col)
     0:line=pack_font24("DIST                    ");1:line=pack_font24("PHAS                    ");
     2:line=pack_font24("CHOR                    ");3:line=pack_font24("D/R                     ");
     4:line=pack_font24("COMP                    ");default:line=pack_font24("PITCH                   ");
    endcase
    tx=x0-(cx+4);ty=y0-382;text_hit=x0>=cx+4 && ty<10;
   end
   if(y0>=410 && y0<440 && x0>=432 && x0<776)begin
    cx=x0<608 ? 432 : 608;bg=24'h222834;
    if(fx_page==5)begin
     enabled=x0<608 ? |extra_values[203+:7] : |extra_values[224+:7];
     line=x0<608 ? (enabled ? pack_font24("VIBRATO ON              ") : pack_font24("VIBRATO OFF             ")) :
                   (enabled ? pack_font24("PORTAMENTO ON           ") : pack_font24("PORTAMENTO OFF          "));
    end else if(fx_page==3)begin
     enabled=x0<608 ? extra_values[28] : extra_values[29];
     line=x0<608 ? (enabled ? pack_font24("DELAY ON                ") : pack_font24("DELAY OFF               ")) :
                   (enabled ? pack_font24("REVERB ON               ") : pack_font24("REVERB OFF              "));
    end else if(x0<608)begin
     enabled=fx_page==0 ? |extra_values[35+:7] : fx_page==1 ? |extra_values[112+:7] : fx_page==2 ? |extra_values[70+:7] : |extra_values[154+:7];
     line=enabled ? pack_font24("ENABLED                 ") : pack_font24("BYPASSED                ");
    end else if(fx_page==0)begin
     line=extra_values[42+:7]==0 ? pack_font24("SOFT CLIP               ") : extra_values[42+:7]==1 ? pack_font24("HARD CLIP               ") : pack_font24("FOLDBACK                ");
    end
    if(enabled)bg=24'h245448;
    tx=x0-(cx+4);ty=y0-420;text_hit=x0>=cx+4 && ty<10;
   end
   for(j=0;j<6;j=j+1)begin
    cx=audio_cell_x(j);cy=audio_cell_y(j);w=166;
    if(x0>=cx && x0<cx+w && y0>=cy && y0<cy+38 && cell_labels[j]!=0)begin
     bg=24'h111822;line=cell_labels[j];tx=x0-(cx+4);ty=y0-(cy+4);text_hit=x0>=cx+4 && ty<10;
     v=cell_values[j];
     // Three raw MIDI digits, no invented physical units.
     if(x0>=cx+136 && x0<cx+160 && y0>=cy+4 && y0<cy+14)begin
      tx=x0-(cx+136);ty=y0-(cy+4);text_hit=1;
      line=cell_numbers[j];
     end
     if(y0>=cy+30 && y0<cy+34 && x0>=cx+4 && x0<cx+4+bar_width[j])bg=cell_sources[j]==0 ? 24'h38C4CC : cell_sources[j]==1 ? 24'hC98BFF : cell_sources[j]==2 ? 24'hF7BB62 : 24'h73EDB5;
    end
   end
   if(fx_page==5 && x0>=432 && x0<776)begin
    if(y0>=586 && y0<602)begin line=pack_font24("PITCH CONTROLS          ");tx=x0-436;ty=y0-588;text_hit=x0>=436 && ty<10;end
    if(y0>=610 && y0<626)begin line=pack_font24("VALUES: MIDI 0-127      ");tx=x0-436;ty=y0-612;text_hit=x0>=436 && ty<10;end
    if(y0>=634 && y0<650)begin line=pack_font24("ON/OFF KEEPS SETTINGS   ");tx=x0-436;ty=y0-636;text_hit=x0>=436 && ty<10;end
   end
  end
  // Keep the two original oscillator scopes and their header selectors.
  if((x0>=40 && x0<412)||(x0>=456 && x0<828))begin
   osc_x=x0<424 ? 40 : 456;warp_rate=x0<424 ? extra_values[0+:7] : extra_values[7+:7];
   bank=x0<424 ? extra_values[14+:7] : extra_values[21+:7];
   if(y0>=212 && y0<236)begin
    hit=1;bg=24'h202E3B;ty=y0-218;text_hit=ty<10;
    if(x0<osc_x+184)begin line=warp_caption(warp_rate);tx=x0-(osc_x+4);text_hit=text_hit && x0>=osc_x+4;end
    else if(x0>=osc_x+200 && x0<osc_x+368)begin
     line={`CH_B,`CH_A,`CH_N,`CH_K,`CH_SPACE,digit(bank/7'd10),digit(bank%7'd10),`CH_SPACE,`CH_MINUS,`CH_SPACE,`CH_PLUS,78'd0};
     tx=x0-(osc_x+204);text_hit=text_hit && x0>=osc_x+204;
    end else text_hit=0;
   end
   if(warp_menu==(osc_x==40 ? 1 : 2) && y0>=108 && y0<212)begin
    hit=1;col=x0<osc_x+124 ? 0 : x0<osc_x+248 ? 1 : 2;
    row=y0<134 ? 0 : y0<160 ? 1 : y0<186 ? 2 : 3;mode=row*3+col;
    bg=warp_rate==mode ? 24'h245448 : 24'h202936;line=mode_label(mode);
    tx=x0-(osc_x+col*124+4);ty=y0-(108+row*26+8);text_hit=x0>=osc_x+col*124+4 && ty<10;
   end else if((osc_x==40 ? wave_a : wave_b)==4 && y0>=108 && y0<212)begin
    hit=1;bg=24'h101923;
    if(y0>=154 && y0<164)begin line=pack_font24("SD/DDR NO PREVIEW       ");tx=x0-(osc_x+72);ty=y0-154;text_hit=x0>=osc_x+72;end
    else if(y0>=174 && y0<184)begin line=pack_font24("BANK STATUS UNAVAILABLE ");tx=x0-(osc_x+64);ty=y0-174;text_hit=x0>=osc_x+64;end
   end
  end
 end
 reg hit1,valid1;reg [23:0] bg1;reg [143:0] line1;reg [13:0] tx1,ty1;
 reg hit2,valid2;reg [23:0] bg2;reg [5:0] ch2;reg [2:0] rx2;reg [3:0] ry2;
 reg hit3;reg [23:0] bg3;reg [1:0] coverage3;
 always @(posedge clk)begin
  hit1<=hit;valid1<=text_hit && tx<192;bg1<=bg;line1<=line;tx1<=tx;ty1<=ty;
  hit2<=hit1;valid2<=valid1;bg2<=bg1;ch2<=char_at(line1,tx1[7:3]);rx2<=tx1[2:0];ry2<=ty1[3:0];
  hit3<=hit2;bg3<=bg2;coverage3<=valid2 ? get_font_7x10(ch2,rx2,ry2) : 0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin out_hit<=0;out_rgb<=0;end
  else begin out_hit<=hit3;out_rgb<=blend_rgb_q4(24'hE0E8F0,bg3,font_alpha_q4(coverage3));end
 end
endmodule
