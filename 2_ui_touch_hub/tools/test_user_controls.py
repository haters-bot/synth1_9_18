"""Regression for user settings, physical focus and absolute LFO previews."""
from datetime import datetime
from pathlib import Path
import json
import subprocess
import hashlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT / 'impl' / ('user_controls_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out, flush=True)
    benches = ['tb_user_controls', 'tb_focus_handoff', 'tb_modulation_values', 'tb_audio_stereo_meter']
    sources = [ROOT / f.attrib['path'] for f in ET.parse(ROOT / '2_ui_touch_hub.gprj').findall('.//File')
               if f.attrib['path'].endswith('.v')]
    sources += [ROOT / 'sim' / (name + '.v') for name in benches]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sources + list((ROOT / 'rtl/ui_vector_engine').glob('*.vh'))}

    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True,
                           text=True, errors='replace', timeout=240)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', '# FAIL:')):
            raise RuntimeError(f'{name} failed; {out}')
        return log

    run('library', [MS / 'vlib.exe', 'work'])
    run('compile', [MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'), *sources])
    for name in benches:
        log = run(name, [MS / 'vsim.exe', '-c', name, '-do', 'run -all; quit -f'])
        assert '# PASS:' in log, out / (name + '.log')
        print('\n'.join(line for line in log.splitlines() if '# PASS:' in line), flush=True)
    assert all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h for p, h in hashes.items())
    (out / 'result.json').write_text(json.dumps(dict(passed=True, source_sha256=hashes), indent=2))


if __name__ == '__main__':
    main()
