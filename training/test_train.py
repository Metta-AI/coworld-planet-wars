"""Check the real bridge's optimizer budget and exported policy reload."""

from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from sys import argv
from tempfile import TemporaryDirectory

import numpy as np
import torch

from .policy import TrainedPolicy
from .sprite_view import OBSERVATION_SIZE
from .train import train

torch.set_num_threads(2)
with TemporaryDirectory() as directory:
    for budget, episode_ticks, terminal in ((32, 1200, False), (160, 120, True)):
        path = Path(directory) / f"model-{budget}.npz"
        output = StringIO()
        with redirect_stdout(output):
            train(Path(argv[1]), path, seed=7, total_timesteps=budget, episode_ticks=episode_ticks)
        lines = output.getvalue().splitlines()
        assert len(lines) == 1, lines
        assert f"agent_steps={budget} terminal={terminal}" in lines[0], lines
        with np.load(path, allow_pickle=False) as weights:
            assert all(np.isfinite(weights[name]).all() for name in weights.files)
        policy = TrainedPolicy(path)
        assert 0 <= policy.action((0.0,) * OBSERVATION_SIZE) < 36
        print(lines[0])
print("real optimizer budgets and exported reload passed")
