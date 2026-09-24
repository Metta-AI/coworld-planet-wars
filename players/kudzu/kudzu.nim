## Kudzu: cost-aware expansion bot for Planet Wars.
##
## Policy (deliberately different from skurge's fight-first bursts):
##   - Score is ownedPlanets^2 per second, so maximize planet count early.
##   - Always capture the cheapest reachable planet: prefer neutrals,
##     attack enemies only when clearly affordable.
##   - Send a budgeted burst (target ships + margin), not a full drain,
##     from the nearest owned planet that can afford the job.
##   - Rotate origins around the frontier instead of one home planet.
##
## Protocol layer (sprite parsing, connection) is shared with sprout.

import
  std/[json, options, os, parseopt, posix, strutils],
  supersnappy, whisky,
  bitworld/spriteprotocol,
  planet_wars/sim,
  systemone

const
  MaxDrainMessages = 256
  NeutralPlanetSpriteBase = 100
  PlayerPlanetSpriteBase = 1000
  PlayerShipSpriteBase = 2000
  PlayerCursorSpriteBase = 5000
  PlanetTextSpriteBase = 10000
  PlanetObjectBase = 2000
  PlanetSelectedObjectBase = 2100
  PlanetOriginObjectBase = 2200
  PlanetTextObjectBase = 2300
  CursorObjectBase = 12000
  PlanetSpriteStride = 8
  CursorSpriteSize = 5
  CursorDeadband = 3
  OriginSelectInterval = 8
  OriginReserveShips = 1
  CaptureMargin = 2
  EnemyCaptureMargin = 5
  UnknownShipsEstimate = 12
  UnknownOriginBudget = 24
  MinLaunchShips = 3
  # Estimated ticks per grown ship at 60 fps (small/medium/large), the
  # midpoints of the server's randomized growth intervals.
  GrowthIntervalTicks = [120, 90, 60]
  MissionTimeoutTicks = TargetFps * 8
  OriginAvoidTicks = TargetFps * 15
  # Losing this many ships beyond our own sends within the loss window
  # means the planet is being drained by enemy fire (growth drift alone
  # stays smaller); contested planets are banned as origins for longer.
  # Losses are accumulated across sightings so both a big gap discovered
  # after an absence and gradual 1-by-1 draining in plain view trigger.
  ContestedLossShips = 3
  ContestedLossWindowTicks = TargetFps * 5
  ContestedAvoidTicks = TargetFps * 30
  # Consecutive missions from one origin that finish without capturing
  # anything before the origin is written off as contested. Outcome-based
  # and immune to ship-accounting drift: our own send mirror overestimates
  # spending while an enemy stream throttles the origin, which masks the
  # enemy drain from loss detection entirely.
  MaxOriginFailStreak = 2
  # Finish the kill: when the target is this close to flipping, keep
  # the burst going instead of abandoning one ship short. Bounded by a
  # total mission time so a regrowing enemy cannot extend us forever.
  FinishKillShips = 3
  FinishKillExtendTicks = TargetFps div 2
  MaxMissionTicks = TargetFps * 25
  # Flat score bonus per planet size (small/medium/large). Large planets
  # grow ships ~2x faster than small ones, but planet count compounds
  # faster than growth, so the bonus is bounded: a large planet is only
  # worth ~55 extra pixels of travel, never a strategy change.
  SizeScoreBonus = [0, 1500, 3000]
  StuckSelectTicks = TargetFps * 2
  AvoidTicks = TargetFps * 6
  SendBurstMaxHoldTicks = TargetFps * 3
  SendBurstPaddingTicks = TargetFps div 4
  SweepPoints = [
    (x: 18, y: 18),
    (x: WorldWidthPixels - 18, y: 18),
    (x: WorldWidthPixels - 18, y: WorldHeightPixels - 18),
    (x: 18, y: WorldHeightPixels - 18),
    (x: WorldWidthPixels div 2, y: WorldHeightPixels div 2)
  ]
  SweepArrivalRadius = 18

