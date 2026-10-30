from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from performance_protocol import (  # noqa: E402
    FrameDecoder,
    PerformanceProtocolError,
    TYPE_EVENT_BATCH,
    TYPE_PLAY,
    WireEvent,
    decode_event_batch,
    encode_event_batch,
    encode_frame,
)


def main() -> None:
    events = (
        WireEvent(0, 60, 100, True),
        WireEvent(500, 60, 0, False),
        WireEvent(500, 64, 80, True),
    )
    frame = encode_event_batch(events, sequence=7)
    decoder = FrameDecoder()
    assert list(decoder.feed(frame[:3])) == []
    parsed = list(decoder.feed(frame[3:]))
    assert len(parsed) == 1
    assert parsed[0].frame_type == TYPE_EVENT_BATCH
    assert parsed[0].sequence == 7
    assert decode_event_batch(parsed[0].payload) == events

    # A bad CRC is discarded without poisoning the following valid frame.
    bad = bytearray(encode_frame(TYPE_PLAY, 8))
    bad[-1] ^= 0x40
    assert list(decoder.feed(bytes(bad) + encode_frame(TYPE_PLAY, 9))) == [
        parsed_frame(0x20, 9, b"")
    ]

    try:
        encode_event_batch([WireEvent(0, 60, 100, True)] * 9)
    except PerformanceProtocolError:
        pass
    else:
        raise AssertionError("oversized event batch was accepted")
    print("PASS: performance frame CRC, fragmentation, recovery and event batches")


def parsed_frame(frame_type: int, sequence: int, payload: bytes):
    # Importing the dataclass only in the assertion keeps the fixture readable.
    from performance_protocol import PerformanceFrame

    return PerformanceFrame(frame_type, sequence, payload)


if __name__ == "__main__":
    main()
