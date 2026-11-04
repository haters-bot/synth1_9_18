"""Compile the real board project and run the new routing/control regression."""
from pathlib import Path
from datetime import datetime
from simulation_sources import project_verilog_sources
import subprocess
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
def main():
    out=ROOT/'impl'/('fx_lfo_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    def run(args,name):
        with (out/name).open('w') as f:
            subprocess.run([str(a) for a in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=120)
    run([MS/'vlib.exe','work'],'vlib.log')
    files=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*files,ROOT/'sim/tb_fx_lfo_routing.v',ROOT/'sim/tb_modulation_overlay.v',ROOT/'sim/tb_lfo_binding_release.v',ROOT/'sim/tb_binding_editor_handoff.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_fx_lfo_routing','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log: raise RuntimeError(f'Regression failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out,flush=True)
    run([MS/'vsim.exe','-c','-l','overlay_simulation.log','tb_modulation_overlay','-do','onerror {quit -code 1}; run -all; quit -f'],'overlay_vsim.log')
    log=(out/'overlay_simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log: raise RuntimeError(f'Overlay regression failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    run([MS/'vsim.exe','-c','-l','handoff_simulation.log','tb_binding_editor_handoff','-do','onerror {quit -code 1}; run -all; quit -f'],'handoff_vsim.log')
    log=(out/'handoff_simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log: raise RuntimeError(f'Editor handoff regression failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    run([MS/'vsim.exe','-c','-l','release_simulation.log','tb_lfo_binding_release','-do','onerror {quit -code 1}; run -all; quit -f'],'release_vsim.log')
    log=(out/'release_simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log: raise RuntimeError(f'Release regression failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x),flush=True)
if __name__=='__main__':main()
