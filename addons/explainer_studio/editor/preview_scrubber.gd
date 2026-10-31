@tool
extends Control
## Studio preview scrubber: shot spans, cue dots, markers and a playhead.
##
## The control is intentionally passive. It renders a [PreviewTimeline] and
## emits [signal seek_requested] / [signal shot_clicked]; the dock owns playback
## state and never lets the widget animate a camera directly.

signal seek_requested(time: float)
signal shot_clicked(shot_index: int)
signal toggle_play_requested

const RULER_HEIGHT := 18.0
const BAND_TOP := 22.0
const MIN_HEIGHT := 88.0

const COLOR_BACKGROUND := Color(0.075, 0.082, 0.105, 1.0)
const COLOR_BORDER := Color(1.0, 1.0, 1.0, 0.09)
const COLOR_SHOT_A := Color(0.114, 0.176, 0.235, 1.0)
const COLOR_SHOT_B := Color(0.102, 0.153, 0.212, 1.0)
const COLOR_SHOT_SELECTED := Color(0.137, 0.263, 0.329, 1.0)
const COLOR_ACCENT := Color(0.298, 0.776, 0.898, 1.0)
const COLOR_SELECTED := Color(0.980, 0.753, 0.333, 1.0)
const COLOR_TEXT := Color(0.780, 0.835, 0.910, 1.0)
const COLOR_MUTED := Color(0.470, 0.525, 0.608, 1.0)
const COLOR_MARKER := Color(0.925, 0.541, 0.369, 1.0)

var timeline := PreviewTimeline.new()

## Playhead position in sequence seconds.
var time: float = 0.0
## Highlighted shot, or `-1`.
var selected_shot: int = -1
## Highlighted cue inside [member selected_shot], or `-1`.
var selected_cue: int = -1

var _scrubbing: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, MIN_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "Click or drag to scrub. Arrow keys step, Shift jumps 1s, Space toggles play."
	resized.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


## Loads a sequence and clamps the playhead into its new range.
func set_sequence(sequence: Sequence) -> void:
	timeline.set_sequence(sequence)
	time = clampf(time, 0.0, timeline.get_duration())
	queue_redraw()


## Moves the playhead. When [param notify] is true [signal seek_requested] fires.
func set_time(value: float, notify: bool = false) -> void:
	var clamped := clampf(value, 0.0, timeline.get_duration())
	if is_equal_approx(clamped, time):
		if notify:
			seek_requested.emit(time)
		return
	time = clamped
	queue_redraw()
	if notify:
		seek_requested.emit(time)


## Current playhead position in seconds.
func get_time() -> float:
	return time


## Highlights the selected shot/cue from the dock.
func set_selection(shot_index: int, cue_index: int) -> void:
	if selected_shot == shot_index and selected_cue == cue_index:
		return
	selected_shot = shot_index
	selected_cue = cue_index
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				grab_focus()
				_scrubbing = true
				_seek_from_x(mouse.position.x, true)
			else:
				_scrubbing = false
			accept_event()
			return
	if event is InputEventMouseMotion and _scrubbing:
		_seek_from_x((event as InputEventMouseMotion).position.x, false)
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var step := 0.1
		if key.shift_pressed:
			step = 1.0
		elif key.ctrl_pressed:
			step = 1.0 / 30.0
		match key.keycode:
			KEY_LEFT:
				set_time(time - step, true)
				accept_event()
			KEY_RIGHT:
				set_time(time + step, true)
				accept_event()
			KEY_HOME:
				set_time(0.0, true)
				accept_event()
			KEY_END:
				set_time(timeline.get_duration(), true)
				accept_event()
			KEY_SPACE:
				toggle_play_requested.emit()
				accept_event()


func _seek_from_x(x: float, clicked: bool) -> void:
	var next_time := timeline.x_to_time(x, size.x)
	next_time = timeline.snap_time_to_marker(next_time, size.x)
	set_time(next_time, true)
	if clicked:
		shot_clicked.emit(timeline.get_shot_index_at(next_time))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND, true)
	if not timeline.has_content():
		_draw_empty_state()
		_draw_border()
		return

	_draw_ruler()
	_draw_shots()
	_draw_cues()
	_draw_markers()
	_draw_playhead()
	_draw_border()


func _draw_border() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.0)


