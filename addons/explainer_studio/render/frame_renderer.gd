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
## Frame 0 is captured before playback starts, so it shows the sequence's
## initial state. The remaining frames land at `1/fps` through `(N-1)/fps`;
## `N/fps` is the take's duration and is not duplicated as a sample.
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

## Offline narration source for M6 VO capture. When set and
## [member RenderSettings.audio_path] is empty, [method render] mixes every
## `voice_over` cue through [AudioCaptureMixer] and muxes the resulting WAV
## instead of rendering silence.
var voice_mixer: AudioCaptureMixer

## Test seam: when valid, called after [member await_frame] with the frame index
## and must return an [Image]. Real renders leave it invalid and read the
## viewport texture after a draw. The callable is synchronous.
var capture_frame: Callable

## Test seam: awaited once before each capture. Defaults to
## [signal RenderingServer.frame_post_draw]. Headless tests inject a process
## frame await because the dummy renderer never emits the draw signal.
var await_frame: Callable

var _rendering: bool = false
var _cancelled: bool = false
var _last_error: String = ""
var _last_result: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _saved_subviewport_size: Vector2i = Vector2i.ZERO
var _saved_subviewport_update_mode: int = SubViewport.UPDATE_WHEN_VISIBLE
var _viewport_resized: bool = false
var _update_mode_overridden: bool = false
var _generated_audio_path: String = ""
var _mixed_event_count: int = 0


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
	# A previous pass writes its mixed narration into `audio_path`; that is an
	# output, not an authored track. Clear it so a repeat render re-mixes instead
	# of trusting a stale (or deleted) WAV from the last pass.
	if not _generated_audio_path.is_empty():
		if active_settings.audio_path == _generated_audio_path:
			active_settings.audio_path = ""
		_generated_audio_path = ""
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
	_mixed_event_count = 0
	_cancelled = false
	_rendering = true

	if encoder == null:
		encoder = FfmpegEncoder.new(active_settings.ffmpeg_path)
	if not encoder.is_available(active_settings):
		return _fail("ffmpeg is not available: %s" % active_settings.ffmpeg_path)

	if not _ensure_directory(active_settings.get_resolved_frames_dir()):
		return _fail("Cannot create frames directory: %s" % active_settings.get_frames_dir())
	if not _ensure_directory(_parent_dir(active_settings.get_output_path())):
		return _fail("Cannot create output directory for %s" % active_settings.get_output_path())
	_clear_old_frames(active_settings)

	await _apply_resolution(active_settings)
	if _cancelled:
		return _fail("Render cancelled.")

	render_started.emit(frame_count, active_settings.get_output_path())
	if _cancelled:
		return _fail("Render cancelled.")

	# Capture frame 0 before playback starts. Waiting for the first draw after
	# play() would already be one fixed step into the tween, shifting every
	# captured frame by one tick.
	var first_image := await _capture_frame_image(0)
	if first_image == null:
		return _fail("Frame 0 could not be captured. Is a renderer available?")
	var first_issue := _store_frame(0, first_image, active_settings, frame_count)
	if not first_issue.is_empty():
		return _fail(first_issue)
	if _cancelled:
		return _fail("Render cancelled.")

	if director != null:
		director.play(active_sequence)

	for index in range(1, frame_count):
		if _cancelled:
			return _fail("Render cancelled.")
		var image := await _capture_frame_image(index)
		if image == null:
			return _fail(
				"Frame %d could not be captured. Is a renderer available?" % index
			)
		var issue := _store_frame(index, image, active_settings, frame_count)
		if not issue.is_empty():
			return _fail(issue)

	_stop_playback()
	_restore_resolution()

	if _cancelled:
		return _fail("Render cancelled.")

	if not _prepare_mixed_audio(active_sequence, active_settings, duration):
		return false

	# Report only what this pass mixed: the mixer may still hold a queue from an
	# earlier render whose authored `audio_path` skipped [method _prepare_mixed_audio].
	var mixed_event_count := _mixed_event_count

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
		"audio_path": active_settings.audio_path,
		"voice_event_count": mixed_event_count,
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


func _capture_frame_image(index: int) -> Image:
	if not capture_frame.is_valid() and _get_capture_viewport() == null:
		return null
	await _await_frame()
	return _read_frame(index)


func _await_frame() -> void:
	if await_frame.is_valid():
		await await_frame.call()
		return
	await RenderingServer.frame_post_draw


func _read_frame(index: int) -> Image:
	if capture_frame.is_valid():
		return capture_frame.call(index) as Image
	var viewport := _get_capture_viewport()
	if viewport == null:
		return null
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()


