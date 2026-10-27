"""Independent integer/float oracle for stereo RMS, dBFS, crest and correlation."""
from pathlib import Path
from datetime import datetime
import json
import math
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out = ROOT/'impl'/('metrics_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    rng = random.Random(8148)
    tone = [round(24000*math.sin(2*math.pi*8*n/1024)) for n in range(1024)]
    quarter = [round(24000*math.cos(2*math.pi*8*n/1024)) for n in range(1024)]
    zeros = [0]*1024
    frames = [([4096]*1024,[4096]*1024),([-32768]*1024,[-32768]*1024),
              (tone,tone),(tone,[-v for v in tone]),(tone,quarter),
              ([16000]*1024,[8000]*1024),(zeros,zeros),
              ([32767]+zeros[1:],[32767]+zeros[1:]),
              ([1,-1]*512,[1,-1]*512),(zeros,[16000]*1024),
              ([32767]*1024,[-32768]*1024),
              ([rng.randrange(-32768,32768) for _ in zeros],
               [rng.randrange(-32768,32768) for _ in zeros]),
              (zeros,zeros),(zeros,zeros),(zeros,zeros),(zeros,zeros)]
    (out/'metrics_input.hex').write_text(''.join(f'{l&65535:04x}{r&65535:04x}\n'
        for left,right in frames for l,r in zip(left,right)))
    def run(name,args):
        p = subprocess.run([str(x) for x in args],cwd=out,text=True,errors='replace',capture_output=True,timeout=90)
        log = p.stdout+p.stderr
        (out/(name+'.log')).write_text(log)
        assert p.returncode == 0 and not any(v in log for v in ('** Error:', '** Fatal:', '# FAIL:')), (out,log[-2000:])
        return log
    run('library',[MS/'vlib.exe','work'])
    run('compile',[MS/'vlog.exe','-sv',ROOT/'rtl/audio/audio_pcm_metrics.v',ROOT/'sim/tb_audio_pcm_metrics.v'])
    log = run('simulation',[MS/'vsim.exe','-c','tb_audio_pcm_metrics','-do','run -all; quit -f'])
    assert '# PASS:' in log,out
    rows = [list(map(int,line.split())) for line in (out/'metrics_output.txt').read_text().splitlines()]
    assert len(rows)==17,(len(rows),out)
    max_db_error = 0
    held = 0
    for row,(left,right) in zip(rows,frames):
        f,rl,rr,pl,pr,db,pdb,crest,corr,bal,cvalid,hold,clip = row
        el = math.isqrt(sum(x*x for x in left)//1024)
        er = math.isqrt(sum(x*x for x in right)//1024)
        epl,epr = max(map(abs,left)),max(map(abs,right))
        assert (rl,rr,pl,pr)==(el,er,epl,epr),(row,(el,er,epl,epr),out)
        cross = sum(l*r for l,r in zip(left,right))//1024
        ec = min(100,abs(cross)*100//(el*er)) if el*er else 0
        if cross<0: ec = -ec
        eb = abs(er-el)*100//(el+er) if el+er else 0
        if er<el: eb = -eb
        assert (corr,bal,cvalid)==(ec,eb,int(el>=8 and er>=8)),(row,(ec,eb),out)
        def db10(amplitude):
            return 200*math.log10(amplitude/32768) if amplitude else -960
        error = max(abs(db-db10(max(el,er))),abs(pdb-db10(max(epl,epr))))
        max_db_error = max(max_db_error,error)
        assert error<=3.2,(row,error,out)
        assert crest==(pdb-db if max(epl,epr) else 0),(row,out)
        held = max(held,epl,epr)
        assert hold==held,(row,held,out)
        if max(epl,epr)>=32752:assert clip==48,(row,out)
    (out/'result.json').write_text(json.dumps(dict(passed=True,frames=16,
        independent_samples=16384,max_db_error=max_db_error/10),indent=2))
    print(next(x for x in log.splitlines() if '# PASS:' in x),flush=True)
    print(f'PASS: independent RMS/peaks/correlation/balance/crest; maximum dBFS error {max_db_error/10:.3f} dB',flush=True)
    print(out,flush=True)

if __name__=='__main__':main()
