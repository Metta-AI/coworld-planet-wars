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
