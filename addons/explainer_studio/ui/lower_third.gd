@tool
class_name LowerThird
extends Control
## Title card that slides in from the bottom-left of the frame.
##
## Cues arrive through [method on_cue] with a [CueEvent]. The event carries the
## shot's remaining time budget, so a lower third scheduled mid-shot reveals,
## holds and fades out on the same clock as the camera move (M2 sequencing rule).
##
## Re-cueing while visible retargets the copy without popping: alpha and slide
## position continue from their current values instead of restarting at zero.

signal lower_third_shown(title: String, subtitle: String)
signal lower_third_hidden()

## Minimum distance in pixels the card keeps from the viewport edges.
@export_range(0.0, 200.0, 1.0, "suffix:px")
var edge_margin: float = 36.0

## Vertical travel in pixels for the slide-in reveal.
@export_range(0.0, 200.0, 1.0, "suffix:px")
var slide_distance: float = 26.0

## Reveal duration in seconds when a cue does not override it.
@export_range(0.0, 2.0, 0.01, "suffix:s")
var reveal_duration: float = 0.35

## Fade-out duration in seconds for [method hide_lower_third].
@export_range(0.0, 2.0, 0.01, "suffix:s")
var dismiss_duration: float = 0.25

## Max text width in pixels; longer copy wraps and grows the card vertically.
@export_range(160.0, 900.0, 10.0, "suffix:px")
var max_width: float = 560.0

## Card background colour.
@export var panel_color: Color = Color(0.06, 0.09, 0.13, 0.94)

## Card border colour.
@export var border_color: Color = Color(0.3, 0.78, 0.9, 0.7)

## Accent bar and kicker colour.
@export var accent_color: Color = Color(0.3, 0.78, 0.9, 1.0)

## Title text colour.
@export var title_color: Color = Color(0.94, 0.97, 1.0, 1.0)

## Subtitle text colour.
@export var subtitle_color: Color = Color(0.64, 0.74, 0.82, 1.0)

## Width of the accent bar in pixels.
@export_range(0.0, 24.0, 1.0, "suffix:px")
var accent_width: float = 5.0

## Kicker font size in points.
@export_range(8, 32, 1, "suffix:pt")
var kicker_font_size: int = 13

## Title font size in points.
@export_range(8, 96, 1, "suffix:pt")
var title_font_size: int = 34

## Subtitle font size in points.
@export_range(8, 48, 1, "suffix:pt")
var subtitle_font_size: int = 18

var _panel: PanelContainer = null
var _accent: ColorRect = null
var _kicker_label: Label = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _rest_position: Vector2 = Vector2.ZERO
var _visible_state: bool = false
var _tween: Tween = null
var _pending_dismiss: float = -1.0
var _current_title: String = ""
var _current_subtitle: String = ""
var _current_kicker: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_panel()
	_panel.visible = false
	_panel.modulate.a = 0.0
	_layout_panel()


func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or _panel == null:
		return
	_layout_panel()
	if _visible_state and (_tween == null or not _tween.is_valid()):
		_panel.position = _rest_position


