"""Render actual RTL into an isolated directory with explicitly synthetic PCM."""
from datetime import datetime
from pathlib import Path
import json
import hashlib
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('audio_upgrade_preview_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out,flush=True)
    def run(name,args):
        # Native full-frame font/raster simulation can exceed three minutes.
        # Persist the transcript as it runs; a bounded long job can be polled.
        with (out/(name+'.log')).open('w') as target:
            p=subprocess.run([str(x) for x in args],cwd=out,text=True,errors='replace',stdout=target,stderr=subprocess.STDOUT,timeout=1800)
        log=(out/(name+'.log')).read_text(errors='replace')
        if p.returncode or any(x in log for x in ('** Error:','** Fatal:','# FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library',[MS/'vlib.exe','work'])
    sources=[ROOT/e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File') if e.attrib['path'].endswith('.v')]
    inputs=[*sources,ROOT/'sim/tb_audio_spectral_preview.v',*sorted((ROOT/'rtl/ui_vector_engine').glob('*.vh'))]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (out/'source_manifest.json').write_text(json.dumps(hashes,indent=2))
    run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources,ROOT/'sim/tb_audio_spectral_preview.v'])
    log=run('simulation',[MS/'vsim.exe','-c','tb_audio_spectral_preview','-do','run -all; quit -f'])
    assert '# PASS: 921600' in log,out
    Image.open(out/'frame.ppm').save(out/'preview.png')
    for line in log.splitlines():
        if '# PASS:' in line:print(line,flush=True)
    mismatches=[name for name,digest in hashes.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
    assert not mismatches,('Preview source changed while running',mismatches,out)
    (out/'result.json').write_text(json.dumps(dict(passed=True,source='RTL simulation; synthetic mono PCM, not hardware',input_files=len(hashes),workspace_mismatches=mismatches),indent=2))
    print(out/'preview.png',flush=True)

if __name__=='__main__':main()
