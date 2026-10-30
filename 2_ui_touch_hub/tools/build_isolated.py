"""Snapshot all project sources to a unique directory and run Gowin there.

Existing pnr output and verified snapshots are never overwritten. The build
manifest binds every copied source to its SHA256, including local edits.
"""
from pathlib import Path
from datetime import datetime
import hashlib,json,shutil,subprocess,xml.etree.ElementTree as ET
import argparse
from combined_constraints import combined_text
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--debug',action='store_true',help='Build the diagnostic top (U15/C14 trace) instead of normal MIDI firmware')
    args=parser.parse_args()
    project='2_ui_touch_hub_debug.gprj' if args.debug else '2_ui_touch_hub.gprj'
    tcl='build_debug.tcl' if args.debug else 'build.tcl'
    prefix='DEBUG_' if args.debug else ''
    # Gowin silently picks the last CST/SDC; reject ambiguous projects before
    # spending time building a design with auto-assigned peripheral pins.
    files=ET.parse(ROOT/project).findall('.//File')
    for kind in ('file.cst','file.sdc'):
        active=[e.attrib['path'] for e in files if e.attrib.get('type')==kind and e.attrib.get('enable','1')=='1']
        if len(active)!=1:raise RuntimeError(f'Expected exactly one active {kind}: {active}')
    cst=next(e.attrib['path'] for e in files if e.attrib.get('type')=='file.cst')
    if (ROOT/cst).read_text(encoding='utf-8')!=combined_text(ROOT,args.debug):
        raise RuntimeError('Combined CST is stale; run python tools/combined_constraints.py')
    out=ROOT/'impl'/(prefix+'R16A_build_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
    paths=[e.attrib['path'] for e in ET.parse(ROOT/project).findall('.//File')]
    paths += [project,tcl,'usb_hid_host_rom.mem']
    paths += ['constraints/ui_touch_hub_debug.cst' if args.debug else 'constraints/ui_touch_hub.cst',
              'constraints/ui_touch_hub_ddr.cst','tools/combined_constraints.py']
    paths += [str(p.relative_to(ROOT)) for p in (ROOT/'rtl/ui_vector_engine').glob('*.vh')]
    manifest={}
    for name in dict.fromkeys(paths):
        src=ROOT/name;dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest);manifest[name]=hashlib.sha256(src.read_bytes()).hexdigest()
    (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2))
    print(out,flush=True)
    with (out/'build.log').open('w') as log:
        process=subprocess.Popen(['D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe',tcl],cwd=out,stdout=log,stderr=subprocess.STDOUT)
        state={'pid':process.pid,'started':datetime.now().isoformat(),'status':'running'}
        (out/'build_process.json').write_text(json.dumps(state,indent=2))
        returncode=process.wait()
    state.update(status='exited',returncode=returncode,ended=datetime.now().isoformat())
    (out/'build_process.json').write_text(json.dumps(state,indent=2))
    print(f'GOWIN_EXIT={returncode}',flush=True)
    raise SystemExit(returncode)
if __name__=='__main__':main()
