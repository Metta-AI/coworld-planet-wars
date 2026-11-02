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

## Player identities and results

The submitted roster slot is a protocol address, independent of native join order.
With configured tokens, a token-only connection resolves to that token's slot;
an explicit slot must match its token. A simultaneous duplicate claim is rejected.
A reconnect keeps its existing episode actor and score, without a fresh spawn.

Result names, scores, wins, planets and ships use roster order, including empty
rows for missing participants. Replay joins retain the resolved slot.
`replayResultsJson` reproduces this boundary while historical unmapped replays
keep their original native-order results. Simulation order and strategy are unchanged.

The native test suite includes result-mapping checks. To exercise the server
through real sockets, use Python with `websockets` 15 and a fresh output directory:

```bash
qa_root=$(mktemp -d /tmp/planet-wars-roster.XXXXXX)
nim c --threads:on --path:src --parallelBuild:1 --out:"$qa_root/server" src/planet_wars.nim
nim c --path:src --parallelBuild:1 --out:"$qa_root/replay-check" tests/roster_replay.nim
python tests/roster_wire.py --server "$qa_root/server" --output "$qa_root/wire"
for scenario in authenticated reconnect local; do
  "$qa_root/replay-check" "$qa_root/wire/$scenario/replay.bitreplay" "$qa_root/wire/$scenario/results.json"
done
```

## Opt-in replay presentation experiment

`experiments/presentation_viewer.nim` draws a copied public replay snapshot with
Polyworld shapes. It is a finite native viewer; the Coworld package continues to
use the existing sprite viewer. Production builds do not import this adapter.

Use the game dependencies in `nimby.lock`. For this renderer only, resolve
Polyworld `449ad184052567c30fa54c269ef45ff8c9e8e29b` and Shady
`c899f7cd17dbe7021d6e3aa2908e6de6549c47f1` into separate checkouts. The game’s
older Shady pin lacks the renderer’s `glsl4Desktop` target. Supply those two
`src` paths to Nim without changing the game lockfile or shared dependency cache.

From the repository root, using Nim 2.2.4 and one compiler worker:

```bash
nim c -d:release --parallelBuild:1 --path:src experiments/presentation_replay_proof.nim
experiments/presentation_replay_proof /path/to/replay.bitreplay
nim c -d:release --parallelBuild:1 --path:src \
  --path:"$PLANET_POLYWORLD_ROOT/src" --path:"$PLANET_SHADY_ROOT/src" \
  experiments/presentation_viewer.nim
experiments/presentation_viewer /path/to/replay.bitreplay 313 /path/to/frame.png 960 540
```

The proof checks recorded hashes, complete simulation state before and after
snapshot construction, coordinate picking at three viewport sizes, and replay
seeks. `experiments/record_conquest_fixture.nim` can generate a separate fixture
using ordinary input masks, joins, a departure, and chat.

The renderer exits after 120 frames. Its mouse hover selects the nearest planet.
It does not implement live play, hosted viewer controls, or production art.
Small ships and overlapping routes remain difficult to distinguish at 320×240.
