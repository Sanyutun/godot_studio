@tool
class_name AudioCaptureMixer
extends RefCounted
## Offline narration capture and WAV mixing for deterministic renders (M6).
##
## The [VoiceOver] player is real-time, so an offline pass with `--fixed-fps`
## cannot rely on it producing a waveform. Instead, cue times resolved through
## [PreviewTimeline.resolve_cue_local_time] (the same maths the [Director] uses)
## drive this mixer: every `voice_over` cue's clip is placed at its absolute
## sequence time, hide/stop cues fade the active clip out, and the result is
## written as one interleaved 16-bit PCM WAV covering the whole take.
##
## [VoiceOver] owns a single player, so starting a line cuts the previous one;
## [method consume_sequence] mirrors that by replacing the active clip at each
## voice cue. Direct [method queue_voice] calls layer instead (a mixer's job),
## unless `replace_active` is set.
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
var _last_mix_path: String = ""


## Path handed to the most recent [method mix_to_wav] call. [FrameRenderer] uses
## it to locate the narration file even when a mixer subclass overrides the
## write itself (test doubles, custom exporters).
func get_last_mix_path() -> String:
	return _last_mix_path


## Clears all queued events.
func clear() -> void:
	_events.clear()


## Sample rate used by [method render_pcm] and [method mix_to_wav].
func get_sample_rate() -> int:
	return _sample_rate


## Queues a clip start at absolute seconds. [param gain] is linear;
## [param fade_in] ramps the clip up over its first seconds; [param skip_frames]
## drops that many leading source frames (the offline twin of playing from a
## position); [param bus] records the audio bus for render-side bookkeeping —
## offline mixing sums everything to one file, so it never changes the samples.
##
## Every clip layers on top of the previous ones. Pass [param replace_active] to
## cut everything already queued instead, which is what [VoiceOver] does when a
## new line interrupts the current one; [method consume_sequence] always sets it.
func queue_voice(
	stream: AudioStreamWAV,
	at_seconds: float,
	gain: float = 1.0,
	fade_in: float = 0.0,
	skip_frames: int = 0,
	bus: StringName = &"",
	replace_active: bool = false
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
		"skip_frames": maxi(skip_frames, 0),
		"bus": bus,
		"channels": channel_count,
		"replace": replace_active,
	})
	return true


