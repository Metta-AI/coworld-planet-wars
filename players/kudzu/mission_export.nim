## Join private model mission choices to the hash-verified game replay.

import std/[json, os, parseopt, posix, sequtils, strutils]
import bitworld/spriteprotocol
import planet_wars/[replays, sim]

proc exportEpisode*(journalPath, replayPath, resultsPath, outputPath, episodeId, sourceRevision: string): JsonNode =
  if sourceRevision.len != 40 or sourceRevision.anyIt(it notin {'0'..'9', 'a'..'f'}):
    raise newException(ValueError, "A pinned lowercase source revision is required")
  let data = loadReplay(replayPath)
  if data.hashes.len == 0:
    raise newException(ValueError, "Replay has no game hashes")
  var choices: seq[JsonNode] = @[]
  var localMasks: seq[uint8] = @[]
  var decisionByInput: seq[int] = @[]
  var currentDecision = -1
  var playerName = ""
  var playerId = -1
  for line in readFile(journalPath).splitLines():
    if line.len == 0:
      continue
    let row = parseJson(line)
    case row["event_type"].getStr()
    of "mission_choice":
      if playerName.len == 0:
        playerName = row["name"].getStr()
        playerId = row["player_id"].getInt()
      elif row["name"].getStr() != playerName or row["player_id"].getInt() != playerId:
        raise newException(ValueError, "Mission journal spans multiple players")
      currentDecision = choices.len
      choices.add(row)
    of "input_mask":
      let mask = row["mask"].getInt()
      if mask < 0 or mask > 127:
        raise newException(ValueError, "Mission journal has an invalid input mask")
      var inputDecision = currentDecision
      if currentDecision >= 0:
        let selected = choices[currentDecision]["selected"]
        if row["mission_origin"].getInt() != selected["origin_id"].getInt() or
            row["mission_target"].getInt() != selected["target_id"].getInt():
          inputDecision = -1
      localMasks.add(mask.uint8)
      decisionByInput.add(inputDecision)
    else:
      raise newException(ValueError, "Unknown mission journal event")
  if choices.len == 0:
    raise newException(ValueError, "Mission journal has no model choices")
  var seat = -1
  for join in data.joins:
    if join.name == playerName:
      if seat >= 0:
        raise newException(ValueError, "Replay has duplicate model player names")
      seat = int(join.player)
  if seat < 0:
    raise newException(ValueError, "Model player is absent from replay")
  let results = parseJson(readFile(resultsPath))
  if results["names"][seat].getStr() != playerName:
    raise newException(ValueError, "Results seat differs from replay player")
  var replayMasks: seq[uint8] = @[]
  for input in data.inputs:
    if int(input.player) == seat:
      replayMasks.add(input.keys)
  if localMasks.len == replayMasks.len + 1 and localMasks[0] == 0:
    localMasks.delete(0)
    decisionByInput.delete(0)
  if localMasks != replayMasks:
    raise newException(ValueError, "Submitted input ledger differs from replay")

  var replay = initReplayPlayer(data)
  let settings = replaySimSettings(data)
  var game = initSimServer(settings.seed, settings.config)
  var applied = newSeq[bool](choices.len)
  var inputCursor = 0
  var modelInputCursor = 0
  var activeDecision = -1
  while replay.playing and game.tickCount < replay.replayMaxTick():
    let currentTime = tickTime(game.tickCount)
    while inputCursor < data.inputs.len and data.inputs[inputCursor].time <= currentTime:
      if int(data.inputs[inputCursor].player) == seat:
        activeDecision = decisionByInput[modelInputCursor]
        inc modelInputCursor
      inc inputCursor
    replay.stepReplay(game)
    if activeDecision < 0 or seat >= game.players.len or
        (replay.masks[seat] and ButtonB) == 0:
      continue
    let selected = choices[activeDecision]["selected"]
    let originIndex = game.players[seat].originPlanet
    let targetIndex = game.players[seat].selectedPlanet
    if originIndex < 0 or targetIndex < 0 or
        originIndex >= game.planets.len or targetIndex >= game.planets.len or
        game.planets[originIndex].id != selected["origin_id"].getInt() or
        game.planets[targetIndex].id != selected["target_id"].getInt():
      continue
    for ship in game.ships:
      if ship.ownerId == playerId and ship.targetPlanet == selected["target_id"].getInt() and
          ship.progress == 1:
        applied[activeDecision] = true
        break
  if replay.hashValidationFailed or replay.hashIndex != data.hashes.len or not game.gameOver:
    raise newException(ValueError, "Replay did not verify a completed game")
  if seat >= game.players.len or game.players[seat].id != playerId:
    raise newException(ValueError, "Model identity differs from the verified replay")
  if parseJson(game.playerScoresJson()) != results:
    raise newException(ValueError, "Results differ from the verified replay")
  if modelInputCursor != replayMasks.len:
    raise newException(ValueError, "Replay did not consume all model inputs")
  var winnerSeat = -1
  for index in 0 ..< results["win"].len:
    if results["win"][index].getBool():
      winnerSeat = index

  var decisions = newJArray()
  for index, row in choices:
    let selected = row["selected"]
    let attemptId = "mission:" & $index & ":model"
    let accepted = applied[index]
    decisions.add(%*{
      "schema_version": "1", "event_type": "decision",
      "episode_id": episodeId, "decision_id": "mission:" & $index,
      "decision_index": index, "game": "coworld-planet-wars",
      "game_version": GameVersion, "source_revision": sourceRevision,
      "seat": $seat, "visibility": "private",
      "observation": row["request"]["state"], "prompt": row["request"],
      "attempts": [{
        "attempt_id": attemptId, "policy": row["response"]["model"],
        "origin": "model", "response": row["response"],
        "parsed_action": selected, "accepted": accepted,
        "rejection_reason": (if accepted: newJNull() else: %("No matching replay-verified ship launch"))
      }],
      "selected_attempt_id": (if accepted: %attemptId else: newJNull()),
      "executed_action": (if accepted: selected else: newJNull()),
      "action_status": (if accepted: "accepted" else: "rejected"),
      "fallback_origin": newJNull(), "reward": newJNull(),
      "terminal": index == choices.high
    })
  result = %*{
    "schema_version": "1",
    "episode": {
      "schema_version": "1", "event_type": "episode",
      "episode_id": episodeId, "game": "coworld-planet-wars",
      "game_version": GameVersion, "source_revision": sourceRevision,
      "status": "completed",
      "outcome": {"winner_seat": winnerSeat, "scores": results["scores"],
                  "replay_ticks": game.tickCount},
      "participant_outcomes": results
    },
    "decisions": decisions
  }
  let descriptor = posix.open(outputPath.cstring, O_WRONLY or O_CREAT or O_EXCL, 0o600.Mode)
  var output: File
  if descriptor < 0 or not output.open(FileHandle(descriptor), fmWrite):
    raise newException(IOError, "Could not create private episode output")
  defer: output.close()
  output.writeLine($result)

when isMainModule:
  var journalPath, replayPath, resultsPath, outputPath, episodeId, sourceRevision: string
  for kind, key, value in getopt():
    if kind != cmdLongOption:
      raise newException(ValueError, "Expected named exporter options")
    case key
    of "journal": journalPath = value
    of "replay": replayPath = value
    of "results": resultsPath = value
    of "output": outputPath = value
    of "episode-id": episodeId = value
    of "source-revision": sourceRevision = value
    else: raise newException(ValueError, "Unknown exporter option: " & key)
  if journalPath.len == 0 or replayPath.len == 0 or resultsPath.len == 0 or
      outputPath.len == 0 or episodeId.len == 0:
    raise newException(ValueError, "Journal, replay, results, output, and episode ID are required")
  let episode = exportEpisode(journalPath, replayPath, resultsPath, outputPath, episodeId, sourceRevision)
  var accepted = 0
  for decision in episode["decisions"]:
    if decision["action_status"].getStr() == "accepted":
      inc accepted
  echo $(%*{"episode_id":episodeId,"decisions":episode["decisions"].len,"accepted":accepted})