type
  SpriteKind = enum
    SpriteUnknown
    SpriteMap
    SpriteNeutralPlanet
    SpritePlayerPlanet
    SpriteCursor
    SpriteOther

  SpriteInfo = object
    defined: bool
    width: int
    height: int
    label: string
    kind: SpriteKind
    ownerId: int
    sizeOrd: int

  ObjectState = object
    present: bool
    x: int
    y: int
    spriteId: int

  PlanetSight = object
    found: bool
    id: int
    ownerId: int
    ships: int
    sizeOrd: int     ## 0 small, 1 medium, 2 large (growth speed).
    seenTick: int    ## Frame the ship count was last read.
    x: int
    y: int
    selected: bool
    origin: bool

  MissionPhase = enum
    PhaseIdle        ## No mission: sweep and look for work.
    PhaseGoOrigin    ## Steer to the mission origin planet.
    PhaseSetOrigin   ## Press A to make it the send origin.
    PhaseGoTarget    ## Steer to the mission target planet.
    PhaseSend        ## Hold B for the planned burst window.

  Mission = object
    phase: MissionPhase
    originId: int
    targetId: int
    budget: int      ## Ships this mission may spend.
    allIn: bool      ## Pressure raid: spend the whole origin.
    startedTick: int
    sendUntilTick: int
    sendHoldTicks: int
    sendCooldown: int

  Bot = object
    sprites: seq[SpriteInfo]
    objects: seq[ObjectState]
    knownPlanets: seq[PlanetSight]
    spentShips: seq[int]   ## Ships sent from each planet since last sighting.
    originAvoidUntil: seq[int]  ## Tick until a planet is banned as origin.
    lossAccum: seq[int]    ## Unexplained ship losses in the recent window.
    lossTick: seq[int]     ## Tick of the last unexplained loss per planet.
    originFailStreak: seq[int]  ## Consecutive captureless missions per origin.
    cameraX: int
    cameraY: int
    frameTick: int
    ownPlayerId: int
    sweepIndex: int
    intent: string
    mission: Mission
    pendingChoices: seq[MissionChoice]
    lastSelectedId: int
    selectionStuckTicks: int
    avoidedTargetId: int
    avoidUntilTick: int

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
): tuple[kind: SpriteKind, ownerId: int, sizeOrd: int] =
  ## Classifies one Planet Wars sprite id. Planet sprite ids encode the
  ## planet size (0 small, 1 medium, 2 large) in their low stride bits.
  if spriteId == MapSpriteId:
    return (SpriteMap, 0, 0)
  if spriteId >= NeutralPlanetSpriteBase and
      spriteId < NeutralPlanetSpriteBase + PlanetSpriteStride:
    return (SpriteNeutralPlanet, 0, spriteId - NeutralPlanetSpriteBase)
  if spriteId >= PlayerPlanetSpriteBase and
      spriteId < PlayerShipSpriteBase:
    return (
      SpritePlayerPlanet,
      (spriteId - PlayerPlanetSpriteBase) div PlanetSpriteStride,
      (spriteId - PlayerPlanetSpriteBase) mod PlanetSpriteStride
    )
  if spriteId >= PlayerCursorSpriteBase and
      spriteId < PlanetTextSpriteBase:
    return (SpriteCursor, spriteId - PlayerCursorSpriteBase, 0)
  if label.len > 0:
    return (SpriteOther, 0, 0)
  (SpriteUnknown, 0, 0)

proc resetMission(bot: var Bot) =
  ## Abandons the current mission.
  bot.mission = Mission(phase: PhaseIdle, originId: -1, targetId: -1)

proc resetGameState(bot: var Bot) =
  ## Clears per-game state when the server starts a new game.
  for item in bot.objects.mitems:
    item.present = false
  bot.knownPlanets.setLen(0)
  bot.spentShips.setLen(0)
  bot.originAvoidUntil.setLen(0)
  bot.lossAccum.setLen(0)
  bot.lossTick.setLen(0)
  bot.originFailStreak.setLen(0)
  bot.pendingChoices.setLen(0)
  bot.frameTick = 0
  bot.ownPlayerId = -1
  bot.lastSelectedId = -1
  bot.selectionStuckTicks = 0
  bot.avoidedTargetId = -1
  bot.avoidUntilTick = 0
  bot.resetMission()

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
      let classified = classifySprite(spriteId, label)
      bot.ensureSprite(spriteId)
      bot.sprites[spriteId] = SpriteInfo(
        defined: true,
        width: width,
        height: height,
        label: label,
        kind: classified.kind,
        ownerId: classified.ownerId,
        sizeOrd: classified.sizeOrd
      )
    of 0x02:
      if offset + 11 > packet.len:
        return false
      let
        objectId = packet.readU16(offset)
        x = packet.readI16(offset + 2)
        y = packet.readI16(offset + 4)
        spriteId = packet.readU16(offset + 9)
      offset += 11
      bot.ensureObject(objectId)
      bot.objects[objectId] = ObjectState(
        present: true,
        x: x,
        y: y,
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
      bot.resetGameState()
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

proc parseShips(label: string): int =
  ## Parses a dynamic ship-count sprite label.
  const Prefix = "ships "
  if not label.startsWith(Prefix):
    return -1
  try:
    parseInt(label.substr(Prefix.len))
  except ValueError:
    -1

proc planetShips(bot: Bot, planetId: int): int =
  ## Returns the visible ship count for one planet id or -1.
  let textId = PlanetTextObjectBase + planetId
  if not bot.objectPresent(textId):
    return -1
  let sprite = bot.spriteInfo(bot.objects[textId].spriteId)
  sprite.label.parseShips()

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
    sizeOrd: sprite.sizeOrd,
    seenTick: bot.frameTick,
    x: bot.cameraX + objectState.x + sprite.width div 2,
    y: bot.cameraY + objectState.y + sprite.height div 2,
    selected: bot.objectPresent(PlanetSelectedObjectBase + planetId),
    origin: bot.objectPresent(PlanetOriginObjectBase + planetId)
  )

