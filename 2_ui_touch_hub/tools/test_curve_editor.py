"""Reproduce direct curve touch, parameter bank and UART integration checks."""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('curve_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    out.mkdir(exist_ok=False)
    subprocess.run([str(MS/'vlib.exe'),'work'],cwd=out,check=True,capture_output=True)
    sources=['rtl/touch_intake/touch_event_router.v','rtl/touch_intake/curve_touch_editor.v',
             'rtl/param_merger/param_merger.v','rtl/midi_uart_tx/midi_uart_tx.v',
             'rtl/ui_vector_engine/filter_panel_renderer.v','rtl/ui_vector_engine/env_panel_renderer.v',
             'sim/tb_curve_touch_editor.v','sim/tb_curve_geometry.v','sim/tb_param_merger.v']
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MS/'vlog.exe'),'-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
                        '+incdir+'+str(ROOT/'sim'),
                        *[str(ROOT/p) for p in sources]],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
    for name in ['tb_curve_touch_editor','tb_curve_geometry','tb_param_merger']:
        subprocess.run([str(MS/'vsim.exe'),'-c','-l',name+'.log',name,
                        '-do','run -all; quit -f'],cwd=out,capture_output=True,check=True)
        data=(out/(name+'.log')).read_text(errors='replace')
        if 'PASS' not in data or any(x in data for x in ['** Fatal:','** Error:','[FAIL]']):
            raise RuntimeError(f'{name} failed: inspect {out}')
        print('\n'.join(line for line in data.splitlines() if 'PASS' in line),flush=True)
    print(out,flush=True)

if __name__=='__main__': main()
