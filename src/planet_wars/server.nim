import
  std/[json, locks, monotimes, os, strutils, tables, times],
  curly, mummy,
  bitworld/client, bitworld/profile, bitworld/spriteprotocol, bitworld/runtime,
  sim, global, replays

const
  HealthzPath = "/healthz"
  ReplayStatePath = "/replay/state"
  ReplayPage = staticRead("../../client/replay.html")
  UnassignedPlayerIndex = 0x7fffffff

type
  WebSocketAppState = object
    lock: Lock
    inputMasks: Table[WebSocket, uint8]
    lastAppliedMasks: Table[WebSocket, uint8]
    chatMessages: Table[WebSocket, string]
    playerIndices: Table[WebSocket, int]
    playerNames: Table[WebSocket, string]
    playerViewers: Table[WebSocket, PlayerViewerState]
    globalViewers: Table[WebSocket, GlobalViewerState]
    replayViewers: Table[WebSocket, GlobalViewerState]
    rewardViewers: Table[WebSocket, bool]
    tokens: seq[string]
    closedSockets: seq[WebSocket]
    replayServerMode: bool
    replayLoaded: bool
    replayState: string
    pendingReplayUri: string

  ServerThreadArgs = object
    server: ptr Server
    address: string
    port: int

var appState: WebSocketAppState

proc initAppState() =
  ## Initializes the shared websocket state.
  initLock(appState.lock)
  appState.inputMasks = initTable[WebSocket, uint8]()
  appState.lastAppliedMasks = initTable[WebSocket, uint8]()
  appState.chatMessages = initTable[WebSocket, string]()
  appState.playerIndices = initTable[WebSocket, int]()
  appState.playerNames = initTable[WebSocket, string]()
  appState.playerViewers = initTable[WebSocket, PlayerViewerState]()
  appState.globalViewers = initTable[WebSocket, GlobalViewerState]()
  appState.replayViewers = initTable[WebSocket, GlobalViewerState]()
  appState.rewardViewers = initTable[WebSocket, bool]()
  appState.tokens = @[]
  appState.closedSockets = @[]
  appState.replayServerMode = false
  appState.replayLoaded = false
  appState.replayState = "{\"loaded\":false}"
  appState.pendingReplayUri = ""

proc isWebSocketUpgrade(request: Request): bool =
  ## Returns true when a GET request is a websocket upgrade.
  request.headers["Sec-WebSocket-Key"].len > 0

proc serveHealthz(request: Request): bool =
  ## Serves the container health check endpoint.
  if request.path != HealthzPath or request.httpMethod notin ["GET", "HEAD"]:
    return false
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain; charset=utf-8"
  headers["Cache-Control"] = "no-cache"
  request.respond(200, headers, "healthy")
  true

proc cleanPlayerName(name: string): string =
  ## Returns a protocol-safe player display name.
  result = name.strip()
  for ch in result.mitems:
    if ch.isSpaceAscii:
      ch = '_'

proc playerIdentity(request: Request): string =
  ## Returns the websocket player identity for rewards and displays.
  let name = request.queryParams.getOrDefault("name", "").cleanPlayerName()
  if name.len > 0:
    return name
  let parts = request.remoteAddress.splitWhitespace()
  if parts.len >= 2:
    return parts[0] & ":" & parts[1]
  request.remoteAddress

proc playerSlot(request: Request): int =
  ## Returns the requested player slot or -1 for automatic assignment.
  let text = request.queryParams.getOrDefault("slot", "").strip()
  if text.len == 0:
    return -1
  try:
    result = parseInt(text)
  except ValueError:
    return int.high
  if result < 0:
    return int.high

proc playerToken(request: Request): string =
  ## Returns the requested player token.
  request.queryParams.getOrDefault("token", "").strip()

proc playerJoinAllowed(slot: int, token: string): bool =
  ## Returns true when the configured token list accepts a join.
  if appState.tokens.len == 0:
    return true
  if slot >= 0 and slot < appState.tokens.len:
    return token == appState.tokens[slot]
  if slot == -1:
    return token in appState.tokens
  false

