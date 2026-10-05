# Planet Wars

A BitWorld strategy game where eight players conquer planets and launch ships
across a tiny star map. This repository implements its own Nim simulation and
BitWorld sprite protocol.

This is not a verified port of Simon Lucas’s Planet Wars RTS engine. Upstream
bot compatibility, rules parity, and use of the AAMAS agent pool have not been
established. Community evaluations should identify this game as the BitWorld
adaptation; results do not establish performance in the upstream competition.

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

## Numeric policy training

See [training/README.md](training/README.md) for the headless eight-seat bridge,
private sprite observation decoder, bounded optimizer smoke, and ordinary
WebSocket player image.
