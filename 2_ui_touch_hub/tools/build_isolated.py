"""Snapshot all project sources to a unique directory and run Gowin there.

Existing pnr output and verified snapshots are never overwritten. The build
manifest binds every copied source to its SHA256, including local edits.
"""
from pathlib import Path
from datetime import datetime
import hashlib,json,shutil,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def main():
    out=ROOT/'impl'/('R16A_build_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
    paths=[e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File')]
    paths += ['2_ui_touch_hub.gprj','build.tcl','usb_hid_host_rom.mem']
    paths += [str(p.relative_to(ROOT)) for p in (ROOT/'rtl/ui_vector_engine').glob('*.vh')]
    manifest={}
    for name in dict.fromkeys(paths):
        src=ROOT/name;dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest);manifest[name]=hashlib.sha256(src.read_bytes()).hexdigest()
    (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2))
    print(out,flush=True)
    with (out/'build.log').open('w') as log:
        process=subprocess.Popen(['D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe','build.tcl'],cwd=out,stdout=log,stderr=subprocess.STDOUT)
        state={'pid':process.pid,'started':datetime.now().isoformat(),'status':'running'}
        (out/'build_process.json').write_text(json.dumps(state,indent=2))
        returncode=process.wait()
    state.update(status='exited',returncode=returncode,ended=datetime.now().isoformat())
    (out/'build_process.json').write_text(json.dumps(state,indent=2))
    print(f'GOWIN_EXIT={returncode}',flush=True)
    raise SystemExit(returncode)
if __name__=='__main__':main()
