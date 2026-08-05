import
  std/[options, os, parseopt, random, strutils, times],
  supersnappy, whisky,
  bitworld/[spriteprotocol, sprites],
  planet_wars/sim

const
  SkurgeDefaultPort = DefaultPort
  MaxDrainMessages = 256
  NeutralPlanetSpriteBase = 100
  PlayerPlanetSpriteBase = 1000
  PlayerShipSpriteBase = 2000
  PlayerCursorSpriteBase = 5000
  PlanetTextSpriteBase = 10000
  PlanetTextDigitSpriteBase = 10000
  PlanetTextMaxChars = 8
  PlanetObjectBase = 2000
  PlanetSelectedObjectBase = 2100
  PlanetOriginObjectBase = 2200
  PlanetTextObjectBase = 2300
  CursorObjectBase = 12000
  PlanetSpriteStride = 8
  CursorSpriteSize = 5
  CursorDeadband = 3
  OriginSelectInterval = 8
  RetargetTicks = TargetFps * 3
  SweepArrivalRadius = 18
  OriginReserveShips = 1
  # A burst pins the cursor, which is the scarcest resource, so cap how
  # long one capture may hold it. Eight seconds measurably lost ground
  # to three; the bounded garrison keeps bursts short enough anyway.
  SendBurstMaxHoldTicks = TargetFps * 3
  SendBurstPaddingTicks = 4
  EnemyTakeMargin = 5
  NeutralTakeMargin = 1
  UnknownShipGuess = 12
  UnknownGrowthTicks = 150
  # One ship of capture cost is worth this many pixels of travel.
  ShipCostWeight = 25
  SmallPlanetRadius = 9
  # A large planet grows ships about twice as fast as a small one, but
  # planet count compounds faster than growth does, so the bonus stays
  # bounded: it is worth a short detour, never a change of plan.
  MissionTimeoutTicks = TargetFps * 8
  # Consecutive bursts from one origin that capture nothing before the
  # origin is written off. Outcome-based, so unlike ship accounting it
  # cannot drift when an enemy stream throttles the planet unseen.
  MaxOriginFailStreak = 2
  OriginAvoidTicks = TargetFps * 20
  # Finish the kill instead of abandoning a burst one ship short, but
  # bound it so a regrowing enemy cannot extend the mission forever.
  FinishKillShips = 3
  FinishKillExtendTicks = TargetFps div 2
  MaxMissionTicks = TargetFps * 25
  # A burst this small cannot flip anything, and each one costs a
  # cursor trip, so accumulate instead of dribbling single ships.
  MinPressureShips = 3
  # Captures one claimed origin should fund before relocating.
  SpreeCaptures = 1
  # How long to stand on a planet whose capture is still in flight.
  ArrivalWaitTicks = TargetFps * 3
  # Send only what the capture needs. Garrisoning ships forward drains
  # the origin below the next capture's cost, which breaks the chain and
  # forces a 141px trip to find ships; measured origins arrive with ~20
  # ships against a ~9 cost, so a lean burst buys a second capture free.
  MaxGarrisonShips = 0
  # Rivals holding at most this many planets are worth hunting down.
  EliminationThreshold = 5
  # Per-planet edge over a weaker rival, steering attacks toward
  # whoever is already losing so rivals fall one at a time.
  # Neutrals never regrow, so ships spent on them are banked rather
  # than burned. Worth a real discount, but not an absolute veto:
  # a neighbouring enemy beats a neutral across the whole map.
  # Target preferences, on the same scale as a wave's cost so they bias
  # the ranking without overriding it. The d-pad bot's equivalents were
  # thousands against a cost term of tens, which made ship cost
  # irrelevant; they were tuned when a capture cost a cursor trip and
  # captures were rare, and that no longer prices anything real.
  # Sprite radii as the bot sees them, one per planet size. The old
  # SmallPlanetRadius of 9 was the *gameplay* radius, so every planet
  # cleared it and the large-planet bonus was silently a no-op.
  MediumSpriteRadius = 15
  LargeSpriteRadius = 18
  ## Opening plan: pool everything, take cheap neighbours until the
  ## economy is wide enough to fund the large planets.
  OpeningPlanetTarget = 6
  OpeningMaxNeutralShips = 10
  ## Every wave is a full commitment; a planet always keeps one ship.
  FleetPercent = 100
  NeutralPreference = 200
  LargePlanetPreference = 120
  EliminationPreference = 300
  WeakRivalPreference = 60
  ## Planet Wars input tags, matching src/planet_wars/global.nim.
  PlanetWarsClick = 0xA0'u8
  PlanetWarsPercent = 0xA1'u8
  ClickPlain = 0'u8
  ClickSelectAll = 2'u8
  MinSendPercent = 10
  MaxSendPercent = 100
  SendPercentStep = 10
  # A send decrements the origin server-side at once and the new count
  # arrives on the next packet, so one tick is enough to avoid spending
  # the same ships twice. Anything longer just idles planets that could
  # already be launching.
  WaveCooldownTicks = 1
  # Ships already flying at a target still count against its defence, so
  # they are remembered until they land. Without this the planner keeps
  # re-buying a planet it has already paid for, which serializes the
  # whole expansion behind one capture at a time.
  CommitmentSlackTicks = TargetFps
  SweepPoints = [
    (x: 18, y: 18),
    (x: WorldWidthPixels - 18, y: 18),
    (x: WorldWidthPixels - 18, y: WorldHeightPixels - 18),
    (x: 18, y: WorldHeightPixels - 18),
    (x: WorldWidthPixels div 2, y: WorldHeightPixels div 2)
  ]