proc visiblePlanets(bot: Bot): seq[PlanetSight] =
  ## Returns all currently visible planets.
  for planetId in 1 .. MaxPlanetCount:
    let planet = bot.planetSight(planetId)
    if planet.found:
      result.add(planet)

proc estimatedShips(bot: Bot, planet: PlanetSight): int =
  ## Estimates one remembered planet's current ship count: owned planets
  ## grow while out of view, and ships we launched from an origin are
  ## deducted until the next sighting.
  result = planet.ships
  if result < 0:
    return
  if planet.ownerId != 0:
    let elapsed = max(0, bot.frameTick - planet.seenTick)
    result += elapsed div GrowthIntervalTicks[clamp(planet.sizeOrd, 0, 2)]
  if planet.id < bot.spentShips.len:
    result = max(0, result - bot.spentShips[planet.id])

proc rememberPlanets(bot: var Bot, planets: openArray[PlanetSight]) =
  ## Updates remembered planet sightings from the current viewport.
  if bot.knownPlanets.len <= MaxPlanetCount:
    bot.knownPlanets.setLen(MaxPlanetCount + 1)
  if bot.spentShips.len <= MaxPlanetCount:
    bot.spentShips.setLen(MaxPlanetCount + 1)
  if bot.originAvoidUntil.len <= MaxPlanetCount:
    bot.originAvoidUntil.setLen(MaxPlanetCount + 1)
  if bot.lossAccum.len <= MaxPlanetCount:
    bot.lossAccum.setLen(MaxPlanetCount + 1)
  if bot.lossTick.len <= MaxPlanetCount:
    bot.lossTick.setLen(MaxPlanetCount + 1)
  if bot.originFailStreak.len <= MaxPlanetCount:
    bot.originFailStreak.setLen(MaxPlanetCount + 1)
  for planet in planets:
    if planet.id >= 0 and planet.id < bot.knownPlanets.len:
      # Contested-origin detection, before overwriting memory: ships
      # lost beyond the forward estimate (growth minus our own sends)
      # can only be enemy fire. Losses accumulate over a short window,
      # so gradual 1-by-1 draining in plain view triggers just like a
      # big gap discovered after an absence. Contested planets are
      # useless origins — missions from them keep getting drained
      # mid-send — so ban them for a while and settle from elsewhere.
      let previous = bot.knownPlanets[planet.id]
      if planet.ships >= 0 and previous.found and previous.ships >= 0 and
          planet.ownerId == bot.ownPlayerId and
          previous.ownerId == planet.ownerId:
        let loss = bot.estimatedShips(previous) - planet.ships
        if loss > 0:
          if bot.frameTick - bot.lossTick[planet.id] >
              ContestedLossWindowTicks:
            bot.lossAccum[planet.id] = 0
          bot.lossAccum[planet.id] += loss
          bot.lossTick[planet.id] = bot.frameTick
          if bot.lossAccum[planet.id] >= ContestedLossShips:
            bot.originAvoidUntil[planet.id] =
              bot.frameTick + ContestedAvoidTicks
            bot.lossAccum[planet.id] = 0
      bot.knownPlanets[planet.id] = planet
      if planet.ships >= 0:
        # A fresh ship-count reading resets the spent estimate.
        bot.spentShips[planet.id] = 0
        # A planet observed too weak to launch is abandoned as an origin
        # for a while: under enemy fire it never actually recovers on the
        # growth schedule our out-of-view estimate assumes, so retrying it
        # locks the bot into a depleted-vs-depleted trench war.
        if planet.ownerId == bot.ownPlayerId and
            planet.ships - OriginReserveShips < MinLaunchShips:
          bot.originAvoidUntil[planet.id] = max(
            bot.originAvoidUntil[planet.id],
            bot.frameTick + OriginAvoidTicks
          )

proc knownPlanetSights(bot: Bot): seq[PlanetSight] =
  ## Returns remembered planet sightings with estimated ship counts.
  for planet in bot.knownPlanets:
    if not planet.found:
      continue
    var estimated = planet
    estimated.ships = bot.estimatedShips(planet)
    result.add(estimated)

