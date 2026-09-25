# Planet Wars numeric policy training

The bridge runs the game simulation without a wall-clock delay. Each seat receives the exact private sprite packet built for its ordinary `/player` WebSocket. Actions are the same held button masks. The game still applies inputs, scores, ends matches, and writes hosted results and replays.

Build and check the bridge from this repository root after `nimby sync nimby.lock`:

```bash
nim c --path:src -o:/tmp/planet-training-bridge training/bridge.nim
nim r --path:src training/test_bridge.nim
python -m training.smoke /tmp/planet-training-bridge
```

`training/test_bridge.nim` checks each seat's packet bytes, action edges, scores, ticks, and game hash against a direct game simulation. The smoke runs an eight-seat, 47-planet, 1,200-tick match and decodes all eight private views. Each feature vector has 386 values: own cursor position, then visibility, ownership, ship count, relative position, planet size, selected ring, and origin ring for each of 48 possible planets. Invisible planets have zero features. The policy has 36 actions: nine directional choices crossed with A and B button states. A fires on a press edge; B stays held. A choice is repeated for six simulation ticks by default.

A bounded CPU policy-gradient run and ordinary player packaging:

```bash
python -m training.train --bridge /tmp/planet-training-bridge --output training/model.npz --total-timesteps 9600 --episode-ticks 1200
docker build -f training/Dockerfile.player -t planet-wars-trained:local .
```

The NumPy model file is generated locally and ignored by git. `training/player.py` loads it from `PLANET_WARS_MODEL`, connects through `COWORLD_PLAYER_WS_URL`, decodes only its private sprite packets, and sends ordinary two-byte button messages. The Dockerfile packages the generated model. Its one-episode optimizer smoke verifies training and loading mechanics; it does not establish policy strength. Evaluate checkpoints against held-out seeds and bundled Skurge before using one competitively.

The canonical Coworld manifest and eight-Skurge certification roster stay unchanged. No hosted version or policy is published by these commands.
