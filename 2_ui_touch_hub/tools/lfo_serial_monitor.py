"""Print LFO rate diagnostics from the unchanged MIDI UART byte stream.

Examples:
  python tools/lfo_serial_monitor.py --hex "F0 7D 45 00 03 F7" --ui-hz 2
  python tools/lfo_serial_monitor.py --port COM7 --ui-hz 4
--ui-hz is the operator's observed UI label, not a measurement from the wire.
Live serial input requires pyserial. File/hex decoding uses only stdlib.
"""
import argparse
import re

HZ = ('0.25', '0.5', '1', '2', '4', '8', '16', '32')


def describe(frame, ui_hz=None):
    if len(frame) != 6 or frame[:2] != bytes((0xF0, 0x7D)) or frame[-1] != 0xF7:
        raise ValueError('Invalid six-byte manufacturer SysEx frame')
    if frame[3] > 127 or frame[4] > 127:
        raise ValueError('Non-MIDI-safe data byte')
    value = frame[3] * 128 + frame[4]
    raw = frame.hex(' ').upper()
    if 0x45 <= frame[2] <= 0x47:
        index = value & 7
        observed = ui_hz if ui_hz is not None else 'unknown'
        expected = HZ.index(ui_hz) if ui_hz is not None else None
        match = 'unknown' if expected is None else str(expected == index)
        return (f'LFO{frame[2]-0x44} UI_Hz={observed} expected_rate_index={expected} '
                f'rate_index={index} encoded_Hz={HZ[index]} stepped={(value >> 3) & 1} '
                f'once={(value >> 4) & 1} mode_value={value} UI_match={match} bytes={raw}')
    return f'id=0x{frame[2]:02X} value={value} bytes={raw}'


def decode_stream(data, ui_hz=None):
    pending = bytearray()
    for byte in data:
        if byte == 0xF0:
            pending = bytearray((byte,))
        elif byte >= 0xF8:
            continue  # MIDI real-time bytes may interrupt a SysEx frame.
        elif pending:
            pending.append(byte)
            if byte == 0xF7:
                if len(pending) == 6 and pending[1] == 0x7D:
                    yield describe(bytes(pending), ui_hz)
                pending.clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--hex')
    mode.add_argument('--port')
    parser.add_argument('--ui-hz', choices=HZ)
    args = parser.parse_args()
    if args.hex is not None:
        text = re.sub(r'\s+', '', args.hex)
        for line in decode_stream(bytes.fromhex(text), args.ui_hz):
            print(line, flush=True)
    else:
        import serial
        with serial.Serial(args.port, 31250, timeout=1) as uart:
            def stream():
                while True:
                    yield from uart.read(256)
            for line in decode_stream(stream(), args.ui_hz):
                print(line, flush=True)


if __name__ == '__main__':
    main()
