"""Compile production RTL and run named six-fix benches, retaining all evidence."""
from pathlib import Path
from datetime import datetime
import hashlib, json, subprocess, sys
from simulation_sources import project_verilog_sources

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')

def main():
    names = sys.argv[1:]
    if not names or any(not n.startswith('tb_') or not n.replace('_', '').isalnum() for n in names):
        raise SystemExit('Usage: test_six_fix.py tb_name [tb_name ...]')
    out = ROOT/'impl'/('six_fix_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    sources = project_verilog_sources(ROOT, '2_ui_touch_hub.gprj') + [ROOT/'sim'/f'{n}.v' for n in names]
    # Compile an immutable snapshot; independent work must not rewrite inputs
    # underneath a running simulator. The final report also checks workspace.
    originals = sources + list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in originals}
    for p in originals:
        q = out/'src'/p.relative_to(ROOT)
        q.parent.mkdir(parents=True, exist_ok=True)
        q.write_bytes(p.read_bytes())
    sources = [out/'src'/p.relative_to(ROOT) for p in sources]
    print(out, flush=True)
    def run(label, args):
        r = subprocess.run(list(map(str,args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=240)
        log = r.stdout+r.stderr
        (out/f'{label}.log').write_text(log)
        if r.returncode or any(s in log for s in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:')):
            print(log[-9000:])
            raise RuntimeError(f'{label} failed: {out}')
        return log
    run('library', [MS/'vlib.exe', 'work'])
    run('compile', [MS/'vlog.exe', '-sv', '+incdir+'+str(out/'src/rtl/ui_vector_engine'), *sources])
    for name in names:
        log = run(name, [MS/'vsim.exe', '-c', name, '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        if 'PASS:' not in log:
            raise RuntimeError(f'Missing PASS: {name}: {out}')
        print('\n'.join(l for l in log.splitlines() if any(s in l for s in ('PASS:', 'UART:', 'CHECK:', 'TRACE:'))), flush=True)
    matches = all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'result.json').write_text(json.dumps({'passed':True, 'workspace_matches_snapshot':matches, 'tests':names, 'source_sha256':hashes}, indent=2))

if __name__ == '__main__':
    main()
