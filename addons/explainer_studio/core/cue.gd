@tool
class_name Cue
extends Resource
## A timed event that belongs to a [Shot].
##
## Cues are the only channel between timing (Director) and presentation (UI,
## audio, custom receivers). A cue fires once, at [member time] seconds after
## its shot starts; [Director] clamps the time into the shot's bounds.

## Typewriter/fade caption reveal. See `ui/caption_revealer.gd` (M2).
const ACTION_CAPTION: StringName = &"caption"
## World-anchored annotation bubble. See `ui/callout.gd` (M2).
const ACTION_CALLOUT: StringName = &"callout"
## Title card. See `ui/lower_third.gd` (M2).
const ACTION_LOWER_THIRD: StringName = &"lower_third"

## Time in seconds, relative to the start of the owning shot.
@export_range(0.0, 600.0, 0.01, "or_greater", "suffix:s")
var time: float = 0.0

## Action name. Use the `ACTION_*` constants or any custom string.
@export var action: StringName = ACTION_CAPTION

## Receiver node. Resolved against the [Director] first, then the scene root.
## Optional: [signal Director.cue_fired] always fires regardless.
@export var target: NodePath

## Free-form payload for the receiver (text, style overrides, ...).
@export var data: Dictionary = {}


## Payload lookup with a typed default.
func get_data(key: String, default_value: Variant = null) -> Variant:
	return data.get(key, default_value)


## Whether [member action] is one of the built-in explainer actions.
func is_known_action() -> bool:
	return action in [ACTION_CAPTION, ACTION_CALLOUT, ACTION_LOWER_THIRD]
