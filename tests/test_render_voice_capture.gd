extends "res://tests/support/test_case.gd"
## M6 test 2 — FrameRenderer × AudioCaptureMixer integration.
##
## Capture and ffmpeg are faked through the documented seams, so this covers the
## wiring only: when a mixer is attached the render must mix the sequence's VO
## cues into a WAV beside the output, point [member RenderSettings.audio_path]
## at it, and hand the muxing arguments to ffmpeg. An authored audio file always
## wins; a mix that cannot be written must fail the render instead of muxing a
## stale narration file.

const OUTPUT := "user://m6_render_vo/take.mp4"
const FRAMES := "user://m6_render_vo/frames"
const MIXED_WAV := "user://m6_render_vo/take_voice.wav"
const PRE_MIXED := "user://m6_render_vo/premixed.wav"
const FAIL_OUTPUT := "user://m6_render_vo_fail/take.mp4"
const SAMPLE_RATE := 48000


func _run_tests() -> void:
	_clean()
	await _test_mixed_narration_muxes()
	_clean()
	await _test_explicit_audio_wins()
	_clean()
	await _test_silent_without_mixer()
	_clean()
	await _test_mix_failure_fails_render()
	_clean()
	finish()


# --- cases -------------------------------------------------------------------

func _test_mixed_narration_muxes() -> void:
	var renderer := _make_renderer()
	var captured_args: Array[PackedStringArray] = []
	renderer.encoder = _fake_encoder(captured_args)
	var mixer := AudioCaptureMixer.new()
	renderer.voice_mixer = mixer

	var settings := _settings(OUTPUT)
	var sequence := _vo_sequence(1.0)
	var ok := await renderer.render(sequence, settings)
	check(ok, "render with mixer succeeds: %s" % renderer.get_last_error())
	check(FileAccess.file_exists(MIXED_WAV), "narration WAV written next to the output")
	check(String(settings.audio_path) == MIXED_WAV,
			"audio_path points at the mix (got '%s')" % settings.audio_path)

	# The saved mix holds the clip: cue at 0.2 s, 0.3 s tone, hide at 0.9 s.
	var loaded := _load_wav_samples(MIXED_WAV)
	check(not loaded.is_empty(), "mix file decodes to samples")
	if not loaded.is_empty():
		var peak := _peak(loaded, int(0.25 * float(SAMPLE_RATE)), int(0.45 * float(SAMPLE_RATE)))
		check(peak > 0.5, "saved mix carries the narration (%f)" % peak)
		var tail := _peak(loaded, int(0.95 * float(SAMPLE_RATE)), loaded.size())
		check(tail < 0.01, "hide cue silences the tail of the saved mix (%f)" % tail)

	# The live mixer queue matches: audible mid-take, silent after the hide.
	var pcm := mixer.render_pcm(mixer.get_total_duration(1.0), 1)
	var live_peak := _peak(pcm, int(0.25 * float(SAMPLE_RATE)), int(0.45 * float(SAMPLE_RATE)))
	check(live_peak > 0.5, "mixer timeline carries the narration (%f)" % live_peak)
	var silent_tail := _peak(pcm, int(0.95 * float(SAMPLE_RATE)), pcm.size())
	check(silent_tail < 0.01, "live mix stays silent after the hide (%f)" % silent_tail)

	var encode_args := _encode_args(captured_args)
	var audio_index := encode_args.rfind("-i")
	check(audio_index >= 0 and String(encode_args[audio_index + 1]).ends_with("_voice.wav"),
			"the second input is the mixed WAV: %s" % [encode_args])
	check(encode_args.has("-af") and encode_args.has("-shortest"),
			"apad/-shortest chain stays intact")
	var result := renderer.get_last_result()
	check(bool(result.get("ok", false)), "result metadata reports success")
	check(int(result.get("frame_count", 0)) == 30,
			"thirty frames for a one-second take at 30 fps")
	check(not renderer.is_rendering(), "renderer is idle afterwards")
	await _dispose(renderer)


