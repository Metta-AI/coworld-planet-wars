import
  std/[json, math, os, random, strutils],
  bitworld/client as bitworldClient, bitworld/pixelfonts, bitworld/profile,
  bitworld/sprites

const
  GameName* = "planet_wars"
  GameVersion* = "2"
  WorldWidthPixels* = 512
  WorldHeightPixels* = 512
  PlayerViewportWidth* = 320
  PlayerViewportHeight* = 200
  DefaultPlanetCount* = 47
  MinPlanetCount* = 1
  MaxPlanetCount* = 48
  DensePlanetCount* = 47
  PlanetSpawnMargin* = 12
  PlanetSpacing* = 10
  PlanetClickPad* = 10
  BaseFps* = 24
  TargetFps* = 60
  WaitForPlayersTimeoutTicks* = TargetFps * 30
  DefaultMaxTicks* = TargetFps * 60 * 5
  DefaultMaxGames* = 0
  ShipSpeedPixelsPerSecond* = 48
  BaseSendRepeatInterval* = 6
  MinSendRepeatInterval* = 1
  SendAccelerationTicks* = 10
  ShipLaneOffsetMax* = 3
  ## Ships leave from points spaced around the planet's edge. One ring is
  ## as many as fit; anything more waits for the next ring.
  ShipsPerRing* = 12
  ## Fixed-point movement. Integer only, so replays stay bit-identical.
  SubpixelScale* = 256
  HeadingCount* = 256
  TrigScale* = 4096
  ShipSpeedSubpixels* =
    (ShipSpeedPixelsPerSecond * SubpixelScale) div TargetFps
  ShipRadiusSubpixels* = 6 * SubpixelScale
  ShipPushSubpixels* = 60
  CollisionCellPixels* = 16
  CollisionGridSide* = WorldWidthPixels div CollisionCellPixels
  RingLaunchDelayTicks* = 4
  DefaultSendPercent* = 50
  ScoreIntervalTicks* = TargetFps
  WebSocketPath* = "/player"
  GlobalWebSocketPath* = "/global"
  AdminWebSocketPath* = "/admin"
  ReplayWebSocketPath* = "/replay"
  RewardWebSocketPath* = "/reward"
  MotionScale* = 256
  CursorAccel* = 30
  CursorFrictionNum* = 232
  CursorFrictionDen* = 256
  CursorMaxSpeed* = 282
  CursorBoostStartTicks* = TargetFps div 6
  CursorBoostSpeedPerTick* = 8
  CursorBoostMaxSpeed* = 640
  CursorStopThreshold* = 5
  BackgroundColor* = RgbaColor(r: 5'u8, g: 7'u8, b: 18'u8, a: 255'u8)
  NeutralPlanetColor* = RgbaColor(
    r: 102'u8,
    g: 112'u8,
    b: 136'u8,
    a: 255'u8
  )
  SelectionColor* = RgbaColor(
    r: 255'u8,
    g: 231'u8,
    b: 82'u8,
    a: 255'u8
  )
  OriginColor* = RgbaColor(r: 84'u8, g: 244'u8, b: 232'u8, a: 255'u8)
  ScoreColor* = RgbaColor(r: 248'u8, g: 250'u8, b: 255'u8, a: 255'u8)
  BlackColor* = RgbaColor(r: 0'u8, g: 0'u8, b: 0'u8, a: 255'u8)
  WhiteColor* = RgbaColor(r: 255'u8, g: 255'u8, b: 255'u8, a: 255'u8)
  ChatBubbleTicks* = TargetFps * 5
  StarColors* = [
    RgbaColor(r: 168'u8, g: 211'u8, b: 255'u8, a: 255'u8),
    RgbaColor(r: 255'u8, g: 246'u8, b: 194'u8, a: 255'u8),
    RgbaColor(r: 213'u8, g: 225'u8, b: 255'u8, a: 255'u8)
  ]
  MapSpriteId* = 1
  MapObjectId* = 1
  MapLayerId* = 0
  MapLayerType* = 0
  TopLeftLayerId* = 1
  TopLeftLayerType* = 1
  ZoomableLayerFlag* = 1
  UiLayerFlag* = 2
  ChatMaxChars* = 40

type
  PlanetWarsError* = object of CatchableError

  SimConfig* = object
    planetCount*: int
    maxTicks*: int
    maxGames*: int
    defaultSendPercent*: int

  PlanetSize* = enum
    PlanetSmall
    PlanetMedium
    PlanetLarge

  Planet* = object
    id*: int
    x*: int
    y*: int
    radius*: int
    size*: PlanetSize
    ownerId*: int
    ships*: int
    growthInterval*: int
    growthTicks*: int

  Ship* = object
    ownerId*: int
    color*: RgbaColor
    targetPlanet*: int
    startX*: int
    startY*: int
    endX*: int
    endY*: int
    progress*: int
    duration*: int
    ## Ticks left on the launch pad. A wave larger than one ring around
    ## the planet leaves in successive rings rather than as one blob.
    launchDelay*: int
    ## Live position in subpixels and a heading in 256 steps. Ships steer
    ## toward their target rather than sliding along a fixed line, which
    ## is what lets them be pushed aside without losing their way.
    posX*: int
    posY*: int
    heading*: uint8

  Star* = object
    x*: int
    y*: int
    color*: RgbaColor

  Player* = object
    id*: int
    name*: string
    color*: RgbaColor
    colorHue*: int
    score*: int
    selectedPlanet*: int
    originPlanet*: int
    sendCooldown*: int
    sendHoldTicks*: int
    cursorX*: int
    cursorY*: int
    cursorVelX*: int
    cursorVelY*: int
    cursorCarryX*: int
    cursorCarryY*: int
    cursorInputX*: int
    cursorInputY*: int
    cursorBoostTicks*: int
    ## Planets held for the next send, by stable planet id. Ids rather than
    ## indices because a selection outlives the array ordering.
    selectedPlanetIds*: seq[int]
    sendPercent*: int

  ChatMessage* = object
    playerId*: int
    text*: string
    tick*: int

  PlayerCommandKind* = enum
    CommandNone
    CommandClick
    CommandShiftClick
    CommandSelectAll

  PlayerCommand* = object
    kind*: PlayerCommandKind
    x*: int
    y*: int

  PlayerInput* = object
    up*: bool
    down*: bool
    left*: bool
    right*: bool
    attackPressed*: bool
    sendHeld*: bool
    ## Mouse play. The cursor is placed directly rather than steered, and
    ## clicks arrive as discrete commands, so more than one can land in a
    ## single tick. Four is past what a hand can produce at 60 Hz.
    hasCursor*: bool
    cursorX*: int
    cursorY*: int
    sendPercent*: int
    commandCount*: int
    commands*: array[4, PlayerCommand]

  SimServer* = object
    config*: SimConfig
    players*: seq[Player]
    planets*: seq[Planet]
    ships*: seq[Ship]
    stars*: seq[Star]
    rng*: Rand
    nextPlayerId*: int
    scoreTicks*: int
    tickCount*: int
    gameOver*: bool
    winnerPlayerId*: int
    maxActiveOwnerCount*: int
    scoreRevision*: int
    textFont*: PixelFont
    chatMessages*: seq[ChatMessage]
    waitingForPlayers*: bool
    expectedPlayers*: int
    waitTicks*: int

