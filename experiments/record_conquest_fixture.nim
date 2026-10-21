## Earn a replay fixture using only public input masks and normal join/leave/chat.
import std/[json, os]
import bitworld/spriteprotocol
import planet_wars/[sim, replays]
let path = paramStr(1)
doAssert path.len > 0
var config = defaultSimConfig()
config.planetCount = 8
config.maxTicks = 1800
config.maxGames = 1
const Seed = 424242
var world = initSimServer(Seed, config)
var writer = openReplayWriter(path, $(%*{"seed": Seed, "planetCount": config.planetCount,
  "maxTicks": config.maxTicks, "maxGames": 1, "tokenCount": 0}))
doAssert writer.enabled
proc join(name: string) =
  let p = world.addPlayer(name)
  writer.writeJoin(tickTime(world.tickCount), p, name, -1, "")
  writer.lastMasks.add 0
join("navigator")
join("observer")
writer.writeChat(tickTime(0), 0, "input-driven conquest fixture")
world.addChatMessage(0, "input-driven conquest fixture")
var previousMasks = newSeq[uint8](8)
var captures = 0
let origin = world.players[0].originPlanet
var target = -1
var nearest = high(int)
for i, planet in world.planets:
  if planet.ownerId == 0:
    let dx = planet.x-world.planets[origin].x
    let dy = planet.y-world.planets[origin].y
    if dx*dx+dy*dy < nearest:
      nearest = dx*dx+dy*dy
      target = i
doAssert target >= 0
while not world.gameOver:
  if world.tickCount == 300: join("late arrival")
  if world.tickCount == 1500:
    writer.writeLeave(tickTime(world.tickCount), 1)
    world.disconnectPlayerAt(1)
  let p = world.players[0]
  let destination = world.planets[target]
  var mask = ButtonB
  # Brake against the existing cursor momentum; never assign cursor or state.
  let dx = destination.x-p.cursorX
  let dy = destination.y-p.cursorY
  if dx*MotionScale > p.cursorVelX*8: mask = mask or ButtonRight
  elif dx*MotionScale < p.cursorVelX*8: mask = mask or ButtonLeft
  if dy*MotionScale > p.cursorVelY*8: mask = mask or ButtonDown
  elif dy*MotionScale < p.cursorVelY*8: mask = mask or ButtonUp
  var inputs = newSeq[PlayerInput](world.players.len)
  inputs[0] = playerInputFromMasks(mask, previousMasks[0])
  previousMasks[0] = mask
  writer.writeInputMaskChange(tickTime(world.tickCount), 0, mask)
  var owners: seq[int]
  for planet in world.planets: owners.add planet.ownerId
  world.step(inputs)
  for i, planet in world.planets:
    if owners[i] != planet.ownerId: inc captures
  writer.writeHash(uint32(world.tickCount), world.gameHash())
writer.closeReplayWriter()
echo $(%*{"tick": world.tickCount, "hash": $world.gameHash(),
  "score": parseJson(world.playerScoresJson()), "capturesFromStep": captures,
  "target": target, "players": world.players.len})
doAssert captures > 0, "Fixture did not earn a conquest"
doAssert world.tickCount > 1500, "Fixture ended before join/leave coverage"
