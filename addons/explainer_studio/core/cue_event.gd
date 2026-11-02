@tool
class_name CueEvent
extends RefCounted
## Runtime payload handed to cue receivers like [CaptionRevealer] and [Callout].
##
## The [Director] builds one per fired cue. [member remaining] is the budget left
## in the shot, so UI can animate on the same clock as the camera and settle
## exactly when the move does (M2–M3 sequencing rule).

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


## Resolves the full reveal/hold/dismiss lifetime for a UI cue so the card is
## gone when the camera settles.
##
## Returns a [Dictionary] with `reveal`, `hold` and `dismiss` in seconds.
## Cue `data` keys `reveal`, `hold` and `dismiss` override the receiver defaults;
## a missing `hold` runs up to the dismiss window. Reveal is clamped to
## [member remaining], then dismiss is clamped to whatever is left, and hold
## fills the rest.
func get_lifetime(reveal_default: float, dismiss_default: float) -> Dictionary:
	var budget := maxf(remaining, 0.0)
	var reveal := clampf(float(get_data("reveal", reveal_default)), 0.0, budget)
	var dismiss := clampf(
		float(get_data("dismiss", dismiss_default)), 0.0, maxf(budget - reveal, 0.0)
	)
	var hold := clampf(
		float(get_data("hold", budget)), reveal, maxf(budget - dismiss, reveal)
	)
	return {"reveal": reveal, "hold": hold, "dismiss": dismiss}
