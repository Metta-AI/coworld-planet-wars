## Hosted experience-request runner for Planet Wars.
##
## Local games are slow and do not resemble the league, so evaluation runs
## on the cluster: one request carries many episodes and they run in
## parallel, so wall-clock is roughly one episode regardless of count.
##
##   xp run <candidate> <baseline> [episodes]  create a paired A/B request
##   xp watch <xreqId>                         poll until it finishes
##   xp stats <xreqId> [xreqId ...]            per-policy scores + sign test
##
## Add --coworld=<id> (or set PLANET_WARS_COWORLD_ID) to measure against an
## uploaded Coworld instead of the league. A league target always resolves
## to that game's *canonical* Coworld, so a redesigned game cannot be
## measured through it until it is promoted; pinning the uploaded Coworld
## measures the new rules without touching the live league or anyone
## else's submitted policies.
##
## Seats alternate candidate and baseline so both meet the same field on
## the same board, and the pairing is what the sign test consumes.

import
  std/[algorithm, json, math, os, strformat, strutils, tables],
  curly, jsony

const
  ApiBase = "https://softmax.com/api/observatory"
  LeagueId = "league_074c818a-fe56-42a4-a2de-1a79202f281a"
  CredentialsPath = ".softmax/credentials.yaml"
  Field = [
    "co-gas-planet-wars-simple-richard:v7",
    "co-gas-planet-wars-simple-relhalpha:v7",
    "daf-conqueror-v4:v1",
    "rowdaboat-kudzu:v1",
    "planet-wars-bot:v32"
  ]

type
  XpError = object of CatchableError

  EpisodeScore = object
    episodeId: string
    labels: seq[string]
    scores: seq[int]
    planets: seq[int]

proc userToken(): string =
  ## Reads the Observatory user token for softmax.com.
  ##
  ## The file is small and regular, so it is scanned by hand rather than
  ## pulling in a YAML dependency: find the `tokens:` block, then the
  ## softmax.com entry under it.
  let path = getHomeDir() / CredentialsPath
  if not fileExists(path):
    raise newException(XpError, "No credentials at " & path)
  var inTokens = false
  for rawLine in lines(path):
    let line = rawLine
    if not line.startsWith(" ") and line.strip().startsWith("tokens:"):
      inTokens = true
      continue
    if not line.startsWith(" ") and line.strip().len > 0:
      inTokens = false
    if inTokens and "softmax.com/api" in line:
      let parts = line.split(": ")
      if parts.len >= 2:
        return parts[^1].strip()
  raise newException(XpError, "No softmax.com token in " & path)

proc apiCall(
  curl: Curly,
  verb, path: string,
  body = "",
  elevated = false
): string =
  ## Performs one authenticated Observatory call.
  var headers: HttpHeaders
  headers["Authorization"] = "Bearer " & userToken()
  headers["Content-Type"] = "application/json"
  if elevated:
    headers["X-Use-Elevated-Privileges"] = "true"
  let response =
    if verb == "GET":
      curl.get(ApiBase & path, headers, timeout = 120)
    else:
      curl.post(ApiBase & path, headers, body, timeout = 180)
  if response.code >= 300:
    raise newException(
      XpError,
      &"{verb} {path} -> {response.code}: {response.body[0 ..< min(240, response.body.len)]}"
    )
  response.body

proc rosterJson(candidate, baseline: string): JsonNode =
  ## Builds an eight-seat roster: candidate and baseline twice each so
  ## both are measured on the same board, plus the live league field.
  result = newJArray()
  var seats: seq[string] = @[candidate, baseline]
  for name in Field:
    seats.add(name)
  seats.add(candidate)
  # Trim or pad to exactly eight seats.
  while seats.len > 8:
    seats.delete(seats.high)
  var slot = 0
  for name in seats:
    result.add(%*{"player": {"policy_ref": name}, "slot": slot})
    inc slot

proc selfPlayRoster(policy: string): JsonNode =
  ## Eight identical seats. This is what the league's qualification gate
  ## actually runs, and what decides whether a policy can ever become
  ## champion, so it is measured directly rather than inferred from solo
  ## map coverage.
  result = newJArray()
  for slot in 0 ..< 8:
    result.add(%*{"player": {"policy_ref": policy}, "slot": slot})

proc targetCoworldId(): string =
  ## Returns the Coworld to measure against, when one is pinned.
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--coworld="):
      return arg["--coworld=".len .. ^1]
  getEnv("PLANET_WARS_COWORLD_ID")

