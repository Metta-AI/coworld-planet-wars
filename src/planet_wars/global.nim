import
  std/algorithm, std/tables,
  bitworld/pixelfonts, bitworld/profile,
  bitworld/spriteprotocol, bitworld/sprites, sim

const
  NeutralPlanetSpriteBase = 100
  PlanetSelectedSpriteBase = 120
  PlanetOriginSpriteBase = 130
  PlayerPlanetSpriteBase = 1000
  PlayerShipSpriteBase = 2000
  PlayerCursorSpriteBase = 5000
  PlanetTextDigitSpriteBase = 10000
  HudSpriteId = 18000
  WaitingSpriteId = 18002
  InterstitialSpriteId = 18003
  ChatSpriteBase = 18010
  PlayerNameSpriteBase = 18100
  ScorePanelDigitSpriteBase = 18300
  ScorePanelChipSpriteBase = 18400
  ScorePanelNameSpriteBase = 18500
  HudLabelSpriteBase = 18700
  PlanetObjectBase = 2000
  PlanetSelectedObjectBase = 2100
  PlanetOriginObjectBase = 2200
  PlanetTextObjectBase = 2300
  ShipObjectBase = 3000
  CursorObjectBase = 12000
  PlayerNameObjectBase = 13000
  CursorZBase = WorldHeightPixels * 2
  PlanetTextZBase = WorldHeightPixels * 3
  PlayerNameZBase = WorldHeightPixels * 4
  ChatBubbleZBase = WorldHeightPixels * 5
  HudLabelObjectBase = 4700
  HudDigitObjectBase = 4710
  HudMaxValueChars = 12
  HudLabelGapX = 3
  HudLabels = ["SCORE", "PLANETS"]
  WaitingObjectId = 4002
  InterstitialObjectId = 4003
  ChatObjectBase = 4010
  ScorePanelChipObjectBase = 14000
  ScorePanelDigitObjectBase = 15000
  ScorePanelNameObjectBase = 17000
  PlanetSpritePad = 4
  ## Planet Wars input tags, outside bitworld's 0x81..0x87 range.
  PlanetWarsClick* = 0xA0'u8
  PlanetWarsPercent* = 0xA1'u8
  PlanetWarsHover* = 0xA2'u8
  ## Ships are drawn at this multiple of the base shape, and each plotted
  ## point becomes a block of the same size so the hull stays solid
  ## instead of breaking into scattered pixels.
  ShipSpriteScale = 3
  ShipSpriteSize = 7 * ShipSpriteScale
  ## Sprites covering the 256 headings. Sixteen reads as smooth turning
  ## while staying far inside the id space before the cursor sprites.
  ShipDirectionCount = 16
  CursorSpriteSize = 5
  ChatBubblePad = 3
  ChatBubblePointerHeight = 3
  ChatBubbleGapY = 4
  ChatBubbleMaxTextWidth = 96
  PlayerNameGapY = 4
  PlayerNameMaxTextWidth = 96
  TextOutlinePad = 1
  HudY = 0
  PlayerUiHeight = 48
  ScorePanelChipSize = 3
  ScorePanelChipGapX = 2
  ScorePanelNameGapX = 2
  ScorePanelMaxScoreChars = 16
  PlanetTextMaxChars = 8
  ReplayCenterBottomLayerId = 4
  ReplayBottomLeftLayerId = 5
  ReplayMismatchLayerId = 6
  ReplayCenterBottomLayerKind = 8
  ReplayBottomLeftLayerKind = 4
  ReplayMismatchLayerKind = 5
  ReplayPanelHeight = 20
  ReplayScrubberWidth = 240
  ReplayScrubberHeight = 5
  ReplayScrubberTrackY = 2
  ReplayScrubberY = 8
  TransportX = 2
  TransportY = 1
  TransportButtonWidth = 12
  TransportButtonStride = 14
  TransportButtonCount = 4
  TransportRowHeight = 7
  TransportSpeedY = 8
  TransportSpeedStride = 18
  TransportSpeedWidth = 16
  TransportSpeedLabels = ["1X", "2X", "3X", "4X", "8X", "16X"]
  TransportSpeedValues = [1, 2, 3, 4, 8, 16]
  TransportSpeedCommands = ['1', '2', '3', '4', '8', '6']
  TransportWidth = TransportSpeedStride * TransportSpeedLabels.len
  TransportHeight = TransportSpeedY + TransportRowHeight
  ReplayMismatchPadX = 4
  ReplayMismatchPadY = 3
  ReplayTickSpriteId = 18600
  ReplayScrubberSpriteId = 18601
  ReplayControlsSpriteId = 18602
  ReplayMismatchSpriteId = 18603
  ReplayTickObjectId = 4600
  ReplayScrubberObjectId = 4601
  ReplayControlsObjectId = 4602
  ReplayMismatchObjectId = 4603

type
  WorldSpriteObject = object
    id: int
    x: int
    y: int
    z: int
    layer: int
    spriteId: int

  PlayerSpriteKey = object
    playerId: int
    color: RgbaColor

  PlayerTextSpriteKey = object
    playerId: int
    text: string
    color: RgbaColor

  GlobalViewerState* = object
    initialized*: bool
    objectIds*: seq[int]
    worldObjects*: Table[int, WorldSpriteObject]
    playerSpriteKeys: seq[PlayerSpriteKey]
    playerNameKeys: seq[PlayerTextSpriteKey]
    planetTextDigitsDefined: bool
    mouseX*: int
    mouseY*: int
    mouseLayer*: int
    mouseDown*: bool
    clickPending*: bool
    mousePressX*: int
    mousePressY*: int
    mousePressLayer*: int
    scrubbingReplay*: bool
    replaySeekTick*: int
    replayCommands*: seq[char]
    replayTickKey: string
    replayControlsKey: string
    replayMismatchKey: string
    interstitialKey: string
    selectedPlanetId*: int
    scorePanelDigitsDefined: bool
    scorePanelPlayerKeys: seq[PlayerTextSpriteKey]

  PlayerViewerState* = object
    initialized*: bool
    objectIds*: seq[int]
    worldObjects*: Table[int, WorldSpriteObject]
    playerSpriteKeys: seq[PlayerSpriteKey]
    playerNameKeys: seq[PlayerTextSpriteKey]
    planetTextDigitsDefined: bool
    waitingSpriteDefined: bool
    hudLabelsDefined: bool
    interstitialKey: string
    ## Mouse input, accumulated between ticks and drained by the sim.
    pointerX*: int
    pointerY*: int
    hasPointer*: bool
    sendPercent*: int
    pendingCount*: int
    pending*: array[4, PlayerCommand]

proc initGlobalViewerState*(): GlobalViewerState =
  ## Returns the default state for one global protocol viewer.
  result.mouseLayer = MapLayerId
  result.selectedPlanetId = -1
  result.replaySeekTick = -1

proc initPlayerViewerState*(): PlayerViewerState =
  ## Returns the default state for one sprite player viewer.
  discard

proc objectVisible(
  x,
  y,
  width,
  height,
  viewportWidth,
  viewportHeight: int
): bool =
  ## Returns true when an object intersects the current viewport.
  if width <= 0 or height <= 0:
    return false
  x < viewportWidth and
    y < viewportHeight and
    x + width > 0 and
    y + height > 0

proc addWorldObject(
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  objectId,
  x,
  y,
  z,
  spriteId,
  spriteWidth,
  spriteHeight,
  viewportWidth,
  viewportHeight: int
) =
  ## Queues one visible world object.
  if not objectVisible(
    x,
    y,
    spriteWidth,
    spriteHeight,
    viewportWidth,
    viewportHeight
  ):
    return
  currentIds.add(objectId)
  objects.add(WorldSpriteObject(
    id: objectId,
    x: x,
    y: y,
    z: z,
    layer: MapLayerId,
    spriteId: spriteId
  ))

