"""Compare committed teammate DDR pin constraints with the live UI constraints.

This is a source-level conflict audit. It is not board identification, memory
capacity verification, IP compilation, bank assignment or timing signoff.
"""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
REF='d4338fb1509f724e686d84f7bbac45692632ea3b'
DDR='constraints/tang_mega_138k_ddr3_standalone.cst'


def git_bytes(path):
    return subprocess.run(['git','show',f'{REF}:{path}'],cwd=ROOT.parent,
                          check=True,capture_output=True).stdout


def locations(text):
    clean=re.sub(r'//[^\n]*','',text)
    return {port:[p.strip() for p in pins.split(',')]
            for port,pins in re.findall(r'IO_LOC\s+"([^"]+)"\s+([^;]+);',clean)}


def main():
    out=ROOT/'impl'/('performance_storage_pins_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    ui_path=ROOT/'constraints/ui_touch_hub.cst'
    ui=locations(ui_path.read_text())
    ddr_bytes=git_bytes(DDR)
    ddr={port:pins for port,pins in locations(ddr_bytes.decode()).items() if port.startswith('ddr_')}
    ui_by_pin={pin:port for port,pins in ui.items() for pin in pins}
    conflicts=[{'pin':pin,'ddr_port':port,'ui_port':ui_by_pin[pin]}
               for port,pins in ddr.items() for pin in pins if pin in ui_by_pin]
    (out/'teammate_ddr_reference.cst').write_bytes(ddr_bytes)
    ip_template=git_bytes('src/ddr3_memory_interface/ddr3_wavetable_ip_tmp.v')
    version=re.search(r'Tool Version: ([^\r\n]+)',ip_template.decode()).group(1)
    result={'pin_conflicts':conflicts,'no_source_pin_conflicts':not conflicts,
            'teammate_commit':REF,'teammate_constraint':DDR,'ddr_pin_locations':ddr,
            'teammate_ip_tool_version':version,
            'source_sha256':{str(ui_path):hashlib.sha256(ui_path.read_bytes()).hexdigest(),
                             f'{REF}:{DDR}':hashlib.sha256(ddr_bytes).hexdigest()},
            'board_identity_verified':False,'physical_memory_capacity_verified':False,
            'bank_voltage_assignment_verified':False,'ui_ddr_ip_compile_verified':False,
            'ui_timing_closed':False}
    (out/'result.json').write_text(json.dumps(result,indent=2))
    if conflicts:raise RuntimeError(f'DDR/UI pin conflicts: {out}')
    print(f'PASS: {len(ddr)} DDR port locations do not overlap live UI pin assignments; physical/IP/bank/timing checks still required')
    print(out)


if __name__=='__main__':main()
