"""Gowin uses a single active CST/SDC. Keep review fragments, build one CST."""
from pathlib import Path
import re


def combined_text(root: Path, debug: bool = False) -> str:
    name = 'ui_touch_hub_debug.cst' if debug else 'ui_touch_hub.cst'
    ui = (root / 'constraints' / name).read_text(encoding='utf-8')
    ddr = (root / 'constraints/ui_touch_hub_ddr.cst').read_text(encoding='utf-8')
    if debug:
        ddr = re.sub(r'(INS_LOC\s+")', r'\1u_hub/', ddr)
    return '// Generated from the UI and DDR review fragments. Do not edit.\n' + ui + '\n' + ddr


def write_combined(root: Path) -> None:
    for debug in (False, True):
        name = 'ui_touch_hub_debug_combined.cst' if debug else 'ui_touch_hub_combined.cst'
        target = root / 'constraints' / name
        target.write_text(combined_text(root, debug), encoding='utf-8', newline='\n')


if __name__ == '__main__':
    write_combined(Path(__file__).resolve().parents[1])
