from __future__ import annotations

import shutil
import subprocess
import hashlib
import json
import os
from datetime import datetime
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    sources = [root / "rtl/performance/performance_event_scheduler.v",
               root / "sim/tb_performance_scheduler.v"]
    out = root / "impl" / ("performance_scheduler_tests_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    out.mkdir()
    modelsim = Path(os.environ.get("MODELSIM_BIN", "D:/altera/modelsim_ase/win32aloem"))
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")

    def run(label, command):
        result = subprocess.run(command, cwd=out, capture_output=True, text=True,
                                errors="replace", timeout=90)
        log = result.stdout + result.stderr
        (out / (label + ".log")).write_text(log, encoding="utf-8")
        if result.returncode or any(token in log for token in ("** Error:", "** Fatal:", "FATAL:", "FAIL:")):
            raise RuntimeError(f"{label} failed; see {out}")
        return log

    if (modelsim / "vsim.exe").exists():
        simulator = "ModelSim"
        run("library", [str(modelsim / "vlib.exe"), "work"])
        run("compile", [str(modelsim / "vlog.exe"), "-sv", "-work", "work", *map(str, sources)])
        for capacity in (5, 8, 1024, 4096, 16384):
            log = run(f"capacity_{capacity}", [str(modelsim / "vsim.exe"), "-c", "-lib", "work",
                      "tb_performance_scheduler", f"-gCAPACITY={capacity}", "-do", "run -all; quit -f"])
            if "PASS: performance scheduler" not in log:
                raise RuntimeError(f"capacity {capacity} did not pass; see {out}")
            print(next(line for line in log.splitlines() if "PASS:" in line))
    elif iverilog and vvp:
        simulator = "Icarus"
        for capacity in (5, 8, 1024, 4096, 16384):
            executable = out / f"capacity_{capacity}.out"
            run(f"compile_{capacity}", [iverilog, "-g2012", f"-Ptb_performance_scheduler.CAPACITY={capacity}",
                "-o", str(executable), *map(str, sources)])
            log = run(f"capacity_{capacity}", [vvp, str(executable)])
            if "PASS: performance scheduler" not in log:
                raise RuntimeError(f"capacity {capacity} did not pass; see {out}")
            print(log.strip())
    else:
        raise SystemExit("ModelSim or iverilog/vvp is required for the scheduler regression")
    (out / "result.json").write_text(json.dumps({"passed": True, "simulator": simulator,
        "capacities": [5, 8, 1024, 4096, 16384], "source_sha256": {
            str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}, indent=2))
    print(out)


if __name__ == "__main__":
    main()