proc flushWorldObjects(
  packet: var seq[uint8],
  objects: var seq[WorldSpriteObject],
  previous: Table[int, WorldSpriteObject],
  next: var Table[int, WorldSpriteObject]
) {.measure.} =
  ## Sends world objects that changed since the viewer's last packet.
  ##
  ## Real depth goes on the wire rather than the post-sort index, because an
  ## index shifts whenever any other object appears or leaves, which would
  ## make almost every object look changed. Both clients sort by (z, y, id)
  ## themselves, so the draw order is identical either way.
  objects.sort(
    proc(a, b: WorldSpriteObject): int =
      result = cmp(a.z, b.z)
      if result == 0:
        result = cmp(a.y, b.y)
      if result == 0:
        result = cmp(a.id, b.id)
  )
  for item in objects:
    next[item.id] = item
    let seen = previous.getOrDefault(item.id, WorldSpriteObject(id: -1))
    if seen == item:
      continue
    packet.addObject(
      item.id, item.x, item.y, item.z, item.layer, item.spriteId
    )

proc planetSpriteRadius(size: PlanetSize): int =
  ## Returns the rendered sprite radius for one planet size.
  planetRadius(size) + PlanetSpritePad

proc neutralPlanetSpriteId(size: PlanetSize): int =
  ## Returns the sprite id for one neutral planet sprite.
  NeutralPlanetSpriteBase + ord(size)

proc playerPlanetSpriteId(playerId: int, size: PlanetSize): int =
  ## Returns the sprite id for one player-owned planet sprite.
  PlayerPlanetSpriteBase + playerId * 8 + ord(size)

proc planetSelectedSpriteId(size: PlanetSize): int =
  ## Returns the sprite id for one selected planet ring.
  PlanetSelectedSpriteBase + ord(size)

proc planetOriginSpriteId(size: PlanetSize): int =
  ## Returns the sprite id for one origin planet ring.
  PlanetOriginSpriteBase + ord(size)

proc playerShipSpriteId(playerId, direction: int): int =
  ## Returns the sprite id for one player's ship and direction.
  PlayerShipSpriteBase + playerId * ShipDirectionCount + direction

proc playerCursorSpriteId(playerId: int): int =
  ## Returns the sprite id for one player's cursor.
  PlayerCursorSpriteBase + playerId

proc playerNameSpriteId(playerId: int): int =
  ## Returns the sprite id for one player's name label.
  PlayerNameSpriteBase + playerId

proc planetTextDigitSpriteId(ch: char): int =
  ## Returns the sprite id for one outlined planet digit.
  PlanetTextDigitSpriteBase + ord(ch) - ord('0')

proc planetTextDigitObjectId(planetId, digitIndex: int): int =
  ## Returns the object id for one planet ship-count digit.
  PlanetTextObjectBase + planetId * PlanetTextMaxChars + digitIndex

proc shipDirection(ship: Ship): int =
  ## Returns the sprite direction for one moving ship. Ships steer, so
  ## this follows the live heading rather than the line it set out on.
  ## Each sprite claims an equal slice of the 256 headings, centred on
  ## its own orientation.
  let half = HeadingCount div (ShipDirectionCount * 2)
  ((int(ship.heading) + half) and (HeadingCount - 1)) div
    (HeadingCount div ShipDirectionCount)

proc buildPlanetSprite(size: PlanetSize, color: RgbaColor): RgbaSprite =
  ## Builds one planet base sprite.
  let
    radius = planetRadius(size)
    spriteRadius = planetSpriteRadius(size)
    center = spriteRadius
    dim = spriteRadius * 2 + 1
    border = color.scaleColor(42)
    shade = color.scaleColor(72)
    highlight = color.mixColor(ScoreColor, 42)
  result = newRgbaSprite(dim, dim)
  result.drawCircleFill(center, center, radius + 1, color)
  result.drawCircleRing(center, center, radius + 1, 1, border)
  result.drawCircleRing(center, center, max(1, radius - 2), 1, shade)
  result.putRgbaPixel(center - radius div 2, center - radius div 2, highlight)

proc buildPlanetRingSprite(size: PlanetSize, color: RgbaColor): RgbaSprite =
  ## Builds one planet ring overlay sprite.
  let
    spriteRadius = planetSpriteRadius(size)
    center = spriteRadius
    dim = spriteRadius * 2 + 1
  result = newRgbaSprite(dim, dim)
  result.drawCircleRing(center, center, spriteRadius - 1, 1, color)

proc buildShipSprite(color: RgbaColor, direction: int): RgbaSprite =
  ## Builds one directional ship sprite: a bright nose, a body behind it,
  ## and a pair of stubby wings. The shape is derived from the heading so
  ## all sixteen orientations come from one piece of code.
  result = newRgbaSprite(ShipSpriteSize, ShipSpriteSize)
  let
    centre = ShipSpriteSize div 2
    heading = uint8((direction * HeadingCount) div ShipDirectionCount)
    forwardX = cosHeading(heading)
    forwardY = sinHeading(heading)
  proc plot(sprite: var RgbaSprite, alongScale, sideScale: int,
      pixel: RgbaColor) =
    ## Places one pixel at a position given along and across the heading.
    let
      x = centre + (forwardX * alongScale - forwardY * sideScale) *
        ShipSpriteScale div (TrigScale * 2)
      y = centre + (forwardY * alongScale + forwardX * sideScale) *
        ShipSpriteScale div (TrigScale * 2)
    for blockY in 0 ..< ShipSpriteScale:
      for blockX in 0 ..< ShipSpriteScale:
        let
          px = x + blockX
          py = y + blockY
        if px >= 0 and py >= 0 and px < ShipSpriteSize and
            py < ShipSpriteSize:
          sprite.putRgbaPixel(px, py, pixel)
  result.plot(0, 0, color)
  result.plot(-2, 0, color)
  result.plot(-4, 2, color)
  result.plot(-4, -2, color)
  result.plot(4, 0, ScoreColor)

proc buildCursorSprite(color: RgbaColor): RgbaSprite =
  ## Builds a 5 by 5 cross cursor with a transparent center.
  result = newRgbaSprite(CursorSpriteSize, CursorSpriteSize)
  let center = CursorSpriteSize div 2
  for i in 0 ..< CursorSpriteSize:
    if i == center:
      continue
    result.putRgbaPixel(i, center, color)
    result.putRgbaPixel(center, i, color)

proc buildBackgroundSprite(sim: SimServer): RgbaSprite {.measure.} =
  ## Builds the starfield background sprite.
  result = newRgbaSprite(WorldWidthPixels, WorldHeightPixels)
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      result.putRgbaPixel(x, y, BackgroundColor)
  for star in sim.stars:
    result.putRgbaPixel(star.x, star.y, star.color)

proc blitGlyph(
  sprite: var RgbaSprite,
  glyph: PixelGlyph,
  baseX,
  baseY: int,
  color: RgbaColor
) =
  ## Blits a single-color Tiny5 glyph into a sprite.
  for y in 0 ..< glyph.height:
    for x in 0 ..< glyph.width:
      if glyph.glyphPixel(x, y):
        sprite.putRgbaPixel(baseX + x, baseY + y, color)

proc blitGlyphOutline(
  sprite: var RgbaSprite,
  glyph: PixelGlyph,
  baseX,
  baseY: int
) =
  ## Blits the black outline around one Tiny5 glyph.
  for y in 0 ..< glyph.height:
    for x in 0 ..< glyph.width:
      if not glyph.glyphPixel(x, y):
        continue
      for oy in -1 .. 1:
        for ox in -1 .. 1:
          if ox == 0 and oy == 0:
            continue
          sprite.putRgbaPixel(
            baseX + x + ox,
            baseY + y + oy,
            BlackColor
          )

proc buildTextSprite(
  sim: SimServer,
  lines: openArray[string],
  color: RgbaColor,
  outlined = false
): RgbaSprite {.measure.} =
  ## Builds a compact Tiny5 protocol text sprite.
  let
    lineHeight = sim.textFont.lineHeight()
    pad = if outlined: TextOutlinePad else: 0
  var width = 1
  for line in lines:
    width = max(width, sim.textFont.textWidth(line))
  result = newRgbaSprite(
    width + pad * 2,
    max(1, lines.len * lineHeight - sim.textFont.spacing) + pad * 2
  )
  for lineIndex, line in lines:
    let baseY = pad + lineIndex * lineHeight
    var baseX = pad
    if outlined:
      for ch in line:
        let glyph = sim.textFont.glyphAt(ch)
        result.blitGlyphOutline(glyph, baseX, baseY)
        baseX += sim.textFont.glyphAdvance(ch)
    baseX = pad
    for ch in line:
      let glyph = sim.textFont.glyphAt(ch)
      result.blitGlyph(glyph, baseX, baseY, color)
      baseX += sim.textFont.glyphAdvance(ch)

