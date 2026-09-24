import
  std/[json, os],
  bitworld/spriteprotocol,
  planet_wars/global,
  planet_wars/replays,
  planet_wars/sim,
  ../players/kudzu/systemone

setCurrentDir(currentSourcePath().parentDir().parentDir())

echo "Testing typed mission choices stay within player-visible candidates"
let missionOptions = @[
  MissionChoice(originId: 1, targetId: 3, budget: 8, score: 10),
  MissionChoice(originId: 2, targetId: 4, budget: 6, score: 20)
]
let missionQuestion = missionRequest(%*{"known_planets": [{"id": 1}, {"id": 2}]}, missionOptions, "jev-latest")
doAssert missionQuestion["questions"]["mission"]["criteria"].len == 2
doAssert parseMissionChoice(%*{"answers": {"mission": {
  "type": "choice", "choice": "mission_1",
  "probabilities": {"mission_0": 0.2, "mission_1": 0.8}
}}}, missionOptions.len) == 1
doAssertRaises(ValueError):
  discard parseMissionChoice(%*{"answers": {"mission": {
    "type": "choice", "choice": "mission_9",
    "probabilities": {"mission_0": 0.2, "mission_1": 0.8}
  }}}, missionOptions.len)
doAssertRaises(ValueError):
  discard parseMissionChoice(%*{"answers": {"mission": {
    "type": "choice", "choice": "mission_0",
    "probabilities": {"mission_0": 0.2, "mission_1": 0.8}
  }}}, missionOptions.len)

const
  PlayerPlanetSpriteBaseForTest = 1000
  PlayerCursorSpriteBaseForTest = 5000
  PlanetTextDigitSpriteBaseForTest = 10000
  PlanetTextObjectBaseForTest = 2300
  PlanetTextMaxCharsForTest = 8
  PlayerNameSpriteBaseForTest = 18100
  ScorePanelDigitSpriteBaseForTest = 18300
  ScorePanelNameSpriteBaseForTest = 18500
  ScorePanelDigitObjectBaseForTest = 15000
  ScorePanelNameObjectBaseForTest = 17000
  ScorePanelMaxScoreCharsForTest = 16

proc findObject(
  objects: openArray[SpritePacketObject],
  objectId: int
): SpritePacketObject =
  ## Returns one packet object or fails the test.
  for item in objects:
    if item.id == objectId:
      return item
  doAssert false, "missing object " & $objectId

echo "Testing default lifecycle config"
let lifecycleConfig = defaultSimConfig()
doAssert lifecycleConfig.planetCount == 47
doAssert lifecycleConfig.maxTicks == TargetFps * 60 * 5
doAssert lifecycleConfig.maxGames == 0

echo "Testing single player does not win before anyone is left"
var soloConfig = defaultSimConfig()
soloConfig.planetCount = 3
soloConfig.maxTicks = 0
var soloGame = initSimServer(123, soloConfig)
discard soloGame.addPlayer("solo")
soloGame.step([])
doAssert not soloGame.gameOver

echo "Testing remaining player wins with neutral planets ignored"
var remainingConfig = defaultSimConfig()
remainingConfig.planetCount = 4
remainingConfig.maxTicks = 0
var remainingGame = initSimServer(124, remainingConfig)
let
  winnerIndex = remainingGame.addPlayer("winner")
  loserIndex = remainingGame.addPlayer("loser")
  winnerId = remainingGame.players[winnerIndex].id
  loserId = remainingGame.players[loserIndex].id
remainingGame.step([])
doAssert not remainingGame.gameOver
for planet in remainingGame.planets.mitems:
  if planet.ownerId == loserId:
    planet.ownerId = 0
remainingGame.step([])
let remainingJson = parseJson(remainingGame.playerScoresJson())
doAssert remainingGame.gameOver
doAssert remainingGame.winnerPlayerId == winnerId
doAssert remainingJson["win"][winnerIndex].getBool()

echo "Testing disconnected players retain fixed result seats"
var disconnectGame = initSimServer(126, defaultSimConfig())
for playerIndex in 0 ..< 8:
  discard disconnectGame.addPlayer("player-" & $playerIndex)
disconnectGame.disconnectPlayerAt(3)
let disconnectJson = parseJson(disconnectGame.playerScoresJson())
doAssert disconnectGame.players.len == 8
doAssert disconnectJson["names"].len == 8
doAssert disconnectJson["scores"].len == 8
doAssert disconnectJson["win"].len == 8
doAssert disconnectJson["planets"].len == 8
doAssert disconnectJson["ships"].len == 8

