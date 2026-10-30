"""Check all MIDI IDs, all 32 touches and physical white LEDs against note names."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'impl' / ('performance_keys_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    ms = Path(os.environ.get('MODELSIM_BIN', 'D:/altera/modelsim_ase/win32aloem'))
    # Independent note-name reference; include both frequency-table endpoints.
    names = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B')
    bases = [21, *range(48, 61), 77]
    blocks = []
    for base in bases:
        white = [i for i in range(32) if '#' not in names[(base + i) % 12]]
        led = {i: 1 << ordinal for ordinal, i in enumerate(white)}
        steps = []
        for note in range(128):
            key = note - base
            mask = 1 << key if 0 <= key < 32 else 0
            steps.append(f"event_note=7'd{note};event_on=1;event_valid=1;step;event_valid=0;step;check(32'h{mask:08x},24'h{led.get(key,0):06x});")
            steps.append("event_on=0;event_valid=1;step;event_valid=0;step;check(0,0);")
        for key in range(32):
            # Releasing scheduled guidance must preserve an overlapping touch.
            steps.append(f"manual_key=5'd{key};manual_down=1;manual_valid=1;event_note=7'd{base+key};event_on=1;event_valid=1;step;")
            steps.append(f"manual_valid=0;event_on=0;step;event_valid=0;step;check_manual(32'h{1<<key:08x},24'h{led.get(key,0):06x});")
            steps.append("manual_down=0;manual_valid=1;step;manual_valid=0;step;check(0,0);")
        for key in range(32):
            steps.append(f"manual_key=5'd{key};manual_down=1;manual_valid=1;remote_key=5'd{key};remote_down=1;remote_valid=1;event_note=7'd{base+key};event_on=1;event_valid=1;step;")
            steps.append(f"remote_valid=0;manual_down=0;event_on=0;step;manual_valid=0;event_valid=0;step;check_manual(32'h{1<<key:08x},24'h{led.get(key,0):06x});")
            steps.append("remote_down=0;remote_valid=1;step;remote_valid=0;step;check(0,0);")
        steps.append('manual_key=0;manual_down=1;manual_valid=1;event_note=7\'d' + str(base) + ';event_on=1;event_valid=1;step;')
        steps.append(f"manual_valid=0;clear_scheduled=1;step;event_valid=0;clear_scheduled=0;step;check_manual(32'h00000001,24'h{led.get(0,0):06x});")
        steps.append('manual_valid=1;manual_down=0;step;manual_valid=0;step;check(0,0);')
        blocks.append(f'''
module keys_{base}(output reg done=0);
reg clk=0,rst_n=0,event_valid=0,event_on=0,manual_valid=0,manual_down=0,clear_scheduled=0;
reg [6:0] event_note=0;reg [4:0] manual_key=0,remote_key=0;reg remote_valid=0,remote_down=0;
wire [31:0] active,guide;wire [23:0] led_active,led_guide;
always #10 clk=~clk;
performance_key_state #(.BASE_NOTE({base})) state_dut(
 .clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_on(event_on),.event_note(event_note),.clear_scheduled(clear_scheduled),
 .manual_valid(manual_valid),.manual_down(manual_down),.manual_key(manual_key),
 .remote_valid(remote_valid),.remote_down(remote_down),.remote_key(remote_key),.active_keys(active),.guide_keys(guide));
performance_led_white_mapper #(.BASE_NOTE({base})) led_dut(
 .active_keys(active),.guide_keys(guide),.led_active(led_active),.led_guide(led_guide));
task step;begin @(negedge clk);end endtask
task check;input [31:0] keys;input [23:0] leds;begin
 if(active!==keys || guide!==keys || led_active!==leds || led_guide!==leds)
  $fatal(1,"base={base} note=%0d key/LED mismatch: %h %h %h %h",event_note,active,guide,led_active,led_guide);
end endtask
task check_manual;input [31:0] keys;input [23:0] leds;begin
 if(active!==keys || guide!==0 || led_active!==leds || led_guide!==0)
  $fatal(1,"base={base} scheduled Off erased manual key");
end endtask
initial begin repeat(3)step;rst_n=1;step;
 {chr(10).join(steps)}
 rst_n=0;step;check(0,0);done=1;
end
endmodule
''')
    tb = out / 'tb_keys.v'
    tb.write_text('`timescale 1ns/1ps\n' + ''.join(blocks) +
                  f'module tb_keys; wire [{len(bases)-1}:0] done;\n' +
                  ''.join(f'keys_{base} b{i}(done[{i}]);\n' for i, base in enumerate(bases)) +
                  'initial begin wait(&done); $display("PASS: 15 base notes, 1920 MIDI IDs, 480 manual overlaps, 480 three-source overlaps, white-only LEDs and unused pixels dark");$finish;end\n'
                  'initial begin #1000000;$fatal(1,"Timeout");end endmodule\n')
    sources = [ROOT / 'rtl/performance/performance_key_state.v',
               ROOT / 'rtl/performance/performance_led_white_mapper.v']
    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=120)
        log = p.stdout + p.stderr
        (out / f'{name}.log').write_text(log)
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library', [ms / 'vlib.exe', 'work'])
    run('compile', [ms / 'vlog.exe', '-sv', *sources, tb])
    log = run('simulation', [ms / 'vsim.exe', '-c', 'tb_keys', '-do', 'run -all; quit -f'])
    if 'PASS:' not in log:
        raise RuntimeError(f'No PASS: {out}')
    (out / 'result.json').write_text(json.dumps({'passed': True, 'bases': bases,
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, Path(__file__)]}}, indent=2))
    print(next(line for line in log.splitlines() if 'PASS:' in line))
    print(out)


if __name__ == '__main__':
    main()