proc textSliceForWidth(
  font: PixelFont,
  text: string,
  maxWidth: int
): string =
  ## Returns the longest text prefix that fits a pixel width.
  var width = 0
  for ch in text:
    let advance = font.glyphAdvance(ch)
    if result.len > 0 and width + advance > maxWidth:
      return
    if result.len == 0 and advance > maxWidth:
      return
    result.add(ch)
    width += advance

proc buildChatBubbleSprite(
  sim: SimServer,
  text: string,
  alpha: uint8
): RgbaSprite {.measure.} =
  ## Builds one Tiny5 chat bubble sprite.
  let
    line = sim.textFont.textSliceForWidth(text, ChatBubbleMaxTextWidth)
    textWidth = max(6, sim.textFont.textWidth(line))
    bodyWidth = textWidth + ChatBubblePad * 2
    bodyHeight = sim.textFont.height + ChatBubblePad * 2
    pointerX = bodyWidth div 2
    fillAlpha = uint8(int(alpha) * 190 div 255)
    fillColor = BlackColor.withAlpha(fillAlpha)
    lineColor = BlackColor.withAlpha(alpha)
    textColor = ScoreColor.withAlpha(alpha)
  result = newRgbaSprite(
    bodyWidth,
    bodyHeight + ChatBubblePointerHeight
  )
  result.fillRect(0, 0, bodyWidth, bodyHeight, fillColor)
  result.strokeRect(0, 0, bodyWidth, bodyHeight, lineColor)
  for y in 0 ..< ChatBubblePointerHeight:
    let span = ChatBubblePointerHeight - y - 1
    for x in pointerX - span .. pointerX + span:
      result.putRgbaPixel(x, bodyHeight + y, lineColor)
  var baseX = ChatBubblePad
  for ch in line:
    let glyph = sim.textFont.glyphAt(ch)
    result.blitGlyph(
      glyph,
      baseX,
      ChatBubblePad,
      textColor
    )
    baseX += sim.textFont.glyphAdvance(ch)

proc playerNameText(sim: SimServer, player: Player): string =
  ## Returns one bounded player name label.
  let text =
    if player.name.len > 0:
      player.name
    else:
      "player " & $player.id
  result = sim.textFont.textSliceForWidth(text, PlayerNameMaxTextWidth)
  if result.len == 0:
    result = $player.id

proc buildPlayerNameSprite(
  sim: SimServer,
  player: Player
): RgbaSprite {.measure.} =
  ## Builds one outlined Tiny5 player name label.
  sim.buildTextSprite([sim.playerNameText(player)], player.color, true)

proc playerNameSpriteWidth(sim: SimServer, text: string): int =
  ## Returns the outlined player name sprite width.
  sim.textFont.textWidth(text) + TextOutlinePad * 2

proc playerNameSpriteHeight(sim: SimServer): int =
  ## Returns the outlined player name sprite height.
  sim.textFont.height + TextOutlinePad * 2

proc playerSpriteKey(player: Player): PlayerSpriteKey =
  ## Returns the semantic key for one player's color sprites.
  PlayerSpriteKey(playerId: player.id, color: player.color)

proc playerTextSpriteKey(
  player: Player,
  text: string
): PlayerTextSpriteKey =
  ## Returns the semantic key for one colored player text sprite.
  PlayerTextSpriteKey(
    playerId: player.id,
    text: text,
    color: player.color
  )

proc hasPlayerSpriteKey(
  keys: openArray[PlayerSpriteKey],
  key: PlayerSpriteKey
): bool =
  ## Returns true when one player color sprite key is cached.
  for existing in keys:
    if existing == key:
      return true

proc rememberPlayerSpriteKey(
  keys: var seq[PlayerSpriteKey],
  key: PlayerSpriteKey
) =
  ## Stores the current player color sprite key.
  for i in countdown(keys.high, 0):
    if keys[i].playerId == key.playerId:
      keys.delete(i)
  keys.add(key)

proc hasPlayerTextSpriteKey(
  keys: openArray[PlayerTextSpriteKey],
  key: PlayerTextSpriteKey
): bool =
  ## Returns true when one player text sprite key is cached.
  for existing in keys:
    if existing == key:
      return true

proc rememberPlayerTextSpriteKey(
  keys: var seq[PlayerTextSpriteKey],
  key: PlayerTextSpriteKey
) =
  ## Stores the current player text sprite key.
  for i in countdown(keys.high, 0):
    if keys[i].playerId == key.playerId:
      keys.delete(i)
  keys.add(key)

proc compareScorePanelPlayers(a, b: Player): int =
  ## Sorts score panel players by descending score.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(a.id, b.id)

proc scorePanelScoreText(score: int): string =
  ## Returns the bounded score text used by score panel objects.
  result = $score
  if result.len > ScorePanelMaxScoreChars:
    result = result[result.len - ScorePanelMaxScoreChars .. result.high]

proc scorePanelScoreWidth(sim: SimServer, players: openArray[Player]): int =
  ## Returns the widest current score label.
  for player in players:
    result = max(result, sim.textFont.textWidth(
      scorePanelScoreText(player.score)
    ))

proc scorePanelNameText(
  sim: SimServer,
  player: Player,
  maxWidth: int
): string =
  ## Returns the bounded score panel player name.
  result = sim.textFont.textSliceForWidth(
    sim.playerNameText(player),
    max(1, maxWidth)
  )
  if result.len == 0:
    result = $player.id

proc scorePanelDigitSpriteId(ch: char): int =
  ## Returns the sprite id for one score panel digit.
  ScorePanelDigitSpriteBase + ord(ch) - ord('0')

proc scorePanelChipSpriteId(playerId: int): int =
  ## Returns the score panel chip sprite id for one player.
  ScorePanelChipSpriteBase + playerId

proc scorePanelNameSpriteId(playerId: int): int =
  ## Returns the score panel name sprite id for one player.
  ScorePanelNameSpriteBase + playerId

proc scorePanelChipObjectId(playerId: int): int =
  ## Returns the score panel chip object id for one player.
  ScorePanelChipObjectBase + playerId

proc scorePanelDigitObjectId(playerId, digitIndex: int): int =
  ## Returns the score panel digit object id for one player digit.
  ScorePanelDigitObjectBase +
    playerId * ScorePanelMaxScoreChars + digitIndex

proc scorePanelNameObjectId(playerId: int): int =
  ## Returns the score panel name object id for one player.
  ScorePanelNameObjectBase + playerId

proc buildScorePanelChipSprite(color: RgbaColor): RgbaSprite =
  ## Builds one solid score panel color chip.
  result = newRgbaSprite(ScorePanelChipSize, ScorePanelChipSize)
  result.fillRect(
    0,
    0,
    ScorePanelChipSize,
    ScorePanelChipSize,
    color
  )

proc planetShipsText(ships: int): string =
  ## Returns the bounded planet ship-count text.
  result = $ships
  if result.len > PlanetTextMaxChars:
    result = result[result.len - PlanetTextMaxChars .. result.high]

proc planetTextSpriteWidth(sim: SimServer, text: string): int =
  ## Returns the outlined planet number sprite width.
  sim.textFont.textWidth(text) + TextOutlinePad * 2

proc planetTextSpriteHeight(sim: SimServer): int =
  ## Returns the outlined planet number sprite height.
  sim.textFont.height + TextOutlinePad * 2

proc addPlanetTextDigitSprites(
  sim: SimServer,
  packet: var seq[uint8]
) {.measure.} =
  ## Adds immutable outlined planet digit sprite definitions.
  for ch in '0' .. '9':
    let digit = sim.buildTextSprite([$ch], ScoreColor, true)
    packet.addSprite(
      planetTextDigitSpriteId(ch),
      digit.width,
      digit.height,
      digit.pixels,
      "planet digit " & $ch
    )

