"""Reference progress to Python's unbounded integer arithmetic for long songs."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'impl' / ('performance_progress_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    rng = random.Random(20261029)
    vectors = [(0, 0), (1, 0), (0, 1), (1, 1), (2, 1)]
    for duration in (65535, 65536, 70000, 300000, 3600000, 0x80000000, 0xffffffff):
        vectors.extend((elapsed, duration) for elapsed in (0, 1, duration // 2, duration - 1, duration, 0xffffffff))
    vectors.extend((rng.randrange(2**32), rng.randrange(2**32)) for _ in range(1000))
    checks = []
    for elapsed, duration in vectors:
        expected = 0 if duration == 0 else min(65535, elapsed * 65535 // duration)
        checks.append(f"check(32'd{elapsed},32'd{duration},16'd{expected});")
    tb = out / 'tb_progress.v'
    tb.write_text('''`timescale 1ns/1ps
module tb_progress;
reg clk=0,rst_n=0,refresh=0;reg [31:0] elapsed_ms=0,duration_ms=0;
wire [15:0] progress;wire busy;
performance_progress dut(.*);
always #10 clk=~clk;
task step;begin @(negedge clk);end endtask
task check;
input [31:0] elapsed,duration;input [15:0] expected;
integer clocks;
begin
 elapsed_ms=elapsed;duration_ms=duration;refresh=1;step;refresh=0;
 // Changing the input must not affect a division already in flight.
 elapsed_ms=32'hdeadbeef;duration_ms=0;
 clocks=0;while(busy && clocks<49)begin step;clocks=clocks+1;end
 if(busy || progress!==expected)
  $fatal(1,"Progress mismatch elapsed=%0d duration=%0d got=%0d expected=%0d",elapsed,duration,progress,expected);
end endtask
initial begin repeat(3)step;rst_n=1;step;
''' + '\n'.join(checks) + '''
elapsed_ms=123456;duration_ms=300000;refresh=1;step;refresh=0;repeat(4)step;
rst_n=0;step;if(busy || progress!==0)$fatal(1,"Reset did not cancel divider");
$display("PASS: 1047 exact progress references including long songs, max timestamp, input latching and mid-division reset");$finish;
end
initial begin #2000000;$fatal(1,"Progress timeout");end
endmodule
''')
    ms = Path(os.environ.get('MODELSIM_BIN', 'D:/altera/modelsim_ase/win32aloem'))
    source = ROOT / 'rtl/performance/performance_progress.v'
    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=120)
        log = p.stdout + p.stderr
        (out / f'{name}.log').write_text(log)
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library', [ms / 'vlib.exe', 'work'])
    run('compile', [ms / 'vlog.exe', '-sv', source, tb])
    log = run('simulation', [ms / 'vsim.exe', '-c', 'tb_progress', '-do', 'run -all; quit -f'])
    if 'PASS:' not in log:
        raise RuntimeError(f'No PASS: {out}')
    (out / 'result.json').write_text(json.dumps({'passed': True, 'vectors': len(vectors),
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, Path(__file__)]}}, indent=2))
    print(next(line for line in log.splitlines() if 'PASS:' in line))
    print(out)


if __name__ == '__main__':
    main()
