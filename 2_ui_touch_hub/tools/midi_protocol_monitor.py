#!/usr/bin/env python3
# ==============================================================================
# Script: midi_protocol_monitor.py
# Description: Real-time Serial Port MIDI Protocol Monitor for FPGA Synthesizer Engine
#              Matches Teammate 3 (synth1_9_18) Audio Protocol:
#              - Channel 16 (0xBF): Continuous Synthesis Parameters & Control Change (CC)
#              - Channel 1  (0x90/0x80): Note-On / Note-Off Real-time Performance Events
# Project: 2_ui_touch_hub (FPGA Real-time Polyphonic Synthesizer UI)
# ==============================================================================

import sys
import time
import argparse
import datetime

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# ------------------------------------------------------------------------------
# 1. MIDI Parameter Dictionary (Teammate 3 synth1_9_18 Alignment)
# ------------------------------------------------------------------------------
CC_NAMES = {
    1:   "Macro 1 / Mod Wheel",
    2:   "Macro 2",
    3:   "Macro 3",
    4:   "Macro 4",
    5:   "Portamento Time",
    7:   "Master Volume",
    10:  "Oscillator Pan",
    12:  "FX Delay Mix",
    13:  "Filter Drive",
    20:  "Wavetable Position (WT Pos)",
    21:  "Waveform / Warp Modulation",
    22:  "Unison Detune Spread",
    23:  "Unison Voice Count",
    71:  "Filter Resonance (Q)",
    72:  "Envelope Release Time",
    73:  "Envelope Attack Time",
    74:  "Filter Cutoff Frequency",
    75:  "Envelope Decay Time",
    76:  "Envelope Sustain Level",
    79:  "Envelope Hold Time",
    91:  "FX Reverb Mix",
    93:  "FX Chorus Mix",
    95:  "Filter Wet/Dry Mix",
    102: "OSC A Power Enable",
    103: "OSC B Power Enable",
    104: "Filter Power Enable",
    110: "FX Slot 1 Bypass",
    111: "FX Slot 2 Bypass",
    112: "FX Slot 3 Bypass",
    113: "FX Slot 4 Bypass",
}

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def get_note_str(note_num):
    octave = (note_num // 12) - 1
    name = NOTE_NAMES[note_num % 12]
    return f"{name}{octave} ({note_num})"

def render_meter(val, max_val=127, width=20):
    val = max(0, min(max_val, val))
    filled = int(round((val / max_val) * width))
    bar = "=" * filled + "-" * (width - filled)
    pct = int((val / max_val) * 100)
    return f"[{bar}] {pct:3d}% ({val:3d})"

# ------------------------------------------------------------------------------
# 2. Protocol Decoder Engine
# ------------------------------------------------------------------------------
class MidiProtocolDecoder:
    def __init__(self, target_channel=None):
        self.target_channel = target_channel
        self.state = 0  # 0: waiting for status, 1: byte1, 2: byte2
        self.status = 0
        self.byte1 = 0
        self.total_msgs = 0
        self.cc_msgs = 0
        self.note_msgs = 0

    def feed_byte(self, b):
        """
        Feeds a single incoming byte to the MIDI stream parser.
        Returns a formatted log string if a complete 3-byte message was parsed, else None.
        """
        # If byte is a Status Byte (bit 7 = 1)
        if b & 0x80:
            self.status = b
            self.state = 1
            return None

        # Data Byte (bit 7 = 0)
        if self.state == 1:
            self.byte1 = b
            self.state = 2
            return None
        elif self.state == 2:
            byte2 = b
            self.state = 0 # Ready for running status or next message
            return self._decode_message(self.status, self.byte1, byte2)
        return None

    def _decode_message(self, status, b1, b2):
        cmd = status & 0xF0
        ch = (status & 0x0F) + 1  # 1-indexed MIDI channel

        if self.target_channel is not None and ch != self.target_channel:
            return None

        now = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        raw_hex = f"{status:02X} {b1:02X} {b2:02X}"
        self.total_msgs += 1

        # Channel 16 Control Change (0xBF)
        if cmd == 0xB0:
            self.cc_msgs += 1
            cc_num = b1
            cc_val = b2
            name = CC_NAMES.get(cc_num, f"Unknown CC{cc_num}")
            meter = render_meter(cc_val)
            tag = f"[CC Ch{ch:02d}]"
            return f"[{now}] {tag} {raw_hex} | {name:<26s} : {meter}"

        # Note On (0x90)
        elif cmd == 0x90:
            self.note_msgs += 1
            vel = b2
            note_str = get_note_str(b1)
            if vel > 0:
                tag = f"[NOTE-ON  Ch{ch:02d}]"
                return f"[{now}] {tag} {raw_hex} | {note_str:<26s} : Vel={vel}"
            else:
                tag = f"[NOTE-OFF Ch{ch:02d}]"
                return f"[{now}] {tag} {raw_hex} | {note_str:<26s} : Release"

        # Note Off (0x80)
        elif cmd == 0x80:
            self.note_msgs += 1
            note_str = get_note_str(b1)
            tag = f"[NOTE-OFF Ch{ch:02d}]"
            return f"[{now}] {tag} {raw_hex} | {note_str:<26s} : Release"

        return f"[{now}] [MIDI Ch{ch:02d}] {raw_hex} | Cmd=0x{cmd:02X} D1={b1} D2={b2}"

# ------------------------------------------------------------------------------
# 3. Serial Port Communication Abstraction
# ------------------------------------------------------------------------------
class SerialReader:
    def __init__(self, port, baudrate):
        self.port = port
        self.baudrate = baudrate
        self.backend = None
        self._open()

    def _open(self):
        # Try pyserial first
        try:
            import serial
            self.ser = serial.Serial(self.port, self.baudrate, timeout=0.1)
            self.backend = "pyserial"
            print(f"[MONITOR] Opened {self.port} at {self.baudrate} baud using pyserial.")
            return
        except ImportError:
            pass
        except Exception as e:
            print(f"[MONITOR] pyserial open failed: {e}")

        # Fallback: Windows Win32 API via ctypes
        if sys.platform == "win32":
            try:
                import ctypes
                from ctypes import wintypes

                GENERIC_READ = 0x80000000
                GENERIC_WRITE = 0x40000000
                OPEN_EXISTING = 3
                FILE_ATTRIBUTE_NORMAL = 0x80

                port_name = f"\\\\.\\{self.port}"
                self.handle = ctypes.windll.kernel32.CreateFileW(
                    port_name,
                    GENERIC_READ | GENERIC_WRITE,
                    0, None,
                    OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL,
                    None
                )
                if self.handle == -1 or self.handle == 0xFFFFFFFFFFFFFFFF:
                    raise OSError(f"Failed to open COM port: {ctypes.GetLastError()}")

                # Configure DCB
                class DCB(ctypes.Structure):
                    _fields_ = [
                        ('DCBlength', wintypes.DWORD),
                        ('BaudRate', wintypes.DWORD),
                        ('flags', wintypes.DWORD),
                        ('wReserved', wintypes.WORD),
                        ('XonLim', wintypes.WORD),
                        ('XoffLim', wintypes.WORD),
                        ('ByteSize', wintypes.BYTE),
                        ('Parity', wintypes.BYTE),
                        ('StopBits', wintypes.BYTE),
                        ('XonChar', ctypes.c_char),
                        ('XoffChar', ctypes.c_char),
                        ('ErrorChar', ctypes.c_char),
                        ('EofChar', ctypes.c_char),
                        ('EvtChar', ctypes.c_char),
                        ('wReserved1', wintypes.WORD),
                    ]
                dcb = DCB()
                dcb.DCBlength = ctypes.sizeof(DCB)
                ctypes.windll.kernel32.GetCommState(self.handle, ctypes.byref(dcb))
                dcb.BaudRate = self.baudrate
                dcb.ByteSize = 8
                dcb.Parity = 0
                dcb.StopBits = 0
                ctypes.windll.kernel32.SetCommState(self.handle, ctypes.byref(dcb))

                # Configure Timeouts
                class COMMTIMEOUTS(ctypes.Structure):
                    _fields_ = [
                        ('ReadIntervalTimeout', wintypes.DWORD),
                        ('ReadTotalTimeoutMultiplier', wintypes.DWORD),
                        ('ReadTotalTimeoutConstant', wintypes.DWORD),
                        ('WriteTotalTimeoutMultiplier', wintypes.DWORD),
                        ('WriteTotalTimeoutConstant', wintypes.DWORD),
                    ]
                timeouts = COMMTIMEOUTS(50, 0, 100, 0, 100)
                ctypes.windll.kernel32.SetCommTimeouts(self.handle, ctypes.byref(timeouts))
                self.backend = "win32_ctypes"
                print(f"[MONITOR] Opened {self.port} at {self.baudrate} baud using native Win32 API.")
                return
            except Exception as e:
                print(f"[MONITOR] Native Win32 COM port open failed: {e}")

        raise RuntimeError(f"Could not open serial port {self.port}. Please check port name and permissions.")

    def read(self, max_bytes=64):
        if self.backend == "pyserial":
            return self.ser.read(max_bytes)
        elif self.backend == "win32_ctypes":
            import ctypes
            from ctypes import wintypes
            buf = ctypes.create_string_buffer(max_bytes)
            bytes_read = wintypes.DWORD()
            res = ctypes.windll.kernel32.ReadFile(
                self.handle, buf, max_bytes, ctypes.byref(bytes_read), None
            )
            if res and bytes_read.value > 0:
                return buf.raw[:bytes_read.value]
            return b""
        return b""

    def close(self):
        if self.backend == "pyserial":
            self.ser.close()
        elif self.backend == "win32_ctypes":
            import ctypes
            ctypes.windll.kernel32.CloseHandle(self.handle)

# ------------------------------------------------------------------------------
# 4. Self-Test / Protocol Verification Suite
# ------------------------------------------------------------------------------
def run_self_test():
    print("=" * 78)
    print("MIDI PROTOCOL MONITOR - SYNTH1_9_18 CHANNEL 16 VALIDATION SUITE")
    print("=" * 78)

    decoder = MidiProtocolDecoder()
    test_packets = [
        # Ch 16 CC Packets: Status=0xBF
        (bytes([0xBF, 74, 80]),  "Cutoff Frequency"),
        (bytes([0xBF, 71, 32]),  "Resonance"),
        (bytes([0xBF, 20, 64]),  "WT Position"),
        (bytes([0xBF, 22, 64]),  "Unison Detune"),
        (bytes([0xBF, 23, 4]),   "Unison Count"),
        (bytes([0xBF, 73, 15]),  "Attack"),
        (bytes([0xBF, 75, 45]),  "Decay"),
        (bytes([0xBF, 76, 90]),  "Sustain"),
        (bytes([0xBF, 72, 35]),  "Release"),
        (bytes([0xBF, 10, 64]),  "Pan"),
        (bytes([0xBF, 7,  100]), "Master Volume"),
        (bytes([0xBF, 1,  127]), "Macro 1"),
        (bytes([0xBF, 91, 50]),  "Reverb"),
        (bytes([0xBF, 12, 40]),  "Delay"),
        # Ch 1 Note Packets: Note On (0x90), Note Off (0x80)
        (bytes([0x90, 60, 100]), "Note On C4"),
        (bytes([0x80, 60, 0]),   "Note Off C4"),
        (bytes([0x90, 48, 110]), "Note On C3"),
        (bytes([0x90, 71, 95]),  "Note On B4"),
    ]

    all_passed = True
    for pkt, desc in test_packets:
        result = None
        for b in pkt:
            res = decoder.feed_byte(b)
            if res:
                result = res
        if result:
            print(f"PASS: {desc:<24s} -> {result}")
        else:
            print(f"FAIL: {desc:<24s} -> Message not decoded!")
            all_passed = False

    print("-" * 78)
    print(f"Test Summary: Total={decoder.total_msgs}, CC={decoder.cc_msgs}, Note={decoder.note_msgs}")
    if all_passed:
        print("[SUCCESS] All 18 MIDI synth1_9_18 protocol test vectors passed perfectly!")
    else:
        print("[ERROR] Some test vectors failed!")
    print("=" * 78)
    return all_passed

# ------------------------------------------------------------------------------
# 5. Main CLI Entry Point
# ------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Teammate 3 (synth1_9_18) MIDI Protocol Serial Port Monitor"
    )
    parser.add_argument("--port", "-p", default="COM3", help="Serial port name (default: COM3)")
    parser.add_argument("--baud", "-b", type=int, default=31250, help="Baud rate (default: 31250)")
    parser.add_argument("--channel", "-c", type=int, default=None, help="Filter by MIDI channel (e.g. 16)")
    parser.add_argument("--test", action="store_true", help="Run protocol decoding self-test suite")

    args = parser.parse_args()

    if args.test:
        success = run_self_test()
        sys.exit(0 if success else 1)

    print(f"[MONITOR] Starting MIDI Protocol Monitor on {args.port} at {args.baud} baud...")
    print(f"[MONITOR] Target Filter: Channel {args.channel if args.channel else 'ALL'}")
    print("[MONITOR] Press Ctrl+C to terminate.")

    decoder = MidiProtocolDecoder(target_channel=args.channel)
    try:
        reader = SerialReader(args.port, args.baud)
    except Exception as e:
        print(f"[ERROR] Could not initialize serial reader: {e}")
        print("[HINT] Run with --test to verify the protocol decoder without physical hardware.")
        sys.exit(1)

    try:
        while True:
            data = reader.read(64)
            if data:
                for b in data:
                    msg = decoder.feed_byte(b)
                    if msg:
                        print(msg, flush=True)
            else:
                time.sleep(0.005)
    except KeyboardInterrupt:
        print("\n[MONITOR] Interrupted by user. Exiting.")
    finally:
        reader.close()
        print(f"[MONITOR] Closed. Total decoded messages: {decoder.total_msgs}")

if __name__ == "__main__":
    main()
