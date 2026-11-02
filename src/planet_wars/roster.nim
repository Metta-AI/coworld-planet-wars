## Protocol roster identities are independent of native simulation order.
import std/json
import sim

const InvalidRosterSlot* = -2

proc resolveRosterSlot*(
  requested: int,
  token: string,
  tokens: openArray[string],
  capacity: int
): int =
  ## A token-only client has the same identity as its configured roster slot.
  if requested < -1 or requested >= capacity:
    return InvalidRosterSlot
  if tokens.len == 0:
    return requested
  if requested >= 0:
    if requested < tokens.len and tokens[requested] == token:
      return requested
    return InvalidRosterSlot
  result = InvalidRosterSlot
  for slot, configured in tokens:
    if configured == token:
      if result != InvalidRosterSlot or slot >= capacity:
        return InvalidRosterSlot
      result = slot

proc availableRosterSlot*(occupied: openArray[int], capacity: int): int =
  ## Allocate anonymous local clients without reusing an episode identity.
  for slot in 0 ..< capacity:
    if slot notin occupied:
      return slot
  InvalidRosterSlot

proc rosterResultsJson*(
  simulation: SimServer,
  slots: openArray[int],
  expectedCount = 0
): string =
  ## Export every per-player field in the submitted roster's order.
  if slots.len != simulation.players.len:
    raise newException(ValueError, "native player/roster mapping is incomplete")
  if expectedCount < 0 or expectedCount > MaxPlanetCount:
    raise newException(ValueError, "invalid result roster size")
  var count = max(expectedCount, slots.len)
  var claimed: array[MaxPlanetCount, bool]
  for slot in slots:
    if slot < 0 or slot >= MaxPlanetCount or claimed[slot]:
      raise newException(ValueError, "invalid or duplicate result roster slot")
    claimed[slot] = true
    count = max(count, slot + 1)
  let native = parseJson(simulation.playerScoresJson())
  var ordered = newJObject()
  for key, value in native:
    ordered[key] = value
  for key in ["names", "scores", "win", "planets", "ships"]:
    var values = newJArray()
    for slot in 0 ..< count:
      case key
      of "names": values.add(%"")
      of "win": values.add(%false)
      else: values.add(%0)
    for nativeIndex, slot in slots:
      values.elems[slot] = native[key][nativeIndex]
    ordered[key] = values
  $ordered
