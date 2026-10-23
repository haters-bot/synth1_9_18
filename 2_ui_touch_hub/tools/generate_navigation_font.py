"""Native navigation glyphs: 11x16 body, 15x22 headings; no enlarged small bitmap."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]

def main():
    chars=json.loads((ROOT/'tools/ui_font_7x10.json').read_text())['characters']
    font=ImageFont.load_default(size=208)
    top,bottom=font.getbbox('H')[1::2]
    lines=['// Native Aileron coverage, Sora Sagano / No Rights Reserved.\n',
           'function [29:0] navigation_font_row;\ninput [5:0] ch; input is_heading; input [4:0] ry;\nbegin case({ch,is_heading,ry})\n']
    for large,(width,height) in enumerate([(11,16),(15,22)]):
        for idx,ch in enumerate(chars):
            box=font.getbbox(ch)
            raw=Image.new('L',(max(1,box[2]-box[0])+8,bottom-top))
            ImageDraw.Draw(raw).text((4-box[0],-top),ch,font=font,fill=255)
            bounds=raw.getbbox()
            canvas=Image.new('L',(15,height))
            if bounds:
                raw=raw.crop((bounds[0],0,bounds[2],raw.height))
                w=min(width,max(1,round(raw.width*height/raw.height)))
                small=raw.resize((w,height),Image.Resampling.LANCZOS)
                canvas.paste(small,((width-w)//2,0))
            for y in range(height):
                values=[canvas.getpixel((x,y)) for x in range(15)]
                bits=''.join(format(0 if a<32 else 1 if a<112 else 2 if a<208 else 3,'02b') for a in values)
                if int(bits,2):lines.append(f"12'd{idx*64+large*32+y}:navigation_font_row=30'b{bits};\n")
    lines+=['default:navigation_font_row=0;endcase end endfunction\n',
            'function [1:0] navigation_font;\ninput [5:0] ch; input is_heading; input [3:0] rx; input [4:0] ry;\nreg [29:0] row_bits;begin row_bits=navigation_font_row(ch,is_heading,ry);case(rx)\n']
    for x in range(15):lines.append(f'{x}:navigation_font=row_bits[{29-x*2}:{28-x*2}];\n')
    lines+=['default:navigation_font=0;endcase end endfunction\n']
    (ROOT/'rtl/ui_vector_engine/navigation_font.vh').write_text(''.join(lines))
    print('Native navigation font generated: body 11x16, heading 15x22')
if __name__=='__main__':main()
