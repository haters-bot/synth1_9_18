"""Full-renderer piano-roll pixels, seven-clock alignment, and real RTL preview."""
from pathlib import Path
from datetime import datetime
import hashlib,json,re,subprocess,zlib,struct
from simulation_sources import project_verilog_sources
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
 out=Path('E:/gaoyun_builds')/('performance_roll_pixels_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
 out.mkdir();print(out,flush=True)
 sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')
 inputs=list(dict.fromkeys(sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))+[ROOT/'2_ui_touch_hub.gprj',Path(__file__),ROOT/'tools/simulation_sources.py']))
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
 for p in inputs:
  q=out/'src'/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes())
 text=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text()
 ports=text[text.index('module ui_top_renderer'):text.index(');')]
 live={'clk':'clk','rst_n':'rst_n','in_hsync':'hs','in_vsync':'vs','in_den':'den','in_pixel_x':'x','in_pixel_y':'y',
 'ui_touch_valid':'tv','ui_touch_down':'td','ui_touch_x':'tx','ui_touch_y':'ty',
 'performance_tick_1ms':'tick','performance_clear_events':'clear','performance_event_push':'push',
 'performance_event_time_ms':'stamp','performance_event_note':'note','performance_event_velocity':"7'd100",
 'performance_event_on':'note_on','performance_start':'start','performance_stop':'stop','performance_pause':'pause',
 'performance_base_note':"7'h35",'performance_calibration_state':"3'd2",'performance_mode':"2'd2",
 'performance_duration_ms':"32'd5000",'performance_gateway_up_in':"1'b1"}
 connections=[]
 for m in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)',ports):
  width,names=m.groups()
  for name in names.split('//')[0].rstrip(' ,\r').split(','):
   name=name.strip()
   if name:connections.append('.'+name+'('+live.get(name,"'0")+')')
 connections+=['.out_hsync(ohs)','.out_vsync(ovs)','.out_den(oden)','.out_pixel_data(rgb)']
 tb=r'''`timescale 1ns/1ps
module tb_performance_roll_pixels;
reg clk=0,rst_n=0,hs=0,vs=0,den=1,tv=0,td=0,tick=0,clear=0,push=0,note_on=0,start=0,stop=0,pause=0;
reg [13:0] x=0,y=0,tx=0,ty=0;
reg [31:0] stamp=0;reg [6:0] note=0;
wire ohs,ovs,oden;wire [23:0] rgb;
integer i,j,fd,checks=0;
always #10 clk=~clk;
ui_top_renderer #(.PERFORMANCE_MAX_EVENTS(64),.PERFORMANCE_RUNTIME_BASE(1)) dut(CONNECTIONS);
task step;begin @(negedge clk);end endtask
task load(input integer ms,key,on);begin
 stamp=ms;note=7'h35+key;note_on=on;push=1;step;push=0;step;
end endtask
task publish;integer n;begin
 n=0;while(dut.u_performance_roll.state!=11 && n<100000)begin step;n=n+1;end
 if(n==100000)$fatal(1,"full renderer roll builder stalled");
 vs=1;step;vs=0;repeat(10)step;
end endtask
function [23:0] color(input integer px,py);
 integer lane;reg edge_,black_;reg [31:0] mask,onsets;reg [23:0] shade;
 begin
 lane=px/40;edge_=(px%40)==0 || (px%40)==39;
 case((53+lane)%12)1,3,6,8,10:black_=1;default:black_=0;endcase
 color=edge_ ? 24'h1D3447 : black_ ? 24'h0B1420 : 24'h101F2B;
 if((py%32)==0)color=24'h213547;
 mask=0;onsets=0;
 if(py>=323 && py<=348)mask[0]=1; // 400--600 ms
 if(py==348)onsets[0]=1;
 if(py>=273 && py<=348)mask[7]=1; // chord, 400--1000 ms
 if(py==348)onsets[7]=1;
 if(py>=198 && py<=248)mask[12]=1; // 1200--1600 ms
 if(py==248)onsets[12]=1;
 if(lane<5)shade=24'hFF8D57;else if(lane<10)shade=24'hF0C85C;
 else if(lane<15)shade=24'h66DA9A;else if(lane<20)shade=24'h53DCE2;
 else if(lane<25)shade=24'h6B9EED;else if(lane<30)shade=24'hB388EF;else shade=24'hED85C6;
 if((px%40)>=4 && (px%40)<36 && mask[lane])color=onsets[lane] ? 24'hEAF9FF : shade;
 if(py>=397)color=24'h3F8897;
 end
endfunction
reg checking=0;reg [23:0] expected[0:6];reg [6:0] dh=0,dv=0,dd=0;
integer latency=0;
always @(posedge clk)begin
 if(checking)begin
  for(integer z=6;z>0;z=z-1)expected[z]=expected[z-1];
  expected[0]=den ? color(x,y) : 0;
  dh={dh[5:0],hs};dv={dv[5:0],vs};dd={dd[5:0],den};latency=latency+1;
  #1;
  if(latency>7)begin
   if(rgb!==expected[6] || {ohs,ovs,oden}!=={dh[6],dv[6],dd[6]})
    $fatal(1,"seven-clock pixel mismatch got=%h want=%h at check %0d",rgb,expected[6],checks);
   checks=checks+1;
  end
 end
end
task point(input integer px,py,input [23:0] want);begin
 x=px;y=py;repeat(12)step;
 if(rgb!==want)$fatal(1,"stationary pixel (%0d,%0d) got=%h want=%h",px,py,rgb,want);
end endtask
initial begin
 repeat(5)step;rst_n=1;repeat(10)step;
 tx=650;ty=20;td=1;tv=1;step;tv=0;step;td=0;tv=1;step;tv=0;
 vs=1;step;vs=0;repeat(15)step;
 if(dut.navigation_view!=2)$fatal(1,"real touch did not enter PERFORM");
 clear=1;step;clear=0;step;
 load(400,0,1);load(400,7,1);load(600,0,0);load(1000,7,0);
 load(1200,12,1);load(1600,12,0);load(5000,20,1);
 start=1;step;start=0;publish;
 point(20,348,24'hEAF9FF);point(20,330,24'hFF8D57);
 point(300,300,24'hF0C85C);point(500,220,24'h66DA9A);
 // Vary raw coordinates every clock across both body and onset edges.
 checking=1;
 for(i=0;i<5000;i=i+1)begin
  x=(i*197)%1280;y=192+(i*43)%208;hs=i[0];den=(i%5)!=0;step;
 end
 checking=0;den=1;hs=0;repeat(12)step;
 // Capture actual final compositor output, not a Python redraw.
 fd=$fopen("perform_rgb.bin","wb");
 for(j=0;j<720;j=j+8)for(i=0;i<1280;i=i+8)begin
  x=i;y=j;repeat(7)step;
  $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 $fclose(fd);
 stop=1;step;stop=0;repeat(12)step;
 point(20,330,24'h101F2B);
 $display("PASS: %0d full-compositor moving pixel/sync checks, onset/body/duration/chords, real page entry, score upload and stop; actual RGB frame captured",checks);
 $finish;
end
initial begin #200000000;$fatal(1,"roll pixels watchdog");end
endmodule
'''.replace('CONNECTIONS',','.join(connections))
 bench=out/'src/tb_performance_roll_pixels.v';bench.write_text(tb)
 def run(name,args):
  r=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=240)
  log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log)
  if r.returncode or any(t in log for t in ('** Error:','** Fatal:','FATAL:','FAIL:')):raise RuntimeError(name+': '+str(out)+'\n'+log[-5000:])
  return log
 run('library',[MS/'vlib.exe','work'])
 run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(out/'src/rtl/ui_vector_engine'),*[out/'src'/p.relative_to(ROOT) for p in sources],bench])
 log=run('simulation',[MS/'vsim.exe','-c','tb_performance_roll_pixels','-do','onerror {quit -code 1}; run -all; quit -f'])
 if 'PASS:' not in log:raise RuntimeError('missing PASS')
 sampled=(out/'perform_rgb.bin').read_bytes();assert len(sampled)==160*90*3
 # An 8-pixel sampling grid keeps a complete-compositor frame practical in
 # the vendor's small-design simulator. Do not call it a native-resolution
 # screenshot: only display geometry changed, and full-rate edge pixels have
 # independent exact checks above.
 raw=b''.join(b''.join(sampled[(r*160+c)*3:(r*160+c+1)*3]*8 for c in range(160))*8 for r in range(90))
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
 scan=b''.join(b'\0'+raw[r*1280*3:(r+1)*1280*3] for r in range(720))
 png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1280,720,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b'')
 (out/'perform.png').write_bytes(png)
 matches=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in hashes.items())
 (out/'result.json').write_text(json.dumps({'passed':True,'workspace_matches_snapshot':matches,'source_sha256':hashes,'frame':'perform.png','frame_sample_step':8,'generated_testbench_sha256':hashlib.sha256(bench.read_bytes()).hexdigest()},indent=2))
 assert matches
 print('\n'.join(l for l in log.splitlines() if 'PASS:' in l),flush=True)
if __name__=='__main__':main()