echo "Testing in-flight ships keep a player active"
var shipConfig = defaultSimConfig()
shipConfig.planetCount = 4
shipConfig.maxTicks = 0
var shipGame = initSimServer(125, shipConfig)
let
  shipWinnerIndex = shipGame.addPlayer("winner")
  shipLoserIndex = shipGame.addPlayer("loser")
  shipWinnerId = shipGame.players[shipWinnerIndex].id
  shipLoserId = shipGame.players[shipLoserIndex].id
shipGame.step([])
for planet in shipGame.planets.mitems:
  if planet.ownerId == shipLoserId:
    planet.ownerId = 0
shipGame.ships.add Ship(
  ownerId: shipLoserId,
  targetPlanet: shipGame.planets[0].id,
  duration: 100
)
shipGame.step([])
doAssert not shipGame.gameOver
shipGame.ships.setLen(0)
shipGame.step([])
doAssert shipGame.gameOver
doAssert shipGame.winnerPlayerId == shipWinnerId

echo "Testing max ticks end"
var timedConfig = defaultSimConfig()
timedConfig.maxTicks = 3
timedConfig.maxGames = 0
var timedGame = initSimServer(456, timedConfig)
for _ in 0 ..< timedConfig.maxTicks:
  timedGame.step([])
doAssert timedGame.gameOver
doAssert timedGame.winnerPlayerId == 0

echo "Testing init packets clear stale objects"
var initGame = initSimServer(789, defaultSimConfig())
var nextState: GlobalViewerState
let initPacket = initGame.buildSpriteProtocolUpdates(
  initGlobalViewerState(),
  nextState
)
doAssert initPacket.len > 0
doAssert initPacket[0] == 0x04'u8

echo "Testing global score panel renders"
var scorePanelGame = initSimServer(793, defaultSimConfig())
let
  redScoreIndex = scorePanelGame.addPlayer("red")
  blueScoreIndex = scorePanelGame.addPlayer("blue")
  redScoreId = scorePanelGame.players[redScoreIndex].id
  blueScoreId = scorePanelGame.players[blueScoreIndex].id
scorePanelGame.players[redScoreIndex].score = 5
scorePanelGame.players[blueScoreIndex].score = 12
scorePanelGame.planets[0].ships = 7
var nextScorePanelState: GlobalViewerState
let scorePanelPacket = scorePanelGame.buildSpriteProtocolUpdates(
  initGlobalViewerState(),
  nextScorePanelState
)
let
  scorePanelObjects = scorePanelPacket.spritePacketObjects()
  scorePanelObjectIds = scorePanelPacket.spritePacketObjectIds()
  scorePanelSpriteIds = scorePanelPacket.spritePacketSpriteIds()
  firstPlanetDigitObject = PlanetTextObjectBaseForTest +
    scorePanelGame.planets[0].id * PlanetTextMaxCharsForTest
  firstPlanetSevenSprite = PlanetTextDigitSpriteBaseForTest + 7
  firstPlanetEightSprite = PlanetTextDigitSpriteBaseForTest + 8
  redScoreNameObject = ScorePanelNameObjectBaseForTest + redScoreId
  blueScoreNameObject = ScorePanelNameObjectBaseForTest + blueScoreId
  blueScoreFirstDigit = ScorePanelDigitObjectBaseForTest +
    blueScoreId * ScorePanelMaxScoreCharsForTest
  blueScoreSecondDigit = blueScoreFirstDigit + 1
doAssert redScoreNameObject in scorePanelObjectIds
doAssert blueScoreNameObject in scorePanelObjectIds
doAssert blueScoreFirstDigit in scorePanelObjectIds
doAssert blueScoreSecondDigit in scorePanelObjectIds
doAssert scorePanelObjects.findObject(blueScoreNameObject).y <
  scorePanelObjects.findObject(redScoreNameObject).y
doAssert PlayerPlanetSpriteBaseForTest + redScoreId * 8 in
  scorePanelSpriteIds