proc updateIdentity(bot: var Bot, planets: openArray[PlanetSight]) =
  ## Recognizes our player id from the origin ring on an owned planet.
  if bot.ownPlayerId > 0:
    return
  for planet in planets:
    if planet.origin and planet.ownerId > 0:
      bot.ownPlayerId = planet.ownerId
      echo "kudzu identified self as player ", bot.ownPlayerId
      return

proc cursorWorld(bot: Bot): tuple[x, y: int] =
  ## Reads our visible cursor world position.
  if bot.ownPlayerId > 0:
    let objectId = CursorObjectBase + bot.ownPlayerId
    if bot.objectPresent(objectId):
      let
        objectState = bot.objects[objectId]
        sprite = bot.spriteInfo(objectState.spriteId)
        width =
          if sprite.defined:
            sprite.width
          else:
            CursorSpriteSize
        height =
          if sprite.defined:
            sprite.height
          else:
            CursorSpriteSize
      return (
        bot.cameraX + objectState.x + width div 2,
        bot.cameraY + objectState.y + height div 2
      )
  (
    bot.cameraX + PlayerViewportWidth div 2,
    bot.cameraY + PlayerViewportHeight div 2
  )

proc distanceSquared(ax, ay, bx, by: int): int =
  ## Returns squared distance between two points.
  let
    dx = ax - bx
    dy = ay - by
  dx * dx + dy * dy

proc steerMask(bot: Bot, targetX, targetY: int): uint8 =
  ## Builds single-axis d-pad input toward one world point.
  let
    cursor = bot.cursorWorld()
    dx = targetX - cursor.x
    dy = targetY - cursor.y
  if abs(dx) <= CursorDeadband and abs(dy) <= CursorDeadband:
    return 0
  if abs(dx) >= abs(dy):
    if dx < 0:
      return ButtonLeft
    return ButtonRight
  if dy < 0:
    return ButtonUp
  ButtonDown

proc sweepMask(bot: var Bot): uint8 =
  ## Moves the cursor through map corners to reveal the world.
  let
    point = SweepPoints[bot.sweepIndex mod SweepPoints.len]
    cursor = bot.cursorWorld()
  if distanceSquared(cursor.x, cursor.y, point.x, point.y) <=
      SweepArrivalRadius * SweepArrivalRadius:
    inc bot.sweepIndex
  let nextPoint = SweepPoints[bot.sweepIndex mod SweepPoints.len]
  bot.intent = "sweep " & $bot.sweepIndex
  bot.steerMask(nextPoint.x, nextPoint.y)

proc selectedPlanetId(planets: openArray[PlanetSight]): int =
  ## Returns the currently selected visible planet id.
  for planet in planets:
    if planet.selected:
      return planet.id
  -1

proc findPlanet(
  planets: openArray[PlanetSight],
  planetId: int
): PlanetSight =
  ## Finds one known planet by id.
  for planet in planets:
    if planet.id == planetId:
      return planet
  PlanetSight()

proc shipsOrEstimate(planet: PlanetSight): int =
  ## Returns visible ships or a conservative estimate.
  if planet.ships < 0:
    return UnknownShipsEstimate
  planet.ships

proc captureCost(bot: Bot, target: PlanetSight): int =
  ## Returns the ships needed to capture one planet.
  if target.ownerId == 0:
    return target.shipsOrEstimate() + CaptureMargin
  target.shipsOrEstimate() + EnemyCaptureMargin

proc availableShips(planet: PlanetSight): int =
  ## Returns the ships one owned planet can spend.
  if planet.ships < 0:
    return UnknownOriginBudget
  max(0, planet.ships - OriginReserveShips)

proc burstTickCount(shipCount: int): int =
  ## Converts a planned ship count into held-send ticks, mirroring the
  ## server's accelerating send-repeat schedule.
  let plannedShips = max(1, shipCount)
  var
    sent = 0
    holdTicks = 0
    cooldown = 0
  while sent < plannedShips and holdTicks < SendBurstMaxHoldTicks:
    inc holdTicks
    if cooldown > 0:
      dec cooldown
    if cooldown == 0:
      inc sent
      cooldown = max(
        MinSendRepeatInterval,
        BaseSendRepeatInterval - holdTicks div SendAccelerationTicks
      )
  min(SendBurstMaxHoldTicks, holdTicks + SendBurstPaddingTicks)

proc usableOrigin(bot: Bot, planet: PlanetSight): bool =
  ## Returns true when one owned planet may launch missions: strong
  ## enough and not recently observed depleted (abandoned).
  if planet.ownerId != bot.ownPlayerId:
    return false
  if planet.id < bot.originAvoidUntil.len and
      bot.frameTick < bot.originAvoidUntil[planet.id]:
    return false
  planet.availableShips() >= MinLaunchShips

