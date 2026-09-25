import std/os
import planet_wars/replays

let replay = loadReplay(paramStr(1))
var player = -1
for join in replay.joins:
  if join.name == "trained-policy":
    player = int(join.player)
doAssert player >= 0
doAssert replay.hashes.len == 360
var submitted = false
for input in replay.inputs:
  if int(input.player) == player and input.keys == 8'u8:
    submitted = true
doAssert submitted, "trained player did not submit its ordinary right-button mask"
echo "trained player input appears in the game-owned replay"