proc clientDataDir*(): string =
  ## Returns the shared client data directory.
  bitworldClient.clientDir() / "data"

proc loadTiny5Font*(): PixelFont =
  ## Loads the shared Tiny5 variable-width pixel font.
  readTiny5Font()

proc defaultSimConfig*(): SimConfig =
  ## Returns the default Planet Wars simulation config.
  SimConfig(
    planetCount: DefaultPlanetCount,
    maxTicks: DefaultMaxTicks,
    maxGames: DefaultMaxGames,
    defaultSendPercent: DefaultSendPercent
  )

proc checkedPlanetCount*(planetCount: int): int =
  ## Returns a supported planet count or raises a game error.
  if planetCount < MinPlanetCount or planetCount > MaxPlanetCount:
    raise newException(
      PlanetWarsError,
      "planetCount must be between " & $MinPlanetCount & " and " &
        $MaxPlanetCount & "."
    )
  planetCount

proc checkSimConfig*(config: SimConfig) =
  ## Raises when simulation config values are outside supported bounds.
  discard config.planetCount.checkedPlanetCount()
  if config.maxTicks < 0:
    raise newException(
      PlanetWarsError,
      "maxTicks must be zero or greater."
    )
  if config.maxGames < 0:
    raise newException(
      PlanetWarsError,
      "maxGames must be zero or greater."
    )

proc worldClampPixel*(x, maxValue: int): int =
  ## Clamps a coordinate to the world pixel bounds.
  max(0, min(maxValue, x))

proc scaledTicks(ticksAtBaseFps: int): int =
  ## Converts a 24 Hz tick duration to the current simulation rate.
  max(1, (ticksAtBaseFps * TargetFps + BaseFps - 1) div BaseFps)

proc planetRadius*(size: PlanetSize): int =
  ## Returns the gameplay radius for one planet size.
  case size
  of PlanetSmall:
    9
  of PlanetMedium:
    11
  of PlanetLarge:
    14

proc initialShips(size: PlanetSize, rng: var Rand): int =
  ## Returns a randomized neutral ship count for one planet.
  case size
  of PlanetSmall:
    4 + rng.rand(3)
  of PlanetMedium:
    7 + rng.rand(4)
  of PlanetLarge:
    11 + rng.rand(5)

proc growthInterval(size: PlanetSize, rng: var Rand): int =
  ## Returns a randomized growth interval for one planet.
  case size
  of PlanetSmall:
    scaledTicks(42 + rng.rand(12))
  of PlanetMedium:
    scaledTicks(30 + rng.rand(10))
  of PlanetLarge:
    scaledTicks(20 + rng.rand(8))

proc randomPlanetSize(rng: var Rand): PlanetSize =
  ## Returns a randomized planet size.
  case rng.rand(99)
  of 0 .. 44:
    PlanetSmall
  of 45 .. 79:
    PlanetMedium
  else:
    PlanetLarge

proc planetsOverlap(a, b: Planet): bool =
  ## Returns true when two generated planets are too close together.
  let
    dx = a.x - b.x
    dy = a.y - b.y
    minDistance = a.radius + b.radius + PlanetSpacing
  dx * dx + dy * dy < minDistance * minDistance

proc randomConfiguredPlanetSize(
  rng: var Rand,
  planetCount: int
): PlanetSize =
  ## Returns a random planet size for the configured map density.
  if planetCount > DensePlanetCount:
    return PlanetSmall
  randomPlanetSize(rng)

proc addGeneratedPlanet(
  sim: var SimServer,
  size: PlanetSize,
  x,
  y: int
): bool =
  ## Adds one generated planet when it does not overlap existing planets.
  let planet = Planet(
    id: sim.planets.len + 1,
    x: x,
    y: y,
    radius: planetRadius(size),
    size: size,
    ownerId: 0,
    ships: initialShips(size, sim.rng),
    growthInterval: growthInterval(size, sim.rng)
  )
  for existing in sim.planets:
    if planet.planetsOverlap(existing):
      return false
  sim.planets.add planet
  true

proc densePlanetPositions(sim: var SimServer): seq[tuple[x, y: int]] =
  ## Returns shuffled grid positions for dense planet fallback.
  let
    radius = planetRadius(PlanetSmall)
    step = radius * 2 + PlanetSpacing
    minCoord = PlanetSpawnMargin + radius
    maxX = WorldWidthPixels - PlanetSpawnMargin - radius - 1
    maxY = WorldHeightPixels - PlanetSpawnMargin - radius - 1
  for y in countup(minCoord, maxY, step):
    for x in countup(minCoord, maxX, step):
      result.add((x: x, y: y))
  shuffle(sim.rng, result)

proc fillDensePlanets(sim: var SimServer, planetCount: int) =
  ## Fills remaining dense map slots with small planets on a grid.
  var positions = sim.densePlanetPositions()
  for position in positions:
    if sim.planets.len >= planetCount:
      return
    discard sim.addGeneratedPlanet(PlanetSmall, position.x, position.y)

