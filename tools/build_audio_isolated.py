"""Preserve audio inputs and run one signoff Gowin build in a fresh folder."""
from datetime import datetime
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
GOWIN=Path('D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

def main():
    live=subprocess.check_output(['powershell','-NoProfile','-Command',
        "@(Get-Process gw_sh -ErrorAction SilentlyContinue).Count"],text=True).strip()
    if live!='0':raise RuntimeError('Another Gowin process is running; do not build concurrently')
    out=ROOT/'impl'/('AUDIO_XY_build_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True);print(out,flush=True)
    project='synth1_9_18.gprj'
    paths=[project,'src/acid_wavetable_16x256.hex','ip/fir_decimator_8x/coeff_q17.txt']
    for item in ET.parse(ROOT/project).findall('.//File'):
        p=item.attrib['path']
        if (ROOT/p).is_file():paths.append(p)
        elif item.attrib.get('enable')=='1':raise FileNotFoundError(ROOT/p)
    manifest={}
    for name in dict.fromkeys(paths):
        dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/name,dest)
        manifest[name]=hashlib.sha256(dest.read_bytes()).hexdigest()
    tcl='''set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir synth1_9_18.gprj]
set_option -verilog_std sysv2017
set_option -top_module top
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -timing_driven 1
set_option -correct_hold_violation 1
set_option -place_option 3
set_option -route_option 2
# Each build uses a fresh source-only directory, with no incremental P&R data.
# Gowin 1.9.11.03 does not expose inc_place/inc_pnr as set_option switches.
run all
exit
'''
    (out/'build_audio.tcl').write_text(tcl,encoding='ascii')
    manifest['build_audio.tcl']=hashlib.sha256((out/'build_audio.tcl').read_bytes()).hexdigest()
    (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2))
    metadata=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        profile='Signoff',tool=str(GOWIN),project=project,started=datetime.now().isoformat())
    (out/'build_metadata.json').write_text(json.dumps(metadata,indent=2))
    with (out/'build.log').open('w',encoding='utf-8') as log:
        p=subprocess.Popen([str(GOWIN),'build_audio.tcl'],cwd=out,stdout=log,stderr=subprocess.STDOUT)
        state=dict(pid=p.pid,status='running',started=metadata['started'])
        (out/'build_process.json').write_text(json.dumps(state,indent=2))
        code=p.wait()
    state.update(status='exited',returncode=code,ended=datetime.now().isoformat())
    (out/'build_process.json').write_text(json.dumps(state,indent=2))
    print('GOWIN_EXIT='+str(code),flush=True)
    raise SystemExit(code)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--background',action='store_true',help='Launch outside the terminal job with a hidden WMI process')
    parser.add_argument('--launch-log',type=Path,help=argparse.SUPPRESS)
    args=parser.parse_args()
    if args.background:
        launch=ROOT/'impl'/('audio_launcher_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
        launch.mkdir(parents=True)
        log=launch/'supervisor.log'
        cmd=subprocess.list2cmdline([sys.executable,str(Path(__file__).resolve()),'--launch-log',str(log)])
        quote=lambda s:"'"+str(s).replace("'","''")+"'"
        ps=("$s=([wmiclass]'Win32_ProcessStartup').CreateInstance(); $s.ShowWindow=0; "
            "$r=([wmiclass]'Win32_Process').Create("+quote(cmd)+","+quote(ROOT)+",$s); "
            "$r | Select-Object ReturnValue,ProcessId | ConvertTo-Json -Compress")
        result=json.loads(subprocess.check_output(['powershell','-NoProfile','-Command',ps],text=True))
        if result['ReturnValue']!=0:raise RuntimeError(result)
        result.update(log=str(log),command=cmd)
        (launch/'launcher.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result,indent=2))
    else:
        if args.launch_log:
            stream=args.launch_log.open('x',encoding='utf-8',buffering=1)
            sys.stdout=sys.stderr=stream
        main()
