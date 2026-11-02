## Check real socket captures and their result boundary independently.
import std/[json, os]
import planet_wars/[sim, replays]

doAssert paramCount() == 2
let data = loadReplay(paramStr(1))
let settings = data.replaySimSettings()
var simulation = initSimServer(settings.seed, settings.config)
var playback = initReplayPlayer(data)
playback.looping = false
while playback.playing and playback.hashIndex < data.hashes.len:
  playback.stepReplay(simulation)
  doAssert not playback.hashValidationFailed
doAssert playback.hashIndex == data.hashes.len and data.hashes.len > 0
let expected = parseJson(readFile(paramStr(2)))
let actual = parseJson(data.replayResultsJson(simulation))
doAssert actual == expected
doAssert data.joins.len == 3
var slots = newJArray()
for join in data.joins:
  slots.add(%int(join.slot))
doAssert slots == %*[2, 0, 1]
var addressedInputs = newJArray()
for input in data.inputs:
  if input.keys == 0:
    continue
  let slot = int(data.joins[int(input.player)].slot)
  let expectedMask = [1'u8, 8'u8, 4'u8][slot]
  doAssert input.keys == expectedMask
  addressedInputs.add(%*{"slot":slot,"mask":input.keys})
doAssert addressedInputs.len == 3
echo $(%*{"verified_hashes":playback.hashIndex,"slots":slots,
  "addressed_inputs":addressedInputs,"results":actual})
