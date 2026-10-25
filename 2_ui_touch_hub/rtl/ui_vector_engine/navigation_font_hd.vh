// High-definition navigation font wrapper.
//
// The legacy navigation_font.vh uses a 4x6 bitmap. Navigation pages now
// sample the existing 7x10 adjustment-page font so the glyph detail is at
// least comparable to the tuning pages, while keeping the old file intact
// as a rollback option.
`include "font_7x10.vh"

function [1:0] navigation_font;
 input [5:0] ch;
 input is_heading;
 input [3:0] rx;
 input [4:0] ry;
 reg [2:0] gx;
 reg [3:0] gy;
 begin
  gx=0;
  gy=0;
  if(is_heading) begin
   // Heading cells are 14x20: exact 2x nearest-neighbour sampling.
   if(rx>=14 || ry>=20) navigation_font=2'd0;
   else begin
    gx=rx[3:1];
    gy=ry[4:1];
    navigation_font=get_font_7x10(ch,gx,gy);
   end
  end else begin
   // Normal cells remain 12x16. Map the full cell to the 7x10 glyph
   // without interpolation, preserving crisp integer pixel edges.
   if(rx>=12 || ry>=16) navigation_font=2'd0;
   else begin
    case(rx)
     0,1:gx=0; 2,3:gx=1; 4,5:gx=2; 6,7:gx=3;
     8,9:gx=4; 10:gx=5; default:gx=6;
    endcase
    case(ry)
     0,1:gy=0; 2,3:gy=1; 4:gy=2; 5,6:gy=3;
     7:gy=4; 8,9:gy=5; 10:gy=6; 11,12:gy=7;
     13:gy=8; default:gy=9;
    endcase
    navigation_font=get_font_7x10(ch,gx,gy);
   end
  end
 end
endfunction
