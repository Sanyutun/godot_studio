extends Node
## Minimal, runnable example of the M1 runtime API.
##
## Attach to a Node in a scene that also contains an [ExplainerCamera] named
## `ExplainerCamera`, then press Play. It is intentionally not part of the M1
## demo scene so the example stays a copy-paste starting point.

## Sequence to play. When empty, a two-shot example is generated at runtime.
@export var sequence: Sequence

@onready var _director: Director = $Director
@onready var _camera: ExplainerCamera = $ExplainerCamera


func _ready() -> void:
	_director.camera = _camera
	_director.shot_started.connect(_on_shot_started)
	_director.cue_fired.connect(_on_cue_fired)

	var take := sequence
	if take == null:
		take = _build_example_sequence()

	await _director.play(take)
	print("[example] take finished")


func _build_example_sequence() -> Sequence:
	var take := Sequence.new()
	take.display_name = "example · punch in / out"

	var punch_in := Shot.new()
	punch_in.kind = Shot.Kind.PUNCH_IN
	punch_in.target = NodePath("../Card")
	punch_in.zoom = 2.0
	punch_in.duration = 1.5
	punch_in.cues = [_cue(0.4, Cue.ACTION_CAPTION, "Zoomed in")]
	take.add_shot(punch_in)

	var punch_out := Shot.new()
	punch_out.kind = Shot.Kind.PUNCH_OUT
	punch_out.zoom = 1.0
	punch_out.duration = 1.0
	take.add_shot(punch_out)
	return take


func _cue(time: float, action: StringName, note: String) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = action
	cue.data = {"note": note}
	return cue


func _on_shot_started(index: int, shot: Shot) -> void:
	print("[example] shot %d/%d: %s" % [index + 1, _director.get_sequence().shots.size(), shot.get_kind_name()])


func _on_cue_fired(cue: Cue, shot_index: int) -> void:
	print("[example] cue '%s' in shot %d: %s" % [cue.action, shot_index, cue.get_data("note", "")])
