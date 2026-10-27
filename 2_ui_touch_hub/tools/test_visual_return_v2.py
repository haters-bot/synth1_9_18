"""Verify real VIS V2 serial transport, independent taps and legacy fallback."""
from datetime import datetime
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('visual_return_v2_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir();print(out,flush=True)
    sources=[ROOT.parent/'src/i2s_visual_tx.v',ROOT.parent/'src/i2s_tx.v']
    sources += [ROOT/p for p in ('rtl/audio/i2s_visual_rx.v','rtl/audio/audio_phase_plot.v',
        'rtl/audio/audio_pcm_metrics.v','sim/tb_visual_return_v2.v')]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    def run(name,args):
        p=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=240)
        log=p.stdout+p.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
        assert p.returncode==0 and not any(x in log for x in ('** Error:','** Fatal:','# FAIL:')),out/(name+'.log')
        return log
    run('library',[MS/'vlib.exe','work'])
    run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*sources])
    log=run('simulation',[MS/'vsim.exe','-c','tb_visual_return_v2','-do','run -all; quit -f'])
    assert '# PASS:' in log,out
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'result.json').write_text(json.dumps(dict(passed=True,source_sha256=hashes),indent=2))
    print('\n'.join(s for s in log.splitlines() if '# PASS:' in s),flush=True)
if __name__=='__main__':main()
