extends "res://tests/support/test_case.gd"
## M6 test 1 — offline narration capture and WAV mixing.
##
## Everything here is pure: no nodes, no engine clock, no ffmpeg. The clips are
## generated in memory (1 kHz / 440 Hz sine bursts) so peak and envelope checks
## have exact expected values.

const EPSILON := 0.0005


func _run_tests() -> void:
	_test_wav_container()
	_test_queue_validation()
	_test_event_counting_and_duration()
	_test_pcm_mixing()
	_test_resampling()
	_test_hide_fade()
	_test_db_gain()
	_test_sequence_resolution()
	_test_marker_resolution()
	_test_track_defaults_precedence()
	_test_render_default_stream()
	_test_hide_variants()
	await _test_file_roundtrip()
	finish()


# --- helpers ---------------------------------------------------------------

func _make_tone(
	seconds: float, frequency: float, amplitude: float, mix_rate: int = 48000
) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	var frames := int(seconds * float(mix_rate))
	var samples := PackedByteArray()
	samples.resize(frames * 2)
	for index in frames:
		var value := amplitude * sin(TAU * frequency * float(index) / float(mix_rate))
		samples.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	wav.data = samples
	return wav


func _hold_shot(duration: float) -> Shot:
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = duration
	return shot


func _voice_cue(time: float, data: Dictionary) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = Cue.ACTION_VOICE_OVER
	cue.data = data
	return cue


func _peak(pcm: PackedFloat32Array, from_frame: int, to_frame: int) -> float:
	var best := 0.0
	var total := pcm.size()
	for frame in range(maxi(from_frame, 0), mini(to_frame, total)):
		best = maxf(best, absf(pcm[frame]))
	return best


func _rms(pcm: PackedFloat32Array, from_frame: int, to_frame: int) -> float:
	var sum := 0.0
	var count := 0
	var total := pcm.size()
	for frame in range(maxi(from_frame, 0), mini(to_frame, total)):
		sum += pcm[frame] * pcm[frame]
		count += 1
	if count == 0:
		return 0.0
	return sqrt(sum / float(count))


# --- container + queue validation -------------------------------------------

func _test_wav_container() -> void:
	var mixer := AudioCaptureMixer.new()
	var pcm := PackedFloat32Array([0.5, -0.25, 1.0, -1.0, 0.0])
	var wav := mixer.build_wav(pcm, 1)
	check(wav.format == AudioStreamWAV.FORMAT_16_BITS, "build_wav emits 16-bit PCM")
	check(not wav.stereo, "mono build_wav leaves stereo off")
	check(wav.mix_rate == AudioCaptureMixer.DEFAULT_SAMPLE_RATE, "default rate is 48 kHz")
	check(wav.data.size() == pcm.size() * 2, "two bytes per float sample")
	check_approx(float(wav.data.decode_s16(0)) / 32767.0, 0.5, 0.001, "0.5 maps near 16383 counts")
	check(wav.data.decode_s16(4) == 32767, "+1.0 clamps to full-scale positive")
	check(wav.data.decode_s16(6) == -32767 or wav.data.decode_s16(6) == -32768, "-1.0 maps to full-scale negative")

	var stereo := mixer.build_wav(PackedFloat32Array([0.1, 0.2]), 2)
	check(stereo.stereo, "channel_count 2 flags the stream stereo")

	# Stereo round trip keeps each channel's own level.
	var stereo_wav := mixer.build_wav(PackedFloat32Array([0.25, -0.5]), 2)
	check(stereo_wav.data.size() == 4, "stereo build keeps interleaved length")
	check_approx(float(stereo_wav.data.decode_s16(0)) / 32767.0, 0.25, 0.001, "left channel survives build")
	check_approx(float(stereo_wav.data.decode_s16(2)) / 32767.0, -0.5, 0.001, "right channel survives build")


