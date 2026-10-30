@tool
class_name Callout
extends Control
## World-anchored annotation bubble for explainer videos.
##
## The bubble lives in a HUD [CanvasLayer] (screen space) but tracks a world
## node through pans and zooms. Each update projects the target with
## `get_viewport().get_canvas_transform()` and clamps it into the visible world
## rect using `affine_inverse()`, so the bubble never leaves the frame even when
## its anchor does.
##
## Follow motion is exponential — `1 - exp(-follow_speed * delta)` — which is
## frame-rate independent. `_process` only runs while the callout is visible and
## anchored; there is no idle polling.

signal callout_shown(text: String)
signal callout_hidden()

## Preferred side of the anchor the bubble sits on.
enum Dock {
	AUTO,   ## Above the anchor unless it is in the top half of the frame.
	ABOVE,
	BELOW,
	LEFT,
	RIGHT,
}

## Dock preference. [constant Dock.AUTO] flips based on the anchor position.
@export var dock: Dock = Dock.AUTO

## Gap in pixels between the anchor and the bubble.
@export_range(0.0, 200.0, 1.0, "suffix:px")
var bubble_gap: float = 26.0

## Minimum distance in pixels the bubble keeps from the viewport edges.
@export_range(0.0, 200.0, 1.0, "suffix:px")
var edge_margin: float = 24.0

## Exponential follow speed. Higher is snappier; smoothing is
## `1 - exp(-follow_speed * delta)`.
@export_range(0.5, 60.0, 0.5)
var follow_speed: float = 14.0

## Reveal duration in seconds when a cue does not override it.
@export_range(0.0, 2.0, 0.01, "suffix:s")
var reveal_duration: float = 0.28

## Fade-out duration in seconds for [method hide_callout].
@export_range(0.0, 2.0, 0.01, "suffix:s")
var dismiss_duration: float = 0.2

## Max text width in pixels; the bubble grows vertically instead.
@export_range(80.0, 600.0, 10.0, "suffix:px")
var max_width: float = 280.0

## Bubble background colour.
@export var bubble_color: Color = Color(0.08, 0.11, 0.16, 0.96)

## Bubble border colour.
@export var border_color: Color = Color(0.3, 0.78, 0.9, 0.9)

## Tail and anchor dot colour.
@export var tail_color: Color = Color(0.3, 0.78, 0.9, 0.95)

## Bubble font size in points.
@export_range(8, 48, 1, "suffix:pt")
var font_size: int = 18

var _bubble: PanelContainer = null
var _label: Label = null
var _target: Node = null
var _anchor_screen: Vector2 = Vector2.ZERO
var _target_screen: Vector2 = Vector2.ZERO
var _anchor_initialized: bool = false
var _visible_state: bool = false
var _tween: Tween = null
var _pending_dismiss: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_bubble()
	_bubble.visible = false
	set_process(false)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _visible_state:
		set_process(false)
		return
	refresh(delta)


## Recomputes the projected anchor and bubble layout.
##
## [param delta] of `0.0` snaps instead of smoothing; tests and the preview
## scrubber use that to evaluate a single frame deterministically.
func refresh(delta: float = 0.0) -> void:
	if not _visible_state or _bubble == null:
		return
	var projected := _project_target()
	_target_screen = projected
	if not _anchor_initialized or delta <= 0.0:
		_anchor_screen = projected
		_anchor_initialized = true
	else:
		var weight := 1.0 - exp(-follow_speed * delta)
		_anchor_screen = _anchor_screen.lerp(projected, weight)
	_layout_bubble()


