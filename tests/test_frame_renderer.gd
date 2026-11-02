extends "res://tests/support/test_case.gd"
## M4 test 3 — frame loop, PNG writing, cleanup, cancellation and failure paths.
## Capture is injected so the test runs headlessly; ffmpeg is faked the same way
## as in test_ffmpeg_encoder.gd. The injected await_frame seam advances one
## SceneTree frame per capture, matching the real draw-per-frame loop.

const OUTPUT := "user://m4_frame_renderer/take.mp4"
const FRAMES := "user://m4_frame_renderer/frames"


func _run_tests() -> void:
	_clean()
	var scratch := make_root("FrameRendererTest")
	var renderer := FrameRenderer.new()
	renderer.name = "FrameRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	var settings := _settings()
	var sequence := _hold_sequence(0.1)

	var started: Array[int] = []
	var frame_events: Array = []
	renderer.render_started.connect(
		func(count: int, _output: String) -> void: started.append(count)
	)
	renderer.frame_rendered.connect(
		func(index: int, total: int, path: String) -> void:
			frame_events.append([index, total, path])
	)
	renderer.capture_frame = func(index: int) -> Image:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 * float(index), 0.2, 0.3, 1.0))
		return image

	var encoded: Array[bool] = [false]
	var encoder := FfmpegEncoder.new("fake-ffmpeg")
	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, output: Array
	) -> int:
		if args.has("-version"):
			return 0
		encoded[0] = true
		_write_output(args)
		output.append("encoded 3 frames")
		return 0
	renderer.encoder = encoder

	var ok := await renderer.render(sequence, settings)
	check(ok, "render succeeds: %s" % renderer.get_last_error())
	check(not renderer.is_rendering(), "renderer is idle after success")
	check(started == [3], "render_started reports the frame count: %s" % [started])
	check(frame_events.size() == 3, "one frame event per captured frame")
	check(frame_events[0][0] == 0, "frame indices start at zero")
	check(frame_events[2][0] == 2, "last frame index is correct")
	check(frame_events[0][1] == 3, "frame events carry the total")
	check(
		String(frame_events[2][2]).ends_with("frame_000002.png"),
		"frame events carry the PNG path"
	)
	check(encoded[0], "encoder ran after capture")
	check(FileAccess.file_exists(settings.get_resolved_output_path()), "output file exists")
	check(
		_count_frames(settings.get_resolved_frames_dir()) == 0,
		"frames are cleaned after a successful encode"
	)
	var result := renderer.get_last_result()
	check(bool(result.get("ok", false)), "last result reports ok")
	check(int(result.get("frame_count", 0)) == 3, "last result stores the frame count")
	check(int(result.get("fps", 0)) == 30, "last result stores the fps")
	check(
		String(result.get("resolved_output_path", "")).ends_with("take.mp4"),
		"last result stores the resolved output"
	)
	check(String(result.get("ffmpeg_output", "")).contains("encoded 3"), "last result stores ffmpeg output")
	check(renderer.get_last_error().is_empty(), "last error is cleared on success")

	settings.keep_frames = true
	var keep_ok := await renderer.render(sequence, settings)
	check(keep_ok, "render with keep_frames succeeds")
	check(
		_count_frames(settings.get_resolved_frames_dir()) == 3,
		"keep_frames leaves the PNG sequence on disk"
	)
	settings.keep_frames = false

	var failures: Array[String] = []
	renderer.render_failed.connect(
		func(message: String) -> void: failures.append(message)
	)
	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, output: Array
	) -> int:
		if args.has("-version"):
			return 0
		output.append("Unknown encoder 'libx264'")
		return 1
	var failed := await renderer.render(sequence, settings)
	check(not failed, "ffmpeg failure fails the render")
	check(
		renderer.get_last_error().contains("ffmpeg exited with code 1"),
		"failure message includes the exit code"
	)
	check(
		renderer.get_last_error().contains("Unknown encoder"),
		"failure message includes ffmpeg output"
	)
	check(failures.size() == 1, "render_failed is emitted once")
	check(
		_count_frames(settings.get_resolved_frames_dir()) == 3,
		"frames are kept for debugging when ffmpeg fails"
	)
	check(not bool(renderer.get_last_result().get("ok", true)), "failure result reports not ok")

	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, output: Array
	) -> int:
		if args.has("-version"):
			return 0
		_write_output(args)
		output.append("ok")
		return 0
	renderer.capture_frame = func(index: int) -> Image:
		if index == 0:
			renderer.cancel()
		return Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var cancelled := await renderer.render(sequence, settings)
	check(not cancelled, "cancelled render returns false")
	check(
		renderer.get_last_error().contains("cancelled"),
		"cancellation records a clear message"
	)
	check(failures.size() == 2, "render_failed is emitted for cancellation")

	settings.overwrite = false
	var refused := await renderer.render(sequence, settings)
	check(not refused, "existing output is refused when overwrite is false")
	check(
		renderer.get_last_error().contains("already exists"),
		"overwrite refusal names the conflict"
	)
	settings.overwrite = true

	var empty := Sequence.new()
	var empty_ok := await renderer.render(empty, settings)
	check(not empty_ok, "zero-duration sequence is refused")
	check(
		renderer.get_last_error().contains("zero duration"),
		"zero-duration refusal explains why"
	)

	settings.fps = 0
	var fps_ok := await renderer.render(sequence, settings)
	check(not fps_ok, "fps below 1 is refused")
	check(
		renderer.get_last_error().contains("Invalid render settings"),
		"settings failure lists validation issues"
	)
	settings.fps = 30

	renderer.sequence = null
	var missing_ok := await renderer.render(null, settings)
	check(not missing_ok, "missing sequence is refused")
	check(
		renderer.get_last_error().contains("No sequence"),
		"missing sequence refusal is explicit"
	)

	var director := Director.new()
	director.name = "Director"
	scratch.add_child(director)
	renderer.director = director
	renderer.capture_frame = func(_index: int) -> Image:
		return Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var directed_ok := await renderer.render(sequence, settings)
	check(directed_ok, "directed render succeeds: %s" % renderer.get_last_error())
	check(not director.is_playing(), "renderer stops the director after capture")

	await _check_capture_order(scratch)
	await _check_frame_size_checks(scratch)
	await _check_subviewport_capture(scratch)
	await _check_encoder_preflight(scratch)

	await dispose(scratch)
	_clean()
	finish()


