"""Deploy SRAM firmware to the engineering PC with hashes and unique audit files.

Run from any directory: python tools/deploy_verified.py --label C1
No automatic programming retry: an SSH timeout may occur after hardware changed.
"""
import argparse
import base64
import functools
import hashlib
import json
from pathlib import Path
import re
import subprocess
import threading
from datetime import datetime
from http.server import HTTPServer, SimpleHTTPRequestHandler
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCAL_IP = "10.136.125.235"
REMOTE_IP = "10.136.125.157"


def remote(ps, timeout=180):
    encoded = base64.b64encode(ps.encode("utf-16le")).decode("ascii")
    result = subprocess.run(
        ["ssh", "-p", "22", "-b", LOCAL_IP, "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=10",
         "-o", "ServerAliveCountMax=3", f"Administrator@{REMOTE_IP}",
         f"powershell -NoProfile -EncodedCommand {encoded}"],
        capture_output=True, timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(result.stdout.decode(errors="replace") +
                           result.stderr.decode(errors="replace"))
    return result.stdout


def capture(remote_dir, output):
    # Source frames remain on the engineering PC; return a smaller preview and
    # the bottom telemetry strip to avoid transferring full camera frames.
    code = f"""
import cv2,base64
from pathlib import Path
p=Path({remote_dir!r})
c=cv2.VideoCapture(0,cv2.CAP_DSHOW)
assert c.isOpened(), 'Camera unavailable'
c.set(cv2.CAP_PROP_FRAME_WIDTH,1920)
c.set(cv2.CAP_PROP_FRAME_HEIGHT,1080)
for i in range(5): ok,f=c.read()
c.release()
assert ok and f is not None, 'No camera frame'
dest=p/'audit.jpg'
assert not dest.exists(), 'Audit already exists'
assert cv2.imwrite(str(dest),f)
for name,im in [('preview.jpg',cv2.resize(f,(960,540))),('telemetry.png',f[775:860,400:1820])]:
    ok,b=cv2.imencode('.'+name.split('.')[-1],im);assert ok
    print('CODEX_FILE:'+name+':'+base64.b64encode(b).decode())
"""
    payload = base64.b64encode(code.encode()).decode()
    data = remote(f"python -c \"import base64;exec(base64.b64decode('{payload}'))\"", 90)
    count = 0
    for line in data.splitlines():
        if line.startswith(b"CODEX_FILE:"):
            _, name, content = line.split(b":", 2)
            dest = output / name.decode("ascii")
            with dest.open("xb") as f:
                f.write(base64.b64decode(content, validate=True))
            count += 1
    if count != 2:
        raise RuntimeError("Camera did not return both audit images")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--fs", type=Path,
                        help="Deploy a preserved bitstream directly (default: current impl/pnr output)")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        parser.error("Use an ASCII label containing letters, digits, _ or -")
    run = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + args.label
    output = ROOT / "impl" / "deploy_runs" / run
    output.mkdir(parents=True, exist_ok=False)
    fs = args.fs.resolve() if args.fs else ROOT / "impl" / "pnr" / "2_ui_touch_hub.fs"
    digest = hashlib.sha256(fs.read_bytes()).hexdigest().upper()
    manifest = {"run": run, "source": str(fs), "sha256": digest,
                "bytes": fs.stat().st_size, "remote": REMOTE_IP}
    with (output / "firmware.zip").open("xb") as stream:
        with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(fs, "2_ui_touch_hub.fs")
    remote_dir = f"D:/gaoyun_deploy/{run}"
    manifest["remote_dir"] = remote_dir
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    server = HTTPServer((LOCAL_IP, 8899), functools.partial(
        SimpleHTTPRequestHandler, directory=str(output)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"[DEPLOY] {run} SHA256={digest}", flush=True)
    try:
        ps = f"""
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if (Test-Path -LiteralPath '{remote_dir}') {{ throw 'Deployment directory already exists' }}
New-Item -ItemType Directory -Path '{remote_dir}' | Out-Null
Invoke-WebRequest -Uri 'http://{LOCAL_IP}:8899/firmware.zip' -OutFile '{remote_dir}/firmware.zip' -UseBasicParsing -TimeoutSec 90
Expand-Archive -LiteralPath '{remote_dir}/firmware.zip' -DestinationPath '{remote_dir}'
$actual=(Get-FileHash -LiteralPath '{remote_dir}/2_ui_touch_hub.fs' -Algorithm SHA256).Hash
if ($actual -ne '{digest}') {{ throw "Bitstream hash mismatch: $actual" }}
Write-Output "VERIFIED_SHA256=$actual"
& 'D:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe' --device GW5AST-138B --run 2 --fsFile '{remote_dir}/2_ui_touch_hub.fs'
$programExit=$LASTEXITCODE
Write-Output "PROGRAMMER_EXIT=$programExit"
if ($programExit -ne 0) {{ exit $programExit }}
Start-Sleep -Seconds 2
Write-Output 'CODEX_PROGRAM_COMPLETE'
"""
        data = remote(ps, 240)
        (output / "programmer.log").write_bytes(data)
        print(data.decode(errors="replace"), flush=True)
        if b"CODEX_PROGRAM_COMPLETE" not in data:
            raise RuntimeError("Programming completion marker missing")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
    print(f"[DEPLOY] Programming verified; capturing to {output}", flush=True)
    capture(remote_dir, output)
    print(f"[DEPLOY] Audit files ready: {output}", flush=True)


if __name__ == "__main__":
    main()