func _test_queue_validation() -> void:
	var mixer := AudioCaptureMixer.new()
	var clip := _make_tone(0.1, 1000.0, 0.9)
	var bad_format := AudioStreamWAV.new()
	bad_format.format = AudioStreamWAV.FORMAT_8_BITS
	bad_format.data = PackedByteArray([0, 1, 2, 3])

	check(not mixer.queue_voice(null, 0.0), "null stream is rejected")
	check(mixer.get_event_count() == 0, "null stream adds no event")
	check(not mixer.queue_voice(bad_format, 0.0), "non-16-bit stream is rejected")
	check(mixer.get_event_count() == 0, "rejected queue adds no event")
	check(mixer.queue_voice(clip, 0.0), "16-bit mono stream is accepted")
	check(mixer.queue_voice(clip, -5.0), "negative start times are accepted")
	check(mixer.get_event_count() == 2, "two accepted events queued")
	mixer.clear()
	check(mixer.get_event_count() == 0, "clear empties the queue")


func _test_event_counting_and_duration() -> void:
	var mixer := AudioCaptureMixer.new()
	var clip := _make_tone(0.5, 1000.0, 0.5)
	var queued := mixer.queue_voice(clip, 1.0)
	check(queued, "queue_voice reports success")
	check(mixer.get_total_duration() >= 1.49 and mixer.get_total_duration() <= 1.51,
			"total duration follows the latest clip end: %f" % mixer.get_total_duration())
	check_approx(mixer.get_total_duration(3.0), 3.0, EPSILON,
			"min_duration floors short narration")
	check_approx(mixer.get_total_duration(0.2), 1.5, EPSILON,
			"a small min_duration never truncates the clip end")
	mixer.queue_hide(0.5)
	check_approx(mixer.get_total_duration(0.0), 1.5, EPSILON,
			"hide events do not extend the timeline")


func _test_pcm_mixing() -> void:
	var mixer := AudioCaptureMixer.new()
	var rate := mixer.get_sample_rate()
	var clip := _make_tone(0.1, 1000.0, 0.9)
	check(mixer.queue_voice(clip, 0.05), "clip queued at 50 ms")
	var pcm := mixer.render_pcm(0.2, 1)
	check(pcm.size() == int(0.2 * float(rate)), "render_pcm returns one frame per output frame")
	var silence_peak := _peak(pcm, 0, int(0.04 * float(rate)))
	check(silence_peak < 0.01, "pre-roll stays silent (peak %f)" % silence_peak)
	var tone_peak := _peak(pcm, int(0.07 * float(rate)), int(0.14 * float(rate)))
	check(tone_peak > 0.8 and tone_peak <= 0.95, "clip lands at its offset with gain intact (%f)" % tone_peak)
	var tail_peak := _peak(pcm, int(0.17 * float(rate)), pcm.size())
	check(tail_peak < 0.01, "audio after the clip end is silent (%f)" % tail_peak)

	# Two half-scale overlapping clips sum without hitting the clamp, so the RMS
	# growth is the uncorrelated quadrature ratio (~1.41), not a clipping artefact.
	var additive := AudioCaptureMixer.new()
	additive.queue_voice(_make_tone(0.1, 1000.0, 0.5), 0.05)
	var single_pcm := additive.render_pcm(0.2, 1)
	additive.queue_voice(_make_tone(0.1, 440.0, 0.5), 0.05)
	var summed := additive.render_pcm(0.2, 1)
	var overlap_rms := _rms(summed, int(0.07 * float(rate)), int(0.10 * float(rate)))
	var single_rms := _rms(single_pcm, int(0.07 * float(rate)), int(0.10 * float(rate)))
	check(overlap_rms > single_rms * 1.3, "overlapping clips mix additively (%f vs %f)" % [overlap_rms, single_rms])

	# Full-scale clips still clamp at the edges instead of wrapping.
	mixer.queue_voice(_make_tone(0.1, 440.0, 0.9), 0.05)
	var loud_sum := mixer.render_pcm(0.2, 1)
	var clipped := true
	for value in loud_sum:
		if value > 1.0 or value < -1.0:
			clipped = false
			break
	check(clipped, "mixed output is clamped to [-1, 1]")

	# Stereo duplication: mono source fills both channels.
	var stereo := mixer.render_pcm(0.2, 2)
	check(stereo.size() == int(0.2 * float(rate)) * 2, "stereo render interleaves two channels")
	var left := _peak(stereo, int(0.07 * float(rate)), int(0.14 * float(rate)))
	var right := 0.0
	var start := int(0.07 * float(rate)) * 2
	var stop := int(0.14 * float(rate)) * 2
	for index in range(start + 1, mini(stop + 1, stereo.size()), 2):
		right = maxf(right, absf(stereo[index]))
	check(left > 0.8 and right > 0.8, "mono clip is duplicated across both channels")

	# fade_in ramps up over the requested seconds.
	var ramped := AudioCaptureMixer.new()
	ramped.queue_voice(_make_tone(0.2, 1000.0, 0.9), 0.0, 1.0, 0.1)
	var ramp_pcm := ramped.render_pcm(0.25, 1)
	var early := _rms(ramp_pcm, 0, int(0.01 * float(rate)))
	var late := _rms(ramp_pcm, int(0.15 * float(rate)), int(0.19 * float(rate)))
	check(early < late * 0.25, "fade_in starts quiet (early %f, late %f)" % [early, late])

	check(mixer.render_pcm(0.0, 1).is_empty(), "zero-length render returns nothing")
	check(mixer.render_pcm(-1.0, 1).is_empty(), "negative lengths clamp to empty")


