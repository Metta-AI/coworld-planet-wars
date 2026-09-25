import std/[base64, json, os]
import planet_wars/[global, replays, sim]
import bridge

setCurrentDir(currentSourcePath().parentDir().parentDir())

for seed in [7, 108519]:
  var bridge: TrainingBridge
  let resetReply = bridge.reset(seed, 120, 12, 8)
  var config = defaultSimConfig()
  config.maxTicks = 120
  config.planetCount = 12
  var direct = initSimServer(seed, config, expectedPlayers = 8)
  var viewers: array[8, PlayerViewerState]
  for seat in 0 ..< 8:
    discard direct.addPlayer("training-" & $seat)
    viewers[seat] = initPlayerViewerState()
  direct.step([])
  for seat in 0 ..< 8:
    var nextViewer: PlayerViewerState
    let packet = direct.buildSpriteProtocolPlayerUpdates(
      seat, viewers[seat], nextViewer
    )
    doAssert resetReply["observations"][seat].getStr() == encode(packet)
    viewers[seat] = nextViewer

  var previousMasks: array[8, uint8]
  for turn in 0 ..< 20:
    let mask = if turn mod 2 == 0: 8'u8 else: 32'u8
    var masks = newSeq[uint8](8)
    var packets: array[8, seq[uint8]]
    for seat in 0 ..< 8:
      masks[seat] = if seat mod 2 == 0: mask else: 64'u8
    for _ in 0 ..< 6:
      var inputs: array[8, PlayerInput]
      for seat in 0 ..< 8:
        inputs[seat] = playerInputFromMasks(masks[seat], previousMasks[seat])
        previousMasks[seat] = masks[seat]
      direct.step(inputs)
      for seat in 0 ..< 8:
        var nextViewer: PlayerViewerState
        packets[seat].add(direct.buildSpriteProtocolPlayerUpdates(
          seat, viewers[seat], nextViewer
        ))
        viewers[seat] = nextViewer
    let reply = bridge.step(masks, 6)
    doAssert reply["tick"].getInt() == direct.tickCount
    doAssert bridge.sim.gameHash() == direct.gameHash()
    for seat in 0 ..< 8:
      doAssert reply["observations"][seat].getStr() == encode(packets[seat])
      doAssert reply["scores"][seat].getInt() == direct.players[seat].score
  doAssert direct.gameOver

echo "training bridge matches ordinary player packets and input masks"
