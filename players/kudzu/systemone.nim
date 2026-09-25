## Typed mission choice over the player's decoded Planet Wars view.

import std/[httpclient, json, monotimes, times]

type
  MissionChoice* = object
    originId*: int
    targetId*: int
    budget*: int
    score*: int

  MissionReply* = object
    index*: int
    request*: JsonNode
    response*: JsonNode
    latencyMs*: int64

proc missionRequest*(state: JsonNode, options: openArray[MissionChoice], model: string): JsonNode =
  if options.len < 2:
    raise newException(ValueError, "SystemOne needs at least two legal missions")
  var criteria = newJObject()
  for index, choice in options:
    criteria["mission_" & $index] = %(
      "Launch " & $choice.budget & " ships from observed planet " &
      $choice.originId & " toward observed planet " & $choice.targetId &
      "; heuristic cost " & $choice.score
    )
  result = %*{
    "model": model,
    "state": state,
    "questions": {"mission": {
      "type": "choice",
      "instructions": "Choose one currently offered expansion mission. The game bot handles pointer and button input.",
      "criteria": criteria
    }}
  }

proc parseMissionChoice*(response: JsonNode, count: int): int =
  let answer = response["answers"]["mission"]
  if answer["type"].getStr() != "choice":
    raise newException(ValueError, "SystemOne returned a non-choice answer")
  let choice = answer["choice"].getStr()
  for index in 0 ..< count:
    if choice == "mission_" & $index:
      result = index
      break
  if choice != "mission_" & $result:
    raise newException(ValueError, "SystemOne chose an unoffered mission")
  let probabilities = answer["probabilities"]
  if probabilities.len != count:
    raise newException(ValueError, "SystemOne returned the wrong mission distribution")
  var total = 0.0
  var maximum = 0.0
  var selected = 0.0
  for index in 0 ..< count:
    let key = "mission_" & $index
    if not probabilities.hasKey(key):
      raise newException(ValueError, "SystemOne omitted a mission probability")
    let probability = probabilities[key].getFloat()
    if probability < 0 or probability > 1:
      raise newException(ValueError, "SystemOne returned an invalid probability")
    total += probability
    maximum = max(maximum, probability)
    if index == result:
      selected = probability
  if abs(total - 1.0) > 0.005 * count.float + 1e-9:
    raise newException(ValueError, "SystemOne probabilities do not sum to one")
  if maximum > selected + 0.01 + 1e-6:
    raise newException(ValueError, "SystemOne selected a lower-ranked mission")

proc chooseMission*(state: JsonNode, options: openArray[MissionChoice], model, url, key: string, slot = -1): MissionReply =
  result.request = missionRequest(state, options, model)
  let client = newHttpClient(timeout = 3000)
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  if key.len > 0:
    client.headers["Authorization"] = "Bearer " & key
  if slot >= 0:
    client.headers["X-Coworld-Player-Slot"] = $slot
  let started = getMonoTime()
  let response = client.request(url, httpMethod = HttpPost, body = $result.request)
  if response.code != Http200:
    raise newException(ValueError, "SystemOne returned HTTP " & $response.code)
  result.response = parseJson(response.body)
  result.latencyMs = (getMonoTime() - started).inMilliseconds
  result.index = parseMissionChoice(result.response, options.len)
