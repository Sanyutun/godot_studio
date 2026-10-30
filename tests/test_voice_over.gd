extends "res://tests/support/test_case.gd"
## M3 test — cue-driven voice-over playback, track overrides, fades and stop.
##
## Audio is generated at runtime as a short 16-bit WAV, so the suite stays
## dependency-free and works headless (Godot's dummy audio driver still advances
## playback and emits `finished`).

const FRAME := 1.0 / 60.0


func _run_tests() -> void:
	await _check_direct_play_and_finish()
	await _check_fade_in()
	await _check_cue_play_with_track()
	await _check_cue_hide_fades_out()
	await _check_stop_voice()
	await _check_director_target_and_outliving_shot()
	_check_track_resource()
	finish()


func _build_stage(stage_name: String) -> Array[Node]:
	var scratch := make_root(stage_name)
	var voice := VoiceOver.new()
	voice.name = "VoiceOver"
	scratch.add_child(voice)
	await process_frame
	return [scratch, voice]


func _make_blip(length: float = 0.3, frequency: float = 440.0) -> AudioStreamWAV:
	const MIX_RATE := 44100
	var frames := maxi(int(ceil(length * MIX_RATE)), 1)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for frame in frames:
		var sample := sin(TAU * frequency * float(frame) / MIX_RATE) * 0.15
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _check_direct_play_and_finish() -> void:
	var stage := await _build_stage("VoiceDirect")
	var scratch: Node = stage[0]
	var voice := stage[1] as VoiceOver
	var stream := _make_blip(0.28)
	var started: Array[AudioStream] = []
	var finished_count: Array[int] = [0]
	voice.voice_started.connect(func(value: AudioStream) -> void: started.append(value))
	voice.voice_finished.connect(func() -> void: finished_count[0] += 1)

	var tween := voice.play_voice(stream, -3.0, 0.0, 0.0)
	check(tween != null, "play_voice returns a tween")
	check(voice.is_voice_playing(), "play_voice starts playback")
	check(voice.get_active_stream() == stream, "active stream is reported")
	check_approx(voice.volume_db, -3.0, 0.01, "zero fade starts at target gain")
	check(started.size() == 1, "voice_started emitted once")
	check(started[0] == stream, "voice_started carries the stream")

	await wait(0.4)
	check(finished_count[0] == 1, "voice_finished emitted when the clip ends")
	check(not voice.is_voice_playing(), "player is idle after the clip")
	check(voice.get_active_stream() == null, "active stream clears after the clip")

	await dispose(scratch)


func _check_fade_in() -> void:
	var stage := await _build_stage("VoiceFadeIn")
	var scratch: Node = stage[0]
	var voice := stage[1] as VoiceOver
	var stream := _make_blip(0.4)

	voice.play_voice(stream, -4.0, 0.08, 0.0)
	check(voice.volume_db <= VoiceOver.SILENT_DB + 0.5, "fade-in starts silent")
	await wait(0.16)
	check_approx(voice.volume_db, -4.0, 0.5, "fade-in reaches the target gain")
	voice.stop_voice(0.0)

	await dispose(scratch)


func _check_cue_play_with_track() -> void:
	var stage := await _build_stage("VoiceCue")
	var scratch: Node = stage[0]
	var voice := stage[1] as VoiceOver
	var stream := _make_blip(0.5)
	var track := VoiceTrack.new()
	track.stream = stream
	track.volume_db = -6.0
	track.bus = &"Master"
	track.fade_in = 0.05
	track.start_offset = 0.02

	var cue := Cue.new()
	cue.action = Cue.ACTION_VOICE_OVER
	cue.data = {"track": track}
	var event := CueEvent.new()
	event.cue = cue
	event.remaining = 0.5
	voice.on_cue(event)

	check(voice.is_voice_playing(), "cue starts the voice-over")
	check(voice.get_active_stream() == stream, "cue uses the track stream")
	check(voice.bus == &"Master", "cue applies the track bus")
	await wait(0.14)
	check_approx(voice.volume_db, -6.0, 0.5, "cue applies the track gain")

	# Per-cue values override the track.
	var override_cue := Cue.new()
	override_cue.action = Cue.ACTION_VOICE_OVER
	override_cue.data = {
		"track": track,
		"volume_db": -2.0,
		"fade_in": 0.0,
		"from": 0.0,
	}
	var override_event := CueEvent.new()
	override_event.cue = override_cue
	override_event.remaining = 0.5
	voice.on_cue(override_event)
	check_approx(voice.volume_db, -2.0, 0.01, "per-cue gain overrides the track")
	voice.stop_voice(0.0)

	await dispose(scratch)