proc markScoresChanged(sim: var SimServer) =
  ## Marks score-visible game state as changed.
  inc sim.scoreRevision

proc generatePlanets(sim: var SimServer) {.measure.} =
  ## Generates non-overlapping planets in the world.
  let planetCount = sim.config.planetCount.checkedPlanetCount()
  var attempts = 0
  while sim.planets.len < planetCount and
      attempts < max(800, planetCount * 320):
    inc attempts
    let
      size = sim.rng.randomConfiguredPlanetSize(planetCount)
      radius = planetRadius(size)
      xSpan = WorldWidthPixels - (PlanetSpawnMargin + radius) * 2
      ySpan = WorldHeightPixels - (PlanetSpawnMargin + radius) * 2
      x = PlanetSpawnMargin + radius + sim.rng.rand(xSpan)
      y = PlanetSpawnMargin + radius + sim.rng.rand(ySpan)
    discard sim.addGeneratedPlanet(size, x, y)
  if sim.planets.len < planetCount:
    sim.fillDensePlanets(planetCount)
  if sim.planets.len < planetCount:
    raise newException(
      PlanetWarsError,
      "Could only place " & $sim.planets.len & " of " & $planetCount &
        " requested planets."
    )

proc generateStars(sim: var SimServer) {.measure.} =
  ## Generates decorative star positions for the protocol background.
  for _ in 0 ..< 120:
    sim.stars.add Star(
      x: sim.rng.rand(WorldWidthPixels - 1),
      y: sim.rng.rand(WorldHeightPixels - 1),
      color: StarColors[sim.rng.rand(StarColors.high)]
    )

proc colorFromHsv*(hue, saturation, value: int): RgbaColor =
  ## Converts HSV values to an opaque RGB color.
  let
    h = ((hue mod 360) + 360) mod 360
    s = max(0, min(100, saturation))
    v = max(0, min(100, value)) * 255 div 100
    c = v * s div 100
    x = c * (60 - abs((h mod 120) - 60)) div 60
    m = v - c
  var
    r = 0
    g = 0
    b = 0
  case h div 60
  of 0:
    r = c
    g = x
  of 1:
    r = x
    g = c
  of 2:
    g = c
    b = x
  of 3:
    g = x
    b = c
  of 4:
    r = x
    b = c
  else:
    r = c
    b = x
  RgbaColor(
    r: uint8(r + m),
    g: uint8(g + m),
    b: uint8(b + m),
    a: 255'u8
  )

proc hueDistance(a, b: int): int =
  ## Returns the shortest circular distance between two hues.
  let distance = abs(a - b) mod 360
  min(distance, 360 - distance)

proc randomBrightPlayerColor*(
  sim: var SimServer
): tuple[hue: int, color: RgbaColor] =
  ## Returns a random bright HSV color away from existing players.
  var
    bestHue = sim.rng.rand(359)
    bestDistance = -1
  for _ in 0 ..< 24:
    let hue = sim.rng.rand(359)
    var minDistance = 360
    for player in sim.players:
      minDistance = min(minDistance, hue.hueDistance(player.colorHue))
    if sim.players.len == 0 or minDistance > bestDistance:
      bestHue = hue
      bestDistance = minDistance
    if minDistance >= 32:
      break
  let
    saturation = 82 + sim.rng.rand(16)
    value = 92 + sim.rng.rand(8)
  (hue: bestHue, color: colorFromHsv(bestHue, saturation, value))

proc ownerBaseColor*(sim: SimServer, ownerId: int): RgbaColor =
  ## Returns the full color for a planet or ship owner.
  if ownerId == 0:
    return NeutralPlanetColor
  for player in sim.players:
    if player.id == ownerId:
      return player.color
  NeutralPlanetColor

proc ownerVisibleColor*(sim: SimServer, viewerId, ownerId: int): RgbaColor =
  ## Returns a viewer-specific owner color.
  discard viewerId
  sim.ownerBaseColor(ownerId)

proc findPlanetIndexById*(sim: SimServer, planetId: int): int =
  ## Finds a planet index by its stable id.
  for i, planet in sim.planets:
    if planet.id == planetId:
      return i
  -1

proc countOwnedPlanets*(sim: SimServer, playerId: int): int =
  ## Counts planets owned by one player id.
  for planet in sim.planets:
    if planet.ownerId == playerId:
      inc result

proc totalPlayerShips*(sim: SimServer, playerId: int): int =
  ## Counts all ships owned by one player in planets and in transit.
  for planet in sim.planets:
    if planet.ownerId == playerId:
      result += max(0, planet.ships)
  for ship in sim.ships:
    if ship.ownerId == playerId:
      inc result

proc claimPlanetForPlayer(sim: var SimServer, playerId: int): int =
  ## Assigns one neutral planet to a joining player.
  var neutralIndices: seq[int] = @[]
  for i, planet in sim.planets:
    if planet.ownerId == 0:
      neutralIndices.add i
  let claimedIndex =
    if neutralIndices.len > 0:
      neutralIndices[sim.rng.rand(neutralIndices.high)]
    else:
      sim.rng.rand(sim.planets.high)
  sim.planets[claimedIndex].ownerId = playerId
  sim.planets[claimedIndex].ships = max(sim.planets[claimedIndex].ships, 10)
  sim.planets[claimedIndex].growthTicks = 0
  sim.markScoresChanged()
  claimedIndex

proc addPlayer*(sim: var SimServer, name: string): int =
  ## Adds a player and returns its index.
  inc sim.nextPlayerId
  let
    playerId = sim.nextPlayerId
    claimedPlanet = sim.claimPlanetForPlayer(playerId)
    planet = sim.planets[claimedPlanet]
    playerColor = sim.randomBrightPlayerColor()
  sim.players.add Player(
    id: playerId,
    name: name,
    sendPercent: clamp(sim.config.defaultSendPercent, 10, 100),
    color: playerColor.color,
    colorHue: playerColor.hue,
    selectedPlanet: claimedPlanet,
    originPlanet: claimedPlanet,
    cursorX: planet.x,
    cursorY: planet.y
  )
  sim.markScoresChanged()
  sim.players.high

