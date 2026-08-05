import
  std/[json, random],
  flatty,
  bitworld/replays as replayCodec,
  bitworld/spriteprotocol,
  sim

type
  ReplayKeyframe* = object
    tick*: int
    simBytes*: string
    joinIndex*: int
    leaveIndex*: int
    inputIndex*: int
    chatIndex*: int
    hashIndex*: int
    masks*: seq[uint8]
    lastAppliedMasks*: seq[uint8]
    hashValidationFailed*: bool
    hashMismatchTick*: int

  ReplayPlayer* = object
    data*: ReplayData
    joinIndex*: int
    leaveIndex*: int
    inputIndex*: int
    chatIndex*: int
    hashIndex*: int
    masks*: seq[uint8]
    lastAppliedMasks*: seq[uint8]
    playing*: bool
    looping*: bool
    speedIndex*: int
    hashValidationFailed*: bool
    hashMismatchTick*: int
    keyframes*: seq[ReplayKeyframe]

  KeyframeState = object
    players: seq[Player]
    planets: seq[Planet]
    ships: seq[Ship]
    chatMessages: seq[ChatMessage]
    rng: Rand
    nextPlayerId: int
    scoreTicks: int
    tickCount: int
    gameOver: bool
    winnerPlayerId: int
    maxActiveOwnerCount: int
    scoreRevision: int

const
  ReplayFps* = TargetFps
  PlaybackSpeeds* = [1, 2, 3, 4, 8, 16]
  ReplayKeyframeTicks* = 100
  PlanetWarsReplayMagic = "PLANETWR"
  PlanetWarsReplayFormatVersion = 2'u16
  PlanetWarsReplaySpec = ReplaySpec(
    magic: PlanetWarsReplayMagic,
    formatVersion: PlanetWarsReplayFormatVersion,
    gameName: GameName,
    gameVersion: GameVersion,
    joinKind: rjkNameSlotToken,
    allowChat: true,
    allowCompressed: true,
    hashOrder: rhoStop
  )

export replayCodec

proc tickTime*(tick: int): uint32 =
  ## Converts a simulation tick to replay milliseconds.
  replayCodec.tickTime(tick, ReplayFps)

proc openReplayWriter*(path: string, configJson: string): ReplayWriter =
  ## Opens a replay file and writes the header.
  replayCodec.openReplayWriter(path, configJson, PlanetWarsReplaySpec)

proc parseReplayBytes*(bytes: string): ReplayData =
  ## Parses one replay file buffer into memory.
  replayCodec.parseReplayBytes(bytes, PlanetWarsReplaySpec)

proc loadReplay*(path: string): ReplayData =
  ## Loads a replay file into memory.
  replayCodec.loadReplay(path, PlanetWarsReplaySpec)

proc writeInputMaskChange*(
  writer: var ReplayWriter,
  time: uint32,
  playerIndex: int,
  mask: uint8
) =
  ## Writes one replay input event when a player's held mask changes.
  if playerIndex < 0 or playerIndex >= writer.lastMasks.len:
    return
  if writer.lastMasks[playerIndex] == mask:
    return
  writer.writeInput(ReplayInput(
    time: time,
    player: uint8(playerIndex),
    keys: mask
  ))
  writer.lastMasks[playerIndex] = mask

proc replaySimSettings*(data: ReplayData): tuple[seed: int, config: SimConfig] =
  ## Reads the recorded seed and simulation config from a replay header.
  result.seed = 0x1A7E7
  result.config = defaultSimConfig()
  if data.configJson.len == 0:
    return
  let node = parseJson(data.configJson)
  if node.kind != JObject:
    return
  if node.hasKey("seed") and node["seed"].kind == JInt:
    result.seed = node["seed"].getInt()
  if node.hasKey("planetCount") and node["planetCount"].kind == JInt:
    result.config.planetCount = node["planetCount"].getInt()
  if node.hasKey("maxTicks") and node["maxTicks"].kind == JInt:
    result.config.maxTicks = node["maxTicks"].getInt()
  if node.hasKey("maxGames") and node["maxGames"].kind == JInt:
    result.config.maxGames = node["maxGames"].getInt()

proc playerInputFromMasks*(currentMask, previousMask: uint8): PlayerInput =
  ## Builds a player input state from current and previous button masks.
  let decoded = decodeInputMask(currentMask)
  result.up = decoded.up
  result.down = decoded.down
  result.left = decoded.left
  result.right = decoded.right
  result.attackPressed =
    (currentMask and ButtonA) != 0 and (previousMask and ButtonA) == 0
  result.sendHeld = decoded.b

proc initReplayPlayer*(data: ReplayData): ReplayPlayer =
  ## Builds replay playback state.
  result.data = data
  result.masks = @[]
  result.lastAppliedMasks = @[]
  result.playing = true
  result.looping = true
  result.hashMismatchTick = -1

proc replaySpeed*(replay: ReplayPlayer): int =
  ## Returns the current integer replay speed.
  PlaybackSpeeds[clamp(replay.speedIndex, 0, PlaybackSpeeds.high)]