proc isGlobalSocketPath(path: string): bool =
  ## Returns true for global viewer websocket endpoints.
  path == GlobalWebSocketPath or
    path == AdminWebSocketPath

proc respondPlain(request: Request, status: int, body: string) =
  ## Sends one plain-text response.
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain; charset=utf-8"
  request.respond(status, headers, body)

proc replayFilePath(uri: string): string =
  ## Resolves one local replay URI to a host path.
  const FilePrefix = "file://"
  if uri.startsWith(FilePrefix):
    return uri[FilePrefix.len .. ^1]
  if "://" in uri:
    return ""
  uri

let replayDownloadPool = newCurlPool(1)

proc loadReplayUri(uri: string): ReplayData =
  ## Loads a replay from a local file URI or HTTP(S) URL.
  parseReplayBytes(readCogameUri(uri, CogameLoadReplayUriEnv))

proc readableReplayUri(uri: string): bool =
  ## Returns true when a replay URI can be opened by this server.
  if uri.len == 0:
    return false
  if uri.startsWith("http://") or uri.startsWith("https://"):
    return replayDownloadPool.head(uri).code == 200
  let path = replayFilePath(uri)
  path.len > 0 and fileExists(path)

proc replayRequestUri(request: Request): string =
  ## Returns the replay artifact URI requested by a Coworld replay client.
  request.queryParams.getOrDefault("uri", "").strip()

proc checkReplayRequest(request: Request): bool =
  ## Validates one replay page or websocket request, capturing the
  ## requested replay URI for the playback loop. Returns false after
  ## responding with an error.
  result = true
  var
    replayServerMode = false
    replayLoaded = false
  {.gcsafe.}:
    withLock appState.lock:
      replayServerMode = appState.replayServerMode
      replayLoaded = appState.replayLoaded
  if not replayServerMode:
    return true
  let uri = request.replayRequestUri()
  if uri.len == 0:
    if replayLoaded:
      return true
    request.respondPlain(400, "missing replay uri\n")
    return false
  var readable = false
  {.gcsafe.}:
    readable = uri.readableReplayUri()
  if not readable:
    request.respondPlain(404, "replay uri is not readable\n")
    return false
  {.gcsafe.}:
    withLock appState.lock:
      appState.pendingReplayUri = uri
  return true

