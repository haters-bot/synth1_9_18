"""Render the changed production toolbar in each mode without the full synth."""
from pathlib import Path
from datetime import datetime
import hashlib,json,re,subprocess
from PIL import Image
from simulation_sources import project_verilog_sources
ROOT=Path(__file__).resolve().parents[1];MS=Path('D:/altera/modelsim_ase/win32aloem')
out=ROOT/'impl'/('performance_toolbar_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir();print(out,flush=True)
src=(ROOT/'rtl/ui_vector_engine/ui_navigation_renderer.v').read_text().split('module ui_navigation_renderer',1)[1].split(');',1)[0]
connections=[]
values={'clk':'clk','rst_n':'rst_n','in_x':'x','in_y':'y','view':"3'd2",'performance_mode':'mode'}
for m in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[[^\]]+\])?\s*([^\n]+)',src):
    for name in m.group(2).strip(' ,\r').split(','):
        name=name.strip()
        if name:connections.append(f".{name}({values.get(name, chr(39)+'0')})")
tb='''`timescale 1ns/1ps
module tb_toolbar;
reg clk=0,rst_n=0;reg [13:0] x=0,y=0;reg [1:0] mode=0;
wire [23:0] rgb;wire hit;integer file,m,py,px;reg [1280*24-1:0] row;
always #10 clk=~clk;
ui_navigation_renderer dut(CONNECTIONS,.out_rgb(rgb),.out_hit(hit));
initial begin
 repeat(8)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
 file=$fopen("toolbar.hex","w");
 for(m=0;m<3;m=m+1)begin mode=m;
  for(py=128;py<176;py=py+1)begin
   y=py;
   for(px=0;px<1284;px=px+1)begin
    @(negedge clk);x=px<1280?px:1279;
    @(posedge clk);#1;
    if(px>=4)begin
     if(!hit || (^rgb)===1'bx)$fatal(1,"invalid toolbar pixel");
     row[(1283-px)*24+:24]=rgb;
    end
   end
   $fwrite(file,"%h\\n",row);
  end
 end
 $fclose(file);$display("PASS: three production mode toolbars, 184320 output pixels");$finish;
end
endmodule
'''.replace('CONNECTIONS',','.join(connections))
bench=out/'tb_toolbar.v';bench.write_text(tb)
sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')+[bench]
inputs=sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
for i,args in enumerate([[MS/'vlib.exe','work'],[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources],
                        [MS/'vsim.exe','-c','tb_toolbar','-do','onerror {quit -code 1}; run -all; quit -f']]):
    r=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=150)
    log=r.stdout+r.stderr;(out/f'step_{i}.log').write_text(log)
    if r.returncode or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(log[-3000:])
assert 'PASS:' in log
rows=(out/'toolbar.hex').read_text().splitlines();assert len(rows)==144
pixels=bytes.fromhex(''.join(r.zfill(1280*6) for r in rows));im=Image.frombytes('RGB',(1280,144),pixels)
for m in range(3):
    for button in range(3):
        assert im.getpixel((304+button*176,m*48+10))==((36,107,104) if m==button else (37,68,85))
        area=im.crop((328+button*176,m*48+12,460+button*176,m*48+35))
        assert any(p not in [(36,107,104),(37,68,85)] for p in area.getdata()),'missing caption'
im.save(out/'toolbar_three_modes.png')
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(out/'result.json').write_text(json.dumps({'passed':True,'source_sha256':hashes},indent=2))
print('PASS: mode labels and selected backgrounds; '+str(out/'toolbar_three_modes.png'))