func _test_resampling() -> void:
	# Sources can run at any rate (the demo generates 44.1 kHz blips); the
	# mixer resamples them to its 48 kHz output without truncating the tail.
	var low := AudioCaptureMixer.new()
	low.queue_voice(_make_tone(0.2, 1000.0, 0.5, 22050), 0.0)
	var low_pcm := low.render_pcm(0.2, 1)
	check(low_pcm.size() == int(0.2 * float(low.get_sample_rate())),
			"low-rate source fills the output window")
	check(_peak(low_pcm, int(0.18 * 48000.0), low_pcm.size()) > 0.3,
			"low-rate source is resampled through to its end")
	check_approx(low.get_total_duration(), 0.2, 0.001,
			"duration follows the source clock")

	var high := AudioCaptureMixer.new()
	high.queue_voice(_make_tone(0.2, 1000.0, 0.5, 96000), 0.0)
	var high_pcm := high.render_pcm(0.2, 1)
	check(_peak(high_pcm, int(0.18 * 48000.0), high_pcm.size()) > 0.3,
			"high-rate source is decimated cleanly")
	check_approx(high.get_total_duration(), 0.2, 0.001,
			"duration follows the source clock")


func _test_hide_fade() -> void:
	var mixer := AudioCaptureMixer.new()
	mixer.queue_voice(_make_tone(1.0, 1000.0, 0.9), 0.0)
	mixer.queue_hide(0.5, 0.1)
	var pcm := mixer.render_pcm(1.0, 1)
	var rate := mixer.get_sample_rate()
	var before := _rms(pcm, int(0.40 * float(rate)), int(0.49 * float(rate)))
	var mid := _rms(pcm, int(0.52 * float(rate)), int(0.56 * float(rate)))
	var after := _rms(pcm, int(0.62 * float(rate)), int(0.90 * float(rate)))
	check(before > 0.1, "audio plays before the hide (%f)" % before)
	check(mid < before * 0.75, "hide fades the clip out (%f < %f)" % [mid, before])
	check(after < 0.01, "silence once the fade completes (%f)" % after)

	# A hide without an explicit fade uses DEFAULT_HIDE_FADE.
	var defaults := AudioCaptureMixer.new()
	defaults.queue_voice(_make_tone(1.0, 1000.0, 0.9), 0.0)
	defaults.queue_hide(0.5)
	var default_pcm := defaults.render_pcm(1.0, 1)
	var just_after := _rms(default_pcm, int(0.50 * float(rate)), int(0.52 * float(rate)))
	var well_after := _rms(default_pcm, int(0.70 * float(rate)), int(0.90 * float(rate)))
	check(just_after > well_after, "default hide fade ramps down")
	check(well_after < 0.01, "default fade fully silences the clip (%f)" % well_after)

	# A hide at/after the end of the render window is a no-op.
	var late_hide := AudioCaptureMixer.new()
	late_hide.queue_voice(_make_tone(0.1, 1000.0, 0.9), 0.0)
	late_hide.queue_hide(0.5)
	var untouched := late_hide.render_pcm(0.1, 1)
	var kept := _rms(untouched, int(0.02 * float(rate)), int(0.09 * float(rate)))
	check(kept > 0.1, "hide beyond the render window changes nothing (%f)" % kept)


