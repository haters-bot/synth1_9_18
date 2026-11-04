`include "font_7x10.vh"
`include "pixel_coverage.vh"
// Four raster stages. The parent navigation's existing final stage supplies
// stage five, preserving the full renderer's seven-clock pixel latency.
module synth_preset_panel(
 input wire clk,rst_n,
 input wire [13:0] x,y,
 input wire visible,
 input wire [2:0] category,
 input wire [3:0] active_index,
 input wire applied_valid,busy,pending,custom_notice,
 output reg hit,
 output reg [23:0] rgb
);
 `include "synth_preset_text.vh"
 `include "synth_preset_layout.vh"
 reg [23:0] bg,fg;
 reg [287:0] line;
 reg [5:0] column;
 reg [2:0] glyph_x;
 reg [3:0] glyph_y;
 reg text_valid;
 integer i,row_y,idx;
 // Text origins are constant or category-local. No pixel division except
 // power-of-two scaling. Names stay ASCII, matching the existing font bank.
 task text_at;
  input [5:0] id;input integer tx,ty;input is_large;
  begin
   if(x>=tx && x<tx+(is_large ? 768 : 384) && y>=ty && y<ty+(is_large ? 20 : 10))begin
    line=synth_preset_text(id);column=(x-tx)>>(is_large ? 4 : 3);
    glyph_x=((x-tx)>>(is_large ? 1 : 0)) & 7;
    glyph_y=(y-ty)>>(is_large ? 1 : 0);text_valid=1;
   end
  end
 endtask
 always @* begin
  bg=24'h101820;fg=24'hDDE7F4;line=0;column=0;glyph_x=0;glyph_y=0;text_valid=0;
  text_at(applied_valid || busy ? PRESET_TITLE_BASE+active_index : PRESET_TEXT_SELECT,280,144,1);
  for(i=0;i<6;i=i+1)begin
   if(x>=40 && x<248 && y>=172+i*68 && y<228+i*68)
    bg=category==i ? 24'h246B68 : 24'h1B3044;
   text_at(i,56,192+i*68,1);
  end
  for(i=0;i<3;i=i+1)begin
   row_y=192+i*128;idx=synth_preset_row_index(category,i);
   if(synth_preset_row_visible(category,i))begin
    if(x>=280 && x<1248 && y>=row_y && y<row_y+112)begin
     bg=(applied_valid || busy) && active_index==idx ? 24'h1D4D4E : 24'h182A3B;
     // Thin colored spine doubles as a is_large, unambiguous touch-card cue.
     if(x<288)bg=24'h52CCBB;
     if(y==row_y || y==row_y+111)bg=24'h34596A;
    end
    text_at(PRESET_TITLE_BASE+idx,312,row_y+20,1);
    text_at(PRESET_DETAIL_BASE+idx,312,row_y+68,1);
   end
  end
  if(y>=612 && y<660)begin
   if(x>=280 && x<488)bg=applied_valid ? 24'h246B68 : 24'h24313D;
   if(x>=504 && x<696)bg=24'h22374C;
   if(x>=800 && x<1248)bg=24'h28313A;
  end
  text_at(PRESET_TEXT_REAPPLY,304,628,1);text_at(PRESET_TEXT_BACK,528,628,1);text_at(PRESET_TEXT_CUSTOM,824,628,1);
  text_at(pending ? PRESET_TEXT_QUEUED : busy ? PRESET_TEXT_APPLYING : PRESET_TEXT_READY,800,148,1);
  text_at(custom_notice ? PRESET_TEXT_NOTICE : PRESET_TEXT_FOOTER,40,680,0);
  text_at(PRESET_TEXT_SD,800,680,0);
 end
 reg h0,h1,h2;
 reg [287:0] line0;
 reg [5:0] col0,ch1;
 reg [2:0] gx0,gx1,gx2;
 reg [3:0] gy0,gy1;
 reg tv0,tv1,tv2;
 reg [13:0] font_row2;
 reg [23:0] bg0,bg1,bg2,fg0,fg1,fg2;
 reg [5:0] selected_char;
 integer c;
 always @* begin
  selected_char=0;
  for(c=0;c<48;c=c+1)selected_char=selected_char|({6{col0==c}} & line0[(47-c)*6+:6]);
 end
 function [1:0] coverage;
  input [13:0] row;input [2:0] px;integer c;
  begin coverage=0;
   for(c=0;c<7;c=c+1)coverage=coverage|({2{px==c}} & row[(6-c)*2+:2]);
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin h0<=0;h1<=0;h2<=0;hit<=0;rgb<=0;tv0<=0;tv1<=0;tv2<=0;end
  else begin
   h0<=visible && x>=32 && x<1248 && y>=128 && y<708;
   line0<=line;col0<=column;gx0<=glyph_x;gy0<=glyph_y;tv0<=text_valid;bg0<=bg;fg0<=fg;
   h1<=h0;ch1<=selected_char;gx1<=gx0;gy1<=gy0;tv1<=tv0;bg1<=bg0;fg1<=fg0;
   h2<=h1;font_row2<=get_font_7x10_row(ch1,gy1);gx2<=gx1;tv2<=tv1;bg2<=bg1;fg2<=fg1;
   hit<=h2;rgb<=blend_rgb_q4(fg2,bg2,font_alpha_q4(tv2 ? coverage(font_row2,gx2) : 0));
  end
 end
endmodule
