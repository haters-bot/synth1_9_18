"""Compare oscillator pixels to deployed source and render real SD layers."""
from datetime import datetime
from pathlib import Path
import hashlib,json,re,subprocess,sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
REFERENCE='d963ff4e32d309182050ed018dfc3974355b6f5d'
sys.stdout.reconfigure(encoding='utf-8',errors='replace')

def main():
 out=Path('E:/gaoyun_builds')/('wavetable_pixels_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
 out.mkdir();print(out,flush=True)
 sources=[ROOT/'rtl/ui_vector_engine'/name for name in ['osc_panel_renderer.v','sine_table.v','audio_controls_renderer.v']]
 inputs=sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))+[Path(__file__),ROOT/'2_ui_touch_hub.gprj',ROOT/'tools/simulation_sources.py']
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
 for p in inputs:
  q=out/'src'/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes())
 sources=[out/'src'/p.relative_to(ROOT) for p in sources]
 for module in ['osc_panel_renderer']:
  data=subprocess.check_output(['git','show',REFERENCE+':2_ui_touch_hub/rtl/ui_vector_engine/'+module+'.v'],cwd=ROOT).decode('utf-8')
  for name in ['ui_top_renderer','osc_panel_renderer','audio_controls_renderer']:
   data=re.sub(r'\b'+name+r'\b',name+'_reference',data)
  ref=out/(module+'_reference.v');ref.write_text(data,encoding='utf-8');sources.append(ref)
 source=(out/'osc_panel_renderer_reference.v').read_text(encoding='utf-8')
 ports=source[source.index('module osc_panel_renderer_reference'):source.index(');')]
 live={'clk','rst_n'}
 values={'val_osca_power':"1'b1",'val_oscb_power':"1'b1",'val_osca_wave':'wave','val_oscb_wave':'wave',
         'wt_pos_a':'position','wt_pos_b':'position','in_x':'delayed_x','in_y':'delayed_y'}
 connections=[]
 for match in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)',ports):
  width,names=match.groups()
  for name in names.split('//')[0].rstrip(' ,\r').split(','):
   name=name.strip()
   if not name:continue
   count=1 if not width else int(width[1:].split(':')[0])-int(width[:-1].split(':')[1])+1
   value=name if name in live else values.get(name,f"{count}'d0")
   connections.append(f'.{name}({value})')
 outputs=['.out_hit_osca(hit_a)','.out_hit_oscb(hit_b)','.out_osca_rgb(rgb_a)','.out_oscb_rgb(rgb_b)',
          '.wt_index_a(bank_a)','.wt_index_b(bank_b)']
 refs=['.out_hit_osca(ref_hit_a)','.out_hit_oscb(ref_hit_b)','.out_osca_rgb(ref_rgb_a)','.out_oscb_rgb(ref_rgb_b)']
 tb=r'''`timescale 1ns/1ps
module tb_wavetable_preview_pixels;
 reg clk=0,rst_n=0;
 reg [13:0] in_x=0,in_y=0,delayed_x=0,delayed_y=0;
 reg [2:0] wave=0;reg [6:0] position=0,bank_a=0,bank_b=9;
 wire hit_a,hit_b,ref_hit_a,ref_hit_b,overlay_hit;
 wire [23:0] rgb_a,rgb_b,ref_rgb_a,ref_rgb_b,overlay_rgb;
 wire [23:0] rgb=overlay_hit ? overlay_rgb : hit_a ? rgb_a : hit_b ? rgb_b : 24'h101318;
 wire [237:0] extras={210'd0,bank_b,bank_a,14'd0};
 integer scenario,n,checks=0,warmup=0,fh,t,total;reg compare=0;
 always #10 clk=~clk;
 always @(posedge clk)begin delayed_x<=in_x;delayed_y<=in_y;end
 osc_panel_renderer dut(CONNECTIONS_NEW);
 osc_panel_renderer_reference golden(CONNECTIONS_OLD);
 audio_controls_renderer overlay(.clk(clk),.rst_n(rst_n),.in_x(in_x),.in_y(in_y),
  .extra_values(extras),.legacy_values(133'd0),.fx_page(3'd0),.warp_menu(2'd0),
  .wave_a(wave),.wave_b(wave),.sources(106'd0),.out_hit(overlay_hit),.out_rgb(overlay_rgb));
 always @(posedge clk)begin
  #1;
  if(compare && {hit_a,hit_b,rgb_a,rgb_b}!=={ref_hit_a,ref_hit_b,ref_rgb_a,ref_rgb_b})
   $fatal(1,"baseline oscillator pixel/latency differs at check %0d",checks);
  if(compare)checks=checks+1;
 end
 task select_bank(input [7:0] id,input [6:0] bank);begin
  @(negedge clk);if(id==8'hA2)bank_a=bank;else bank_b=bank;
  repeat(2000)@(negedge clk);
 end endtask
 task image(input [255:0] filename);begin
  compare=0;fh=$fopen(filename,"w");$fdisplay(fh,"P3\n808 148\n255");total=808*148;
  for(t=0;t<total+4;t=t+1)begin
   @(negedge clk);in_x=t<total ? 32+t%808 : 0;in_y=t<total ? 96+t/808 : 0;
   @(posedge clk);#2;
   if(t>=4)begin
    if(^rgb===1'bx)$fatal(1,"unknown SD preview pixel");
    $fdisplay(fh,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
   end
  end
  $fclose(fh);
 end endtask
 initial begin
  repeat(8)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
  for(scenario=0;scenario<8;scenario=scenario+1)begin
   compare=0;wave=scenario%4;position=(scenario*19)%128;repeat(20)@(negedge clk);compare=1;
   for(n=0;n<4096;n=n+1)begin
    @(negedge clk);in_x=(n*47)%1280;in_y=(n*31)%720;
   end
  end
  compare=0;wave=4;position=0;select_bank(8'hA2,0);select_bank(8'hA3,9);
  image("sd_00_09_position_000.ppm");
  position=127;repeat(2000)@(negedge clk);image("sd_00_09_position_127.ppm");
  position=64;select_bank(8'hA2,5);select_bank(8'hA3,3);image("sd_05_03_position_064.ppm");
  if(checks<32768)$fatal(1,"insufficient baseline comparisons");
  $display("PASS: %0d oscillator baseline RGB/hit/latency comparisons, four original waves and WT changes; three production OSC/overlay SD BANK/WT POSITION raster captures",checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"preview raster watchdog");end
endmodule
'''.replace('CONNECTIONS_NEW',','.join(connections+outputs)).replace('CONNECTIONS_OLD',','.join(connections+refs))
 bench=out/'tb_wavetable_preview_pixels.v';bench.write_text(tb,encoding='utf-8');sources.append(bench)
 def run(name,cmd):
  r=subprocess.run(list(map(str,cmd)),cwd=out,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
  log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
  if r.returncode or any(marker in log for marker in ['** Error:','** Fatal:','FATAL:']):raise RuntimeError(name+': '+str(out)+'\n'+log[-3500:])
  return log
 run('library',[MS/'vlib.exe','work'])
 run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(out/'src/rtl/ui_vector_engine'),*sources])
 log=run('simulation',[MS/'vsim.exe','-c','tb_wavetable_preview_pixels','-do','onerror {quit -code 1}; run -all; quit -f'])
 assert 'PASS:' in log
 images=[]
 for name in ['sd_00_09_position_000','sd_00_09_position_127','sd_05_03_position_064']:
  with Image.open(out/(name+'.ppm')) as im:
   assert im.size==(808,148);im.resize((1616,296)).save(out/(name+'.png'))
  images.append(str(out/(name+'.png')))
 assert len({hashlib.sha256((out/(name+'.ppm')).read_bytes()).hexdigest() for name in ['sd_00_09_position_000','sd_00_09_position_127','sd_05_03_position_064']})==3
 assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 (out/'result.json').write_text(json.dumps({'passed':True,'workspace_matches_snapshot':True,'source_sha256':hashes,'reference_commit':REFERENCE,'images':images,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
 print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)

if __name__=='__main__':main()