type
  SpriteKind = enum
    SpriteUnknown
    SpriteMap
    SpriteNeutralPlanet
    SpritePlayerPlanet
    SpriteRing
    SpriteShip
    SpriteCursor
    SpriteText

  BotPhase = enum
    PhaseOpening    ## Pool everything at the nearest cheap neutrals.
    PhaseBigPlanets ## Pool everything at the large planets.
    PhaseSnake      ## Roll one stack over the nearest neutral, forever.

  Wave = object
    sourceId: int
    targetId: int
    percent: int

  BotCommand = object
    kind: uint8
    x: int
    y: int
    percent: int

  SpriteInfo = object
    defined: bool
    width: int
    height: int
    label: string
    kind: SpriteKind
    ownerId: int
    pixels: seq[uint8]
    color: RgbaColor

  ObjectState = object
    present: bool
    x: int
    y: int
    z: int
    layer: int
    spriteId: int

  PlanetSight = object
    found: bool
    id: int
    ownerId: int
    ships: int
    x: int
    y: int
    radius: int
    seenTick: int
    selected: bool
    origin: bool

  Bot = object
    sprites: seq[SpriteInfo]
    objects: seq[ObjectState]
    knownPlanets: seq[PlanetSight]
    shipDebits: seq[int]
    steerAxisHorizontal: bool
    rng: Rand
    cameraX: int
    cameraY: int
    frameTick: int
    ownPlayerId: int
    ownColor: RgbaColor
    colorKnown: bool
    colorAnnounced: bool
    selectedPlanetId: int
    originPlanetId: int
    lastSelectedPlanetId: int
    selectionStuckTicks: int
    phase: BotPhase
    waveCooldownUntil: int
    committedShips: seq[int]
    commitmentExpiry: seq[int]
    lastWave: Wave
    sweptAtTick: int
    intent: string

proc readU16(blob: string, offset: int): int =
  ## Reads one little endian unsigned 16 bit value.
  int(uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8))

proc readI16(blob: string, offset: int): int =
  ## Reads one little endian signed 16 bit value.
  let value = uint16(blob[offset].uint8) or
    (uint16(blob[offset + 1].uint8) shl 8)
  int(cast[int16](value))

proc readU32(blob: string, offset: int): int =
  ## Reads one little endian unsigned 32 bit value.
  int(uint32(blob[offset].uint8) or
    (uint32(blob[offset + 1].uint8) shl 8) or
    (uint32(blob[offset + 2].uint8) shl 16) or
    (uint32(blob[offset + 3].uint8) shl 24))

proc ensureSprite(bot: var Bot, spriteId: int) =
  ## Grows the sprite table so it can hold one sprite id.
  if spriteId >= bot.sprites.len:
    bot.sprites.setLen(spriteId + 1)

proc ensureObject(bot: var Bot, objectId: int) =
  ## Grows the object table so it can hold one object id.
  if objectId >= bot.objects.len:
    bot.objects.setLen(objectId + 1)

proc spriteInfo(bot: Bot, spriteId: int): SpriteInfo =
  ## Returns sprite metadata or an empty sprite.
  if spriteId >= 0 and spriteId < bot.sprites.len:
    return bot.sprites[spriteId]
  SpriteInfo()

proc classifySprite(
  spriteId: int,
  label: string
): tuple[kind: SpriteKind, ownerId: int] =
  ## Classifies one Planet Wars sprite id.
  let lower = label.toLowerAscii()
  if spriteId == MapSpriteId:
    return (SpriteMap, 0)
  if spriteId >= NeutralPlanetSpriteBase and
      spriteId < NeutralPlanetSpriteBase + PlanetSpriteStride:
    return (SpriteNeutralPlanet, 0)
  if spriteId >= PlayerPlanetSpriteBase and
      spriteId < PlayerShipSpriteBase:
    return (
      SpritePlayerPlanet,
      (spriteId - PlayerPlanetSpriteBase) div PlanetSpriteStride
    )
  if spriteId >= PlayerCursorSpriteBase and
      spriteId < PlanetTextSpriteBase:
    return (SpriteCursor, spriteId - PlayerCursorSpriteBase)
  if lower.contains("selected") or lower.contains("origin"):
    return (SpriteRing, 0)
  if lower.contains("ship") and not lower.startsWith("ships "):
    return (SpriteShip, 0)
  if label.len > 0:
    return (SpriteText, 0)
  (SpriteUnknown, 0)

