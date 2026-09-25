"""Portable numeric policy for Planet Wars' ordinary sprite player."""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE


class TrainedPolicy:
    def __init__(self, path: Path) -> None:
        with np.load(path, allow_pickle=False) as weights:
            self.w1 = weights["w1"]
            self.b1 = weights["b1"]
            self.w2 = weights["w2"]
            self.b2 = weights["b2"]
        if self.w1.shape[1] != OBSERVATION_SIZE or self.w2.shape[0] != len(
            ACTION_MASKS
        ):
            raise ValueError(
                "Planet Wars adapter does not match the sprite action protocol"
            )

    def action(self, observation: tuple[float, ...]) -> int:
        features = np.asarray(observation, dtype=np.float32)
        hidden = np.maximum(features @ self.w1.T + self.b1, 0)
        logits = hidden @ self.w2.T + self.b2
        return int(np.argmax(logits))
