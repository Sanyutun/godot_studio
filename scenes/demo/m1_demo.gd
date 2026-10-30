extends Node2D
## M1 demo: a five-shot sequence over placeholder art.
##
## Run windowed:   godot scenes/demo/m1_shots.tscn
## Run headless:   godot --headless scenes/demo/m1_shots.tscn --quit-after 800
## Quit on end:    godot --headless scenes/demo/m1_shots.tscn -- --quit-on-finish

## Start playing automatically on `_ready`.
@export var autoplay: bool = true
## Restart the take after a short pause so the demo can be watched unattended.
@export var loop: bool = true

@onready var camera: ExplainerCamera = $ExplainerCamera
@onready var director: Director = $Director
@onready var status_label: Label = $HUD/Status

var _sequence: Sequence
var _quit_on_finish: bool = false


func _ready() -> void:
	_quit_on_finish = OS.get_cmdline_user_args().has("--quit-on-finish")
	director.camera = camera
	director.shot_started.connect(_on_shot_started)
	director.shot_finished.connect(_on_shot_finished)
	director.cue_fired.connect(_on_cue_fired)
	director.sequence_finished.connect(_on_sequence_finished)

	_sequence = _build_sequence()
	var issues := _sequence.validate()
	for issue in issues:
		push_warning("[M1] %s" % issue)
	print(
		"[M1] '%s': %d shots, %.2fs total"
		% [_sequence.display_name, _sequence.shots.size(), _sequence.get_total_duration()]
	)
	if autoplay:
		director.play(_sequence)


func _build_sequence() -> Sequence:
	var take := Sequence.new()
	take.display_name = "M1 · five-shot tour"

	var opening := Shot.new()
	opening.kind = Shot.Kind.HOLD
	opening.duration = 1.2
	opening.cues = [
		_make_cue(0.1, Cue.ACTION_LOWER_THIRD, "title: three features"),
		_caption_cue(0.3, "Three features. One take."),
	]

	var punch := Shot.new()
	punch.kind = Shot.Kind.PUNCH_IN
	punch.target = NodePath("../World/CardA")
	punch.zoom = 2.1
	punch.duration = 2.2
	punch.ease = Tween.EASE_OUT
	punch.trans = Tween.TRANS_CUBIC
	punch.cues = [
		_callout_cue(0.25, "CalloutA", "Feature A — crisp punch-in", "../../World/CardA", 1.8),
		_caption_cue(1.3, "Fast, deterministic camera moves", "fade_up"),
	]

	var pan := Shot.new()
	pan.kind = Shot.Kind.PAN
	pan.target = NodePath("../World/CardB")
	pan.duration = 2.2
	pan.ease = Tween.EASE_IN_OUT
	pan.trans = Tween.TRANS_SINE
	pan.cues = [
		_callout_cue(0.5, "CalloutB", "Feature B — pan on rails", "../../World/CardB", 1.5),
	]

	var fit := Shot.new()
	fit.kind = Shot.Kind.FIT_RECT
	fit.rect = Rect2(340.0, 360.0, 1240.0, 400.0)
	fit.duration = 2.8
	fit.ease = Tween.EASE_IN_OUT
	fit.trans = Tween.TRANS_QUINT
	fit.cues = [
		_caption_cue(0.1, "Every feature framed by one fit_rect", "slide_left"),
		_callout_cue(1.1, "CalloutA", "Fit keeps the whole grid in frame", "../../World/CardC", 1.4),
	]

	var release := Shot.new()
	release.kind = Shot.Kind.PUNCH_OUT
	release.zoom = 1.0
	release.duration = 2.4
	release.ease = Tween.EASE_IN_OUT
	release.trans = Tween.TRANS_CUBIC
	release.cues = [
		_hide_callout_cue(0.1, "CalloutA"),
		_hide_callout_cue(0.1, "CalloutB"),
		_caption_cue(0.5, "Captions and callouts share the camera clock"),
		_make_cue(1.2, Cue.ACTION_LOWER_THIRD, "title: outro"),
	]

	take.add_shot(opening)
	take.add_shot(punch)
	take.add_shot(pan)
	take.add_shot(fit)
	take.add_shot(release)
	return take


func _make_cue(time: float, action: StringName, note: String, data: Dictionary = {}) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = action
	var payload := data.duplicate()
	payload["note"] = note
	cue.data = payload
	return cue


func _caption_cue(time: float, text: String, caption_mode: String = "typewriter") -> Cue:
	var cue := _make_cue(time, Cue.ACTION_CAPTION, text, {"text": text, "mode": caption_mode})
	cue.target = NodePath("../HUD/Caption")
	return cue


func _callout_cue(
	time: float,
	target_name: String,
	text: String,
	anchor_path: String,
	hold: float,
	reveal: float = 0.3
) -> Cue:
	var cue := _make_cue(time, Cue.ACTION_CALLOUT, text, {
		"text": text,
		"anchor": NodePath(anchor_path),
		"hold": hold,
		"reveal": reveal,
	})
	cue.target = NodePath("../HUD/%s" % target_name)
	return cue


func _hide_callout_cue(time: float, target_name: String, duration: float = 0.2) -> Cue:
	var cue := _make_cue(time, Cue.ACTION_CALLOUT, "hide %s" % target_name, {
		"hide": true,
		"duration": duration,
	})
	cue.target = NodePath("../HUD/%s" % target_name)
	return cue


func _on_shot_started(index: int, shot: Shot) -> void:
	status_label.text = "Shot %d/%d · %s · %.1fs" % [
		index + 1, _sequence.shots.size(), shot.get_kind_name(), shot.duration,
	]
	print("[M1] shot %d/%d start: %s (%.1fs)" % [index + 1, _sequence.shots.size(), shot.get_kind_name(), shot.duration])


func _on_shot_finished(index: int, shot: Shot) -> void:
	var elapsed := _sequence.get_shot_start_time(index) + shot.duration
	print("[M1] shot %d done at %05.2fs" % [index + 1, elapsed])


func _on_cue_fired(cue: Cue, shot_index: int) -> void:
	print("[M1] cue '%s' @ shot %d: %s" % [cue.action, shot_index, cue.get_data("note", "")])


func _on_sequence_finished(finished_sequence: Sequence) -> void:
	print("[M1] sequence finished: %s (%.2fs)" % [finished_sequence.display_name, finished_sequence.get_total_duration()])
	status_label.text = "Take complete · %.1fs" % finished_sequence.get_total_duration()
	if _quit_on_finish:
		get_tree().quit()
		return
	if loop:
		status_label.text += " · restarting…"
		get_tree().create_timer(1.0).timeout.connect(_restart)


func _restart() -> void:
	director.play(_sequence)