func _check_capture_order(scratch: Node) -> void:
	var director := _OrderDirector.new()
	director.name = "OrderDirector"
	scratch.add_child(director)
	var renderer := FrameRenderer.new()
	renderer.name = "OrderRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	renderer.director = director
	renderer.encoder = _fake_encoder()

	var starts: Array[bool] = []
	renderer.capture_frame = func(_index: int) -> Image:
		starts.append(director.played)
		return Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var ok := await renderer.render(_hold_sequence(0.1), _settings())
	check(ok, "ordered render succeeds: %s" % renderer.get_last_error())
	check(starts.size() == 3, "ordered render captures every frame")
	check(not starts[0], "frame 0 is captured before playback starts")
	check(starts[1], "playback starts after frame 0")


func _check_frame_size_checks(scratch: Node) -> void:
	var capture_viewport := SubViewport.new()
	capture_viewport.name = "SizeViewport"
	capture_viewport.size = Vector2i(16, 16)
	scratch.add_child(capture_viewport)
	var renderer := FrameRenderer.new()
	renderer.name = "SizeRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	renderer.capture_viewport = capture_viewport
	renderer.encoder = _fake_encoder()
	var settings := _settings()
	settings.resolution = Vector2i(4, 4)

	renderer.capture_frame = func(_index: int) -> Image:
		return Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var mismatch := await renderer.render(_hold_sequence(0.1), settings)
	check(not mismatch, "captured size mismatch fails the render")
	check(
		renderer.get_last_error().contains("Captured frame"),
		"size mismatch names the captured frame"
	)
	check(capture_viewport.size == Vector2i(16, 16), "size mismatch restores the viewport")

	settings.resolution = Vector2i.ZERO
	renderer.capture_frame = func(_index: int) -> Image:
		return Image.create(3, 3, false, Image.FORMAT_RGBA8)
	var odd := await renderer.render(_hold_sequence(0.1), settings)
	check(not odd, "odd captured frame fails for yuv420p")
	check(renderer.get_last_error().contains("even"), "odd frame failure explains the rule")


