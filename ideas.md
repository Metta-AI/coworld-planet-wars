# Skurge improvement log

Goal: top of the Planet Wars leaderboard.
Dashboard: https://softmaxdash-nginx.tail0f4a29.ts.net/league/planet-wars
Our xp view: https://softmaxdash-nginx.tail0f4a29.ts.net/league/planet-wars/xp?sel=p%3Aandre-von-houck&top=3

## Hard constraints

- **Qualification gate.** A submitted policy only becomes champion after a
  self-play episode (8 identical clones) in which one seat ends owning
  **all 47 planets**. One failure disqualifies immediately; `max_attempts: 3`
  does not grant three tries at the gate. The verdict text lives in the
  membership `notes` field — NOT in the episodes API, which returns 0 rows
  for qualification episodes and misled me into calling it an infra bug.
- Champion today is `planet-wars-skurge:v1`. It captures **9/47** planets in
  two minutes with no opponent at all. Best experimental build: ~25-28/47.
- Score is `ownedPlanets^2` per second. Ships contribute nothing directly.
- Neutrals never regrow; owned planets grow 1 ship per interval
  (small ~120 ticks, medium ~90, large ~60).
- Cursor cannot move diagonally: `applyInput` takes left/right OR up/down.
- Held B accelerates from 1 ship/6 ticks to 1 ship/tick after ~50 ticks.

## Measurement

`scratchpad/bench_sweep.py` — solo bot, 47 neutrals, no opponent.
Reports coverage@2min and sweepTick. The server only writes results when a
game ENDS, so it runs a LADDER of games at 1800/3600/5400/7200 ticks and
reads each final count. Tick limits are exact under load, so the ladder
parallelises safely.

### Measurement methodology — read this before trusting any number

1. **The benchmark is DETERMINISTIC per seed** provided every concurrent
   game runs the SAME number of ticks. Ten repeats of one build on one
   seed gave range 25..25. Repetition therefore measures nothing.
2. **The ladder (mixed 1800/3600/5400/7200) injects its own noise.** Short
   games finish early, CPU load shifts mid-run, the bot misses ticks, and
   identical builds diverge by up to 5 planets. Never compare builds with
   it — use it only for a single build's growth curve.
3. **Real variance is MAP LAYOUT.** Correct design: one run per seed,
   uniform duration, paired between builds, sign test over per-seed
   differences. That is `scratchpad/seed_bench.py <port> <seeds> <a> <b>`.
4. **12 maps is about the minimum.** Three seeds produced two confident
   conclusions that both evaporated at 12.

Two results that did NOT survive this: garrison size (+3 on the tuning
seed, +0.7 over three) and v33 origin ranking (+3 on three hand-picked
seeds, **+0.6 with p=0.51 over twelve**).

Phase profile of a solo run (instrument `bot.intent` with the mission phase):

| phase | share |
|---|---|
| PhaseGoTarget | ~42% |
| PhaseGoOrigin | ~28% |
| waiting | ~17% |
| PhaseSend | ~12% |

Never ship-starved: at 25 planets income is ~17 ships/sec against a ~9-ship
capture cost, yet it manages one capture per ~4s against a ~1.4s floor.

Planning distances (instrument `planMission` to echo chosen distances):

Profile BEFORE the v33 origin fix:

| plan type | share | cursor travel |
|---|---|---|
| chained (camp) | 16% | 77px |
| full replan | 84% | 141px to origin + 82px to target |

Profile AFTER v33 (27.7 planets):

| phase | share |     | plan type | share | travel |
|---|---|---|---|---|---|
| PhaseGoTarget | 45.9% | | chained | 29% | 64px |
| PhaseGoOrigin | 35.3% | | full replan | 71% | 124 + 100 = 224px |
| PhaseSend | 9.5% | | | | |
| waiting | 8.3% | | | | |

**Target: raise the chained share further; travel is still 81% of the clock.**

## Tried