proc planPressureMission(bot: var Bot, known: openArray[PlanetSight]) =
  ## Fallback when nothing is affordable: throw the richest planet's
  ## whole stock at the nearest target so pressure never stops.
  var origin = PlanetSight()
  for candidate in known:
    if not bot.usableOrigin(candidate):
      continue
    if not origin.found or
        candidate.availableShips() > origin.availableShips():
      origin = candidate
  if not origin.found:
    return
  var
    bestScore = high(int)
    bestTarget = PlanetSight()
  for wantEnemies in [false, true]:
    for target in known:
      if target.ownerId == bot.ownPlayerId:
        continue
      if (target.ownerId != 0) != wantEnemies:
        continue
      if target.id == bot.avoidedTargetId and
          bot.frameTick < bot.avoidUntilTick:
        continue
      let score = distanceSquared(origin.x, origin.y, target.x, target.y) +
        bot.captureCost(target) * bot.captureCost(target)
      if score < bestScore:
        bestScore = score
        bestTarget = target
    if bestTarget.found:
      break
  if not bestTarget.found:
    return
  bot.mission = Mission(
    phase: PhaseGoOrigin,
    originId: origin.id,
    targetId: bestTarget.id,
    budget: origin.availableShips(),
    allIn: true,
    startedTick: bot.frameTick
  )
  bot.intent = "pressure " & $origin.id & "->" & $bestTarget.id &
    " allin " & $bot.mission.budget

proc planMission(bot: var Bot, known: openArray[PlanetSight]) =
  ## Picks the cheapest affordable capture as the next mission.
  ## Colonizing is strictly prioritized: neutral planets never regrow,
  ## so ships spent there are permanent progress, while attacking an
  ## enemy frontline planet feeds an endless regrow-and-reinforce war.
  ## Enemies are only targeted when no neutral mission exists at all.
  var
    bestScore = high(int)
    bestOrigin = PlanetSight()
    bestTarget = PlanetSight()
  bot.pendingChoices.setLen(0)
  for wantEnemies in [false, true]:
    bot.pendingChoices.setLen(0)
    for target in known:
      if target.ownerId == bot.ownPlayerId:
        continue
      if (target.ownerId != 0) != wantEnemies:
        continue
      if target.id == bot.avoidedTargetId and
          bot.frameTick < bot.avoidUntilTick:
        continue
      let cost = bot.captureCost(target)
      # Find the nearest owned planet that can afford this target, then
      # upgrade to the richest origin within 2x that distance: stockpiled
      # rear planets should fund expansion instead of sitting idle while
      # a barely-affording frontier planet drip-feeds every mission.
      var nearestScore = high(int)
      for candidate in known:
        if not bot.usableOrigin(candidate) or
            candidate.availableShips() < cost:
          continue
        let distance = distanceSquared(
          candidate.x, candidate.y, target.x, target.y
        )
        if distance < nearestScore:
          nearestScore = distance
      if nearestScore == high(int):
        continue
      var
        origin = PlanetSight()
        originScore = nearestScore
        originShips = -1
      for candidate in known:
        if not bot.usableOrigin(candidate) or
            candidate.availableShips() < cost:
          continue
        let distance = distanceSquared(
          candidate.x, candidate.y, target.x, target.y
        )
        # 2x the distance means 4x the squared distance.
        if distance <= nearestScore * 4 and
            candidate.availableShips() > originShips:
          originShips = candidate.availableShips()
          originScore = distance
          origin = candidate
      if not origin.found:
        continue
      # Fast-growing planets get a bounded bonus as future ship factories.
      let score = originScore + cost * cost -
        SizeScoreBonus[clamp(target.sizeOrd, 0, 2)]
      let surplus = max(0, origin.availableShips() - cost)
      bot.pendingChoices.add(MissionChoice(
        originId: origin.id, targetId: target.id,
        budget: cost + surplus div 2, score: score
      ))
      if score < bestScore:
        bestScore = score
        bestOrigin = origin
        bestTarget = target
    if bestTarget.found:
      break
  if bestTarget.found:
    # Send the capture cost plus half the origin's surplus: the extra
    # ships garrison the captured planet, turning it into a well-stocked
    # origin for the next hop instead of leaving wealth pooled in the rear.
    let
      cost = bot.captureCost(bestTarget)
      surplus = max(0, bestOrigin.availableShips() - cost)
    bot.mission = Mission(
      phase: PhaseGoOrigin,
      originId: bestOrigin.id,
      targetId: bestTarget.id,
      budget: cost + surplus div 2,
      startedTick: bot.frameTick
    )
    bot.intent = "mission " & $bestOrigin.id & "->" & $bestTarget.id &
      " budget " & $bot.mission.budget
  else:
    bot.planPressureMission(known)

