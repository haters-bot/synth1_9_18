"""Run receiver and production I2S loopback regressions with preserved logs."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MODELSIM = Path(os.environ.get('MODELSIM_BIN', 'D:/altera/modelsim_ase/win32aloem'))


def main():
    out = ROOT / 'impl' / ('i2s_tests_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    sources = [ROOT / 'rtl/audio/i2s_visual_rx.v', ROOT.parent / 'src/i2s_tx.v',
               ROOT / 'rtl/audio/audio_fft_tables.v',ROOT / 'rtl/audio/audio_fft_analyzer.v',
               ROOT / 'rtl/audio/audio_phase_plot.v',
               ROOT / 'rtl/audio/audio_pcm_metrics.v', ROOT / 'rtl/audio/audio_stereo_meter.v',
               ROOT / 'rtl/audio/audio_correlation_cursor.v',
               ROOT / 'sim/tb_audio_correlation_cursor.v',
               ROOT / 'rtl/audio/audio_waveform_capture.v',
               ROOT / 'sim/tb_i2s_visual_rx.v', ROOT / 'sim/tb_i2s_visual_loopback.v',
               ROOT / 'rtl/ui_vector_engine/ui_navigation_renderer.v',
               ROOT / 'sim/tb_audio_visual_windows.v']
    sources.append(ROOT / 'sim/tb_audio_waveform_capture.v')
    sources.append(ROOT / 'sim/tb_i2s_metrics_chain.v')
    headers = list((ROOT / 'rtl/ui_vector_engine').glob('*.vh'))
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources + headers}

    def run(name, command):
        result = subprocess.run(command, cwd=out, text=True, errors='replace',
                                capture_output=True, timeout=90)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_text(log)
        if result.returncode or any(token in log for token in ('** Error:', '** Fatal:', '# ERROR:', '# FAIL:')):
            raise RuntimeError(name + ' failed; see ' + str(out / (name + '.log')))
        return log

    run('library', [str(MODELSIM / 'vlib.exe'), 'work'])
    run('compile', [str(MODELSIM / 'vlog.exe'), '-sv', '-work', 'work',
                    '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'), *map(str, sources)])
    for top in ('tb_i2s_visual_rx', 'tb_i2s_visual_loopback', 'tb_audio_visual_windows','tb_audio_waveform_capture','tb_i2s_metrics_chain','tb_audio_correlation_cursor'):
        # ModelSim can exit zero after a testbench failure. Require the
        # explicit PASS marker as well as a clean process and transcript.
        log = run(top, [str(MODELSIM / 'vsim.exe'), '-c', '-lib', 'work', top,
                        '-do', 'run -all; quit -f'])
        if '# PASS:' not in log:
            raise RuntimeError(top + ' has no PASS marker; see ' + str(out))
        for line in log.splitlines():
            if '# PASS:' in line:
                print(line)
    (out / 'result.json').write_text(json.dumps({'passed': True, 'source_sha256': hashes}, indent=2))
    print(out)


if __name__ == '__main__':
    main()