proc dominantColor(
  pixels: openArray[uint8],
  width,
  height: int
): RgbaColor =
  ## Returns the average visible color in one RGBA sprite.
  if width <= 0 or height <= 0 or pixels.len != width * height * 4:
    return RgbaColor()
  var
    r = 0
    g = 0
    b = 0
    a = 0
    count = 0
  for y in 0 ..< height:
    for x in 0 ..< width:
      let offset = (y * width + x) * 4
      if pixels[offset + 3] < 128'u8:
        continue
      let bright =
        pixels[offset] > 235'u8 and
        pixels[offset + 1] > 235'u8 and
        pixels[offset + 2] > 235'u8
      if bright:
        continue
      r += int(pixels[offset])
      g += int(pixels[offset + 1])
      b += int(pixels[offset + 2])
      a += int(pixels[offset + 3])
      inc count
  if count == 0:
    return RgbaColor()
  RgbaColor(
    r: uint8(r div count),
    g: uint8(g div count),
    b: uint8(b div count),
    a: uint8(a div count)
  )

proc colorHex(color: RgbaColor): string =
  ## Returns one color as a readable RGB hex string.
  const Hex = "0123456789abcdef"
  result = "#"
  for value in [color.r, color.g, color.b]:
    let byte = int(value)
    result.add(Hex[(byte shr 4) and 0x0f])
    result.add(Hex[byte and 0x0f])

proc applySpritePacket(bot: var Bot, packet: string): bool =
  ## Applies one or more server sprite protocol messages.
  var offset = 0
  while offset < packet.len:
    let messageType = packet[offset].uint8
    inc offset
    case messageType
    of 0x01:
      if offset + 10 > packet.len:
        return false
      let
        spriteId = packet.readU16(offset)
        width = packet.readU16(offset + 2)
        height = packet.readU16(offset + 4)
        compressedLen = packet.readU32(offset + 6)
      offset += 10
      if compressedLen < 0 or offset + compressedLen + 2 > packet.len:
        return false
      let compressed =
        if compressedLen > 0:
          packet.substr(offset, offset + compressedLen - 1)
        else:
          ""
      offset += compressedLen
      let labelLen = packet.readU16(offset)
      offset += 2
      if offset + labelLen > packet.len:
        return false
      let label =
        if labelLen > 0:
          packet.substr(offset, offset + labelLen - 1)
        else:
          ""
      offset += labelLen
      let rawPixels = supersnappy.uncompress(compressed)
      var pixels = newSeq[uint8](rawPixels.len)
      for i, ch in rawPixels:
        pixels[i] = ch.uint8
      if pixels.len != width * height * 4:
        pixels.setLen(0)
      let classified = classifySprite(spriteId, label)
      bot.ensureSprite(spriteId)
      bot.sprites[spriteId] = SpriteInfo(
        defined: true,
        width: width,
        height: height,
        label: label,
        kind: classified.kind,
        ownerId: classified.ownerId,
        pixels: pixels,
        color: dominantColor(pixels, width, height)
      )
    of 0x02:
      if offset + 11 > packet.len:
        return false
      let
        objectId = packet.readU16(offset)
        x = packet.readI16(offset + 2)
        y = packet.readI16(offset + 4)
        z = packet.readI16(offset + 6)
        layer = int(packet[offset + 8].uint8)
        spriteId = packet.readU16(offset + 9)
      offset += 11
      bot.ensureObject(objectId)
      bot.objects[objectId] = ObjectState(
        present: true,
        x: x,
        y: y,
        z: z,
        layer: layer,
        spriteId: spriteId
      )
    of 0x03:
      if offset + 2 > packet.len:
        return false
      let objectId = packet.readU16(offset)
      offset += 2
      if objectId >= 0 and objectId < bot.objects.len:
        bot.objects[objectId].present = false
    of 0x04:
      for item in bot.objects.mitems:
        item.present = false
      bot.knownPlanets.setLen(0)
      bot.frameTick = 0
      bot.ownPlayerId = -1
      bot.colorKnown = false
      bot.colorAnnounced = false
      bot.selectedPlanetId = -1
      bot.originPlanetId = -1
      bot.waveCooldownUntil = 0
      bot.lastWave = Wave(sourceId: -1, targetId: -1, percent: 0)
    of 0x05:
      if offset + 5 > packet.len:
        return false
      offset += 5
    of 0x06:
      if offset + 3 > packet.len:
        return false
      offset += 3
    else:
      return false
  true

proc updateCamera(bot: var Bot) =
  ## Updates the visible map camera from the map object.
  if MapObjectId < bot.objects.len and bot.objects[MapObjectId].present:
    bot.cameraX = -bot.objects[MapObjectId].x
    bot.cameraY = -bot.objects[MapObjectId].y

proc objectPresent(bot: Bot, objectId: int): bool =
  ## Returns true when one object exists in the current sprite scene.
  objectId >= 0 and objectId < bot.objects.len and bot.objects[objectId].present

proc planetShips(bot: Bot, planetId: int): int =
  ## Reads a planet's ship count from its per-digit text objects.
  var text = ""
  for digitIndex in 0 ..< PlanetTextMaxChars:
    let objectId = PlanetTextObjectBase +
      planetId * PlanetTextMaxChars + digitIndex
    if not bot.objectPresent(objectId):
      continue
    let digit = bot.objects[objectId].spriteId - PlanetTextDigitSpriteBase
    if digit < 0 or digit > 9:
      continue
    text.add(char(ord('0') + digit))
  if text.len == 0:
    return -1
  parseInt(text)