func _test_explicit_audio_wins() -> void:
	var renderer := _make_renderer()
	var captured_args: Array[PackedStringArray] = []
	renderer.encoder = _fake_encoder(captured_args)
	var mixer := AudioCaptureMixer.new()
	renderer.voice_mixer = mixer

	_write_premixed()
	var settings := _settings(OUTPUT)
	settings.audio_path = PRE_MIXED
	var ok := await renderer.render(_vo_sequence(1.0), settings)
	check(ok, "render with authored audio succeeds: %s" % renderer.get_last_error())
	check(not FileAccess.file_exists(MIXED_WAV),
			"authored audio skips the offline mix entirely")
	check(mixer.get_event_count() == 0, "mixer queue stays empty")
	var encode_args := _encode_args(captured_args)
	var audio_index := encode_args.rfind("-i")
	var audio_arg := String(encode_args[audio_index + 1]) if audio_index >= 0 else ""
	check(audio_arg.ends_with("premixed.wav"),
			"ffmpeg muxes the authored file instead (got '%s')" % audio_arg)
	await _dispose(renderer)


func _test_silent_without_mixer() -> void:
	var renderer := _make_renderer()
	var captured_args: Array[PackedStringArray] = []
	renderer.encoder = _fake_encoder(captured_args)

	var settings := _settings(OUTPUT)
	var ok := await renderer.render(_vo_sequence(1.0), settings)
	check(ok, "M4 behaviour survives without a mixer: %s" % renderer.get_last_error())
	check(not FileAccess.file_exists(MIXED_WAV), "no mix is produced without a mixer")
	var encode_args := _encode_args(captured_args)
	check(not " ".join(encode_args).contains("_voice.wav"),
			"video-only command never references the mix")
	await _dispose(renderer)


func _test_mix_failure_fails_render() -> void:
	var renderer := _make_renderer()
	var captured_args: Array[PackedStringArray] = []
	renderer.encoder = _fake_encoder(captured_args)
	var mixer := _UnwritableMixer.new()
	renderer.voice_mixer = mixer

	var settings := _settings(FAIL_OUTPUT)
	var ok := await renderer.render(_vo_sequence(1.0), settings)
	check(not ok, "render fails when the narration mix cannot be written")
	check(String(renderer.get_last_error()).contains("Narration mix failed"),
			"failure names the mix: %s" % renderer.get_last_error())
	check(captured_args.size() <= 1, "ffmpeg never ran after the mix failure")
	check(String(settings.audio_path).is_empty(),
			"a failed mix never rewrites audio_path")
	check(not renderer.is_rendering(), "renderer resets after the failure")
	await _dispose(renderer)


# --- helpers -----------------------------------------------------------------

## Mixer double whose WAV write always fails, mirroring a read-only disk.
class _UnwritableMixer:
	extends AudioCaptureMixer

	func mix_to_wav(_wav_path: String, _duration_seconds: float, _channel_count: int = 2) -> bool:
		return false


func _make_renderer() -> FrameRenderer:
	var scratch := make_root("M6RenderVo")
	var renderer := FrameRenderer.new()
	renderer.name = "FrameRenderer"
	scratch.add_child(renderer)
	renderer.await_frame = _await_process_frame
	renderer.capture_frame = func(_index: int) -> Image:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.3, 0.4, 1.0))
		return image
	return renderer


func _dispose(renderer: FrameRenderer) -> void:
	var parent := renderer.get_parent()
	renderer.queue_free()
	if parent != null:
		parent.queue_free()
	await process_frame
	await process_frame


func _fake_encoder(captured: Array[PackedStringArray]) -> FfmpegEncoder:
	var encoder := FfmpegEncoder.new("fake-ffmpeg")
	encoder.process_runner = func(
			_executable: String, args: PackedStringArray, output: Array
	) -> int:
		captured.append(args)
		if args.has("-version"):
			return 0
		_write_output(args)
		output.append("encoded with narration")
		return 0
	return encoder


