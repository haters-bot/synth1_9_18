from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path


DDR_VENDOR_FILENAMES = {
    "ddr3_pll_400m_ip.v",
    "ddr3_pll_400m_ip_mod.v",
    "ddr3_wavetable_ip.v",
}


def project_verilog_sources(root: Path, project_name: str) -> list[Path]:
    project = ET.parse(root / project_name).findall(".//File")
    paths = [root / entry.attrib["path"] for entry in project
             if entry.attrib["path"].endswith(".v") and
             Path(entry.attrib["path"]).name not in DDR_VENDOR_FILENAMES]
    paths.append(root / "sim/ddr3_vendor_ip_stubs.v")
    return paths
