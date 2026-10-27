"""Render the real settings RTL into reviewable PNGs, without operating hardware."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT / 'impl' / ('controls_preview_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out, flush=True)
    sources = [ROOT / f.attrib['path'] for f in ET.parse(ROOT / '2_ui_touch_hub.gprj').findall('.//File')
               if f.attrib['path'].endswith('.v')]
    sources.append(ROOT / 'sim/tb_controls_preview.v')
    inputs = sources + list((ROOT / 'rtl/ui_vector_engine').glob('*.vh'))
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}

    def run(name, args):
        with (out / (name + '.log')).open('w') as log:
            p = subprocess.run(list(map(str, args)), cwd=out, stdout=log,
                               stderr=subprocess.STDOUT, timeout=900)
        text = (out / (name + '.log')).read_text(errors='replace')
        if p.returncode or '** Fatal:' in text or '** Error:' in text:
            raise RuntimeError(f'{name} failed: {out}')
        return text

    run('library', [MS / 'vlib.exe', 'work'])
    run('compile', [MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'), *sources])
    log = run('simulation', [MS / 'vsim.exe', '-c', 'tb_controls_preview', '-do', 'run -all; quit -f'])
    assert '# PASS:' in log, out
    for name in ('controls_01_08', 'controls_25_32', 'display_scales'):
        with Image.open(out / (name + '.ppm')) as image:
            assert image.size == (1280, 720)
            image.save(out / (name + '.png'))
    assert all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h for p, h in hashes.items())
    (out / 'result.json').write_text(json.dumps(dict(passed=True, source_sha256=hashes), indent=2))
    print(next(line for line in log.splitlines() if '# PASS:' in line), flush=True)


if __name__ == '__main__':
    main()
