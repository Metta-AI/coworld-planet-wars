"""Exercise roster attribution through real authenticated player sockets."""
from __future__ import annotations

import argparse
import asyncio
import json
import socket
from pathlib import Path
from urllib.parse import urlencode, urlsplit

import websockets


async def read_frames(connection):
    count = 0
    async for message in connection:
        assert isinstance(message, bytes)
        count += 1
    return count


async def rejected(url, expected):
    # The pinned HTTP encoder omits the reason phrase on rejected upgrades.
    # Inspect the numeric status instead of accepting an arbitrary handshake error.
    target = urlsplit(url)
    reader, writer = await asyncio.open_connection(target.hostname, target.port)
    try:
        request = (f'GET {target.path}?{target.query} HTTP/1.1\r\nHost: {target.netloc}\r\n'
                   'Connection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\n'
                   'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n')
        writer.write(request.encode())
        await writer.drain()
        status = await asyncio.wait_for(reader.readline(), timeout=3)
        assert status.split()[:2] == [b'HTTP/1.1', str(expected).encode()], status
    finally:
        writer.close()
        await writer.wait_closed()


async def episode(server_binary, output, authenticated, reconnect, assert_order):
    output.mkdir()
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    tokens = ['fixture-zero', 'fixture-one', 'fixture-two']
    config = {'seed': 7313, 'planetCount': 12, 'maxTicks': 180,
              'maxGames': 1, 'num_agents': 3, 'tokens': tokens if authenticated else []}
    command = [str(server_binary), '--host:127.0.0.1', f'--port:{port}',
               '--config:' + json.dumps(config), f'--results:{output / "results.json"}',
               f'--save-replay:{output / "replay.bitreplay"}']
    root = Path(__file__).resolve().parents[1]
    connections, readers = {}, []
    with (output / 'server.log').open('x') as log:
        server = await asyncio.create_subprocess_exec(*command, cwd=root, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if server.returncode is not None:
                    raise RuntimeError('server exited before accepting players')
                with socket.socket() as probe:
                    if probe.connect_ex(('127.0.0.1', port)) == 0:
                        break
                await asyncio.sleep(0.02)
            else:
                raise TimeoutError('server did not open its port')
            base = f'ws://127.0.0.1:{port}/player?'
            if authenticated and assert_order:
                await rejected(base + urlencode({'slot': 0, 'token': tokens[1]}), 403)
            # Slots are addressing fixtures. Strategies never depend on them.
            for slot in [2, 0, 1]:
                query = {'name': f'wire-{slot}'}
                if authenticated:
                    query['token'] = tokens[slot]
                if not authenticated or slot != 2:
                    query['slot'] = slot
                connection = await websockets.connect(base + urlencode(query), proxy=None)
                assert isinstance(await asyncio.wait_for(connection.recv(), timeout=3), bytes)
                connections[slot] = connection
                readers.append(asyncio.create_task(read_frames(connection)))
            # Lobby inputs are intentionally neither applied nor recorded.
            # Send after every client has received its first active scene.
            for slot, connection in connections.items():
                await connection.send(bytes([0x84, {2: 4, 0: 1, 1: 8}[slot]]))
            await asyncio.sleep(0.12)
            for connection in connections.values():
                await connection.send(bytes([0x84, 0]))
            if authenticated and assert_order:
                await rejected(base + urlencode({'slot': 1, 'token': tokens[1]}), 409)
            await asyncio.sleep(1.05)
            await connections[0].close()
            if reconnect:
                await asyncio.sleep(0.12)
                query = {'name': 'reconnected-zero', 'slot': 0, 'token': tokens[0]}
                connection = await websockets.connect(base + urlencode(query), proxy=None)
                assert isinstance(await asyncio.wait_for(connection.recv(), timeout=3), bytes)
                connections[0] = connection
                readers.append(asyncio.create_task(read_frames(connection)))
                await connection.send(bytes([0x84, 0]))
            await asyncio.wait_for(server.wait(), timeout=10)
            assert server.returncode == 0
            await asyncio.gather(*readers)
            result = json.loads((output / 'results.json').read_text())
            expected = ['wire-0', 'wire-1', 'wire-2']
            observed = {'names': result['names'], 'scores': result['scores'],
                        'planets': result['planets'], 'expected_names': expected,
                        'roster_order_correct': result['names'] == expected,
                        'reconnect': reconnect, 'authenticated': authenticated}
            (output / 'observed.json').write_text(json.dumps(observed, indent=2))
            if assert_order:
                assert result['names'] == expected, observed
                assert all(len(result[key]) == 3 for key in ['scores', 'names', 'win', 'ships', 'planets'])
                assert result['planets'] == [0, 1, 1]
                assert result['scores'][0] < min(result['scores'][1:])
            else:
                assert result['names'] != expected, 'Baseline no longer reproduces the attribution defect'
            return observed
        finally:
            for connection in connections.values():
                await connection.close()
            if server.returncode is None:
                server.terminate()
                await asyncio.wait_for(server.wait(), timeout=5)
            await asyncio.gather(*readers, return_exceptions=True)


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', action='store_true')
    args = parser.parse_args()
    args.output.mkdir()
    cases = [('authenticated', True, False)] if args.baseline else [
        ('authenticated', True, False), ('reconnect', True, True), ('local', False, False)]
    rows = []
    for label, auth, reconnect in cases:
        row = await episode(args.server.resolve(), args.output / label, auth, reconnect, not args.baseline)
        rows.append({'case': label, **row})
    (args.output / 'summary.json').write_text(json.dumps(rows, indent=2))
    print(json.dumps(rows))


if __name__ == '__main__':
    asyncio.run(main())