| # | change | result |
|---|---|---|
| 1 | Read ship counts from per-digit text objects (v2) | correct, but no win vs v1 (50/99 paired) |
| 2 | Sized bursts + chained captures (v3) | 50/99 paired vs v1 — noise |
| 3 | kudzu-style global origin/target pairing (v4) | +18.7% mean score, rank delta inconclusive; DISQUALIFIED at gate |
| 4 | Cursor-aware travel cost (v5) | inconclusive |
| 5 | Enemy-proximity avoidance (v6) | dropped: would make self-play LESS decisive, cannot pass gate |
| 6 | Endgame elimination closer (v7) | 0 sweeps / 20 hosted self-play, best seat 29 |
| 7 | Soft neutral preference instead of veto (v8) | claims all 47 in self-play but 2-3 survivors |
| 8 | Flight-time-aware enemy cost + staging loiter (v9) | 47/47 solo in ~150s |
| 9 | Longer send burst 3s -> 8s (v11) | REGRESSED hard (16-20 planets). A burst pins the cursor. |
| 10 | Bounded garrison (v12) | neutral |
| 11 | Explore when nothing targetable (v13) | neutral solo; still correct to keep |
| 12 | Prefer origin already held (v14) | no change |
| 13 | Manhattan cursor cost + instant origin claim (v15) | no change |
| 14 | Camp on claimed origin (v16) | no change |
| 15 | Chain from planet just captured (v17) | GoOrigin 39% -> 25%; planet count unchanged |
| 16 | Cheapest-first targeting (v18) | REGRESSED (23). Travel dominates, not ships. |
| 17 | Adaptive ship weight by empire size (v19) | REGRESSED (20) |
| 18 | Send while travelling (v20) | REGRESSED (22) — raids the capture budget |
| 19 | Surplus-only travel send (v22) | neutral |
| 20 | Garrison 30 / 45 (v23/v24) | no change |
| 21 | Hold position until capture lands (v25) | REGRESSED (22) |
| 22 | Chip neutrals from nearest origin (v26) | REGRESSED (22) |
| 23 | Keep origin until dry (v27) | no change; camp rate still 16% |
| 24 | Garrison 0 / 4 (v28/v29) | looked like +3, **did not replicate** across seeds (26.0 vs 25.3) |
| 25 | Spree-sized origins (v30/v31) | REGRESSED (26 / 23) |
| 26 | Raise OriginReserveShips 1 -> 8/12/16 | REGRESSED hard (17/16/13). Draining an origin to 1 ship is CORRECT — each planet funds ~1 capture and moving on is inherent. |
| 27 | Rank origins by the cursor's actual trip (v33) | Looked like +2.4 on three seeds; **12-map paired test says 6W-3L-3T, +0.6, p=0.51 — NOT significant.** Kept anyway (harmless, better-motivated code) but it is not a win. |
| 28 | Origin detour bound 1x / 2x / 3x | 1x and 2x tie (27.7); 3x collapses (23.0). Win is tight selection, not the constant. Keep 2x. |
| 29 | SizeScoreBonus 0 / 400 / 1500 | wash (26.7 / 27.3 / 27.7). Keep 1500. |
| 30 | Weight squared capture cost 20x / 60x | REGRESSED (26.3 / 24.7 vs 27.7). Third confirmation that travel dominates and ship price should stay negligible. |

