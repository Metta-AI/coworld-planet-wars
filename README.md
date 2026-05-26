# Planet Wars

Coworld strategy game where players conquer planets and launch ships across
a tiny star map.

## Running

```bash
nimble build
./planet_wars --address:0.0.0.0 --port:8080
```

Open `http://localhost:8080/client/global` to spectate.

## Bot

The bundled Nim bot is `skurge`.

```bash
nim c --path:src players/skurge/skurge.nim
./players/skurge/skurge --address:localhost --port:8080
```