proc httpHandler(request: Request) =
  ## Handles HTTP routes and websocket upgrades.
  if request.serveHealthz():
    discard
  elif request.path == ReplayStatePath and request.httpMethod == "GET":
    var replayState: string
    {.gcsafe.}:
      withLock appState.lock:
        replayState = appState.replayState
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json; charset=utf-8"
    headers["Cache-Control"] = "no-store"
    request.respond(200, headers, replayState)
  elif request.path == WebSocketPath and
      request.httpMethod == "GET" and
      request.isWebSocketUpgrade():
    let
      slot = request.playerSlot()
      token = request.playerToken()
    var allowed = false
    {.gcsafe.}:
      withLock appState.lock:
        allowed = playerJoinAllowed(slot, token)
    if not allowed:
      var headers: HttpHeaders
      headers["Content-Type"] = "text/plain; charset=utf-8"
      request.respond(403, headers, "player token rejected\n")
      return
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.globalViewers.del(websocket)
        appState.rewardViewers.del(websocket)
        appState.playerViewers[websocket] = initPlayerViewerState()
        appState.playerNames[websocket] = request.playerIdentity()
        appState.playerIndices[websocket] = UnassignedPlayerIndex
        appState.inputMasks[websocket] = 0
        appState.lastAppliedMasks[websocket] = 0
  elif request.path.isGlobalSocketPath() and
      request.httpMethod == "GET" and request.isWebSocketUpgrade():
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerViewers.del(websocket)
        appState.playerIndices.del(websocket)
        appState.playerNames.del(websocket)
        appState.inputMasks.del(websocket)
        appState.lastAppliedMasks.del(websocket)
        appState.rewardViewers.del(websocket)
        var state = initGlobalViewerState()
        state.compact = request.queryParams.getOrDefault("compact", "") == "1"
        appState.globalViewers[websocket] = state
  elif request.path == ReplayWebSocketPath and
      request.httpMethod == "GET" and request.isWebSocketUpgrade():
    if not request.checkReplayRequest():
      return
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerViewers.del(websocket)
        appState.playerIndices.del(websocket)
        appState.playerNames.del(websocket)
        appState.inputMasks.del(websocket)
        appState.lastAppliedMasks.del(websocket)
        appState.rewardViewers.del(websocket)
        appState.globalViewers.del(websocket)
        appState.replayViewers[websocket] = initGlobalViewerState()
  elif request.path == ReplayWebSocketPath and request.httpMethod == "GET":
    if not request.checkReplayRequest():
      return
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html; charset=utf-8"
    request.respond(200, headers, ReplayPage)
  elif request.path in [ReplayClientRoute, CoworldReplayClientRoute] and
      request.httpMethod == "GET":
    if not request.checkReplayRequest():
      return
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html; charset=utf-8"
    request.respond(200, headers, ReplayPage)
  elif request.path == RewardWebSocketPath and request.httpMethod == "GET" and
      request.isWebSocketUpgrade():
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerViewers.del(websocket)
        appState.playerIndices.del(websocket)
        appState.playerNames.del(websocket)
        appState.inputMasks.del(websocket)
        appState.lastAppliedMasks.del(websocket)
        appState.globalViewers.del(websocket)
        appState.rewardViewers[websocket] = true
  elif request.serveClientRoute(GlobalClientRoute):
    discard
  else:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain; charset=utf-8"
    request.respond(200, headers, "Bit World global protocol server")

proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) =
  ## Handles websocket lifecycle and input messages.
  case event
  of OpenEvent:
    discard
  of MessageEvent:
    if message.kind == Ping:
      websocket.send(message.data, Pong)
      return
    if message.kind != BinaryMessage:
      return
    {.gcsafe.}:
      withLock appState.lock:
        if websocket in appState.replayViewers:
          appState.replayViewers[websocket].applyGlobalViewerMessage(
            message.data,
            replayControls = true
          )
        elif websocket in appState.globalViewers:
          appState.globalViewers[websocket].applyGlobalViewerMessage(
            message.data,
            replayControls = appState.replayServerMode
          )
        elif websocket in appState.playerViewers:
          if isInputPacket(message.data):
            appState.inputMasks[websocket] = blobToMask(message.data)
          elif isChatPacket(message.data):
            appState.chatMessages[websocket] = blobToChat(message.data)
          else:
            var
              mask = appState.inputMasks.getOrDefault(websocket, 0)
              chatText = ""
            appState.playerViewers[websocket].applyPlayerViewerMessage(
              message.data,
              mask,
              chatText
            )
            appState.inputMasks[websocket] = mask
            if chatText.len > 0:
              appState.chatMessages[websocket] = chatText
  of ErrorEvent:
    discard
  of CloseEvent:
    {.gcsafe.}:
      withLock appState.lock:
        appState.closedSockets.add(websocket)

proc removePlayer(sim: var SimServer, websocket: WebSocket) =
  ## Removes a websocket and keeps live player indices consistent.
  if websocket in appState.replayViewers:
    appState.replayViewers.del(websocket)
  if websocket in appState.globalViewers:
    appState.globalViewers.del(websocket)
  if websocket in appState.rewardViewers:
    appState.rewardViewers.del(websocket)
  if websocket in appState.playerViewers:
    appState.playerViewers.del(websocket)
  if websocket in appState.chatMessages:
    appState.chatMessages.del(websocket)
  if websocket notin appState.playerIndices:
    appState.playerNames.del(websocket)
    appState.inputMasks.del(websocket)
    appState.lastAppliedMasks.del(websocket)
    return
  let removedIndex = appState.playerIndices[websocket]
  appState.playerIndices.del(websocket)
  appState.playerNames.del(websocket)
  appState.inputMasks.del(websocket)
  appState.lastAppliedMasks.del(websocket)
  if removedIndex >= 0 and removedIndex < sim.players.len:
    sim.disconnectPlayerAt(removedIndex)

