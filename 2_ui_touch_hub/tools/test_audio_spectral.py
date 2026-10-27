"""Validate measured phase pixels and FFT against independent floating DFT."""
from pathlib import Path
from datetime import datetime
import math
import subprocess
import json

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('spectral_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    samples=[]
    for frame in range(6):
        frame_samples=[]
        for n in range(1024):
            if frame==0:value=24000*math.sin(2*math.pi*8*n/1024)
            elif frame==1:value=18000*math.cos(2*math.pi*64*n/1024)
            elif frame==2:value=12000*(math.sin(2*math.pi*8*n/1024)+math.cos(2*math.pi*64*n/1024))
            elif frame==3:value=0
            elif frame==4:value=-32768
            else:value=1000*math.sin(2*math.pi*3*n/1024)
            frame_samples.append(round(value))
        samples.append(frame_samples)
    (out/'fft_input.hex').write_text(''.join(f'{v & 65535:04x}\n' for frame in samples for v in frame),encoding='ascii')
    def run(name,args):
        p=subprocess.run([str(x) for x in args],cwd=out,text=True,errors='replace',capture_output=True,timeout=180)
        log=p.stdout+p.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
        if p.returncode or any(x in log for x in ('** Error:','** Fatal:','# FAIL:','# ERROR:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library',[MS/'vlib.exe','work'])
    sources=[ROOT/'rtl/audio'/p for p in ('audio_fft_tables.v','audio_fft_analyzer.v','audio_phase_plot.v')]
    sources += [ROOT/'sim'/p for p in ('tb_audio_fft_analyzer.v','tb_audio_phase_plot.v')]
    run('compile',[MS/'vlog.exe','-sv',*sources])
    for top in ('tb_audio_fft_analyzer','tb_audio_phase_plot'):
        log=run(top,[MS/'vsim.exe','-c',top,'-do','run -all; quit -f'])
        assert '# PASS:' in log,(top,out)
        print(next(line for line in log.splitlines() if '# PASS:' in line),flush=True)
    measured={}
    for line in (out/'fft_bins.txt').read_text().splitlines():
        frame,k,r,i=map(int,line.split());measured[frame,k]=complex(r,i)
    maximum_error=0
    for frame,data in enumerate(samples):
        windowed=[v*round(32767*.5*(1-math.cos(2*math.pi*n/1024)))/32768 for n,v in enumerate(data)]
        expected=[]
        for k in range(513):
            angle=-2*math.pi*k/1024
            step=complex(math.cos(angle),math.sin(angle));phase=1+0j;total=0j
            for v in windowed:total+=v*phase;phase*=step
            golden=total/1024;actual=measured[frame,k]
            error=abs(actual-golden);maximum_error=max(maximum_error,error)
            assert error<18,(frame,k,actual,golden,error,out)
            expected.append(abs(golden))
        if frame in (0,1,5):
            peak=max(range(1,512),key=lambda k:abs(measured[frame,k]))
            assert peak=={0:8,1:64,5:3}[frame],(frame,peak)
        if frame==3:assert all(measured[frame,k]==0 for k in range(1024))
    edges=[1,2,3,4,5,6,7,8,9,10,12,14,16,19,22,26,31,37,44,52,62,74,88,104,124,148,176,208,248,296,352,420,512]
    levels_checked=0
    for line in (out/'fft_levels.txt').read_text().splitlines():
        frame,band,actual=map(int,line.split())
        peak=max(int(abs(measured[frame,k].real)+abs(measured[frame,k].imag)) for k in range(edges[band],edges[band+1]))
        if peak<16:expected_level=0
        else:
            exponent=peak.bit_length()-1
            code=4*exponent+((peak>>(exponent-2)) & 3)
            expected_level=min(63,((code-16)*7)>>2)
        assert actual==expected_level,(frame,band,actual,expected_level,out)
        levels_checked+=1
    assert levels_checked==192,(levels_checked,out)
    (out/'result.json').write_text(json.dumps({'passed':True,'frames':70,'dft_bins_checked':3078,'display_levels_checked':levels_checked,'maximum_complex_error_lsb':maximum_error},indent=2))
    print(f'PASS: 3078 FFT bins against floating DFT; maximum complex error {maximum_error:.3f} LSB',flush=True)
    print(f'PASS: {levels_checked} display levels against independent exponent/mantissa calculation',flush=True)
    print(out,flush=True)


if __name__=='__main__':main()
