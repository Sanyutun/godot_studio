@tool
class_name CaptionRevealer
extends Control
## Typewriter / fade / slide caption driven by [Cue]s.
##
## Cues arrive through [method on_cue] with a [CueEvent]. The event carries the
## shot's remaining time budget, so a caption scheduled mid-shot always finishes
## when the camera move settles instead of running past the cut.
##
## Re-cueing while visible retargets the text without popping: alpha and glyph
## count start from their current values, never from zero.

signal reveal_started(text: String)
signal reveal_finished()
signal dismissed()

enum Mode {
	TYPEWRITER,  ## Reveal glyph by glyph.
	FADE_UP,     ## Fade in while rising into place.
	SLIDE_LEFT,  ## Fade in while sliding in from the right.
}

const MODE_NAMES: Array[String] = ["typewriter", "fade_up", "slide_left"]

## Default reveal mode when a cue does not override it.
@export var mode: Mode = Mode.TYPEWRITER

## Default reveal duration in seconds when a cue does not provide one.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var reveal_duration: float = 0.6

## Fade-out duration in seconds for [method dismiss].
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var dismiss_duration: float = 0.3

## Vertical travel in pixels for [constant Mode.FADE_UP].
@export_range(0.0, 200.0, 1.0, "suffix:px")
var fade_distance: float = 18.0

## Horizontal travel in pixels for [constant Mode.SLIDE_LEFT].
@export_range(0.0, 400.0, 1.0, "suffix:px")
var slide_distance: float = 42.0

## Optional existing [Label] to drive. A centred label is created when empty.
@export var label_path: NodePath

var _label: Label = null
var _base_alpha: float = 1.0
var _label_rest_position: Vector2 = Vector2.ZERO
var _rest_captured: bool = false
var _active_mode: int = Mode.TYPEWRITER
var _last_text_length: int = 0
var _reveal_tween: Tween = null
var _dismiss_tween: Tween = null
var _current_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_alpha = maxf(modulate.a, 0.001)
	_label = _resolve_label()
	_label_rest_position = _label.position
	_rest_captured = true
	_label.visible_characters = -1
	if not Engine.is_editor_hint():
		hide()


## Reveals [param text] and returns the running [Tween].
##
## [param reveal_mode] `-1` keeps [member mode]. [param duration] `-1` uses
## [member reveal_duration]. When called while visible the reveal continues from
## the current alpha / glyph count (no pop).
func reveal(
	text: String,
	reveal_mode: int = -1,
	duration: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT
) -> Tween:
	if _label == null:
		_label = _resolve_label()
		_label_rest_position = _label.position
		_rest_captured = true
	var was_visible := visible and modulate.a > 0.001
	var active_mode: int = mode if reveal_mode < 0 else reveal_mode
	var active_duration := reveal_duration if duration < 0.0 else maxf(duration, 0.0)
	_active_mode = active_mode
	_current_text = text
	_label.text = text
	_kill_tweens()

	show()
	if not was_visible:
		modulate.a = 0.0 if active_mode != Mode.TYPEWRITER else _base_alpha
		_label.position = _mode_start_position(active_mode)
	else:
		modulate.a = clampf(modulate.a, 0.0, _base_alpha)

	var from_characters := 0
	if active_mode == Mode.TYPEWRITER:
		modulate.a = _base_alpha
		if was_visible:
			var current := _label.visible_characters
			if current < 0:
				current = _last_text_length
			from_characters = clampi(current, 0, text.length())
		_label.visible_characters = from_characters
	_last_text_length = text.length()

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	tween.set_ease(ease_type)
	if active_mode == Mode.TYPEWRITER:
		tween.tween_method(_apply_visible_characters, float(from_characters), float(text.length()), active_duration)
		tween.parallel().tween_property(_label, "position", _label_rest_position, active_duration)
		tween.parallel().tween_property(self, "modulate:a", _base_alpha, active_duration)
	else:
		tween.tween_property(self, "modulate:a", _base_alpha, active_duration)
		tween.parallel().tween_property(_label, "position", _label_rest_position, active_duration)
	tween.finished.connect(_on_reveal_finished, CONNECT_ONE_SHOT)
	_reveal_tween = tween
	reveal_started.emit(text)
	return tween


