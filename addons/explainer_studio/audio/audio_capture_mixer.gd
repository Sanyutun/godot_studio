@tool
class_name AudioCaptureMixer
extends RefCounted
## Offline narration capture and WAV mixing for deterministic renders (M6).
##
## The [VoiceOver] player is real-time, so an offline pass with `--fixed-fps`
## cannot rely on it producing a waveform. Instead, cue times resolved through
## [PreviewTimeline.resolve_cue_local_time] (the same maths the [Director] uses)
## drive this mixer: every `voice_over` cue's clip is placed at its absolute
## sequence time, hide/stop cues fade the active clip out, and everything is
## summed into one interleaved 16-bit PCM WAV covering the whole take.
##
## All functions are pure — no nodes, no engine clock — which keeps headless
## tests fast and lets [method mix_to_wav] be reused by CI or tool scripts.
## Short tracks keep their full length: the picture never truncates narration
## failures, and silent padding mirrors ffmpeg's `-af apad` behaviour from M4.

## Default sample rate used when none is given.
const DEFAULT_SAMPLE_RATE := 48000
## Fade applied to a hide cue that carries no explicit duration.
const DEFAULT_HIDE_FADE := 0.15

var _sample_rate: int = DEFAULT_SAMPLE_RATE
var _events: Array[Dictionary] = []


## Clears all queued events.
func clear() -> void:
	_events.clear()


## Sample rate used by [method render_pcm] and [method mix_to_wav].
func get_sample_rate() -> int:
	return _sample_rate


## Queues a clip start at absolute seconds. [param gain] is linear;
## [param fade_in] ramps the clip up over its first seconds.
func queue_voice(
	stream: AudioStreamWAV,
	at_seconds: float,
	gain: float = 1.0,
	fade_in: float = 0.0
) -> bool:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return false
	var channel_count := _stream_channels(stream)
	if channel_count <= 0:
		return false
	_events.append({
		"kind": "voice",
		"time": maxf(at_seconds, 0.0),
		"stream": stream,
		"gain": gain,
		"fade_in": maxf(fade_in, 0.0),
		"channels": channel_count,
	})
	return true


## Queues a fade-out of every clip active at [param at_seconds]. A non-positive
## [param fade_out] keeps [member DEFAULT_HIDE_FADE].
func queue_hide(at_seconds: float, fade_out: float = -1.0) -> void:
	_events.append({
		"kind": "hide",
		"time": maxf(at_seconds, 0.0),
		"fade_out": fade_out if fade_out > 0.0 else DEFAULT_HIDE_FADE,
	})


## Number of queued events.
func get_event_count() -> int:
	return _events.size()


## Total rendered length in seconds: the latest clip end, clamped to
## [param min_duration] so short narration never truncates the picture.
func get_total_duration(min_duration: float = 0.0) -> float:
	var latest := min_duration
	for event in _events:
		if String(event.get("kind", "")) != "voice":
			continue
		var stream := event.get("stream") as AudioStreamWAV
		var start := float(event.get("time", 0.0))
		var data_length := stream.data.stream_len() if stream != null else 0
		var clip_seconds := float(data_length) / (float(stream.mix_rate) * float(_stream_channels(stream)))
		latest = maxf(latest, start + maxf(clip_seconds, 0.0))
	return maxf(latest, 0.0)


## Sums every queued event into interleaved mono or stereo samples in the
## [-1, 1] range. [param channel_count] must be 1 or 2.
func render_pcm(duration_seconds: float, channel_count: int) -> PackedFloat32Array:
	var channels := clampi(channel_count, 1, 2)
	var frames := maxi(int(round(duration_seconds * float(_sample_rate))), 0)
	var output := PackedFloat32Array()
	output.resize(frames * channels)
	if frames <= 0:
		return output

	# Stable order: clips first at equal times, then hides, queue order breaks ties.
	var indexed: Array[Dictionary] = []
	for index in _events.size():
		indexed.append({"event": _events[index], "order": index})
	indexed.sort_custom(_compare_events)

	for entry in indexed:
		var event: Dictionary = entry["event"]
		if String(event.get("kind", "")) == "hide":
			_apply_hide(output, frames, channels, event)
		else:
			_mix_clip(output, frames, channels, event)

	for index in output.size():
		output[index] = clampf(output[index], -1.0, 1.0)
	return output


## Renders the mixed timeline and writes a 16-bit PCM WAV to [param wav_path]
## (`user://` and `res://` paths are globalized). Returns `true` on success.
func mix_to_wav(wav_path: String, duration_seconds: float, channel_count: int = 2) -> bool:
	var pcm := render_pcm(duration_seconds, clampi(channel_count, 1, 2))
	var wav := build_wav(pcm, clampi(channel_count, 1, 2))
	var error := wav.save_wav(wav_path)
	if error != OK:
		push_error("AudioCaptureMixer: save_wav('%s') failed with %s." % [wav_path, error_string(error)])
		return false
	return true