func _test_db_gain() -> void:
	var mixer := AudioCaptureMixer.new()
	var loud := _make_tone(0.1, 1000.0, 0.9)
	mixer.queue_voice(loud, 0.0, AudioCaptureMixer.db_to_linear(-6.0206))
	var pcm := mixer.render_pcm(0.15, 1)
	var peak := _peak(pcm, int(0.02 * 48000), int(0.09 * 48000))
	check(peak > 0.4 and peak < 0.5, "-6 dB halves the amplitude (peak %f)" % peak)
	check_approx(AudioCaptureMixer.db_to_linear(0.0), 1.0, 0.0001, "0 dB is unity gain")
	check_approx(AudioCaptureMixer.db_to_linear(-20.0), 0.1, 0.0001, "-20 dB is one tenth")


func _test_sequence_resolution() -> void:
	var sequence := Sequence.new()
	sequence.add_shot(_hold_shot(2.0))
	sequence.add_shot(_hold_shot(3.0))
	var stream := _make_tone(0.25, 1000.0, 0.8)
	sequence.shots[0].cues.append(_voice_cue(0.5, {"stream": stream}))
	sequence.shots[1].cues.append(_voice_cue(1.0, {"stream": stream}))

	var mixer := AudioCaptureMixer.new()
	var added := mixer.consume_sequence(sequence)
	check(added == 2, "consume_sequence queues both VO cues: %d" % added)
	var pcm := mixer.render_pcm(sequence.get_total_duration(), 1)
	var first_start := int(0.5 * 48000)
	var second_start := int(3.0 * 48000)
	check(_peak(pcm, first_start + 4800, first_start + 11000) > 0.5,
			"cue in shot 0 mixes at its absolute time")
	check(_peak(pcm, second_start + 4800, second_start + 11000) > 0.5,
			"cue in shot 1 shifts by the shot start time")
	check(_peak(pcm, 0, 4000) < 0.01, "nothing plays before the first cue")

	var resolved := AudioCaptureMixer.resolve_voice_cue_time(sequence, sequence.shots[1].cues[0], 1)
	check_approx(resolved, 3.0, 0.001, "resolve_voice_cue_time adds the shot offset")
	check_approx(AudioCaptureMixer.resolve_voice_cue_time(null, null, 0), 0.0, EPSILON,
			"null inputs resolve to zero")
	check_approx(AudioCaptureMixer.resolve_voice_cue_time(null, _voice_cue(1.25, {}), 0), 1.25,
			0.001, "missing sequence falls back to cue.time")
	check_approx(AudioCaptureMixer.resolve_voice_cue_time(sequence, _voice_cue(1.25, {}), 9), 1.25,
			0.001, "out-of-range shot index falls back to cue.time")


func _test_marker_resolution() -> void:
	var sequence := Sequence.new()
	sequence.add_shot(_hold_shot(2.0))
	sequence.add_shot(_hold_shot(2.0))
	sequence.add_marker(&"vo_hook", 1.8)
	var cue := _voice_cue(0.0, {"stream": _make_tone(0.1, 1000.0, 0.8)})
	cue.marker = &"vo_hook"
	sequence.shots[0].cues.append(cue)

	var mixer := AudioCaptureMixer.new()
	check(mixer.consume_sequence(sequence) == 1, "marker cue queued once")
	var absolute := AudioCaptureMixer.resolve_voice_cue_time(sequence, cue, 0)
	check_approx(absolute, 1.8, 0.001, "marker resolves to absolute sequence time")

	# Marker outside the shot clamps to the shot end, exactly like the Director.
	var far := _voice_cue(0.0, {"stream": _make_tone(0.1, 1000.0, 0.8)})
	far.marker = &"vo_hook"
	sequence.shots[1].cues.append(far)
	var clamped := AudioCaptureMixer.resolve_voice_cue_time(sequence, far, 1)
	check_approx(clamped, 2.0, 0.001, "marker beyond the shot clamps to its end")

	# Unknown markers fall back to cue.time.
	var unknown := _voice_cue(0.4, {"stream": _make_tone(0.1, 1000.0, 0.8)})
	unknown.marker = &"nope"
	var fallback := AudioCaptureMixer.resolve_voice_cue_time(sequence, unknown, 1)
	check_approx(fallback, 2.4, 0.001, "unknown marker uses the raw cue time")


