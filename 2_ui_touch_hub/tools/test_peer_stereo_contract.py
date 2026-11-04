"""Run UI UART regressions through read-only snapshots of the peer receivers."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT / 'impl' / ('peer_stereo_contract_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    revision = subprocess.check_output(['git', 'rev-parse', 'origin/main'], cwd=ROOT, text=True).strip()
    hashes = {}
    for name in ('uart_rx.v', 'midi_note_parser.v', 'synth_control_router.v', 'highres_parameter_parser.v'):
        data = subprocess.check_output(['git', 'show', f'{revision}:src/{name}'], cwd=ROOT)
        (out / name).write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()

    pan = (ROOT / 'sim/tb_midi_uart_tx.v').read_text(encoding='utf-8')
    pan = pan.replace('module tb_midi_uart_tx;', 'module tb_peer_pan;')
    pan_monitor = r'''
wire [7:0] peer_byte;wire peer_valid,peer_framing;
wire cv;wire [3:0] channel;wire [6:0] number,value,global_pan,pan_a,pan_b;
integer global_checks=0,a_checks=0,b_checks=0;
uart_rx #(.CLK_HZ(62500000),.BAUD_RATE(3125000)) peer_uart(
 .clk(clk),.rst_n(rst_n),.rx(uart_tx),.data(peer_byte),.data_valid(peer_valid),.framing_error(peer_framing));
midi_note_parser peer_midi(.clk(clk),.rst_n(rst_n),.byte_data(peer_byte),.byte_valid(peer_valid),
 .control_change_valid(cv),.control_change_channel(channel),.control_change_number(number),.control_change_value(value));
synth_control_router peer_control(.clk(clk),.rst_n(rst_n),.raw_note_event_valid(1'b0),
 .raw_note_event_on(1'b0),.raw_note_event_channel(4'd0),.raw_note_event_note(7'd0),.raw_note_event_velocity(7'd0),
 .raw_control_change_valid(cv),.raw_control_change_channel(channel),.raw_control_change_number(number),
 .raw_control_change_value(value),.pan_target(global_pan),.osc_a_pan(pan_a),.osc_b_pan(pan_b));
always @(posedge clk)begin
 if(peer_framing)$fatal(1,"peer UART framing error");
 if(rst_n && cv)begin
  #1;
  if(number==10)begin
   if(global_pan!==value)$fatal(1,"global PAN not applied by peer");global_checks=global_checks+1;
  end
  if(number==91)begin
   if(pan_a!==value)$fatal(1,"OSC A PAN not applied by peer");a_checks=a_checks+1;
  end
  if(number==92)begin
   if(pan_b!==value)$fatal(1,"OSC B PAN not applied by peer");b_checks=b_checks+1;
  end
 end
end
'''
    # Same accelerated UART ratio as the existing wire decoder.
    pan = pan.replace('    // Use smaller divider', pan_monitor + '\n    // Use smaller divider')
    pan = pan.replace('        $finish;', '''        repeat(30)@(posedge clk);
        if(global_checks!=3 || a_checks!=3 || b_checks!=3)$fatal(1,"peer PAN coverage %0d/%0d/%0d",global_checks,a_checks,b_checks);
        $display("PASS: peer UART -> MIDI parser -> control router applies global/A/B PAN at 0,64,127");
        $finish;''')
    (out / 'tb_peer_pan.v').write_text(pan, encoding='utf-8')

    lfo = (ROOT / 'sim/tb_lfo_sysex_tx.v').read_text(encoding='utf-8').replace('module tb_lfo_sysex_tx;', 'module tb_peer_lfo;')
    lfo_monitor = r'''
wire [7:0] peer_byte;wire peer_valid,peer_framing,hr_valid;
wire [6:0] hr_id;wire [13:0] hr_value;
integer level_route_seen=0;
uart_rx #(.CLK_HZ(62500000),.BAUD_RATE(3125000)) peer_uart(
 .clk(clk),.rst_n(rst_n),.rx(uart_tx),.data(peer_byte),.data_valid(peer_valid),.framing_error(peer_framing));
highres_parameter_parser peer_parser(.clk(clk),.rst_n(rst_n),.byte_data(peer_byte),.byte_valid(peer_valid),
 .parameter_valid(hr_valid),.parameter_id(hr_id),.parameter_value(hr_value));
always @(posedge clk)begin
 if(peer_framing)$fatal(1,"peer SysEx UART framing error");
 if(hr_valid && hr_id==86 && hr_value==14'h017F)level_route_seen=level_route_seen+1;
end
'''
    lfo = lfo.replace('    integer errors;', lfo_monitor + '\n    integer errors;')
    lfo = lfo.replace('        if (errors == 0)', '''        repeat(30)@(posedge clk);
        if(level_route_seen!=1)$fatal(1,"peer parser did not accept OSC A Level LFO1 +127 exactly once");
        $display("PASS: UI LFO dispatcher -> UART -> peer 14-bit SysEx parser accepts T6 value 0x017F");
        if (errors == 0)''')
    (out / 'tb_peer_lfo.v').write_text(lfo, encoding='utf-8')

    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True,
                           text=True, errors='replace', timeout=180)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', '[FAIL]')):
            raise RuntimeError(f'{name} failed: {out}')
        return log

    run('library', [MS / 'vlib.exe', 'work'])
    run('compile', [MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'),
                    ROOT / 'rtl/midi_uart_tx/midi_uart_tx.v', ROOT / 'rtl/midi_uart_tx/lfo_sysex_tx.v',
                    *[out / name for name in hashes], out / 'tb_peer_pan.v', out / 'tb_peer_lfo.v'])
    for top in ('tb_peer_pan', 'tb_peer_lfo'):
        log = run(top, [MS / 'vsim.exe', '-c', top, '-do', 'run -all; quit -f'])
        assert '# PASS:' in log, out
        print('\n'.join(line for line in log.splitlines() if '# PASS:' in line))
    (out / 'result.json').write_text(json.dumps(dict(passed=True, peer_revision=revision, peer_source_sha256=hashes), indent=2))
    print(out)


if __name__ == '__main__':
    main()
