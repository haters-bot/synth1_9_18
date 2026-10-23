"""Run the current compact ENV/MIDI regression without remapping coordinates.

The authoritative testbench already contains independent compact geometry.
Applying the historical R15-to-R16 migration again halves gestures twice.
"""
from datetime import datetime
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
def main():
    out=ROOT/'impl'/('compact_env_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    tb=(ROOT/'sim/tb_curve_touch_editor.v').read_text()
    (out/'tb_curve_touch_editor.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as f:subprocess.run([str(a) for a in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=120)
    run([MS/'vlib.exe','work'],'vlib.log')
    files=['rtl/touch_intake/touch_event_router.v','rtl/touch_intake/curve_touch_editor.v','rtl/param_merger/param_merger.v','rtl/midi_uart_tx/midi_uart_tx.v']
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*[ROOT/p for p in files],out/'tb_curve_touch_editor.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_curve_touch_editor','-do','run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(f'Failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out)
if __name__=='__main__':main()
