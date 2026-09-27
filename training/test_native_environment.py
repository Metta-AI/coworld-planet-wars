"""Compare the shared training binding to an independent real native bridge."""

import hashlib
from pathlib import Path
from sys import argv
from tempfile import TemporaryDirectory

import numpy as np

from metta_training.environment import EnvironmentContext

from .env import PlanetWarsEnv
from .native_environment import NativePlanetWarsEnvironment

bridge = Path(argv[1]).resolve()
root = Path(__file__).resolve().parent.parent
with TemporaryDirectory() as directory:
    for players in (2, 8):
        context = EnvironmentContext(
            seed=7, index=0, mode="evaluate", output=Path(directory), assets=frozenset({bridge})
        )
        environment = NativePlanetWarsEnvironment(
            {"bridge": bridge, "game_root": root, "player_count": players, "episode_ticks": 120},
            context=context,
        )
        try:
            with PlanetWarsEnv(bridge, players, root) as oracle:
                seed = "heldout-19"
                numeric_seed = int.from_bytes(hashlib.sha256(seed.encode()).digest()[:8], "little") & ((1 << 63) - 1)
                expected = oracle.reset(numeric_seed, max_ticks=120)
                observed = environment.reset(seed)
                np.testing.assert_array_equal(observed.values, np.asarray(expected, dtype=np.float32))
                for step in range(20):
                    actions = [(step * 7 + seat) % 36 for seat in range(players)]
                    expected, rewards, done, info = oracle.step(tuple(actions))
                    transition = environment.step([[action] for action in actions])
                    np.testing.assert_array_equal(transition.observation.values, np.asarray(expected, dtype=np.float32))
                    assert np.asarray(transition.observation.action_masks).all()
                    assert transition.rewards == list(rewards)
                    assert transition.terminated == [done] * players
                    assert transition.episode_done == done
                    assert transition.score == info["scores"][0]
                    assert done == (step == 19)
                assert info["tick"] == 120
                assert not environment.active
        finally:
            environment.close()
        assert environment.env.process.poll() is not None
        print(f"{players} seats: 20 exact native transitions, terminal boundary and process cleanup verified")