proc planetSight(bot: Bot, planetId: int): PlanetSight =
  ## Reads one visible planet from protocol objects.
  let objectId = PlanetObjectBase + planetId
  if not bot.objectPresent(objectId):
    return PlanetSight()
  let
    objectState = bot.objects[objectId]
    sprite = bot.spriteInfo(objectState.spriteId)
  if not sprite.defined or
      sprite.kind notin {SpriteNeutralPlanet, SpritePlayerPlanet}:
    return PlanetSight()
  PlanetSight(
    found: true,
    id: planetId,
    ownerId: sprite.ownerId,
    ships: bot.planetShips(planetId),
    x: bot.cameraX + objectState.x + sprite.width div 2,
    y: bot.cameraY + objectState.y + sprite.height div 2,
    radius: sprite.width div 2,
    seenTick: bot.frameTick,
    selected: bot.objectPresent(PlanetSelectedObjectBase + planetId),
    origin: bot.objectPresent(PlanetOriginObjectBase + planetId)
  )

proc visiblePlanets(bot: Bot): seq[PlanetSight] =
  ## Returns all currently visible planets.
  for planetId in 1 .. MaxPlanetCount:
    let planet = bot.planetSight(planetId)
    if planet.found:
      result.add(planet)

proc rememberPlanets(bot: var Bot, planets: openArray[PlanetSight]) =
  ## Updates remembered planet sightings from the current viewport.
  if bot.knownPlanets.len <= MaxPlanetCount:
    bot.knownPlanets.setLen(MaxPlanetCount + 1)
  if bot.shipDebits.len <= MaxPlanetCount:
    bot.shipDebits.setLen(MaxPlanetCount + 1)
  for planet in planets:
    if planet.id >= 0 and planet.id < bot.knownPlanets.len:
      bot.knownPlanets[planet.id] = planet
      if planet.ships >= 0:
        bot.shipDebits[planet.id] = 0

proc knownPlanetSights(bot: Bot): seq[PlanetSight] =
  ## Returns all remembered planet sightings.
  for planet in bot.knownPlanets:
    if planet.found:
      result.add(planet)

proc updateIdentity(bot: var Bot, planets: openArray[PlanetSight]) =
  ## Recognizes Skurge's player id and color from its own selection.
  ##
  ## The whole board is visible now, so no planet is identifiable by
  ## position. Selection rings only ever appear on planets we own, so one
  ## select-all click names every planet that is ours.
  for planet in planets:
    if not planet.selected or planet.ownerId <= 0:
      continue
    if bot.ownPlayerId != planet.ownerId:
      bot.ownPlayerId = planet.ownerId
      bot.colorAnnounced = false
    let sprite = bot.spriteInfo(
      bot.objects[PlanetObjectBase + planet.id].spriteId
    )
    bot.ownColor = sprite.color
    bot.colorKnown = true
    return

proc selectedPlanetId(planets: openArray[PlanetSight]): int =
  ## Returns the currently selected visible planet id.
  for planet in planets:
    if planet.selected:
      return planet.id
  -1

proc originPlanetId(planets: openArray[PlanetSight]): int =
  ## Returns the currently visible origin planet id.
  for planet in planets:
    if planet.origin:
      return planet.id
  -1

proc findPlanet(
  planets: openArray[PlanetSight],
  planetId: int
): PlanetSight =
  ## Finds one visible planet by id.
  for planet in planets:
    if planet.id == planetId:
      return planet
  PlanetSight()

proc distanceSquared(ax, ay, bx, by: int): int =
  ## Returns squared distance between two points.
  let
    dx = ax - bx
    dy = ay - by
  dx * dx + dy * dy

proc intSqrt(value: int): int =
  ## Returns the integer square root of a non-negative value.
  if value <= 0:
    return 0
  var guess = value
  var next = (guess + 1) div 2
  while next < guess:
    guess = next
    next = (guess + value div guess) div 2
  guess

proc distance(ax, ay, bx, by: int): int =
  ## Returns the straight-line distance between two points.
  intSqrt(distanceSquared(ax, ay, bx, by))

proc cursorDistance(ax, ay, bx, by: int): int =
  ## Returns how far the cursor must actually travel. The game accepts
  ## one axis at a time, so movement is L-shaped and a diagonal hop
  ## costs the sum of both legs, not the straight line.
  abs(ax - bx) + abs(ay - by)

proc growthIntervalTicks(radius: int): int =
  ## Estimates a planet's ship growth interval from its visible radius.
  if radius <= 9:
    120
  elif radius <= 11:
    85
  else:
    60

proc shipDebit(bot: Bot, planetId: int): int =
  ## Returns unreconciled ships already spent from one planet.
  if planetId >= 0 and planetId < bot.shipDebits.len:
    return bot.shipDebits[planetId]
  0

proc estimatedShips(bot: Bot, planet: PlanetSight): int =
  ## Estimates a planet's current ship count from its last sighting.
  if planet.ships < 0:
    # Never read this planet's count. A fixed guess is badly wrong late,
    # when stockpiles are huge, and under-sending wastes a whole burst,
    # so grow the guess with the clock for planets somebody owns.
    if planet.ownerId == 0:
      return UnknownShipGuess
    return UnknownShipGuess + bot.frameTick div UnknownGrowthTicks
  if planet.ownerId == 0:
    return max(0, planet.ships - bot.shipDebit(planet.id))
  let elapsed = max(0, bot.frameTick - planet.seenTick)
  max(
    0,
    planet.ships + elapsed div growthIntervalTicks(planet.radius) -
      bot.shipDebit(planet.id)
  )