## Builds a 16-bit PCM [AudioStreamWAV] from interleaved [-1, 1] samples.
## Exposed for tests and custom exporters.
func build_wav(pcm: PackedFloat32Array, channel_count: int) -> AudioStreamWAV:
	var channels := clampi(channel_count, 1, 2)
	var samples := PackedInt16Array()
	samples.resize(pcm.size())
	for index in pcm.size():
		samples[index] = int16(clampf(pcm[index], -1.0, 1.0) * 32767.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = channels == 2
	wav.mix_rate = _sample_rate
	wav.data = samples
	return wav


## Wraps [param pcm] in a loopable [AudioStreamGenerator] playback, useful for
## auditioning a mixed take through a regular [AudioStreamPlayer].
static func make_generator_playback(
	pcm: PackedFloat32Array, channel_count: int, sample_rate: int = DEFAULT_SAMPLE_RATE
) -> AudioStreamPlayback:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(maxi(sample_rate, 1))
	generator.set_bus("")
	var playback := generator.get_playback_object()
	if playback == null:
		return null
	playback.add_frames(pcm)
	return playback


## Resolves a VO cue to absolute sequence seconds using the same marker maths
## as the [Director]: `cue.time` is shot-relative, a named marker wins when it
## exists and is clamped into the shot like the runtime does.
static func resolve_voice_cue_time(
	sequence: Sequence, cue: Cue, shot_index: int
) -> float:
	if cue == null:
		return 0.0
	if sequence == null or shot_index < 0 or shot_index >= sequence.shots.size():
		return maxf(cue.time, 0.0)
	var local := PreviewTimeline.resolve_cue_local_time(sequence, cue, shot_index)
	return sequence.get_shot_start_time(shot_index) + local


## Walks [param sequence] and queues every `voice_over` cue (start and hide)
## onto this mixer. Per-cue precedence mirrors [VoiceOver.on_cue]:
## `data.stream` → `data.track` → [param default_stream]; `volume_db`, `bus`,
## `fade_in`, `from` and a hide cue's `duration` all behave as documented in
## the README. Returns the number of queued events.
func consume_sequence(
	sequence: Sequence,
	default_stream: AudioStreamWAV = null,
	default_volume_db: float = 0.0,
	default_fade_in: float = 0.0
) -> int:
	if sequence == null:
		return 0
	var before := _events.size()
	for shot_index in sequence.shots.size():
		var shot := sequence.shots[shot_index]
		if shot == null:
			continue
		for cue in shot.cues:
			if cue == null or cue.action != Cue.ACTION_VOICE_OVER:
				continue
			var absolute := resolve_voice_cue_time(sequence, cue, shot_index)
			var data := cue.data
			var is_hide := bool(data.get("hide", false)) or StringName(data.get("stop", &"")) == &"stop"
			if is_hide:
				queue_hide(absolute, float(data.get("duration", -1.0)))
				continue
			var stream := _pick_stream(data, default_stream)
			if stream == null:
				continue
			var track := data.get("track") as VoiceTrack
			var volume_db := float(data.get("volume_db",
				track.volume_db if track != null else default_volume_db))
			var fade_in := float(data.get("fade_in",
				track.fade_in if track != null else default_fade_in))
			var gain := db_to_linear(volume_db)
			var at_seconds := absolute + float(data.get("from", 0.0))
			if track != null:
				at_seconds += track.start_offset
			queue_voice(stream, at_seconds, gain, fade_in)
	return _events.size() - before


## Decibel to linear gain. Exposed because [VoiceOver] keeps authoring in dB.
static func db_to_linear(decibels: float) -> float:
	return pow(10.0, decibels / 20.0)


static func _compare_events(a: Dictionary, b: Dictionary) -> bool:
	var a_event: Dictionary = a["event"]
	var b_event: Dictionary = b["event"]
	var a_time := float(a_event.get("time", 0.0))
	var b_time := float(b_event.get("time", 0.0))
	if not is_equal_approx(a_time, b_time):
		return a_time < b_time
	var a_is_voice := String(a_event.get("kind", "")) == "voice"
	var b_is_voice := String(b_event.get("kind", "")) == "voice"
	if a_is_voice != b_is_voice:
		return a_is_voice
	return int(a["order"]) < int(b["order"])


func _apply_hide(output: PackedFloat32Array, frames: int, channels: int, event: Dictionary) -> void:
	var hide_seconds := float(event.get("time", 0.0))
	var fade_seconds := maxf(float(event.get("fade_out", DEFAULT_HIDE_FADE)), 0.0)
	var hide_frame := int(round(hide_seconds * float(_sample_rate)))
	if hide_frame >= frames:
		return
	var fade_frames := maxi(int(round(fade_seconds * float(_sample_rate))), 1)
	var total := output.size()
	for frame in range(hide_frame, frames):
		# Envelope: 1 at the hide instant, 0 `fade_frames` later; earlier frames
		# are untouched, later frames stay silent.
		var remaining := float(frames - frame)
		var envelope := 1.0
		if frame < hide_frame + fade_frames:
			envelope = float(hide_frame + fade_frames - frame) / float(fade_frames)
		elif remaining < 0.0:
			envelope = 0.0
		for channel in channels:
			var index := frame * channels + channel
			if index < total:
				output[index] *= clampf(envelope, 0.0, 1.0)


func _mix_clip(output: PackedFloat32Array, frames: int, channels: int, event: Dictionary) -> void:
	var stream := event.get("stream") as AudioStreamWAV
	if stream == null:
		return
	var source_channels := int(event.get("channels", 1))
	var gain := float(event.get("gain", 1.0))
	var fade_in_frames := int(round(float(event.get("fade_in", 0.0)) * float(_sample_rate)))
	var start_frame := int(round(float(event.get("time", 0.0)) * float(_sample_rate)))
	var raw := stream.data
	var source_frames := raw.size() / maxi(source_channels, 1)
	var total := output.size()
	for frame in range(start_frame, min(start_frame + source_frames, frames)):
		if frame < 0:
			continue
		var source_frame := frame - start_frame
		var envelope := gain
		if fade_in_frames > 0 and source_frame < fade_in_frames:
			envelope = gain * float(source_frame + 1) / float(fade_in_frames)
		for channel in channels:
			var source_channel := mini(channel, source_channels - 1)
			var sample := float(raw[source_frame * source_channels + source_channel]) / 32768.0
			var index := frame * channels + channel
			if index < total:
				output[index] += sample * envelope


static func _stream_channels(stream: AudioStreamWAV) -> int:
	if stream == null:
		return 0
	return 2 if stream.stereo else 1
