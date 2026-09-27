"""Planet Wars' private sprite bridge as a shared Metta numeric environment."""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
from pydantic import Field

from metta_training.environment import EnvironmentContext, EnvironmentSpec, NumericObservation, NumericTransition
from metta_training.game import Record

from .env import PlanetWarsEnv
from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE


class PlanetWarsSettings(Record):
    bridge: Path
    game_root: Path
    player_count: int = Field(default=8, ge=2, le=8)
    episode_ticks: int = Field(default=18_000, gt=0)
    planet_count: int = Field(default=47, ge=1, le=47)
    repeat: int = Field(default=6, gt=0)


class EpisodeInfo(Record):
    tick: int = Field(ge=0)
    scores: list[int]


class NativePlanetWarsEnvironment:
    """All seats train on the exact observations and held masks used by players."""

    def __init__(self, config: dict[str, object], *, context: EnvironmentContext) -> None:
        self.config = PlanetWarsSettings.model_validate(config)
        if self.config.bridge not in context.assets:
            raise ValueError("Declare the native bridge in the environment assets")
        self.spec = EnvironmentSpec(
            observation_size=OBSERVATION_SIZE,
            action_sizes=[len(ACTION_MASKS)],
            agents=self.config.player_count,
        )
        self.env = PlanetWarsEnv(self.config.bridge, self.config.player_count, self.config.game_root)
        self.active = False

    def encode(self, observations: tuple[tuple[float, ...], ...]) -> NumericObservation:
        values = np.asarray(observations, dtype=np.float32)
        if values.shape != (self.spec.agents, self.spec.observation_size):
            raise ValueError("Private observation dimensions differ from the declared environment")
        return NumericObservation(
            values=values,
            action_masks=np.ones((self.spec.agents, len(ACTION_MASKS)), dtype=np.bool_),
        )

    def reset(self, seed: str) -> NumericObservation:
        numeric_seed = int.from_bytes(hashlib.sha256(seed.encode()).digest()[:8], "little") & ((1 << 63) - 1)
        observations = self.env.reset(numeric_seed, self.config.episode_ticks, self.config.planet_count)
        self.active = True
        return self.encode(observations)

    def step(self, actions: list[list[int]]) -> NumericTransition:
        if not self.active:
            raise ValueError("Reset the environment before taking a step")
        if len(actions) != self.spec.agents or any(
            len(action) != 1 or not 0 <= action[0] < len(ACTION_MASKS) for action in actions
        ):
            raise ValueError("Each seat must supply one legal action index")
        observations, rewards, done, raw_info = self.env.step(
            tuple(action[0] for action in actions), self.config.repeat
        )
        info = EpisodeInfo.model_validate(raw_info)
        if len(rewards) != self.spec.agents or len(info.scores) != self.spec.agents:
            raise ValueError("Native reward and score counts differ from the declared seats")
        self.active = not done
        return NumericTransition(
            observation=self.encode(observations),
            rewards=list(rewards),
            terminated=[done] * self.spec.agents,
            episode_done=done,
            score=info.scores[0],
            perf=float(info.scores[0] == max(info.scores)),
        )

    def close(self) -> None:
        self.active = False
        self.env.close()