proc removePlayerById*(sim: var SimServer, playerId: int) =
  ## Removes ownership and ships for one disconnected player id.
  for planet in sim.planets.mitems:
    if planet.ownerId == playerId:
      planet.ownerId = 0
  var remainingShips: seq[Ship] = @[]
  for ship in sim.ships:
    if ship.ownerId != playerId:
      remainingShips.add ship
  sim.ships = move(remainingShips)
  sim.markScoresChanged()

proc cleanChatMessage*(message: string): string =
  ## Returns a printable, bounded chat message.
  let trimmed = message.strip()
  for ch in trimmed:
    if result.len >= ChatMaxChars:
      return
    if ch >= ' ' and ch <= '~':
      result.add(ch)

proc addChatMessage*(sim: var SimServer, playerIndex: int, message: string) =
  ## Adds one cursor chat bubble from a connected player.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  let text = cleanChatMessage(message)
  if text.len == 0:
    return
  for i in countdown(sim.chatMessages.high, 0):
    if sim.chatMessages[i].playerId == sim.players[playerIndex].id:
      sim.chatMessages.delete(i)
  sim.chatMessages.add ChatMessage(
    playerId: sim.players[playerIndex].id,
    text: text,
    tick: sim.tickCount
  )

proc pruneChatMessages*(sim: var SimServer) =
  ## Removes expired cursor chat bubbles.
  for i in countdown(sim.chatMessages.high, 0):
    if sim.tickCount - sim.chatMessages[i].tick >= ChatBubbleTicks:
      sim.chatMessages.delete(i)

proc nearestPlanetIndex*(
  sim: SimServer,
  worldX,
  worldY: int
): int {.measure.} =
  ## Returns the planet nearest to a world position.
  if sim.planets.len == 0:
    return -1
  var
    bestIndex = 0
    bestDistance = high(int)
  for i, planet in sim.planets:
    let
      dx = planet.x - worldX
      dy = planet.y - worldY
      distance = dx * dx + dy * dy
    if distance < bestDistance:
      bestDistance = distance
      bestIndex = i
  bestIndex

proc applyCursorMomentumAxis(
  player: var Player,
  carry: var int,
  velocity: int,
  horizontal: bool
) =
  ## Applies subpixel cursor motion on one axis.
  carry += velocity
  while abs(carry) >= MotionScale:
    let step = if carry < 0: -1 else: 1
    if horizontal:
      let nextX = worldClampPixel(player.cursorX + step, WorldWidthPixels - 1)
      if nextX == player.cursorX:
        carry = 0
        break
      player.cursorX = nextX
    else:
      let nextY = worldClampPixel(player.cursorY + step, WorldHeightPixels - 1)
      if nextY == player.cursorY:
        carry = 0
        break
      player.cursorY = nextY
    carry -= step * MotionScale

proc updateCursorBoost(player: var Player, inputX, inputY: int) =
  ## Updates long-distance cursor acceleration state.
  if inputX == 0 and inputY == 0:
    player.cursorInputX = 0
    player.cursorInputY = 0
    player.cursorBoostTicks = 0
    return
  if inputX != player.cursorInputX or inputY != player.cursorInputY:
    player.cursorInputX = inputX
    player.cursorInputY = inputY
    player.cursorBoostTicks = 1
  else:
    inc player.cursorBoostTicks

proc cursorMaxSpeed(player: Player): int =
  ## Returns the current cursor speed cap after hold acceleration.
  let boostTicks = max(0, player.cursorBoostTicks - CursorBoostStartTicks)
  min(
    CursorBoostMaxSpeed,
    CursorMaxSpeed + boostTicks * CursorBoostSpeedPerTick
  )

proc shipDuration*(startX, startY, endX, endY: int): int =
  ## Returns the travel duration for one ship.
  let
    dx = abs(endX - startX)
    dy = abs(endY - startY)
    travel = max(dx, dy)
  max(
    1,
    (travel * TargetFps + ShipSpeedPixelsPerSecond - 1) div
      ShipSpeedPixelsPerSecond
  )

proc sendRepeatInterval(holdTicks: int): int =
  ## Returns the repeat interval for held send input.
  max(
    MinSendRepeatInterval,
    BaseSendRepeatInterval - holdTicks div SendAccelerationTicks
  )

proc randomShipLaneOffset(
  sim: var SimServer,
  originPlanet,
  targetPlanet: Planet
): tuple[x, y: int] =
  ## Returns a small lane offset so ship streams do not overlap perfectly.
  let laneRadius = min(
    ShipLaneOffsetMax,
    max(0, min(originPlanet.radius, targetPlanet.radius) - 2)
  )
  if laneRadius <= 0:
    return (0, 0)
  for _ in 0 ..< 16:
    let
      dx = sim.rng.rand(laneRadius * 2) - laneRadius
      dy = sim.rng.rand(laneRadius * 2) - laneRadius
    if (dx != 0 or dy != 0) and dx * dx + dy * dy <= laneRadius * laneRadius:
      return (dx, dy)
  (laneRadius, 0)

proc buildCosTable(): array[HeadingCount, int32] =
  ## Builds the fixed-point cosine table at compile time. Floats appear
  ## here and nowhere else, so the running simulation stays integral.
  for i in 0 ..< HeadingCount:
    let angle = float64(i) * 2.0 * 3.14159265358979 / float64(HeadingCount)
    result[i] = int32(round(cos(angle) * float64(TrigScale)))

const CosTable = buildCosTable()

proc cosHeading*(heading: uint8): int =
  ## Cosine of a heading, scaled by TrigScale.
  int(CosTable[int(heading)])

proc sinHeading*(heading: uint8): int =
  ## Sine of a heading, scaled by TrigScale. Screen y grows downward, so
  ## this is the cosine table shifted a quarter turn.
  int(CosTable[(int(heading) + 192) and (HeadingCount - 1)])

