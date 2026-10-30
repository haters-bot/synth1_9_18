"""Exercise the song-storage transport against an independent delayed DDR model."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT=Path(__file__).resolve().parents[1]


def main():
    out=ROOT/'impl'/('performance_store_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    ms=Path(os.environ.get('MODELSIM_BIN','D:/altera/modelsim_ase/win32aloem'))
    sources=[ROOT/'rtl/performance/performance_async_fifo.v',ROOT/'rtl/performance/performance_pcm_store.v',
             ROOT/'sim/tb_performance_pcm_store.v']
    def run(name,args):
        p=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=180)
        log=p.stdout+p.stderr
        (out/f'{name}.log').write_text(log)
        if p.returncode or any(t in log for t in ('** Error:','** Fatal:','FATAL:','FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log
    run('library',[ms/'vlib.exe','work'])
    run('compile',[ms/'vlog.exe','-sv',*sources])
    ratios=[(10,7),(7,13)]
    for src,mem in ratios:
        log=run(f'clocks_{src}_{mem}',[ms/'vsim.exe','-c','tb_performance_pcm_store',f'-gSRC_HALF={src}',
                f'-gMEM_HALF={mem}','-do','run -all; quit -f'])
        if 'PASS:' not in log:raise RuntimeError(f'Missing PASS: {out}')
        print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)
    # Snapshot the exact teammate adapter for compatibility verification without
    # touching audio source files or relying on the older local working copy.
    ref='d4338fb1509f724e686d84f7bbac45692632ea3b'
    adapter=out/'teammate_ddr3_user_port_adapter.v'
    adapter.write_bytes(subprocess.run(['git','show',f'{ref}:src/ddr3_user_port_adapter.v'],
                       cwd=ROOT.parent,check=True,capture_output=True).stdout)
    chain_sources=[ROOT/'rtl/performance/performance_async_fifo.v',ROOT/'rtl/performance/performance_pcm_capture.v',
                   ROOT/'rtl/performance/performance_pcm_store.v',ROOT/'rtl/performance/performance_recording_subsystem.v',
                   ROOT/'rtl/performance/performance_command_decoder.v',ROOT/'rtl/performance/performance_record_status.v',
                   ROOT/'rtl/audio/i2s_visual_rx.v',
                   ROOT/'rtl/performance/performance_export_filter.v',ROOT/'rtl/performance/performance_audio_export.v',
                   ROOT/'sim/tb_performance_record_chain.v']
    run('compile_chain',[ms/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),adapter,*chain_sources])
    log=run('record_chain',[ms/'vsim.exe','-c','tb_performance_record_chain','-do','run -all; quit -f'])
    if 'PASS:' not in log:raise RuntimeError(f'Missing chain PASS: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)
    (out/'result.json').write_text(json.dumps({'passed':True,'clock_half_periods_ns':ratios,
        'teammate_adapter_commit':ref,'i2s_record_chain':True,
        'source_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,*chain_sources,adapter,Path(__file__)]}},indent=2))
    print(out)


if __name__=='__main__':main()
