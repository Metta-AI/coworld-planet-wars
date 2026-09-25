"""Package a fixed policy and complete a mixed ordinary-player episode."""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
import time
from pathlib import Path

import numpy as np

from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--skurge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    args.output.mkdir(parents=True, exist_ok=True)
    model = root / "training/smoke-model.npz"
    w1 = np.zeros((128, OBSERVATION_SIZE), dtype=np.float32)
    b1 = np.zeros(128, dtype=np.float32)
    w2 = np.zeros((len(ACTION_MASKS), 128), dtype=np.float32)
    b2 = np.zeros(len(ACTION_MASKS), dtype=np.float32)
    b2[ACTION_MASKS.index(8)] = 1
    np.savez(model, w1=w1, b1=b1, w2=w2, b2=b2)
    subprocess.run(
        [
            "docker",
            "build",
            "-f",
            "training/Dockerfile.player",
            "-t",
            "planet-wars-trained:smoke",
            "--build-arg",
            "MODEL_FILE=training/smoke-model.npz",
            ".",
        ],
        cwd=root,
        check=True,
    )
    results = args.output / "results.json"
    replay = args.output / "replay.bitreplay"
    server_log = (args.output / "server.log").open("w")
    player_log = (args.output / "player.log").open("w")
    skurge_log = (args.output / "skurge.log").open("w")
    port = 18957
    server = subprocess.Popen(
        [
            str(args.server),
            "--host:127.0.0.1",
            f"--port:{port}",
            '--config:{"seed":33,"planetCount":12,"maxTicks":360,"maxGames":1,"num_agents":2}',
            f"--results:{results}",
            f"--save-replay:{replay}",
        ],
        cwd=root,
        stdout=server_log,
        stderr=subprocess.STDOUT,
    )
    player = None
    skurge = None
    try:
        for _ in range(100):
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", port)) == 0:
                    break
            time.sleep(0.1)
        else:
            raise RuntimeError("Planet Wars server did not open its port")
        player = subprocess.Popen(
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "host",
                "-e",
                f"COWORLD_PLAYER_WS_URL=ws://127.0.0.1:{port}/player?name=trained-policy&slot=0",
                "planet-wars-trained:smoke",
            ],
            cwd=root,
            stdout=player_log,
            stderr=subprocess.STDOUT,
        )
        skurge = subprocess.Popen(
            [
                str(args.skurge),
                f"--url:ws://127.0.0.1:{port}/player",
                "--name:skurge",
                "--slot:1",
                "--exit-on-disconnect",
            ],
            cwd=root,
            stdout=skurge_log,
            stderr=subprocess.STDOUT,
        )
        assert server.wait(timeout=30) == 0
        assert player.wait(timeout=10) == 0
        assert skurge.wait(timeout=10) == 0
        data = json.loads(results.read_text())
        assert set(data["names"]) == {"trained-policy", "skurge"}
        assert len(data["scores"]) == 2
        assert replay.stat().st_size > 0
        print(f"mixed container episode complete: {data['names']} {data['scores']}")
    finally:
        for process in (server, player, skurge):
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait()
        for stream in (server_log, player_log, skurge_log):
            stream.close()


if __name__ == "__main__":
    main()
