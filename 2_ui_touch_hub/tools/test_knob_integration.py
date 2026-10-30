"""Run a pin-level TXE8148 burst slave, parameter merger and ASCII UART regression."""
from datetime import datetime
from simulation_sources import project_verilog_sources
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT / 'impl' / ('knob_integration_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out, flush=True)

    def run(args, name):
        result = subprocess.run([str(a) for a in args], cwd=out, capture_output=True,
                                text=True, timeout=120)
        (out / name).write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise RuntimeError(f'{name}: exit {result.returncode}; see {out}')
        return result.stdout + result.stderr

    run([MS / 'vlib.exe', 'work'], 'vlib.log')
    sources = project_verilog_sources(ROOT, '2_ui_touch_hub_debug.gprj')
    run([MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'),
         *sources, ROOT / 'sim/tb_knob_spi_burst.v', ROOT / 'sim/tb_knob_spi_rx.v',
         ROOT / 'sim/tb_knob_ascii_trace.v'], 'compile.log')
    # Both projects use the same source; the normal image must include C14 text.
    top = (ROOT / 'rtl/ui_touch_hub_top.v').read_text(encoding='utf-8')
    for bench in ['tb_knob_spi_burst', 'tb_knob_spi_rx', 'tb_knob_ascii_trace']:
        log = run([MS / 'vsim.exe', '-c', '-l', bench + '.log', bench,
                   '-do', 'onerror {quit -code 1}; run -all; quit -f'], bench + '_stdout.log')
        assert 'PASS:' in log and '** Fatal:' not in log and '** Error:' not in log, out / (bench + '.log')
        for line in log.splitlines():
            if 'PASS:' in line or 'COUNTS ' in line:
                print(line, flush=True)
    assert 'parameter DEBUG_KNOB_ASCII=1' in top, 'Normal firmware must enable C14 knob ASCII'
    print('PASS: normal/debug project sources compiled; normal C14 ASCII is enabled', flush=True)


if __name__ == '__main__':
    main()
