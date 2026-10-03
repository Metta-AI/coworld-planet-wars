## Bounded native viewer; run only inside the granted serial GUI lease.
import std/[os, strutils, json]
import chroma, opengl, pixie, vmath, windy
import polyworld/shapes
import planet_wars/[sim, replays, presentation]

let data = loadReplay(paramStr(1))
let settings = data.replaySimSettings()
var world = initSimServer(settings.seed, settings.config)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(settings.seed, settings.config)
let tick = if paramCount() >= 2: parseInt(paramStr(2)) else: replay.replayMaxTick()
replay.applyReplaySeek(world, tick)
doAssert not replay.hashValidationFailed
let before = world.gameHash()
let frame = world.presentationFrame()
let width = if paramCount() >= 4: parseInt(paramStr(4)) else: 800
let height = if paramCount() >= 5: parseInt(paramStr(5)) else: 800
let camera = fixedCamera(width, height)
let window = newWindow("Planet Wars replay presentation / tick " & $tick,
                       ivec2(width.int32, height.int32), vsync = false)
window.makeContextCurrent()
loadExtensions()
var renderer = initShapeRenderer()
var selected = -1
proc color(bytes: array[4, uint8]): ColorRGBX = rgbx(bytes[0], bytes[1], bytes[2], bytes[3])
proc drawFrame() =
  glViewport(0, 0, width.GLsizei, height.GLsizei)
  glClearColor(0.02, 0.03, 0.07, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  renderer.clear()
  # Routes below planets, ships above them: no sphere can hide a ship.
  for ship in frame.ships:
    renderer.addLine(vec3(ship.fromX.float32, 0, ship.fromY.float32),
      vec3(ship.toX.float32, 0, ship.toY.float32),
      rgbx(ship.color[0], ship.color[1], ship.color[2], 90), 0.4)
  for i, planet in frame.planets:
    let center = vec3(planet.x.float32, 1, planet.y.float32)
    if i == selected:
      renderer.addCircle(center, planet.radius.float32+3, rgbx(255, 231, 82, 254))
    renderer.addCircle(center + vec3(0, 0.1, 0), planet.radius.float32, color(planet.color))
  for ship in frame.ships:
    let c = vec3(ship.x.float32, 2, ship.y.float32)
    renderer.addTriangle(c+vec3(0, 0, -2.5), c+vec3(-1.8, 0, 2),
                         c+vec3(1.8, 0, 2), color(ship.color))
  let halfWidth = width.float32 / (2*camera.scale)
  let halfHeight = height.float32 / (2*camera.scale)
  let projection = ortho(-halfWidth, halfWidth, -halfHeight, halfHeight, 0.1'f32, 1000'f32)
  let view = lookAt(vec3(256, 600, 256), vec3(256, 0, 256), vec3(0, 0, -1))
  renderer.draw(projection * view)
  doAssert glGetError() == GL_NO_ERROR

try:
  for frameIndex in 0 ..< 120:
    pollEvents()
    if window.closeRequested: break
    selected = frame.pickPlanet(camera, window.mousePos.x.float32, window.mousePos.y.float32)
    drawFrame()
    if frameIndex == 100 and paramCount() >= 3:
      var pixels = newSeq[uint8](width*height*4)
      glReadPixels(0, 0, width.GLsizei, height.GLsizei, GL_RGBA, GL_UNSIGNED_BYTE, pixels[0].addr)
      let image = newImage(width, height)
      for y in 0 ..< height:
        for x in 0 ..< width:
          let offset = (y*width+x)*4
          image[x, height-1-y] = rgbx(pixels[offset], pixels[offset+1], pixels[offset+2], 255)
      image.writeFile(paramStr(3))
      echo $(%*{"tick": tick, "hash": $before, "selected": selected,
        "mouseX": window.mousePos.x, "mouseY": window.mousePos.y,
        "width": width, "height": height, "ships": frame.ships.len,
        "planets": frame.planets.len, "screenshot": paramStr(3)})
    window.swapBuffers()
    sleep(16)
  doAssert world.gameHash() == before
finally:
  renderer.closeShapeRenderer()
  window.close()