proc resetConnectedClients() =
  ## Clears per-game websocket state while keeping sockets connected.
  var
    playerSockets: seq[WebSocket] = @[]
    globalSockets: seq[WebSocket] = @[]
  for websocket in appState.playerIndices.keys:
    playerSockets.add(websocket)
  for websocket in appState.globalViewers.keys:
    globalSockets.add(websocket)
  for websocket in playerSockets:
    appState.playerIndices[websocket] = UnassignedPlayerIndex
    appState.playerViewers[websocket] = initPlayerViewerState()
    appState.inputMasks[websocket] = 0
    appState.lastAppliedMasks[websocket] = 0
  for websocket in globalSockets:
    appState.globalViewers[websocket] = initGlobalViewerState()
  appState.chatMessages.clear()

proc recordPlayerLeave(
  replayWriter: var ReplayWriter,
  sim: SimServer,
  websocket: WebSocket
) =
  ## Records one replay leave event for a live player socket.
  ## Must be called with the app state lock held, before removal.
  if not replayWriter.enabled:
    return
  if websocket notin appState.playerIndices:
    return
  let playerIndex = appState.playerIndices[websocket]
  if playerIndex < 0 or playerIndex >= sim.players.len:
    return
  replayWriter.writeLeave(tickTime(sim.tickCount), playerIndex)
  if playerIndex < replayWriter.lastMasks.len:
    replayWriter.lastMasks[playerIndex] = 0

proc rewardAddress(address: string): string =
  ## Returns the reward protocol identity for one address.
  let parts = address.splitWhitespace()
  if parts.len >= 2:
    return parts[0] & ":" & parts[1]
  address

proc buildRewardPacket(sim: SimServer): string {.measure.} =
  ## Builds one reward protocol packet for the current tick.
  for player in sim.players:
    result.add("reward ")
    result.add(player.name.rewardAddress())
    result.add(" ")
    result.add($player.score)
    result.add("\n")

proc writeScoresIfNeeded(
  sim: SimServer,
  lastRevision: var int,
  runtimeConfig: RuntimeConfig
) {.measure.} =
  ## Writes scores when score-visible state changed.
  if runtimeConfig.resultsUri.len == 0:
    return
  if sim.scoreRevision == lastRevision:
    return
  runtimeConfig.writeResults(sim.playerScoresJson() & "\n")
  lastRevision = sim.scoreRevision

proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
  ## Runs the mummy server on its own thread.
  args.server[].serve(Port(args.port), args.address)

proc sendBinaryPacket(
  websocket: WebSocket,
  packet: openArray[uint8]
) {.measure.} =
  ## Sends one sprite protocol binary packet.
  websocket.send(blobFromBytes(packet), BinaryMessage)

proc sendTextPacket(websocket: WebSocket, packet: string) {.measure.} =
  ## Sends one text protocol packet.
  websocket.send(packet, TextMessage)

proc runFrameLimiter(previousTick: var MonoTime) =
  ## Sleeps to keep the server near the target frame rate.
  let frameDuration = initDuration(microseconds = 1_000_000 div TargetFps)
  let elapsed = getMonoTime() - previousTick
  if elapsed < frameDuration:
    sleep(int((frameDuration - elapsed).inMilliseconds))
  previousTick = getMonoTime()