proc flightTicks(origin, target: PlanetSight): int =
  ## Returns how long ships take to fly between two planets.
  let travel = max(
    abs(target.x - origin.x),
    abs(target.y - origin.y)
  )
  (travel * TargetFps + ShipSpeedPixelsPerSecond - 1) div
    ShipSpeedPixelsPerSecond

proc captureCost(bot: Bot, target: PlanetSight): int =
  ## Estimates the ships required to capture one target planet.
  if target.ownerId == 0:
    bot.estimatedShips(target) + NeutralTakeMargin
  else:
    bot.estimatedShips(target) + EnemyTakeMargin

proc captureCostFrom(bot: Bot, origin, target: PlanetSight): int =
  ## Capture cost including the ships an enemy grows while ours fly in.
  ## Under-sending by that margin wastes the entire burst, because an
  ## enemy planet keeps every ship it survives with.
  result = bot.captureCost(target)
  if target.ownerId > 0:
    result += flightTicks(origin, target) div
      growthIntervalTicks(target.radius)

proc availableShips(bot: Bot, planet: PlanetSight): int =
  ## Returns the ships one owned planet can spend without losing itself.
  max(0, bot.estimatedShips(planet) - OriginReserveShips)

proc ownerPlanetCount(
  planets: openArray[PlanetSight],
  ownerId: int
): int =
  ## Returns how many planets one player holds.
  for planet in planets:
    if planet.found and planet.ownerId == ownerId:
      inc result

proc committedAgainst(bot: Bot, planetId: int): int =
  ## Returns ships already flying at one target and still expected.
  if planetId < 0 or planetId >= bot.committedShips.len:
    return 0
  if bot.frameTick >= bot.commitmentExpiry[planetId]:
    return 0
  bot.committedShips[planetId]

proc commit(bot: var Bot, target: PlanetSight, source: PlanetSight,
    ships, flight: int) =
  ## Records a wave so its ships are not bought twice.
  if target.id < 0 or target.id >= bot.committedShips.len:
    return
  if bot.frameTick >= bot.commitmentExpiry[target.id]:
    bot.committedShips[target.id] = 0
  bot.committedShips[target.id] += ships
  bot.commitmentExpiry[target.id] =
    bot.frameTick + flight + CommitmentSlackTicks

proc launchCount(ships, percent: int): int =
  ## Returns how many ships one send actually launches.
  min((ships * percent) div 100, max(0, ships - 1))

proc sendPercentFor(ships, needed: int): int =
  ## Returns the smallest send size that launches enough ships to take a
  ## target, or zero when this planet cannot fund the capture at all.
  ##
  ## A planet always keeps one ship, so even a full send is capped, and
  ## sending less than the cost wastes the whole wave: the target keeps
  ## every ship it survives with.
  if ships <= 1 or needed <= 0:
    return 0
  var percent = MinSendPercent
  while percent <= MaxSendPercent:
    if min((ships * percent) div 100, ships - 1) >= needed:
      return percent
    percent += SendPercentStep
  0

proc waveCost(
  bot: Bot,
  planets: openArray[PlanetSight],
  source, target: PlanetSight,
  needed: int
): int =
  ## Ranks one source-target pair, lower being better.
  ##
  ## Score is planet count squared, so two cheap captures beat one
  ## expensive capture and cost leads the ranking. The bonuses below are
  ## the weights the d-pad bot was tuned to; they carry over because they
  ## price planets, not cursor travel.
  result = needed * ShipCostWeight +
    distance(source.x, source.y, target.x, target.y)
  if target.radius > SmallPlanetRadius:
    result -= LargePlanetPreference
  if target.ownerId == 0:
    # Neutrals never regrow, so ships spent on them are banked.
    result -= NeutralPreference
  else:
    let held = planets.ownerPlanetCount(target.ownerId)
    if held <= EliminationThreshold:
      result -= EliminationPreference
    result -= (EliminationThreshold - min(held, EliminationThreshold)) *
      WeakRivalPreference

proc planWave(bot: Bot, planets: openArray[PlanetSight]): Wave =
  ## Picks the best capture available this tick.
  ##
  ## Every planet is visible and a wave is two clicks, so there is no
  ## cursor to steer and no fog to remember: this is a plain allocation
  ## of owned fleets to the targets they can actually take.
  result = Wave(sourceId: -1, targetId: -1, percent: 0)
  var bestCost = high(int)
  for target in planets:
    if not target.found or target.ownerId == bot.ownPlayerId:
      continue
    for source in planets:
      if not source.found or source.ownerId != bot.ownPlayerId:
        continue
      if source.id == target.id:
        continue
      let needed =
        bot.captureCostFrom(source, target) - bot.committedAgainst(target.id)
      if needed <= 0:
        # Already paid for; spend these ships somewhere that needs them.
        continue
      let percent = sendPercentFor(bot.estimatedShips(source), needed)
      if percent == 0:
        continue
      let cost = bot.waveCost(planets, source, target, needed)
      if cost < bestCost:
        bestCost = cost
        result = Wave(
          sourceId: source.id,
          targetId: target.id,
          percent: percent
        )

