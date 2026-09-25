## Headless Planet Wars episodes over the same private sprite packets and
## button masks used by ordinary WebSocket players.

import std/[base64, json]
import planet_wars/[global, replays, sim]

type
  TrainingBridge* = object
    sim*: SimServer
    viewers: seq[PlayerViewerState]
    previousMasks: seq[uint8]
    previousScores: seq[int]

proc observations(bridge: var TrainingBridge): JsonNode =
  result = newJArray()
  for seat in 0 ..< bridge.sim.players.len:
    var nextViewer: PlayerViewerState
    let packet = bridge.sim.buildSpriteProtocolPlayerUpdates(
      seat, bridge.viewers[seat], nextViewer
    )
    bridge.viewers[seat] = nextViewer
    result.add(%encode(packet))

proc reset*(bridge: var TrainingBridge, seed, maxTicks, planetCount, playerCount: int): JsonNode =
  doAssert playerCount >= 2 and playerCount <= 8
  var config = defaultSimConfig()
  config.maxTicks = maxTicks
  config.planetCount = planetCount
  config.checkSimConfig()
  bridge.sim = initSimServer(seed, config, expectedPlayers = playerCount)
  bridge.viewers = newSeq[PlayerViewerState](playerCount)
  bridge.previousMasks = newSeq[uint8](playerCount)
  bridge.previousScores = newSeq[int](playerCount)
  for seat in 0 ..< playerCount:
    discard bridge.sim.addPlayer("training-" & $seat)
    bridge.viewers[seat] = initPlayerViewerState()
  bridge.sim.step([]) # Releases the normal two-player waiting lobby.
  doAssert not bridge.sim.waitingForPlayers
  let zeroes = newSeq[int](playerCount)
  %*{
    "observations": bridge.observations(),
    "rewards": zeroes,
    "scores": zeroes,
    "done": false,
    "tick": bridge.sim.tickCount
  }

proc step*(bridge: var TrainingBridge, masks: seq[uint8], repeat: int): JsonNode =
  doAssert repeat > 0
  doAssert not bridge.sim.gameOver
  doAssert masks.len == bridge.sim.players.len
  var packets = newSeq[seq[uint8]](masks.len)
  for _ in 0 ..< repeat:
    var inputs = newSeq[PlayerInput](masks.len)
    for seat in 0 ..< masks.len:
      doAssert masks[seat] <= 0x7f'u8
      inputs[seat] = playerInputFromMasks(masks[seat], bridge.previousMasks[seat])
      bridge.previousMasks[seat] = masks[seat]
    bridge.sim.step(inputs)
    for seat in 0 ..< masks.len:
      var nextViewer: PlayerViewerState
      packets[seat].add(bridge.sim.buildSpriteProtocolPlayerUpdates(
        seat, bridge.viewers[seat], nextViewer
      ))
      bridge.viewers[seat] = nextViewer
    if bridge.sim.gameOver:
      break
  var
    observations = newJArray()
    rewards = newJArray()
    scores = newJArray()
  for seat in 0 ..< masks.len:
    let score = bridge.sim.players[seat].score
    observations.add(%encode(packets[seat]))
    rewards.add(%(score - bridge.previousScores[seat]))
    scores.add(%score)
    bridge.previousScores[seat] = score
  %*{
    "observations": observations,
    "rewards": rewards,
    "scores": scores,
    "done": bridge.sim.gameOver,
    "tick": bridge.sim.tickCount
  }

when isMainModule:
  import std/os
  doAssert paramCount() == 1
  setCurrentDir(paramStr(1))
  var bridge: TrainingBridge
  while not stdin.endOfFile:
    let command = parseJson(stdin.readLine())
    let response = case command["cmd"].getStr()
      of "reset": bridge.reset(
        command["seed"].getInt(),
        command["max_ticks"].getInt(),
        command["planet_count"].getInt(),
        command["player_count"].getInt()
      )
      of "step":
        let masks = command["masks"]
        var values: seq[uint8] = @[]
        for mask in masks:
          values.add(uint8(mask.getInt()))
        bridge.step(values, command["repeat"].getInt())
      else: raise newException(ValueError, "unknown training command")
    echo response
