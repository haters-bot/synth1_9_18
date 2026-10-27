"""Verify serial waveform through the PC decoder, corruption recovery and project compilation."""
from datetime import datetime
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from touch_trace_monitor import TraceDecoder, format_record

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def run(cmd,out,filename):
    with (out/filename).open('w') as log:
        subprocess.run([str(v) for v in cmd],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)


def main():
    out=ROOT/'impl'/('trace_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(exist_ok=False)
    run([MS/'vlib.exe','work'],out,'vlib.log')
    paths=[e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub_debug.gprj').findall('.//File')
           if e.attrib['path'].endswith('.v')]
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
         *[ROOT/p for p in paths],ROOT/'sim/tb_touch_trace.v'],out,'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_touch_trace','-do','run -all; quit -f'],out,'vsim_stdout.log')
    data=(out/'simulation.log').read_text(errors='replace')
    assert 'PASS:' in data and not any(v in data for v in ['** Fatal:','** Error:']),out
    raw=bytes.fromhex((out/'trace_bytes.hex').read_text())
    (out/'trace.bin').write_bytes(raw)
    assert len(raw)%64==0
    d=TraceDecoder();records=[]
    # Deliberately fragmented reads, including single-byte magic prefixes.
    for i in range(0,len(raw),7):records.extend(d.feed(raw[i:i+7]))
    assert not d.buffer and not d.bad_frames and not d.skipped_bytes
    full=next(r for r in records if len(set(r['events']) & set(['touch','button','delta','parameter_request','curve','spi']))==6)
    assert full['touch']==dict(phase='DOWN',down=True,source='usb',raw_x=8192,raw_y=4800,x=640,y=360)
    assert full['button']['name']=='ENV_TAB' and full['button']['action']==1
    assert full['delta']==-4 and full['parameter_request']['value']==99
    assert full['curve']['values']==[10,0,40,90,111] and full['curve']['mask']==21
    assert full['panel_event']==dict(knob=5,action='CW') and full['context']['value']==1
    assert full['spi_link']==dict(chip=1,connected=True)
    assert any(r.get('touch',{}).get('phase')=='UP' for r in records)
    assert any('lfo' in r['events'] and r['lfo_snapshot']['tab']==2 for r in records)
    assert all('status' not in r['events'] or 'spi_link' in r for r in records)
    # Recovery after arbitrary noise, false magic, one corrupt frame and a partial tail.
    bad=bytearray(raw[:64]);bad[22]^=1
    d2=TraceDecoder()
    recovered=d2.feed(b'noise\x55'+bytes(bad)+raw[64:128]+raw[128:138])
    assert len(recovered)==1 and d2.bad_frames>=1 and len(d2.buffer)==10
    recovered+=d2.feed(raw[138:192])
    assert len(recovered)==2 and not d2.buffer
    print(next(v for v in data.splitlines() if 'PASS:' in v))
    print('PASS: complete debug/normal RTL compiled; host decoding, signed delta, local state, loss reporting, fragmentation and resync')
    print(format_record(full))
    print(out,flush=True)


if __name__=='__main__':main()