Net: **no validated improvement in map coverage after 30 experiments.**
The one apparent win (#27) failed its 12-map replication.
The mechanism behind it was still real: `bestOriginFor` ranked candidate origins by
their distance **to the target**, ignoring where the cursor was — so a
well-stocked planet next to the cursor lost to one marginally nearer the
target but a long walk away, and the cursor paid that walk every capture.
Ranking by cursor->origin->target fixed it. The "upgrade to a richer
origin within 2x" bound was also comparing squared distances against a
linear intent, so it was far looser than its comment claimed.

Diagnostic that cracked it: echo the REASON the origin is rejected, per
tick. Result was 458 noships (avail=0 raw=1), 208 banned, 9 ok — the
origin is drained to exactly 1 ship because `sendShip` only refuses at 1.
That is normal, not a bug (see #26), but it proved chaining essentially
never fires, which is why every tweak layered on top of it did nothing.

## Qualification gate — corrected understanding

The gate is NOT a skill threshold, it is a **low-probability event**, and
each submission is an independent attempt.

- Everything sweeps SOLO in 300s: v33, v21 and kudzu all reach 47/47.
  So qualification is not a solo run (skurge:v2 == v21 code and it failed).
- NOBODY sweeps 8-clone self-play: v33 tops out at 15-22 planets with 3-5
  survivors; **kudzu, which passed the gate on 2026-07-23, tops out at
  17-21** in the same test. It cannot pass reliably either.
- Andrew Brower's membership list is the tell: 32 submitted versions, most
  disqualified, several qualified, one now champion. The winning strategy
  is resubmission, not a better bot.
- Hosted self-play may also be easier than local: a clone that fails to
  connect leaves its planets neutral for someone else to sweep up.

So: submit, and resubmit on disqualification. Uploading the same code as a
new version is cheap.

## Measured standing of our build (paired seed_bench, sign test)

| comparison | result |
|---|---|
| v33 vs champion `planet-wars-skurge:v1` | **10W-0L, +16.1 planets, p=0.0020** |
| v33 vs `rowdaboat-kudzu` (rival, ex-#1) | **8W-0L, +7.6 planets, p=0.0078** |
| v33 vs v21 (own prior build) | 6W-3L-3T, +0.6, p=0.51 — not significant |

v33 is decisively better than what we field and than the strongest rival
bot, even though it is not distinguishable from our own recent baseline.

## Gate probe — hosted, 24 episodes (2026-08-04)

`tools/xp.nim selfplay <policy> <episodes>` builds an 8-identical-seat
roster, which is what the qualification gate actually runs;
`tools/xp.nim gate <xreq>` reports the distribution it scores.

| build | top seat mean | best | survivors | sweeps |
|---|---|---|---|---|
| v33 (`skurge:v3`) | 25.3 | 33 | 2.8 | **0 / 12** |
| v37 (`skurge:v4`) | 23.6 | 33 | 3.2 | **0 / 12** |

**Zero sweeps in 24 hosted episodes; the best seat ever reached 33 of the
47 required.** With 0 successes in 24 trials the sweep rate is at most
~12% and probably far lower. Four submissions (`planet-wars-skurge:v4`,
`skurge:v2/v3/v4`) were all disqualified on this.

Conclusion: last place is NOT bot quality. Our build beats the incumbent
champion by +16.1 planets (10W-0L, p=0.0020) and cannot get on the field.
Tuning toward the gate also failed — v37's war-phase concentration made
the gate metric *worse* (23.6 vs 25.3).

Options when league work resumes: (a) repeated submission, since each is
an independent roll — `tools/resubmit.nim` automates upload+submit+await;
(b) raise the gate with the league owner as likely misconfigured, bringing
this distribution as evidence.

**Note the redesign changes this calculus.** Mouse input and full-map
visibility remove the two asymmetry generators (cursor-travel luck and
scouting luck) that let one self-play clone run away, so the 47-planet
gate likely becomes *harder*, not easier.

## Ideas not yet tried

- **Route planner (highest value).** Claim one rich origin, then sweep the
  cursor through every planet it can fund in a nearest-neighbour tour,
  relocating only when dry. Current code re-derives an origin per capture.
- Instrument WHY camp is rejected (per-reason counters), rather than
  guessing. With garrison 0 an origin at 20 ships should fund a second
  9-ship capture, yet camp still fires only 16% — that gap is unexplained
  and is the single most informative thing left to measure.
- Multi-target burst: keep origin fixed, move cursor target to target
  without re-planning at all.
- Contested-play checks: everything above is tuned on an empty map. A lean
  garrison may be fragile when a neighbour can flip a 1-ship planet back.

## Bandwidth after removing the viewport (measured 2026-08-04)

Full-map visibility means every player receives the whole board every tick,
so the per-tick packet was measured directly on an idle 47-planet game with
one viewer and no ships in flight.

| Build | Bytes/tick | At 60 Hz | Note |
|---|---|---|---|
| Viewport removed, no delta | 1929 | 116 KB/s | re-sends a board that is not changing |
| + world-object delta | 549 | 33 KB/s | 115 objects, 1-2 re-sent per change |
| + HUD as digit objects | 24 | 1.4 KB/s | HUD sprite was a ~530 byte bitmap per tick |
| + map backdrop on the delta path | 12 | 0.7 KB/s | the one object left is the ticking score digit |

**160x reduction, and the remaining 12 bytes are a real change.** Three
findings worth keeping:

1. **The sort index had to stop going on the wire.** `flushWorldObjects`
   overwrote `z` with the post-sort index, which shifts whenever any other
   object appears or leaves — so nearly every object looked changed and
   delta compression was impossible. Both clients already sort by
   `(z, y, id)`, so sending real depth changes nothing visually.
2. **The HUD dominated, not the planets.** It rasterized "SCORE n /
   PLANETS n" into one sprite and re-uploaded the bitmap whenever the score
   moved, which is nearly every tick. Rebuilt on the ten shared score-panel
   digit sprites it costs one 12-byte object per digit that actually
   differs. Those digit sprites were previously only defined on the global
   viewer path, so the player view had to define them too.
3. **Ships stay irreducible at ~12 bytes each per tick** — they move every
   tick, so nothing above helps them. That is the real budget: a 500-ship
   engagement is ~360 KB/s per viewer. If that becomes a problem the lever
   is `MaxShipsInFlight` or a lower ship update rate, not compression.

Locked in by `tests.nim`: an unchanged board must re-send zero objects, and
changing one planet's ship count must re-send only that planet's digit.

## Porting skurge to the mouse rules (2026-08-04)

The redesign deleted the d-pad, so every bot was inert: they drive
`[0x84, mask]`, which the sim no longer reads. Ranking cannot move until
this is fixed, so the port is the unblock, not new bot development.

**What survived.** All the sensing: sprite-protocol parsing, per-digit
ship counts, planet sightings, distance and growth estimates. Those read
the board, and the board still renders the same way.

**What was deleted (~600 lines).** The mission FSM, cursor steering
(`steerMask`, `sweepMask`, `travelSendMask`, `loiterMask`), send bursts,
origin banning, and the fog machinery. All of it existed to manage cursor
travel and a 320x200 viewport; neither exists now.

**What replaced it.** A per-tick allocator: rank every (owned source,
target) pair by what the capture costs, pick the cheapest, emit two clicks
(select the source, click the target). ~120 lines.

Two things the port forced:

1. **Identity had to change.** The bot recognized itself by the origin
   ring under its own cursor. With the whole map visible and no cursor,
   nothing distinguishes our planets by position — so the bot now opens
   with a select-all click, and the selection rings that come back name
   every planet it owns and its color.
2. **Send size is a search, not a constant.** Percentages are 10..100 in
   steps of 10 and a planet always keeps one ship, so the bot picks the
   smallest percentage whose launch count covers the capture cost.
   Under-sending wastes the whole wave.

**The tuned weights did not transfer, as the plan predicted.** The d-pad
bot scored targets with `NeutralPreferenceBonus = 6000` and
`SizeScoreBonus = 1500` against a ship-cost term of ~350. When a capture
cost a cursor trip and captures were rare, that made sense; now a capture
is two clicks, so the bonuses swamped cost entirely and the bot chased
expensive large planets while draining itself to 10%. Rescaled to the same
order as cost (200/120/300/60).

**Not measured.** One local game on one seed went 15 -> 18 planets after
the rescale. That is a single sample and is *not* evidence — the same
pattern produced two retracted claims earlier in this project. Real
numbers need paired hosted runs, which are not available yet: hosted
canonical is still the d-pad game, so an experience request would evaluate
the old rules. Validating the new bot requires publishing the redesigned
game version first, which is a deploy decision and not mine to take.

## Packaging the redesign for publish (2026-08-04)

Everything below the deploy itself is now done, so publishing is one
approved step rather than a pile of prep.

**Version stamps bumped, and this one was a latent bug.** `GameVersion`
was still `"1"` and `PlanetWarsReplayFormatVersion` still `1`, even though
the ship record gained fields, the RNG draw sequence changed when
`randomShipLaneOffset` was deleted, and the entire input model was
replaced. bitworld's loader rejects a replay whose stamps disagree
(`replays.nim:387,395`), so bumping both to `2` makes stale replays fail
cleanly instead of being decoded by a sim that no longer matches them.
Left unbumped, a v1 replay would have loaded and quietly mis-hashed.

**`defaultSendPercent` is now a real config field.** It runs
`SimConfig` -> `addPlayer`, is declared in `config_schema`, and is listed
in `isKnownConfigField` — that last one matters because
`src/planet_wars.nim` hard-raises on any field it does not know, so a
schema entry without it would break every hosted run that set it.
Clamped to 10..100 on the way in. Manifest `0.1.0` -> `0.2.0`.

**Still open, deliberately:**

- **kudzu is untouched.** It is a local bench copy: no Dockerfile, no
  coplayer manifest, absent from the manifest's player array, with a ship
  reader that parses a label the server stopped emitting. It is now
  inert as well. Porting it as a control arm or deleting it are both
  defensible, but it is not mine to delete unasked.
- **The deploy.** Publishing 0.2.0 as canonical invalidates every
  submitted policy in the league, including other players' — they all
  drive the deleted d-pad. That is the league owner's call.

  **Measurement can dodge the promotion, but not the way I first said.**

  First claim (wrong): hosted evaluation is blocked until 0.2.0 is
  canonical. Wrong — `V2CreateExperienceRequestRequest` carries a
  top-level `coworld_id` ("Direct Coworld target") alongside the league
  selector, so a request can pin a specific Coworld.

  Second claim (also wrong, and the dangerous one): uploading is safe
  because `certify` is what promotes. **There is no promote step.**
  `v2_api_reference.md:149` — the canonical Coworld for a game is
  "the canonical (highest semver) Coworld for the game's
  `coworld_name`". Canonical is *derived from version ordering*. Hosted
  canonical is 0.1.3, so `upload-coworld` at 0.2.0 under the name
  `planet_wars` would become canonical the instant it lands, and the
  league resolves its game's canonical Coworld. Every policy submitted
  by every player drives the deleted d-pad, so an upload intended purely
  as a test artifact would break the live league for everyone.

  **The safe path is to upload under a different `coworld_name`**, so it
  never competes for the `planet_wars` canonical slot:
  `upload-coworld --patch '{"game":{"name":"planet_wars_redesign"}}'`,
  then pin `--coworld=<id>`. Not yet verified that a new name is
  permitted for a non-team caller, or whether it creates a catalog entry
  that others can see. Verify before running.

## Measuring the redesign without promoting it (2026-08-04)

`tools/xp.nim` now takes `--coworld=<id>` (or `PLANET_WARS_COWORLD_ID`)
and sets the request's top-level `coworld_id` instead of
`target.league_id`. Flags are parsed positionally-independently, so the
option works before or after the subcommand.

The run, once the game version is uploaded:

1. `coworld upload-coworld --version 0.2.0` -> returns a Coworld id.
   This does **not** promote: `certify` is the promoting step, so the
   live league keeps running the d-pad game untouched.
2. `coworld upload-policy` the ported skurge, twice, as candidate and
   baseline builds.
3. `xp --coworld=<id> run <candidate> <baseline> 20`
4. `xp watch <xreqId>` then `xp stats <xreqId>` for the paired sign test.

**The old `Field` roster is useless here.** Those five hosted policies
(`co-gas-planet-wars-simple-richard:v7` and friends) all drive the
deleted d-pad, so against the new rules they are motionless — an A/B
against them would be a solo benchmark in an A/B costume. Measurement on
the new game has to be our builds against each other, or self-play,
until other players port.

## Teaching skurge the mouse rules: solo conquest (2026-08-04)

Local runs, at the user's explicit direction, until the bot can take the
whole map. `tools/solo.nim` runs N seeds and reports planets held and
time-to-sweep; `PLANET_WARS_SPEED` runs the server clock faster (an env
var, not a flag, because bitworld's runtime rejects unknown argv before
our code sees it). The simulation is fixed-step, so the clock changes how
long a run takes to watch, not what happens in it.

| Change | Sweeps | Mean sweep |
|---|---|---|
| Ported bot, as first written | 6/6 | 106.9s |
| Cooldown 4 -> 1 tick, in-flight commitments | 6/6 | 92.8s |
| Neutral capture margin 2 -> 1 | 6/6 | 87.4s |
| Select-all mass wave when nothing is affordable alone | 6/6 | 71.8s |
| Phase machine: opening -> big planets -> snake, 100% waves | 6/6 | 70.9s |

**34% faster, sweeping every seed.** Reproducibility was checked before
trusting any of it: the same build twice gave 87.4s and 88.2s, so
differences under ~1.5s are noise, and the two entries at 71.8s/70.9s are
a tie rather than an improvement.

Findings worth keeping:

1. **The biggest single win was the stall, not the tuning.** Before the
   mass wave, whenever no single planet could fund any capture the bot
   sat on its ships. Pooling the empire with one select-all click turned
   those stalls into captures: 87.4s -> 71.8s, larger than every
   parameter change combined.
2. **In-flight ships must be remembered.** Without a commitment ledger
   the planner re-buys a planet it has already paid for, which serializes
   the whole expansion behind one capture at a time.
3. **A full send does not remove the affordability check — it makes it
   matter more.** Forcing 100% waves without checking the fleet could
   actually take the target dropped the bot from 47 planets to 3: a wave
   that lands one ship short changes nothing, and the target keeps every
   ship it survived with. Nearest-first is the plan; nearest-we-can-hold
   is the plan that works.
4. **`SmallPlanetRadius = 9` was silently a no-op.** It is the *gameplay*
   radius, but the bot reads *sprite* radii (13/15/18), so every planet
   cleared the bar and the large-planet bonus applied to everything.
5. **20x clock breaks the harness** — runs produce no results at all.
   Unused; 10x is verified reproducible.

**The snake phase rarely triggers.** It is gated on owning every large
planet, which does not happen until the map is nearly swept, so the
pooled fallback does most of the work. Single-source sends are now
preferred whenever the stack alone can afford the target, which is the
snake in substance, but the explicit phase fires only ~8 times a game.

### Two optimizations that did not work (reverted)

| Change | Sweeps | Mean sweep | Verdict |
|---|---|---|---|
| Baseline (phase machine) | 6/6 | 70.9s | kept |
| Snake gate: fire at *most* large planets, not all | 6/6 | 71.5s | reverted |
| Two independent 100% waves per tick | 6/6 | 70.2s | reverted |

Both are inside the ~1.5s noise floor established by running one build
twice (87.4s / 88.2s). Neither is an improvement.

**That two structural changes in a row moved nothing is the real
result: the solo sweep is economy-bound, not travel- or
parallelism-bound.** Captures are limited by how fast owned planets grow
ships, and taking cheap near planets first already maximizes that
compounding. More waves in flight does not help when there are no spare
ships to put in them. Further speed has to come from the growth curve —
capture order, or preferring planets that grow faster sooner — not from
issuing orders more aggressively.

Worth revisiting once there are opponents: parallel independent waves
were neutral here, but solo play never punishes concentrating the whole
fleet in one place, and a real opponent would.

## Leaderboard state, checked 2026-08-04

| Rank | Player | Elo |
|---|---|---|
| 1 | relh | 1637.1 |
| 2 | richard | 1538.6 |
| 3 | Andrew Brower | 1483.4 |
| 4 | RowDaBoat | 1474.6 |
| 5 | docxology | 1472.3 |
| 6 | **Andre von Houck** | 1394.1 |

248 rounds each, 706 competition rounds total. The leader is **relh**,
not richard — earlier notes in this file said richard, which is stale.
Our own rating drifted up from 1374.4 without any new submission, so the
league is live and our incumbent d-pad champion is still competing.

### Two paths to a rank, and they are mutually exclusive

**A. Improve the d-pad bot against the live game. No deploy.** The league
runs canonical 0.1.3, which is the d-pad game, so only a d-pad bot can
score. The pre-rewrite skurge is recovered to
`players/skurge_dpad/skurge_dpad.nim` and builds. Hosted experience
requests work against it today with no publishing of any kind.
*Blocked by:* the 47-planet self-play qualification gate. Measured 0
sweeps in 24 hosted episodes, best seat 33; four submissions were
disqualified. A better bot still cannot get on the field without winning
that lottery, and that is what has kept us 6th regardless of bot quality.

**B. Publish the redesign and compete on the new rules.** Our mouse bot
sweeps 47/47 on 6 of 6 maps, so it would likely clear the same gate
easily. *Blocked by:* canonical is highest semver, so publishing 0.2.0
breaks all six players' submitted policies and 248 rounds of live
competition, immediately and without a confirmation step.

The redesign made the game better and made the leaderboard goal harder,
and no amount of engineering resolves that — it is a decision about
whether the league moves to the new game.
