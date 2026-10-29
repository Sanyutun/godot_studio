@tool
class_name ExplainerCamera
extends Camera2D
## Cinematic 2D camera driven by [Shot] resources.
##
## The camera owns every move tween. Nothing else should animate [member position]
## or [member zoom] directly: call [method play_shot] (or let a [Director] do it)
## so aborts, state flags and signals stay consistent.
##
## A tween can be killed from the outside (editor scrub, scene change, a second
## shot). Killed tweens never emit `finished`, so the camera reaps them with a
## signal-based watchdog and [method is_shot_active] self-heals on read. That is
## the regression fix for the punch-out drift bug.

signal shot_started(shot: Shot)
signal shot_finished(shot: Shot)
signal shot_aborted(shot: Shot)
## Emitted exactly once per started shot, whether it finished or was aborted.
## [method await_shot] waits on this.
signal shot_settled(shot: Shot)

const MIN_ZOOM := 0.05
const MAX_ZOOM := 20.0
## Extra time after a shot's duration before an externally killed tween is reaped.
const KILL_WATCHDOG_GRACE := 0.25

## Zoom used by [constant Shot.Kind.PUNCH_OUT] when a shot leaves [member Shot.zoom]
## at its default.
@export_range(0.05, 20.0, 0.05, "or_greater")
var default_zoom: float = 1.0

## Extra world-space margin in pixels when fitting a rect.
@export_range(0.0, 512.0, 1.0, "suffix:px")
var fit_padding: float = 48.0

## Fallback look-at target used when a shot's own [member Shot.target] is empty.
@export var default_target: NodePath

var _active_tween: Tween = null
var _active_shot: Shot = null
var _shot_active: bool = false
var _generation: int = 0


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


## Starts [param shot] and returns its tween so callers can `await` it directly.
## The camera also emits [signal shot_settled]; [method await_shot] is a thin
## wrapper that survives aborted tweens.
func play_shot(shot: Shot) -> Tween:
	if shot == null:
		push_error("ExplainerCamera.play_shot(): shot is null.")
		return null
	if _shot_active:
		_abort_active_shot(true)

	_generation += 1
	var generation := _generation
	_shot_active = true
	_active_shot = shot
	shot_started.emit(shot)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(shot.trans)
	tween.set_ease(shot.ease)
	_build_shot_tween(tween, shot)

	_active_tween = tween
	tween.finished.connect(_on_tween_finished.bind(generation, shot), CONNECT_ONE_SHOT)
	_watch_for_killed_tween(generation, shot)
	return tween


## Plays [param shot] and returns when it settles (finished, aborted or killed).
func await_shot(shot: Shot) -> void:
	var tween := play_shot(shot)
	if tween == null:
		return
	await shot_settled


## Cancels the active shot and resets the camera state. Safe to call twice.
func abort() -> void:
	if not _shot_active and _active_tween == null:
		return
	_abort_active_shot(true)


## Whether a shot is currently driving the camera. Self-heals when the tween was
## killed behind our back, emitting [signal shot_aborted] once.
func is_shot_active() -> bool:
	if not _shot_active:
		return false
	if _active_tween == null or not _active_tween.is_valid():
		_abort_active_shot(true)
	return _shot_active


## The shot currently driving the camera, or `null`.
func get_active_shot() -> Shot:
	return _active_shot


## The tween currently driving the camera, or `null`.
func get_active_tween() -> Tween:
	return _active_tween


## Zoom that frames [param world_rect] in the current viewport, clamped to the
## camera limits. Public for presets and the preview scrubber.
func get_fit_zoom(world_rect: Rect2) -> float:
	if not is_inside_tree():
		return maxf(zoom.x, MIN_ZOOM)
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return zoom.x
	var padded := world_rect.grow(fit_padding)
	if padded.size.x <= 0.0 or padded.size.y <= 0.0:
		return zoom.x
	var raw := minf(viewport_size.x / padded.size.x, viewport_size.y / padded.size.y)
	return clampf(raw, MIN_ZOOM, MAX_ZOOM)


func _build_shot_tween(tween: Tween, shot: Shot) -> void:
	var duration := shot.get_safe_duration()
	match shot.kind:
		Shot.Kind.HOLD:
			tween.tween_interval(duration)
		Shot.Kind.PAN:
			tween.tween_property(self, "position", _resolve_position(shot, position), duration)
		Shot.Kind.FIT_RECT:
			var fit_rect := _resolve_fit_rect(shot)
			var fit_zoom := get_fit_zoom(fit_rect)
			tween.tween_property(self, "position", fit_rect.get_center(), duration)
			tween.parallel().tween_property(self, "zoom", Vector2(fit_zoom, fit_zoom), duration)
		Shot.Kind.PUNCH_IN, Shot.Kind.PUNCH_OUT:
			var punch_zoom := _target_zoom(shot)
			if shot.target.is_empty():
				tween.tween_property(self, "zoom", Vector2(punch_zoom, punch_zoom), duration)
			else:
				tween.tween_property(self, "position", _resolve_position(shot, position), duration)
				tween.parallel().tween_property(self, "zoom", Vector2(punch_zoom, punch_zoom), duration)
		_:
			# MOVE and DRIFT: position plus zoom.
			var move_zoom := _target_zoom(shot)
			tween.tween_property(self, "position", _resolve_position(shot, position), duration)
			tween.parallel().tween_property(self, "zoom", Vector2(move_zoom, move_zoom), duration)


func _target_zoom(shot: Shot) -> float:
	return clampf(shot.zoom, MIN_ZOOM, MAX_ZOOM)


func _resolve_position(shot: Shot, fallback: Vector2) -> Vector2:
	var path := shot.target
	if path.is_empty():
		path = default_target
	if path.is_empty():
		return fallback
	var node := get_node_or_null(path)
	if node == null:
		push_warning("ExplainerCamera: target '%s' not found; keeping position." % path)
		return fallback
	return _world_position_of(node, fallback)


func _world_position_of(node: Node, fallback: Vector2) -> Vector2:
	if node is Node2D:
		return (node as Node2D).global_position
	if node is Control:
		return (node as Control).get_global_rect().get_center()
	if node is CanvasItem:
		return (node as CanvasItem).get_global_transform().origin
	return fallback


func _resolve_fit_rect(shot: Shot) -> Rect2:
	if shot.rect.size.x > 0.0 and shot.rect.size.y > 0.0:
		return shot.rect
	var fallback_zoom := maxf(zoom.x, MIN_ZOOM)
	var view_size := get_viewport_rect().size / fallback_zoom
	return Rect2(position - view_size * 0.5, view_size)


func _on_tween_finished(generation: int, shot: Shot) -> void:
	if generation != _generation or not _shot_active:
		return
	_shot_active = false
	_active_tween = null
	_active_shot = null
	shot_finished.emit(shot)
	shot_settled.emit(shot)


func _abort_active_shot(notify: bool) -> void:
	var shot := _active_shot
	var tween := _active_tween
	_shot_active = false
	_active_tween = null
	_active_shot = null
	if tween != null and tween.is_valid():
		tween.kill()
	if notify and shot != null:
		shot_aborted.emit(shot)
		shot_settled.emit(shot)


func _watch_for_killed_tween(generation: int, shot: Shot) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(shot.get_safe_duration() + KILL_WATCHDOG_GRACE).timeout
	if generation != _generation or not _shot_active:
		return
	if _active_tween != null and _active_tween.is_valid():
		return
	print_verbose(
		"ExplainerCamera: tween for '%s' was killed externally; resetting shot state."
		% shot.get_kind_name()
	)
	_abort_active_shot(true)
