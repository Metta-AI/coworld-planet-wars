# Planet Wars numeric policy training

The bridge runs the game simulation without a wall-clock delay. Each seat receives the exact private sprite packet built for its ordinary `/player` WebSocket. Actions are the same held button masks. The game still applies inputs, scores, ends matches, and writes hosted results and replays.

Build and check the bridge from this repository root after `nimby sync nimby.lock`:

```bash
nim c --path:src -o:/tmp/planet-training-bridge training/bridge.nim
nim r --path:src training/test_bridge.nim
python -m training.smoke /tmp/planet-training-bridge
python -m training.test_train /tmp/planet-training-bridge
```

`training/test_bridge.nim` checks each seat's packet bytes, action edges, scores, ticks, and game hash against a direct game simulation. The smoke runs an eight-seat, 47-planet, 1,200-tick match and decodes all eight private views. Each feature vector has 386 values: own cursor position, then visibility, ownership, ship count, relative position, planet size, selected ring, and origin ring for each of 48 possible planets. Invisible planets have zero features. The policy has 36 actions: nine directional choices crossed with A and B button states. A fires on a press edge; B stays held. A choice is repeated for six simulation ticks by default.

A bounded CPU policy-gradient run and ordinary player packaging:

```bash
python -m training.train --bridge /tmp/planet-training-bridge --output training/model.npz --total-timesteps 9600 --episode-ticks 1200
docker build -f training/Dockerfile.player -t planet-wars-trained:local .
```

The timestep budget counts seat policy decisions, excluding repeated simulation ticks.
Choose a positive multiple of eight for the eight-seat batch.
A budget ending mid-episode bootstraps the last visible value before the optimizer update.

The NumPy model file is generated locally and ignored by git. `training/player.py` loads it from `PLANET_WARS_MODEL`, connects through `COWORLD_PLAYER_WS_URL`, decodes only its private sprite packets, and sends ordinary two-byte button messages. The Dockerfile packages the generated model. Its one-episode optimizer smoke verifies training and loading mechanics; it does not establish policy strength. Evaluate checkpoints against held-out seeds and bundled Skurge before using one competitively.

## Shared Metta native environment

`training.native_environment:NativePlanetWarsEnvironment` binds this bridge to Metta's `NumericEnvironment` contract.
It exposes all eight seats, 386 private features per seat, 36 ordinary button-mask choices, native reward deltas, and whole-game terminal boundaries.
The bridge binary must be declared as an environment asset. The game remains responsible for simulation and scoring.

From a Metta checkout with `metta-training` installed, check the binding against a second native bridge:

```bash
PYTHONPATH=/path/to/coworld-planet-wars uv run --package metta-training python -m training.test_native_environment /tmp/planet-training-bridge
```

The test compares every observation and reward through complete 120-tick episodes with two and eight seats.
It also verifies terminal boundaries and native-process cleanup. It does not run an optimizer.

Configure the shared pipeline with:

```python
from pathlib import Path
from metta_training.environment import EnvironmentSpec, PythonEnvironmentConfig
from metta_training.evaluation import EvaluationConfig
from metta_training.model_config import FabricConfig
from metta_training.pipeline import NumericTrainingConfig, run_training
from metta_training.policy_bundle import PolicyExportConfig
from metta_training.puffer import BuildConfig, RunConfig

root = Path("/path/to/coworld-planet-wars")
bridge = Path("/tmp/planet-training-bridge")
environment = PythonEnvironmentConfig(
    factory="training.native_environment:NativePlanetWarsEnvironment",
    workers="process",
    startup_parallelism=8,
    options={"config": {"bridge": str(bridge), "game_root": str(root)}},
    spec=EnvironmentSpec(observation_size=386, action_sizes=[36], agents=8),
    assets=[bridge],
    source_modules=["training.native_environment", "training.env", "training.sprite_view"],
)
config = NumericTrainingConfig(
    build=BuildConfig(
        environment="metta_coworld",
        python_environment=environment,
        fabric=FabricConfig(observation_size=386, action_sizes=[36], platform="cuda", options={"atoms": 8}),
    ),
    trainer=RunConfig.synchronous(1024, 64, horizon=16),
    evaluator=EvaluationConfig(seeds=[19, 31], episodes_per_seed=1, timeout_seconds=1200),
    exporter=PolicyExportConfig(),
)
run_training(Path("train_dir/planet-wars-native"), config)
```

Set `PYTHONPATH` to the game checkout when launching that Python program from Metta.
The timestep count includes all seats; eight environments contain 64 agents.
Default episodes preserve the game's 18,000-tick duration and 47 planets.
Native Fabric optimization, checkpoint export, and ordinary-player reload still require execution proof.
The existing NumPy player loads the separate CPU smoke model; it cannot load a Fabric bundle.

The canonical Coworld manifest and eight-Skurge certification roster stay unchanged. No hosted version or policy is published by these commands.
