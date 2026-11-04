"""Render the actual navigation layer, independent of the unchanged synth layers."""
from pathlib import Path
from datetime import datetime
import argparse
import subprocess
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
def main():
 parser=argparse.ArgumentParser(description='Render one or all navigation pages from RTL.')
 parser.add_argument('--page',choices=['visual','controls','display','inputs','about','menu'],
                     help='Render one page only; the default renders all six pages.')
 args=parser.parse_args()
 page_ids={'visual':1,'controls':2,'display':3,'inputs':4,'about':5,'menu':6}
 selected_page=page_ids.get(args.page,0)
 out=ROOT/'impl'/('navigation_preview_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
 tb=r'''`timescale 1ns/1ps
module tb_navigation_frame;
reg clk=0,rst_n=0;reg [13:0] x=0,y=0;reg [1:0] view=1;reg [7:0] settings_section_id=1;
wire hit;wire [23:0] rgb;
integer file,px,py,page,first_page,last_page,pixel_count;
always #10 clk=~clk;
ui_navigation_renderer dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.view(view),
 .settings_section_id(settings_section_id),.show_diagnostics(1'b0),.usb_connected(1'b1),.usb_error(1'b0),
 .macro_values({7'd64,7'd64,7'd64,7'd64}),.out_hit(hit),.out_rgb(rgb));
initial begin
 if(!$value$plusargs("PAGE=%d",page))page=0;
 if(page<1 || page>6)begin first_page=1;last_page=6;end
 else begin first_page=page;last_page=page;end
 pixel_count=0;
 repeat(8)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);
 for(page=first_page;page<=last_page;page=page+1)begin
  if(page==1)begin view=1;settings_section_id=1;file=$fopen("visual.ppm","wb");end
  else if(page<=5)begin view=2;settings_section_id=page-1;
   case(page)2:file=$fopen("system_controls.ppm","wb");3:file=$fopen("system_display.ppm","wb");
    4:file=$fopen("system_inputs.ppm","wb");default:file=$fopen("system_about.ppm","wb");endcase
  end else begin view=3;settings_section_id=1;file=$fopen("menu.ppm","wb");end
  $fwrite(file,"P6\n1280 720\n255\n");
  for(py=0;py<720;py=py+1)begin
   for(px=0;px<1285;px=px+1)begin
    @(negedge clk);x=px<1280 ? px : 1279;y=py;
    if(px>=5)begin
     if(!hit || (^rgb)===1'bx)$fatal(1,"Uncovered or unknown navigation pixel");
     $fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);pixel_count=pixel_count+1;
    end
   end
  end
  $fclose(file);$display("Rendered navigation artifact %0d",page);
 end
 $display("PASS: %0d complete known navigation pixels",pixel_count);$finish;
end
endmodule
'''
 (out/'tb_navigation_frame.v').write_text(tb)
 def run(args,name):
  with (out/name).open('w') as f:subprocess.run([str(a) for a in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=480)
 run([MS/'vlib.exe','work'],'vlib.log')
 run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),ROOT/'rtl/ui_vector_engine/ui_navigation_renderer.v','tb_navigation_frame.v'],'compile.log')
 sim_args=[MS/'vsim.exe','-c','-l','simulation.log','tb_navigation_frame']
 if selected_page:sim_args.append(f'+PAGE={selected_page}')
 sim_args+=['-do','run -all; quit -f']
 run(sim_args,'vsim.log')
 log=(out/'simulation.log').read_text(errors='replace')
 if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(str(out))
 from PIL import Image
 names=['visual','system_controls','system_display','system_inputs','system_about','menu']
 selected_names=[names[selected_page-1]] if selected_page else names
 for name in selected_names:
  with Image.open(out/(name+'.ppm')) as im:
   if im.size!=(1280,720):raise RuntimeError('Invalid dimensions')
   im.save(out/(name+'.png'))
 print(log[log.index('# Rendered'):]);print(out,flush=True)
if __name__=='__main__':main()
