"""Fast two-seat Planet Wars training episodes with ordinary wire actions."""

from __future__ import annotations

import base64
import json
import subprocess
from pathlib import Path

from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE, SpriteView


class PlanetWarsEnv:
    """Every seat sees only its private sprite stream and chooses an input mask."""

    def __init__(
        self, bridge: Path, player_count: int = 8, game_root: Path | None = None
    ) -> None:
        self.player_count = player_count
        root = game_root or Path(__file__).resolve().parent.parent
        self.process = subprocess.Popen(
            [str(bridge), str(root)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        self.views = [SpriteView(f"training-{seat}") for seat in range(player_count)]

    def __enter__(self) -> PlanetWarsEnv:
        return self

    def __exit__(self, *_: object) -> None:
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait()

    def _request(self, command: dict[str, object]) -> dict[str, object]:
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.process.stdin.write(json.dumps(command) + "\n")
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def _observations(self, reply: dict[str, object]) -> tuple[tuple[float, ...], ...]:
        packets = reply["observations"]
        assert isinstance(packets, list) and len(packets) == self.player_count
        for view, packet in zip(self.views, packets, strict=True):
            assert isinstance(packet, str)
            view.apply(base64.b64decode(packet))
        observations = tuple(view.features() for view in self.views)
        assert all(len(item) == OBSERVATION_SIZE for item in observations)
        return observations

    def reset(
        self, seed: int, max_ticks: int = 18_000, planet_count: int = 47
    ) -> tuple[tuple[float, ...], ...]:
        self.views = [
            SpriteView(f"training-{seat}") for seat in range(self.player_count)
        ]
        reply = self._request(
            {
                "cmd": "reset",
                "seed": seed,
                "max_ticks": max_ticks,
                "planet_count": planet_count,
                "player_count": self.player_count,
            }
        )
        return self._observations(reply)

    def step(
        self, actions: tuple[int, ...], repeat: int = 6
    ) -> tuple[tuple[tuple[float, ...], ...], tuple[int, ...], bool, dict[str, object]]:
        assert len(actions) == self.player_count
        masks = [ACTION_MASKS[action] for action in actions]
        reply = self._request({"cmd": "step", "masks": masks, "repeat": repeat})
        observations = self._observations(reply)
        rewards = reply["rewards"]
        assert isinstance(rewards, list) and len(rewards) == self.player_count
        return (
            observations,
            tuple(int(reward) for reward in rewards),
            bool(reply["done"]),
            {
                "tick": reply["tick"],
                "scores": reply["scores"],
            },
        )
