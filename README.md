# Planet Wars

<!-- COWORLD-REPO-STATUS:START -->
> [!NOTE]
> Coworld repo status: **incomplete** (`coworld-incomplete`).
> Canonical repository: `Metta-AI/coworld-planet-wars`.
> Manifest path: `coworld_manifest.json`.
> Build path: `Dockerfile`
> Certification: blocked until `uv run coworld certify coworld_manifest.json` passes and the result is recorded.
>
> Missing pieces:
> - [ ] Validate the root concrete manifest against the current Coworld schema.
> - [ ] Run `uv run coworld certify coworld_manifest.json` with the bundled players.
> - [ ] Switch the repo topic to `coworld-complete` after certification passes.
<!-- COWORLD-REPO-STATUS:END -->


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
