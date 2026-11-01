"""Real renderer touch/navigation and six simulated panel screenshots; no EDA."""
from pathlib import Path
from datetime import datetime
import hashlib,json,re,subprocess
from simulation_sources import project_verilog_sources
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
 out=Path('E:/gaoyun_builds')/('synth_preset_ui_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
 header=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text(encoding='utf-8').split('module ui_top_renderer',1)[1].split(');',1)[0]
 live={'clk','rst_n','ui_touch_valid','ui_touch_down','ui_touch_x','ui_touch_y','in_vsync','in_den','in_pixel_x','in_pixel_y','preset_active_index','preset_applied_valid'}
 ports=[]
 for m in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)',header):
  width,names=m.groups();bits=1 if not width else int(width[1:].split(':')[0])+1
  for name in names.split('//')[0].rstrip(' ,\r').split(','):
   name=name.strip()
   if name:ports.append(f'.{name}({name if name in live else str(bits)+chr(39)+"d0"})')
 ports.extend(['.preset_apply_req(request)','.preset_apply_index(index)','.out_pixel_data(rgb)'])
 tb='''`timescale 1ns/1ps
module tb_synth_preset_ui;
 reg clk=0,rst_n=0,ui_touch_valid=0,ui_touch_down=0,in_vsync=0,in_den=1,preset_applied_valid=0;
 reg [13:0] ui_touch_x=0,ui_touch_y=0,in_pixel_x=0,in_pixel_y=0;
 reg [3:0] preset_active_index=0;
 wire request;wire [3:0] index;wire [23:0] rgb;
 integer count=0;reg [3:0] last;
 always #5 clk=~clk;
 INSTANCE
 always @(posedge clk)if(request)begin count=count+1;last=index;preset_active_index<=index;preset_applied_valid<=1;end
 task frame;
  begin @(negedge clk);in_vsync=1;repeat(3)@(negedge clk);in_vsync=0;repeat(20)@(negedge clk);end
 endtask
 task tap;
  input [13:0] x,y;
  begin @(negedge clk);ui_touch_x=x;ui_touch_y=y;ui_touch_valid=1;ui_touch_down=1;
   @(negedge clk);ui_touch_valid=0;repeat(10)@(negedge clk);
   ui_touch_valid=1;ui_touch_down=0;@(negedge clk);ui_touch_valid=0;repeat(20)@(negedge clk);
  end
 endtask
 integer category,row,expected=0,before_count,n,j,choice;
 reg [23:0] expected_rgb[0:6];
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(30)@(negedge clk);
  tap(880,20);frame();
  if(dut.navigation_view!=3)$fatal(1,"FAIL: SYSTEM header navigation");
  tap(1080,100);
  if(dut.settings_section_id!=4)$fatal(1,"FAIL: PRESETS tab selection");
  for(category=0;category<6;category=category+1)begin
   tap(120,192+category*68);
   if(dut.preset_category!=category)$fatal(1,"FAIL: category touch target");
   for(row=0;row<(category==4?3:category==5?1:2);row=row+1)begin
    tap(480,224+row*128);
    if(last!=expected || count!=expected+1)$fatal(1,"FAIL: card %d request count=%d index=%d",expected,count,last);
    expected=expected+1;
   end
  end
  tap(360,628);if(count!=13 || last!=11)$fatal(1,"FAIL: full reapply button");
  before_count=count;tap(920,628);
  if(count!=before_count || !dut.preset_custom_notice)$fatal(1,"FAIL: custom reserve falsely applies a preset");
  // Independently specified solid colors on the NEW page, streamed every
  // clock. Seven-clock alignment is checked through the entire compositor.
  for(n=0;n<518;n=n+1)begin
   @(negedge clk);choice=(n*3)%7;
   for(j=6;j>0;j=j-1)expected_rgb[j]=expected_rgb[j-1];
   case(choice)
    0:begin in_pixel_x=400;in_pixel_y=290;expected_rgb[0]=24'h1D4D4E;end
    1:begin in_pixel_x=42;in_pixel_y=190;expected_rgb[0]=24'h1B3044;end
    2:begin in_pixel_x=42;in_pixel_y=530;expected_rgb[0]=24'h246B68;end
    3:begin in_pixel_x=300;in_pixel_y=640;expected_rgb[0]=24'h246B68;end
    4:begin in_pixel_x=802;in_pixel_y=650;expected_rgb[0]=24'h28313A;end
    5:begin in_pixel_x=710;in_pixel_y=620;expected_rgb[0]=24'h101820;end
    6:begin in_pixel_x=281;in_pixel_y=193;expected_rgb[0]=24'h52CCBB;end
   endcase
   @(posedge clk);#1;if(n>=6 && rgb!==expected_rgb[6])$fatal(1,"FAIL: preset seven-clock alignment at %0d got %h expected %h",n,rgb,expected_rgb[6]);
  end
  tap(550,628);
  if(dut.navigation_view!=3)$fatal(1,"FAIL: return switched outside VSYNC");
  frame();if(dut.navigation_view!=0)$fatal(1,"FAIL: return to synthesizer");
  $display("PASS: real ui_top_renderer SYSTEM navigation, six categories, all 12 cards, reapply, reserved custom, 512 seven-clock pixel checks and VSYNC return");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: preset UI timeout");end
endmodule
'''.replace('INSTANCE','ui_top_renderer #(.PRESET_ENABLE(1),.PERFORMANCE_MAX_EVENTS(64)) dut('+','.join(ports)+');')
 (out/'tb_synth_preset_ui.v').write_text(tb)
 panel='''`timescale 1ns/1ps
module tb_synth_preset_pixels;
 reg clk=0,rst_n=0;reg [13:0] x=0,y=0;
 reg [2:0] category=0;reg [3:0] active=0;
 wire hit;wire [23:0] rgb;
 always #5 clk=~clk;
 synth_preset_panel panel(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.visible(1'b1),.category(category),
  .active_index(active),.applied_valid(1'b1),.busy(1'b0),.pending(1'b0),.custom_notice(1'b0),.hit(hit),.rgb(rgb));
 integer c,p,file;reg [255:0] filename;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(c=0;c<6;c=c+1)begin
   category=c;active=c==5?11:c*2;
   $sformat(filename,"preset_panel_%0d.ppm",c);file=$fopen(filename,"wb");
   $fwrite(file,"P6\\n640 360\\n255\\n");
   for(p=0;p<230403;p=p+1)begin
    @(negedge clk);x=(p%640)*2;y=(p/640)*2;
    @(posedge clk);#1;
    if(p>=3)begin
     if(^rgb===1'bx)$fatal(1,"FAIL: unknown pixel");
     if(hit)$fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
     else $fwrite(file,"%c%c%c",8'h10,8'h18,8'h20);
    end
   end
   $fclose(file);
  end
  $display("PASS: six categories rendered from real four-stage RTL, 1382400 pixels");$finish;
 end
endmodule
'''
 (out/'tb_synth_preset_pixels.v').write_text(panel)
 sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')
 inputs=list(dict.fromkeys(sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))+[ROOT/'2_ui_touch_hub.gprj',Path(__file__)]))
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
 for p in inputs:
  q=out/'src'/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes())
 def run(label,args):
  r=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=240)
  log=r.stdout+r.stderr;(out/(label+'.log')).write_text(log)
  if r.returncode or any(x in log for x in ('** Error:','** Fatal:','FAIL:')):raise RuntimeError(str(out)+'\n'+log[-4000:])
  print('\n'.join(l for l in log.splitlines() if 'PASS:' in l),flush=True)
 run('library',[MS/'vlib.exe','work'])
 run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(out/'src/rtl/ui_vector_engine'),*[out/'src'/p.relative_to(ROOT) for p in sources],out/'tb_synth_preset_ui.v',out/'tb_synth_preset_pixels.v'])
 for bench in ('tb_synth_preset_ui','tb_synth_preset_pixels'):
  run(bench,[MS/'vsim.exe','-c',bench,'-do','onerror {quit -code 1}; run -all; quit -f'])
 from PIL import Image,ImageDraw
 montage=Image.new('RGB',(1280,1080),'#101820')
 for c in range(6):
  im=Image.open(out/f'preset_panel_{c}.ppm');assert im.size==(640,360)
  im.resize((1280,720),Image.Resampling.NEAREST).save(out/f'preset_panel_{c}.png')
  montage.paste(im,((c%2)*640,(c//2)*360))
 montage.save(out/'preset_panels.png')
 matches=all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 (out/'result.json').write_text(json.dumps({'passed':True,'workspace_matches_snapshot':matches,'source_sha256':hashes,'cards':12,'categories':6,'rendered_pixels':1382400,'synthesis_or_hardware':False},indent=2))
 assert matches
 print('PASS: UI and simulated panel screenshots retained: '+str(out))

if __name__=='__main__':main()
