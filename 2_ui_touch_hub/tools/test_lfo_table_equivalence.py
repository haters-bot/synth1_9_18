"""Check bounded-width pipelining against the previously rendered curve math."""
from datetime import datetime
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('lfo_equivalence_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    source=subprocess.check_output(['git','show','f99d1cd:rtl/ui_vector_engine/lfo_smooth_table.v'],cwd=ROOT).decode()
    (out/'reference.v').write_text(source.replace('module lfo_smooth_table(', 'module lfo_smooth_table_reference(',1))
    def run(args,name):
        with (out/name).open('w') as log:
            subprocess.run([str(a) for a in args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
    run([MS/'vlib.exe','work'],'vlib.log')
    run([MS/'vlog.exe','-sv',ROOT/'rtl/ui_vector_engine/lfo_smooth_table.v',out/'reference.v',ROOT/'sim/tb_lfo_table_equivalence.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_lfo_table_equivalence','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(f'Curve equivalence failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out,flush=True)

if __name__=='__main__':main()
