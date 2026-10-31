class_name FrameRenderer
extends Node
## Deterministic frame capture and MP4 export (M4).
##
## [method render] starts a [Sequence] on a [Director], captures one viewport
## image per frame into [member RenderSettings.frames_dir], then asks
## [FfmpegEncoder] to encode the PNG sequence. Run with
## `--fixed-fps <settings.fps>` so Tweens advance by exactly one frame per
## capture; that fixed step is what makes repeated renders match.
##
## The node lives beside the Director in the demo scene, but it can also be
## created at runtime from a tool script:
##
## [codeblock]
## var renderer := FrameRenderer.new()
## add_child(renderer)
## renderer.director = director
## var ok := await renderer.render(sequence, render_settings)
## [/codeblock]

signal render_started(frame_count: int, output_path: String)
signal frame_rendered(index: int, total: int, frame_path: String)
signal encode_started(command: PackedStringArray)
signal render_finished(output_path: String)
signal render_failed(message: String)

## Director to drive. When unset the renderer only captures the current scene,
## which is useful for stills and for tests.
@export var director: Director

## Sequence rendered by [method render] when no override is passed.
@export var sequence: Sequence

## Render profile. A default profile is created when left empty.
@export var settings: RenderSettings

## Viewport to capture. Defaults to this node's viewport.
@export var capture_viewport: Viewport

## Encoder instance. Leave empty to create one from [member RenderSettings.ffmpeg_path].
var encoder: FfmpegEncoder

## Test seam: when valid, called with the frame index and must return an [Image].
## Real renders leave it invalid and read the viewport texture after a draw.
var capture_frame: Callable

var _rendering: bool = false
var _cancelled: bool = false
var _last_error: String = ""
var _last_result: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _saved_subviewport_size: Vector2i = Vector2i.ZERO
var _viewport_resized: bool = false


## Renders [param sequence_override] (or [member sequence]) using
## [param settings_override] (or [member settings]). Await the call to block
## until encoding finishes; returns `true` on success.
func render(
	sequence_override: Sequence = null, settings_override: RenderSettings = null
) -> bool:
	if _rendering:
		push_warning("FrameRenderer.render(): a render is already running.")
		return false
	var active_sequence := sequence_override if sequence_override != null else sequence
	var active_settings := settings_override if settings_override != null else settings
	if active_settings == null:
		active_settings = RenderSettings.new()
	if active_sequence == null:
		return _fail("No sequence to render.")

	for issue in active_sequence.validate():
		push_warning("FrameRenderer: %s" % issue)
	var duration := active_sequence.get_total_duration()
	var issues := active_settings.validate(duration)
	if duration <= 0.0:
		issues.append("Sequence has zero duration.")
	if not issues.is_empty():
		return _fail("Invalid render settings: %s" % " ".join(issues))

	var frame_count := active_settings.get_frame_count(duration)
	if frame_count <= 0:
		return _fail("Sequence duration produces no frames.")

	if not active_settings.overwrite and FileAccess.file_exists(
		active_settings.get_output_path()
	):
		return _fail("Output already exists: %s" % active_settings.get_output_path())

	sequence = active_sequence
	settings = active_settings
	_last_error = ""
	_last_result = {}
	_cancelled = false
	_rendering = true

	if not _ensure_directory(active_settings.get_resolved_frames_dir()):
		return _fail("Cannot create frames directory: %s" % active_settings.get_frames_dir())
	if not _ensure_directory(_parent_dir(active_settings.get_output_path())):
		return _fail("Cannot create output directory for %s" % active_settings.get_output_path())
	_clear_old_frames(active_settings)

	if encoder == null:
		encoder = FfmpegEncoder.new(active_settings.ffmpeg_path)

	await _apply_resolution(active_settings)
	if _cancelled:
		return _fail("Render cancelled.")

	render_started.emit(frame_count, active_settings.get_output_path())
	if director != null:
		director.play(active_sequence)

	for index in frame_count:
		if _cancelled:
			return _fail("Render cancelled.")
		var image: Image = await _grab_frame(index)
		if image == null:
			return _fail(
				"Frame %d could not be captured. Is a renderer available?" % index
			)
		var frame_path := active_settings.get_resolved_frames_dir().path_join(
			active_settings.get_frame_filename(index)
		)
		var save_error := image.save_png(frame_path)
		if save_error != OK:
			return _fail("Could not save frame %d (error %d)." % [index, save_error])
		frame_rendered.emit(index, frame_count, frame_path)

	_stop_playback()
	_restore_resolution()

	if _cancelled:
		return _fail("Render cancelled.")

	if encoder == null:
		return _fail("No ffmpeg encoder available.")
	encode_started.emit(active_settings.build_ffmpeg_args())
	var encode_result := encoder.encode(active_settings)
	if not bool(encode_result.get("ok", false)):
		var ffmpeg_output := String(encode_result.get("output", ""))
		var detail := ffmpeg_output.strip_edges()
		if detail.length() > 400:
			detail = detail.substr(detail.length() - 400)
		var message := "ffmpeg exited with code %d." % int(encode_result.get("exit_code", -1))
		if not detail.is_empty():
			message += " %s" % detail
		return _fail(message)

	if not active_settings.keep_frames:
		_clear_old_frames(active_settings)

	var output_path := active_settings.get_output_path()
	_last_result = {
		"ok": true,
		"output_path": output_path,
		"resolved_output_path": active_settings.get_resolved_output_path(),
		"frame_count": frame_count,
		"fps": active_settings.fps,
		"command": encode_result.get("command", PackedStringArray()),
		"ffmpeg_output": encode_result.get("output", ""),
	}
	_rendering = false
	render_finished.emit(output_path)
	return true


