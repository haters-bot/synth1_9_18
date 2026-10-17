# ==============================================================================
# Script: screen_camera_audit.py
# Description: Automated Camera Snapshot & Visual Clarity Audit Tool
#              Captures high-resolution frame from front camera or external webcam,
#              evaluates contrast/sharpness, and saves audit artifacts.
# Project: 2_ui_touch_hub (1280x720 Procedural Vector UI)
# ==============================================================================

import os
import sys
import subprocess
import time

FFMPEG_PATHS = [
    r"D:\SW\SOLIDWORKS\FloXpress\bin\ffmpeg.exe",
    r"D:\SW\SOLIDWORKS Flow Simulation\binCFW\ffmpeg.exe",
    "ffmpeg"
]

def find_ffmpeg():
    for p in FFMPEG_PATHS:
        if os.path.exists(p):
            return p
    return "ffmpeg"

def capture_screen_photo(output_path="screen_audit.jpg", camera_name="HD Camera"):
    ffmpeg = find_ffmpeg()
    cmd = [
        ffmpeg,
        "-f", "dshow",
        "-i", f"video={camera_name}",
        "-vframes", "1",
        "-y",
        output_path
    ]
    print(f"[INFO] Invoking camera capture: {camera_name} -> {output_path}")
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
            print(f"[SUCCESS] Captured photo ({os.path.getsize(output_path)} bytes) to {output_path}")
            return True
        else:
            print(f"[ERROR] Capture failed: {res.stderr.decode('utf-8', 'ignore')}")
            return False
    except Exception as e:
        print(f"[ERROR] Exception during capture: {e}")
        return False

if __name__ == "__main__":
    out_file = sys.argv[1] if len(sys.argv) > 1 else "screen_audit.jpg"
    success = capture_screen_photo(out_file)
    sys.exit(0 if success else 1)
