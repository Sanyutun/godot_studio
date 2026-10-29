@tool
class_name Shot
extends Resource
## One cinematic move inside a [Sequence].
##
## A shot is plain data: where the [ExplainerCamera] should be at the end of
## [member duration], how it should get there, and which [Cue]s fire on the way.
## Everything serializes to `.tres`, so shot lists are diffable and editable.

## Camera move kinds. Integer values match the inspector dropdown order.
enum Kind {
	MOVE,       ## Move position and zoom to the target.
	PUNCH_IN,   ## Emphasise by zooming in (optionally towards a target).
	PUNCH_OUT,  ## Release emphasis by zooming out (optionally towards a target).
	PAN,        ## Move position only; zoom is left untouched.
	FIT_RECT,   ## Frame [member rect] using the camera's fit padding.
	DRIFT,      ## Slow move + zoom for ambient motion; author long durations.
	HOLD,       ## No camera motion; waits for [member duration].
}

const KIND_NAMES: Array[String] = [
	"move", "punch_in", "punch_out", "pan", "fit_rect", "drift", "hold",
]

## Move kind. See [enum Kind] for the semantics of each value.
@export_enum("move", "punch_in", "punch_out", "pan", "fit_rect", "drift", "hold")
var kind: int = Kind.MOVE

## What to look at. Resolved relative to the [ExplainerCamera]. Optional; when
## empty the camera keeps its current position for shots that only zoom.
@export var target: NodePath

## World-space rectangle framed by [constant Kind.FIT_RECT], in pixels.
## When left empty the camera's current view is used.
@export var rect: Rect2 = Rect2()

## Absolute target zoom, where `1.0` is the unzoomed viewport.
@export_range(0.05, 20.0, 0.05, "or_greater") var zoom: float = 1.0

## Duration in seconds. [constant Kind.HOLD] uses this as its wait time.
@export_range(0.0, 600.0, 0.01, "or_greater", "suffix:s")
var duration: float = 1.0

## Easing curve applied to the camera tween.
@export var ease: Tween.EaseType = Tween.EASE_OUT

## Interpolation curve applied to the camera tween.
@export var trans: Tween.TransitionType = Tween.TRANS_CUBIC

## Cues fired relative to the start of this shot. The [Director] clamps their
## times to `[0, duration]` and fires them on the camera's clock.
@export var cues: Array[Cue] = []


## Lowercase name of [member kind], matching the inspector labels.
func get_kind_name() -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return "unknown"
	return KIND_NAMES[kind]


## Whether this shot actually moves the camera.
func has_motion() -> bool:
	return kind != Kind.HOLD


## Clamped, non-negative duration in seconds.
func get_safe_duration() -> float:
	return maxf(duration, 0.0)