proc headingFromDelta*(dx, dy: int): uint8 =
  ## Nearest of the 256 headings pointing along a delta. Found by scanning
  ## the table with integer cross products, so no trigonometry is needed
  ## at runtime.
  if dx == 0 and dy == 0:
    return 0
  var
    best = 0
    bestDot = low(int)
  for candidate in 0 ..< HeadingCount:
    let dot = cosHeading(uint8(candidate)) * dx + sinHeading(uint8(candidate)) * dy
    if dot > bestDot:
      bestDot = dot
      best = candidate
  uint8(best)

proc currentShipPosition*(ship: Ship): tuple[x: int, y: int] =
  ## Returns the current world position for one ship.
  (ship.posX div SubpixelScale, ship.posY div SubpixelScale)

proc sendShip*(sim: var SimServer, playerIndex: int): bool {.measure.} =
  ## Sends one ship from the selected origin to the selected target.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return false
  let
    originIndex = sim.players[playerIndex].originPlanet
    targetIndex = sim.players[playerIndex].selectedPlanet
  if originIndex < 0 or originIndex >= sim.planets.len or
      targetIndex < 0 or targetIndex >= sim.planets.len:
    return false
  if originIndex == targetIndex:
    return false
  if sim.planets[originIndex].ownerId != sim.players[playerIndex].id:
    return false
  if sim.planets[originIndex].ships <= 1:
    return false
  let
    originPlanet = sim.planets[originIndex]
    targetPlanet = sim.planets[targetIndex]
    laneOffset = sim.randomShipLaneOffset(originPlanet, targetPlanet)
    startX = originPlanet.x + laneOffset.x
    startY = originPlanet.y + laneOffset.y
    endX = targetPlanet.x + laneOffset.x
    endY = targetPlanet.y + laneOffset.y
  dec sim.planets[originIndex].ships
  sim.ships.add Ship(
    ownerId: sim.players[playerIndex].id,
    color: sim.players[playerIndex].color,
    targetPlanet: targetPlanet.id,
    startX: startX,
    startY: startY,
    endX: endX,
    endY: endY,
    duration: shipDuration(startX, startY, endX, endY)
  )
  sim.markScoresChanged()
  true

proc planetIdAt*(sim: SimServer, worldX, worldY: int): int =
  ## Returns the planet under a world point, or -1 when the point is
  ## empty space. Unlike the old cursor model this does not snap to the
  ## nearest planet: clicking nothing selects nothing.
  result = -1
  var bestDistance = high(int)
  for planet in sim.planets:
    let
      dx = planet.x - worldX
      dy = planet.y - worldY
      distance = dx * dx + dy * dy
      reach = planet.radius + PlanetClickPad
    if distance <= reach * reach and distance < bestDistance:
      bestDistance = distance
      result = planet.id

proc ownsPlanetId(sim: SimServer, playerIndex, planetId: int): bool =
  ## Returns true when one player owns a planet by id.
  let index = sim.findPlanetIndexById(planetId)
  index >= 0 and sim.planets[index].ownerId == sim.players[playerIndex].id

proc pruneSelection(sim: var SimServer, playerIndex: int) =
  ## Drops selected planets that were lost or destroyed.
  var kept: seq[int] = @[]
  for planetId in sim.players[playerIndex].selectedPlanetIds:
    if sim.ownsPlanetId(playerIndex, planetId):
      kept.add(planetId)
  sim.players[playerIndex].selectedPlanetIds = kept

proc spreadOffset(
  slot,
  radius,
  towardX,
  towardY: int
): tuple[x, y: int] =
  ## Returns one launch point on a planet's edge. Slots fan out either
  ## side of the direction of travel, so a wave leaves facing its target
  ## instead of stacking on a single pixel.
  ##
  ## Integer only: the fan is built from a small fixed table rather than
  ## trigonometry, keeping the simulation deterministic.
  const
    FanNumerators = [0, 2, -2, 4, -4, 6, -6, 8, -8, 10, -10, 12]
    FanDenominator = 16
  let
    step = FanNumerators[slot mod FanNumerators.len]
    # Perpendicular to the travel direction, scaled down to stay on the
    # edge rather than swinging wide.
    perpX = -towardY
    perpY = towardX
    length = max(1, abs(towardX) + abs(towardY))
    alongX = (towardX * radius) div length
    alongY = (towardY * radius) div length
    sideX = (perpX * radius * step) div (length * FanDenominator)
    sideY = (perpY * radius * step) div (length * FanDenominator)
  (alongX + sideX, alongY + sideY)

proc sendFleet*(
  sim: var SimServer,
  playerIndex,
  targetPlanetId: int
): int {.measure.} =
  ## Sends a percentage of the ships on every selected planet toward one
  ## target, and returns how many ships launched. A planet always keeps
  ## one ship, so a send can never abandon a world.
  let targetIndex = sim.findPlanetIndexById(targetPlanetId)
  if targetIndex < 0:
    return 0
  let percent = clamp(sim.players[playerIndex].sendPercent, 10, 100)
  for planetId in sim.players[playerIndex].selectedPlanetIds:
    if planetId == targetPlanetId:
      continue
    let originIndex = sim.findPlanetIndexById(planetId)
    if originIndex < 0 or
        sim.planets[originIndex].ownerId != sim.players[playerIndex].id:
      continue
    let
      available = sim.planets[originIndex].ships - 1
      count = min((sim.planets[originIndex].ships * percent) div 100, available)
    if count <= 0:
      continue
    for launched in 0 ..< count:
      let
        originPlanet = sim.planets[originIndex]
        targetPlanet = sim.planets[targetIndex]
        ring = launched div ShipsPerRing
        slot = launched mod ShipsPerRing
        # Spread the ring around the edge, centred on the heading to the
        # target so the leading ships already face the right way.
        toTargetX = targetPlanet.x - originPlanet.x
        toTargetY = targetPlanet.y - originPlanet.y
        spread = spreadOffset(slot, originPlanet.radius + 2,
          toTargetX, toTargetY)
        startX = originPlanet.x + spread.x
        startY = originPlanet.y + spread.y
        endX = targetPlanet.x + spread.x div 2
        endY = targetPlanet.y + spread.y div 2
      dec sim.planets[originIndex].ships
      sim.ships.add Ship(
        ownerId: sim.players[playerIndex].id,
        color: sim.players[playerIndex].color,
        targetPlanet: targetPlanet.id,
        startX: startX,
        startY: startY,
        endX: endX,
        endY: endY,
        duration: shipDuration(startX, startY, endX, endY),
        launchDelay: ring * RingLaunchDelayTicks,
        posX: startX * SubpixelScale,
        posY: startY * SubpixelScale,
        heading: headingFromDelta(endX - startX, endY - startY)
      )
      inc result
  if result > 0:
    sim.markScoresChanged()