proc addScorePanelDigitSprites(
  sim: SimServer,
  packet: var seq[uint8]
) {.measure.} =
  ## Adds stable score panel digit sprite definitions.
  for ch in '0' .. '9':
    let digit = sim.buildTextSprite([$ch], ScoreColor, false)
    packet.addSprite(
      scorePanelDigitSpriteId(ch),
      digit.width,
      digit.height,
      digit.pixels,
      "score digit " & $ch
    )

proc addScorePanelPlayerSprites(
  sim: SimServer,
  packet: var seq[uint8],
  keys: var seq[PlayerTextSpriteKey],
  player: Player,
  name: string
) {.measure.} =
  ## Adds score panel player sprites only when their pixels change.
  let key = player.playerTextSpriteKey(name)
  if keys.hasPlayerTextSpriteKey(key):
    return
  let
    chip = buildScorePanelChipSprite(player.color)
    label = sim.buildTextSprite([name], player.color, false)
  packet.addSprite(
    scorePanelChipSpriteId(player.id),
    chip.width,
    chip.height,
    chip.pixels,
    "score chip " & $player.id
  )
  packet.addSprite(
    scorePanelNameSpriteId(player.id),
    label.width,
    label.height,
    label.pixels,
    "score name " & name
  )
  keys.rememberPlayerTextSpriteKey(key)

proc applyGlobalViewerMessage*(
  state: var GlobalViewerState,
  message: string,
  replayControls = false
) =
  ## Applies one or more global protocol client messages.
  for item in message.parseSpriteClientMessages():
    case item.kind
    of SpriteClientMouseMoveMessage:
      state.mouseX = item.x
      state.mouseY = item.y
      state.mouseLayer =
        if item.hasLayer:
          item.layer
        else:
          MapLayerId
    of SpriteClientMouseButtonMessage:
      if item.button == 0x01'u8:
        state.mouseDown = item.down
        if state.mouseDown:
          state.clickPending = true
          state.mousePressX = state.mouseX
          state.mousePressY = state.mouseY
          state.mousePressLayer = state.mouseLayer
        else:
          state.scrubbingReplay = false
    of SpriteClientChatMessage:
      if replayControls:
        for ch in item.text:
          state.replayCommands.add(ch)
    of SpriteClientInputMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage:
      discard

proc replayCommandAt(layer, x, y: int): char =
  ## Returns the replay transport command under a UI coordinate.
  if layer != ReplayBottomLeftLayerId:
    return '\0'
  let
    localX = x - TransportX
    localY = y - TransportY
  if localX < 0:
    return '\0'
  if localY >= 0 and localY < TransportRowHeight:
    let index = localX div TransportButtonStride
    if index < 0 or index >= TransportButtonCount:
      return '\0'
    if localX - index * TransportButtonStride >= TransportButtonWidth:
      return '\0'
    case index
    of 0: return '<'
    of 1: return ' '
    of 2: return 'e'
    else: return 'r'
  if localY >= TransportSpeedY and localY < TransportSpeedY +
      TransportRowHeight:
    let index = localX div TransportSpeedStride
    if index < 0 or index >= TransportSpeedCommands.len:
      return '\0'
    if localX - index * TransportSpeedStride >= TransportSpeedWidth:
      return '\0'
    return TransportSpeedCommands[index]
  '\0'

proc replayScrubTickAt(
  layer, x, y, maxTick: int,
  requireInside = true
): int =
  ## Returns the replay tick under the scrubber pointer.
  if layer != ReplayCenterBottomLayerId or maxTick < 0:
    return -1
  let
    scrubberX = max(0, (WorldWidthPixels - ReplayScrubberWidth) div 2)
    localX = x - scrubberX
    localY = y - ReplayScrubberY
  if requireInside and (
      localX < 0 or localX >= ReplayScrubberWidth or
      localY < 0 or localY >= ReplayScrubberHeight
    ):
    return -1
  if ReplayScrubberWidth <= 1:
    return 0
  let clampedX = clamp(localX, 0, ReplayScrubberWidth - 1)
  clamp((clampedX * maxTick) div (ReplayScrubberWidth - 1), 0, maxTick)

proc drainReplayViewerInput*(
  state: var GlobalViewerState,
  maxTick: int,
  seekTicks: var seq[int],
  commands: var seq[char]
) =
  ## Collects pending replay seeks and transport commands from one viewer.
  state.replaySeekTick = -1
  if state.clickPending:
    state.clickPending = false
    let seekTick = replayScrubTickAt(
      state.mousePressLayer,
      state.mousePressX,
      state.mousePressY,
      maxTick
    )
    if seekTick >= 0:
      state.scrubbingReplay = true
      state.replaySeekTick = seekTick
    else:
      let command = replayCommandAt(
        state.mousePressLayer,
        state.mousePressX,
        state.mousePressY
      )
      if command != '\0':
        state.replayCommands.add(command)
  if state.mouseDown and state.scrubbingReplay:
    let seekTick = replayScrubTickAt(
      state.mouseLayer,
      state.mouseX,
      state.mouseY,
      maxTick,
      requireInside = false
    )
    if seekTick >= 0:
      state.replaySeekTick = seekTick
  if state.replaySeekTick >= 0:
    seekTicks.add(state.replaySeekTick)
  state.replaySeekTick = -1
  for command in state.replayCommands:
    commands.add(command)
  state.replayCommands.setLen(0)

proc readI16At(message: string, offset: int): int =
  ## Reads one little endian signed 16 bit value.
  let value = uint16(message[offset].uint8) or
    (uint16(message[offset + 1].uint8) shl 8)
  int(cast[int16](value))

proc initPlayerSendPercent*(state: var PlayerViewerState) =
  ## Seeds the send size so a player who never presses a number key still
  ## sends the documented default.
  if state.sendPercent == 0:
    state.sendPercent = DefaultSendPercent

proc applyPlanetWarsInput*(
  state: var PlayerViewerState,
  message: string
): bool =
  ## Parses the Planet Wars input protocol, which is deliberately separate
  ## from bitworld's button and mouse messages so the game can carry
  ## modifiers, a send percentage and select-all without changing the
  ## shared protocol. Returns true when the message was ours.
  if message.len == 0:
    return false
  state.initPlayerSendPercent()
  case message[0].uint8
  of PlanetWarsClick:
    if message.len < 6:
      return true
    if state.pendingCount < state.pending.len:
      let action = message[5].uint8
      state.pending[state.pendingCount] = PlayerCommand(
        kind:
          case action
          of 0'u8: CommandClick
          of 1'u8: CommandShiftClick
          of 2'u8: CommandSelectAll
          else: CommandNone,
        x: message.readI16At(1),
        y: message.readI16At(3)
      )
      inc state.pendingCount
    true
  of PlanetWarsPercent:
    if message.len >= 2:
      state.sendPercent = clamp(int(message[1].uint8), 10, 100)
    true
  of PlanetWarsHover:
    if message.len >= 5:
      state.pointerX = message.readI16At(1)
      state.pointerY = message.readI16At(3)
      state.hasPointer = true
    true
  else:
    false

proc takePlayerInput*(state: var PlayerViewerState): PlayerInput =
  ## Drains accumulated mouse input into one tick of simulation input.
  result.hasCursor = state.hasPointer
  result.cursorX = state.pointerX
  result.cursorY = state.pointerY
  result.sendPercent = state.sendPercent
  result.commandCount = state.pendingCount
  for i in 0 ..< state.pendingCount:
    result.commands[i] = state.pending[i]
  state.pendingCount = 0

proc applyPlayerViewerMessage*(
  state: var PlayerViewerState,
  message: string,
  inputMask: var uint8,
  chatText: var string
) =
  ## Applies sprite-player input messages.
  if state.applyPlanetWarsInput(message):
    return
  for item in message.parseSpriteClientMessages():
    case item.kind
    of SpriteClientChatMessage:
      chatText.add(item.text)
    of SpriteClientInputMessage:
      inputMask = item.mask
    of SpriteClientMouseMoveMessage, SpriteClientMouseButtonMessage,
        SpriteClientReadyMessage, SpriteClientDebugSpriteMessage:
      discard

