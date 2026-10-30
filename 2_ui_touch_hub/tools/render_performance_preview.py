"""Exercise the production renderer's LED path and save its full performance page."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import re
import subprocess
from PIL import Image
from simulation_sources import project_verilog_sources

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('performance_preview_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out,flush=True)
    source=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text()
    ports=source.split('module ui_top_renderer',1)[1].split(');',1)[0]
    live={'clk','rst_n','in_vsync','in_den','in_pixel_x','in_pixel_y',
          'ui_touch_valid','ui_touch_down','ui_touch_x','ui_touch_y',
          'performance_event_push','performance_event_note','performance_start','performance_stop','performance_pause',
          'performance_recording_in'}
    connections=[]
    for match in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=match.groups()
        bits=1 if not width else int(width[1:].split(':')[0])+1
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if not name:continue
            value=name if name in live else f"{bits}'d"+str({'performance_event_on':1,
                'performance_event_velocity':100,'performance_duration_ms':1000}.get(name,0))
            connections.append(f'.{name}({value})')
    connections+=['.performance_led_data(serial)','.out_pixel_data(rgb)','.out_den(den)']
    tb=r'''`timescale 1ns/1ps
module tb_performance_preview;
reg clk=0,rst_n=0,in_vsync=0,in_den=1;
reg [13:0] in_pixel_x=0,in_pixel_y=0,ui_touch_x=0,ui_touch_y=0;
reg ui_touch_valid=0,ui_touch_down=0;
reg performance_event_push=0;
wire performance_start,performance_stop,performance_pause,performance_recording_in;
reg [6:0] performance_event_note=64;
wire serial,den;wire [23:0] rgb;
wire local_play,local_pause,local_stop,local_record;
wire page_active;
integer p,b,h,frames=0,checks=0,file,x,y,plays=0,pauses=0,stops=0,records=0;
reg [23:0] expected;
// Store one scanline and write it in one formatted transaction.  A per-pixel
// $fwrite made the full 1280x720 production render exceed ModelSim's timeout;
// this keeps every pixel check while reducing file calls from 921600 to 720.
reg [1280*24-1:0] row_pixels;
always #10 clk=~clk;
ui_top_renderer dut(CONNECTIONS,.performance_page_active(page_active));
performance_touch_controls controls(.clk(clk),.rst_n(rst_n),.page_active(page_active),
 .touch_valid(ui_touch_valid),.touch_down(ui_touch_down),.touch_x(ui_touch_x),.touch_y(ui_touch_y),
 .play(local_play),.pause_toggle(local_pause),.stop(local_stop),.record_toggle(local_record));
performance_command_decoder commands(.clk(clk),.rst_n(rst_n),.tick_1ms(1'b0),
 .packet_valid(1'b0),.packet_type(8'd0),.packet_length(7'd0),.packet_payload(512'd0),
 .local_play(local_play),.local_pause_toggle(local_pause),.local_stop(local_stop),.local_record_toggle(local_record),
 .record_start_accepted(1'b0),.record_start_rejected(1'b0),.record_active(1'b0),.record_busy(1'b0),.record_done(1'b0),
 .start_pulse(performance_start),.stop_pulse(performance_stop),.pause_state(performance_pause),
 .recording(performance_recording_in));
always @(posedge clk)begin
 if(local_play)plays=plays+1;
 if(local_pause)pauses=pauses+1;
 if(local_stop)stops=stops+1;
 if(local_record)records=records+1;
end
task step;begin @(posedge clk);#1;end endtask
task packet;input integer px,py;input down;begin
 @(negedge clk);ui_touch_valid=1;ui_touch_down=down;ui_touch_x=px;ui_touch_y=py;
 @(negedge clk);ui_touch_valid=0;repeat(12)@(negedge clk);
end endtask
task page;input integer px;begin
 packet(px,22,1);packet(0,0,0);
 @(negedge clk);in_vsync=1;repeat(8)@(negedge clk);in_vsync=0;repeat(12)@(negedge clk);
end endtask
task button;input integer px;begin
 packet(px,152,1);packet(0,0,0);
 @(negedge clk);in_vsync=1;repeat(8)@(negedge clk);in_vsync=0;repeat(12)@(negedge clk);
 if(dut.navigation_view!=2)$fatal(1,"transport control navigated away");
end endtask
task receive;input [23:0] lit;begin
 for(p=0;p<24;p=p+1)begin
  expected=lit[p] ? 24'h14200A : 24'd0;
  for(b=23;b>=0;b=b-1)begin
   wait(serial===1);h=0;
   while(serial===1)begin h=h+1;step;end
   if(h!==(expected[b]?40:20))$fatal(1,"frame=%0d pixel=%0d bit=%0d pulse=%0d",frames,p,b,h);
   checks=checks+1;
  end
 end
 // Wait out the rest of the complete reset-low interval.
 repeat(15100)step;
 frames=frames+1;
end endtask
initial begin
 repeat(5)step;@(negedge clk);rst_n=1;
 receive(0); // mandatory startup clear, even with no note changes
 page(650);if(dut.navigation_view!=2)$fatal(1,"page entry");
 packet(20,600,1);receive(24'h1); // first white key
 packet(0,0,0);receive(0);
 @(negedge clk);performance_event_push=1;
 @(negedge clk);performance_event_push=0;
 fork button(80);receive(24'h4);join // MIDI64 = third white key
 button(150);if(!performance_pause)$fatal(1,"pause");
 button(150);if(performance_pause)$fatal(1,"resume");
 button(1040);if(!performance_recording_in)$fatal(1,"record request");
 button(1040);if(performance_recording_in)$fatal(1,"record stop request");
 // Whole raster through the actual seven-stage renderer.
 file=$fopen("performance.hex","w");
 for(y=0;y<720;y=y+1)begin
  @(negedge clk);in_pixel_x=0;in_pixel_y=y;repeat(9)@(negedge clk);
   row_pixels='0;
  for(x=0;x<1280;x=x+1)begin
   @(negedge clk);in_pixel_x=x+7<1280 ? x+7 : 1279;
   if((^rgb)===1'bx || !den)$fatal(1,"invalid raster at %0d,%0d",x,y);
    row_pixels[(1279-x)*24 +: 24]=rgb;
  end
   $fwrite(file,"%h\n",row_pixels);
 end
 $fclose(file);
 fork button(220);receive(0);join
 packet(20,600,1);receive(24'h1);
 fork page(440);receive(0);join // complete all-dark frame after page exit
 if(frames!=7 || checks!=4032 || plays!=1 || pauses!=2 || stops!=1 || records!=2)$fatal(1,"coverage");
 $display("PASS: production renderer, real control clicks preserve page, 7 decoded direct 24-pixel chains, startup dark/touch/release/MIDI64/stop/page-exit dark and 921600 valid output pixels");
 $finish;
end
initial begin #40000000;$fatal(1,"timeout");end
endmodule
'''.replace('CONNECTIONS',','.join(connections))
    tb_path=out/'tb_performance_preview.v'
    tb_path.write_text(tb)
    sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')+[tb_path]
    inputs=sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    def run(name,args):
        with (out/(name+'.log')).open('w') as log:
            process=subprocess.run(list(map(str,args)),cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=3600)
        log=(out/(name+'.log')).read_text(errors='replace')
        if process.returncode or any(t in log for t in ('** Error:','** Fatal:','FATAL:','FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library',[MS/'vlib.exe','work'])
    run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources])
    log=run('simulation',[MS/'vsim.exe','-c','tb_performance_preview','-do','run -all; quit -f'])
    if 'PASS:' not in log:raise RuntimeError(f'Missing PASS: {out}')
    rows=(out/'performance.hex').read_text().splitlines()
    if len(rows)!=720:raise RuntimeError('Incomplete raster rows')
    pixel_bytes=bytearray()
    for y,row in enumerate(rows):
        row=row.strip()
        if len(row)>1280*6:raise RuntimeError(f'Invalid raster row width at y={y}: {len(row)}')
        # Verilog %h may omit leading zeroes; those represent leading black
        # pixels in this MSB-first scanline and are restored here.
        pixel_bytes.extend(bytes.fromhex(row.zfill(1280*6)))
    if len(pixel_bytes)!=1280*720*3:raise RuntimeError('Incomplete raster payload')
    image=Image.frombytes('RGB',(1280,720),bytes(pixel_bytes))
    image.save(out/'performance.png')
    if not all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items()):
        raise RuntimeError('Source changed during simulation')
    (out/'result.json').write_text(json.dumps({'passed':True,'source_sha256':hashes},indent=2))
    print(next(line for line in log.splitlines() if 'PASS:' in line))
    print(out/'performance.png')


if __name__=='__main__':main()