func _test_track_defaults_precedence() -> void:
	var track := VoiceTrack.new()
	track.stream = _make_tone(0.6, 440.0, 0.9)
	track.volume_db = -6.0206
	track.fade_in = 0.05
	track.start_offset = 0.25
	var cue_stream := _make_tone(0.5, 1000.0, 0.9)

	var sequence := Sequence.new()
	sequence.add_shot(_hold_shot(2.0))
	sequence.shots[0].cues.append(_voice_cue(0.0, {"track": track}))
	sequence.shots[0].cues.append(_voice_cue(1.0, {"stream": cue_stream, "volume_db": 0.0, "track": track}))
	sequence.shots[0].cues.append(_voice_cue(1.5, {"stream": cue_stream, "volume_db": 0.0, "from": 0.1, "track": track}))

	var mixer := AudioCaptureMixer.new()
	check(mixer.consume_sequence(sequence) == 3, "all three VO cues queue")
	var pcm := mixer.render_pcm(3.0, 1)
	# Track-only cue: starts at 0.0, skips the first 0.25 s, halved by -6 dB.
	var track_peak := _peak(pcm, int(0.30 * 48000), int(0.34 * 48000))
	check(track_peak > 0.3 and track_peak < 0.55, "track volume halves the clip (%f)" % track_peak)
	check(_peak(pcm, 0, int(0.05 * 48000)) > 0.1, "start_offset keeps playback at the cue time")
	check(_peak(pcm, int(0.40 * 48000), int(0.50 * 48000)) < 0.01,
			"start_offset trims the head of the track clip")
	# Per-cue stream wins over the track stream: unity 1 kHz burst at 1.0 s.
	var override_peak := _peak(pcm, int(1.05 * 48000), int(1.20 * 48000))
	check(override_peak > 0.8, "per-cue stream overrides the track (%f)" % override_peak)
	# Per-cue volume_db (0 dB) and `from` (0.1 s, replacing the track's 0.25 s)
	# win over the track, so the 0.5 s clip is audible from 1.5 s to 1.9 s.
	var unity_peak := _peak(pcm, int(1.55 * 48000), int(1.64 * 48000))
	check(unity_peak > 0.8, "per-cue volume_db overrides the track (%f)" % unity_peak)

	# default_stream fallback when neither cue nor track carries audio.
	var bare := Sequence.new()
	bare.add_shot(_hold_shot(1.0))
	bare.shots[0].cues.append(_voice_cue(0.0, {}))
	var fallback_mixer := AudioCaptureMixer.new()
	var queued := fallback_mixer.consume_sequence(bare, _make_tone(0.1, 1000.0, 0.8))
	check(queued == 1, "default_stream feeds a cue with no stream")
	var fallback_pcm := fallback_mixer.render_pcm(0.2, 1)
	check(_peak(fallback_pcm, int(0.02 * 48000), int(0.09 * 48000)) > 0.5,
			"default_stream clip actually mixes")
	var empty := AudioCaptureMixer.new()
	check(empty.consume_sequence(bare) == 0, "no stream anywhere queues nothing")
	check(empty.consume_sequence(null) == 0, "null sequence queues nothing")