proc runServerLoop*(
  host = DefaultHost,
  port = DefaultPort,
  seed = 0x1A7E7,
  simConfig = defaultSimConfig(),
  runtimeConfig = RuntimeConfig(),
  tokens: seq[string] = @[],
  saveReplayPath = "",
  expectedPlayers = 0
) =
  ## Runs the Planet Wars server loop.
  startProfileTrace()
  defer:
    finishProfileTrace()
  initAppState()
  appState.tokens = tokens
  var replayWriter = openReplayWriter(
    saveReplayPath,
    $(%*{
      "seed": seed,
      "planetCount": simConfig.planetCount,
      "maxTicks": simConfig.maxTicks,
      "maxGames": simConfig.maxGames,
      "tokenCount": tokens.len
    })
  )
  let httpServer = newServer(
    httpHandler,
    websocketHandler,
    workerThreads = 4,
    tcpNoDelay = true
  )
  var serverThread: Thread[ServerThreadArgs]
  var serverPtr = cast[ptr Server](unsafeAddr httpServer)
  createThread(
    serverThread,
    serverThreadProc,
    ServerThreadArgs(server: serverPtr, address: host, port: port)
  )
  httpServer.waitUntilReady()
  var
    sim = initSimServer(seed, simConfig, expectedPlayers)
    lastTick = getMonoTime()
    lastScoreRevision = -1
    gamesFinished = 0
  while true:
    var
      sockets: seq[WebSocket] = @[]
      playerIndices: seq[int] = @[]
      playerStates: seq[PlayerViewerState] = @[]
      inputs: seq[PlayerInput]
      globalViewers: seq[WebSocket] = @[]
      globalStates: seq[GlobalViewerState] = @[]
      rewardViewers: seq[WebSocket] = @[]
    {.gcsafe.}:
      withLock appState.lock:
        for websocket in appState.closedSockets:
          replayWriter.recordPlayerLeave(sim, websocket)
          sim.removePlayer(websocket)
        appState.closedSockets.setLen(0)
        for websocket in appState.playerIndices.keys:
          if appState.playerIndices[websocket] != UnassignedPlayerIndex:
            continue
          let
            name = appState.playerNames.getOrDefault(websocket, "unknown")
            playerIndex = sim.addPlayer(name)
          appState.playerIndices[websocket] = playerIndex
          if replayWriter.enabled:
            replayWriter.writeJoin(
              tickTime(sim.tickCount),
              playerIndex,
              name,
              -1,
              ""
            )
            while replayWriter.lastMasks.len < sim.players.len:
              replayWriter.lastMasks.add(0)
        for websocket, chatText in appState.chatMessages.pairs:
          let playerIndex = appState.playerIndices.getOrDefault(
            websocket,
            -1
          )
          sim.addChatMessage(playerIndex, chatText)
          if replayWriter.enabled and
              playerIndex >= 0 and playerIndex < sim.players.len:
            replayWriter.writeChat(
              tickTime(sim.tickCount),
              playerIndex,
              chatText
            )
        appState.chatMessages.clear()
        inputs = newSeq[PlayerInput](sim.players.len)
        for websocket, playerIndex in appState.playerIndices.pairs:
          sockets.add(websocket)
          playerIndices.add(playerIndex)
          playerStates.add(
            appState.playerViewers.getOrDefault(
              websocket,
              initPlayerViewerState()
            )
          )
          if playerIndex < 0 or playerIndex >= inputs.len:
            continue
          let
            currentMask = appState.inputMasks.getOrDefault(websocket, 0)
            previousMask =
              appState.lastAppliedMasks.getOrDefault(websocket, 0)
          if sim.waitingForPlayers:
            # Lobby inputs are neither applied nor recorded, so a mask
            # held across the start still fires its press edge on the
            # first simulated tick, live and in replays alike.
            continue
          inputs[playerIndex] = playerInputFromMasks(
            currentMask,
            previousMask
          )
          appState.lastAppliedMasks[websocket] = currentMask
          replayWriter.writeInputMaskChange(
            tickTime(sim.tickCount),
            playerIndex,
            currentMask
          )
        for websocket, state in appState.globalViewers.pairs:
          globalViewers.add(websocket)
          globalStates.add(state)
        for websocket in appState.rewardViewers.keys:
          rewardViewers.add(websocket)
    let
      wasGameOver = sim.gameOver
      wasWaiting = sim.waitingForPlayers
    sim.step(inputs)
    if not wasWaiting:
      replayWriter.writeHash(uint32(sim.tickCount), sim.gameHash())
    let gameFinished = sim.gameOver and not wasGameOver
    let rewardPacket = sim.buildRewardPacket()
    for i in 0 ..< sockets.len:
      var nextState: PlayerViewerState
      let packet = sim.buildSpriteProtocolPlayerUpdates(
        playerIndices[i],
        playerStates[i],
        nextState
      )
      try:
        sockets[i].sendBinaryPacket(packet)
        {.gcsafe.}:
          withLock appState.lock:
            if sockets[i] in appState.playerViewers:
              appState.playerViewers[sockets[i]] = nextState
      except:
        {.gcsafe.}:
          withLock appState.lock:
            replayWriter.recordPlayerLeave(sim, sockets[i])
            sim.removePlayer(sockets[i])
    for websocket in rewardViewers:
      try:
        websocket.sendTextPacket(rewardPacket)
      except:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(websocket)
    for i in 0 ..< globalViewers.len:
      var nextState: GlobalViewerState
      let packet = sim.buildSpriteProtocolUpdates(globalStates[i], nextState)
      if packet.len == 0:
        continue
      try:
        globalViewers[i].sendBinaryPacket(packet)
        {.gcsafe.}:
          withLock appState.lock:
            if globalViewers[i] in appState.globalViewers:
              appState.globalViewers[globalViewers[i]] = nextState
      except:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(globalViewers[i])
    if profileShouldDump(sim.tickCount):
      finishProfileTrace()
    if gameFinished:
      inc gamesFinished
      echo "Planet Wars game finished: ", gamesFinished
      sim.writeScoresIfNeeded(lastScoreRevision, runtimeConfig)
      if replayWriter.enabled:
        # Only the first game of a run is recorded and uploaded.
        replayWriter.closeReplayWriter()
        if saveReplayPath.len > 0 and fileExists(saveReplayPath):
          echo "Replay written: ", saveReplayPath,
            " (", getFileSize(saveReplayPath), " bytes)"
          runtimeConfig.writeReplay(readFile(saveReplayPath))
      if simConfig.maxGames > 0 and gamesFinished >= simConfig.maxGames:
        break
      sim = initSimServer(seed + gamesFinished, simConfig, expectedPlayers)
      lastScoreRevision = -1
      {.gcsafe.}:
        withLock appState.lock:
          resetConnectedClients()
    runFrameLimiter(lastTick)

