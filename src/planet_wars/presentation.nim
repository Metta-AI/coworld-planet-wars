## Experimental read-only replay presentation. No simulation or input ownership.
import std/math
import sim

type
  MapCamera* = object
    width*, height*, scale*, left*, top*: float32
  PlanetView* = object
    id*, owner*, x*, y*, radius*, ships*: int
    color*: array[4, uint8]
  ShipView* = object
    owner*, x*, y*, fromX*, fromY*, toX*, toY*: int
    color*: array[4, uint8]
  PresentationFrame* = object
    tick*: int
    planets*: seq[PlanetView]
    ships*: seq[ShipView]

proc fixedCamera*(width, height: int): MapCamera =
  ## Fixed top-down, equal scale on both axes, with visible edge padding.
  result.width = max(1, width).float32
  result.height = max(1, height).float32
  result.scale = min(result.width, result.height) / 544'f32
  result.left = (result.width - 512'f32 * result.scale) / 2
  result.top = (result.height - 512'f32 * result.scale) / 2

proc screenPoint*(camera: MapCamera, x, y: int): tuple[x, y: float32] =
  (camera.left + x.float32 * camera.scale,
   camera.top + y.float32 * camera.scale)

proc worldPoint*(camera: MapCamera, x, y: float32): tuple[x, y: int] =
  (clamp(round((x-camera.left)/camera.scale).int, 0, 511),
   clamp(round((y-camera.top)/camera.scale).int, 0, 511))

proc pickPlanet*(frame: PresentationFrame, camera: MapCamera,
                 x, y: float32): int =
  ## Same nearest-center rule and stable first-index tie as the game cursor.
  let point = camera.worldPoint(x, y)
  result = -1
  var distance = high(int)
  for i, planet in frame.planets:
    let dx = planet.x-point.x
    let dy = planet.y-point.y
    let candidate = dx*dx + dy*dy
    if candidate < distance:
      distance = candidate
      result = i

proc presentationFrame*(world: SimServer): PresentationFrame =
  ## Copy only visible presentation values. Never keep a writable sim alias.
  result.tick = world.tickCount
  for planet in world.planets:
    var color = [102'u8, 112, 136, 254]
    for player in world.players:
      if player.id == planet.ownerId:
        color = [player.color.r, player.color.g, player.color.b, 254'u8]
    result.planets.add PlanetView(id: planet.id, owner: planet.ownerId,
      x: planet.x, y: planet.y, radius: planet.radius, ships: planet.ships,
      color: color)
  for ship in world.ships:
    let position = ship.currentShipPosition()
    result.ships.add ShipView(owner: ship.ownerId, x: position.x, y: position.y,
      fromX: ship.startX, fromY: ship.startY, toX: ship.endX, toY: ship.endY,
      color: [ship.color.r, ship.color.g, ship.color.b, 254'u8])