func _test_render_default_stream() -> void:
	var sequence := Sequence.new()
	sequence.add_shot(_hold_shot(1.0))
	sequence.shots[0].cues.append(_voice_cue(0.0, {}))
	sequence.shots[0].cues.append(_voice_cue(0.5, {"hide": true}))
	var mixer := AudioCaptureMixer.new()
	var events := mixer.consume_sequence(sequence, _make_tone(0.2, 1000.0, 0.8), -12.0)
	check(events == 2, "voice plus hide queue two events: %d" % events)
	var pcm := mixer.render_pcm(1.0, 1)
	var peak := _peak(pcm, int(0.02 * 48000), int(0.18 * 48000))
	check(peak > 0.1 and peak < 0.3, "default_volume_db applies (-12 dB → %f)" % peak)
	var after_hide := _rms(pcm, int(0.70 * 48000), int(0.95 * 48000))
	check(after_hide < 0.01, "hide cue silences the narration (%f)" % after_hide)


func _test_hide_variants() -> void:
	var stream := _make_tone(1.0, 1000.0, 0.9)
	var sequence := Sequence.new()
	sequence.add_shot(_hold_shot(2.0))
	sequence.shots[0].cues.append(_voice_cue(0.0, {"stream": stream}))
	sequence.shots[0].cues.append(_voice_cue(0.5, {"stop": &"stop", "duration": 0.05}))

	var mixer := AudioCaptureMixer.new()
	check(mixer.consume_sequence(sequence) == 2, "stop-marker hide queues")
	var pcm := mixer.render_pcm(2.0, 1)
	var rate := 48000
	check(_rms(pcm, int(0.40 * float(rate)), int(0.49 * float(rate))) > 0.1, "plays before hide")
	check(_rms(pcm, int(0.62 * float(rate)), int(1.5 * float(rate))) < 0.01,
			"explicit hide duration cuts the clip short")

	# The `hide` boolean key works too, and a hide with no stream still queues.
	var alt := Sequence.new()
	alt.add_shot(_hold_shot(1.0))
	alt.shots[0].cues.append(_voice_cue(0.2, {"hide": true}))
	var alt_mixer := AudioCaptureMixer.new()
	check(alt_mixer.consume_sequence(alt) == 1, "hide:true queues without a stream")


func _test_file_roundtrip() -> void:
	var path := "user://m6_audio_capture/mix.wav"
	var dir := "user://m6_audio_capture"
	var missing_dir := "user://m6_audio_missing_dir"
	_remove_tree(ProjectSettings.globalize_path(missing_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var mixer := AudioCaptureMixer.new()
	mixer.queue_voice(_make_tone(0.2, 1000.0, 0.9), 0.0)
	mixer.queue_voice(_make_tone(0.2, 440.0, 0.5), 0.1, AudioCaptureMixer.db_to_linear(-6.0))
	check(mixer.mix_to_wav(path, 0.5, 2), "mix_to_wav writes the file")
	check(FileAccess.file_exists(path), "wav exists on disk")

	var file := FileAccess.open(path, FileAccess.READ)
	check(file != null, "wav opens for reading")
	if file != null:
		# The canonical 44-byte header comes first; the mix lands in `data`.
		var header := file.get_buffer(12)
		check(header.slice(0, 4).get_string_from_ascii() == "RIFF", "file starts with RIFF")
		check(header.slice(8, 12).get_string_from_ascii() == "WAVE", "file is WAVE format")
		file.seek(44)
		var data := file.get_buffer(int(file.get_length() - 44))
		var samples := PackedFloat32Array()
		for byte_index in range(0, data.size() - 1, 2):
			samples.append(float(data.decode_s16(byte_index)) / 32768.0)
		var expected_frames := int(0.5 * float(mixer.get_sample_rate())) * 2
		check(samples.size() >= expected_frames, "payload holds the rendered frames")
		var heard := PackedFloat32Array()
		for index in mini(expected_frames, samples.size()):
			heard.append(samples[index])
		var peak := _peak(heard, int(0.12 * 48000.0), int(0.19 * 48000.0))
		check(peak > 0.3, "decoded payload carries audible audio (%f)" % peak)
		file.close()

	check(not mixer.mix_to_wav(missing_dir.path_join("nested/mix.wav"), 0.1),
			"mix_to_wav fails cleanly on a missing directory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_tree(absolute_path: String) -> void:
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := absolute_path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