func _check_subviewport_capture(scratch: Node) -> void:
	var subviewport := SubViewport.new()
	subviewport.name = "CaptureViewport"
	subviewport.size = Vector2i(16, 16)
	subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	scratch.add_child(subviewport)
	var renderer := FrameRenderer.new()
	renderer.name = "SubviewportRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	renderer.capture_viewport = subviewport
	renderer.encoder = _fake_encoder()
	var settings := _settings()
	settings.resolution = Vector2i(8, 8)

	var observed_modes: Array[int] = []
	var observed_sizes: Array[Vector2i] = []
	renderer.capture_frame = func(_index: int) -> Image:
		observed_modes.append(subviewport.render_target_update_mode)
		observed_sizes.append(subviewport.size)
		return Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var ok := await renderer.render(_hold_sequence(0.1), settings)
	check(ok, "subviewport render succeeds: %s" % renderer.get_last_error())
	check(not observed_modes.is_empty(), "subviewport render captured frames")
	check(
		observed_modes[0] == SubViewport.UPDATE_ALWAYS,
		"subviewport updates every frame while rendering"
	)
	check(observed_sizes[0] == Vector2i(8, 8), "subviewport is resized for the render")
	check(
		subviewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE,
		"subviewport update mode is restored"
	)
	check(subviewport.size == Vector2i(16, 16), "subviewport size is restored")


func _check_encoder_preflight(scratch: Node) -> void:
	var renderer := FrameRenderer.new()
	renderer.name = "PreflightRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	var encoder := FfmpegEncoder.new("missing-ffmpeg")
	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, _output: Array
	) -> int:
		return 127 if args.has("-version") else 0
	renderer.encoder = encoder
	var captures: Array[int] = []
	renderer.capture_frame = func(index: int) -> Image:
		captures.append(index)
		return Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var settings := _settings()
	settings.ffmpeg_path = "missing-ffmpeg"
	var ok := await renderer.render(_hold_sequence(0.1), settings)
	check(not ok, "missing ffmpeg fails the render")
	check(
		renderer.get_last_error().contains("not available"),
		"missing ffmpeg failure names availability"
	)
	check(captures.is_empty(), "missing ffmpeg fails before capture")


func _settings() -> RenderSettings:
	var settings := RenderSettings.new()
	settings.output_path = OUTPUT
	settings.frames_dir = FRAMES
	settings.fps = 30
	return settings


func _hold_sequence(duration: float) -> Sequence:
	var sequence := Sequence.new()
	sequence.display_name = "render-test"
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = duration
	sequence.add_shot(shot)
	return sequence


func _await_process_frame() -> void:
	await process_frame


func _fake_encoder() -> FfmpegEncoder:
	var encoder := FfmpegEncoder.new("fake-ffmpeg")
	encoder.process_runner = _fake_runner
	return encoder


func _fake_runner(
	_executable: String, args: PackedStringArray, output: Array
) -> int:
	if args.has("-version"):
		return 0
	_write_output(args)
	output.append("encoded")
	return 0


func _write_output(args: PackedStringArray) -> void:
	if args.is_empty():
		return
	var file := FileAccess.open(String(args[args.size() - 1]), FileAccess.WRITE)
	if file != null:
		file.store_string("fake mp4")
		file.close()


func _count_frames(directory: String) -> int:
	var dir := DirAccess.open(directory)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with(RenderSettings.FRAME_PREFIX) and entry.ends_with(
			RenderSettings.FRAME_EXTENSION
		):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _clean() -> void:
	if FileAccess.file_exists(OUTPUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT))
	_remove_dir(FRAMES)
	_remove_dir("user://m4_frame_renderer")


func _remove_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)


class _OrderDirector:
	extends Director

	var played: bool = false

	func play(_sequence: Sequence) -> void:
		played = true