proc replayMaxTick*(replay: ReplayPlayer): int =
  ## Returns the final tick available in the replay.
  if replay.data.hashes.len == 0:
    return 0
  int(replay.data.hashes[^1].tick)

proc resetReplay*(replay: var ReplayPlayer) =
  ## Resets replay playback cursors.
  replay.joinIndex = 0
  replay.leaveIndex = 0
  replay.inputIndex = 0
  replay.chatIndex = 0
  replay.hashIndex = 0
  replay.hashValidationFailed = false
  replay.hashMismatchTick = -1
  replay.masks = @[]
  replay.lastAppliedMasks = @[]

proc ensureReplayPlayer(replay: var ReplayPlayer, player: int) =
  ## Expands replay input tables for one player.
  while replay.masks.len <= player:
    replay.masks.add(0)
  while replay.lastAppliedMasks.len <= player:
    replay.lastAppliedMasks.add(0)

proc saveKeyframeSim(sim: SimServer): string =
  ## Serializes dynamic simulation state for one replay keyframe.
  KeyframeState(
    players: sim.players,
    planets: sim.planets,
    ships: sim.ships,
    chatMessages: sim.chatMessages,
    rng: sim.rng,
    nextPlayerId: sim.nextPlayerId,
    scoreTicks: sim.scoreTicks,
    tickCount: sim.tickCount,
    gameOver: sim.gameOver,
    winnerPlayerId: sim.winnerPlayerId,
    maxActiveOwnerCount: sim.maxActiveOwnerCount,
    scoreRevision: sim.scoreRevision
  ).toFlatty()

proc restoreKeyframeSim(sim: var SimServer, bytes: string) =
  ## Restores dynamic simulation state from one replay keyframe,
  ## keeping loaded assets and static config untouched.
  let state = bytes.fromFlatty(KeyframeState)
  sim.players = state.players
  sim.planets = state.planets
  sim.ships = state.ships
  sim.chatMessages = state.chatMessages
  sim.rng = state.rng
  sim.nextPlayerId = state.nextPlayerId
  sim.scoreTicks = state.scoreTicks
  sim.tickCount = state.tickCount
  sim.gameOver = state.gameOver
  sim.winnerPlayerId = state.winnerPlayerId
  sim.maxActiveOwnerCount = state.maxActiveOwnerCount
  sim.scoreRevision = state.scoreRevision

proc saveReplayKeyframe(replay: ReplayPlayer, sim: SimServer): ReplayKeyframe =
  ## Builds one replay keyframe from the current playback state.
  ReplayKeyframe(
    tick: sim.tickCount,
    simBytes: sim.saveKeyframeSim(),
    joinIndex: replay.joinIndex,
    leaveIndex: replay.leaveIndex,
    inputIndex: replay.inputIndex,
    chatIndex: replay.chatIndex,
    hashIndex: replay.hashIndex,
    masks: replay.masks,
    lastAppliedMasks: replay.lastAppliedMasks,
    hashValidationFailed: replay.hashValidationFailed,
    hashMismatchTick: replay.hashMismatchTick
  )

proc restoreReplayKeyframe(
  replay: var ReplayPlayer,
  sim: var SimServer,
  keyframe: ReplayKeyframe
) =
  ## Restores playback state from one replay keyframe.
  sim.restoreKeyframeSim(keyframe.simBytes)
  replay.joinIndex = keyframe.joinIndex
  replay.leaveIndex = keyframe.leaveIndex
  replay.inputIndex = keyframe.inputIndex
  replay.chatIndex = keyframe.chatIndex
  replay.hashIndex = keyframe.hashIndex
  replay.masks = keyframe.masks
  replay.lastAppliedMasks = keyframe.lastAppliedMasks
  replay.hashValidationFailed = keyframe.hashValidationFailed
  replay.hashMismatchTick = keyframe.hashMismatchTick

proc replayKeyframeIndex(replay: ReplayPlayer, tick: int): int =
  ## Returns the newest keyframe at or before one tick.
  for i, keyframe in replay.keyframes:
    if keyframe.tick > tick:
      break
    result = i

proc applyReplayEvents(replay: var ReplayPlayer, sim: var SimServer) =
  ## Applies replay leaves, joins, inputs, and chats for the current tick.
  let time = tickTime(sim.tickCount)
  while replay.leaveIndex < replay.data.leaves.len and
      replay.data.leaves[replay.leaveIndex].time <= time:
    let leave = replay.data.leaves[replay.leaveIndex]
    if int(leave.player) < 0 or int(leave.player) >= sim.players.len:
      raise newException(ReplayError, "Replay player leave is invalid")
    sim.removePlayerAt(int(leave.player))
    if int(leave.player) < replay.masks.len:
      replay.masks.delete(int(leave.player))
    if int(leave.player) < replay.lastAppliedMasks.len:
      replay.lastAppliedMasks.delete(int(leave.player))
    inc replay.leaveIndex

  while replay.joinIndex < replay.data.joins.len and
      replay.data.joins[replay.joinIndex].time <= time:
    let join = replay.data.joins[replay.joinIndex]
    if int(join.player) != sim.players.len:
      raise newException(ReplayError, "Replay player join order is invalid")
    if sim.addPlayer(join.name) != int(join.player):
      raise newException(ReplayError, "Replay player join was rejected")
    replay.ensureReplayPlayer(int(join.player))
    inc replay.joinIndex

  while replay.inputIndex < replay.data.inputs.len and
      replay.data.inputs[replay.inputIndex].time <= time:
    let input = replay.data.inputs[replay.inputIndex]
    replay.ensureReplayPlayer(int(input.player))
    replay.masks[int(input.player)] = input.keys
    inc replay.inputIndex

  while replay.chatIndex < replay.data.chats.len and
      replay.data.chats[replay.chatIndex].time <= time:
    let chat = replay.data.chats[replay.chatIndex]
    sim.addChatMessage(int(chat.player), chat.message)
    inc replay.chatIndex

