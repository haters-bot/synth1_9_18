"""Decode the existing MIDI CC and LFO SysEx tests, rejecting zero-exit failures."""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT / 'impl' / ('midi_lfo_protocol_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    print(out, flush=True)

    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True,
                           text=True, errors='replace', timeout=240)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', '[FAIL]', '# ERROR:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log

    run('library', [MS / 'vlib.exe', 'work'])
    sources = [ROOT / 'rtl/midi_uart_tx/midi_uart_tx.v', ROOT / 'rtl/midi_uart_tx/lfo_sysex_tx.v',
               ROOT / 'sim/tb_midi_uart_tx.v', ROOT / 'sim/tb_lfo_sysex_tx.v']
    run('compile', [MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'), *sources])
    for top, marker in [('tb_midi_uart_tx', 'ALL MIDI_UART_TX PROTOCOL TESTS PASSED'),
                        ('tb_lfo_sysex_tx', '[DONE] ALL TESTS PASSED')]:
        log = run(top, [MS / 'vsim.exe', '-c', top, '-do', 'run -all; quit -f'])
        assert marker in log, out
        print('PASS: ' + marker, flush=True)


if __name__ == '__main__':
    main()
