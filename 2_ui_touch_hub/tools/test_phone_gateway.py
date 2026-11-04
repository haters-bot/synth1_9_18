"""Optional computer bridge: only real FPGA bytes may count as ACKs."""
import asyncio
from pathlib import Path
from aiohttp.test_utils import TestClient, TestServer
from aiohttp import WSMsgType
from performance_gateway import build_app
from performance_protocol import encode_frame, TYPE_HELLO, TYPE_STATUS


class Bridge:
    def __init__(self):
        self.written=[]
        self.incoming=b""
    def write(self,data):self.written.append(data)
    def read(self):
        result=self.incoming;self.incoming=b"";return result
    def close(self):pass


async def main():
    bridge=Bridge();root=Path(__file__).resolve().parents[1]/"performance_web"
    async with TestClient(TestServer(build_app(root,bridge,False))) as client:
        ws=await client.ws_connect("/ws");await ws.receive_json()
        request=encode_frame(TYPE_HELLO,3);await ws.send_bytes(request)
        await asyncio.sleep(.04)
        assert bridge.written==[request]
        response=await client.get("/ws");assert response.status==409
        ack=encode_frame(TYPE_STATUS,3,bytes(22));bridge.incoming=ack
        message=await ws.receive(timeout=1);assert message.type==WSMsgType.BINARY and message.data==ack
        await ws.close()
    bridge=Bridge()
    async with TestClient(TestServer(build_app(root,bridge,True))) as client:
        ws=await client.ws_connect("/ws");await ws.receive_json()
        await ws.send_bytes(encode_frame(TYPE_HELLO,1))
        assert (await ws.receive_json())["type"]=="dry_run" and not bridge.written
        await ws.close()
    print("PASS: gateway forwards real board binary ACK only, single session ownership, dry-run never impersonates FPGA")


if __name__=="__main__":asyncio.run(main())