proc missionValid(bot: Bot, known: openArray[PlanetSight]): bool =
  ## Returns true while the current mission still makes sense.
  if bot.mission.phase == PhaseIdle:
    return false
  if bot.frameTick - bot.mission.startedTick > MissionTimeoutTicks and
      bot.mission.phase != PhaseSend:
    return false
  let origin = known.findPlanet(bot.mission.originId)
  if not origin.found or origin.ownerId != bot.ownPlayerId:
    return false
  # Abort early when the planned origin turns out too weak to matter
  # or got abandoned (observed depleted), instead of flying there and
  # camping on a 1-ship planet.
  if bot.mission.phase in {PhaseGoOrigin, PhaseSetOrigin} and
      not bot.usableOrigin(origin):
    return false
  let target = known.findPlanet(bot.mission.targetId)
  if not target.found or target.ownerId == bot.ownPlayerId:
    return false
  true

proc trackSelectionStuck(bot: var Bot, selectedId: int) =
  ## Counts ticks the selection has not changed while steering.
  if selectedId == bot.lastSelectedId:
    inc bot.selectionStuckTicks
  else:
    bot.lastSelectedId = selectedId
    bot.selectionStuckTicks = 0

proc loiterMask(bot: var Bot, known: openArray[PlanetSight]): uint8 =
  ## Idle behavior between missions: park the cursor at the richest
  ## owned planet instead of sweeping the whole map. That keeps the
  ## cursor calm, near the next likely launch site, and refreshes that
  ## planet's ship count. Sweeps only when nothing is known to park at.
  var best = PlanetSight()
  for planet in known:
    if planet.ownerId != bot.ownPlayerId:
      continue
    if not best.found or planet.availableShips() > best.availableShips():
      best = planet
  if not best.found:
    return bot.sweepMask()
  bot.intent = "loiter " & $best.id
  bot.steerMask(best.x, best.y)

