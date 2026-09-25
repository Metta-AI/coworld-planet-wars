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

Recorded `.bitreplay` files use the native Nim simulation for playback. Open
`/client/replay` on a replay server for the star map, score overview, and
playback controls. The browser page keeps the authoritative sprite stream;
it does not substitute another Planet Wars ruleset.

## Bot

The bundled Nim bot is `skurge`.

```bash
nim c --path:src players/skurge/skurge.nim
./players/skurge/skurge --address:localhost --port:8080
```

## Jev mission trial

Kudzu can trial typed SystemOne decisions at its mission boundary. It sends
only decoded player-visible planet sightings and affordable mission candidates.
The selected mission still becomes ordinary pointer and button input over the
same sprite WebSocket. The bot releases held input before the bounded model call.
Hosted players send Jev calls to the pod's `AWS_ENDPOINT_URL_BEDROCK_RUNTIME`
sidecar with pinned model `typesafe/jev-1.13`; they do not need a TypeSafe key.
The league must allow that model. Direct local trials use `TYPESAFE_API_KEY`
and default to `jev-latest` unless `--model` overrides it.

```bash
nim c -d:ssl --path:src players/kudzu/kudzu.nim
mkdir -m 700 -p /tmp/planet
TYPESAFE_API_KEY=<key> ./players/kudzu/kudzu --address:localhost --port:8080 \
  --systemone --model:jev-latest --journal:/tmp/planet/missions.jsonl
```

The journal is created with mode `0600` and retains exact requests, replies,
model round-trip latency in milliseconds, selected missions, and sent input masks
without the API key. `TYPESAFE_BASE_URL`
may point to a local model stub. After a game that saved results and a replay,
export only replay-verified ship launches to the shared trajectory contract:

```bash
./planet_wars --host:127.0.0.1 --port:8080 \
  --results:/tmp/planet/results.json --save-replay:/tmp/planet/replay.bitreplay
```

```bash
nim c --path:src players/kudzu/mission_export.nim
./players/kudzu/mission_export --journal:/tmp/planet/missions.jsonl \
  --replay:/tmp/planet/replay.bitreplay --results:/tmp/planet/results.json \
  --episode-id:planet-trial-1 --source-revision:$(git rev-parse HEAD) \
  --output:/tmp/planet/complete.jsonl
```

The exporter requires a hash-valid complete replay, an exact input ledger,
and results matching the replay. It writes a mode-`0600` `CompleteEpisode`
JSONL file for `metta-posttrain export-hosted`.

## Numeric policy training

See [training/README.md](training/README.md) for the headless eight-seat bridge,
private sprite observation decoder, bounded optimizer smoke, and ordinary
WebSocket player image.
