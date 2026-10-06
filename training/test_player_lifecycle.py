"""Exercise game closure while a real ordinary player's inference is pending."""

from __future__ import annotations

import asyncio
import os
import struct
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Event, Thread

from websockets.asyncio.server import serve

from .numeric_policy import ChoiceRequest, ChoiceResponse


async def main() -> None:
    for close_code in (1000, 1011):
        requested = Event()
        released = Event()

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                request = ChoiceRequest.model_validate_json(
                    self.rfile.read(int(self.headers["Content-Length"]))
                )
                assert request.seat == 0 and request.decision_id == 1
                requested.set()
                assert released.wait(10)
                body = ChoiceResponse(choice=16).model_dump_json().encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = Thread(target=http.serve_forever)
        thread.start()

        async def game(socket) -> None:
            label = b"player name trained-policy"
            packet = (
                b"\x01"
                + struct.pack("<HHHI", 1, 4, 4, 0)
                + struct.pack("<H", len(label))
                + label
            )
            for object_id in (13001, 12001):
                packet += b"\x02" + struct.pack("<HhhhBH", object_id, 10, 10, 0, 0, 1)
            await socket.send(packet)
            assert await asyncio.to_thread(requested.wait, 10)
            await socket.close(code=close_code)
            released.set()

        try:
            async with serve(game, "127.0.0.1", 0) as server:
                port = server.sockets[0].getsockname()[1]
                env = dict(
                    os.environ,
                    COWORLD_PLAYER_WS_URL=f"ws://127.0.0.1:{port}/player",
                    PLAYER_NUMERIC_URL=f"http://127.0.0.1:{http.server_port}/choice",
                )
                process = await asyncio.create_subprocess_exec(
                    sys.executable,
                    "-m",
                    "training.player",
                    env=env,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                _, stderr = await asyncio.wait_for(process.communicate(), 20)
                assert requested.is_set()
                if close_code == 1000:
                    assert process.returncode == 0, stderr.decode()
                else:
                    assert (
                        process.returncode != 0 and b"ConnectionClosedError" in stderr
                    ), stderr.decode()
        finally:
            released.set()
            http.shutdown()
            thread.join()
            http.server_close()
    print("Normal game closure exits zero; abnormal closure remains an error.")


if __name__ == "__main__":
    asyncio.run(main())
