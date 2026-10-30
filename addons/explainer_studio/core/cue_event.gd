@tool
class_name CueEvent
extends RefCounted
## Runtime payload handed to cue receivers like [CaptionRevealer] and [Callout].
##
## The [Director] builds one per fired cue. [member remaining] is the budget left
## in the shot, so UI can animate on the same clock as the camera and settle
## exactly when the move does (M2 sequencing rule).

## The authored cue.
var cue: Cue

## Shot that owns the cue.
var shot: Shot

## Index of the owning shot in the playing sequence.
var shot_index: int = -1

## Full duration of the owning shot, in seconds.
var shot_duration: float = 0.0

## Clamped cue time inside the shot, in seconds.
var elapsed: float = 0.0

## Time left in the shot when the cue fired, in seconds. Never negative.
var remaining: float = 0.0


## Payload lookup with a default.
func get_data(key: String, default_value: Variant = null) -> Variant:
	if cue == null:
		return default_value
	return cue.get_data(key, default_value)


## Reveal/animation budget for this cue: the requested duration clamped to
## [member remaining]. A negative or missing request uses the full budget.
func get_budget(requested: float) -> float:
	if requested < 0.0:
		return remaining
	return minf(requested, remaining)
