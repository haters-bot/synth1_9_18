"""Reference HTTP/WebSocket gateway for the phone performance page.

The gateway is deliberately a thin transport bridge.  It does not synthesize
audio or parse a MIDI file; the browser parses the file and sends the bounded
V1 frames from :mod:`performance_protocol`. With ``--dry-run`` it validates
frames without opening a serial port, and never generates an FPGA ACK.

The hardware deployment needs ``aiohttp`` and ``pyserial`` on the gateway
machine, plus 3.3 V UART adapter TX -> UI F16, adapter RX <- UI F14,
and shared ground. Do not connect this UART to audio E19.
"""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web

from performance_protocol import FrameDecoder, PerformanceFrame


class SerialBridge:
    def __init__(self, port: str | None, baud: int) -> None:
        self.port = port
        self.baud = baud
        self._serial: Any = None

    def write(self, data: bytes) -> None:
        if not self.port:
            return
        if self._serial is None:
            try:
                import serial  # type: ignore
            except ImportError as exc:  # pragma: no cover - hardware-only path
                raise RuntimeError("pyserial is required when --serial is used") from exc
            self._serial = serial.Serial(self.port, self.baud, timeout=0)
        self._serial.write(data)

    def read(self) -> bytes:
        if self._serial is None:
            return b""
        return self._serial.read(min(4096, self._serial.in_waiting))

    def close(self) -> None:
        if self._serial is not None:
            self._serial.close()
            self._serial = None


class Gateway:
    def __init__(self, web_root: Path, bridge: SerialBridge, dry_run: bool) -> None:
        self.web_root = web_root
        self.bridge = bridge
        self.dry_run = dry_run
        self.client_active = False

    async def index(self, _request: web.Request) -> web.StreamResponse:
        return web.FileResponse(self.web_root / "index.html")

    async def websocket(self, request: web.Request) -> web.StreamResponse:
        if self.client_active:
            return web.Response(status=409, text="Only one board session can own the serial link")
        self.client_active = True
        ws = web.WebSocketResponse(max_msg_size=128 * 1024, heartbeat=30)
        await ws.prepare(request)
        decoder = FrameDecoder()
        await ws.send_json({"type": "gateway", "ok": True, "dry_run": self.dry_run})
        async def receive_board() -> None:
            while not ws.closed:
                raw = self.bridge.read()
                if raw:
                    await ws.send_bytes(raw)
                await asyncio.sleep(0.01)
        reader = asyncio.create_task(receive_board())
        try:
            async for message in ws:
                if message.type == WSMsgType.BINARY:
                    raw = bytes(message.data)
                    frames = tuple(decoder.feed(raw))
                    if not frames:
                        await ws.send_json({"type": "error", "message": "incomplete or invalid performance frame"})
                        continue
                    if self.dry_run:
                        # Parser demo only. Never impersonate an FPGA ACK.
                        await ws.send_json({"type": "dry_run", "message": "No board ACK is generated"})
                    else:
                        self.bridge.write(raw)
                elif message.type == WSMsgType.TEXT:
                    await ws.send_json({"type": "error", "message": "V1 gateway accepts binary frames only"})
                elif message.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                    break
        finally:
            reader.cancel()
            try:
                await reader
            except asyncio.CancelledError:
                pass
            self.client_active = False
            await ws.close()
        return ws

    async def shutdown(self, _app: web.Application) -> None:
        self.bridge.close()


def build_app(web_root: Path, bridge: SerialBridge, dry_run: bool) -> web.Application:
    gateway = Gateway(web_root, bridge, dry_run)
    app = web.Application()
    app.router.add_get("/", gateway.index)
    app.router.add_get("/ws", gateway.websocket)
    app.router.add_static("/", web_root, show_index=False)
    app.on_cleanup.append(gateway.shutdown)
    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="Phone performance HTTP/WebSocket gateway")
    parser.add_argument("--serial", help="serial port connected TX -> UI F16, RX <- UI F14")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--web-port", type=int, default=8080)
    parser.add_argument("--dry-run", action="store_true", help="validate frames without opening a serial port")
    args = parser.parse_args()
    if not args.serial and not args.dry_run:
        parser.error("provide --serial or explicitly choose --dry-run")
    root = Path(__file__).resolve().parents[1] / "performance_web"
    app = build_app(root, SerialBridge(args.serial, args.baud), args.dry_run)
    web.run_app(app, host=args.host, port=args.web_port)


if __name__ == "__main__":
    main()
