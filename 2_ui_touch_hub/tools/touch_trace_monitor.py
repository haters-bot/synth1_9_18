"""Read diagnostic FPGA trace over the board DEBUG USB-UART (115200 8N1).

This is NOT a MIDI monitor. Use the separate diagnostic firmware only.
Examples: python tools/touch_trace_monitor.py --list
          python tools/touch_trace_monitor.py --port COM5 --seconds 60
          python tools/touch_trace_monitor.py --decode capture.bin
"""
import argparse
from datetime import datetime
from functools import reduce
import json
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
PARAMS = {
    int(value, 16): name for name, value in re.findall(
        r"`define\s+PARAM_ID_(\w+)\s+8'h([0-9A-Fa-f]+)",
        (ROOT / 'rtl/ui_vector_engine/params.vh').read_text(encoding='utf-8'))
}
FLAGS = ('touch', 'button', 'delta', 'parameter_request', 'curve', 'spi', 'lfo', 'status')
KNOB_PARAMS = (
    'OSCA_WT_POS','OSCA_WARP','OSCA_PAN','OSCA_VOL','OSCA_UNISON','OSCA_DETUNE','OSCA_BLEND','OSCA_PHASE',
    'ENV1_ATTACK','ENV1_HOLD','ENV1_DECAY','ENV1_SUSTAIN','ENV1_RELEASE','MASTER_VOL','MACRO1','MACRO2',
    'OSCB_WT_POS','OSCB_WARP','OSCB_PAN','OSCB_VOL','OSCB_UNISON','OSCB_DETUNE','OSCB_BLEND','OSCB_PHASE',
    'FLT_CUTOFF','FLT_RES','FLT_PAN','FLT_DRIVE','FLT_FAT','FLT_MIX','FX_REVERB','FX_DELAY')
KNOB_BY_ID = {int(value, 16): i+1 for i, name in enumerate(KNOB_PARAMS)
              for value in re.findall(r"`define\s+PARAM_ID_"+re.escape(name)+r"\s+8'h([0-9A-Fa-f]+)",
                                      (ROOT / 'rtl/ui_vector_engine/params.vh').read_text(encoding='utf-8'))}


class TraceDecoder:
    def __init__(self):
        self.buffer = bytearray()
        self.bad_frames = 0
        self.skipped_bytes = 0
        self.last_sequence = None
        self.down = False

    def feed(self, chunk):
        self.buffer.extend(chunk)
        result = []
        while len(self.buffer) >= 2:
            pos = self.buffer.find(b'\x55\xaa')
            if pos < 0:
                keep = int(self.buffer[-1] == 0x55)
                self.skipped_bytes += len(self.buffer) - keep
                self.buffer[:] = self.buffer[-1:] if keep else b''
                break
            if pos:
                self.skipped_bytes += pos
                del self.buffer[:pos]
            if len(self.buffer) < 64:
                break
            frame = bytes(self.buffer[:64])
            if frame[2] != 1 or reduce(int.__xor__, frame, 0) != 0:
                self.bad_frames += 1
                self.skipped_bytes += 1
                del self.buffer[0]
                continue
            del self.buffer[:64]
            result.append(self.decode_frame(frame))
        return result

    def decode_frame(self, f):
        u16 = lambda p: int.from_bytes(f[p:p+2], 'little')
        u32 = lambda p: int.from_bytes(f[p:p+4], 'little')
        name = lambda v: PARAMS.get(v, f'UNKNOWN_0x{v:02X}')
        seq = u32(4)
        gap = 0 if self.last_sequence is None else (seq-self.last_sequence-1) & 0xffffffff
        self.last_sequence = seq
        r = dict(version=f[2], sequence=seq, board_ms=u32(8), dropped_records=u32(12),
                 sequence_gap=gap, events=[v for b, v in enumerate(FLAGS) if f[3] & (1 << b)])
        if (f[3] & 0x80) and (f[62] & 0x10):
            r['spi_link'] = dict(chip=2 if f[62] & 0x08 else 1,
                                 connected=bool(f[62] & 0x02))
        r['context'] = dict(focus_id=f[26], focus=name(f[26]), focus_known=bool(f[52]),
                            value=f[53] if f[58] else None, env_tab=f[41]+1,
                            button_state_hex=f'{u32(54):08X}')
        panel_action = {1: 'PRESS', 2: 'RELEASE'}.get(f[60])
        if f[3] & 0x20 and panel_action:
            knob = KNOB_BY_ID.get(f[59])
            if knob:
                r['panel_event'] = dict(knob=knob, action=panel_action)
        if f[3] & 1:
            down = bool(f[16])
            phase = ('MOVE' if self.down else 'DOWN') if down else ('UP' if self.down else 'RELEASE_IDLE')
            self.down = down
            r['touch'] = dict(phase=phase, down=down, source={1:'usb', 2:'hspi', 3:'uart'}.get(f[17], 'unknown'),
                              raw_x=u16(18), raw_y=u16(20), x=u16(22), y=u16(24))
        if f[3] & 2:
            r['button'] = dict(id=f[27], name=name(f[27]), action=f[28])
        if f[3] & 4:
            r['delta'] = f[29] if f[29] < 128 else f[29]-256
        if f[3] & 8:
            r['parameter_request'] = dict(id=f[30], name=name(f[30]), value=f[31])
        if f[3] & 16:
            r['curve'] = dict(panel='FILTER' if f[34] & 4 else 'ENV', tab=(f[34] & 3)+1,
                              mask=f[35], values=list(f[36:41]))
        if f[3] & 32:
            # Byte 60 is nonzero for a physical switch edge. This prevents a
            # switch-only frame from replaying the previous rotation payload.
            if not panel_action:
                knob = KNOB_BY_ID.get(f[32])
                if knob:
                    r['panel_event'] = dict(knob=knob, action='CW' if f[61] & 1 else 'CCW')
                else:
                    r['spi'] = dict(id=f[32], name=name(f[32]), value=f[33])
        # All frames carry the local LFO snapshot, even if this event is a touch
        # on an unchanged preset/restart control. These are local UI values.
        r['lfo_snapshot'] = dict(tab=f[42]+1, rate_index=f[43], once=bool(f[44] & 1),
                                 stepped=bool(f[44] & 2), preset=f[44] >> 2,
                                 nodes=list(f[45:52]))
        return r