proc checkReplayHash(replay: var ReplayPlayer, sim: SimServer) =
  ## Checks the recorded hash for the current tick, leniently.
  if replay.hashValidationFailed:
    if sim.tickCount >= replay.replayMaxTick():
      replay.playing = false
    return
  if replay.hashIndex >= replay.data.hashes.len:
    replay.playing = false
    return
  let expected = replay.data.hashes[replay.hashIndex]
  if int(expected.tick) < sim.tickCount:
    echo "Replay hash tick is missing at tick ", sim.tickCount, "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  if int(expected.tick) > sim.tickCount:
    return
  let hash = sim.gameHash()
  if hash != expected.hash:
    echo "Replay hash mismatch at tick ", sim.tickCount,
      "; expected ", expected.hash, ", got ", hash, "."
    replay.hashValidationFailed = true
    replay.hashMismatchTick = sim.tickCount
    return
  inc replay.hashIndex

proc stepReplay*(replay: var ReplayPlayer, sim: var SimServer) =
  ## Advances replay playback by one simulation tick.
  replay.applyReplayEvents(sim)
  var inputs = newSeq[PlayerInput](sim.players.len)
  for playerIndex in 0 ..< sim.players.len:
    replay.ensureReplayPlayer(playerIndex)
    inputs[playerIndex] = playerInputFromMasks(
      replay.masks[playerIndex],
      replay.lastAppliedMasks[playerIndex]
    )
    replay.lastAppliedMasks[playerIndex] = replay.masks[playerIndex]
  sim.step(inputs)
  replay.checkReplayHash(sim)

proc buildReplayKeyframes*(
  replay: var ReplayPlayer,
  seed: int,
  simConfig: SimConfig,
  interval = ReplayKeyframeTicks
) =
  ## Builds serialized seek keyframes across the whole replay.
  replay.keyframes = @[]
  var
    sim = initSimServer(seed, simConfig)
    builder = initReplayPlayer(replay.data)
  builder.looping = false
  replay.keyframes.add(builder.saveReplayKeyframe(sim))
  let maxTick = builder.replayMaxTick()
  while builder.playing and sim.tickCount < maxTick:
    builder.stepReplay(sim)
    if sim.tickCount mod max(interval, 1) == 0 or sim.tickCount == maxTick:
      replay.keyframes.add(builder.saveReplayKeyframe(sim))

proc seekReplay*(replay: var ReplayPlayer, sim: var SimServer, tick: int) =
  ## Seeks replay playback to a target tick using seek keyframes.
  if replay.keyframes.len == 0:
    return
  replay.restoreReplayKeyframe(
    sim,
    replay.keyframes[replay.replayKeyframeIndex(tick)]
  )
  while sim.tickCount < tick and replay.hashIndex < replay.data.hashes.len:
    replay.stepReplay(sim)

proc applyReplaySeek*(replay: var ReplayPlayer, sim: var SimServer, tick: int) =
  ## Seeks replay playback and pauses on the target tick.
  replay.playing = false
  replay.seekReplay(sim, clamp(tick, 0, replay.replayMaxTick()))

proc applyReplayCommand*(
  replay: var ReplayPlayer,
  sim: var SimServer,
  command: char
) =
  ## Applies one replay viewer transport command.
  case command
  of ' ':
    replay.playing = not replay.playing
  of 'p':
    replay.playing = true
  of 'P':
    replay.playing = false
  of '+', '=':
    replay.speedIndex = min(replay.speedIndex + 1, PlaybackSpeeds.high)
  of '-', '_':
    replay.speedIndex = max(replay.speedIndex - 1, 0)
  of '1':
    replay.speedIndex = 0
  of '2':
    replay.speedIndex = 1
  of '3':
    replay.speedIndex = 2
  of '4':
    replay.speedIndex = 3
  of '8':
    replay.speedIndex = 4
  of '6':
    replay.speedIndex = 5
  of ',', '<':
    replay.playing = false
    replay.seekReplay(sim, 0)
  of 'b':
    replay.playing = false
    replay.seekReplay(sim, max(0, sim.tickCount - 1))
  of 'e':
    replay.playing = false
    replay.seekReplay(sim, replay.replayMaxTick())
  of 'r':
    replay.looping = not replay.looping
  of '.', '>':
    replay.playing = false
    replay.seekReplay(sim, sim.tickCount + ReplayFps * 5)
  else:
    discard