## Shows a callout anchored to [param target] and returns the reveal/animation
## [Tween]. When already visible, text and anchor are retargeted without
## resetting alpha or scale.
##
## [param hold] is the total time the bubble stays up before it starts fading
## out, in seconds; `0` keeps it up until [method hide_callout] or the next cue.
## [param dismiss] is the fade-out duration, or `-1` to use [member dismiss_duration].
func show_callout(
	text: String,
	target: Node = null,
	hold: float = 0.0,
	reveal: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT,
	dismiss: float = -1.0
) -> Tween:
	if _bubble == null:
		_ensure_bubble()
	if _label == null:
		return null
	var was_visible := _visible_state
	_label.text = text
	if is_instance_valid(target):
		_target = target
	if not was_visible:
		_anchor_initialized = false
		_bubble.modulate.a = 0.0
		_bubble.scale = Vector2(0.92, 0.92)
	_visible_state = true
	_bubble.visible = true
	_pending_dismiss = dismiss_duration if dismiss < 0.0 else maxf(dismiss, 0.0)
	set_process(not Engine.is_editor_hint())
	if was_visible:
		_layout_bubble()
	else:
		refresh(0.0)

	_kill_tween()
	var active_reveal := reveal_duration if reveal < 0.0 else maxf(reveal, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	tween.set_ease(ease_type)
	tween.tween_property(_bubble, "modulate:a", 1.0, active_reveal)
	tween.parallel().tween_property(_bubble, "scale", Vector2.ONE, active_reveal)
	if hold > 0.0:
		tween.tween_interval(maxf(hold - active_reveal, 0.0))
		tween.finished.connect(_on_hold_finished, CONNECT_ONE_SHOT)
	else:
		tween.finished.connect(_on_show_tween_finished, CONNECT_ONE_SHOT)
	_tween = tween
	callout_shown.emit(text)
	return tween


## Fades the callout out and returns the [Tween].
func hide_callout(
	duration: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_IN
) -> Tween:
	if not _visible_state or _bubble == null:
		return null
	_kill_tween()
	var active_duration := dismiss_duration if duration < 0.0 else maxf(duration, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	tween.set_ease(ease_type)
	tween.tween_property(_bubble, "modulate:a", 0.0, active_duration)
	tween.parallel().tween_property(_bubble, "scale", Vector2(0.96, 0.96), active_duration)
	tween.finished.connect(_on_hide_tween_finished, CONNECT_ONE_SHOT)
	_tween = tween
	return tween


## Cue receiver entry point. Supported `data` keys: `text`, `anchor` (NodePath or
## Node), `hold`, `reveal`, `hide`.
func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if bool(event.get_data("hide", false)):
		hide_callout(event.get_budget(float(event.get_data("duration", -1.0))))
		return
	var text := String(event.get_data("text", ""))
	if text.is_empty():
		return
	var anchor := _resolve_anchor(event.get_data("anchor", null))
	# The whole cue lifetime — reveal, hold and fade-out — has to fit the shot's
	# remaining time so the bubble is gone when the camera settles.
	var budget := maxf(event.remaining, 0.0)
	var reveal := clampf(float(event.get_data("reveal", reveal_duration)), 0.0, budget)
	var dismiss := minf(dismiss_duration, maxf(budget - reveal, 0.0))
	var hold := clampf(
		float(event.get_data("hold", budget)), reveal, maxf(budget - dismiss, reveal)
	)
	var shot_trans := Tween.TRANS_CUBIC
	var shot_ease := Tween.EASE_OUT
	if event.shot != null:
		shot_trans = event.shot.trans
		shot_ease = event.shot.ease
	show_callout(text, anchor, hold, reveal, shot_trans, shot_ease, dismiss)


## Anchor point in screen pixels, after clamping and smoothing.
func get_anchor_screen_position() -> Vector2:
	return _anchor_screen


## Bubble top-left in screen pixels.
func get_bubble_position() -> Vector2:
	if _bubble == null:
		return Vector2.ZERO
	return _bubble.position


## Current callout text.
func get_text() -> String:
	return "" if _label == null else _label.text


## Whether the callout is currently shown (including fade-out).
func is_callout_visible() -> bool:
	return _visible_state and _bubble != null and _bubble.visible


## Node currently tracked as the world anchor.
func get_target_node() -> Node:
	return _target


## Sets the world anchor without changing text or visibility.
func set_target_node(node: Node) -> void:
	_target = node


func _ensure_bubble() -> void:
	_bubble = get_node_or_null("Bubble") as PanelContainer
	if _bubble == null:
		_bubble = PanelContainer.new()
		_bubble.name = "Bubble"
		_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bubble)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = bubble_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_bubble.add_theme_stylebox_override("panel", style)

	_label = _bubble.get_node_or_null("Label") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bubble.add_child(_label)
	_label.custom_minimum_size = Vector2(max_width, 0.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))


