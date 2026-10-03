## Runs the existing PLANETWR codec/player and audits a read-only adapter.
import std/[json, os, strutils]
import planet_wars/[sim, replays, presentation]

proc terminal(world: SimServer): JsonNode =
  %*{"tick": world.tickCount, "hash": $world.gameHash(),
      "score": parseJson(world.playerScoresJson()), "over": world.gameOver,
      "winner": world.winnerPlayerId, "planets": world.planets,
      "ships": world.ships, "players": world.players, "chat": world.chatMessages,
      "stars": world.stars, "config": world.config, "scoreRevision": world.scoreRevision,
      "rng": $world.rng, "nextPlayerId": world.nextPlayerId,
      "scoreTicks": world.scoreTicks, "maxActiveOwnerCount": world.maxActiveOwnerCount,
      "waitingForPlayers": world.waitingForPlayers,
      "expectedPlayers": world.expectedPlayers, "waitTicks": world.waitTicks,
      "textFont": $world.textFont}

let path = paramStr(1)
doAssert path.len > 0, "Pass an existing PLANETWR replay path"
let data = loadReplay(path)
let settings = data.replaySimSettings()
var world = initSimServer(settings.seed, settings.config)
var playback = initReplayPlayer(data)
var expected = newSeq[string](playback.replayMaxTick()+1)
var conquestCount = 0
var previousOwners: seq[int]
while playback.playing:
  playback.stepReplay(world)
  doAssert not playback.hashValidationFailed, "Recorded tick hash mismatch at " & $world.tickCount
  let before = $terminal(world)
  let frame = world.presentationFrame()
  for size in [(800, 800), (960, 540), (320, 240)]:
    let camera = fixedCamera(size[0], size[1])
    for planet in world.planets:
      let screen = camera.screenPoint(planet.x, planet.y)
      doAssert frame.pickPlanet(camera, screen.x, screen.y) == world.nearestPlanetIndex(planet.x, planet.y)
    for point in [(0, 0), (511, 0), (0, 511), (511, 511), (256, 256)]:
      let screen = camera.screenPoint(point[0], point[1])
      doAssert camera.worldPoint(screen.x, screen.y) == (point[0], point[1])
      doAssert frame.pickPlanet(camera, screen.x, screen.y) == world.nearestPlanetIndex(point[0], point[1])
  doAssert before == $terminal(world), "Presentation mutated authoritative state"
  if previousOwners.len == world.planets.len:
    for i, planet in world.planets:
      if previousOwners[i] != planet.ownerId: inc conquestCount
  previousOwners.setLen(0)
  for planet in world.planets: previousOwners.add planet.ownerId
  expected[world.tickCount] = before
  echo $(%*{"kind": "tick", "tick": world.tickCount,
    "hash": $world.gameHash(), "score": parseJson(world.playerScoresJson()),
    "planets": frame.planets.len, "ships": frame.ships.len})
let finalWorld = terminal(world)
var seeker = initReplayPlayer(data)
seeker.buildReplayKeyframes(settings.seed, settings.config)
for tick in [playback.replayMaxTick(), 42, 150, 1, 99, 100, 101, playback.replayMaxTick()]:
  let target = min(tick, playback.replayMaxTick())
  seeker.applyReplaySeek(world, target)
  doAssert not seeker.hashValidationFailed
  doAssert $terminal(world) == expected[target], "Seek world mismatch at " & $target
  echo $(%*{"kind": "seek", "tick": target, "hash": $world.gameHash()})
echo $(%*{"kind": "terminal", "world": finalWorld,
  "joins": data.joins.len, "leaves": data.leaves.len, "chats": data.chats.len,
  "inputs": data.inputs.len, "hashes": data.hashes.len,
  "conquestTransitions": conquestCount, "keyframes": seeker.keyframes.len})
