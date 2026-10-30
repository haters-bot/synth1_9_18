"""Verify the backend-independent local PCM recorder; keep every simulation log."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'impl' / ('performance_pcm_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    ms = Path(os.environ.get('MODELSIM_BIN', 'D:/altera/modelsim_ase/win32aloem'))
    sources = [ROOT / 'rtl/performance/performance_pcm_capture.v', ROOT / 'sim/tb_performance_pcm_capture.v']
    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=120)
        log = p.stdout + p.stderr
        (out / f'{name}.log').write_text(log)
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library', [ms / 'vlib.exe', 'work'])
    chain_sources = [ROOT / 'rtl/audio/i2s_visual_rx.v', ROOT.parent / 'src/i2s_tx.v', ROOT / 'sim/tb_i2s_visual_loopback.v']
    run('compile', [ms / 'vlog.exe', '-sv', '+define+PCM_CAPTURE', *sources, *chain_sources])
    for depth in (3, 16):
        log = run(f'depth_{depth}', [ms / 'vsim.exe', '-c', 'tb_performance_pcm_capture', f'-gDEPTH={depth}', '-do', 'run -all; quit -f'])
        if 'PASS:' not in log:
            raise RuntimeError(f'No PASS: {out}')
        print(next(line for line in log.splitlines() if 'PASS:' in line))
    log = run('production_chain', [ms / 'vsim.exe', '-c', 'tb_i2s_visual_loopback', '-do', 'run -all; quit -f'])
    marker = 'PASS: production I2S transmitter -> independent-clock UI receiver -> PCM write stream'
    if marker not in log:
        raise RuntimeError(f'Chain has no PASS: {out}')
    print(next(line for line in log.splitlines() if marker in line))
    (out / 'result.json').write_text(json.dumps({'passed': True, 'depths': [3, 16], 'production_i2s_chain': True,
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, *chain_sources, Path(__file__)]}}, indent=2))
    print(out)


if __name__ == '__main__':
    main()
