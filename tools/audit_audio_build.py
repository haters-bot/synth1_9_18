"""Re-read audio STA, source snapshots and bitstream before SRAM deployment."""
from datetime import datetime
from pathlib import Path
import argparse,hashlib,json,re,sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'2_ui_touch_hub/tools'))
from audit_build import rows,section

def inspect_build(build):
    build=Path(build).resolve();pnr=build/'impl/pnr';name='synth1_9_18'
    manifest=json.loads((build/'source_manifest.json').read_text())
    text=(pnr/(name+'_tr_content.html')).read_text(errors='replace')
    summary={r[0]:r[1] for r in rows(text) if len(r)==2}
    setup=int(summary['Numbers of Setup Violated Endpoints'])
    hold=int(summary['Numbers of Hold Violated Endpoints'])
    clocks=[]
    for r in rows(section(text,'Max_Frequency_Report')):
        if len(r)>=6 and r[0].isdigit():
            clocks.append(dict(clock=r[1],required_mhz=float(r[2].split('(')[0]),
                               actual_mhz=float(r[3].split('(')[0])))
    negative=[]
    for block in re.split(r'<h3>Path\d+</h3>',text)[1:]:
        d={r[0]:r[1] for r in rows(block.split('</table>',1)[0]) if len(r)==2}
        if {'Slack','From','To'}<=d.keys() and float(d['Slack'])<0:
            negative.append(dict(slack_ns=float(d['Slack']),source=d['From'],destination=d['To']))
    slacks={}
    for kind in ('Setup','Hold','Recovery','Removal'):
        m=re.search(r'<h3><a name="'+kind+r'_Slack_Table"[^>]*>.*?(?=<h3>|<h2>|$)',text,re.S)
        values=[float(r[1]) for r in rows(m[0]) if len(r)>=2 and r[0].isdigit()] if m else []
        slacks[kind.lower()]=dict(reported_paths=len(values),worst_slack_ns=min(values) if values else None)
    m=re.search(r'<h[23]><a name="MIN_PULSE_WIDTH_TABLE"[^>]*>.*?(?=<h3>|<h2>|$)',text,re.S)
    values=[float(r[1]) for r in rows(m[0]) if len(r)>=2 and r[0].isdigit()] if m else []
    slacks['pulse_width']=dict(reported_paths=len(values),worst_slack_ns=min(values) if values else None)
    snapshots=[];workspace=[]
    for path,h in manifest.items():
        if not (build/path).is_file() or hashlib.sha256((build/path).read_bytes()).hexdigest()!=h:snapshots.append(path)
        # The generated Tcl is part of the immutable build, not a source file.
        if path=='build_audio.tcl':continue
        if not (ROOT/path).is_file() or hashlib.sha256((ROOT/path).read_bytes()).hexdigest()!=h:workspace.append(path)
    fs=pnr/(name+'.fs');log=(build/'build.log').read_text(errors='replace')
    complete=fs.is_file() and fs.stat().st_size>0 and 'Bitstream generation completed' in log
    errors=[]
    if workspace:errors.append('Workspace source differs from build')
    if snapshots:errors.append('Snapshot hash mismatch')
    if not clocks:errors.append('Missing clock report')
    if not {'sys_clk','ddr_clk400','ddr_user_clk100'}<={c['clock'] for c in clocks}:errors.append('Required audio/DDR clock report missing')
    if not all(s['reported_paths'] and s['worst_slack_ns']>=0 for s in slacks.values()):errors.append('Five timing categories must all be reported and nonnegative')
    if re.search(r'ERROR\s*\(',log):errors.append('Gowin logged an error')
    return dict(time=datetime.now().isoformat(),build=str(build),input_files=len(manifest),
        clocks=clocks,setup_violated_endpoints=setup,hold_violated_endpoints=hold,
        negative_paths=negative,slack_tables=slacks,workspace_mismatches=workspace,snapshot_mismatches=snapshots,
        fs_sha256=hashlib.sha256(fs.read_bytes()).hexdigest().upper() if fs.is_file() else None,
        fs_bytes=fs.stat().st_size if fs.is_file() else None,bitstream_complete=complete,audit_errors=errors,
        timing_closed=complete and not errors and not negative and setup==0 and hold==0
            and all(c['actual_mhz']>=c['required_mhz'] for c in clocks))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('build',type=Path);a=p.parse_args()
    result=inspect_build(a.build)
    out=a.build/('audit_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.json')
    with out.open('x') as f:json.dump(result,f,indent=2)
    print(json.dumps(result,indent=2));print(out)
    if not result['timing_closed']:raise SystemExit(1)
if __name__=='__main__':main()
