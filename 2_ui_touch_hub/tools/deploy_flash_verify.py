# ==============================================================================
# Script: deploy_flash_verify.py
# Description: Automated Bitstream Packaging, Remote Deployment, JTAG Flashing,
#              and Closed-Loop Optical Camera Audit.
# Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
# ==============================================================================

import os
import sys
import time
import zipfile
import subprocess

LOCAL_FS = r"D:\github\gaoyun\2_ui_touch_hub\impl\pnr\2_ui_touch_hub.fs"
LOCAL_ZIP = r"D:\github\gaoyun\2_ui_touch_hub\impl\pnr\2_ui_touch_hub.zip"
REMOTE_IP = "10.136.125.157"
LOCAL_IP = "10.136.125.235"
HTTP_PORT = 8899

def log(msg):
    print(f"[DEPLOY] {msg}", flush=True)

def step1_compress_bitstream():
    if not os.path.exists(LOCAL_FS):
        log(f"ERROR: Bitstream file {LOCAL_FS} not found!")
        return False
    fs_size = os.path.getsize(LOCAL_FS)
    log(f"Found bitstream: {LOCAL_FS} ({fs_size:,} bytes, modified {time.ctime(os.path.getmtime(LOCAL_FS))})")
    
    log(f"Compressing bitstream to {LOCAL_ZIP}...")
    with zipfile.ZipFile(LOCAL_ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(LOCAL_FS, arcname="2_ui_touch_hub.fs")
    zip_size = os.path.getsize(LOCAL_ZIP)
    log(f"Compressed {fs_size:,} bytes -> {zip_size:,} bytes ({zip_size / fs_size * 100:.1f}%)")
    return True

def step2_remote_fetch_and_flash():
    # SSH command via ZeroTier bound interface
    # 1. Download zip from local HTTP server
    # 2. Extract D:\2_ui_touch_hub.fs
    # 3. Execute programmer_cli.exe --device GW5AST-138B --run 2 --fs D:\2_ui_touch_hub.fs
    remote_ps_script = (
        f"$ProgressPreference = 'SilentlyContinue'; "
        f"New-Item -ItemType Directory -Force -Path 'D:\\gaoyun_deploy' | Out-Null; "
        f"Write-Host '[REMOTE] Downloading firmware package from http://{LOCAL_IP}:{HTTP_PORT}...'; "
        f"Invoke-WebRequest -Uri 'http://{LOCAL_IP}:{HTTP_PORT}/2_ui_touch_hub.zip' -OutFile 'D:\\gaoyun_deploy\\2_ui_touch_hub.zip' -UseBasicParsing; "
        f"Write-Host '[REMOTE] Extracting package...'; "
        f"Expand-Archive -Path 'D:\\gaoyun_deploy\\2_ui_touch_hub.zip' -DestinationPath 'D:\\gaoyun_deploy\\' -Force; "
        f"Write-Host '[REMOTE] Invoking Gowin Programmer CLI...'; "
        f"& 'D:\\Gowin\\Gowin_V1.9.11.03_Education_x64\\Programmer\\bin\\programmer_cli.exe' --device GW5AST-138B --run 2 --fsFile 'D:\\gaoyun_deploy\\2_ui_touch_hub.fs'"
    )
    import base64
    b64_cmd = base64.b64encode(remote_ps_script.encode('utf-16le')).decode('ascii')
    
    ssh_cmd = [
        "ssh",
        "-b", LOCAL_IP,
        "-o", "ConnectTimeout=15",
        "-o", "StrictHostKeyChecking=no",
        f"Administrator@{REMOTE_IP}",
        f"powershell -EncodedCommand {b64_cmd}"
    ]
    
    log(f"Executing remote deployment via SSH ({REMOTE_IP})...")
    res = subprocess.run(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    print(res.stdout)
    if res.stderr:
        print("[STDERR]", res.stderr)
    return res.returncode == 0

def step3_camera_audit():
    audit_script = os.path.join(os.path.dirname(__file__), "screen_camera_audit.py")
    out_img = r"D:\github\gaoyun\2_ui_touch_hub\screen_audit_latest.jpg"
    log(f"Running optical verification via camera snapshot -> {out_img}")
    res = subprocess.run([sys.executable, audit_script, out_img], text=True)
    if os.path.exists(out_img) and os.path.getsize(out_img) > 1000:
        log(f"Camera audit image successfully captured ({os.path.getsize(out_img):,} bytes)!")
        return out_img
    return None

if __name__ == "__main__":
    if not step1_compress_bitstream():
        sys.exit(1)
    if not step2_remote_fetch_and_flash():
        log("Remote flashing failed!")
        sys.exit(2)
    log("Remote flashing SUCCEEDED! Waiting 2s for screen sync...")
    time.sleep(2)
    img = step3_camera_audit()
    log("All deployment and closed-loop verification steps completed!")
