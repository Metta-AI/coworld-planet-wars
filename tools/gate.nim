## Local qualification-gate probe for Planet Wars.
##
## The league gate runs eight identical clones on one map and only passes
## a policy if one of them finishes owning every planet. That is a tail
## event, not a strength test: eight identical deterministic bots rank an
## identical board identically and settle into an even split, which is
## exactly what the gate rejects.
##
## This measures the thing the gate scores — how often *some* seat sweeps,
## and how high the best seat reaches — so a change can be judged on tail
## probability rather than on mean strength.
##
##   gate <serverBinary> <botBinary> [seeds] [ticks] [speed] [seats]

import
  std/[algorithm, json, math, os, osproc, strformat, strtabs, strutils]

const
  BasePort = 8500
  PollMilliseconds = 250
  StartupMilliseconds = 600
  BotStaggerMilliseconds = 60
  TargetFps = 60
  PlanetCount = 47

type
  GateRun = object
    seed: int
    topSeat: int
    swept: bool
    survivors: int

proc readRun(path: string, seed: int): GateRun =
  ## Reads one finished episode and returns what the best seat managed.
  result = GateRun(seed: seed, topSeat: -1, swept: false, survivors: 0)
  if not fileExists(path):
    return
  let node = parseJson(readFile(path))
  if not node.hasKey("planets"):
    return
  for entry in node["planets"]:
    let held = entry.getInt()
    if held > result.topSeat:
      result.topSeat = held
    if held > 0:
      inc result.survivors
  result.swept = result.topSeat >= PlanetCount

proc runOne(
  serverBinary, botBinary, workDir: string,
  seed, ticks, speed, seats, index: int
): GateRun =
  ## Runs one eight-clone self-play episode.
  let
    port = BasePort + (index mod 40)
    resultsPath = workDir / &"gate_{seed}.json"
    config = &"""{{"seed":{seed},"maxGames":1,"maxTicks":{ticks},""" &
      &""""num_agents":{seats},"planetCount":{PlanetCount}}}"""
  removeFile(resultsPath)
  let server = startProcess(
    serverBinary,
    args = @[
      &"--host:127.0.0.1",
      &"--port:{port}",
      &"--config:{config}",
      &"--results:{resultsPath}"
    ],
    env = newStringTable({"PLANET_WARS_SPEED": $speed}),
    options = {poStdErrToStdOut}
  )
  sleep(StartupMilliseconds)
  var bots: seq[Process]
  for seat in 0 ..< seats:
    bots.add(startProcess(
      botBinary,
      args = @[
        &"--address:127.0.0.1", &"--port:{port}", &"--name:seat{seat}"
      ],
      options = {poStdErrToStdOut}
    ))
    # Clones seed their RNG from the clock and their pid, so they need to
    # start at distinguishable moments to draw different jitter.
    sleep(BotStaggerMilliseconds)
  # The old game holds a waiting lobby until every seat has joined, so
  # the tick budget starts late; allow generously for it.
  let budgetMilliseconds = (ticks * 1000) div (TargetFps * max(1, speed))
  var waited = 0
  while waited < budgetMilliseconds + 90000:
    if fileExists(resultsPath):
      break
    sleep(PollMilliseconds)
    waited += PollMilliseconds
  sleep(PollMilliseconds)
  result = readRun(resultsPath, seed)
  for bot in bots:
    bot.terminate()
  server.terminate()
  for bot in bots:
    discard bot.waitForExit()
  discard server.waitForExit()

proc report(runs: seq[GateRun]) =
  ## Reports the tail, which is the only thing the gate cares about.
  var
    tops: seq[int]
    sweeps = 0
    survivorTotal = 0
  for run in runs:
    if run.topSeat < 0:
      continue
    tops.add(run.topSeat)
    survivorTotal += run.survivors
    if run.swept:
      inc sweeps
  if tops.len == 0:
    echo "no completed episodes"
    return
  tops.sort(cmp)
  var total = 0
  for value in tops:
    total += value
  echo ""
  echo &"episodes {tops.len} of {runs.len}"
  echo &"top seat: mean {total / tops.len:.1f}  median " &
    &"{tops[tops.len div 2]}  best {tops[^1]}"
  echo &"survivors: mean {survivorTotal / tops.len:.1f}"
  echo &"SWEEPS ({PlanetCount} planets): {sweeps}/{tops.len}"
  echo &"tops: {tops}"

proc main() =
  if paramCount() < 2:
    echo "usage: gate <serverBinary> <botBinary> [seeds] [ticks] [speed] [seats]"
    quit(1)
  let
    serverBinary = paramStr(1)
    botBinary = paramStr(2)
    seeds = if paramCount() >= 3: parseInt(paramStr(3)) else: 8
    ticks = if paramCount() >= 4: parseInt(paramStr(4)) else: 10800
    speed = if paramCount() >= 5: parseInt(paramStr(5)) else: 6
    seats = if paramCount() >= 6: parseInt(paramStr(6)) else: 8
    workDir = getTempDir() / "planet_wars_gate"
  createDir(workDir)
  echo &"gate: {seeds} episodes, {seats} seats, {ticks} ticks, {speed}x"
  var runs: seq[GateRun]
  for index in 0 ..< seeds:
    let seed = 5000 + index * 91
    let run = runOne(
      serverBinary, botBinary, workDir, seed, ticks, speed, seats, index
    )
    runs.add(run)
    echo &"seed {seed}: top {run.topSeat} survivors {run.survivors} " &
      (if run.swept: "SWEEP" else: "")
  report(runs)

when isMainModule:
  main()