func _encode_args(captured: Array[PackedStringArray]) -> PackedStringArray:
	for args in captured:
		if not args.has("-version"):
			return args
	return PackedStringArray()


func _write_output(args: PackedStringArray) -> void:
	if args.is_empty():
		return
	var file := FileAccess.open(String(args[args.size() - 1]), FileAccess.WRITE)
	if file != null:
		file.store_string("fake mp4")
		file.close()


## Writes an authored narration file so [method RenderSettings.validate] sees it.
func _write_premixed() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PRE_MIXED.get_base_dir())
	)
	var mixer := AudioCaptureMixer.new()
	mixer.queue_voice(_make_tone(0.2, 440.0, 0.5), 0.0)
	mixer.mix_to_wav(PRE_MIXED, 0.2, 1)


func _settings(output: String) -> RenderSettings:
	var settings := RenderSettings.new()
	settings.output_path = output
	settings.frames_dir = FRAMES
	settings.fps = 30
	return settings


func _vo_sequence(duration: float) -> Sequence:
	var sequence := Sequence.new()
	sequence.display_name = "m6-render-vo"
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = duration
	var voice := Cue.new()
	voice.time = 0.2
	voice.action = Cue.ACTION_VOICE_OVER
	voice.data = {"stream": _make_tone(0.3, 1000.0, 0.8)}
	var hide := Cue.new()
	hide.time = 0.9
	hide.action = Cue.ACTION_VOICE_OVER
	hide.data = {"hide": true}
	shot.cues = [voice, hide]
	sequence.add_shot(shot)
	return sequence


func _make_tone(seconds: float, frequency: float, amplitude: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var frames := int(seconds * float(SAMPLE_RATE))
	var samples := PackedByteArray()
	samples.resize(frames * 2)
	for index in frames:
		var value := amplitude * sin(TAU * frequency * float(index) / float(SAMPLE_RATE))
		samples.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	wav.data = samples
	return wav


## Decodes a 16-bit PCM WAV written by AudioCaptureMixer into [-1, 1] floats by
## scanning the `data` chunk — no engine audio loading involved. Multi-channel
## files are folded to their left channel so callers can index by frame.
func _load_wav_samples(path: String) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return output
	var bytes := file.get_buffer(int(file.get_length()))
	file.close()
	if bytes.size() < 12:
		return output
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return output
	var offset := 12
	var channels := 1
	while offset + 8 <= bytes.size():
		var chunk_id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := int(
				bytes[offset + 4]
				| (bytes[offset + 5] << 8)
				| (bytes[offset + 6] << 16)
				| (bytes[offset + 7] << 24)
		)
		var payload := offset + 8
		if chunk_id == "fmt " and chunk_size >= 4:
			channels = maxi(int(bytes[payload + 2] | (bytes[payload + 3] << 8)), 1)
		elif chunk_id == "data":
			var stride := channels * 2
			for index in range(payload, mini(payload + chunk_size - 1, bytes.size() - 1), stride):
				var raw := bytes[index] | (bytes[index + 1] << 8)
				if raw >= 32768:
					raw -= 65536
				output.append(float(raw) / 32768.0)
			return output
		offset = payload + chunk_size + (chunk_size % 2)
	return output


func _peak(pcm: PackedFloat32Array, from_frame: int, to_frame: int) -> float:
	var best := 0.0
	var total := pcm.size()
	for frame in range(maxi(from_frame, 0), mini(to_frame, total)):
		best = maxf(best, absf(pcm[frame]))
	return best


func _await_process_frame() -> void:
	await process_frame


func _clean() -> void:
	for directory in ["user://m6_render_vo", "user://m6_render_vo_fail"]:
		var dir := DirAccess.open(directory)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if dir.current_is_dir():
				var sub := DirAccess.open(directory.path_join(entry))
				if sub != null:
					sub.list_dir_begin()
					var child := sub.get_next()
					while not child.is_empty():
						sub.remove(child)
						child = sub.get_next()
					sub.list_dir_end()
			else:
				dir.remove(entry)
			entry = dir.get_next()
		dir.list_dir_end()
