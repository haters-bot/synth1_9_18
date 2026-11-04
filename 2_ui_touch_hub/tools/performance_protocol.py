"""Binary V1 transport used by the phone/native shell and UI FPGA.

2026-10-30 current wiring: module TXD -> UI F16, UI F14 -> module RXD.
Current bidirectional ACK/audio extension is documented in
doc/HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md. The historical gateway
description below is retained as background, not current wiring guidance.

The phone speaks WebSocket to a gateway.  The gateway forwards these frames
over the UI board's unused debug UART RX (E13, 3.3 V TTL).  The protocol is
deliberately independent of the audio board: E19 remains the physical MIDI
keyboard input on the audio board.

Frame layout (little endian where a field is wider than one byte)::

    A5 version type sequence length_lo length_hi payload... crc_lo crc_hi

CRC-16/CCITT-FALSE covers ``version`` through the last payload byte.  The
current FPGA parser accepts payloads up to 64 bytes.  An event batch contains
up to eight fixed eight-byte records::

    time_ms[31:0], note[7:0], velocity[7:0], flags[0]=on, reserved[7:1]

The design uses milliseconds for the on-board LED scheduler.  The original
MIDI event timestamp remains available in the browser/gateway for diagnostics.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Iterator

SYNC = 0xA5
VERSION = 0x01
MAX_PAYLOAD = 64
EVENT_BYTES = 8
MAX_BATCH_EVENTS = MAX_PAYLOAD // EVENT_BYTES

TYPE_HELLO = 0x01
TYPE_SONG_CLEAR = 0x10
TYPE_SONG_BEGIN = 0x11
TYPE_EVENT_BATCH = 0x12
TYPE_SONG_END = 0x13
TYPE_PLAY = 0x20
TYPE_PAUSE = 0x21
TYPE_STOP = 0x22
TYPE_MANUAL_NOTE = 0x30
TYPE_RECORD_START = 0x40
TYPE_RECORD_STOP = 0x41
TYPE_STATUS = 0x70
TYPE_ERROR = 0x7F


class PerformanceProtocolError(ValueError):
    """Raised for malformed or unsupported performance frames."""


def crc16_ccitt(data: bytes, crc: int = 0xFFFF) -> int:
    """Return CRC-16/CCITT-FALSE for *data*."""

    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def _u16(value: int) -> bytes:
    if not 0 <= value <= 0xFFFF:
        raise PerformanceProtocolError(f"u16 out of range: {value}")
    return value.to_bytes(2, "little")


def _u32(value: int) -> bytes:
    if not 0 <= value <= 0xFFFFFFFF:
        raise PerformanceProtocolError(f"u32 out of range: {value}")
    return value.to_bytes(4, "little")


def encode_frame(frame_type: int, sequence: int, payload: bytes = b"") -> bytes:
    """Encode one complete wire frame."""

    if not 0 <= frame_type <= 0xFF:
        raise PerformanceProtocolError(f"frame type out of range: {frame_type}")
    if not 0 <= sequence <= 0xFF:
        raise PerformanceProtocolError(f"sequence out of range: {sequence}")
    if len(payload) > MAX_PAYLOAD:
        raise PerformanceProtocolError(f"payload exceeds {MAX_PAYLOAD} bytes")
    body = bytes((VERSION, frame_type, sequence)) + _u16(len(payload)) + payload
    crc = crc16_ccitt(body)
    return bytes((SYNC,)) + body + crc.to_bytes(2, "little")


def encode_song_begin(duration_ms: int, event_count: int, sequence: int = 0) -> bytes:
    return encode_frame(TYPE_SONG_BEGIN, sequence, _u32(duration_ms) + _u16(event_count))


def encode_event_batch(events: Iterable["WireEvent"], sequence: int = 0) -> bytes:
    events = tuple(events)
    if not 1 <= len(events) <= MAX_BATCH_EVENTS:
        raise PerformanceProtocolError(f"event batch must contain 1..{MAX_BATCH_EVENTS} events")
    payload = bytearray()
    for event in events:
        if not 0 <= event.note <= 127 or not 0 <= event.velocity <= 127:
            raise PerformanceProtocolError("MIDI note and velocity must be 0..127")
        payload += _u32(event.time_ms)
        payload += bytes((event.note, event.velocity, 1 if event.on else 0, 0))
    return encode_frame(TYPE_EVENT_BATCH, sequence, bytes(payload))


@dataclass(frozen=True)
class WireEvent:
    time_ms: int
    note: int
    velocity: int
    on: bool


@dataclass(frozen=True)
class PerformanceFrame:
    frame_type: int
    sequence: int
    payload: bytes


class FrameDecoder:
    """Incremental decoder suitable for a UART or WebSocket byte stream."""

    def __init__(self, *, max_payload: int = MAX_PAYLOAD) -> None:
        self.max_payload = max_payload
        self._buffer = bytearray()

    def feed(self, data: bytes) -> Iterator[PerformanceFrame]:
        self._buffer.extend(data)
        while True:
            try:
                start = self._buffer.index(SYNC)
            except ValueError:
                self._buffer.clear()
                return
            if start:
                del self._buffer[:start]
            if len(self._buffer) < 8:
                return
            version = self._buffer[1]
            frame_type = self._buffer[2]
            sequence = self._buffer[3]
            length = int.from_bytes(self._buffer[4:6], "little")
            if version != VERSION or length > self.max_payload:
                del self._buffer[:1]
                continue
            total = 1 + 5 + length + 2
            if len(self._buffer) < total:
                return
            body = bytes(self._buffer[1 : 6 + length])
            received = int.from_bytes(self._buffer[6 + length : total], "little")
            del self._buffer[:total]
            if crc16_ccitt(body) != received:
                continue
            yield PerformanceFrame(frame_type, sequence, body[5:])


def decode_event_batch(payload: bytes) -> tuple[WireEvent, ...]:
    if not payload or len(payload) % EVENT_BYTES:
        raise PerformanceProtocolError("event batch length is not a multiple of eight")
    if len(payload) > MAX_PAYLOAD:
        raise PerformanceProtocolError("event batch exceeds parser capacity")
    events = []
    for offset in range(0, len(payload), EVENT_BYTES):
        time_ms = int.from_bytes(payload[offset : offset + 4], "little")
        note = payload[offset + 4]
        velocity = payload[offset + 5]
        flags = payload[offset + 6]
        if note > 127 or velocity > 127:
            raise PerformanceProtocolError("event note or velocity is out of range")
        events.append(WireEvent(time_ms, note, velocity, bool(flags & 1)))
    return tuple(events)


__all__ = [
    "EVENT_BYTES",
    "FrameDecoder",
    "MAX_BATCH_EVENTS",
    "MAX_PAYLOAD",
    "PerformanceFrame",
    "PerformanceProtocolError",
    "SYNC",
    "TYPE_EVENT_BATCH",
    "TYPE_HELLO",
    "TYPE_MANUAL_NOTE",
    "TYPE_PAUSE",
    "TYPE_PLAY",
    "TYPE_RECORD_START",
    "TYPE_RECORD_STOP",
    "TYPE_SONG_BEGIN",
    "TYPE_SONG_CLEAR",
    "TYPE_SONG_END",
    "TYPE_STATUS",
    "TYPE_STOP",
    "VERSION",
    "WireEvent",
    "crc16_ccitt",
    "decode_event_batch",
    "encode_event_batch",
    "encode_frame",
    "encode_song_begin",
]
