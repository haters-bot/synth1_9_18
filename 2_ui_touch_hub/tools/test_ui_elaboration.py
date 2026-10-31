"""Normal/debug RTL hierarchy check using official primitive models and DDR stubs.
No synthesis, place/route, or hardware access. Never a DDR/timing acceptance test.
"""
from pathlib import Path
from datetime import datetime
import subprocess,hashlib,json,shutil
from simulation_sources import project_verilog_sources
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
PRIM=Path('D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/simlib/gw5a/prim_sim.v')
out=Path('E:/gaoyun_builds')/('ui_elaboration_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
projects=['2_ui_touch_hub.gprj','2_ui_touch_hub_debug.gprj']
sources=list(dict.fromkeys(p for project in projects for p in project_verilog_sources(ROOT,project)))
inputs=list(dict.fromkeys(sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))+[ROOT/p for p in projects]+[Path(__file__),ROOT/'tools/simulation_sources.py']))
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
for p in inputs:
 target=out/'src'/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())
for p in [ROOT/'rtl/touch_intake/usb_hid_host_rom.mem']:
 q=out/'src'/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes())
def run(name,args):
 r=subprocess.run(list(map(str,args)),cwd=out/'src',capture_output=True,text=True,errors='replace',timeout=180)
 log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log)
 if r.returncode or any(x in log for x in ['** Error:','** Fatal:','FATAL:']):raise RuntimeError(name+': '+str(out)+'\n'+log[-5000:])
run('library',[MS/'vlib.exe',out/'work'])
run('compile',[MS/'vlog.exe','-sv','-work',out/'work','+incdir+'+str(out/'src/rtl/ui_vector_engine'),PRIM,*[out/'src'/p.relative_to(ROOT) for p in sources]])
for top in ['ui_touch_hub_top','ui_touch_hub_debug_top']:
 run(top,[MS/'vsim.exe','-c','-lib',out/'work',top,'GSR','-do','onerror {quit -code 1}; run 0; quit -f'])
matches=all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(out/'result.json').write_text(json.dumps({'passed':True,'workspace_matches_snapshot':matches,'source_sha256':hashes,'primitive_sha256':hashlib.sha256(PRIM.read_bytes()).hexdigest(),'ddr_real_timing_tested':False},indent=2))
if not matches:raise RuntimeError('Workspace changed during elaboration')
print('PASS: normal/debug complete hierarchies elaborate with official primitives and DDR stubs; no synthesis or hardware. '+str(out))
