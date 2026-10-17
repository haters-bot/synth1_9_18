import os
import sys
import time
import zipfile
import base64
import subprocess

LOCAL_FS = r"D:\github\gaoyun\2_ui_touch_hub\impl\pnr\2_ui_touch_hub.fs"
LOCAL_ZIP = r"D:\github\gaoyun\2_ui_touch_hub\impl\pnr\2_ui_touch_hub.zip"
REMOTE_IP = "10.136.125.157"
LOCAL_IP = "10.136.125.235"
HTTP_PORT = 8899

def log(msg):
    print(f"[DEPLOY] {msg}", flush=True)

def run_remote_powershell(ps_code, timeout=180):
    b64_code = base64.b64encode(ps_code.encode("utf-16le")).decode("ascii")
    ssh_cmd = [
        "ssh",
        "-p", "22",
        "-b", LOCAL_IP,
        "-o", "ConnectTimeout=60",
        "-o", "ServerAliveInterval=10",
        "-o", "ServerAliveCountMax=5",
        "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=yes",
        f"Administrator@{REMOTE_IP}",
        f"powershell -NoProfile -EncodedCommand {b64_code}"
    ]
    for attempt in range(3):
        try:
            log(f"Running remote command (attempt {attempt+1}/3)...")
            res = subprocess.run(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
            if res.returncode == 0:
                return 0, res.stdout, res.stderr
            log(f"Attempt {attempt+1} failed with code {res.returncode}: {res.stderr.strip()[:100]}")
            time.sleep(3)
        except Exception as e:
            log(f"Attempt {attempt+1} exception: {e}")
            time.sleep(3)
    return res.returncode, res.stdout, res.stderr

def main():
    if not os.path.exists(LOCAL_FS):
        log(f"ERROR: Local bitstream {LOCAL_FS} not found!")
        sys.exit(1)

    local_fs_size = os.path.getsize(LOCAL_FS)
    log(f"Step 1: Compressing local bitstream ({local_fs_size:,} bytes)...")
    with zipfile.ZipFile(LOCAL_ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(LOCAL_FS, arcname="2_ui_touch_hub.fs")
    local_zip_size = os.path.getsize(LOCAL_ZIP)
    log(f"Compressed to {local_zip_size:,} bytes.")

    import threading
    from http.server import HTTPServer, SimpleHTTPRequestHandler
    
    class PnrZipHandler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=os.path.dirname(LOCAL_ZIP), **kwargs)
        def log_message(self, format, *args):
            pass

    httpd = HTTPServer((LOCAL_IP, HTTP_PORT), PnrZipHandler)
    srv_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    srv_thread.start()
    log(f"Started embedded HTTP server on {LOCAL_IP}:{HTTP_PORT}...")

    log(f"Step 2: Triggering remote download, extraction and programming...")
    ps_deploy = f"""
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path 'D:\\gaoyun_deploy' | Out-Null
Write-Host '[REMOTE] Downloading firmware from http://{LOCAL_IP}:{HTTP_PORT}/2_ui_touch_hub.zip...'
Invoke-WebRequest -Uri 'http://{LOCAL_IP}:{HTTP_PORT}/2_ui_touch_hub.zip' -OutFile 'D:\\gaoyun_deploy\\2_ui_touch_hub.zip' -UseBasicParsing
Write-Host '[REMOTE] Extracting package...'
Expand-Archive -Path 'D:\\gaoyun_deploy\\2_ui_touch_hub.zip' -DestinationPath 'D:\\gaoyun_deploy\\' -Force
$fs = Get-Item 'D:\\gaoyun_deploy\\2_ui_touch_hub.fs'
Write-Host "[REMOTE] Extracted bitstream: $($fs.Length) bytes, modified $($fs.LastWriteTime)"

Write-Host '[REMOTE] Programming FPGA SRAM with Gowin programmer CLI...'
& 'D:\\Gowin\\Gowin_V1.9.11.03_Education_x64\\Programmer\\bin\\programmer_cli.exe' --device GW5AST-138B --run 2 --fsFile 'D:\\gaoyun_deploy\\2_ui_touch_hub.fs'

Write-Host '[REMOTE] Waiting 2 seconds for video frame stabilization...'
Start-Sleep -Seconds 2

if (Test-Path 'D:\\gaoyun\\snap.py') {{
    Write-Host '[REMOTE] Running snap.py camera audit...'
    python D:\\gaoyun\\snap.py
}} else {{
    Write-Host '[REMOTE] Running snap_fast.py camera audit...'
    python D:\\gaoyun\\snap_fast.py
}}
"""
    code, stdout, stderr = run_remote_powershell(ps_deploy)
    print(stdout)
    if stderr:
        print("[STDERR]", stderr)

    if code != 0:
        log("Deployment failed!")
        sys.exit(1)

    log("Step 3: Fetching camera snapshot from remote machine...")
    from fetch_image import fetch_file
    fetch_file("D:\\gaoyun\\cam_0.jpg", "remote_screen_hud.jpg")
    fetch_file("D:\\gaoyun\\cam_screen_crop.png", "remote_screen_crop.png")
    log("All deployment and capture steps finished successfully!")

if __name__ == "__main__":
    main()
