"""Summarize an isolated Gowin build without treating an fs file as timing closure.

Writes a new timestamped JSON audit. No previous report or bitstream is changed.
"""
import argparse
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def rows(text):
    result=[]
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>',text,re.S|re.I):
        cells=re.findall(r'<t[dh][^>]*>(.*?)(?=</t[dh]>|<t[dh][ >]|$)',row,re.S|re.I)
        result.append([html.unescape(re.sub(r'<[^>]+>','',v)).strip() for v in cells])
    return result

def section(text,name):
    hit=re.search(r'<h2><a name="'+re.escape(name)+r'"[^>]*>.*?(?=<h2>|$)',text,re.S)
    return hit.group(0) if hit else ''

def inspect_build(build):
    """Read the current preserved evidence; do not trust a cached pass flag."""
    build=Path(build).resolve()
    pnr=build/'impl/pnr'
    manifest=json.loads((build/'source_manifest.json').read_text())
    timing=(pnr/'2_ui_touch_hub_tr_content.html').read_text(errors='replace')
    all_rows=rows(timing)
    summary={r[0]:r[1] for r in all_rows if len(r)==2}
    setup=int(summary['Numbers of Setup Violated Endpoints'])
    hold=int(summary['Numbers of Hold Violated Endpoints'])
    clocks=[]
    for r in rows(section(timing,'Max_Frequency_Report')):
        if len(r)>=6 and r[0].isdigit():
            clocks.append({'clock':r[1],'required_mhz':float(r[2].split('(')[0]),
                           'actual_mhz':float(r[3].split('(')[0]),'logic_levels':int(r[4])})
    paths=[]
    for block in re.split(r'<h3>Path\d+</h3>',timing)[1:]:
        first=block.split('</table>',1)[0]
        values={r[0]:r[1] for r in rows(first) if len(r)==2}
        if {'Slack','From','To'}<=values.keys() and float(values['Slack'])<0:
            paths.append({'slack_ns':float(values['Slack']),'from':values['From'],'to':values['To']})
    slack_tables={}
    for kind in ('Setup','Hold','Recovery','Removal'):
        match=re.search(r'<h3><a name="'+kind+r'_Slack_Table"[^>]*>.*?(?=<h3>|<h2>|$)',timing,re.S)
        values=[]
        serializer_endpoints=set()
        if match:
            for row in rows(match.group(0)):
                if len(row)>=2 and row[0].isdigit():
                    values.append(float(row[1]))
                    if len(row)>3 and 'tmds_serdes_inst0/RESET' in row[3]:
                        serializer_endpoints.add(row[3])
        slack_tables[kind.lower()]={'reported_paths':len(values),
                                    'worst_slack_ns':min(values) if values else None,
                                    'oser10_reset_endpoints':sorted(serializer_endpoints)}
    pulse=re.search(r'<h[23]><a name="MIN_PULSE_WIDTH_TABLE"[^>]*>.*?(?=<h3>|<h2>|$)',timing,re.S)
    pulse_values=[float(r[1]) for r in rows(pulse.group(0)) if len(r)>=2 and r[0].isdigit()] if pulse else []
    slack_tables['pulse_width']={'reported_paths':len(pulse_values),
                                 'worst_slack_ns':min(pulse_values) if pulse_values else None}
    fs=pnr/'2_ui_touch_hub.fs'
    mismatches=[p for p,d in manifest.items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=d]
    copy_mismatches=[p for p,d in manifest.items() if hashlib.sha256((build/p).read_bytes()).hexdigest()!=d]
    log=(build/'build.log').read_text(errors='replace')
    sdc_paths=[p for p in manifest if p.endswith('.sdc')]
    reset_exemptions=[]
    for name in sdc_paths:
        for line in (build/name).read_text().splitlines():
            if re.match(r'\s*set_false_path\b',line) and 'tmds_serdes_inst0/RESET' in line:
                reset_exemptions.append(line.strip())
    errors=[]
    if mismatches: errors.append('Workspace differs from preserved build inputs')
    if copy_mismatches: errors.append('Preserved build input hashes changed')
    if reset_exemptions: errors.append('OSER10 reset recovery/removal is exempted')
    if not {'clk_pixel','clk_usb','ch569_htclk'} <= {c['clock'] for c in clocks}:
        errors.append('Required clock reports are missing')
    if slack_tables['recovery']['reported_paths']==0:
        errors.append('No recovery paths reported; reset release is not proven')
    if slack_tables['removal']['reported_paths']==0:
        errors.append('No removal paths reported; reset release is not proven')
    if not pulse_values:
        errors.append('No minimum pulse-width paths reported')
    for kind in ('recovery','removal'):
        if len(slack_tables[kind]['oser10_reset_endpoints'])!=3:
            errors.append('Not all three OSER10 reset lanes are present in '+kind+' report')
    if any(s['worst_slack_ns'] is not None and s['worst_slack_ns']<0 for s in slack_tables.values()):
        errors.append('Negative setup/hold/recovery/removal slack')
    if re.search(r'ERROR\s*\(',log): errors.append('Gowin logged an error')
    complete='Bitstream generation completed' in log and fs.is_file() and fs.stat().st_size>0
    result={'time':datetime.now().isoformat(),'build':str(build),
            'current_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'input_files':len(manifest),'workspace_mismatches':mismatches,'snapshot_mismatches':copy_mismatches,
            'clocks':clocks,'setup_violated_endpoints':setup,'hold_violated_endpoints':hold,
            'negative_paths':paths,'fs_bytes':fs.stat().st_size if fs.exists() else None,
            'fs_sha256':hashlib.sha256(fs.read_bytes()).hexdigest().upper() if fs.exists() else None,
            'bitstream_complete':complete,'slack_tables':slack_tables,
            'oser10_reset_exemptions':reset_exemptions,'audit_errors':errors,
            'timing_closed':bool(clocks) and setup==0 and hold==0 and not paths and not errors
                            and complete and all(c['actual_mhz']>=c['required_mhz'] for c in clocks)}
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build',type=Path)
    args=parser.parse_args()
    build=args.build.resolve()
    result=inspect_build(build)
    output=build/('audit_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.json')
    with output.open('x') as stream:json.dump(result,stream,indent=2)
    print(json.dumps({k:v for k,v in result.items() if k!='negative_paths'},indent=2))
    print('Worst negative paths:',json.dumps(result['negative_paths'][:5],indent=2));print(output)

if __name__=='__main__':main()
