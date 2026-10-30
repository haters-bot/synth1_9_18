from __future__ import annotations

import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    sources = [root / "rtl/performance/performance_command_decoder.v",
               root / "rtl/performance/performance_touch_controls.v",
               root / "sim/tb_performance_command_decoder.v"]
    out = root / "impl" / ("performance_command_tests_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    out.mkdir()
    modelsim = Path(os.environ.get("MODELSIM_BIN", "D:/altera/modelsim_ase/win32aloem"))
    iverilog, vvp = shutil.which("iverilog"), shutil.which("vvp")

    if (modelsim / "vsim.exe").exists():
        commands = [
            [str(modelsim / "vlib.exe"), "work"],
            [str(modelsim / "vlog.exe"), "-sv", "-work", "work", *map(str, sources)],
            [str(modelsim / "vsim.exe"), "-c", "-lib", "work", "tb_performance_command_decoder",
             "-do", "onerror {quit -code 1}; run -all; quit -f"],
        ]
    elif iverilog and vvp:
        executable = out / "command_decoder.out"
        commands = [[iverilog, "-g2012", "-o", str(executable), *map(str, sources)], [vvp, str(executable)]]
    else:
        raise SystemExit("ModelSim or iverilog/vvp is required")

    combined = []
    for index, command in enumerate(commands):
        result = subprocess.run(command, cwd=out, capture_output=True, text=True,
                                errors="replace", timeout=120)
        log = result.stdout + result.stderr
        (out / f"step_{index}.log").write_text(log, encoding="utf-8")
        combined.append(log)
        if result.returncode:
            raise RuntimeError(f"command decoder test failed; see {out}")
    output = "\n".join(combined)
    if "PASS: touchscreen hit regions" not in output:
        raise RuntimeError(f"command decoder test did not report PASS; see {out}")
    print(next(line for line in output.splitlines() if "PASS:" in line))
    print(out)


if __name__ == "__main__":
    main()
