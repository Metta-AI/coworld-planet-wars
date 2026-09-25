"""Complete certified-shape headless episode through private sprite views."""

from pathlib import Path
from sys import argv

from .env import PlanetWarsEnv
from .sprite_view import OBSERVATION_SIZE


with PlanetWarsEnv(Path(argv[1])) as env:
    observations = env.reset(108519, max_ticks=1200, planet_count=47)
    assert len(observations) == 8
    done = False
    while not done:
        observations, rewards, done, info = env.step((4, 3, 7, 0, 12, 8, 6, 10))
        assert all(len(view) == OBSERVATION_SIZE for view in observations)
        assert len(rewards) == 8
    assert info["tick"] == 1200
    assert len(info["scores"]) == 8
    print(f"eight-seat private-sprite episode completed: {info['scores']}")
