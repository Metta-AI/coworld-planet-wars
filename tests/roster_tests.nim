import std/json
import planet_wars/[roster, sim, replays]

echo "Testing roster token identities and duplicate claims"
let tokens = ["zero", "one", "two"]
doAssert resolveRosterSlot(0, "zero", tokens, 3) == 0
doAssert resolveRosterSlot(-1, "two", tokens, 3) == 2
doAssert resolveRosterSlot(0, "one", tokens, 3) == InvalidRosterSlot
doAssert resolveRosterSlot(-1, "unknown", tokens, 3) == InvalidRosterSlot
doAssert resolveRosterSlot(3, "two", tokens, 3) == InvalidRosterSlot
doAssert resolveRosterSlot(-1, "shared", ["shared", "shared"], 2) == InvalidRosterSlot
doAssert resolveRosterSlot(1, "shared", ["shared", "shared"], 2) == 1
doAssert resolveRosterSlot(-1, "", [], 3) == -1
doAssert availableRosterSlot([2, 0], 3) == 1
doAssert availableRosterSlot([2, 0, 1], 3) == InvalidRosterSlot

echo "Testing reversed native joins preserve every roster result field"
var reversed = initSimServer(71, defaultSimConfig())
discard reversed.addPlayer("third")
discard reversed.addPlayer("first")
discard reversed.addPlayer("second")
reversed.players[0].score = 53
reversed.players[1].score = 17
reversed.players[2].score = 31
let beforeHash = reversed.gameHash()
let raw = parseJson(reversed.playerScoresJson())
let ordered = parseJson(reversed.rosterResultsJson([2, 0, 1], 3))
doAssert ordered["names"] == %*["first", "second", "third"]
doAssert ordered["scores"] == %*[17, 31, 53]
for key in ["names", "scores", "win", "planets", "ships"]:
  doAssert ordered[key][0] == raw[key][1]
  doAssert ordered[key][1] == raw[key][2]
  doAssert ordered[key][2] == raw[key][0]
doAssert reversed.gameHash() == beforeHash
doAssert parseJson(reversed.playerScoresJson()) == raw

echo "Testing disconnected and absent roster rows retain attribution"
reversed.disconnectPlayerAt(1)
let disconnected = parseJson(reversed.rosterResultsJson([2, 0, 1], 4))
doAssert disconnected["names"] == %*["first", "second", "third", ""]
doAssert disconnected["scores"] == %*[17, 31, 53, 0]
doAssert disconnected["planets"][0].getInt() == 0
doAssert disconnected["ships"][0].getInt() == 0
doAssert disconnected["win"][3].getBool() == false
var duplicateRejected = false
try:
  discard reversed.rosterResultsJson([0, 0, 2], 3)
except ValueError:
  duplicateRejected = true
doAssert duplicateRejected

echo "Testing replay result metadata and historical native result order"
var data: ReplayData
data.configJson = "{\"resultSlotCount\":4}"
for index, slot in [2, 0, 1]:
  data.joins.add ReplayJoin(player: uint8(index), slot: slot)
doAssert data.replayResultsJson(reversed) == reversed.rosterResultsJson([2, 0, 1], 4)
data.configJson = "{}"
for join in data.joins.mitems:
  join.slot = -1
doAssert data.replayResultsJson(reversed) == reversed.playerScoresJson()