proc selectPlanetAt(sim: SimServer, worldX, worldY: int): int =
  ## Returns the clicked planet id, or minus one.
  var
    bestId = -1
    bestDistance = high(int)
  for planet in sim.planets:
    let
      dx = planet.x - worldX
      dy = planet.y - worldY
      distance = dx * dx + dy * dy
      radius = planet.radius + PlanetSpritePad
    if distance <= radius * radius and distance < bestDistance:
      bestId = planet.id
      bestDistance = distance
  bestId

proc addCommonSpriteDefinitions(packet: var seq[uint8], sim: SimServer) =
  ## Adds sprite definitions shared by global and player views.
  let background = sim.buildBackgroundSprite()
  packet.addSprite(
    MapSpriteId,
    background.width,
    background.height,
    background.pixels,
    "starfield"
  )
  for size in PlanetSize:
    let planet = buildPlanetSprite(size, NeutralPlanetColor)
    packet.addSprite(
      neutralPlanetSpriteId(size),
      planet.width,
      planet.height,
      planet.pixels,
      "neutral planet"
    )
    let
      selected = buildPlanetRingSprite(size, SelectionColor)
      origin = buildPlanetRingSprite(size, OriginColor)
    packet.addSprite(
      planetSelectedSpriteId(size),
      selected.width,
      selected.height,
      selected.pixels,
      "selected planet"
    )
    packet.addSprite(
      planetOriginSpriteId(size),
      origin.width,
      origin.height,
      origin.pixels,
      "origin planet"
    )
  discard sim

proc addPlayerSpriteDefinitions(
  packet: var seq[uint8],
  keys: var seq[PlayerSpriteKey],
  sim: SimServer
) {.measure.} =
  ## Adds dynamic full-color sprite definitions for all players.
  for player in sim.players:
    let key = player.playerSpriteKey()
    if keys.hasPlayerSpriteKey(key):
      continue
    for size in PlanetSize:
      let planet = buildPlanetSprite(size, player.color)
      packet.addSprite(
        playerPlanetSpriteId(player.id, size),
        planet.width,
        planet.height,
        planet.pixels,
        "player planet"
      )
    for direction in 0 ..< ShipDirectionCount:
      let ship = buildShipSprite(player.color, direction)
      packet.addSprite(
        playerShipSpriteId(player.id, direction),
        ship.width,
        ship.height,
        ship.pixels,
        "player ship"
      )
    let cursor = buildCursorSprite(player.color)
    packet.addSprite(
      playerCursorSpriteId(player.id),
      cursor.width,
      cursor.height,
      cursor.pixels,
      "player cursor"
    )
    keys.rememberPlayerSpriteKey(key)

proc buildSpriteProtocolInit(sim: SimServer): seq[uint8] {.measure.} =
  ## Builds the initial global viewer snapshot.
  result = @[]
  result.addClearObjects()
  result.addLayer(MapLayerId, MapLayerType, ZoomableLayerFlag)
  result.addViewport(MapLayerId, WorldWidthPixels, WorldHeightPixels)
  result.addLayer(TopLeftLayerId, TopLeftLayerType, UiLayerFlag)
  result.addViewport(TopLeftLayerId, ScreenWidth, ScreenHeight)
  result.addCommonSpriteDefinitions(sim)

proc buildSpriteProtocolPlayerInit(sim: SimServer): seq[uint8] {.measure.} =
  ## Builds the initial sprite player snapshot.
  result = @[]
  result.addClearObjects()
  result.addLayer(MapLayerId, MapLayerType, ZoomableLayerFlag)
  result.addViewport(MapLayerId, WorldWidthPixels, WorldHeightPixels)
  result.addLayer(TopLeftLayerId, TopLeftLayerType, UiLayerFlag)
  result.addViewport(TopLeftLayerId, PlayerViewportWidth, PlayerUiHeight)
  result.addCommonSpriteDefinitions(sim)