doAssert PlayerCursorSpriteBaseForTest + redScoreId in scorePanelSpriteIds
doAssert PlayerNameSpriteBaseForTest + redScoreId in scorePanelSpriteIds
doAssert firstPlanetSevenSprite in scorePanelSpriteIds
doAssert firstPlanetDigitObject in scorePanelObjectIds
doAssert scorePanelObjects.findObject(firstPlanetDigitObject).spriteId ==
  firstPlanetSevenSprite
doAssert ScorePanelDigitSpriteBaseForTest + 1 in scorePanelSpriteIds
doAssert ScorePanelNameSpriteBaseForTest + redScoreId in scorePanelSpriteIds
var cachedScorePanelState: GlobalViewerState
let cachedScorePanelPacket = scorePanelGame.buildSpriteProtocolUpdates(
  nextScorePanelState,
  cachedScorePanelState
)
let cachedScorePanelSpriteIds =
  cachedScorePanelPacket.spritePacketSpriteIds()
doAssert ScorePanelDigitSpriteBaseForTest + 1 notin cachedScorePanelSpriteIds
doAssert ScorePanelNameSpriteBaseForTest + redScoreId notin
  cachedScorePanelSpriteIds
doAssert PlayerPlanetSpriteBaseForTest + redScoreId * 8 notin
  cachedScorePanelSpriteIds
doAssert PlayerCursorSpriteBaseForTest + redScoreId notin
  cachedScorePanelSpriteIds
doAssert PlayerNameSpriteBaseForTest + redScoreId notin
  cachedScorePanelSpriteIds
doAssert firstPlanetSevenSprite notin cachedScorePanelSpriteIds
scorePanelGame.planets[0].ships += 1
scorePanelGame.players[redScoreIndex].name = "redder"
var changedScorePanelState: GlobalViewerState
let changedScorePanelPacket = scorePanelGame.buildSpriteProtocolUpdates(
  cachedScorePanelState,
  changedScorePanelState
)
let changedScorePanelSpriteIds =
  changedScorePanelPacket.spritePacketSpriteIds()
doAssert firstPlanetSevenSprite notin changedScorePanelSpriteIds
doAssert firstPlanetEightSprite notin changedScorePanelSpriteIds
doAssert changedScorePanelPacket.spritePacketObjects().findObject(
  firstPlanetDigitObject
).spriteId == firstPlanetEightSprite
doAssert PlayerNameSpriteBaseForTest + redScoreId in
  changedScorePanelSpriteIds

echo "Testing cursor chat bubbles render and expire"
var chatGame = initSimServer(790, defaultSimConfig())
let chatPlayerIndex = chatGame.addPlayer("speaker")
chatGame.addChatMessage(chatPlayerIndex, "hello")
doAssert chatGame.chatMessages.len == 1
var nextPlayerState: PlayerViewerState
let chatPacket = chatGame.buildSpriteProtocolPlayerUpdates(
  chatPlayerIndex,
  initPlayerViewerState(),
  nextPlayerState
)
doAssert chatPacket.len > 0
for _ in 0 ..< ChatBubbleTicks:
  chatGame.step([])
doAssert chatGame.chatMessages.len == 0

echo "Testing eliminated player cursor visibility"
var cursorConfig = defaultSimConfig()
cursorConfig.planetCount = 4
cursorConfig.maxTicks = 0
var cursorGame = initSimServer(791, cursorConfig)
let
  viewerIndex = cursorGame.addPlayer("viewer")
  hiddenIndex = cursorGame.addPlayer("hidden")
  viewerId = cursorGame.players[viewerIndex].id
  hiddenId = cursorGame.players[hiddenIndex].id
cursorGame.players[hiddenIndex].cursorX = cursorGame.players[viewerIndex].cursorX
cursorGame.players[hiddenIndex].cursorY = cursorGame.players[viewerIndex].cursorY
for planet in cursorGame.planets.mitems:
  if planet.ownerId == hiddenId:
    planet.ownerId = 0
var
  viewerState: PlayerViewerState
  hiddenState: PlayerViewerState
let
  hiddenCursorObjectId = 12000 + hiddenId
  viewerPacket = cursorGame.buildSpriteProtocolPlayerUpdates(
    viewerIndex,
    initPlayerViewerState(),
    viewerState
  )
  hiddenPacket = cursorGame.buildSpriteProtocolPlayerUpdates(
    hiddenIndex,
    initPlayerViewerState(),
    hiddenState
  )