func _check_cue_hide_fades_out() -> void:
	var stage := await _build_stage("VoiceCueHide")
	var scratch: Node = stage[0]
	var voice := stage[1] as VoiceOver
	var stream := _make_blip(0.6)
	var stopped: Array[int] = [0]
	voice.voice_stopped.connect(func() -> void: stopped[0] += 1)
	voice.play_voice(stream, 0.0, 0.0, 0.0)

	var cue := Cue.new()
	cue.action = Cue.ACTION_VOICE_OVER
	cue.data = {"hide": true, "duration": 0.05}
	var event := CueEvent.new()
	event.cue = cue
	event.remaining = 0.5
	voice.on_cue(event)
	await wait(0.14)

	check(not voice.is_voice_playing(), "hide cue stops the voice-over")
	check(stopped[0] == 1, "hide cue emits voice_stopped once")

	await dispose(scratch)


func _check_stop_voice() -> void:
	var stage := await _build_stage("VoiceStop")
	var scratch: Node = stage[0]
	var voice := stage[1] as VoiceOver
	var stream := _make_blip(0.8)
	var stopped: Array[int] = [0]
	voice.voice_stopped.connect(func() -> void: stopped[0] += 1)

	check(voice.stop_voice() == null, "stop_voice is a no-op when idle")
	voice.play_voice(stream, 0.0, 0.0, 0.0)
	var tween := voice.stop_voice(0.05)
	check(tween != null, "stop_voice returns the fade tween")
	if tween != null:
		await tween.finished
	await wait(0.02)
	check(not voice.is_voice_playing(), "fade-out stops playback")
	check(stopped[0] == 1, "voice_stopped emitted once")

	await dispose(scratch)


func _check_director_target_and_outliving_shot() -> void:
	var scratch := make_root("VoiceDirector")
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	var voice := VoiceOver.new()
	voice.name = "VoiceOver"
	scratch.add_child(voice)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)
	await process_frame

	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.15
	var cue := Cue.new()
	cue.action = Cue.ACTION_VOICE_OVER
	cue.target = NodePath("../VoiceOver")
	cue.data = {"stream": _make_blip(0.5)}
	shot.cues = [cue]
	var sequence := Sequence.new()
	sequence.add_shot(shot)

	var started: Array[int] = [0]
	voice.voice_started.connect(func(_stream: AudioStream) -> void: started[0] += 1)
	await director.play(sequence)

	check(started[0] == 1, "Director resolves the VoiceOver cue target")
	check(voice.is_voice_playing(), "voice-over outlives the shot that started it")
	voice.stop_voice(0.0)
	check(not voice.is_voice_playing(), "explicit stop ends the outliving voice-over")

	await dispose(scratch)


func _check_track_resource() -> void:
	var track := VoiceTrack.new()
	check(not track.is_playable(), "empty track is not playable")
	check_approx(track.get_length(), 0.0, 0.0001, "empty track length is zero")
	track.stream = _make_blip(0.2)
	check(track.is_playable(), "track with a stream is playable")
	check(track.get_length() > 0.19, "track reports the stream length")
	check(Cue.new().is_known_action(), "default caption action is known")
	var cue := Cue.new()
	cue.action = Cue.ACTION_VOICE_OVER
	check(cue.is_known_action(), "voice_over is a known action")