## Requests cancellation after the current frame. [method render] then returns
## `false` and emits [signal render_failed] with a `cancelled` message.
func cancel() -> void:
	if _rendering:
		_cancelled = true


## Whether a render is in flight.
func is_rendering() -> bool:
	return _rendering


## Last failure message, or an empty string after a successful render.
func get_last_error() -> String:
	return _last_error


## Metadata from the last render: output path, frame count, exact ffmpeg command
## and ffmpeg output. On failure it contains `ok: false` and `error`.
func get_last_result() -> Dictionary:
	return _last_result


func _grab_frame(index: int) -> Image:
	if capture_frame.is_valid():
		return capture_frame.call(index) as Image
	var viewport := capture_viewport
	if viewport == null and is_inside_tree():
		viewport = get_viewport()
	if viewport == null:
		return null
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()


func _apply_resolution(active_settings: RenderSettings) -> void:
	var target := active_settings.resolution
	if target.x <= 0 or target.y <= 0 or not is_inside_tree():
		return
	var viewport := capture_viewport if capture_viewport != null else get_viewport()
	if viewport is SubViewport:
		var subviewport := viewport as SubViewport
		_saved_subviewport_size = subviewport.size
		subviewport.size = target
		_viewport_resized = true
	else:
		var window := get_window()
		if window != null:
			_saved_window_size = window.size
			window.size = target
			_viewport_resized = true
	if _viewport_resized:
		await get_tree().process_frame


func _restore_resolution() -> void:
	if not _viewport_resized:
		return
	var viewport := capture_viewport if capture_viewport != null else get_viewport()
	if viewport is SubViewport:
		(viewport as SubViewport).size = _saved_subviewport_size
	else:
		var window := get_window()
		if window != null:
			window.size = _saved_window_size
	_viewport_resized = false


func _stop_playback() -> void:
	if director != null and director.is_playing():
		director.stop()


func _clear_old_frames(active_settings: RenderSettings) -> void:
	var dir := DirAccess.open(active_settings.get_resolved_frames_dir())
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with(RenderSettings.FRAME_PREFIX) and entry.ends_with(
			RenderSettings.FRAME_EXTENSION
		):
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _ensure_directory(path: String) -> bool:
	if path.is_empty():
		return true
	var absolute := _absolute_path(path)
	if absolute.is_empty():
		return false
	if DirAccess.dir_exists_absolute(absolute):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute) == OK


func _parent_dir(path: String) -> String:
	if path.is_empty():
		return ""
	var base := path.get_base_dir()
	if base == path or base == ".":
		return ""
	return base


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _fail(message: String) -> bool:
	_last_error = message
	_last_result = {"ok": false, "error": message}
	_stop_playback()
	_restore_resolution()
	_rendering = false
	render_failed.emit(message)
	return false
