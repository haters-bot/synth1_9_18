"""Capture diagnostic UART on the engineering PC and bring original logs back.

Example: python tools/capture_remote_trace.py --port COM6 --seconds 30 --label first_clicks
Requires diagnostic firmware already programmed. Does not program/reset the FPGA.
"""
import argparse
import base64
from datetime import datetime
import functools
import hashlib
from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
from pathlib import Path
import re
import threading
import zipfile

from deploy_verified import remote, LOCAL_IP, REMOTE_IP, ROOT
from touch_trace_monitor import TraceDecoder


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port',required=True)
    ap.add_argument('--seconds',type=int,default=30)
    ap.add_argument('--label',required=True)
    args=ap.parse_args()
    if not re.fullmatch(r'COM[0-9]+',args.port,re.I):ap.error('Use a verified engineering-PC COM port')
    if not 1<=args.seconds<=300:ap.error('--seconds must be 1..300')
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.label):ap.error('ASCII label only')
    run=datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+args.label
    out=ROOT/'impl'/'touch_logs'/run;out.mkdir(parents=True,exist_ok=False)
    rdir=f'D:/gaoyun_deploy/trace_{run}'
    with zipfile.ZipFile(out/'capture_tools.zip','x',zipfile.ZIP_DEFLATED) as z:
        for name in ['tools/touch_trace_monitor.py','rtl/ui_vector_engine/params.vh']:
            z.write(ROOT/name,name)
    server=HTTPServer((LOCAL_IP,8899),functools.partial(SimpleHTTPRequestHandler,directory=str(out)))
    worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
    manifest=dict(run=run,remote=REMOTE_IP,remote_dir=rdir,port=args.port,seconds=args.seconds,
                  firmware_requirement='ui_touch_hub_debug_top / trace protocol 1 / 115200 8N1')
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    try:
        remote(f"""
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(Test-Path -LiteralPath '{rdir}'){{throw 'Capture directory already exists'}}
New-Item -ItemType Directory -Path '{rdir}' | Out-Null
Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri 'http://{LOCAL_IP}:8899/capture_tools.zip' -OutFile '{rdir}/capture_tools.zip'
Expand-Archive -LiteralPath '{rdir}/capture_tools.zip' -DestinationPath '{rdir}'
""",60)
    finally:
        server.shutdown();server.server_close()
    command=f"python -u '{rdir}/tools/touch_trace_monitor.py' --port {args.port} --seconds {args.seconds} --output '{rdir}/capture.jsonl'"
    print(f'CAPTURE_START {args.port} {args.seconds}s\nRemote retained: {rdir}\nLocal: {out}',flush=True)
    # SSH streams the serial monitor directly to the terminal so users can see
    # each click live. UTF-8 is set explicitly for the Windows PowerShell host.
    import subprocess
    ps=f"[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();$ProgressPreference='SilentlyContinue';{command};exit $LASTEXITCODE"
    encoded=base64.b64encode(ps.encode('utf-16le')).decode()
    cmd=['ssh','-p','22','-b',LOCAL_IP,'-o','BatchMode=yes','-o','ConnectTimeout=10',
         '-o','ServerAliveInterval=10','-o','ServerAliveCountMax=3',
         f'Administrator@{REMOTE_IP}',f'powershell -NoProfile -EncodedCommand {encoded}']
    with (out/'console.log').open('x',encoding='utf-8') as console:
        proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        # The remote reader has its own bounded --seconds deadline. Remaining
        # SSH failures terminate through the keepalive settings above.
        for line in iter(proc.stdout.readline,b''):
            text=line.decode('utf-8',errors='replace').rstrip()
            print(text,flush=True);console.write(text+'\n');console.flush()
        code=proc.wait(timeout=10)
    # Return raw evidence even if the reader found zero valid records.
    for name in ['capture.bin','capture.jsonl']:
        result=remote(f"[Convert]::ToBase64String([IO.File]::ReadAllBytes('{rdir}/{name}'))",60)
        data=base64.b64decode(result.strip(),validate=True)
        with (out/name).open('xb') as f:f.write(data)
        manifest[name+'_sha256']=hashlib.sha256(data).hexdigest().upper()
    d=TraceDecoder();records=d.feed((out/'capture.bin').read_bytes())
    manifest.update(reader_exit=code,records=len(records),bad_frames=d.bad_frames,
                    skipped_bytes=d.skipped_bytes,trailing_bytes=len(d.buffer),
                    touch_records=sum('touch' in r['events'] for r in records),
                    sequence_gap_total=sum(r['sequence_gap'] for r in records),
                    board_dropped=max([r['dropped_records'] for r in records],default=0))
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(manifest,indent=2),flush=True)
    if code or not records:raise SystemExit('Capture incomplete; inspect preserved files')


if __name__=='__main__':
    import sys
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    main()