proc decideNextMask(bot: var Bot): uint8 =
  ## Chooses the next controller mask: the settler-policy mission loop.
  bot.updateCamera()
  let visible = bot.visiblePlanets()
  bot.rememberPlanets(visible)
  bot.updateIdentity(visible)
  let
    known = bot.knownPlanetSights()
    selectedId = visible.selectedPlanetId()
  bot.trackSelectionStuck(selectedId)

  if bot.ownPlayerId <= 0:
    return bot.sweepMask()

  # Mission upkeep: drop finished/broken missions, plan a new one.
  if not bot.missionValid(known):
    let hadMission = bot.mission.phase != PhaseIdle
    bot.resetMission()
    if hadMission:
      bot.selectionStuckTicks = 0
    bot.planMission(known)
  if bot.mission.phase == PhaseIdle:
    bot.intent = "scout"
    return bot.loiterMask(known)

  let
    origin = known.findPlanet(bot.mission.originId)
    target = known.findPlanet(bot.mission.targetId)

  # If the cursor cannot reach a planet (selection stuck too long),
  # blacklist the target briefly and re-plan.
  if bot.mission.phase in {PhaseGoOrigin, PhaseGoTarget} and
      bot.selectionStuckTicks > StuckSelectTicks + MissionTimeoutTicks:
    bot.avoidedTargetId = bot.mission.targetId
    bot.avoidUntilTick = bot.frameTick + AvoidTicks
    bot.resetMission()
    bot.intent = "unstick"
    return bot.sweepMask()

  case bot.mission.phase
  of PhaseIdle:
    return bot.sweepMask()
  of PhaseGoOrigin:
    if origin.origin:
      bot.mission.phase = PhaseGoTarget
      bot.intent = "origin ready " & $origin.id
      return 0
    if selectedId == origin.id:
      bot.mission.phase = PhaseSetOrigin
      return 0
    bot.intent = "go origin " & $origin.id
    return bot.steerMask(origin.x, origin.y)
  of PhaseSetOrigin:
    if origin.origin:
      bot.mission.phase = PhaseGoTarget
      return 0
    if selectedId != origin.id:
      bot.mission.phase = PhaseGoOrigin
      return 0
    bot.intent = "set origin " & $origin.id
    if bot.frameTick mod OriginSelectInterval == 0:
      return ButtonA
    return 0
  of PhaseGoTarget:
    if not origin.origin:
      bot.mission.phase = PhaseGoOrigin
      return 0
    if selectedId == target.id:
      bot.mission.phase = PhaseSend
      bot.mission.sendUntilTick =
        bot.frameTick + burstTickCount(bot.mission.budget)
      bot.intent = "burst " & $bot.mission.budget & " at " & $target.id
      return ButtonB
    bot.intent = "go target " & $target.id
    return bot.steerMask(target.x, target.y)
  of PhaseSend:
    # Stop early when the origin is drained or the target flipped to us.
    if target.ownerId == bot.ownPlayerId:
      if origin.id < bot.originFailStreak.len:
        bot.originFailStreak[origin.id] = 0
      bot.resetMission()
      bot.intent = "captured " & $target.id
      return 0
    if origin.ships >= 0 and origin.ships <= OriginReserveShips:
      # Hold position while a nearly-flipped target's incoming ships
      # land; the origin regrows a ship every couple of seconds too.
      if target.ships >= 0 and target.ships <= FinishKillShips and
          bot.frameTick - bot.mission.startedTick < MaxMissionTicks:
        bot.intent = "finishing " & $target.id & " (origin low)"
        return ButtonB
      # An origin that ran dry mid-send is being outdrained by enemy
      # fire; ban it so the next mission launches from elsewhere.
      if origin.id < bot.originAvoidUntil.len:
        bot.originAvoidUntil[origin.id] =
          bot.frameTick + ContestedAvoidTicks
      bot.resetMission()
      bot.intent = "origin drained"
      return 0
    if selectedId != target.id:
      bot.mission.phase = PhaseGoTarget
      return 0
    if bot.frameTick >= bot.mission.sendUntilTick:
      # Finish the kill: a target about to flip is worth a short burst
      # extension — abandoning at 1 ship wastes the whole investment,
      # and ships already in flight need a moment to land.
      if target.ships >= 0 and target.ships <= FinishKillShips and
          (origin.ships < 0 or origin.ships > OriginReserveShips) and
          bot.frameTick - bot.mission.startedTick < MaxMissionTicks:
        bot.mission.sendUntilTick = bot.frameTick + FinishKillExtendTicks
        bot.intent = "finishing " & $target.id
        return ButtonB
      # The burst ran its full window without flipping the target: the
      # planned ships did not arrive as planned (enemy stream throttled
      # the origin or intercepted at the target). A couple of those in a
      # row marks the origin contested no matter what the ship
      # accounting says — outcomes cannot drift.
      if origin.id < bot.originFailStreak.len:
        inc bot.originFailStreak[origin.id]
        if bot.originFailStreak[origin.id] >= MaxOriginFailStreak:
          bot.originFailStreak[origin.id] = 0
          if origin.id < bot.originAvoidUntil.len:
            bot.originAvoidUntil[origin.id] =
              bot.frameTick + ContestedAvoidTicks
      bot.resetMission()
      bot.intent = "burst done"
      return 0
    # Mirror the server's held-send schedule so the origin's remembered
    # ship count stays honest while it is outside the viewport.
    inc bot.mission.sendHoldTicks
    if bot.mission.sendCooldown > 0:
      dec bot.mission.sendCooldown
    if bot.mission.sendCooldown == 0:
      if origin.id < bot.spentShips.len:
        inc bot.spentShips[origin.id]
      bot.mission.sendCooldown = max(
        MinSendRepeatInterval,
        BaseSendRepeatInterval -
          bot.mission.sendHoldTicks div SendAccelerationTicks
      )
    bot.intent = "sending to " & $target.id
    return ButtonB

proc playerInputBlob(mask: uint8): string =
  ## Builds a sprite protocol player input packet.
  blobFromBytes([0x84'u8, mask and 0x7f'u8])

proc maskSummary(mask: uint8): string =
  ## Returns a compact human-readable input mask.
  if (mask and ButtonUp) != 0:
    result.add("U")
  if (mask and ButtonDown) != 0:
    result.add("D")
  if (mask and ButtonLeft) != 0:
    result.add("L")
  if (mask and ButtonRight) != 0:
    result.add("R")
  if (mask and ButtonA) != 0:
    result.add("A")
  if (mask and ButtonB) != 0:
    result.add("B")
  if result.len == 0:
    result = "."

proc echoDebug(bot: Bot, mask: uint8, force = false) =
  ## Prints occasional bot status for local tuning.
  if not force and bot.frameTick mod TargetFps != 0:
    return
  echo "step=", bot.frameTick,
    " keys=", mask.maskSummary(),
    " self=", bot.ownPlayerId,
    " phase=", bot.mission.phase,
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
  ## Creates a fresh bot state.
  result.ownPlayerId = -1
  result.lastSelectedId = -1
  result.avoidedTargetId = -1
  result.mission = Mission(phase: PhaseIdle, originId: -1, targetId: -1)

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

