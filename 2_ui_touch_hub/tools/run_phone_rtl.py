"""Small isolated ModelSim runner for HC-07 protocol and export regressions."""
from pathlib import Path
from datetime import datetime
import json
import hashlib
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(top, sources, inputs=None, timeout=180):
    output = ROOT / "impl" / (top + "_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    output.mkdir()
    for name, value in (inputs or {}).items():
        (output / name).write_text(value, encoding="utf-8")
    binary = Path(os.environ.get("MODELSIM_BIN", "D:/altera/modelsim_ase/win32aloem"))
    commands = [[str(binary / "vlib.exe"), "work"],
                [str(binary / "vlog.exe"), "-sv", "+incdir+" + str(ROOT / "rtl/ui_vector_engine"), *[str(ROOT / path) for path in sources]],
                [str(binary / "vsim.exe"), "-c", top, "-do", "onerror {quit -code 1}; run -all; quit -f"]]
    logs = []
    for index, command in enumerate(commands):
        result = subprocess.run(command, cwd=output, capture_output=True, text=True, errors="replace", timeout=timeout)
        log = result.stdout + result.stderr
        (output / f"step_{index}.log").write_text(log, encoding="utf-8")
        logs.append(log)
        if result.returncode or "** Error" in log or "** Fatal" in log:
            raise RuntimeError(f"RTL failure: {output}\n{log[-5000:]}")
    if "PASS:" not in logs[-1]:
        raise RuntimeError(f"No PASS: {output}")
    paths=[ROOT/path for path in sources]+[ROOT/"rtl/ui_vector_engine/performance_export_coeffs.vh",Path(__file__)]
    hashes={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    (output / "result.json").write_text(json.dumps({"passed": True, "top": top,"source_sha256":hashes},indent=2), encoding="utf-8")
    print(logs[-1][-1800:])
    print(output)
    return output


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2:])