proc addTarget(body: JsonNode) =
  ## Points one request at a pinned Coworld, or the live league by default.
  ##
  ## `coworld_id` is a top-level request field rather than part of
  ## `target`; the two are alternatives, so only one is ever set.
  let coworld = targetCoworldId()
  if coworld.len > 0:
    body["coworld_id"] = %coworld
  else:
    body["target"] = %*{"league_id": LeagueId}

proc positionalArg(index: int): string =
  ## Returns one positional argument, skipping --flags.
  var seen = 0
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--"):
      continue
    if seen == index:
      return arg
    inc seen
  ""

proc positionalCount(): int =
  ## Returns how many positional arguments were given.
  for i in 1 .. paramCount():
    if not paramStr(i).startsWith("--"):
      inc result

proc createSelfPlay(
  curl: Curly,
  policy: string,
  episodes: int
): string =
  ## Creates one hosted self-play request and returns its id.
  let body = %*{
    "roster": selfPlayRoster(policy),
    "num_episodes": episodes,
    "notes": &"self-play gate probe for {policy}"
  }
  body.addTarget()
  parseJson(curl.apiCall("POST", "/v2/experience-requests", $body))["id"].getStr()

proc reportSelfPlay(episodes: seq[EpisodeScore]) =
  ## Reports the distribution that the gate cares about: how many planets
  ## the leading seat ends with, and how often that reaches a full sweep.
  var tops: seq[int]
  var sweeps = 0
  var survivorTotal = 0
  for episode in episodes:
    if episode.planets.len == 0:
      continue
    var top = 0
    var alive = 0
    for count in episode.planets:
      if count > top:
        top = count
      if count > 0:
        inc alive
    tops.add(top)
    survivorTotal += alive
    if top >= 47:
      inc sweeps
  if tops.len == 0:
    echo "no scored episodes"
    return
  tops.sort(cmp)
  var total = 0
  for value in tops:
    total += value
  echo &"episodes {tops.len}"
  echo &"top seat: mean {total / tops.len:.1f}  median {tops[tops.len div 2]}  best {tops[^1]}"
  echo &"survivors: mean {survivorTotal / tops.len:.1f}"
  echo &"SWEEPS (47 planets): {sweeps}/{tops.len}"
  echo &"tops: {tops}"

proc createRequest(
  curl: Curly,
  candidate, baseline: string,
  episodes: int
): string =
  ## Creates one hosted experience request and returns its id.
  let body = %*{
    "roster": rosterJson(candidate, baseline),
    "num_episodes": episodes,
    "notes": &"paired {candidate} vs {baseline}"
  }
  body.addTarget()
  let raw = curl.apiCall("POST", "/v2/experience-requests", $body)
  let node = parseJson(raw)
  node["id"].getStr()

proc requestStatus(curl: Curly, xreqId: string): tuple[status: string, done, total: int] =
  ## Returns the request status and how many episodes have finished.
  let node = parseJson(curl.apiCall("GET", "/v2/experience-requests/" & xreqId))
  var done = 0
  var total = 0
  if node.hasKey("episodes"):
    for episode in node["episodes"]:
      inc total
      if episode{"status"}.getStr() == "completed":
        inc done
  (node{"status"}.getStr(), done, total)

proc episodeScores(curl: Curly, xreqId: string): seq[EpisodeScore] =
  ## Fetches every completed episode's per-seat scores.
  let rows = parseJson(
    curl.apiCall("GET", "/v2/experience-requests/" & xreqId & "/episodes")
  )
  for row in rows:
    if row{"status"}.getStr() != "completed":
      continue
    let jobId = row{"job_id"}.getStr()
    if jobId.len == 0:
      continue
    var labels: seq[string]
    var participants = row{"participants"}
    if participants != nil:
      var ordered = newSeq[(int, string)]()
      for participant in participants:
        ordered.add((
          participant{"position"}.getInt(),
          participant{"label"}.getStr()
        ))
      ordered.sort(proc (a, b: (int, string)): int = cmp(a[0], b[0]))
      for pair in ordered:
        labels.add(pair[1])
    var artifact: string
    try:
      artifact = curl.apiCall(
        "GET", "/jobs/" & jobId & "/artifacts/results", elevated = true
      )
    except CatchableError:
      continue
    let start = artifact.find('{')
    if start < 0:
      continue
    let results = parseJson(artifact[start .. ^1])
    var scores: seq[int]
    var planets: seq[int]
    for value in results{"scores"}:
      scores.add(value.getInt())
    for value in results{"planets"}:
      planets.add(value.getInt())
    result.add(EpisodeScore(
      episodeId: row{"id"}.getStr(),
      labels: labels,
      scores: scores,
      planets: planets
    ))

