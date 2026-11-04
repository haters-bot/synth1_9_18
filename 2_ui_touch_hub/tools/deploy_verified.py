"""Deploy firmware to the engineering PC with hashes and unique audit files.

Run from any directory: python tools/deploy_verified.py --label C1
Use --target external-flash only when the board DIP settings are confirmed; this
erases and programs the external configuration flash, then verifies it.
No automatic programming retry: an SSH timeout may occur after hardware changed.
"""
import argparse
import base64
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys
import subprocess
import threading
from datetime import datetime
from http.server import HTTPServer, SimpleHTTPRequestHandler
import zipfile

ROOT = Path(__file__).resolve().parents[1]

# Campus IPv6 is the working path: ~4ms RTT and 10/10 connect success, versus
# ZeroTier relay at 400ms+ RTT with 65% loss. The ZeroTier addresses stay as an
# explicit fallback for networks without IPv6.
LOCAL_IP = os.environ.get("GAOYUN_LOCAL_IP", "240c:c283:4007:92f6:33dd:5a1d:ff72:c489")
REMOTE_IP = os.environ.get("GAOYUN_REMOTE_IP", "240c:c283:4007:9527:557c:f808:60e6:3b89")
IPV6 = ":" in REMOTE_IP


def ssh_host(ip):
    """Bracket a literal IPv6 address for ssh/scp/URL use."""
    return f"[{ip}]" if ":" in ip else ip


class IPv6HTTPServer(HTTPServer):
    address_family = socket.AF_INET6


class RemoteCommandError(RuntimeError):
    def __init__(self, result):
        self.stdout = result.stdout
        self.stderr = result.stderr
        self.returncode = result.returncode
        super().__init__(result.stdout.decode(errors="replace") +
                         result.stderr.decode(errors="replace"))


def remote(ps, timeout=180):
    # The script travels over stdin, so no caller-supplied text is ever part of
    # the remote command line. subprocess gets an argument list (shell=False).
    args = ["ssh", "-p", "22"]
    if IPV6:
        args.extend(["-6"])
    else:
        args.extend(["-b", LOCAL_IP])
    args.extend([
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
        "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
        "Administrator@" + ssh_host(REMOTE_IP),
        "powershell -NoProfile -NonInteractive -Command -",
    ])
    result = subprocess.run(args, input=ps.encode("utf-8"),
                            capture_output=True, timeout=timeout)
    if result.returncode:
        raise RemoteCommandError(result)
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
    parser.add_argument("--target", choices=("sram", "external-flash"), default="sram",
                        help="sram is volatile (default); external-flash erases, programs and verifies persistent flash")
    parser.add_argument("--board", choices=("ui", "audio"), default="ui",
                        help="Select the matching source/STA auditor and bitstream name")
    parser.add_argument("--check-only", action="store_true", help="Validate local sources, STA and hash without programming")
    args = parser.parse_args()
    if args.board=="audio" and (not args.fs or args.target!="sram"):
        parser.error("Audio deployment requires --fs and SRAM operation 2")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        parser.error("Use an ASCII label containing letters, digits, _ or -")
    run = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + args.label
    output = ROOT / "impl" / "deploy_runs" / run
    fs = args.fs.resolve() if args.fs else ROOT / "impl" / "pnr" / "2_ui_touch_hub.fs"
    digest = hashlib.sha256(fs.read_bytes()).hexdigest().upper()
    # Re-read STA and source hashes before any remote write. A historical
    # audit JSON or filename alone is not an authorization to deploy R16.
    build = fs.parents[2]
    audit = None
    if (build / 'source_manifest.json').is_file():
        if args.board=="audio":
            sys.path.insert(0,str(ROOT.parent/'tools'))
            from audit_audio_build import inspect_build
        else:
            from audit_build import inspect_build
        audit = inspect_build(build)
        if not audit['timing_closed'] or audit['fs_sha256'] != digest:
            raise RuntimeError('Build rejected before remote programming: '+
                               json.dumps(audit,ensure_ascii=True))
    else:
        raise RuntimeError('Deployment requires an isolated build with source_manifest.json')
    if args.check_only:
        print(json.dumps(dict(board=args.board,source=str(fs),sha256=digest,audit=audit),indent=2))
        return
    fs_name='synth1_9_18.fs' if args.board=='audio' else '2_ui_touch_hub.fs'
    output.mkdir(parents=True, exist_ok=False)
    operation = 2 if args.target == "sram" else 69
    manifest = {"run": run, "board": args.board, "target": args.target, "programmer_operation": operation,
                "source": str(fs), "sha256": digest,
                "bytes": fs.stat().st_size, "remote": REMOTE_IP,
                "programming_status": "not_confirmed"}
    if audit is not None:
        manifest['build_audit'] = audit
    with (output / "firmware.zip").open("xb") as stream:
        with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(fs, fs_name)
    remote_dir = f"D:/gaoyun_deploy/{run}"
    manifest["remote_dir"] = remote_dir
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    server_cls = IPv6HTTPServer if IPV6 else HTTPServer
    server = server_cls((LOCAL_IP, 8899), functools.partial(
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
Invoke-WebRequest -Uri 'http://{ssh_host(LOCAL_IP)}:8899/firmware.zip' -OutFile '{remote_dir}/firmware.zip' -UseBasicParsing -TimeoutSec 90
Expand-Archive -LiteralPath '{remote_dir}/firmware.zip' -DestinationPath '{remote_dir}'
$actual=(Get-FileHash -LiteralPath '{remote_dir}/{fs_name}' -Algorithm SHA256).Hash
if ($actual -ne '{digest}') {{ throw "Bitstream hash mismatch: $actual" }}
Write-Output "VERIFIED_SHA256=$actual"
& 'D:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe' --device GW5AST-138B --run {operation} --fsFile '{remote_dir}/{fs_name}' 2>&1 | Tee-Object -FilePath '{remote_dir}/programmer.log'
$programExit=$LASTEXITCODE
$programExit | Set-Content -LiteralPath '{remote_dir}/programmer_exit.txt'
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
        manifest["programming_status"] = (
            "flash_programmed_verified_power_cycle_pending"
            if args.target == "external-flash" else "sram_programmed"
        )
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    except Exception as error:
        # An SSH failure can occur after SRAM changed. Preserve available output
        # and leave the hardware outcome unconfirmed; never retry automatically.
        for attr in ("stdout", "stderr"):
            content = getattr(error, attr, None)
            if content:
                (output / ("remote_" + attr + ".log")).write_bytes(
                    content if isinstance(content, bytes) else content.encode("utf-8"))
        manifest["error"] = str(error)
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        raise
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
    if args.target == "external-flash":
        print(f"[DEPLOY] External flash erase/program/verify passed: {output}", flush=True)
        print("[DEPLOY] Power-cycle the board, then inspect the display to verify boot from flash.", flush=True)
        return
    if args.board=="audio":
        print(f"[DEPLOY] Audio SRAM programming verified: {output}",flush=True)
        return
    print(f"[DEPLOY] SRAM programming verified; capturing to {output}", flush=True)
    capture(remote_dir, output)
    print(f"[DEPLOY] Audit files ready: {output}", flush=True)


if __name__ == "__main__":
    main()