proc applyPlayerCommand(
  sim: var SimServer,
  playerIndex: int,
  command: PlayerCommand
) =
  ## Applies one click. What you click decides what happens: your own
  ## planet selects, anything else is a target and receives a wave from
  ## whatever is selected. One button does the whole game.
  let planetId = sim.planetIdAt(command.x, command.y)
  if command.kind == CommandSelectAll:
    var owned: seq[int] = @[]
    for planet in sim.planets:
      if planet.ownerId == sim.players[playerIndex].id:
        owned.add(planet.id)
    sim.players[playerIndex].selectedPlanetIds = owned
    return
  if planetId < 0 or command.kind == CommandNone:
    return
  if sim.ownsPlanetId(playerIndex, planetId):
    if command.kind == CommandShiftClick:
      if planetId notin sim.players[playerIndex].selectedPlanetIds:
        sim.players[playerIndex].selectedPlanetIds.add(planetId)
    else:
      sim.players[playerIndex].selectedPlanetIds = @[planetId]
    return
  # A target. The selection survives the send, so clicking a second
  # target immediately launches another wave from the same planets.
  discard sim.sendFleet(playerIndex, planetId)

proc resolveShipArrival(sim: var SimServer, ship: Ship) =
  ## Applies a ship arrival to its target planet.
  let targetIndex = sim.findPlanetIndexById(ship.targetPlanet)
  if targetIndex < 0 or targetIndex >= sim.planets.len:
    return
  if sim.planets[targetIndex].ownerId == ship.ownerId:
    inc sim.planets[targetIndex].ships
  else:
    dec sim.planets[targetIndex].ships
    if sim.planets[targetIndex].ships < 0:
      sim.planets[targetIndex].ownerId = ship.ownerId
      sim.planets[targetIndex].ships = -sim.planets[targetIndex].ships
      sim.planets[targetIndex].growthTicks = 0
  sim.markScoresChanged()

proc separateShips(sim: var SimServer) {.measure.} =
  ## Pushes overlapping ships of the same owner apart. Ships belonging to
  ## different players pass through each other untouched, so a wave is
  ## never blocked by an enemy stream.
  ##
  ## Candidates come from a uniform integer grid rebuilt each tick, which
  ## keeps the cost near linear without any floating point.
  if sim.ships.len < 2:
    return
  var buckets = newSeq[seq[int32]](CollisionGridSide * CollisionGridSide)
  for index, ship in sim.ships:
    if ship.launchDelay > 0:
      continue
    let
      cellX = clamp(
        (ship.posX div SubpixelScale) div CollisionCellPixels,
        0, CollisionGridSide - 1
      )
      cellY = clamp(
        (ship.posY div SubpixelScale) div CollisionCellPixels,
        0, CollisionGridSide - 1
      )
    buckets[cellY * CollisionGridSide + cellX].add(int32(index))
  let minGap = ShipRadiusSubpixels * 2
  for cellY in 0 ..< CollisionGridSide:
    for cellX in 0 ..< CollisionGridSide:
      for offsetY in -1 .. 1:
        for offsetX in -1 .. 1:
          let
            otherY = cellY + offsetY
            otherX = cellX + offsetX
          if otherX < 0 or otherY < 0 or
              otherX >= CollisionGridSide or otherY >= CollisionGridSide:
            continue
          for a in buckets[cellY * CollisionGridSide + cellX]:
            for b in buckets[otherY * CollisionGridSide + otherX]:
              if b <= a:
                continue
              let first = int(a)
              let second = int(b)
              if sim.ships[first].ownerId != sim.ships[second].ownerId:
                continue
              let
                dx = sim.ships[second].posX - sim.ships[first].posX
                dy = sim.ships[second].posY - sim.ships[first].posY
              if dx * dx + dy * dy >= minGap * minGap:
                continue
              # Coincident ships still need a stable direction to part in,
              # so fall back to a spread derived from the pair's indices.
              let away =
                if dx == 0 and dy == 0:
                  uint8((first * 37 + second * 17) and (HeadingCount - 1))
                else:
                  headingFromDelta(dx, dy)
              let
                pushX = (cosHeading(away) * ShipPushSubpixels) div TrigScale
                pushY = (sinHeading(away) * ShipPushSubpixels) div TrigScale
              sim.ships[second].posX += pushX
              sim.ships[second].posY += pushY
              sim.ships[first].posX -= pushX
              sim.ships[first].posY -= pushY

proc stepShips(sim: var SimServer) {.measure.} =
  ## Advances all ships, separates crowded friendly ships, and resolves
  ## arrivals.
  for ship in sim.ships.mitems:
    if ship.launchDelay > 0:
      dec ship.launchDelay
      continue
    inc ship.progress
    let targetIndex = sim.findPlanetIndexById(ship.targetPlanet)
    if targetIndex >= 0:
      # Re-aim every tick so a ship nudged aside still converges.
      ship.heading = headingFromDelta(
        sim.planets[targetIndex].x * SubpixelScale - ship.posX,
        sim.planets[targetIndex].y * SubpixelScale - ship.posY
      )
    ship.posX += (cosHeading(ship.heading) * ShipSpeedSubpixels) div TrigScale
    ship.posY += (sinHeading(ship.heading) * ShipSpeedSubpixels) div TrigScale
  sim.separateShips()
  var activeShips: seq[Ship] = @[]
  for ship in sim.ships:
    if ship.launchDelay > 0:
      activeShips.add ship
      continue
    let targetIndex = sim.findPlanetIndexById(ship.targetPlanet)
    if targetIndex < 0:
      continue
    let
      dx = sim.planets[targetIndex].x * SubpixelScale - ship.posX
      dy = sim.planets[targetIndex].y * SubpixelScale - ship.posY
      reach = sim.planets[targetIndex].radius * SubpixelScale
    # A long-lived ship is force-landed so a crowded target can never
    # leave one circling forever.
    if dx * dx + dy * dy <= reach * reach or
        ship.progress > ship.duration * 3 + TargetFps * 10:
      sim.resolveShipArrival(ship)
    else:
      activeShips.add ship
  sim.ships = move(activeShips)