func _draw_empty_state() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := maxi(get_theme_font_size("font_size", "Label") - 2, 9)
	draw_string(
		font,
		Vector2(0.0, size.y * 0.5 + font_size * 0.35),
		"Load a sequence to scrub",
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		font_size,
		COLOR_MUTED
	)


func _draw_ruler() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := maxi(get_theme_font_size("font_size", "Label") - 3, 8)
	var duration := timeline.get_duration()
	var interval := timeline.get_tick_interval()
	var tick := 0.0
	while tick <= duration + 0.0001:
		var x := timeline.time_to_x(tick, size.x)
		draw_line(Vector2(x, RULER_HEIGHT - 5.0), Vector2(x, RULER_HEIGHT), COLOR_MUTED, 1.0)
		var label := (
			"%.1fs" % tick if interval < 1.0 else "%ds" % int(round(tick))
		)
		draw_string(
			font,
			Vector2(x - 14.0, RULER_HEIGHT - 8.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			28.0,
			font_size,
			COLOR_MUTED
		)
		tick += interval


func _draw_shots() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := maxi(get_theme_font_size("font_size", "Label") - 2, 9)
	var band_height := clampf(size.y * 0.30, 18.0, 30.0)
	var band_bottom := BAND_TOP + band_height
	var segments := timeline.get_segments()
	for segment in segments:
		var index := int(segment.get("index", -1))
		var start := float(segment.get("start", 0.0))
		var end := float(segment.get("end", 0.0))
		var x1 := timeline.time_to_x(start, size.x)
		var x2 := timeline.time_to_x(end, size.x)
		var rect := Rect2(x1, BAND_TOP, maxf(x2 - x1, 1.0), band_height)
		var fill := COLOR_SHOT_A if index % 2 == 0 else COLOR_SHOT_B
		if index == selected_shot:
			fill = COLOR_SHOT_SELECTED
		draw_rect(rect, fill, true)
		draw_rect(rect, COLOR_BORDER, false, 1.0)
		if rect.size.x >= 38.0:
			var shot := timeline.sequence.shots[index]
			var kind_name := "unknown" if shot == null else shot.get_kind_name()
			var label := "%d · %s" % [index + 1, kind_name]
			draw_string(
				font,
				Vector2(x1 + 5.0, BAND_TOP + band_height * 0.5 + font_size * 0.35),
				label,
				HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 10.0,
				font_size,
				COLOR_TEXT
			)
		if index == selected_shot:
			draw_rect(rect, COLOR_SELECTED, false, 1.5)
	# A zero-length shot still gets a visible boundary tick.
	for index in range(1, segments.size()):
		var x := timeline.time_to_x(float(segments[index].get("start", 0.0)), size.x)
		draw_line(Vector2(x, BAND_TOP), Vector2(x, band_bottom), COLOR_BACKGROUND, 1.0)


func _draw_cues() -> void:
	var band_bottom := BAND_TOP + clampf(size.y * 0.30, 18.0, 30.0)
	var cue_y := minf(band_bottom + 12.0, size.y - 24.0)
	for event in timeline.get_cue_events():
		var x := timeline.time_to_x(float(event.get("time", 0.0)), size.x)
		var is_marker := bool(event.get("marker", false))
		draw_circle(Vector2(x, cue_y), 3.0, COLOR_MARKER if is_marker else COLOR_ACCENT)
		var is_selected := (
			int(event.get("shot_index", -1)) == selected_shot
			and int(event.get("cue_index", -1)) == selected_cue
		)
		if is_selected:
			draw_arc(Vector2(x, cue_y), 5.0, 0.0, TAU, 16, COLOR_SELECTED, 1.5)


func _draw_markers() -> void:
	var marker_y := size.y - 11.0
	for event in timeline.get_marker_events():
		var x := timeline.time_to_x(float(event.get("time", 0.0)), size.x)
		var points := PackedVector2Array([
			Vector2(x, marker_y - 5.0),
			Vector2(x + 4.5, marker_y),
			Vector2(x, marker_y + 5.0),
			Vector2(x - 4.5, marker_y),
		])
		draw_colored_polygon(points, COLOR_MARKER)


func _draw_playhead() -> void:
	var x := timeline.time_to_x(time, size.x)
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), COLOR_SELECTED, 2.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(x - 5.0, 0.0),
			Vector2(x + 5.0, 0.0),
			Vector2(x, 7.0),
		]),
		COLOR_SELECTED
	)
