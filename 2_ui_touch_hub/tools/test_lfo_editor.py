"""Run LFO/router integration and measured touch mapping regressions in ModelSim."""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT/'impl'/('lfo_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    out.mkdir(exist_ok=False)
    subprocess.run([str(MS/'vlib.exe'), 'work'], cwd=out, check=True, capture_output=True)
    sources = ['rtl/touch_intake/touch_event_router.v',
               'rtl/ui_vector_engine/lfo_editor_state.v',
               'sim/tb_lfo_editor.v', 'sim/tb_touch_coordinate_observer.v']
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MS/'vlog.exe'), '-sv',
                        '+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
                        *[str(ROOT/p) for p in sources]],
                       cwd=out, stdout=log, stderr=subprocess.STDOUT, check=True)
    for name in ['tb_lfo_editor', 'tb_touch_coordinate_observer']:
        subprocess.run([str(MS/'vsim.exe'), '-c', '-l', name+'.log', name,
                        '-do', 'run -all; quit -f'], cwd=out, capture_output=True, check=True)
        data = (out/(name+'.log')).read_text(errors='replace')
        if 'PASS:' not in data or '** Fatal:' in data or '** Error:' in data:
            raise RuntimeError(f'{name} failed; inspect {out}')
        print(next(line for line in data.splitlines() if 'PASS:' in line), flush=True)
    print(out, flush=True)


if __name__ == '__main__':
    main()