proc massLaunchTotal(
  bot: Bot,
  planets: openArray[PlanetSight],
  targetId, percent: int
): int =
  ## Returns how many ships every owned planet launches together.
  for source in planets:
    if source.found and source.ownerId == bot.ownPlayerId and
        source.id != targetId:
      result += launchCount(bot.estimatedShips(source), percent)

proc planMassWave(bot: Bot, planets: openArray[PlanetSight]): Wave =
  ## Picks a target the whole empire can take together.
  ##
  ## Selecting every planet at once is what the select-all click is for:
  ## when no single planet can fund a capture the bot would otherwise sit
  ## on its ships, and pooling them turns a stall into a capture. It is a
  ## fallback rather than a default because one wave from everywhere
  ## sends far more than a cheap neutral is worth.
  result = Wave(sourceId: -1, targetId: -1, percent: 0)
  var bestNeeded = high(int)
  for target in planets:
    if not target.found or target.ownerId == bot.ownPlayerId:
      continue
    let needed = bot.captureCost(target) - bot.committedAgainst(target.id)
    if needed <= 0 or needed >= bestNeeded:
      continue
    var percent = MinSendPercent
    while percent <= MaxSendPercent:
      if bot.massLaunchTotal(planets, target.id, percent) >= needed:
        bestNeeded = needed
        result = Wave(sourceId: -2, targetId: target.id, percent: percent)
        break
      percent += SendPercentStep

proc richestOwned(bot: Bot, planets: openArray[PlanetSight]): PlanetSight =
  ## Returns the owned planet holding the most ships: where the fleet is.
  var best = -1
  for planet in planets:
    if not planet.found or planet.ownerId != bot.ownPlayerId:
      continue
    let ships = bot.estimatedShips(planet)
    if ships > best:
      best = ships
      result = planet

proc ownedCount(bot: Bot, planets: openArray[PlanetSight]): int =
  ## Returns how many planets we hold.
  for planet in planets:
    if planet.found and planet.ownerId == bot.ownPlayerId:
      inc result

proc bigPlanetsLeft(bot: Bot, planets: openArray[PlanetSight]): bool =
  ## Returns true while any large planet is still not ours.
  for planet in planets:
    if planet.found and planet.ownerId != bot.ownPlayerId and
        planet.radius >= LargeSpriteRadius:
      return true
  false

proc updatePhase(bot: var Bot, planets: openArray[PlanetSight]) =
  ## Advances the opening plan. Phases only ever move forward.
  case bot.phase
  of PhaseOpening:
    if bot.ownedCount(planets) >= OpeningPlanetTarget:
      bot.phase = PhaseBigPlanets
  of PhaseBigPlanets:
    if not bot.bigPlanetsLeft(planets):
      bot.phase = PhaseSnake
  of PhaseSnake:
    discard

proc nearestTarget(
  bot: Bot,
  planets: openArray[PlanetSight],
  fromPlanet: PlanetSight,
  wantBig: bool,
  maxShips, available: int
): PlanetSight =
  ## Returns the closest planet this fleet can actually take.
  ##
  ## Affordability is not optional even at a full send: a wave that lands
  ## one ship short changes nothing, and the target keeps every ship it
  ## survived with. Nearest-first is the plan; nearest-we-can-hold is the
  ## plan that works.
  var bestDistance = high(int)
  for target in planets:
    if not target.found or target.ownerId == bot.ownPlayerId:
      continue
    if wantBig and target.radius < LargeSpriteRadius:
      continue
    if maxShips > 0 and bot.estimatedShips(target) > maxShips:
      continue
    let needed =
      bot.captureCost(target) - bot.committedAgainst(target.id)
    if needed <= 0 or needed > available:
      continue
    let away = distance(fromPlanet.x, fromPlanet.y, target.x, target.y)
    if away < bestDistance:
      bestDistance = away
      result = target

