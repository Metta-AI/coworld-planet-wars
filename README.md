# Planet Wars

Coworld strategy game where players conquer planets and launch ships across
a tiny star map.

## Coworld package

This repository owns the Coworld manifest template and every image build declared by it:

```bash
coworld build --version 0.1.4
coworld certify dist/coworld_manifest.json
coworld upload-coworld dist/coworld_manifest.json
```

## Running

```bash
nimble build
./planet_wars --host:0.0.0.0 --port:8080
```

Open `http://localhost:8080/client/global` to spectate.

## Bot

The bundled Nim bot is `skurge`.

```bash
nim c --path:src players/skurge/skurge.nim
./players/skurge/skurge --address:localhost --port:8080
```

Kudzu can trial typed SystemOne decisions at its mission boundary. It sends
only decoded player-visible planet sightings and affordable mission candidates.
The selected mission still becomes ordinary pointer and button input over the
same sprite WebSocket. The bot releases held input before the bounded model call.

```bash
nim c -d:ssl --path:src players/kudzu/kudzu.nim
TYPESAFE_API_KEY=<key> ./players/kudzu/kudzu --address:localhost --port:8080 \
  --systemone --model:jev-latest --journal:mission-decisions.jsonl
```

The journal is created with mode `0600` and retains exact requests, replies,
and selected missions without the API key. `TYPESAFE_BASE_URL` may point to a
local model stub. The journal currently records model intents; a game-result
join and completed trajectory export are needed before posttraining labels can
be selected from Planet Wars.