## Queues a fade-out of every clip active at [param at_seconds]. A negative
## [param fade_out] keeps [member DEFAULT_HIDE_FADE]; `0` cuts immediately.
func queue_hide(at_seconds: float, fade_out: float = -1.0) -> void:
	_events.append({
		"kind": "hide",
		"time": maxf(at_seconds, 0.0),
		"fade_out": fade_out if fade_out >= 0.0 else DEFAULT_HIDE_FADE,
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
		if stream == null:
			continue
		var start := float(event.get("time", 0.0))
		var channels := maxi(_stream_channels(stream), 1)
		var sample_rate := float(maxi(stream.mix_rate, 1))
		# `queue_voice()` only accepts 16-bit PCM, so every frame is two bytes
		# per channel. `data.size()` is a byte count, not a frame count.
		var total_frames := float(stream.data.size()) / float(channels * 2)
		var clip_frames := maxf(total_frames - float(maxi(int(event.get("skip_frames", 0)), 0)), 0.0)
		var clip_seconds := clip_frames / sample_rate
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

	# Stable order: absolute time, then queue order. Queue order is the authored
	# cue order because consume_sequence walks shots and cues in sequence order,
	# so equal-time cues behave exactly like the Director's stable sort.
	var indexed: Array[Dictionary] = []
	for index in _events.size():
		indexed.append({"event": _events[index], "order": index})
	indexed.sort_custom(_compare_events)

	for entry in indexed:
		var event: Dictionary = entry["event"]
		if String(event.get("kind", "")) == "hide":
			_apply_hide(output, frames, channels, event)
		else:
			if bool(event.get("replace", false)):
				_cut_active(output, channels, float(event.get("time", 0.0)))
			_mix_clip(output, frames, channels, event)

	for index in output.size():
		output[index] = clampf(output[index], -1.0, 1.0)
	return output


## Renders the mixed timeline and writes a 16-bit PCM WAV file to
## [param wav_path] (`user://` paths are globalized). Returns `true` on success.
## The destination directory must already exist — [FrameRenderer] creates it
## before requesting a mix, and failing here keeps a typo from scattering
## directories across the project.
func mix_to_wav(wav_path: String, duration_seconds: float, channel_count: int = 2) -> bool:
	_last_mix_path = wav_path
	var pcm := render_pcm(duration_seconds, clampi(channel_count, 1, 2))
	var bytes := encode_wav_bytes(pcm, clampi(channel_count, 1, 2))
	var absolute := ProjectSettings.globalize_path(wav_path) if wav_path.begins_with("user://") else wav_path
	var directory := absolute.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		push_error("AudioCaptureMixer: directory does not exist '%s'." % directory)
		return false
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("AudioCaptureMixer: cannot open '%s' for writing (%s)." % [wav_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_buffer(bytes)
	file.close()
	return true


## Builds a 44-byte-header 16-bit PCM WAV container around interleaved
## [-1, 1] samples. Exposed for tests and custom exporters.
static func encode_wav_bytes(pcm: PackedFloat32Array, channel_count: int, sample_rate: int = DEFAULT_SAMPLE_RATE) -> PackedByteArray:
	var channels := clampi(channel_count, 1, 2)
	var rate := maxi(sample_rate, 1)
	var data_size := pcm.size() * 2
	var bytes := PackedByteArray()
	bytes.resize(44 + data_size)
	var offset := 0
	offset = _put_string(bytes, offset, "RIFF")
	offset = _put_u32le(bytes, offset, 36 + data_size)
	offset = _put_string(bytes, offset, "WAVE")
	offset = _put_string(bytes, offset, "fmt ")
	offset = _put_u32le(bytes, offset, 16)
	offset = _put_u16le(bytes, offset, 1)  # PCM
	offset = _put_u16le(bytes, offset, channels)
	offset = _put_u32le(bytes, offset, rate)
	offset = _put_u32le(bytes, offset, rate * channels * 2)
	offset = _put_u16le(bytes, offset, channels * 2)
	offset = _put_u16le(bytes, offset, 16)
	offset = _put_string(bytes, offset, "data")
	offset = _put_u32le(bytes, offset, data_size)
	for sample in pcm:
		var value := int(round(clampf(float(sample), -1.0, 1.0) * 32767.0))
		if value < 0:
			value += 65536
		offset = _put_u16le(bytes, offset, value)
	return bytes


static func _put_string(target: PackedByteArray, offset: int, text: String) -> int:
	for byte in text.to_ascii_buffer():
		target[offset] = byte
		offset += 1
	return offset


static func _put_u16le(target: PackedByteArray, offset: int, value: int) -> int:
	target[offset] = value & 0xFF
	target[offset + 1] = (value >> 8) & 0xFF
	return offset + 2


static func _put_u32le(target: PackedByteArray, offset: int, value: int) -> int:
	target[offset] = value & 0xFF
	target[offset + 1] = (value >> 8) & 0xFF
	target[offset + 2] = (value >> 16) & 0xFF
	target[offset + 3] = (value >> 24) & 0xFF
	return offset + 4


## Packs interleaved [param pcm] samples in the [-1, 1] range into an
## [AudioStreamWAV] — 16-bit PCM at [member DEFAULT_SAMPLE_RATE] (or
## [param sample_rate]), mono by default and stereo when [param channel_count]
## is 2. This is the in-memory counterpart of [method mix_to_wav]: the same
## clamped quantization, minus the file I/O and the RIFF container.
static func build_wav(
		pcm: PackedFloat32Array, channel_count: int = 1, sample_rate: int = DEFAULT_SAMPLE_RATE
) -> AudioStreamWAV:
	var channels := clampi(channel_count, 1, 2)
	var rate := maxi(sample_rate, 1)
	var samples := PackedByteArray()
	samples.resize(pcm.size() * 2)
	for index in pcm.size():
		var value := int(round(clampf(float(pcm[index]), -1.0, 1.0) * 32767.0))
		samples.encode_s16(index * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = samples
	return stream


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
			var is_hide := CueEvent.is_flag(data.get("hide", false)) or CueEvent.is_flag(data.get("stop", false))
			if is_hide:
				# Mirror [method CueEvent.get_budget]: a missing duration spends
				# the shot's remaining time, an explicit one is clamped to it.
				var local := absolute - sequence.get_shot_start_time(shot_index)
				var remaining := maxf(shot.get_safe_duration() - local, 0.0)
				var requested := float(data.get("duration", -1.0))
				queue_hide(
					absolute,
					remaining if requested < 0.0 else minf(requested, remaining)
				)
				continue
			var stream := _pick_stream(data, default_stream)
			if stream == null:
				push_warning(
					"AudioCaptureMixer: shot %d cue '%s' has no 16-bit PCM stream; skipped."
					% [shot_index, cue.action]
				)
				continue
			var track := data.get("track") as VoiceTrack
			var volume_db := float(data.get("volume_db",
				track.volume_db if track != null else default_volume_db))
			var fade_in := float(data.get("fade_in",
				track.fade_in if track != null else default_fade_in))
			var gain := db_to_linear(volume_db)
			# [VoiceOver.on_cue] lets a per-cue `from` replace the track offset
			# rather than adding to it.
			var from_seconds := float(data.get(
				"from", track.start_offset if track != null else 0.0
			))
			var skip_frames := maxi(int(round(from_seconds * float(stream.mix_rate))), 0)
			# One VoiceOver player means a new line stops the current one; direct
			# queue_voice() callers opt into layering instead.
			queue_voice(stream, absolute, gain, fade_in, skip_frames, _cue_bus(data, track), true)
	return _events.size() - before


## Resolves the clip for one `voice_over` cue following the [VoiceOver]
## precedence: `data.stream` → `data.track` ([member VoiceTrack.stream]) →
## [param default_stream]. A `stream_path`/`path` string is loaded from disk
## when no inline stream was authored. Anything that is not a 16-bit
## [AudioStreamWAV] yields `null`, so [method queue_voice] rejects it instead
## of mixing a silent or malformed buffer.
## Per-cue `bus` wins over [member VoiceTrack.bus]; empty means "whatever the
## mixer records on the event" (offline mixing has no live bus routing).
static func _cue_bus(data: Dictionary, track: VoiceTrack) -> StringName:
	if data.has("bus"):
		return StringName(data.get("bus", &""))
	return track.bus if track != null else &""


static func _pick_stream(data: Dictionary, default_stream: AudioStreamWAV) -> AudioStreamWAV:
	var candidate: AudioStream = null
	if data.has("stream"):
		candidate = data.get("stream") as AudioStream
	if candidate == null:
		var track: VoiceTrack = data.get("track") as VoiceTrack
		if track != null:
			candidate = track.stream
	if candidate == null:
		var path := String(data.get("stream_path", data.get("path", "")))
		if not path.is_empty():
			candidate = load(path) as AudioStream
	if candidate == null:
		candidate = default_stream
	var wav := candidate as AudioStreamWAV
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	return wav


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
	return int(a["order"]) < int(b["order"])


## Silences every sample from [param at_seconds] onward. A replacement clip is
## mixed after the cut, so it starts on a clean buffer — the offline twin of
## [method VoiceOver.play_voice] calling `stop()` before `play()`.
func _cut_active(output: PackedFloat32Array, channels: int, at_seconds: float) -> void:
	var start_frame := maxi(int(round(at_seconds * float(_sample_rate))), 0)
	var total := output.size()
	for index in range(start_frame * channels, total):
		output[index] = 0.0


func _apply_hide(output: PackedFloat32Array, frames: int, channels: int, event: Dictionary) -> void:
	var hide_seconds := float(event.get("time", 0.0))
	var fade_seconds := maxf(float(event.get("fade_out", DEFAULT_HIDE_FADE)), 0.0)
	var hide_frame := int(round(hide_seconds * float(_sample_rate)))
	if hide_frame >= frames:
		return
	var fade_frames := maxi(int(round(fade_seconds * float(_sample_rate))), 1) if fade_seconds > 0.0 else 0
	var total := output.size()
	for frame in range(hide_frame, frames):
		# Envelope: 1 at the hide instant, 0 once the fade completes; every later
		# frame stays fully silent so a hide also cuts clips that outlive it.
		var envelope := 0.0
		if fade_frames == 0:
			envelope = 1.0 if frame == hide_frame else 0.0
		elif frame < hide_frame + fade_frames:
			envelope = float(hide_frame + fade_frames - frame) / float(fade_frames)
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
	var skip_frames := maxi(int(event.get("skip_frames", 0)), 0)
	var bytes_per_frame := source_channels * 2
	var available := maxi(raw.size() / bytes_per_frame - skip_frames, 0)
	var source_rate := float(maxi(stream.mix_rate, 1))
	var step := source_rate / float(_sample_rate)
	# Convert remaining source frames to output frames so low-rate sources are
	# not truncated and high-rate ones do not overrun.
	var output_frames := int(ceil(float(available) / maxf(step, 0.000001)))
	var end_frame := min(start_frame + output_frames, frames)
	var total := output.size()
	for frame in range(maxi(start_frame, 0), end_frame):
		var source_frame := skip_frames + int(round(float(frame - start_frame) * step))
		var source_offset := source_frame * bytes_per_frame
		# Resampling can advance the source cursor faster than the output one, so
		# check the byte offset per frame instead of trusting `end_frame` alone.
		if source_offset + bytes_per_frame > raw.size():
			break
		var envelope := gain
		if fade_in_frames > 0 and frame - start_frame < fade_in_frames:
			envelope = gain * float(frame - start_frame + 1) / float(fade_in_frames)
		for channel in channels:
			var source_channel := mini(channel, source_channels - 1)
			var sample := float(raw.decode_s16(source_offset + source_channel * 2)) / 32768.0
			var index := frame * channels + channel
			if index < total:
				output[index] += sample * envelope


static func _stream_channels(stream: AudioStreamWAV) -> int:
	if stream == null:
		return 0
	return 2 if stream.stereo else 1