doAssert cursorGame.countOwnedPlanets(hiddenId) == 0
doAssert cursorGame.countOwnedPlanets(viewerId) > 0
doAssert hiddenCursorObjectId notin viewerPacket.spritePacketObjectIds()
doAssert hiddenCursorObjectId in hiddenPacket.spritePacketObjectIds()

echo "Testing cursor accelerates over long holds"
var speedGame = initSimServer(792, cursorConfig)
let speedPlayerIndex = speedGame.addPlayer("speed")
speedGame.players[speedPlayerIndex].cursorX = WorldWidthPixels div 2
speedGame.players[speedPlayerIndex].cursorY = WorldHeightPixels div 2
for _ in 0 ..< TargetFps:
  speedGame.applyInput(speedPlayerIndex, PlayerInput(right: true))
doAssert speedGame.players[speedPlayerIndex].cursorVelX > CursorMaxSpeed
doAssert speedGame.players[speedPlayerIndex].cursorVelX <= CursorBoostMaxSpeed

echo "Testing waiting lobby holds the game until everyone joins"
var lobbyConfig = defaultSimConfig()
lobbyConfig.planetCount = 6
lobbyConfig.maxTicks = 10
var lobbyGame = initSimServer(321, lobbyConfig, expectedPlayers = 2)
doAssert lobbyGame.waitingForPlayers
for _ in 0 ..< 5:
  lobbyGame.step([PlayerInput(right: true, attackPressed: true)])
doAssert lobbyGame.waitingForPlayers
doAssert lobbyGame.tickCount == 0
let lobbyFirstIndex = lobbyGame.addPlayer("early")
lobbyGame.step([])
doAssert lobbyGame.waitingForPlayers
doAssert lobbyGame.tickCount == 0
doAssert lobbyGame.planets[lobbyGame.players[lobbyFirstIndex].originPlanet].ships == 10
discard lobbyGame.addPlayer("late")
lobbyGame.step([])
doAssert not lobbyGame.waitingForPlayers
doAssert lobbyGame.tickCount == 0
lobbyGame.step([])
doAssert lobbyGame.tickCount == 1
var lobbyWaitingState: GlobalViewerState
var lobbyWaitingNext: GlobalViewerState
var lobbyView = initSimServer(322, lobbyConfig, expectedPlayers = 2)
let lobbyPacket = lobbyView.buildSpriteProtocolUpdates(
  lobbyWaitingState,
  lobbyWaitingNext
)
doAssert 4003 in lobbyPacket.spritePacketObjectIds()

echo "Testing waiting lobby starts after the timeout"
var timeoutGame = initSimServer(323, lobbyConfig, expectedPlayers = 2)
discard timeoutGame.addPlayer("only")
for _ in 0 ..< WaitForPlayersTimeoutTicks:
  timeoutGame.step([])
doAssert not timeoutGame.waitingForPlayers
doAssert timeoutGame.tickCount == 0
timeoutGame.step([])
doAssert timeoutGame.tickCount == 1

proc scriptedMask(playerIndex, tick: int): uint8 =
  ## Returns a deterministic scripted input mask for replay tests.
  if playerIndex == 0:
    if tick mod 60 < 30:
      result = ButtonRight or ButtonA
    elif tick mod 60 < 45:
      result = ButtonDown or ButtonB
  else:
    if tick mod 40 < 20:
      result = ButtonLeft
    elif tick mod 40 < 30:
      result = ButtonUp or ButtonA

echo "Testing replay records and plays back deterministically"
const ReplayTestTicks = 200
var replayConfig = defaultSimConfig()
replayConfig.planetCount = 6
replayConfig.maxTicks = ReplayTestTicks
replayConfig.maxGames = 1
let replayTestSeed = 424242
var recordedGame = initSimServer(
  replayTestSeed,
  replayConfig,
  expectedPlayers = 2
)
recordedGame.step([])
doAssert recordedGame.waitingForPlayers
let replayPath = getTempDir() / "planet-wars-test.bitreplay"
var writer = openReplayWriter(
  replayPath,
  $(%*{
    "seed": replayTestSeed,
    "planetCount": replayConfig.planetCount,
    "maxTicks": replayConfig.maxTicks,
    "maxGames": replayConfig.maxGames,
    "tokenCount": 0
  })
)
doAssert writer.enabled
var appliedMasks = [0'u8, 0'u8]
var connected = [true, true]
for playerIndex in 0 ..< 2:
  let joinedIndex = recordedGame.addPlayer("bot" & $playerIndex)
  doAssert joinedIndex == playerIndex
  writer.writeJoin(
    tickTime(recordedGame.tickCount),
    playerIndex,
    "bot" & $playerIndex,
    -1,
    ""
  )
  while writer.lastMasks.len < recordedGame.players.len:
    writer.lastMasks.add(0)
