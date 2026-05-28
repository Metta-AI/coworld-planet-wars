import
  std/json,
  bitworld/runtime,
  jsony,
  planet_wars/server,
  planet_wars/sim

type
  RunConfig = object
    address: string
    port: int
    seed: int
    simConfig: SimConfig
    tokens: seq[string]

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  ## Reads one optional integer config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(
      PlanetWarsError,
      "Config field " & name & " must be an integer."
    )
  value = item.getInt()

proc readConfigStrings(node: JsonNode, name: string, values: var seq[string]) =
  ## Reads one optional string array config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JArray:
    raise newException(
      PlanetWarsError,
      "Config field " & name & " must be an array."
    )
  var next: seq[string] = @[]
  for i in 0 ..< item.len:
    if item[i].kind != JString:
      raise newException(
        PlanetWarsError,
        "Config field " & name & " item " & $i & " must be a string."
      )
    next.add item[i].getStr()
  values = next

proc isKnownConfigField(name: string): bool =
  ## Returns true when a JSON config field is supported.
  case name
  of "seed",
      "planetCount",
      "maxTicks",
      "maxGames",
      "tokens":
    true
  else:
    false

proc validateConfigFields(node: JsonNode) =
  ## Raises when JSON config contains an unknown field.
  for name, _ in node.pairs:
    if not name.isKnownConfigField():
      raise newException(
        PlanetWarsError,
        "Unknown config field: " & name
      )

proc update(config: var RunConfig, jsonText: string) =
  ## Updates the run config from a JSON object.
  if jsonText.len == 0:
    return
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(
      PlanetWarsError,
      "Could not parse config JSON: " & e.msg
    )
  if node.kind != JObject:
    raise newException(PlanetWarsError, "Config must be a JSON object.")
  node.validateConfigFields()
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("planetCount", config.simConfig.planetCount)
  node.readConfigInt("maxTicks", config.simConfig.maxTicks)
  node.readConfigInt("maxGames", config.simConfig.maxGames)
  node.readConfigStrings("tokens", config.tokens)

proc echoStartupPaths(config: RunConfig) =
  ## Prints configured score output paths.
  echo "Using planet count: " & $config.simConfig.planetCount
  echo "Using max ticks: " & $config.simConfig.maxTicks
  echo "Using max games: " & $config.simConfig.maxGames

when isMainModule:
  let runtimeConfig = readRuntimeConfig()
  var
    config = RunConfig(
      address: runtimeConfig.host,
      port: runtimeConfig.port,
      seed: 0x1A7E7,
      simConfig: defaultSimConfig(),
      tokens: @[]
    )
  config.update(runtimeConfig.config)
  config.simConfig.checkSimConfig()
  config.echoStartupPaths()
  runServerLoop(
    config.address,
    config.port,
    config.seed,
    config.simConfig,
    runtimeConfig,
    config.tokens
  )