proc recordInput(journal: File, bot: Bot, mask: uint8) =
  if journal == nil:
    return
  journal.writeLine($(%*{
    "event_type": "input_mask", "frame_tick": bot.frameTick,
    "player_id": bot.ownPlayerId, "mask": mask,
    "mission_origin": bot.mission.originId,
    "mission_target": bot.mission.targetId
  }))
  journal.flushFile()

proc runBot(
  address = DefaultHost,
  port = DefaultPort,
  url = "",
  name = "kudzu",
  token = "",
  slot = -1,
  maxSteps = 0,
  exitOnDisconnect = false,
  useJev = false,
  model = "jev-latest",
  journalPath = ""
) =
  ## Connects Kudzu to Planet Wars and runs the mission loop.
  let apiKey = if useJev: getEnv("TYPESAFE_API_KEY") else: ""
  if useJev and apiKey.len == 0:
    raise newException(ValueError, "TYPESAFE_API_KEY is required for typed missions")
  var journal: File
  if journalPath.len > 0:
    let descriptor = posix.open(journalPath.cstring, O_WRONLY or O_CREAT or O_EXCL, 0o600.Mode)
    if descriptor < 0 or not journal.open(FileHandle(descriptor), fmWrite):
      raise newException(IOError, "Could not create private mission journal")
  defer:
    if journal != nil:
      journal.close()
  let endpoint = connectUrl(address, url, name, token, port, slot)
  var connected = false
  while true:
    try:
      echo "kudzu connecting to ", endpoint
      var bot = initBot()
      let ws = newWebSocket(endpoint)
      connected = true
      var lastMask = 0xff'u8
      while true:
        if not ws.receiveUpdates(bot):
          continue
        let mask = bot.decideNextMask()
        if useJev and bot.pendingChoices.len > 1:
          if lastMask != 0:
            ws.send(playerInputBlob(0), BinaryMessage)
            lastMask = 0
            journal.recordInput(bot, 0)
          var planets = newJArray()
          for planet in bot.knownPlanetSights():
            planets.add(%*{
              "id": planet.id, "owner_id": planet.ownerId,
              "estimated_ships": planet.ships, "last_seen_tick": planet.seenTick,
              "x": planet.x, "y": planet.y, "size": planet.sizeOrd
            })
          let state = %*{
            "game": "Planet Wars", "frame_tick": bot.frameTick,
            "own_player_id": bot.ownPlayerId, "known_planets": planets
          }
          let reply = chooseMission(
            state, bot.pendingChoices, model,
            getEnv("TYPESAFE_BASE_URL", "https://api.typesafe.ai") & "/v1/systemone", apiKey
          )
          let selected = bot.pendingChoices[reply.index]
          bot.mission = Mission(
            phase: PhaseGoOrigin, originId: selected.originId,
            targetId: selected.targetId, budget: selected.budget,
            startedTick: bot.frameTick
          )
          bot.intent = "model mission " & $selected.originId & "->" &
            $selected.targetId & " budget " & $selected.budget
          if journal != nil:
            journal.writeLine($(%*{
              "event_type": "mission_choice", "frame_tick": bot.frameTick,
              "player_id": bot.ownPlayerId, "name": name, "model": model,
              "request": reply.request, "response": reply.response,
              "selected": {"origin_id": selected.originId,
                           "target_id": selected.targetId, "budget": selected.budget}
            }))
            journal.flushFile()
          bot.pendingChoices.setLen(0)
          continue
        bot.pendingChoices.setLen(0)
        bot.echoDebug(mask, mask != lastMask)
        if mask != lastMask:
          ws.send(playerInputBlob(mask), BinaryMessage)
          lastMask = mask
          journal.recordInput(bot, mask)
        if maxSteps > 0 and bot.frameTick >= maxSteps:
          bot.echoDebug(mask, true)
          ws.close()
          return
    except CatchableError as e:
      if exitOnDisconnect and connected:
        echo "kudzu exiting after disconnect: ", e.msg
        return
      echo "kudzu reconnecting after error: ", e.msg
      sleep(250)

when isMainModule:
  var
    address = DefaultHost
    port = DefaultPort
    url = getEnv("COGAMES_ENGINE_WS_URL")
    name =
      if url.len > 0:
        ""
      else:
        "kudzu"
    token = ""
    slot = -1
    maxSteps = 0
    exitOnDisconnect = url.len > 0
    useJev = false
    model = "jev-latest"
    journalPath = ""

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
      of "exit-on-disconnect":
        exitOnDisconnect = true
      of "systemone":
        useJev = true
      of "model":
        model = value
      of "journal":
        journalPath = value
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
    exitOnDisconnect,
    useJev,
    model,
    journalPath
  )