writer.writeChat(tickTime(recordedGame.tickCount), 0, "glhf")
recordedGame.addChatMessage(0, "glhf")
recordedGame.step([])
doAssert not recordedGame.waitingForPlayers
doAssert recordedGame.tickCount == 0
while not recordedGame.gameOver:
  if recordedGame.tickCount == ReplayTestTicks - 1:
    writer.writeLeave(tickTime(recordedGame.tickCount), 1)
    recordedGame.disconnectPlayerAt(1)
    connected[1] = false
  var inputs = newSeq[PlayerInput](recordedGame.players.len)
  for playerIndex in 0 ..< recordedGame.players.len:
    if not connected[playerIndex]:
      continue
    let mask = scriptedMask(playerIndex, recordedGame.tickCount)
    inputs[playerIndex] = playerInputFromMasks(
      mask,
      appliedMasks[playerIndex]
    )
    appliedMasks[playerIndex] = mask
    writer.writeInputMaskChange(
      tickTime(recordedGame.tickCount),
      playerIndex,
      mask
    )
  recordedGame.step(inputs)
  writer.writeHash(uint32(recordedGame.tickCount), recordedGame.gameHash())
writer.closeReplayWriter()
doAssert recordedGame.tickCount == ReplayTestTicks
let recordedFinalHash = recordedGame.gameHash()

let replayData = loadReplay(replayPath)
let replaySettings = replayData.replaySimSettings()
doAssert replaySettings.seed == replayTestSeed
doAssert replaySettings.config.planetCount == replayConfig.planetCount
doAssert replaySettings.config.maxTicks == replayConfig.maxTicks
var
  playbackGame = initSimServer(replaySettings.seed, replaySettings.config)
  playback = initReplayPlayer(replayData)
doAssert playback.replayMaxTick() == ReplayTestTicks
while playback.playing:
  playback.stepReplay(playbackGame)
doAssert not playback.hashValidationFailed
doAssert playbackGame.tickCount == ReplayTestTicks
doAssert playbackGame.gameHash() == recordedFinalHash
doAssert playbackGame.players.len == 2
doAssert playbackGame.chatMessages.len == recordedGame.chatMessages.len
doAssert playbackGame.chatMessages[0].text == "glhf"

echo "Testing replay keyframes seek to exact ticks"
var
  seekGame = initSimServer(replaySettings.seed, replaySettings.config)
  seeker = initReplayPlayer(replayData)
seeker.buildReplayKeyframes(replaySettings.seed, replaySettings.config)
doAssert seeker.keyframes.len == ReplayTestTicks div ReplayKeyframeTicks + 1
var
  referenceGame = initSimServer(replaySettings.seed, replaySettings.config)
  reference = initReplayPlayer(replayData)
while referenceGame.tickCount < 150:
  reference.stepReplay(referenceGame)
seeker.applyReplaySeek(seekGame, 150)
doAssert not seeker.playing
doAssert seekGame.tickCount == 150
doAssert seekGame.gameHash() == referenceGame.gameHash()
seeker.applyReplaySeek(seekGame, 42)
doAssert seekGame.tickCount == 42
seeker.applyReplaySeek(seekGame, ReplayTestTicks)
doAssert seekGame.tickCount == ReplayTestTicks
doAssert seekGame.gameHash() == recordedFinalHash

echo "Testing replay transport commands"
seeker.applyReplayCommand(seekGame, ' ')
doAssert seeker.playing
seeker.applyReplayCommand(seekGame, ' ')
doAssert not seeker.playing
seeker.applyReplayCommand(seekGame, '8')
doAssert seeker.replaySpeed() == 8
seeker.applyReplayCommand(seekGame, '-')
doAssert seeker.replaySpeed() == 4
seeker.applyReplayCommand(seekGame, '<')
doAssert seekGame.tickCount == 0
seeker.applyReplayCommand(seekGame, 'e')
doAssert seekGame.tickCount == ReplayTestTicks
removeFile(replayPath)
