"""Render real RTL with synthetic PCM and verify new raster coverage alignment."""
from pathlib import Path
from datetime import datetime
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('spectral_preview_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    out.mkdir()
    print(out,flush=True)
    def run(name,args,timeout=300):
        with (out/(name+'.log')).open('w') as log:
            p=subprocess.run([str(x) for x in args],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        s=(out/(name+'.log')).read_text(errors='replace')
        if p.returncode or any(x in s for x in ('** Error:','** Fatal:','# FAIL:','# ERROR:')):
            raise RuntimeError(name+' failed: '+str(out))
        return s
    run('library',[MS/'vlib.exe','work'])
    sources=[ROOT/'rtl/audio'/p for p in ('audio_fft_tables.v','audio_fft_analyzer.v','audio_phase_plot.v')]
    sources += [ROOT/'rtl/ui_vector_engine/ui_navigation_renderer.v',ROOT/'sim/tb_audio_spectral_preview.v']
    run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources])
    log=run('simulation',[MS/'vsim.exe','-c','tb_audio_spectral_preview','-do','run -all; quit -f'],timeout=600)
    assert '# PASS: 921600' in log and '# PASS: 4096' in log
    for line in log.splitlines():
        if '# PASS:' in line:print(line,flush=True)
    assert (out/'frame.ppm').stat().st_size==2764816
    Image.open(out/'frame.ppm').save(out/'frame.png')
    print(out/'frame.png',flush=True)


if __name__=='__main__':main()
