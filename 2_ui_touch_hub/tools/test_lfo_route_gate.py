"""Compare touch-driven LFO route UART bytes in RTL and Gowin's official .vo.

--build explicitly builds a simulation-only isolated probe, never the UI image.
The probe has automatic pins and accelerated UART/timers: NEVER deploy its .fs.
--netlist-dir reuses an existing probe and its frozen source files without EDA.
"""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')
GOWIN = Path('D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE')
FILES = {
    'touch_event_router.v': 'rtl/touch_intake/touch_event_router.v',
    'lfo_binding_state.v': 'rtl/ui_vector_engine/lfo_binding_state.v',
    'lfo_sysex_tx.v': 'rtl/midi_uart_tx/lfo_sysex_tx.v',
    'midi_uart_tx.v': 'rtl/midi_uart_tx/midi_uart_tx.v',
    'params.vh': 'rtl/ui_vector_engine/params.vh',
    'mod_targets.vh': 'rtl/ui_vector_engine/mod_targets.vh',
    'lfo_route_probe.v': 'sim/lfo_route_probe.v',
    'tb_lfo_route_probe.v': 'sim/tb_lfo_route_probe.v',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build', action='store_true')
    mode.add_argument('--netlist-dir', type=Path)
    parser.add_argument('--rates', action='store_true', help='Use the touch-driven editor/rate probe')
    parser.add_argument('--testbench', type=Path, help='Explicit bench override when checking an existing .vo')
    parser.add_argument('--output-root', type=Path, default=Path('E:/gaoyun_builds'))
    args = parser.parse_args()
    if args.rates:
        FILES.pop('lfo_binding_state.v')
        FILES['lfo_editor_state.v'] = 'rtl/ui_vector_engine/lfo_editor_state.v'
        FILES['lfo_route_probe.v'] = 'sim/lfo_rate_probe.v'
        FILES['tb_lfo_route_probe.v'] = 'sim/tb_lfo_rate_uart.v'
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    args.output_root.mkdir(parents=True, exist_ok=True)
    out = args.output_root / ('lfo_route_gate_test_' + stamp)
    out.mkdir()
    print(out, flush=True)

    def run(label, command, cwd=out, timeout=240):
        print('START: ' + label, flush=True)
        try:
            result = subprocess.run(list(map(str, command)), cwd=cwd,
                                    capture_output=True, text=True, errors='replace', timeout=timeout)
            log = result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            def decode(value):
                return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
            log = decode(error.stdout) + decode(error.stderr)
            (out / (label + '.log')).write_text(log, encoding='utf-8')
            raise RuntimeError(label + ': timed out; evidence retained') from error
        (out / (label + '.log')).write_text(log, encoding='utf-8')
        print('\n'.join(line for line in log.splitlines() if any(tag in line for tag in
              ('UART:', 'CHECK:', 'PASS:', 'Fatal:', 'Error:'))), flush=True)
        if result.returncode or any(tag in log for tag in ('** Error:', '** Fatal:', 'FAIL:', '[FAIL]')):
            raise RuntimeError(label + ': failed; evidence retained at ' + str(out))
        return log

    report = {'passed': False, 'diagnostic_only_never_deploy': True, 'stages': {}}
    try:
        probe = out / 'probe'
        probe.mkdir()
        origin = ROOT if args.build else args.netlist_dir.resolve()
        for name, relative in FILES.items():
            source = (args.testbench.resolve() if name == 'tb_lfo_route_probe.v' and args.testbench
                      else origin / (relative if args.build else name))
            (probe / name).write_bytes(source.read_bytes())
        hashes = {name: hashlib.sha256((probe / name).read_bytes()).hexdigest() for name in FILES}
        report['source_sha256'] = hashes
        (probe / 'source_manifest.json').write_text(json.dumps(hashes, indent=2))
        netlist = probe / 'impl/pnr/probe.vo' if args.build else origin / 'impl/pnr/probe.vo'
        if args.build:
            # Refuse to overlap another Gowin invocation, including a production build.
            check = subprocess.run(['powershell', '-NoProfile', '-Command',
                "@(Get-Process gw_sh,GowinSynthesis,pnr -ErrorAction SilentlyContinue).Count"],
                capture_output=True, text=True, check=True)
            if int(check.stdout.strip()):
                raise RuntimeError('Another Gowin process is active; do not build concurrently')
            names = [name for name in FILES if name.endswith('.v') and not name.startswith('tb_')]
            entries = ''.join(f'<File path="{name}" type="file.verilog" enable="1"/>' for name in names)
            entries += '<File path="probe.cst" type="file.cst" enable="1"/><File path="probe.sdc" type="file.sdc" enable="1"/>'
            (probe / 'probe.gprj').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE gowin-fpga-project>\n<Project><Template>FPGA</Template><Version>5</Version>'
                '<Device name="GW5AST-138B" pn="GW5AST-LV138PG484AC1/I0">gw5ast138b-011</Device>'
                '<FileList>' + entries + '</FileList></Project>')
            (probe / 'probe.cst').write_text('IO_LOC "clk" V22;\nIO_LOC "rst_n" AA13;\n')
            (probe / 'probe.sdc').write_text('create_clock -name clk -period 20 [get_ports {clk}]\n')
            (probe / 'probe.tcl').write_text('open_project probe.gprj\n'
                'set_option -top_module lfo_route_probe\nset_option -synthesis_tool gowinsynthesis\n'
                'set_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nset_option -use_sspi_as_gpio 1\n'
                'set_option -place_option 3\nset_option -route_option 1\nset_option -timing_driven 1\n'
                'set_option -correct_hold_violation 1\nset_option -gen_verilog_sim_netlist 1\n'
                'set_option -show_init_in_vo 1\nrun all\nexit\n')
            run('gowin', [GOWIN / 'bin/gw_sh.exe', 'probe.tcl'], cwd=probe, timeout=600)
        library = GOWIN / 'simlib/gw5a/prim_sim.v'
        report['netlist'] = str(netlist)
        report['netlist_sha256'] = hashlib.sha256(netlist.read_bytes()).hexdigest()
        report['primitive_library_sha256'] = hashlib.sha256(library.read_bytes()).hexdigest()
        for kind in ('rtl', 'gate'):
            work = 'work_' + kind
            run(kind + '_library', [MS / 'vlib.exe', work])
            sources = ([probe / name for name in FILES if name.endswith('.v') and not name.startswith('tb_')]
                       if kind == 'rtl' else [library, netlist])
            run(kind + '_compile', [MS / 'vlog.exe', '-sv', '-work', work,
                *(['+define+GATE_PROBE'] if kind == 'gate' else []),
                '+incdir+' + str(probe), *sources, probe / 'tb_lfo_route_probe.v'])
            log = run(kind + '_sim', [MS / 'vsim.exe', '-c', work + '.tb_lfo_route_probe', '-do',
                'onerror {quit -code 1}; onbreak {quit -code 1 -force}; run -all; quit -f'])
            if 'PASS:' not in log:
                raise RuntimeError(kind + ': missing PASS')
            report['stages'][kind] = {'passed': True}
        report['workspace_matches_snapshot'] = all(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == hashes[name]
                                                   for name, relative in FILES.items())
        report['passed'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        (out / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
