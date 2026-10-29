@tool
class_name Director
extends Node
## Executes a [Sequence] on an [ExplainerCamera] and fires its [Cue]s on schedule.
##
## Everything outside the camera layer talks to this node: UI, rendering and the
## editor dock never animate the camera directly. [method play] is a coroutine —
## `await director.play(sequence)` waits for the whole take.
##
## Cue times are clamped to `[0, shot.duration]` and scheduled on a tween that
## starts with the camera shot, so UI lands on the same clock as the move (M2).

signal sequence_started(sequence: Sequence)
signal sequence_finished(sequence: Sequence)
signal sequence_stopped(sequence: Sequence)
signal shot_started(index: int, shot: Shot)
signal shot_finished(index: int, shot: Shot)
signal cue_fired(cue: Cue, shot_index: int)
signal playback_changed(playing: bool)

## Camera to drive. When unset, [method _resolve_camera] falls back to
## [member camera_path], a child named `ExplainerCamera`, or the camera group.
@export var camera: ExplainerCamera

## Optional fallback for [member camera], as a NodePath relative to this node.
@export var camera_path: NodePath

## Play [member autoplay_sequence] when the scene enters the tree.
@export var autoplay: bool = false

## Sequence used by [member autoplay].
@export var autoplay_sequence: Sequence

var _sequence: Sequence = null
var _playing: bool = false
var _shot_index: int = -1
var _run_id: int = 0
var _cue_tween: Tween = null


func _ready() -> void:
	if camera == null:
		camera = _resolve_camera()
	if autoplay and autoplay_sequence != null:
		play.call_deferred(autoplay_sequence)


## Plays [param sequence] from the first shot. Await the call to block until the
## take ends; call [method stop] to cancel it early.
func play(sequence: Sequence) -> void:
	if sequence == null:
		push_error("Director.play(): sequence is null.")
		return
	stop()
	_run_id += 1
	var run_id := _run_id
	_sequence = sequence
	_playing = true
	playback_changed.emit(true)
	sequence_started.emit(sequence)

	for index in sequence.shots.size():
		if run_id != _run_id:
			return
		var shot := sequence.shots[index]
		if shot == null:
			continue
		_shot_index = index
		await _play_shot(shot, index, run_id)

	if run_id != _run_id:
		return
	_playing = false
	_shot_index = -1
	playback_changed.emit(false)
	sequence_finished.emit(sequence)


## Cancels playback, aborts the camera move and clears the active cue tween.
func stop() -> void:
	_run_id += 1
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = null
	if camera != null:
		camera.abort()
	var was_playing := _playing
	var stopped_sequence := _sequence
	_playing = false
	_shot_index = -1
	_sequence = null
	if was_playing:
		playback_changed.emit(false)
		if stopped_sequence != null:
			sequence_stopped.emit(stopped_sequence)


## Whether a take is running.
func is_playing() -> bool:
	return _playing


## Index of the currently playing shot, or `-1` when idle.
func get_shot_index() -> int:
	return _shot_index


## Sequence currently playing (or most recently played), or `null`.
func get_sequence() -> Sequence:
	return _sequence


## Total duration of the active sequence in seconds.
func get_total_duration() -> float:
	if _sequence == null:
		return 0.0
	return _sequence.get_total_duration()


## Start time of the shot at [param index] in the active sequence, in seconds.
func get_shot_start_time(index: int) -> float:
	if _sequence == null:
		return 0.0
	return _sequence.get_shot_start_time(index)


## Clamps a cue time into a shot's bounds. Exposed for the dock and tests.
static func clamp_cue_time(time: float, duration: float) -> float:
	return clampf(time, 0.0, maxf(duration, 0.0))


func _play_shot(shot: Shot, index: int, run_id: int) -> void:
	shot_started.emit(index, shot)
	_schedule_cues(shot, index)

	var active_camera := _resolve_camera()
	if active_camera == null:
		if is_inside_tree():
			await get_tree().create_timer(shot.get_safe_duration()).timeout
	else:
		await active_camera.await_shot(shot)

	# A cue clamped to the shot end is stepped by the cue tween in the same frame
	# the camera settles. Flush one frame so the last cue always lands before the
	# shot is reported as finished.
	if is_inside_tree():
		await get_tree().process_frame

	if run_id != _run_id:
		return
	shot_finished.emit(index, shot)


func _schedule_cues(shot: Shot, index: int) -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = null
	if shot.cues.is_empty():
		return

	var duration := shot.get_safe_duration()
	var ordered := _ordered_cues(shot, duration)
	if ordered.is_empty():
		return

	var cue_tween := create_tween()
	cue_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cue_tween = cue_tween
	var cursor := 0.0
	for cue in ordered:
		var cue_time := clamp_cue_time(cue.time, duration)
		if cue_time > cursor:
			cue_tween.tween_interval(cue_time - cursor)
			cursor = cue_time
		cue_tween.tween_callback(_fire_cue.bind(cue, index))


func _ordered_cues(shot: Shot, duration: float) -> Array[Cue]:
	var ordered: Array[Cue] = []
	for cue in shot.cues:
		if cue != null:
			ordered.append(cue)
	ordered.sort_custom(
		func(a: Cue, b: Cue) -> bool:
			return clamp_cue_time(a.time, duration) < clamp_cue_time(b.time, duration)
	)
	return ordered


func _fire_cue(cue: Cue, shot_index: int) -> void:
	cue_fired.emit(cue, shot_index)
	var target := _resolve_cue_target(cue)
	if target != null and target.has_method("on_cue"):
		target.call("on_cue", cue)


func _resolve_cue_target(cue: Cue) -> Node:
	if cue.target.is_empty():
		return null
	var node := get_node_or_null(cue.target)
	if node != null:
		return node
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene.get_node_or_null(cue.target)
	return null


func _resolve_camera() -> ExplainerCamera:
	if is_instance_valid(camera):
		return camera
	if not camera_path.is_empty():
		var node := get_node_or_null(camera_path)
		if node is ExplainerCamera:
			camera = node as ExplainerCamera
			return camera
	var child := get_node_or_null("ExplainerCamera")
	if child is ExplainerCamera:
		camera = child as ExplainerCamera
		return camera
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var grouped := tree.get_first_node_in_group("explainer_camera")
	if grouped is ExplainerCamera:
		camera = grouped as ExplainerCamera
		return camera
	return null