proc stepGrowth(sim: var SimServer) {.measure.} =
  ## Grows ships on owned planets.
  var changed = false
  for planet in sim.planets.mitems:
    if planet.ownerId == 0:
      continue
    inc planet.growthTicks
    if planet.growthTicks >= planet.growthInterval:
      planet.growthTicks = 0
      if planet.ships < 9999:
        inc planet.ships
        changed = true
  if changed:
    sim.markScoresChanged()

proc stepScore(sim: var SimServer) {.measure.} =
  ## Awards score from owned planet count.
  inc sim.scoreTicks
  if sim.scoreTicks < ScoreIntervalTicks:
    return
  sim.scoreTicks = 0
  for player in sim.players.mitems:
    let ownedCount = sim.countOwnedPlanets(player.id)
    player.score += ownedCount * ownedCount
  sim.markScoresChanged()

proc addActiveOwner(owners: var seq[int], ownerId: int) =
  ## Adds one non-neutral owner id if it is not already present.
  if ownerId <= 0:
    return
  for existing in owners:
    if existing == ownerId:
      return
  owners.add(ownerId)

proc activeOwnerIds(sim: SimServer): seq[int] {.measure.} =
  ## Returns players that still have planets or ships in flight.
  for planet in sim.planets:
    result.addActiveOwner(planet.ownerId)
  for ship in sim.ships:
    result.addActiveOwner(ship.ownerId)

proc finishGame*(sim: var SimServer, winnerPlayerId: int) =
  ## Marks the current game finished with an optional winner.
  if sim.gameOver:
    return
  sim.gameOver = true
  sim.winnerPlayerId = winnerPlayerId
  sim.markScoresChanged()

proc checkRemainingWin*(sim: var SimServer) =
  ## Finishes when only one non-neutral player remains.
  let owners = sim.activeOwnerIds()
  sim.maxActiveOwnerCount = max(sim.maxActiveOwnerCount, owners.len)
  if sim.maxActiveOwnerCount > 1 and owners.len == 1:
    sim.finishGame(owners[0])

proc checkMaxTicks*(sim: var SimServer) =
  ## Finishes the game when the tick limit is reached.
  if sim.config.maxTicks > 0 and sim.tickCount >= sim.config.maxTicks:
    sim.finishGame(0)

proc ensureSelection*(sim: var SimServer, playerIndex: int) {.measure.} =
  ## Repairs one player's cursor and selected planet.
  if playerIndex < 0 or playerIndex >= sim.players.len or sim.planets.len == 0:
    return
  if sim.players[playerIndex].cursorX == 0 and
      sim.players[playerIndex].cursorY == 0:
    let seedIndex =
      if sim.players[playerIndex].selectedPlanet >= 0 and
          sim.players[playerIndex].selectedPlanet < sim.planets.len:
        sim.players[playerIndex].selectedPlanet
      else:
        0
    sim.players[playerIndex].cursorX = sim.planets[seedIndex].x
    sim.players[playerIndex].cursorY = sim.planets[seedIndex].y
  sim.players[playerIndex].selectedPlanet = sim.nearestPlanetIndex(
    sim.players[playerIndex].cursorX,
    sim.players[playerIndex].cursorY
  )
  if sim.players[playerIndex].originPlanet < 0 or
      sim.players[playerIndex].originPlanet >= sim.planets.len:
    sim.players[playerIndex].originPlanet =
      sim.players[playerIndex].selectedPlanet

proc applyInput*(
  sim: var SimServer,
  playerIndex: int,
  input: PlayerInput
) {.measure.} =
  ## Applies one player's input to cursor and ship commands.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.ensureSelection(playerIndex)
  if sim.players[playerIndex].sendCooldown > 0:
    dec sim.players[playerIndex].sendCooldown
  # Mouse play: place the cursor, take the chosen send size, then run the
  # clicks that arrived this tick.
  if input.hasCursor:
    sim.players[playerIndex].cursorX =
      worldClampPixel(input.cursorX, WorldWidthPixels - 1)
    sim.players[playerIndex].cursorY =
      worldClampPixel(input.cursorY, WorldHeightPixels - 1)
  if input.sendPercent > 0:
    sim.players[playerIndex].sendPercent = clamp(input.sendPercent, 10, 100)
  if input.commandCount > 0:
    sim.pruneSelection(playerIndex)
    for i in 0 ..< min(input.commandCount, input.commands.len):
      sim.applyPlayerCommand(playerIndex, input.commands[i])
  var
    inputX = 0
    inputY = 0
  if input.left and not input.right:
    inputX = -1
  elif input.right and not input.left:
    inputX = 1
  elif input.up and not input.down:
    inputY = -1
  elif input.down and not input.up:
    inputY = 1
  sim.players[playerIndex].updateCursorBoost(inputX, inputY)
  let cursorSpeed = sim.players[playerIndex].cursorMaxSpeed()
  if inputX != 0:
    sim.players[playerIndex].cursorVelX = clamp(
      sim.players[playerIndex].cursorVelX + inputX * CursorAccel,
      -cursorSpeed,
      cursorSpeed
    )
  else:
    sim.players[playerIndex].cursorVelX =
      (sim.players[playerIndex].cursorVelX * CursorFrictionNum) div
      CursorFrictionDen
    if abs(sim.players[playerIndex].cursorVelX) < CursorStopThreshold:
      sim.players[playerIndex].cursorVelX = 0
  if inputY != 0:
    sim.players[playerIndex].cursorVelY = clamp(
      sim.players[playerIndex].cursorVelY + inputY * CursorAccel,
      -cursorSpeed,
      cursorSpeed
    )
  else:
    sim.players[playerIndex].cursorVelY =
      (sim.players[playerIndex].cursorVelY * CursorFrictionNum) div
      CursorFrictionDen
    if abs(sim.players[playerIndex].cursorVelY) < CursorStopThreshold:
      sim.players[playerIndex].cursorVelY = 0
  applyCursorMomentumAxis(
    sim.players[playerIndex],
    sim.players[playerIndex].cursorCarryX,
    sim.players[playerIndex].cursorVelX,
    true
  )
  applyCursorMomentumAxis(
    sim.players[playerIndex],
    sim.players[playerIndex].cursorCarryY,
    sim.players[playerIndex].cursorVelY,
    false
  )
  sim.players[playerIndex].selectedPlanet = sim.nearestPlanetIndex(
    sim.players[playerIndex].cursorX,
    sim.players[playerIndex].cursorY
  )
  let selectedIndex = sim.players[playerIndex].selectedPlanet
  if input.attackPressed and selectedIndex >= 0 and
      selectedIndex < sim.planets.len:
    if sim.planets[selectedIndex].ownerId == sim.players[playerIndex].id:
      sim.players[playerIndex].originPlanet = selectedIndex
  if input.sendHeld:
    inc sim.players[playerIndex].sendHoldTicks
    if sim.players[playerIndex].sendCooldown == 0:
      if sim.sendShip(playerIndex):
        sim.players[playerIndex].sendCooldown =
          sendRepeatInterval(sim.players[playerIndex].sendHoldTicks)
  else:
    sim.players[playerIndex].sendHoldTicks = 0

