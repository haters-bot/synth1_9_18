"""Decode the production renderer LED block without simulating unused pixels."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    path = ROOT / 'rtl/ui_vector_engine/ui_top_renderer.v'
    production = path.read_text(encoding='utf-8').split('    performance_led_white_mapper #(', 1)[1].split('    wire synth_touch_down=', 1)[0]
    production = '    performance_led_white_mapper #(' + production
    tb = r'''`timescale 1ns/1ps
module tb_performance_led_path;
localparam PERFORMANCE_KEY_COUNT=32,PERFORMANCE_LED_COUNT=24,PERFORMANCE_BASE_NOTE=60;
reg clk=0,rst_n=0,performance_page_active=0;
reg [31:0] performance_active_keys=0,performance_guide_keys=0;
wire [23:0] performance_led_active_keys,performance_led_guide_keys;
wire performance_led_data;
always #10 clk=~clk;
PRODUCTION
integer p,b,h,frames=0,bits=0;
reg [23:0] expected;
task step;begin @(posedge clk);#1;end endtask
task frame;
 input [23:0] active,guide;
 begin
  for(p=0;p<24;p=p+1)begin
   expected=active[p] ? 24'h14200A : guide[p] ? 24'h10070E : 24'd0;
   for(b=23;b>=0;b=b-1)begin
    wait(performance_led_data===1);h=0;
    while(performance_led_data===1)begin h=h+1;step;end
    if(h!==(expected[b] ? 40 : 20))$fatal(1,"direct frame=%0d LED=%0d bit=%0d",frames,p,b);
    bits=bits+1;
   end
  end
  // No extra prefix/trailer pixel may be emitted after the 576 data bits.
  while(!led_frame_done)begin
   if(performance_led_data!==0)$fatal(1,"frame has more than 24 pixels");step;
  end
  repeat(4)step;frames=frames+1;
 end
endtask
initial begin
 repeat(5)step;@(negedge clk);rst_n=1;frame(0,0);
 @(negedge clk);performance_page_active=1;performance_active_keys=1;frame(1,0);
 @(negedge clk);performance_active_keys=2;frame(0,0); // black C# receives no LED
 @(negedge clk);performance_guide_keys=4;frame(0,2); // D is second white LED
 @(negedge clk);performance_active_keys=5;frame(3,2); // active color wins overlap
 @(negedge clk);performance_page_active=0;frame(0,0);
 if(frames!=6 || bits!=3456)$fatal(1,"coverage");
 $display("PASS: production white mapper/frame builder/driver, six direct 24-pixel wire frames, first LED not shifted, black-key dark, guidance/active priority, unused dark and page-exit clear");
 $finish;
end
initial begin #10000000;$fatal(1,"LED path timeout");end
endmodule
'''.replace('PRODUCTION', production)
    out = ROOT / 'impl' / ('performance_led_path_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    (out / 'tb.v').write_text(tb, encoding='utf-8')
    sources = [ROOT / 'rtl/performance/performance_led_white_mapper.v', ROOT / 'rtl/performance/ws2812_driver.v']

    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=180)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', '# FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log

    run('library', [MS / 'vlib.exe', 'work'])
    run('compile', [MS / 'vlog.exe', '-sv', *sources, out / 'tb.v'])
    log = run('simulation', [MS / 'vsim.exe', '-c', 'tb_performance_led_path', '-do', 'run -all; quit -f'])
    assert '# PASS:' in log, out
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [path, *sources]}
    (out / 'result.json').write_text(json.dumps(dict(passed=True, source_sha256=hashes), indent=2))
    print(next(line for line in log.splitlines() if '# PASS:' in line))
    print(out)


if __name__ == '__main__':
    main()
