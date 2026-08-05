import
  std/[json, os],
  bitworld/spriteprotocol,
  planet_wars/global,
  planet_wars/replays,
  planet_wars/sim

setCurrentDir(currentSourcePath().parentDir().parentDir())

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
  var inputs = newSeq[PlayerInput](recordedGame.players.len)
  for playerIndex in 0 ..< recordedGame.players.len:
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

echo "Testing planet hit test only picks planets under the point"
var hitConfig = defaultSimConfig()
hitConfig.planetCount = 6
hitConfig.maxTicks = 0
var hitGame = initSimServer(4242, hitConfig)
let probePlanet = hitGame.planets[0]
doAssert hitGame.planetIdAt(probePlanet.x, probePlanet.y) == probePlanet.id
doAssert hitGame.planetIdAt(
  probePlanet.x + probePlanet.radius + PlanetClickPad - 1,
  probePlanet.y
) == probePlanet.id
# Far from every planet the click selects nothing rather than snapping to
# the nearest, which is how the old cursor behaved.
var emptyX = 0
block findEmpty:
  for x in countup(0, WorldWidthPixels - 1, 3):
    for y in countup(0, WorldHeightPixels - 1, 3):
      if hitGame.planetIdAt(x, y) < 0:
        emptyX = x
        doAssert hitGame.planetIdAt(x, y) == -1
        break findEmpty
doAssert emptyX >= 0

echo "Testing click selects, shift-click adds, and a target sends"
var clickConfig = defaultSimConfig()
clickConfig.planetCount = 8
clickConfig.maxTicks = 0
var clickGame = initSimServer(99, clickConfig)
let clickPlayer = clickGame.addPlayer("clicker")
# Give the player a second planet so multi-select can be exercised.
var ownedIds: seq[int] = @[]
for planet in clickGame.planets.mitems:
  if planet.ownerId == clickGame.players[clickPlayer].id:
    ownedIds.add(planet.id)
var extraId = -1
for planet in clickGame.planets.mitems:
  if planet.ownerId == 0 and extraId < 0:
    planet.ownerId = clickGame.players[clickPlayer].id
    planet.ships = 20
    extraId = planet.id
doAssert extraId > 0
let firstOwnedId = ownedIds[0]

proc clickAt(game: SimServer, planetId: int,
    kind: PlayerCommandKind): PlayerInput =
  ## Builds one input carrying a single click on a planet's centre.
  let index = game.findPlanetIndexById(planetId)
  result.commandCount = 1
  result.commands[0] = PlayerCommand(
    kind: kind,
    x: game.planets[index].x,
    y: game.planets[index].y
  )

clickGame.step([clickGame.clickAt(firstOwnedId, CommandClick)])
doAssert clickGame.players[clickPlayer].selectedPlanetIds == @[firstOwnedId]
clickGame.step([clickGame.clickAt(extraId, CommandShiftClick)])
doAssert clickGame.players[clickPlayer].selectedPlanetIds.len == 2
doAssert extraId in clickGame.players[clickPlayer].selectedPlanetIds

echo "Testing a wave sends half of each selected planet and keeps selection"
var targetId = -1
for planet in clickGame.planets:
  if planet.ownerId == 0:
    targetId = planet.id
    break
doAssert targetId > 0
let
  beforeShips = block:
    var total = 0
    for planetId in clickGame.players[clickPlayer].selectedPlanetIds:
      total += clickGame.planets[clickGame.findPlanetIndexById(planetId)].ships
    total
  selectionBefore = clickGame.players[clickPlayer].selectedPlanetIds
clickGame.step([clickGame.clickAt(targetId, CommandClick)])
var afterShips = 0
for planetId in selectionBefore:
  afterShips += clickGame.planets[clickGame.findPlanetIndexById(planetId)].ships
doAssert clickGame.ships.len > 0
doAssert afterShips < beforeShips
# Half of each planet, and never enough to abandon one.
doAssert afterShips >= selectionBefore.len
doAssert clickGame.players[clickPlayer].selectedPlanetIds == selectionBefore

echo "Testing sends never drop a planet below one ship"
var drainGame = initSimServer(7, clickConfig)
let drainPlayer = drainGame.addPlayer("drainer")
drainGame.players[drainPlayer].sendPercent = 100
var drainOriginId = -1
for planet in drainGame.planets.mitems:
  if planet.ownerId == drainGame.players[drainPlayer].id:
    planet.ships = 10
    drainOriginId = planet.id
var drainTargetId = -1
for planet in drainGame.planets:
  if planet.ownerId == 0:
    drainTargetId = planet.id
    break
