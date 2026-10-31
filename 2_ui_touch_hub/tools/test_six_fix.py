"""Compile production RTL and run named six-fix benches, retaining all evidence."""
from pathlib import Path
from datetime import datetime
import hashlib, json, subprocess, sys
from simulation_sources import project_verilog_sources

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')

def main():
    names = sys.argv[1:]
    if not names or any(not n.startswith('tb_') or not n.replace('_', '').isalnum() for n in names):
        raise SystemExit('Usage: test_six_fix.py tb_name [tb_name ...]')
    out = Path('E:/gaoyun_builds')/('six_fix_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    sources = project_verilog_sources(ROOT, '2_ui_touch_hub.gprj') + [ROOT/'sim'/f'{n}.v' for n in names]
    # Compile an immutable snapshot; independent work must not rewrite inputs
    # underneath a running simulator. The final report also checks workspace.
    originals = sources + list((ROOT/'rtl/ui_vector_engine').glob('*.vh')) + [
        ROOT/'2_ui_touch_hub.gprj', Path(__file__).resolve(), ROOT/'tools/simulation_sources.py']
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in originals}
    for p in originals:
        q = out/'src'/p.relative_to(ROOT)
        q.parent.mkdir(parents=True, exist_ok=True)
        q.write_bytes(p.read_bytes())
    sources = [out/'src'/p.relative_to(ROOT) for p in sources]
    references = {}
    if 'tb_audio_protocol_alignment' in names:
        commit='dbffe3768fa29405ad50845d4e915577d1c16557'
        for filename in ('synth_control_router.v','midi_note_parser.v'):
            blob=subprocess.check_output(['git','show',commit+':src/'+filename],cwd=ROOT)
            golden=out/'src/sim'/filename
            golden.write_bytes(blob);sources.append(golden)
            references[filename]={'commit':commit,'sha256':hashlib.sha256(blob).hexdigest()}
    if 'tb_modulation_audio_equivalence' in names:
        # Read-only golden audio RTL, pinned rather than dependent on moving HEAD.
        commit = 'dbffe3768fa29405ad50845d4e915577d1c16557'
        blob = subprocess.check_output(['git', 'show', commit+':src/lfo_target_router_v2.v'], cwd=ROOT)
        golden = out/'src/sim/audio_router_reference.v'
        golden.write_bytes(blob)
        sources.append(golden)
        references['audio_router'] = {'commit':commit, 'sha256':hashlib.sha256(blob).hexdigest()}
    if 'tb_lfo_capabilities' in names:
        # Pin all 53 previous IDs independently of the newly edited decoder.
        blob = subprocess.check_output(['git', 'show', 'e981aaf:2_ui_touch_hub/rtl/ui_vector_engine/mod_targets.vh'], cwd=ROOT).decode()
        import re
        ids = re.findall(r"\d+: mod_id=8'd(\d+);", blob)
        assert len(ids)==53
        (out/'target_ids_before.hex').write_text('\n'.join(f'{int(n):02x}' for n in ids))
    print(out, flush=True)
    def run(label, args):
        try:
            r = subprocess.run(list(map(str,args)), cwd=out, capture_output=True, text=True, errors='replace', timeout=240)
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
            log = decoded(error.stdout) + decoded(error.stderr)
            (out/f'{label}.log').write_text(log + '\nTIMEOUT: wall-clock limit 240 seconds\n')
            (out/'failure.json').write_text(json.dumps({'passed': False, 'stage': label,
                'reason': 'wall_clock_timeout', 'timeout_seconds': 240}, indent=2))
            raise RuntimeError(f'{label} timed out; partial output preserved: {out}') from error
        log = r.stdout+r.stderr
        (out/f'{label}.log').write_text(log)
        if r.returncode or any(s in log for s in ('** Error:', '** Fatal:', 'FATAL:', 'FAIL:', '[FAIL]', '# ERROR:')):
            print(log[-9000:])
            raise RuntimeError(f'{label} failed: {out}')
        return log
    run('library', [MS/'vlib.exe', 'work'])
    run('compile', [MS/'vlog.exe', '-sv', '+incdir+'+str(out/'src/rtl/ui_vector_engine'), *sources])
    for name in names:
        log = run(name, [MS/'vsim.exe', '-c', name, '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        if not any(marker in log for marker in ('PASS:', '[DONE] ALL TESTS PASSED', 'ALL MIDI_UART_TX PROTOCOL TESTS PASSED')):
            raise RuntimeError(f'Missing PASS: {name}: {out}')
        print('\n'.join(l for l in log.splitlines() if any(s in l for s in ('PASS:', 'UART:', 'CHECK:', 'TRACE:'))), flush=True)
    matches = all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'result.json').write_text(json.dumps({'passed':True, 'workspace_matches_snapshot':matches, 'tests':names, 'source_sha256':hashes, 'read_only_references':references}, indent=2))
    if not matches:
        raise RuntimeError(f'Workspace changed after snapshot; rerun affected tests: {out}')

if __name__ == '__main__':
    main()