proc signTestP(wins, losses: int): float =
  ## Two-sided exact sign test.
  let n = wins + losses
  if n == 0:
    return 1.0
  var tail = 0.0
  let extreme = min(wins, losses)
  for k in 0 .. extreme:
    var term = 1.0
    for i in 0 ..< k:
      term = term * float(n - i) / float(i + 1)
    tail += term
  min(1.0, 2.0 * tail / pow(2.0, float(n)))

proc reportStats(episodes: seq[EpisodeScore], candidate, baseline: string) =
  ## Prints per-policy means and the paired sign test.
  var totals = initTable[string, seq[int]]()
  var wins, losses, ties: int
  for episode in episodes:
    var perLabel = initTable[string, seq[int]]()
    for i, label in episode.labels:
      if i < episode.scores.len:
        totals.mgetOrPut(label, @[]).add(episode.scores[i])
        perLabel.mgetOrPut(label, @[]).add(episode.scores[i])
    if perLabel.hasKey(candidate) and perLabel.hasKey(baseline):
      var candidateMean = 0.0
      for value in perLabel[candidate]:
        candidateMean += float(value)
      candidateMean /= float(perLabel[candidate].len)
      var baselineMean = 0.0
      for value in perLabel[baseline]:
        baselineMean += float(value)
      baselineMean /= float(perLabel[baseline].len)
      if candidateMean > baselineMean:
        inc wins
      elif candidateMean < baselineMean:
        inc losses
      else:
        inc ties

  echo &"episodes scored: {episodes.len}"
  echo &"{\"policy\":44s}{\"seats\":>6s}{\"mean\":>10s}{\"median\":>9s}"
  var names: seq[string]
  for name in totals.keys:
    names.add(name)
  names.sort(proc (a, b: string): int =
    var meanA = 0.0
    for v in totals[a]: meanA += float(v)
    meanA /= float(totals[a].len)
    var meanB = 0.0
    for v in totals[b]: meanB += float(v)
    meanB /= float(totals[b].len)
    cmp(meanB, meanA)
  )
  for name in names:
    var values = totals[name]
    values.sort(cmp)
    var mean = 0.0
    for v in values: mean += float(v)
    mean /= float(values.len)
    echo &"{name:44s}{values.len:>6d}{mean:>10.0f}{values[values.len div 2]:>9d}"

  if wins + losses + ties > 0:
    let p = signTestP(wins, losses)
    let verdict = if p < 0.05: "SIGNIFICANT" else: "not significant"
    echo ""
    echo &"{candidate} vs {baseline}: {wins}W-{losses}L-{ties}T  sign-test p={p:.4f}  {verdict}"

proc main() =
  let curl = newCurly()
  defer: curl.close()
  if positionalCount() < 1:
    echo "usage: xp [--coworld=<id>] run <cand> <base> [eps] | selfplay <policy> [eps] | watch <id> | gate <id>... | stats <id>..."
    quit(1)
  case positionalArg(0)
  of "run":
    if positionalCount() < 3:
      raise newException(XpError, "run needs <candidate> <baseline>")
    let episodes =
      if positionalCount() >= 4: parseInt(positionalArg(3)) else: 20
    let xreqId =
      curl.createRequest(positionalArg(1), positionalArg(2), episodes)
    echo "created ", xreqId, " with ", episodes, " episodes"
  of "watch":
    let xreqId = positionalArg(1)
    while true:
      let state = curl.requestStatus(xreqId)
      echo &"{state.status} {state.done}/{state.total}"
      if state.status in ["completed", "failed", "cancelled"]:
        break
      sleep(30_000)
  of "selfplay":
    if positionalCount() < 2:
      raise newException(XpError, "selfplay needs <policy>")
    let episodes =
      if positionalCount() >= 3: parseInt(positionalArg(2)) else: 12
    echo "created ", curl.createSelfPlay(positionalArg(1), episodes),
      " with ", episodes, " self-play episodes"
  of "gate":
    var episodes: seq[EpisodeScore]
    for i in 1 ..< positionalCount():
      episodes.add(curl.episodeScores(positionalArg(i)))
    reportSelfPlay(episodes)
  of "stats":
    var episodes: seq[EpisodeScore]
    for i in 1 ..< positionalCount():
      episodes.add(curl.episodeScores(positionalArg(i)))
    if episodes.len == 0:
      echo "no completed episodes"
      quit(1)
    var candidate = ""
    var baseline = ""
    for label in episodes[0].labels:
      if label.startsWith("skurge:"):
        if candidate.len == 0:
          candidate = label
        elif label != candidate and baseline.len == 0:
          baseline = label
    if baseline.len == 0:
      baseline = "planet-wars-skurge:v1"
    reportStats(episodes, candidate, baseline)
  else:
    raise newException(XpError, "unknown command " & positionalArg(0))

when isMainModule:
  main()