drainGame.players[drainPlayer].selectedPlanetIds = @[drainOriginId]
discard drainGame.sendFleet(drainPlayer, drainTargetId)
doAssert drainGame.planets[
  drainGame.findPlanetIndexById(drainOriginId)
].ships == 1

echo "Testing a new player defaults to half-strength waves"
doAssert drainGame.players[drainPlayer].id > 0
var defaultGame = initSimServer(11, clickConfig)
let defaultPlayer = defaultGame.addPlayer("fresh")
doAssert defaultGame.players[defaultPlayer].sendPercent == DefaultSendPercent
doAssert DefaultSendPercent == 50

echo "Testing friendly ships separate and rival ships pass through"
var pushConfig = defaultSimConfig()
pushConfig.planetCount = 4
pushConfig.maxTicks = 0
var pushGame = initSimServer(21, pushConfig)
let
  pushA = pushGame.addPlayer("a")
  pushB = pushGame.addPlayer("b")
let pushTarget = pushGame.planets[0].id
proc stackedShip(owner, target: int): Ship =
  ## Two ships sharing one position, already launched.
  Ship(
    ownerId: owner,
    targetPlanet: target,
    posX: 100 * SubpixelScale,
    posY: 100 * SubpixelScale,
    heading: 0,
    duration: 100
  )
pushGame.ships = @[
  stackedShip(pushGame.players[pushA].id, pushTarget),
  stackedShip(pushGame.players[pushA].id, pushTarget)
]
pushGame.step([PlayerInput(), PlayerInput()])
let friendlyGap =
  abs(pushGame.ships[0].posX - pushGame.ships[1].posX) +
  abs(pushGame.ships[0].posY - pushGame.ships[1].posY)
doAssert friendlyGap > 0

pushGame.ships = @[
  stackedShip(pushGame.players[pushA].id, pushTarget),
  stackedShip(pushGame.players[pushB].id, pushTarget)
]
pushGame.step([PlayerInput(), PlayerInput()])
let rivalGap =
  abs(pushGame.ships[0].posX - pushGame.ships[1].posX) +
  abs(pushGame.ships[0].posY - pushGame.ships[1].posY)
doAssert rivalGap == 0

echo "Testing an unchanged board re-sends nothing"
var deltaConfig = defaultSimConfig()
deltaConfig.planetCount = 20
deltaConfig.maxTicks = 0
var deltaGame = initSimServer(811, deltaConfig)
let deltaIndex = deltaGame.addPlayer("watcher")
var deltaFirstState: PlayerViewerState
let deltaFirstPacket = deltaGame.buildSpriteProtocolPlayerUpdates(
  deltaIndex,
  initPlayerViewerState(),
  deltaFirstState
)
# The first packet is a full snapshot: every planet, its digits and the map.
doAssert deltaFirstPacket.spritePacketObjectIds().len > 20

var deltaSecondState: PlayerViewerState
let deltaSecondPacket = deltaGame.buildSpriteProtocolPlayerUpdates(
  deltaIndex,
  deltaFirstState,
  deltaSecondState
)
# Nothing moved between the two builds, so nothing should go on the wire.
doAssert deltaSecondPacket.spritePacketObjectIds().len == 0

echo "Testing one changed planet re-sends only that planet"
deltaGame.planets[0].ships = 7
var deltaThirdState: PlayerViewerState
let deltaThirdPacket = deltaGame.buildSpriteProtocolPlayerUpdates(
  deltaIndex,
  deltaSecondState,
  deltaThirdState
)
let deltaThirdIds = deltaThirdPacket.spritePacketObjectIds()
doAssert deltaThirdIds.len > 0
doAssert deltaThirdIds.len <= 2
doAssert PlanetTextObjectBaseForTest +
  deltaGame.planets[0].id * PlanetTextMaxCharsForTest in deltaThirdIds

echo "Testing config sets the starting wave size"
var percentConfig = defaultSimConfig()
percentConfig.planetCount = 4
percentConfig.maxTicks = 0
percentConfig.defaultSendPercent = 80
var percentGame = initSimServer(823, percentConfig)
let percentIndex = percentGame.addPlayer("sender")
doAssert percentGame.players[percentIndex].sendPercent == 80
# Out-of-range config must clamp rather than produce an unusable player.
var wildConfig = percentConfig
wildConfig.defaultSendPercent = 500
var wildGame = initSimServer(824, wildConfig)
doAssert wildGame.players[wildGame.addPlayer("wild")].sendPercent == 100