proc runReplayServerLoop*(
  host = DefaultHost,
  port = DefaultPort,
  runtimeConfig = RuntimeConfig()
) =
  ## Serves recorded Planet Wars replays to replay and global viewers.
  initAppState()
  appState.replayServerMode = true

  var
    replayData = ReplayData()
    replaySeed = 0x1A7E7
    replaySimConfig = defaultSimConfig()
    replayLoaded = false
  if runtimeConfig.replay.len > 0:
    replayData = parseReplayBytes(runtimeConfig.replay)
    let settings = replayData.replaySimSettings()
    replaySeed = settings.seed
    replaySimConfig = settings.config
    replayLoaded = true
  appState.replayLoaded = replayLoaded

  let httpServer = newServer(
    httpHandler,
    websocketHandler,
    workerThreads = 4,
    tcpNoDelay = true
  )
  var serverThread: Thread[ServerThreadArgs]
  var serverPtr = cast[ptr Server](unsafeAddr httpServer)
  createThread(
    serverThread,
    serverThreadProc,
    ServerThreadArgs(server: serverPtr, address: host, port: port)
  )
  httpServer.waitUntilReady()

  var
    sim = initSimServer(replaySeed, replaySimConfig)
    replay =
      if replayLoaded:
        initReplayPlayer(replayData)
      else:
        ReplayPlayer()
    lastTick = getMonoTime()
  if replayLoaded:
    replay.buildReplayKeyframes(replaySeed, replaySimConfig)

  while true:
    var
      pendingReplayUri = ""
      viewerSockets: seq[WebSocket] = @[]
      viewerStates: seq[GlobalViewerState] = @[]
      viewerIsReplay: seq[bool] = @[]
      seekTicks: seq[int] = @[]
      commands: seq[char] = @[]

    {.gcsafe.}:
      withLock appState.lock:
        pendingReplayUri = appState.pendingReplayUri
        appState.pendingReplayUri = ""
        for websocket in appState.closedSockets:
          sim.removePlayer(websocket)
        appState.closedSockets.setLen(0)

    if pendingReplayUri.len > 0:
      try:
        replayData = loadReplayUri(pendingReplayUri)
        let settings = replayData.replaySimSettings()
        replaySeed = settings.seed
        replaySimConfig = settings.config
        sim = initSimServer(replaySeed, replaySimConfig)
        replay = initReplayPlayer(replayData)
        replay.buildReplayKeyframes(replaySeed, replaySimConfig)
        replayLoaded = true
        {.gcsafe.}:
          withLock appState.lock:
            appState.replayLoaded = true
      except CatchableError as e:
        echo "Could not load replay uri: ", e.msg

    {.gcsafe.}:
      withLock appState.lock:
        for websocket, state in appState.replayViewers.mpairs:
          state.drainReplayViewerInput(
            replay.replayMaxTick(),
            seekTicks,
            commands
          )
          viewerSockets.add(websocket)
          viewerStates.add(state)
          viewerIsReplay.add(true)
        for websocket, state in appState.globalViewers.mpairs:
          state.drainReplayViewerInput(
            replay.replayMaxTick(),
            seekTicks,
            commands
          )
          viewerSockets.add(websocket)
          viewerStates.add(state)
          viewerIsReplay.add(false)

    if replayLoaded:
      for seekTick in seekTicks:
        replay.applyReplaySeek(sim, seekTick)
      for command in commands:
        replay.applyReplayCommand(sim, command)
      if replay.playing:
        for _ in 0 ..< replay.replaySpeed():
          if replay.playing:
            replay.stepReplay(sim)
        if replay.looping and not replay.playing and
            replay.replayMaxTick() > 0:
          replay.seekReplay(sim, 0)
          replay.playing = true

    var players = newJArray()
    for player in sim.players:
      players.add(%*{
        "name": player.name,
        "score": player.score,
        "planets": sim.countOwnedPlanets(player.id),
        "color": [player.color.r, player.color.g, player.color.b]
      })
    let replayState = $(%*{
      "loaded": replayLoaded,
      "tick": sim.tickCount,
      "maxTick": replay.replayMaxTick(),
      "playing": replay.playing,
      "speed": replay.replaySpeed(),
      "gameOver": sim.gameOver,
      "planetCount": sim.planets.len,
      "fleetCount": sim.ships.len,
      "players": players
    })
    {.gcsafe.}:
      withLock appState.lock:
        appState.replayState = replayState

    for i in 0 ..< viewerSockets.len:
      var nextState: GlobalViewerState
      let packet = sim.buildSpriteProtocolUpdates(
        viewerStates[i],
        nextState,
        showScorePanel = not viewerStates[i].compact,
        replayControls = replayLoaded and not viewerStates[i].compact,
        replayTick = sim.tickCount,
        replaySpeed = replay.replaySpeed(),
        replayMaxTick = replay.replayMaxTick(),
        replayPlaying = replay.playing,
        replayLooping = replay.looping,
        replayMismatchTick = replay.hashMismatchTick
      )
      if packet.len == 0:
        continue
      try:
        viewerSockets[i].sendBinaryPacket(packet)
        {.gcsafe.}:
          withLock appState.lock:
            if viewerIsReplay[i]:
              if viewerSockets[i] in appState.replayViewers:
                appState.replayViewers[viewerSockets[i]] = nextState
            elif viewerSockets[i] in appState.globalViewers:
              appState.globalViewers[viewerSockets[i]] = nextState
      except:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(viewerSockets[i])

    runFrameLimiter(lastTick)
