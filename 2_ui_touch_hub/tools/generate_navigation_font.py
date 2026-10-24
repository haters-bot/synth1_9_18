"""Generate a compact 4x6 navigation font from the verified 7x10 glyph source."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]


def source_cell(glyph, sx, sy):
    x0 = (sx * 7) // 4
    x1 = ((sx + 1) * 7 + 3) // 4
    y0 = (sy * 10) // 6
    y1 = ((sy + 1) * 10 + 2) // 6
    return max(glyph[y][x] for y in range(y0, y1) for x in range(x0, x1)) >= 2


def main():
    data = json.loads((ROOT / 'tools/ui_font_7x10.json').read_text())
    rows = []
    for idx, glyph in enumerate(data['glyphs']):
        for sy in range(6):
            bits = ''.join('1' if source_cell(glyph, sx, sy) else '0' for sx in range(4))
            rows.append(f"     9'd{idx * 8 + sy}: navigation_font_row=4'b{bits};\n")
    text = '''// Generated navigation font: pre-compressed 4x6 coverage glyphs.
// The 4x6 table keeps the navigation path shallow while preserving readable shapes.
function [3:0] navigation_font_row;
 input [5:0] ch; input [2:0] sy;
 begin
  case({ch,sy})
''' + ''.join(rows) + '''   default: navigation_font_row=4'b0000;
  endcase
 end
endfunction
function [1:0] navigation_font;
 input [5:0] ch; input is_heading; input [3:0] rx; input [4:0] ry;
 reg [2:0] sx,sy; reg [3:0] row;
 begin
  sx=0; sy=0; row=0;
  if(is_heading) begin
   if(rx>=15 || ry>=22) navigation_font=0;
   else begin
    case(rx)
     0,1,2,3:sx=0; 4,5,6,7:sx=1; 8,9,10,11:sx=2; default:sx=3;
    endcase
    case(ry)
     0,1,2:sy=0; 3,4,5,6:sy=1; 7,8,9:sy=2; 10,11,12,13:sy=3;
     14,15,16,17:sy=4; default:sy=5;
    endcase
    row=navigation_font_row(ch,sy);
    navigation_font=row[3-sx] ? 2'd3 : 2'd0;
   end
  end else begin
   if(rx<2 || rx>12 || ry>=16) navigation_font=0;
   else begin
    case(rx)
     2,3,4:sx=0; 5,6,7:sx=1; 8,9:sx=2; default:sx=3;
    endcase
    case(ry)
     0,1:sy=0; 2,3,4:sy=1; 5,6,7:sy=2; 8,9,10:sy=3;
     11,12,13:sy=4; default:sy=5;
    endcase
    row=navigation_font_row(ch,sy);
    navigation_font=row[3-sx] ? 2'd3 : 2'd0;
   end
  end
 end
endfunction
'''
    (ROOT / 'rtl/ui_vector_engine/navigation_font.vh').write_text(text)
    print('Navigation font generated: compact 4x6 table, body 11x16, heading 15x22')


if __name__ == '__main__':
    main()