proc decideCommands(bot: var Bot): seq[BotCommand] =
  ## Returns the clicks to send this tick.
  let planets = bot.visiblePlanets()
  bot.rememberPlanets(planets)
  bot.updateIdentity(planets)
  bot.selectedPlanetId = planets.selectedPlanetId()
  if bot.ownPlayerId <= 0:
    # Nothing identifies us yet. Select everything we own; the rings that
    # come back name our planets and our color.
    bot.intent = "identify"
    return @[BotCommand(kind: ClickSelectAll, x: 0, y: 0)]
  if bot.sweptAtTick < 0 and planets.len > 0:
    var owned = 0
    for planet in planets:
      if planet.ownerId == bot.ownPlayerId:
        inc owned
    if owned == planets.len:
      bot.sweptAtTick = bot.frameTick
      echo "SWEEP tick=", bot.frameTick, " planets=", owned
  if bot.frameTick < bot.waveCooldownUntil:
    bot.intent = "cooldown"
    return @[]
  bot.updatePhase(planets)
  let anchor = bot.richestOwned(planets)
  if not anchor.found:
    bot.intent = "no planets"
    return @[]
  # Every wave is a full commitment, so the fleet stays together instead
  # of dribbling out in pieces that arrive too small to take anything.
  let
    pooled = bot.massLaunchTotal(planets, -1, FleetPercent)
    solo = launchCount(bot.estimatedShips(anchor), FleetPercent)
    target =
      case bot.phase
      of PhaseOpening:
        bot.nearestTarget(
          planets, anchor, false, OpeningMaxNeutralShips, pooled
        )
      of PhaseBigPlanets:
        bot.nearestTarget(planets, anchor, true, 0, pooled)
      of PhaseSnake:
        bot.nearestTarget(planets, anchor, false, 0, solo)
  if not target.found:
    # The phase filter found nothing; fall back to anything capturable so
    # the bot never idles waiting for a planet that will not appear.
    # Prefer the snake: if the stack alone can take the nearest planet,
    # send only that stack and leave every other planet's ships free for
    # the next capture. Pool the empire only when one planet is short.
    let soloTarget = bot.nearestTarget(planets, anchor, false, 0, solo)
    if soloTarget.found:
      bot.waveCooldownUntil = bot.frameTick + WaveCooldownTicks
      bot.commit(soloTarget, anchor, solo, flightTicks(anchor, soloTarget))
      bot.lastWave = Wave(
        sourceId: anchor.id, targetId: soloTarget.id, percent: FleetPercent
      )
      bot.intent = "snake " & $anchor.id & " -> " & $soloTarget.id
      return @[
        BotCommand(
          kind: ClickPlain, x: anchor.x, y: anchor.y, percent: FleetPercent
        ),
        BotCommand(
          kind: ClickPlain, x: soloTarget.x, y: soloTarget.y, percent: 0
        )
      ]
    let anyTarget = bot.nearestTarget(planets, anchor, false, 0, pooled)
    if not anyTarget.found:
      bot.intent = "nothing left to take"
      return @[]
    bot.waveCooldownUntil = bot.frameTick + WaveCooldownTicks
    bot.commit(anyTarget, anchor, pooled, flightTicks(anchor, anyTarget))
    bot.lastWave = Wave(
      sourceId: anchor.id, targetId: anyTarget.id, percent: FleetPercent
    )
    bot.intent = "fallback -> " & $anyTarget.id
    return @[
      BotCommand(
        kind: ClickSelectAll, x: 0, y: 0, percent: FleetPercent
      ),
      BotCommand(kind: ClickPlain, x: anyTarget.x, y: anyTarget.y, percent: 0)
    ]
  bot.waveCooldownUntil = bot.frameTick + WaveCooldownTicks
  if bot.phase == PhaseSnake:
    # One stack rolling forward: send everything from wherever the fleet
    # currently sits to the nearest neutral, then again from there.
    bot.commit(target, anchor, solo, flightTicks(anchor, target))
    bot.lastWave = Wave(
      sourceId: anchor.id, targetId: target.id, percent: FleetPercent
    )
    bot.intent = "snake " & $anchor.id & " -> " & $target.id
    return @[
      BotCommand(
        kind: ClickPlain, x: anchor.x, y: anchor.y, percent: FleetPercent
      ),
      BotCommand(kind: ClickPlain, x: target.x, y: target.y, percent: 0)
    ]
  bot.commit(target, anchor, pooled, flightTicks(anchor, target))
  bot.lastWave = Wave(
    sourceId: -2, targetId: target.id, percent: FleetPercent
  )
  bot.intent = $bot.phase & " -> " & $target.id
  @[
    BotCommand(kind: ClickSelectAll, x: 0, y: 0, percent: FleetPercent),
    BotCommand(kind: ClickPlain, x: target.x, y: target.y, percent: 0)
  ]

proc addI16(packet: var seq[uint8], value: int) =
  ## Appends one little endian signed 16 bit value.
  let v = uint16(int16(value))
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc sendPercentBlob(percent: int): string =
  ## Builds a Planet Wars send-size packet.
  blobFromBytes([PlanetWarsPercent, uint8(clamp(percent, 10, 100))])

proc clickBlob(command: BotCommand): string =
  ## Builds a Planet Wars click packet.
  var bytes: seq[uint8] = @[PlanetWarsClick]
  bytes.addI16(command.x)
  bytes.addI16(command.y)
  bytes.add(command.kind)
  blobFromBytes(bytes)