func _project_target() -> Vector2:
	if not is_instance_valid(_target):
		return _anchor_screen
	var world_point := _world_position_of(_target)
	var canvas_transform := get_viewport().get_canvas_transform()
	var clamped_world := _clamp_world_to_view(world_point, canvas_transform)
	return canvas_transform * clamped_world


func _world_position_of(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).global_position
	if node is Control:
		var canvas_center := (node as Control).get_global_rect().get_center()
		return get_viewport().get_canvas_transform().affine_inverse() * canvas_center
	return _anchor_screen


func _clamp_world_to_view(world_point: Vector2, canvas_transform: Transform2D) -> Vector2:
	var inverse := canvas_transform.affine_inverse()
	var world_top_left := inverse * Vector2.ZERO
	var world_bottom_right := inverse * get_viewport_rect().size
	var visible_world := Rect2(world_top_left, world_bottom_right - world_top_left).abs()
	var pixels_per_world_unit := maxf(canvas_transform.get_scale().x, 0.0001)
	var margin_world := edge_margin / pixels_per_world_unit
	if visible_world.size.x <= margin_world * 2.0 or visible_world.size.y <= margin_world * 2.0:
		return world_point
	return Vector2(
		clampf(
			world_point.x,
			visible_world.position.x + margin_world,
			visible_world.end.x - margin_world
		),
		clampf(
			world_point.y,
			visible_world.position.y + margin_world,
			visible_world.end.y - margin_world
		)
	)


func _layout_bubble() -> void:
	if _bubble == null:
		return
	var minimum := _bubble.get_combined_minimum_size()
	_bubble.size = minimum
	_bubble.pivot_offset = minimum * 0.5
	var desired := _anchor_screen + _dock_offset(minimum)
	var viewport_size := get_viewport_rect().size
	var max_x := maxf(viewport_size.x - minimum.x - edge_margin, edge_margin)
	var max_y := maxf(viewport_size.y - minimum.y - edge_margin, edge_margin)
	_bubble.position = Vector2(
		clampf(desired.x, edge_margin, max_x),
		clampf(desired.y, edge_margin, max_y)
	)
	queue_redraw()


func _dock_offset(bubble_size: Vector2) -> Vector2:
	var active_dock := dock
	if active_dock == Dock.AUTO:
		var half_height := get_viewport_rect().size.y * 0.5
		active_dock = Dock.ABOVE if _anchor_screen.y > half_height else Dock.BELOW
	match active_dock:
		Dock.ABOVE:
			return Vector2(-bubble_size.x * 0.5, -bubble_size.y - bubble_gap)
		Dock.LEFT:
			return Vector2(-bubble_size.x - bubble_gap, -bubble_size.y * 0.5)
		Dock.RIGHT:
			return Vector2(bubble_gap, -bubble_size.y * 0.5)
		_:
			return Vector2(-bubble_size.x * 0.5, bubble_gap)


func _draw() -> void:
	if not _visible_state or _bubble == null or not _bubble.visible:
		return
	if _target_screen.distance_to(_anchor_screen) < 1.0:
		return
	var bubble_rect := Rect2(_bubble.position, _bubble.size)
	var tail_start := Vector2(
		clampf(_target_screen.x, bubble_rect.position.x, bubble_rect.end.x),
		clampf(_target_screen.y, bubble_rect.position.y, bubble_rect.end.y)
	)
	draw_line(tail_start, _target_screen, tail_color, 2.0, true)
	draw_circle(_target_screen, 4.0, tail_color)


func _resolve_anchor(value: Variant) -> Node:
	if value is Node:
		return value as Node
	if value is NodePath:
		var path := value as NodePath
		if path.is_empty():
			return _target
		var node := get_node_or_null(path)
		if node != null:
			return node
		var tree := get_tree()
		if tree != null and tree.current_scene != null:
			return tree.current_scene.get_node_or_null(path)
	return _target


func _on_hold_finished() -> void:
	if _visible_state:
		hide_callout(_pending_dismiss)


func _on_show_tween_finished() -> void:
	if _bubble != null:
		_bubble.modulate.a = 1.0
		_bubble.scale = Vector2.ONE


func _on_hide_tween_finished() -> void:
	_visible_state = false
	if _bubble != null:
		_bubble.visible = false
	set_process(false)
	queue_redraw()
	callout_hidden.emit()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