func _store_frame(
	index: int, image: Image, active_settings: RenderSettings, frame_count: int
) -> String:
	var size_issue := _frame_size_issue(image, active_settings)
	if not size_issue.is_empty():
		return size_issue
	var frame_path := active_settings.get_resolved_frames_dir().path_join(
		active_settings.get_frame_filename(index)
	)
	var save_error := image.save_png(frame_path)
	if save_error != OK:
		return "Could not save frame %d (error %d)." % [index, save_error]
	frame_rendered.emit(index, frame_count, frame_path)
	return ""


func _frame_size_issue(image: Image, active_settings: RenderSettings) -> String:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return "Captured frame has no pixels."
	var target := active_settings.resolution
	if target.x > 0 and target.y > 0 and (width != target.x or height != target.y):
		return (
			"Captured frame is %dx%d but the render resolution is %dx%d. "
			+ "Check viewport/window scaling."
		) % [width, height, target.x, target.y]
	if active_settings.requires_even_dimensions() and (width % 2 != 0 or height % 2 != 0):
		return (
			"Captured frame %dx%d needs even width and height for %s."
			% [width, height, active_settings.pixel_format]
		)
	return ""


func _get_capture_viewport() -> Viewport:
	if capture_viewport != null and is_instance_valid(capture_viewport):
		return capture_viewport
	if is_inside_tree():
		return get_viewport()
	return null


func _apply_resolution(active_settings: RenderSettings) -> void:
	if not is_inside_tree():
		return
	var viewport := _get_capture_viewport()
	if viewport == null:
		return
	var target := active_settings.resolution
	var has_target := target.x > 0 and target.y > 0
	if viewport is SubViewport:
		var subviewport := viewport as SubViewport
		_saved_subviewport_update_mode = subviewport.render_target_update_mode
		subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_update_mode_overridden = true
		if has_target:
			_saved_subviewport_size = subviewport.size
			subviewport.size = target
			_viewport_resized = true
		await get_tree().process_frame
		return
	if not has_target:
		return
	var window := viewport as Window
	if window == null:
		window = get_window()
	if window != null:
		_saved_window_size = window.size
		window.size = target
		_viewport_resized = true
		await get_tree().process_frame


func _restore_resolution() -> void:
	if not _viewport_resized and not _update_mode_overridden:
		return
	var viewport := _get_capture_viewport()
	if viewport is SubViewport:
		var subviewport := viewport as SubViewport
		if _viewport_resized:
			subviewport.size = _saved_subviewport_size
		if _update_mode_overridden:
			subviewport.render_target_update_mode = _saved_subviewport_update_mode
	elif _viewport_resized:
		var window := viewport as Window
		if window == null:
			window = get_window()
		if window != null:
			window.size = _saved_window_size
	_viewport_resized = false
	_update_mode_overridden = false


func _stop_playback() -> void:
	if director != null and director.is_playing():
		director.stop()


## M6 offline VO capture: when a [AudioCaptureMixer] is attached and no audio
## file was authored, mix the sequence's `voice_over` cues into a WAV next to
## the output and point [member RenderSettings.audio_path] at it. An explicit
## `audio_path` always wins; without a mixer the render stays silent (M4).
## Returns `false` (after `_fail`) only when a configured mix could not be
## written, so callers never mux a stale or missing narration file.
func _prepare_mixed_audio(
	active_sequence: Sequence, active_settings: RenderSettings, duration: float
) -> bool:
	if active_settings.has_audio() or voice_mixer == null:
		# An authored track wins, but drop any queue left from an earlier pass so
		# [method get_event_count] never describes a take that was not mixed.
		if voice_mixer != null:
			voice_mixer.clear()
		return true
	voice_mixer.clear()
	if voice_mixer.consume_sequence(active_sequence) <= 0:
		return true
	var expected_wav_path := "%s_voice.wav" % active_settings.get_output_path().get_basename()
	if not _ensure_directory(_parent_dir(expected_wav_path)):
		return _fail("Cannot create directory for mixed narration: %s" % expected_wav_path)
	var total := maxf(voice_mixer.get_total_duration(duration), duration)
	if not voice_mixer.mix_to_wav(expected_wav_path, total):
		return _fail("Narration mix failed to save: %s" % expected_wav_path)
	# The mixer (or a subclass with a custom exporter) decides where the audio
	# actually landed; fall back to the conventional name when it stays silent.
	var wav_path := voice_mixer.get_last_mix_path()
	if wav_path.is_empty():
		wav_path = expected_wav_path
	active_settings.audio_path = wav_path
	_generated_audio_path = wav_path
	_mixed_event_count = voice_mixer.get_event_count()
	print("[FrameRenderer] mixed %d VO event(s) → %s" % [voice_mixer.get_event_count(), wav_path])
	return true


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