proc addPlanetObjects(
  sim: SimServer,
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  viewerId,
  selectedIndex,
  originIndex,
  selectedPlanetId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds planet base, ring, and ship-count objects.
  for i, planet in sim.planets:
    let
      spriteRadius = planetSpriteRadius(planet.size)
      width = spriteRadius * 2 + 1
      sx = planet.x - spriteRadius - cameraX
      sy = planet.y - spriteRadius - cameraY
      spriteId =
        if planet.ownerId == 0:
          neutralPlanetSpriteId(planet.size)
        else:
          playerPlanetSpriteId(planet.ownerId, planet.size)
    objects.addWorldObject(
      currentIds,
      PlanetObjectBase + planet.id,
      sx,
      sy,
      planet.y,
      spriteId,
      width,
      width,
      viewportWidth,
      viewportHeight
    )
    if i == originIndex:
      objects.addWorldObject(
        currentIds,
        PlanetOriginObjectBase + planet.id,
        sx,
        sy,
        planet.y + 1,
        planetOriginSpriteId(planet.size),
        width,
        width,
        viewportWidth,
        viewportHeight
      )
    # Every planet held for the next send gets a ring, so a multi-planet
    # selection is visible rather than guessed at.
    var selectedForSend = planet.id == selectedPlanetId
    if not selectedForSend and viewerId > 0:
      for player in sim.players:
        if player.id == viewerId:
          selectedForSend = planet.id in player.selectedPlanetIds
          break
    if selectedForSend:
      objects.addWorldObject(
        currentIds,
        PlanetSelectedObjectBase + planet.id,
        sx,
        sy,
        planet.y + 2,
        planetSelectedSpriteId(planet.size),
        width,
        width,
        viewportWidth,
        viewportHeight
      )
    let
      text = planetShipsText(planet.ships)
      textWidth = sim.planetTextSpriteWidth(text)
      textHeight = sim.planetTextSpriteHeight()
      textX = planet.x - textWidth div 2 - cameraX
      textY = planet.y - textHeight div 2 - cameraY
    if objectVisible(
      textX,
      textY,
      textWidth,
      textHeight,
      viewportWidth,
      viewportHeight
    ):
      var digitX = textX
      for j, ch in text:
        if j >= PlanetTextMaxChars:
          break
        if ch < '0' or ch > '9':
          continue
        let digitWidth = sim.textFont.glyphAt(ch).width + TextOutlinePad * 2
        objects.addWorldObject(
          currentIds,
          planetTextDigitObjectId(planet.id, j),
          digitX,
          textY,
          PlanetTextZBase + planet.y,
          planetTextDigitSpriteId(ch),
          digitWidth,
          textHeight,
          viewportWidth,
          viewportHeight
        )
        digitX += sim.textFont.glyphAdvance(ch)
  discard viewerId

proc addShipObjects(
  sim: SimServer,
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  viewerId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds moving ship objects.
  for i, ship in sim.ships:
    let
      pos = currentShipPosition(ship)
      sx = pos.x - ShipSpriteSize div 2 - cameraX
      sy = pos.y - ShipSpriteSize div 2 - cameraY
    objects.addWorldObject(
      currentIds,
      ShipObjectBase + i,
      sx,
      sy,
      pos.y + 20,
      playerShipSpriteId(ship.ownerId, ship.shipDirection()),
      ShipSpriteSize,
      ShipSpriteSize,
      viewportWidth,
      viewportHeight
    )
  discard viewerId

proc playerMarkerVisibleTo(
  sim: SimServer,
  player: Player,
  viewerId: int
): bool =
  ## Returns true when one player's cursor stack is visible to a viewer.
  if viewerId <= 0 or player.id == viewerId:
    return true
  sim.countOwnedPlanets(player.id) > 0

proc addCursorObjects(
  sim: SimServer,
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  viewerId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds all visible player cursors.
  for player in sim.players:
    if not sim.playerMarkerVisibleTo(player, viewerId):
      continue
    let
      sx = player.cursorX - CursorSpriteSize div 2 - cameraX
      sy = player.cursorY - CursorSpriteSize div 2 - cameraY
    objects.addWorldObject(
      currentIds,
      CursorObjectBase + player.id,
      sx,
      sy,
      CursorZBase + player.cursorY,
      playerCursorSpriteId(player.id),
      CursorSpriteSize,
      CursorSpriteSize,
      viewportWidth,
      viewportHeight
    )

proc chatMessageAlpha(sim: SimServer, message: ChatMessage): uint8 =
  ## Returns the fade alpha for one chat message.
  let age = clamp(sim.tickCount - message.tick, 0, ChatBubbleTicks)
  uint8(((ChatBubbleTicks - age) * 255) div ChatBubbleTicks)

proc addPlayerNameObjects(
  sim: SimServer,
  packet: var seq[uint8],
  keys: var seq[PlayerTextSpriteKey],
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  viewerId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds name labels above all visible player cursors.
  for player in sim.players:
    if not sim.playerMarkerVisibleTo(player, viewerId):
      continue
    let
      labelText = sim.playerNameText(player)
      labelWidth = sim.playerNameSpriteWidth(labelText)
      labelHeight = sim.playerNameSpriteHeight()
      spriteId = playerNameSpriteId(player.id)
      sx = player.cursorX - labelWidth div 2 - cameraX
      sy = player.cursorY - CursorSpriteSize div 2 -
        PlayerNameGapY - labelHeight - cameraY
    if not objectVisible(
      sx,
      sy,
      labelWidth,
      labelHeight,
      viewportWidth,
      viewportHeight
    ):
      continue
    let key = player.playerTextSpriteKey(labelText)
    if not keys.hasPlayerTextSpriteKey(key):
      let label = sim.buildPlayerNameSprite(player)
      packet.addSprite(
        spriteId,
        label.width,
        label.height,
        label.pixels,
        "player name " & player.name
      )
      keys.rememberPlayerTextSpriteKey(key)
    objects.addWorldObject(
      currentIds,
      PlayerNameObjectBase + player.id,
      sx,
      sy,
      PlayerNameZBase + player.cursorY,
      spriteId,
      labelWidth,
      labelHeight,
      viewportWidth,
      viewportHeight
    )

proc addChatBubbleObjects(
  sim: SimServer,
  packet: var seq[uint8],
  objects: var seq[WorldSpriteObject],
  currentIds: var seq[int],
  viewerId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds cursor-anchored chat bubble objects.
  for message in sim.chatMessages:
    let alpha = sim.chatMessageAlpha(message)
    if alpha == 0:
      continue
    for player in sim.players:
      if player.id != message.playerId:
        continue
      if not sim.playerMarkerVisibleTo(player, viewerId):
        break
      let
        bubble = sim.buildChatBubbleSprite(
          message.text,
          alpha
        )
        nameTopY = player.cursorY - CursorSpriteSize div 2 -
          PlayerNameGapY - sim.playerNameSpriteHeight()
        sx = player.cursorX - bubble.width div 2 - cameraX
        sy = nameTopY - bubble.height - ChatBubbleGapY - cameraY
        spriteId = ChatSpriteBase + player.id
      packet.addSprite(
        spriteId,
        bubble.width,
        bubble.height,
        bubble.pixels,
        "chat " & message.text
      )
      objects.addWorldObject(
        currentIds,
        ChatObjectBase + player.id,
        sx,
        sy,
        ChatBubbleZBase + player.cursorY,
        spriteId,
        bubble.width,
        bubble.height,
        viewportWidth,
        viewportHeight
      )
      break

proc addWorldObjects(
  sim: SimServer,
  packet: var seq[uint8],
  playerNameKeys: var seq[PlayerTextSpriteKey],
  currentIds: var seq[int],
  previousObjects: Table[int, WorldSpriteObject],
  nextObjects: var Table[int, WorldSpriteObject],
  viewerId,
  selectedIndex,
  originIndex,
  selectedPlanetId,
  cameraX,
  cameraY,
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds all visible world objects to a protocol packet.
  var objects: seq[WorldSpriteObject] = @[]
  currentIds.add(MapObjectId)
  objects.add(WorldSpriteObject(
    id: MapObjectId,
    x: -cameraX,
    y: -cameraY,
    z: low(int16),
    layer: MapLayerId,
    spriteId: MapSpriteId
  ))
  sim.addPlanetObjects(
    objects,
    currentIds,
    viewerId,
    selectedIndex,
    originIndex,
    selectedPlanetId,
    cameraX,
    cameraY,
    viewportWidth,
    viewportHeight
  )
  sim.addShipObjects(
    objects,
    currentIds,
    viewerId,
    cameraX,
    cameraY,
    viewportWidth,
    viewportHeight
  )
  sim.addCursorObjects(
    objects,
    currentIds,
    viewerId,
    cameraX,
    cameraY,
    viewportWidth,
    viewportHeight
  )
  sim.addPlayerNameObjects(
    packet,
    playerNameKeys,
    objects,
    currentIds,
    viewerId,
    cameraX,
    cameraY,
    viewportWidth,
    viewportHeight
  )
  sim.addChatBubbleObjects(
    packet,
    objects,
    currentIds,
    viewerId,
    cameraX,
    cameraY,
    viewportWidth,
    viewportHeight
  )
  packet.flushWorldObjects(objects, previousObjects, nextObjects)

proc addPlayerHudLabelSprites(
  sim: SimServer,
  packet: var seq[uint8]
) {.measure.} =
  ## Adds the immutable player HUD label sprites.
  for i, label in HudLabels:
    let sprite = sim.buildTextSprite([label], ScoreColor, false)
    packet.addSprite(
      HudLabelSpriteBase + i,
      sprite.width,
      sprite.height,
      sprite.pixels,
      "hud label " & label
    )

proc addPlayerHud(
  sim: SimServer,
  packet: var seq[uint8],
  labelsDefined: var bool,
  currentIds: var seq[int],
  previousObjects: Table[int, WorldSpriteObject],
  nextObjects: var Table[int, WorldSpriteObject],
  playerIndex: int
) {.measure.} =
  ## Adds the player score HUD.
  ##
  ## The score moves almost every tick, so rasterizing the HUD into one
  ## sprite re-uploaded a few hundred bytes of bitmap every frame. Labels
  ## are static and the digits are ten shared sprites, so a changed score
  ## now costs one 12 byte object message per digit that actually differs.
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  if not labelsDefined:
    # The player view has no score panel, so the shared digit sprites the
    # HUD draws with have to be defined here too.
    sim.addScorePanelDigitSprites(packet)
    sim.addPlayerHudLabelSprites(packet)
    labelsDefined = true
  let
    player = sim.players[playerIndex]
    planets = sim.countOwnedPlanets(player.id)
    lineHeight = sim.textFont.height + 1
  var objects: seq[WorldSpriteObject] = @[]
  for line, value in [player.score, planets]:
    let
      rowY = HudY + line * lineHeight
      labelObjectId = HudLabelObjectBase + line
    objects.add(WorldSpriteObject(
      id: labelObjectId,
      x: 0,
      y: rowY,
      z: high(int16),
      layer: TopLeftLayerId,
      spriteId: HudLabelSpriteBase + line
    ))
    currentIds.add(labelObjectId)
    var digitX = sim.textFont.textWidth(HudLabels[line]) + HudLabelGapX
    for i, ch in $value:
      if i >= HudMaxValueChars or ch < '0' or ch > '9':
        continue
      let digitObjectId = HudDigitObjectBase + line * HudMaxValueChars + i
      objects.add(WorldSpriteObject(
        id: digitObjectId,
        x: digitX,
        y: rowY,
        z: high(int16),
        layer: TopLeftLayerId,
        spriteId: scorePanelDigitSpriteId(ch)
      ))
      currentIds.add(digitObjectId)
      digitX += sim.textFont.glyphAdvance(ch)
  packet.flushWorldObjects(objects, previousObjects, nextObjects)

proc addWaitingText(
  sim: SimServer,
  packet: var seq[uint8],
  waitingSpriteDefined: var bool,
  currentIds: var seq[int]
) {.measure.} =
  ## Adds centered waiting text to an unassigned player view.
  let
    width = sim.playerNameSpriteWidth("WAITING")
    height = sim.playerNameSpriteHeight()
  if not waitingSpriteDefined:
    let text = sim.buildTextSprite(["WAITING"], ScoreColor, true)
    packet.addSprite(
      WaitingSpriteId,
      text.width,
      text.height,
      text.pixels,
      "waiting"
    )
    waitingSpriteDefined = true
  packet.addObject(
    WaitingObjectId,
    max(0, (WorldWidthPixels - width) div 2),
    max(0, (WorldHeightPixels - height) div 2),
    high(int16),
    MapLayerId,
    WaitingSpriteId
  )
  currentIds.add(WaitingObjectId)

proc addWaitingForPlayersOverlay(
  sim: SimServer,
  packet: var seq[uint8],
  interstitialKey: var string,
  currentIds: var seq[int],
  viewportWidth,
  viewportHeight: int
) {.measure.} =
  ## Adds the centered waiting-for-players interstitial overlay.
  let
    title = "WAITING FOR PLAYERS"
    countLine = $sim.players.len & " OF " & $sim.expectedPlayers & " JOINED"
    lineHeight = sim.textFont.lineHeight()
    width = max(
      sim.textFont.textWidth(title),
      sim.textFont.textWidth(countLine)
    ) + TextOutlinePad * 2
    height = max(1, 2 * lineHeight - sim.textFont.spacing) +
      TextOutlinePad * 2
  if interstitialKey != countLine:
    let text = sim.buildTextSprite([title, countLine], ScoreColor, true)
    packet.addSprite(
      InterstitialSpriteId,
      text.width,
      text.height,
      text.pixels,
      "waiting for players"
    )
    interstitialKey = countLine
  packet.addObject(
    InterstitialObjectId,
    max(0, (viewportWidth - width) div 2),
    max(0, (viewportHeight - height) div 2),
    high(int16),
    MapLayerId,
    InterstitialSpriteId
  )
  currentIds.add(InterstitialObjectId)

proc addGlobalScorePanel(
  sim: SimServer,
  packet: var seq[uint8],
  currentIds: var seq[int],
  state: GlobalViewerState,
  nextState: var GlobalViewerState
) {.measure.} =
  ## Adds the global player score panel objects.
  if sim.players.len == 0:
    return
  if not state.scorePanelDigitsDefined:
    sim.addScorePanelDigitSprites(packet)
    nextState.scorePanelDigitsDefined = true
  var players = sim.players
  players.sort(compareScorePanelPlayers)
  let
    lineHeight = sim.textFont.lineHeight()
    rowHeight = max(lineHeight, ScorePanelChipSize)
    scoreColumnWidth = sim.scorePanelScoreWidth(players)
    nameX = ScorePanelChipSize + ScorePanelChipGapX +
      scoreColumnWidth + ScorePanelNameGapX
    nameMaxWidth = max(1, ScreenWidth - nameX)
  for i, player in players:
    let
      rowY = i * rowHeight
      chipY = rowY + (rowHeight - ScorePanelChipSize) div 2
      scoreText = scorePanelScoreText(player.score)
      scoreWidth = sim.textFont.textWidth(scoreText)
      scoreX = ScorePanelChipSize + ScorePanelChipGapX +
        max(0, scoreColumnWidth - scoreWidth)
      name = sim.scorePanelNameText(player, nameMaxWidth)
      chipObjectId = scorePanelChipObjectId(player.id)
      nameObjectId = scorePanelNameObjectId(player.id)
    sim.addScorePanelPlayerSprites(
      packet,
      nextState.scorePanelPlayerKeys,
      player,
      name
    )
    packet.addObject(
      chipObjectId,
      0,
      chipY,
      high(int16),
      TopLeftLayerId,
      scorePanelChipSpriteId(player.id)
    )
    currentIds.add(chipObjectId)
    packet.addObject(
      nameObjectId,
      nameX,
      rowY,
      high(int16),
      TopLeftLayerId,
      scorePanelNameSpriteId(player.id)
    )
    currentIds.add(nameObjectId)
    var digitX = scoreX
    for j, ch in scoreText:
      if j >= ScorePanelMaxScoreChars:
        break
      if ch < '0' or ch > '9':
        continue
      let digitObjectId = scorePanelDigitObjectId(player.id, j)
      packet.addObject(
        digitObjectId,
        digitX,
        rowY,
        high(int16),
        TopLeftLayerId,
        scorePanelDigitSpriteId(ch)
      )
      currentIds.add(digitObjectId)
      digitX += sim.textFont.glyphAdvance(ch)

proc buildSpriteProtocolPlayerUpdates*(
  sim: SimServer,
  playerIndex: int,
  state: PlayerViewerState,
  nextState: var PlayerViewerState
): seq[uint8] {.measure.} =
  ## Builds sprite protocol updates for one playable player view.
  result = @[]
  nextState = state
  if not nextState.initialized:
    result = sim.buildSpriteProtocolPlayerInit()
    nextState.initialized = true
  if not state.planetTextDigitsDefined:
    sim.addPlanetTextDigitSprites(result)
    nextState.planetTextDigitsDefined = true
  result.addPlayerSpriteDefinitions(nextState.playerSpriteKeys, sim)
  var currentIds: seq[int] = @[]
  var nextObjects: Table[int, WorldSpriteObject]
  if playerIndex < 0 or playerIndex >= sim.players.len:
    if sim.waitingForPlayers:
      sim.addWaitingForPlayersOverlay(
        result,
        nextState.interstitialKey,
        currentIds,
        WorldWidthPixels,
        WorldHeightPixels
      )
    else:
      sim.addWaitingText(
        result,
        nextState.waitingSpriteDefined,
        currentIds
      )
  else:
    var ownedSim = sim
    let player = ownedSim.players[playerIndex]
    # Every player sees the whole board. There is no camera and nothing is
    # culled, so the view never scrolls and never hides a planet.
    ownedSim.addWorldObjects(
      result,
      nextState.playerNameKeys,
      currentIds,
      state.worldObjects,
      nextObjects,
      player.id,
      player.selectedPlanet,
      player.originPlanet,
      -1,
      0,
      0,
      WorldWidthPixels,
      WorldHeightPixels
    )
    ownedSim.addPlayerHud(
      result,
      nextState.hudLabelsDefined,
      currentIds,
      state.worldObjects,
      nextObjects,
      playerIndex
    )
    if sim.waitingForPlayers:
      sim.addWaitingForPlayersOverlay(
        result,
        nextState.interstitialKey,
        currentIds,
        WorldWidthPixels,
        WorldHeightPixels
      )
  for objectId in state.objectIds:
    if objectId notin currentIds:
      result.addDeleteObject(objectId)
  nextState.objectIds = currentIds
  nextState.worldObjects = nextObjects

proc blitText(
  sim: SimServer,
  target: var RgbaSprite,
  text: string,
  x, y: int,
  color: RgbaColor
) =
  ## Blits one Tiny5 text line into a sprite.
  var dx = x
  for ch in text:
    let glyph = sim.textFont.glyphAt(ch)
    target.blitGlyph(glyph, dx, y, color)
    dx += sim.textFont.glyphAdvance(ch)

proc buildReplayTickSprite(sim: SimServer, tick: int): RgbaSprite =
  ## Builds the replay tick counter sprite.
  let text = "TICK " & $tick
  result = newRgbaSprite(
    sim.textFont.textWidth(text) + TextOutlinePad * 2,
    sim.textFont.lineHeight() + TextOutlinePad * 2
  )
  var dx = TextOutlinePad
  for ch in text:
    let glyph = sim.textFont.glyphAt(ch)
    result.blitGlyphOutline(glyph, dx, TextOutlinePad)
    dx += sim.textFont.glyphAdvance(ch)
  sim.blitText(result, text, TextOutlinePad, TextOutlinePad, WhiteColor)

proc buildReplayScrubberSprite(tick, maxTick: int): RgbaSprite =
  ## Builds the compact replay scrubber sprite.
  result = newRgbaSprite(ReplayScrubberWidth, ReplayScrubberHeight)
  let
    track = RgbaColor(r: 90, g: 90, b: 90, a: 255)
    knob = RgbaColor(r: 255, g: 255, b: 255, a: 255)
    knobEdge = RgbaColor(r: 180, g: 180, b: 180, a: 255)
    knobX =
      if maxTick > 0:
        clamp(
          (tick * (ReplayScrubberWidth - 1)) div maxTick,
          0,
          ReplayScrubberWidth - 1
        )
      else:
        0
  for x in 0 ..< ReplayScrubberWidth:
    result.putRgbaPixel(x, ReplayScrubberTrackY, track)
  for x in 0 .. knobX:
    result.putRgbaPixel(x, ReplayScrubberTrackY, knob)
  for y in 0 ..< ReplayScrubberHeight:
    result.putRgbaPixel(knobX, y, knob)
  if knobX > 0:
    result.putRgbaPixel(knobX - 1, ReplayScrubberTrackY, knobEdge)
  if knobX < ReplayScrubberWidth - 1:
    result.putRgbaPixel(knobX + 1, ReplayScrubberTrackY, knobEdge)

proc buildReplayControlsSprite(
  sim: SimServer,
  playing: bool,
  looping: bool,
  speed: int
): RgbaSprite =
  ## Builds the replay transport controls sprite from text buttons.
  result = newRgbaSprite(TransportWidth, TransportHeight)
  let
    bright = RgbaColor(r: 255, g: 255, b: 255, a: 255)
    dim = RgbaColor(r: 128, g: 128, b: 128, a: 255)
    buttons = [
      "<<",
      if playing: "||" else: "|>",
      ">|",
      "R"
    ]
  for i, label in buttons:
    let color =
      if i == 3:
        if looping: bright else: dim
      else:
        bright
    sim.blitText(result, label, i * TransportButtonStride, 0, color)
  for i, label in TransportSpeedLabels:
    let color =
      if TransportSpeedValues[i] == speed:
        bright
      else:
        dim
    sim.blitText(
      result,
      label,
      i * TransportSpeedStride,
      TransportSpeedY,
      color
    )

proc addReplayControls(
  sim: SimServer,
  packet: var seq[uint8],
  currentIds: var seq[int],
  nextState: var GlobalViewerState,
  replayTick,
  replaySpeed,
  replayMaxTick: int,
  playing,
  looping: bool,
  mismatchTick: int
) =
  ## Adds the replay timing controls for one replay viewer frame.
  packet.addLayer(
    ReplayCenterBottomLayerId,
    ReplayCenterBottomLayerKind,
    UiLayerFlag
  )
  packet.addViewport(
    ReplayCenterBottomLayerId,
    WorldWidthPixels,
    ReplayPanelHeight
  )
  packet.addLayer(
    ReplayBottomLeftLayerId,
    ReplayBottomLeftLayerKind,
    UiLayerFlag
  )
  packet.addViewport(
    ReplayBottomLeftLayerId,
    WorldWidthPixels,
    ReplayPanelHeight
  )
  let
    controlTick = max(0, replayTick)
    controlMaxTick = max(controlTick, replayMaxTick)
    tickKey = $controlTick & "/" & $controlMaxTick
    controlsKey = $playing & "/" & $looping & "/" & $replaySpeed
  if nextState.replayTickKey != tickKey:
    let
      tickText = sim.buildReplayTickSprite(controlTick)
      scrubber = buildReplayScrubberSprite(controlTick, controlMaxTick)
    packet.addSprite(
      ReplayTickSpriteId,
      tickText.width,
      tickText.height,
      tickText.pixels,
      "replay tick"
    )
    packet.addSprite(
      ReplayScrubberSpriteId,
      scrubber.width,
      scrubber.height,
      scrubber.pixels,
      "replay scrubber"
    )
    nextState.replayTickKey = tickKey
  if nextState.replayControlsKey != controlsKey:
    let controls = sim.buildReplayControlsSprite(
      playing,
      looping,
      replaySpeed
    )
    packet.addSprite(
      ReplayControlsSpriteId,
      controls.width,
      controls.height,
      controls.pixels,
      "replay controls"
    )
    nextState.replayControlsKey = controlsKey
  let tickTextWidth =
    sim.textFont.textWidth("TICK " & $controlTick) + TextOutlinePad * 2
  packet.addObject(
    ReplayTickObjectId,
    max(0, (WorldWidthPixels - tickTextWidth) div 2),
    0,
    0,
    ReplayCenterBottomLayerId,
    ReplayTickSpriteId
  )
  currentIds.add(ReplayTickObjectId)
  packet.addObject(
    ReplayScrubberObjectId,
    max(0, (WorldWidthPixels - ReplayScrubberWidth) div 2),
    ReplayScrubberY,
    0,
    ReplayCenterBottomLayerId,
    ReplayScrubberSpriteId
  )
  currentIds.add(ReplayScrubberObjectId)
  packet.addObject(
    ReplayControlsObjectId,
    TransportX,
    TransportY,
    0,
    ReplayBottomLeftLayerId,
    ReplayControlsSpriteId
  )
  currentIds.add(ReplayControlsObjectId)
  if mismatchTick >= 0:
    let mismatchKey = $mismatchTick
    packet.addLayer(
      ReplayMismatchLayerId,
      ReplayMismatchLayerKind,
      UiLayerFlag
    )
    if nextState.replayMismatchKey != mismatchKey:
      let
        label = "HASH MISMATCH AT TICK " & $mismatchTick
        textWidth = sim.textFont.textWidth(label)
      var warning = newRgbaSprite(
        textWidth + ReplayMismatchPadX * 2,
        sim.textFont.lineHeight() + ReplayMismatchPadY * 2
      )
      warning.fillRect(
        0,
        0,
        warning.width,
        warning.height,
        RgbaColor(r: 220, g: 20, b: 20, a: 255)
      )
      sim.blitText(
        warning,
        label,
        ReplayMismatchPadX,
        ReplayMismatchPadY,
        WhiteColor
      )
      packet.addViewport(
        ReplayMismatchLayerId,
        warning.width,
        warning.height
      )
      packet.addSprite(
        ReplayMismatchSpriteId,
        warning.width,
        warning.height,
        warning.pixels,
        "replay mismatch"
      )
      nextState.replayMismatchKey = mismatchKey
    packet.addObject(
      ReplayMismatchObjectId,
      0,
      0,
      0,
      ReplayMismatchLayerId,
      ReplayMismatchSpriteId
    )
    currentIds.add(ReplayMismatchObjectId)

proc buildSpriteProtocolUpdates*(
  sim: SimServer,
  state: GlobalViewerState,
  nextState: var GlobalViewerState,
  replayControls = false,
  replayTick = -1,
  replaySpeed = 1,
  replayMaxTick = -1,
  replayPlaying = false,
  replayLooping = false,
  replayMismatchTick = -1
): seq[uint8] {.measure.} =
  ## Builds global viewer object updates for the current tick.
  result = @[]
  nextState = state
  if nextState.clickPending and not replayControls:
    if nextState.mouseLayer == MapLayerId:
      nextState.selectedPlanetId =
        sim.selectPlanetAt(nextState.mouseX, nextState.mouseY)
    nextState.clickPending = false
  if not nextState.initialized:
    result = sim.buildSpriteProtocolInit()
    nextState.initialized = true
  if not state.planetTextDigitsDefined:
    sim.addPlanetTextDigitSprites(result)
    nextState.planetTextDigitsDefined = true
  result.addPlayerSpriteDefinitions(nextState.playerSpriteKeys, sim)
  var currentIds: seq[int] = @[]
  var nextObjects: Table[int, WorldSpriteObject]
  sim.addWorldObjects(
    result,
    nextState.playerNameKeys,
    currentIds,
    state.worldObjects,
    nextObjects,
    0,
    -1,
    -1,
    nextState.selectedPlanetId,
    0,
    0,
    WorldWidthPixels,
    WorldHeightPixels
  )
  sim.addGlobalScorePanel(result, currentIds, state, nextState)
  if sim.waitingForPlayers:
    sim.addWaitingForPlayersOverlay(
      result,
      nextState.interstitialKey,
      currentIds,
      WorldWidthPixels,
      WorldHeightPixels
    )
  if replayControls:
    sim.addReplayControls(
      result,
      currentIds,
      nextState,
      replayTick,
      replaySpeed,
      replayMaxTick,
      replayPlaying,
      replayLooping,
      replayMismatchTick
    )
  for objectId in state.objectIds:
    if objectId notin currentIds:
      result.addDeleteObject(objectId)
  nextState.objectIds = currentIds
  nextState.worldObjects = nextObjects
