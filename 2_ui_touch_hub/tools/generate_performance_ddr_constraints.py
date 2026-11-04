from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = "d4338fb1509f724e686d84f7bbac45692632ea3b"
SOURCE = "constraints/tang_mega_138k_ddr3_standalone.cst"
OUTPUT = ROOT / "constraints/ui_touch_hub_ddr.cst"


def main() -> None:
    if OUTPUT.exists():
        raise FileExistsError(f"Refusing to overwrite existing constraint file: {OUTPUT}")
    result = subprocess.run(["git", "show", f"{REFERENCE}:{SOURCE}"], cwd=ROOT.parent,
                            capture_output=True, check=True, text=True, encoding="utf-8")
    lines = [line for line in result.stdout.splitlines()
             if re.match(r"\s*(?:IO_(?:LOC|PORT)\s+\"ddr_|INS_LOC\s+)", line)]
    if not lines or not all("ddr_" in line or "u_ddr3_wrapper/" in line for line in lines):
        raise RuntimeError("Unexpected DDR constraint content")
    header = [
        "// DDR3 pins and dedicated PHY resources for the Tang Mega 138K UI board.",
        f"// Source: {REFERENCE}:{SOURCE}",
        "// Keep this separate from the UI peripheral constraints for review.",
        "",
    ]
    OUTPUT.write_text("\n".join(header + lines) + "\n", encoding="ascii", newline="\n")
    print(f"Wrote {len(lines)} DDR-only constraints to {OUTPUT}")


if __name__ == "__main__":
    main()
