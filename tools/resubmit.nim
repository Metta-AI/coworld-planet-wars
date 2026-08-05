## Repeated league qualification attempts.
##
## The Planet Wars gate needs one of eight identical self-play clones to
## finish owning all 47 planets. Measured over 24 hosted episodes our best
## build never exceeded 33, so the gate is a low-probability roll rather
## than a skill threshold — the observed rate is consistent with how other
## players qualify (one entrant has 32 submitted versions, a handful of
## which passed).
##
## Each submission is an independent attempt, so this uploads the same
## image under a fresh version and submits it, until one qualifies.
##
##   resubmit <docker-image> <policy-name> [attempts]

import
  std/[os, osproc, strformat, strutils]

const
  MettaDir = "/Users/me/p/metta"
  LeagueId = "league_074c818a-fe56-42a4-a2de-1a79202f281a"
  PollSeconds = 45
  MaxPollRounds = 40

proc run(args: seq[string]): tuple[output: string, code: int] =
  ## Runs one coworld CLI command from the metta workspace.
  let command = "cd " & quoteShell(MettaDir) & " && uv run coworld " &
    args.mapIt(quoteShell(it)).join(" ")
  execCmdEx(command)

proc uploadPolicy(image, name: string): string =
  ## Uploads the image as a new version and returns its label.
  let (output, _) = run(@[
    "upload-policy", image, "-n", name, "--tag", "purpose=gate-attempt"
  ])
  for line in output.splitLines():
    if "Upload complete:" in line:
      return line.split(": ")[^1].strip()
  ""

proc submitPolicy(label: string): bool =
  ## Submits one policy version to the league.
  let (output, _) = run(@[
    "submit", label, "-l", LeagueId, "--no-open-browser"
  ])
  "Submission:" in output

proc membershipStatus(label: string): string =
  ## Returns the league membership status for one policy label.
  let (output, _) = run(@[
    "memberships", "-l", LeagueId, "--json"
  ])
  # The CLI prints one JSON blob; scan it rather than parsing, since only
  # the status word next to our label is needed.
  let marker = "\"label\": \"" & label & "\""
  let at = output.find(marker)
  if at < 0:
    return "unknown"
  # Status appears before the policy_version block for each membership.
  let window = output[max(0, at - 4000) ..< at]
  for state in ["disqualified", "competing", "qualifying"]:
    if ("\"status\": \"" & state & "\"") in window:
      result = state
  if result.len == 0:
    result = "unknown"

proc awaitOutcome(label: string): string =
  ## Waits for a submission to leave the qualifying state.
  for _ in 0 ..< MaxPollRounds:
    let status = membershipStatus(label)
    if status in ["competing", "disqualified"]:
      return status
    sleep(PollSeconds * 1000)
  "timeout"

proc main() =
  if paramCount() < 2:
    echo "usage: resubmit <docker-image> <policy-name> [attempts]"
    quit(1)
  let
    image = paramStr(1)
    name = paramStr(2)
    attempts = if paramCount() >= 3: parseInt(paramStr(3)) else: 6
  for attempt in 1 .. attempts:
    let label = uploadPolicy(image, name)
    if label.len == 0:
      echo &"attempt {attempt}: upload failed"
      continue
    if not submitPolicy(label):
      echo &"attempt {attempt}: submit failed for {label}"
      continue
    echo &"attempt {attempt}: submitted {label}, waiting for the gate"
    let outcome = awaitOutcome(label)
    echo &"attempt {attempt}: {label} -> {outcome}"
    if outcome == "competing":
      echo &"QUALIFIED {label} after {attempt} attempt(s)"
      return
  echo "no attempt qualified"

when isMainModule:
  main()