def format_record(r):
    parts = [f"#{r['sequence']} {r['board_ms']}ms"]
    if 'touch' in r:
        t = r['touch']
        parts.append(f"{t['phase']} {t['source']} raw=({t['raw_x']},{t['raw_y']}) screen=({t['x']},{t['y']})")
    c = r['context']
    if c['focus_known']:
        parts.append(f"focus={c['focus']} value={c['value']} ENV{c['env_tab']}")
    if 'button' in r:
        b = r['button']; parts.append(f"BUTTON {b['name']} action={b['action']}")
    if 'delta' in r:
        parts.append(f"delta={r['delta']:+d}")
    if 'parameter_request' in r:
        p = r['parameter_request']; parts.append(f"PARAM_REQ {p['name']}={p['value']}")
    if 'curve' in r:
        v = r['curve']; parts.append(f"{v['panel']}{v['tab']} mask=0x{v['mask']:02X} values={v['values']}")
    if 'spi' in r:
        if 'panel_event' not in r:
            p = r['spi']; parts.append(f"SPI {p['name']}={p['value']}")
    if 'panel_event' in r:
        p = r['panel_event']; parts.append(f"KNOB{p['knob']:02d} {p['action']}")
    if 'lfo' in r['events']:
        v = r['lfo_snapshot']; parts.append(f"LFO{v['tab']} rate_index={v['rate_index']} nodes={v['nodes']}")
    if 'spi_link' in r:
        v=r['spi_link']; parts.append(f"SPI U{v['chip']} {'CONNECTED' if v['connected'] else 'DISCONNECTED'}")
    elif 'status' in r['events']:
        parts.append('STATUS')
    if r['dropped_records'] or r['sequence_gap']:
        parts.append(f"LOSS board_total={r['dropped_records']} gap={r['sequence_gap']}")
    return ' | '.join(parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--port')
    ap.add_argument('--seconds', type=float)
    ap.add_argument('--output', type=Path, help='New JSONL file; never overwrite an existing capture')
    ap.add_argument('--decode', type=Path, help='Decode saved raw binary offline; no serial package needed')
    args = ap.parse_args()
    if args.seconds is not None and args.seconds <= 0:
        ap.error('--seconds must be positive')
    decoder = TraceDecoder()
    if args.decode:
        with args.decode.open('rb') as stream:
            while chunk := stream.read(4096):
                for record in decoder.feed(chunk): print(format_record(record))
        print(f'bad_frames={decoder.bad_frames} skipped_bytes={decoder.skipped_bytes} trailing_bytes={len(decoder.buffer)}')
        return
    try:
        import serial
        import serial.tools.list_ports
    except ImportError:
        ap.error('Install pyserial first: python -m pip install pyserial')
    if args.list:
        for p in serial.tools.list_ports.comports(): print(p.device, p.description, p.hwid)
        return
    if not args.port:
        ap.error('Use --list to find the board DEBUG USB-UART, then specify --port COMx')
    output = args.output or ROOT/'impl'/'touch_logs'/('touch_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.jsonl')
    raw_path = output.with_suffix('.bin')
    if output == raw_path or output.exists() or raw_path.exists():
        ap.error('Output files already exist or paths collide; choose new names')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Do not send bytes, reset the FPGA, or change any UI parameter.
    ser = serial.Serial()
    ser.port=args.port;ser.baudrate=115200;ser.timeout=0.2
    ser.dtr=False;ser.rts=False
    received=0;start=time.monotonic()
    with ser, output.open('x',encoding='utf-8') as log, raw_path.open('xb') as raw:
        print(f'Diagnostic trace 115200 8N1: {args.port}\nJSONL: {output}\nRAW: {raw_path}', flush=True)
        try:
            while args.seconds is None or time.monotonic()-start < args.seconds:
                chunk=ser.read(4096 if ser.in_waiting>4096 else max(1,ser.in_waiting))
                if not chunk: continue
                raw.write(chunk);raw.flush()
                for record in decoder.feed(chunk):
                    received+=1
                    record['received_at']=datetime.now().astimezone().isoformat()
                    log.write(json.dumps(record,ensure_ascii=False)+'\n');log.flush()
                    print(format_record(record),flush=True)
        except KeyboardInterrupt:
            pass
    print(f'records={received} bad_frames={decoder.bad_frames} skipped_bytes={decoder.skipped_bytes} trailing_bytes={len(decoder.buffer)}')
    if not received:
        raise SystemExit('No valid trace received. Check diagnostic firmware, COM port, and DEBUG USB connection.')


if __name__ == '__main__':
    if hasattr(sys.stdout,'reconfigure'): sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    main()