proc step*(sim: var SimServer, inputs: openArray[PlayerInput]) {.measure.} =
  ## Advances one deterministic game tick.
  if sim.gameOver:
    return
  if sim.waitingForPlayers:
    # The lobby holds the game clock at zero: planets do not grow and
    # inputs are ignored, so late joiners start on equal footing. The
    # first simulated tick runs on the frame after the lobby ends.
    inc sim.waitTicks
    if sim.players.len >= sim.expectedPlayers or
        sim.waitTicks >= WaitForPlayersTimeoutTicks:
      sim.waitingForPlayers = false
    return
  for playerIndex in 0 ..< sim.players.len:
    let input =
      if playerIndex < inputs.len:
        inputs[playerIndex]
      else:
        PlayerInput()
    sim.applyInput(playerIndex, input)
  sim.stepGrowth()
  sim.stepShips()
  sim.stepScore()
  inc sim.tickCount
  sim.pruneChatMessages()
  sim.checkRemainingWin()
  sim.checkMaxTicks()

proc initSimServer*(
  seed: int,
  config = defaultSimConfig(),
  expectedPlayers = 0
): SimServer {.measure.} =
  ## Creates a fresh simulation server. A positive expectedPlayers count
  ## holds the game in a waiting lobby until that many players join.
  config.checkSimConfig()
  result.config = config
  result.expectedPlayers = expectedPlayers
  result.waitingForPlayers = expectedPlayers > 0
  result.winnerPlayerId = 0
  result.rng = initRand(seed)
  result.textFont = loadTiny5Font()
  result.chatMessages = @[]
  result.generatePlanets()
  result.generateStars()
  result.markScoresChanged()

proc removePlayerAt*(sim: var SimServer, playerIndex: int) =
  ## Removes one player from the simulation, compacting indices.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  sim.removePlayerById(sim.players[playerIndex].id)
  sim.players.delete(playerIndex)

proc mixHash(hash: var uint64, value: uint64) =
  ## Mixes one value into a running FNV-1a style hash.
  hash = (hash xor value) * 1099511628211'u64

proc mixHashInt(hash: var uint64, value: int) =
  ## Mixes one integer into a running hash.
  hash.mixHash(cast[uint64](int64(value)))

proc gameHash*(sim: SimServer): uint64 =
  ## Returns a deterministic hash of gameplay state.
  result = 14695981039346656037'u64
  result.mixHashInt(sim.tickCount)
  result.mixHashInt(sim.scoreTicks)
  result.mixHashInt(ord(sim.gameOver))
  result.mixHashInt(sim.winnerPlayerId)
  result.mixHashInt(sim.maxActiveOwnerCount)
  result.mixHashInt(sim.nextPlayerId)
  result.mixHashInt(sim.players.len)
  for player in sim.players:
    result.mixHashInt(player.id)
    result.mixHashInt(player.score)
    result.mixHashInt(player.selectedPlanet)
    result.mixHashInt(player.originPlanet)
    result.mixHashInt(player.sendCooldown)
    result.mixHashInt(player.sendHoldTicks)
    result.mixHashInt(player.cursorX)
    result.mixHashInt(player.cursorY)
    result.mixHashInt(player.cursorVelX)
    result.mixHashInt(player.cursorVelY)
    result.mixHashInt(player.cursorBoostTicks)
  result.mixHashInt(sim.planets.len)
  for planet in sim.planets:
    result.mixHashInt(planet.ownerId)
    result.mixHashInt(planet.ships)
    result.mixHashInt(planet.growthTicks)
  result.mixHashInt(sim.ships.len)
  for ship in sim.ships:
    result.mixHashInt(ship.ownerId)
    result.mixHashInt(ship.targetPlanet)
    result.mixHashInt(ship.progress)
    result.mixHashInt(ship.posX)
    result.mixHashInt(ship.posY)
    result.mixHashInt(int(ship.heading))
    result.mixHashInt(ship.launchDelay)

proc playerScoresJson*(sim: SimServer): string {.measure.} =
  ## Builds the current per-player score JSON.
  var
    names = newJArray()
    scores = newJArray()
    wins = newJArray()
    planets = newJArray()
    ships = newJArray()
    results = newJObject()
  for player in sim.players:
    names.add(%player.name)
    scores.add(%player.score)
    wins.add(%(sim.gameOver and player.id == sim.winnerPlayerId))
    planets.add(%sim.countOwnedPlanets(player.id))
    ships.add(%sim.totalPlayerShips(player.id))
  results["names"] = names
  results["scores"] = scores
  results["win"] = wins
  results["planets"] = planets
  results["ships"] = ships
  $results
