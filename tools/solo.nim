## Solo conquest benchmark for Planet Wars.
##
## Runs skurge alone against a map of neutrals and reports how much of it
## it takes, and how fast. The target is a full sweep: all planets owned.
##
##   solo <serverBinary> <botBinary> [seeds] [ticks] [speed]
##
## Each seed is an independent map. The clock runs at `speed` times real
## time, which changes only how long a run takes to watch: the simulation
## is fixed-step, so results are identical to a real-time run.

import
  std/[algorithm, json, math, os, osproc, streams, strformat,
    strtabs, strutils]

const
  BasePort = 8400
  PollMilliseconds = 200
  StartupMilliseconds = 400
  TargetFps = 60

type
  RunResult = object
    seed: int
    planets: int
    score: int
    sweptAtTick: int

proc readResult(path: string, seed: int): RunResult =
  ## Reads one finished game's result file.
  result = RunResult(seed: seed, planets: -1, score: -1, sweptAtTick: -1)
  if not fileExists(path):
    return
  let node = parseJson(readFile(path))
  if node.hasKey("planets") and node["planets"].len > 0:
    result.planets = node["planets"][0].getInt()
  if node.hasKey("scores") and node["scores"].len > 0:
    result.score = node["scores"][0].getInt()

proc runOne(
  serverBinary, botBinary, workDir: string,
  seed, ticks, speed, planetCount, index: int
): RunResult =
  ## Runs one solo game and returns what the bot ended with.
  let
    port = BasePort + (index mod 40)
    resultsPath = workDir / &"result_{seed}.json"
    config = &"""{{"seed":{seed},"maxGames":1,"maxTicks":{ticks},""" &
      &""""num_agents":1,"planetCount":{planetCount}}}"""
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
    options = {poStdErrToStdOut, poUsePath}
  )
  sleep(StartupMilliseconds)
  let bot = startProcess(
    botBinary,
    args = @[&"--address:127.0.0.1", &"--port:{port}", "--name:skurge"],
    options = {poStdErrToStdOut}
  )
  # A run cannot outlast its own tick budget by much, so cap the wait
  # rather than trusting the processes to exit.
  let budgetMilliseconds = (ticks * 1000) div (TargetFps * max(1, speed))
  var waited = 0
  while waited < budgetMilliseconds + 8000:
    if fileExists(resultsPath):
      break
    sleep(PollMilliseconds)
    waited += PollMilliseconds
  sleep(PollMilliseconds)
  result = readResult(resultsPath, seed)
  bot.terminate()
  server.terminate()
  discard bot.waitForExit()
  discard server.waitForExit()
  # Read the bot's output only after it has exited, so the stream is at
  # EOF and the read cannot block.
  for line in bot.outputStream.readAll().splitLines():
    if line.startsWith("SWEEP tick="):
      let rest = line["SWEEP tick=".len .. ^1]
      result.sweptAtTick = parseInt(rest.split(' ')[0])
      break

proc report(results: seq[RunResult], planetCount: int) =
  ## Prints the distribution that matters: how close to a full sweep.
  var
    counts: seq[int]
    sweeps = 0
    total = 0
  for item in results:
    if item.planets < 0:
      continue
    counts.add(item.planets)
    total += item.planets
    if item.planets >= planetCount:
      inc sweeps
  if counts.len == 0:
    echo "no completed runs"
    return
  var sweepTicks: seq[int]
  for item in results:
    if item.sweptAtTick >= 0:
      sweepTicks.add(item.sweptAtTick)
  counts.sort(cmp)
  echo ""
  echo &"runs {counts.len} of {results.len}"
  echo &"planets: mean {total / counts.len:.1f}  median " &
    &"{counts[counts.len div 2]}  worst {counts[0]}  best {counts[^1]}"
  echo &"SWEEPS ({planetCount} planets): {sweeps}/{counts.len}"
  echo &"all: {counts}"
  if sweepTicks.len > 0:
    sweepTicks.sort(cmp)
    var sweepTotal = 0
    for value in sweepTicks:
      sweepTotal += value
    echo &"sweep time: mean {sweepTotal / sweepTicks.len / TargetFps:.1f}s" &
      &"  best {sweepTicks[0] / TargetFps:.1f}s" &
      &"  worst {sweepTicks[^1] / TargetFps:.1f}s"

proc main() =
  if paramCount() < 2:
    echo "usage: solo <serverBinary> <botBinary> [seeds] [ticks] [speed]"
    quit(1)
  let
    serverBinary = paramStr(1)
    botBinary = paramStr(2)
    seeds = if paramCount() >= 3: parseInt(paramStr(3)) else: 8
    ticks = if paramCount() >= 4: parseInt(paramStr(4)) else: 7200
    speed = if paramCount() >= 5: parseInt(paramStr(5)) else: 8
    planetCount = 47
    workDir = getTempDir() / "planet_wars_solo"
  createDir(workDir)
  echo &"solo: {seeds} seeds, {ticks} ticks, {speed}x clock"
  var results: seq[RunResult]
  for index in 0 ..< seeds:
    let seed = 1000 + index * 37
    let item = runOne(
      serverBinary, botBinary, workDir,
      seed, ticks, speed, planetCount, index
    )
    results.add(item)
    let sweepText =
      if item.sweptAtTick >= 0:
        &"swept at tick {item.sweptAtTick} " &
          &"({item.sweptAtTick / TargetFps:.1f}s)"
      else:
        "no sweep"
    echo &"seed {seed}: planets {item.planets} score {item.score} {sweepText}"
  report(results, planetCount)

when isMainModule:
  main()
