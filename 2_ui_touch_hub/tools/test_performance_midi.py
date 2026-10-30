from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from performance_midi import MidiFormatError, note_to_key, parse_midi


def vlq(value: int) -> bytes:
    if value < 0:
        raise ValueError(value)
    encoded = [value & 0x7F]
    value >>= 7
    while value:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(reversed(encoded))


def track(events: bytes) -> bytes:
    return b"MTrk" + len(events).to_bytes(4, "big") + events


def make_song() -> bytes:
    tempo = vlq(0) + b"\xFF\x51\x03\x07\xA1\x20"  # 120 BPM
    notes = (
        vlq(0) + b"\x90\x3C\x64"  # C4 on
        + vlq(480) + b"\x3C\x00"  # running-status C4 off
        + vlq(0) + b"\x90\x40\x50"  # E4 on
        + vlq(240) + b"\x80\x40\x00"  # explicit E4 off
        + vlq(0) + b"\xFF\x2F\x00"
    )
    tempo_track = tempo + vlq(0) + b"\xFF\x2F\x00"
    header = b"MThd" + (6).to_bytes(4, "big") + (1).to_bytes(2, "big") + (2).to_bytes(2, "big") + (480).to_bytes(2, "big")
    return header + track(tempo_track) + track(notes)


def main() -> None:
    song = parse_midi(make_song())
    assert song.midi_format == 1
    assert song.division == 480
    assert song.duration_us == 750_000
    assert [(event.note, event.on, event.time_us, event.velocity) for event in song.events] == [
        (60, True, 0, 100),
        (60, False, 500_000, 0),
        (64, True, 500_000, 80),
        (64, False, 750_000, 0),
    ]
    assert note_to_key(60) == 0
    assert note_to_key(83) == 23
    assert note_to_key(84) == 24
    assert note_to_key(91) == 31
    assert note_to_key(92) is None
    for base in range(21, 78):
        for note in range(128):
            key = note_to_key(note, base_note=base)
            assert key == (note - base if base <= note < base + 32 else None)
    try:
        parse_midi(b"bad")
    except MidiFormatError:
        pass
    else:
        raise AssertionError("malformed MIDI was accepted")
    print("PASS: MIDI tempo, running status, note events, range mapping and errors")


if __name__ == "__main__":
    main()
