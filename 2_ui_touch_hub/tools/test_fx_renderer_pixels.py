"""Compare optimized FX output pixels with the accepted 20d749e baseline."""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('fx_pixel_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    reference=subprocess.check_output(['git','show','20d749e:2_ui_touch_hub/rtl/ui_vector_engine/fx_strip_renderer.v'],cwd=ROOT).decode()
    reference=reference.replace('module fx_strip_renderer(', 'module fx_strip_renderer_reference(',1)
    (out/'reference.v').write_text(reference)
    def run(args,name,timeout=300):
        with (out/name).open('w') as log:
            subprocess.run([str(a) for a in args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=timeout)
    run([MS/'vlib.exe','work'],'vlib.log')
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
         ROOT/'rtl/ui_vector_engine/fx_strip_renderer.v',out/'reference.v',ROOT/'sim/tb_fx_renderer_pixels.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_fx_renderer_pixels','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'FX raster regression failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out,flush=True)

if __name__=='__main__':main()
