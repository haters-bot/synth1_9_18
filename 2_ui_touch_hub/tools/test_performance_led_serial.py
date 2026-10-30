"""Decode the actual WS2812 output waveform; no internal DUT state reference."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'impl' / ('performance_led_serial_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    ms = Path(os.environ.get('MODELSIM_BIN', 'D:/altera/modelsim_ase/win32aloem'))
    sources = [ROOT / 'rtl/performance/ws2812_driver.v', ROOT / 'sim/tb_ws2812_serial.v']
    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=120)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log)
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library', [ms / 'vlib.exe', 'work'])
    run('compile', [ms / 'vlog.exe', '-sv', *sources])
    log = run('simulation', [ms / 'vsim.exe', '-c', 'tb_ws2812_serial', '-do', 'run -all; quit -f'])
    if 'PASS:' not in log:
        raise RuntimeError(f'No PASS: {out}')
    (out / 'result.json').write_text(json.dumps({'passed': True,
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, Path(__file__)]}}, indent=2))
    print(next(line for line in log.splitlines() if 'PASS:' in line))
    print(out)


if __name__ == '__main__':
    main()