## Shows a lower third and returns the reveal/animation [Tween]. When already
## visible, copy and layout are retargeted without resetting alpha or position.
##
## [param hold] is the total time the card stays up before it starts fading out,
## in seconds; `0` keeps it up until [method hide_lower_third] or the next cue.
## [param dismiss] is the fade-out duration, or `-1` to use
## [member dismiss_duration]. [param kicker] is optional eyebrow copy.
func show_lower_third(
	title: String,
	subtitle: String = "",
	hold: float = 0.0,
	reveal: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT,
	dismiss: float = -1.0,
	kicker: String = ""
) -> Tween:
	if _panel == null:
		_ensure_panel()
	if _title_label == null:
		return null
	var was_visible := _visible_state
	_current_title = title
	_current_subtitle = subtitle
	_current_kicker = kicker
	_title_label.text = title
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()
	_kicker_label.text = kicker
	_kicker_label.visible = not kicker.is_empty()
	_apply_style()

	_panel.visible = true
	_visible_state = true
	_pending_dismiss = dismiss_duration if dismiss < 0.0 else maxf(dismiss, 0.0)
	_layout_panel()
	if not was_visible:
		_panel.modulate.a = 0.0
		_panel.position = _rest_position + Vector2(0.0, slide_distance)
	_kill_tween()
	var active_reveal := reveal_duration if reveal < 0.0 else maxf(reveal, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	tween.set_ease(ease_type)
	tween.tween_property(_panel, "modulate:a", 1.0, active_reveal)
	tween.parallel().tween_property(_panel, "position", _rest_position, active_reveal)
	if hold > 0.0:
		tween.tween_interval(maxf(hold - active_reveal, 0.0))
		tween.finished.connect(_on_hold_finished, CONNECT_ONE_SHOT)
	else:
		tween.finished.connect(_on_show_tween_finished, CONNECT_ONE_SHOT)
	_tween = tween
	lower_third_shown.emit(title, subtitle)
	return tween


## Updates the copy of a visible lower third without resetting its reveal.
func retarget(
	title: String,
	subtitle: String = "",
	reveal: float = -1.0,
	kicker: String = ""
) -> Tween:
	return show_lower_third(
		title, subtitle, 0.0, reveal, Tween.TRANS_CUBIC, Tween.EASE_OUT, -1.0, kicker
	)


## Fades the lower third out and returns the [Tween].
func hide_lower_third(
	duration: float = -1.0,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_IN
) -> Tween:
	if not _visible_state or _panel == null:
		return null
	_kill_tween()
	var active_duration := dismiss_duration if duration < 0.0 else maxf(duration, 0.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	tween.set_ease(ease_type)
	tween.tween_property(_panel, "modulate:a", 0.0, active_duration)
	tween.parallel().tween_property(
		_panel, "position", _rest_position + Vector2(0.0, slide_distance), active_duration
	)
	tween.finished.connect(_on_hide_tween_finished, CONNECT_ONE_SHOT)
	_tween = tween
	return tween


## Cue receiver entry point. Supported `data` keys: `title`, `subtitle`,
## `kicker`, `hold`, `reveal`, `duration` (hide duration), `hide`.
func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if bool(event.get_data("hide", false)):
		hide_lower_third(event.get_budget(float(event.get_data("duration", -1.0))))
		return
	var title := String(event.get_data("title", ""))
	if title.is_empty():
		title = String(event.get_data("text", ""))
	if title.is_empty():
		return
	var subtitle := String(event.get_data("subtitle", ""))
	var kicker := String(event.get_data("kicker", ""))
	# The whole cue lifetime — reveal, hold and fade-out — has to fit the shot's
	# remaining time so the card is gone when the camera settles.
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
	show_lower_third(
		title, subtitle, hold, reveal, shot_trans, shot_ease, dismiss, kicker
	)


## Current title text.
func get_title() -> String:
	return _current_title


## Current subtitle text.
func get_subtitle() -> String:
	return _current_subtitle


## Current kicker text.
func get_kicker() -> String:
	return _current_kicker


## Alias for [method get_title], matching the other UI receivers.
func get_text() -> String:
	return _current_title


## Alias for [method hide_lower_third] with the default transition.
func dismiss(duration: float = -1.0) -> Tween:
	return hide_lower_third(duration)


## Whether the card is currently shown (including fade-out).
func is_lower_third_visible() -> bool:
	return _visible_state and _panel != null and _panel.visible


## The [PanelContainer] being driven. Mostly useful for tests and custom theming.
func get_panel() -> PanelContainer:
	return _panel


## Card top-left in screen pixels, ignoring the in-flight slide offset.
func get_rest_position() -> Vector2:
	return _rest_position


func _ensure_panel() -> void:
	_panel = get_node_or_null("Panel") as PanelContainer
	if _panel == null:
		_panel = PanelContainer.new()
		_panel.name = "Panel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 20.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_panel.add_theme_stylebox_override("panel", style)

	var row := _panel.get_node_or_null("Row") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 14)
		_panel.add_child(row)

	_accent = row.get_node_or_null("Accent") as ColorRect
	if _accent == null:
		_accent = ColorRect.new()
		_accent.name = "Accent"
		_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_accent)

	var copy := row.get_node_or_null("Copy") as VBoxContainer
	if copy == null:
		copy = VBoxContainer.new()
		copy.name = "Copy"
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_theme_constant_override("separation", 2)
		row.add_child(copy)

	_kicker_label = copy.get_node_or_null("Kicker") as Label
	if _kicker_label == null:
		_kicker_label = Label.new()
		_kicker_label.name = "Kicker"
		_kicker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(_kicker_label)

	_title_label = copy.get_node_or_null("Title") as Label
	if _title_label == null:
		_title_label = Label.new()
		_title_label.name = "Title"
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(_title_label)

	_subtitle_label = copy.get_node_or_null("Subtitle") as Label
	if _subtitle_label == null:
		_subtitle_label = Label.new()
		_subtitle_label.name = "Subtitle"
		_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(_subtitle_label)

	_title_label.custom_minimum_size = Vector2(max_width, 0.0)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.custom_minimum_size = Vector2(max_width, 0.0)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kicker_label.uppercase = true
	_apply_style()


func _apply_style() -> void:
	if _panel == null:
		return
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.bg_color = panel_color
		style.border_color = border_color
	if _accent != null:
		_accent.color = accent_color
		_accent.custom_minimum_size = Vector2(accent_width, 0.0)
	if _kicker_label != null:
		_kicker_label.add_theme_font_size_override("font_size", kicker_font_size)
		_kicker_label.add_theme_color_override("font_color", accent_color)
	if _title_label != null:
		_title_label.custom_minimum_size.x = max_width
		_title_label.add_theme_font_size_override("font_size", title_font_size)
		_title_label.add_theme_color_override("font_color", title_color)
	if _subtitle_label != null:
		_subtitle_label.custom_minimum_size.x = max_width
		_subtitle_label.add_theme_font_size_override("font_size", subtitle_font_size)
		_subtitle_label.add_theme_color_override("font_color", subtitle_color)


func _layout_panel() -> void:
	if _panel == null:
		return
	var minimum := _panel.get_combined_minimum_size()
	_panel.size = minimum
	var viewport_size := get_viewport_rect().size
	var max_y := maxf(viewport_size.y - minimum.y - edge_margin, edge_margin)
	_rest_position = Vector2(
		edge_margin,
		clampf(viewport_size.y - minimum.y - edge_margin, edge_margin, max_y)
	)


func _on_hold_finished() -> void:
	if _visible_state:
		hide_lower_third(_pending_dismiss)


func _on_show_tween_finished() -> void:
	if _panel != null:
		_panel.modulate.a = 1.0
		_panel.position = _rest_position


func _on_hide_tween_finished() -> void:
	_visible_state = false
	if _panel != null:
		_panel.visible = false
		_panel.position = _rest_position
	lower_third_hidden.emit()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