proc chatBlob(text: string): string =
  ## Builds a sprite protocol text input packet.
  var bytes: seq[uint8] = @[0x81'u8]
  bytes.addU16(text.len)
  for ch in text:
    bytes.add(uint8(ord(ch)))
  blobFromBytes(bytes)

proc echoDebug(bot: Bot, force = false) =
  ## Prints occasional bot status for local tuning.
  if not force and bot.frameTick mod TargetFps != 0:
    return
  echo "step=", bot.frameTick,
    " self=", bot.ownPlayerId,
    " selected=", bot.selectedPlanetId,
    " wave=", bot.lastWave.sourceId, "->", bot.lastWave.targetId,
    " pct=", bot.lastWave.percent,
    " intent=", bot.intent

proc queryEscape(value: string): string =
  ## Escapes a query string component.
  const Hex = "0123456789ABCDEF"
  for ch in value:
    if ch.isAlphaNumeric() or ch in {'-', '_', '.', '~'}:
      result.add(ch)
    else:
      let byte = ord(ch)
      result.add('%')
      result.add(Hex[(byte shr 4) and 0x0f])
      result.add(Hex[byte and 0x0f])

proc withPath(url, path: string): string =
  ## Adds a websocket path when the supplied URL has no path.
  let schemePos = url.find("://")
  let start =
    if schemePos < 0:
      0
    else:
      schemePos + 3
  for i in start ..< url.len:
    case url[i]
    of '/':
      return url
    of '?', '#':
      return url[0 ..< i] & path & url[i .. ^1]
    else:
      discard
  url & path

proc addQueryParam(url, key, value: string): string =
  ## Appends one escaped query parameter to a URL.
  if value.len == 0:
    return url
  result = url
  if '?' in result:
    result.add('&')
  else:
    result.add('?')
  result.add(key)
  result.add('=')
  result.add(value.queryEscape())

proc connectUrl(
  address,
  url,
  name,
  token: string,
  port,
  slot: int
): string =
  ## Builds the player websocket URL.
  if url.len > 0:
    result = url.withPath(WebSocketPath)
  else:
    result = "ws://" & address & ":" & $port & WebSocketPath
  result = result.addQueryParam("name", name)
  if slot >= 0:
    result = result.addQueryParam("slot", $slot)
  result = result.addQueryParam("token", token)

proc initBot(): Bot =
  ## Creates a fresh Skurge bot state.
  result.rng = initRand(getTime().toUnix() xor int64(getCurrentProcessId()))
  result.ownPlayerId = -1
  result.selectedPlanetId = -1
  result.originPlanetId = -1
  result.lastWave = Wave(sourceId: -1, targetId: -1, percent: 0)
  result.sweptAtTick = -1
  result.committedShips = newSeq[int](MaxPlanetCount + 1)
  result.commitmentExpiry = newSeq[int](MaxPlanetCount + 1)

proc acceptServerMessage(
  ws: WebSocket,
  message: Message,
  bot: var Bot
): bool =
  ## Handles one websocket message from the game server.
  case message.kind
  of BinaryMessage:
    result = bot.applySpritePacket(message.data)
    if result:
      inc bot.frameTick
  of Ping:
    ws.send(message.data, Pong)
  of TextMessage, Pong:
    discard

proc receiveUpdates(ws: WebSocket, bot: var Bot): bool =
  ## Receives and applies all currently queued sprite updates.
  let firstMessage = ws.receiveMessage(-1)
  if firstMessage.isNone:
    return false
  if ws.acceptServerMessage(firstMessage.get, bot):
    result = true
  var drained = 0
  while drained < MaxDrainMessages:
    let message = ws.receiveMessage(0)
    if message.isNone:
      break
    if ws.acceptServerMessage(message.get, bot):
      result = true
    inc drained

proc runBot(
  address = DefaultHost,
  port = SkurgeDefaultPort,
  url = "",
  name = "skurge",
  token = "",
  slot = -1,
  maxSteps = 0,
  chat = false,
  exitOnDisconnect = false
) =
  ## Connects Skurge to Planet Wars and runs the attack policy.
  let endpoint = connectUrl(address, url, name, token, port, slot)
  var connected = false
  while true:
    try:
      echo "skurge connecting to ", endpoint
      var bot = initBot()
      let ws = newWebSocket(endpoint)
      connected = true
      var lastPercent = 0
      if chat:
        ws.send(chatBlob("skurge online"), BinaryMessage)
      while true:
        if not ws.receiveUpdates(bot):
          continue
        let commands = bot.decideCommands()
        bot.echoDebug(commands.len > 0)
        for command in commands:
          if command.percent > 0 and command.percent != lastPercent:
            ws.send(sendPercentBlob(command.percent), BinaryMessage)
            lastPercent = command.percent
          ws.send(clickBlob(command), BinaryMessage)
        if maxSteps > 0 and bot.frameTick >= maxSteps:
          bot.echoDebug(true)
          ws.close()
          return
    except CatchableError as e:
      if exitOnDisconnect and connected:
        echo "skurge exiting after disconnect: ", e.msg
        return
      echo "skurge reconnecting after error: ", e.msg
      sleep(250)

when isMainModule:
  var
    address = DefaultHost
    port = SkurgeDefaultPort
    url = getEnv("COGAMES_ENGINE_WS_URL")
    name =
      if url.len > 0:
        ""
      else:
        "skurge"
    token = ""
    slot = -1
    maxSteps = 0
    chat = false
    exitOnDisconnect = url.len > 0

  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      case key
      of "address":
        address = value
      of "port":
        port = parseInt(value)
      of "url":
        url = value
      of "name":
        name = value
      of "token":
        token = value
      of "slot":
        slot = parseInt(value)
      of "max-steps":
        maxSteps = parseInt(value)
      of "chat":
        chat = true
      of "exit-on-disconnect":
        exitOnDisconnect = true
      else:
        raise newException(ValueError, "Unknown option: --" & key)
    of cmdArgument, cmdShortOption:
      raise newException(ValueError, "Unexpected argument: " & key)
    of cmdEnd:
      discard

  runBot(
    address,
    port,
    url,
    name,
    token,
    slot,
    maxSteps,
    chat,
    exitOnDisconnect
  )
