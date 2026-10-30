"""Verify score-clock falling cues through the production renderer."""
from pathlib import Path
from datetime import datetime
import subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
def main():
 out=ROOT/'impl'/('performance_cue_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
 from simulation_sources import project_verilog_sources
 sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')+[ROOT/'sim/tb_performance_cue.v']
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 for label,args in [('library',[MS/'vlib.exe','work']),('compile',[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources]),('simulation',[MS/'vsim.exe','-c','tb_performance_cue','-do','run -all; quit -f'])]:
  result=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=120)
  log=result.stdout+result.stderr;(out/(label+'.log')).write_text(log)
  if result.returncode or any(t in log for t in ('** Error:','** Fatal:','FATAL:','FAIL:')):raise RuntimeError(f'{label} failed: {out}')
 if 'PASS:' not in log:raise RuntimeError(f'Missing PASS: {out}')
 assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 (out/'result.json').write_text(json.dumps({'passed':True,'source_sha256':hashes},indent=2))
 print(next(l for l in log.splitlines() if 'PASS:' in l));print(out)
if __name__=='__main__':main()
