import subprocess
import base64
import os
import time

def fetch_file(remote_path, local_path):
    ps_cmd = f"$b = [IO.File]::ReadAllBytes('{remote_path}'); [Convert]::ToBase64String($b)"
    b64_script = base64.b64encode(ps_cmd.encode('utf-16le')).decode('ascii')
    cmd = [
        "ssh",
        "-b", "10.136.125.235",
        "-o", "ConnectTimeout=25",
        "-o", "StrictHostKeyChecking=no",
        "Administrator@10.136.125.157",
        f"powershell -NoProfile -EncodedCommand {b64_script}"
    ]
    for attempt in range(3):
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False, timeout=30, check=True)
            b64_str = b"".join(res.stdout.split())
            data = base64.b64decode(b64_str)
            with open(local_path, "wb") as f:
                f.write(data)
            print(f"Successfully fetched {remote_path} -> {local_path} ({len(data):,} bytes)", flush=True)
            return
        except Exception as e:
            print(f"Attempt {attempt+1} failed: {e}", flush=True)
            time.sleep(2)
    raise RuntimeError(f"Failed to fetch {remote_path} after 3 attempts")

if __name__ == "__main__":
    import time
    fetch_file("D:\\gaoyun\\cam_0.jpg", "remote_screen_hud.jpg")
    fetch_file("D:\\gaoyun\\cam_screen_crop.png", "remote_screen_crop.png")
