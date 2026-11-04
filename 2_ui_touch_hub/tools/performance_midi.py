"""Small dependency-free Standard MIDI File parser for performance guidance.

The parser intentionally emits note events only. Audio rendering remains on
the FPGA audio engine; this module prepares deterministic, absolute-timestamp
events for the UI/gateway path.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import asdict, dataclass
from fractions import Fraction
import json
from pathlib import Path
from typing import Iterable


class MidiFormatError(ValueError):
    """Raised when a Standard MIDI File is malformed or unsupported."""


@dataclass(frozen=True)
class PerformanceEvent:
    time_us: int
    note: int
    velocity: int
    on: bool
    channel: int
    track: int
    tick: int


@dataclass(frozen=True)
class PerformanceSong:
    midi_format: int
    division: int
    duration_us: int
    events: tuple[PerformanceEvent, ...]

    def to_dict(self) -> dict:
        return {
            "format": "performance-midi-v1",
            "midi_format": self.midi_format,
            "division": self.division,
            "duration_us": self.duration_us,
            "events": [asdict(event) for event in self.events],
        }

    def to_json(self, *, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), ensure_ascii=False, indent=indent)


def _need(data: bytes, offset: int, count: int, what: str) -> None:
    if offset < 0 or offset + count > len(data):
        raise MidiFormatError(f"truncated {what} at byte {offset}")


def _u16(data: bytes, offset: int) -> int:
    _need(data, offset, 2, "u16")
    return int.from_bytes(data[offset : offset + 2], "big")


def _u32(data: bytes, offset: int) -> int:
    _need(data, offset, 4, "u32")
    return int.from_bytes(data[offset : offset + 4], "big")


def _vlq(data: bytes, offset: int, end: int) -> tuple[int, int]:
    value = 0
    for _ in range(4):
        if offset >= end:
            raise MidiFormatError("truncated variable-length quantity")
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, offset
    raise MidiFormatError("variable-length quantity exceeds four bytes")


def _parse_track(
    track: bytes, track_index: int
) -> tuple[list[tuple[int, int, int, int, bool, int]], list[tuple[int, int, int, int]], int]:
    """Return notes, tempo changes and final absolute tick.

    Note tuple: (tick, sequence, channel, note, on, velocity).
    Tempo tuple: (tick, sequence, tempo_us_per_quarter, track_index).
    """

    notes: list[tuple[int, int, int, int, bool, int]] = []
    tempos: list[tuple[int, int, int, int]] = []
    pos = 0
    tick = 0
    sequence = 0
    running_status: int | None = None

    while pos < len(track):
        delta, pos = _vlq(track, pos, len(track))
        tick += delta
        if pos >= len(track):
            raise MidiFormatError("track ends after delta time")

        status = track[pos]
        if status & 0x80:
            pos += 1
            if 0x80 <= status <= 0xEF:
                running_status = status
            elif status < 0xF8:
                running_status = None
        elif running_status is not None:
            status = running_status
        else:
            raise MidiFormatError("data byte without running status")

        if status == 0xFF:
            _need(track, pos, 1, "meta event type")
            meta_type = track[pos]
            pos += 1
            length, pos = _vlq(track, pos, len(track))
            _need(track, pos, length, "meta event payload")
            payload = track[pos : pos + length]
            pos += length
            if meta_type == 0x51 and length == 3:
                tempos.append((tick, sequence, int.from_bytes(payload, "big"), track_index))
            sequence += 1
            if meta_type == 0x2F:
                break
            continue

        if status in (0xF0, 0xF7):
            length, pos = _vlq(track, pos, len(track))
            _need(track, pos, length, "sysex payload")
            pos += length
            running_status = None
            sequence += 1
            continue

        # MIDI real-time bytes have no data payload and do not disturb running
        # status. They are ignored by the file parser.
        if status >= 0xF8:
            sequence += 1
            continue

        message_type = status & 0xF0
        channel = status & 0x0F
        if message_type in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
            _need(track, pos, 2, "two-byte MIDI message")
            data1, data2 = track[pos] & 0x7F, track[pos + 1] & 0x7F
            pos += 2
            if message_type == 0x80 or (message_type == 0x90 and data2 == 0):
                notes.append((tick, sequence, channel, data1, False, data2))
            elif message_type == 0x90:
                notes.append((tick, sequence, channel, data1, True, data2))
        elif message_type in (0xC0, 0xD0):
            _need(track, pos, 1, "one-byte MIDI message")
            pos += 1
        else:
            raise MidiFormatError(f"unsupported MIDI status 0x{status:02X}")
        sequence += 1

    return notes, tempos, tick


def parse_midi(data: bytes, *, min_note: int = 21, max_note: int = 108) -> PerformanceSong:
    """Parse a PPQN Standard MIDI File into absolute timed note events."""

    _need(data, 0, 14, "MThd header")
    if data[:4] != b"MThd":
        raise MidiFormatError("missing MThd header")
    header_length = _u32(data, 4)
    if header_length != 6:
        raise MidiFormatError(f"unexpected MThd length {header_length}")
    midi_format = _u16(data, 8)
    track_count = _u16(data, 10)
    division_raw = _u16(data, 12)
    if midi_format not in (0, 1):
        raise MidiFormatError("only MIDI formats 0 and 1 are supported")
    if division_raw & 0x8000:
        raise MidiFormatError("SMPTE time division is not supported")
    division = division_raw
    if division == 0:
        raise MidiFormatError("PPQN division cannot be zero")

    offset = 14
    all_notes: list[tuple[int, int, int, int, bool, int, int]] = []
    all_tempos: list[tuple[int, int, int, int]] = []
    max_tick = 0
    for track_index in range(track_count):
        _need(data, offset, 8, "MTrk header")
        if data[offset : offset + 4] != b"MTrk":
            raise MidiFormatError(f"missing MTrk header for track {track_index}")
        length = _u32(data, offset + 4)
        start = offset + 8
        end = start + length
        _need(data, start, length, f"track {track_index}")
        notes, tempos, track_end = _parse_track(data[start:end], track_index)
        max_tick = max(max_tick, track_end)
        all_notes.extend((*note, track_index) for note in notes)
        all_tempos.extend(tempos)
        offset = end

    tempo_by_tick: dict[int, int] = {0: 500_000}
    for tick, _sequence, tempo, _track in sorted(all_tempos, key=lambda item: item[:2]):
        if tempo <= 0:
            raise MidiFormatError("tempo must be positive")
        tempo_by_tick[tick] = tempo

    tempo_ticks = sorted(tempo_by_tick)
    tempo_segments: list[tuple[int, Fraction, int]] = []
    accumulated = Fraction(0, 1)
    previous_tick = tempo_ticks[0]
    previous_tempo = tempo_by_tick[previous_tick]
    tempo_segments.append((previous_tick, accumulated, previous_tempo))
    for tick in tempo_ticks[1:]:
        accumulated += Fraction((tick - previous_tick) * previous_tempo, division)
        previous_tick = tick
        previous_tempo = tempo_by_tick[tick]
        tempo_segments.append((tick, accumulated, previous_tempo))

    def tick_to_us(tick: int) -> int:
        index = bisect_right(tempo_ticks, tick) - 1
        start_tick, start_us, tempo = tempo_segments[index]
        return int(start_us + Fraction((tick - start_tick) * tempo, division))

    events: list[PerformanceEvent] = []
    for tick, sequence, channel, note, on, velocity, track_index in all_notes:
        if not min_note <= note <= max_note:
            continue
        events.append(
            PerformanceEvent(
                time_us=tick_to_us(tick),
                note=note,
                velocity=velocity,
                on=on,
                channel=channel + 1,
                track=track_index,
                tick=tick,
            )
        )

    events.sort(key=lambda event: (event.time_us, event.on, event.track, event.tick, event.note))
    return PerformanceSong(
        midi_format=midi_format,
        division=division,
        duration_us=tick_to_us(max_tick),
        events=tuple(events),
    )


def parse_midi_file(path: str | Path, **kwargs) -> PerformanceSong:
    return parse_midi(Path(path).read_bytes(), **kwargs)


def note_to_key(note: int, *, base_note: int = 60, key_count: int = 32) -> int | None:
    """Return a chromatic key index or None when the note is out of range."""

    key = note - base_note
    return key if 0 <= key < key_count else None


def song_to_json(path: str | Path, output: str | Path) -> None:
    song = parse_midi_file(path)
    Path(output).write_text(song.to_json() + "\n", encoding="utf-8")


__all__ = [
    "MidiFormatError",
    "PerformanceEvent",
    "PerformanceSong",
    "note_to_key",
    "parse_midi",
    "parse_midi_file",
    "song_to_json",
]