## Updates the text of an in-flight reveal. Thin alias of [method reveal] that
## documents the pop-free retarget use case.
func retarget(
	text: String,
	duration: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT
) -> Tween:
	return reveal(text, -1, duration, trans, ease_type)


## Fades the caption out and returns the [Tween].
func dismiss(duration: float = -1.0) -> Tween:
	if not visible:
		return null
	_kill_tweens()
	var active_duration := dismiss_duration if duration < 0.0 else maxf(duration, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, active_duration)
	tween.finished.connect(_on_dismiss_finished, CONNECT_ONE_SHOT)
	_dismiss_tween = tween
	return tween


## Cue receiver entry point. Supported `data` keys: `text`, `mode`,
## `duration` (clamped to the shot budget), `hide`.
func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if bool(event.get_data("hide", false)):
		var hide_duration := event.get_budget(float(event.get_data("duration", -1.0)))
		dismiss(hide_duration)
		return
	var text := String(event.get_data("text", event.cue.action))
	if text.is_empty():
		return
	var requested_mode := _mode_from_name(String(event.get_data("mode", _mode_name(mode))))
	var budget := event.get_budget(float(event.get_data("duration", -1.0)))
	var shot_trans := Tween.TRANS_CUBIC
	var shot_ease := Tween.EASE_OUT
	if event.shot != null:
		shot_trans = event.shot.trans
		shot_ease = event.shot.ease
	reveal(text, requested_mode, budget, shot_trans, shot_ease)


## Caption text currently displayed or being revealed.
func get_text() -> String:
	return _current_text


## The [Label] being driven. Mostly useful for tests and custom theming.
func get_label() -> Label:
	return _label


## Whether a reveal tween is currently running.
func is_revealing() -> bool:
	return _reveal_tween != null and _reveal_tween.is_valid() and _reveal_tween.is_running()


## Whether the caption is visible and fully revealed.
func is_revealed() -> bool:
	if not visible or _label == null:
		return false
	if _active_mode == Mode.TYPEWRITER:
		return _label.visible_ratio >= 0.999
	return modulate.a >= _base_alpha * 0.999


## Reveal progress in `[0, 1]` for the active mode.
func get_reveal_progress() -> float:
	if not visible or _label == null:
		return 0.0
	if _active_mode == Mode.TYPEWRITER:
		return _label.visible_ratio
	return clampf(modulate.a / _base_alpha, 0.0, 1.0)


func _resolve_label() -> Label:
	if not label_path.is_empty():
		var configured := get_node_or_null(label_path)
		if configured is Label:
			return configured as Label
	var existing := get_node_or_null("Label")
	if existing is Label:
		return existing as Label
	var created := Label.new()
	created.name = "Label"
	created.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	created.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	created.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	created.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	created.add_theme_font_size_override("font_size", 30)
	created.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	created.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	created.add_theme_constant_override("outline_size", 6)
	add_child(created)
	return created


func _mode_start_position(active_mode: int) -> Vector2:
	match active_mode:
		Mode.FADE_UP:
			return _label_rest_position + Vector2(0.0, fade_distance)
		Mode.SLIDE_LEFT:
			return _label_rest_position + Vector2(slide_distance, 0.0)
		_:
			return _label_rest_position


func _apply_visible_characters(value: float) -> void:
	if _label == null:
		return
	_label.visible_characters = clampi(int(round(value)), 0, _label.text.length())


func _mode_from_name(mode_name: String) -> int:
	match mode_name:
		"fade_up":
			return Mode.FADE_UP
		"slide_left":
			return Mode.SLIDE_LEFT
		_:
			return Mode.TYPEWRITER


func _mode_name(mode_value: int) -> String:
	if mode_value < 0 or mode_value >= MODE_NAMES.size():
		return MODE_NAMES[Mode.TYPEWRITER]
	return MODE_NAMES[mode_value]


func _on_reveal_finished() -> void:
	if _label != null:
		_label.visible_characters = -1
		_label.position = _label_rest_position
	modulate.a = _base_alpha
	reveal_finished.emit()


func _on_dismiss_finished() -> void:
	hide()
	if _label != null:
		_label.position = _label_rest_position
	dismissed.emit()


func _kill_tweens() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	if _dismiss_tween != null and _dismiss_tween.is_valid():
		_dismiss_tween.kill()
	_dismiss_tween = null
