@tool
class_name VoiceOver
extends AudioStreamPlayer
## Cue-driven voice-over / narration player (M3).
##
## Cues use [constant Cue.ACTION_VOICE_OVER] and target this node. Cue `data` may
## provide a `stream` ([AudioStream]), a `track` ([VoiceTrack]), or a
## `stream_path`/`path` resource path. Per-cue `volume_db`, `bus`, `fade_in` and
## `from` values override the track, which overrides this node's defaults.
##
## Narration deliberately outlives a shot: a VO line can bridge a cut. Send a
## cue with `hide: true` (or `stop: true`) and an optional `duration` to fade it
## out on the same budget as the other UI receivers.

signal voice_started(stream: AudioStream)
signal voice_finished()
signal voice_stopped()

## Gain used as the start/end point for fades.
const SILENT_DB := -80.0

## Clip used when a cue does not provide one.
@export var default_stream: AudioStream

## Gain used when a cue does not provide one.
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var default_volume_db: float = 0.0

## Optional bus override for cues. Empty keeps the node's configured bus.
@export var default_bus: StringName = &""

## Default fade-in duration in seconds.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var fade_in_duration: float = 0.0

## Default fade-out duration in seconds for [method stop_voice].
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var fade_out_duration: float = 0.15

var _fade_tween: Tween = null
var _target_volume_db: float = 0.0
var _active_stream: AudioStream = null
var _stopping: bool = false


func _ready() -> void:
	if not finished.is_connected(_on_audio_finished):
		finished.connect(_on_audio_finished)


## Starts [param stream_override] (or [member default_stream]) and returns the
## fade-in [Tween]. Returns `null` when no stream is available.
##
## [param target_volume_db] is the final gain. [param fade_in] `-1` uses
## [member fade_in_duration]. [param from_position] starts inside the clip.
func play_voice(
	stream_override: AudioStream = null,
	target_volume_db: float = 0.0,
	fade_in: float = -1.0,
	from_position: float = 0.0
) -> Tween:
	var next_stream := stream_override if stream_override != null else default_stream
	if next_stream == null:
		push_warning("VoiceOver.play_voice(): no stream provided.")
		return null

	_kill_fade_tween()
	if playing:
		stop()
	_stopping = false
	_active_stream = next_stream
	if stream != next_stream:
		stream = next_stream
	_target_volume_db = target_volume_db
	var active_fade := fade_in_duration if fade_in < 0.0 else maxf(fade_in, 0.0)
	volume_db = SILENT_DB if active_fade > 0.0 else _target_volume_db
	play(maxf(from_position, 0.0))

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "volume_db", _target_volume_db, active_fade)
	tween.finished.connect(_on_fade_in_finished, CONNECT_ONE_SHOT)
	_fade_tween = tween
	voice_started.emit(next_stream)
	return tween


## Fades the active voice-over out and returns the fade [Tween], or `null` when
## nothing is playing. A [param fade_out] of `0` stops immediately.
func stop_voice(fade_out: float = -1.0) -> Tween:
	if not playing:
		return null
	_kill_fade_tween()
	var active_fade := fade_out_duration if fade_out < 0.0 else maxf(fade_out, 0.0)
	if active_fade <= 0.0:
		_stopping = true
		_finish_stop()
		return null
	_stopping = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "volume_db", SILENT_DB, active_fade)
	tween.finished.connect(_finish_stop, CONNECT_ONE_SHOT)
	_fade_tween = tween
	return tween


## Whether a voice-over is currently playing.
func is_voice_playing() -> bool:
	return playing


## Clip currently playing, or `null`.
func get_active_stream() -> AudioStream:
	return _active_stream


## Cue receiver entry point. Supported `data` keys: `stream`, `track`,
## `stream_path`/`path`, `volume_db`, `bus`, `fade_in`, `from`, `hide`/`stop`,
## `duration` (fade-out duration).
func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if bool(event.get_data("hide", event.get_data("stop", false))):
		stop_voice(event.get_budget(float(event.get_data("duration", -1.0))))
		return

	var track := event.get_data("track", null) as VoiceTrack
	var next_stream := event.get_data("stream", null) as AudioStream
	if next_stream == null and track != null:
		next_stream = track.stream
	if next_stream == null:
		next_stream = _load_stream(event.get_data("stream_path", event.get_data("path", "")))
	if next_stream == null:
		next_stream = default_stream
	if next_stream == null:
		push_warning("VoiceOver: cue '%s' has no stream." % event.cue.action)
		return

	var target_db := default_volume_db
	var bus_name := default_bus
	var fade_in := fade_in_duration
	var from_position := 0.0
	if track != null:
		target_db = track.volume_db
		bus_name = track.bus
		fade_in = track.fade_in
		from_position = track.start_offset
	target_db = float(event.get_data("volume_db", target_db))
	bus_name = StringName(String(event.get_data("bus", bus_name)))
	fade_in = float(event.get_data("fade_in", fade_in))
	from_position = float(event.get_data("from", from_position))
	if not bus_name.is_empty():
		bus = bus_name
	play_voice(next_stream, target_db, fade_in, from_position)


func _load_stream(value: Variant) -> AudioStream:
	var path := ""
	if value is String or value is StringName:
		path = String(value)
	elif value is NodePath:
		path = String(value)
	if path.is_empty():
		return null
	return load(path) as AudioStream


func _on_fade_in_finished() -> void:
	_fade_tween = null
	volume_db = _target_volume_db


func _on_audio_finished() -> void:
	if _stopping:
		_finish_stop()
		return
	_kill_fade_tween()
	volume_db = _target_volume_db
	_active_stream = null
	# Drop the stream reference so the audio server can release the playback.
	stream = null
	voice_finished.emit()


func _finish_stop() -> void:
	# Called either from the fade tween or from `finished` when the clip runs out
	# mid-fade. Guard against a double stop so `voice_stopped` fires exactly once.
	if not _stopping and not playing:
		return
	_stopping = false
	_kill_fade_tween()
	var was_active := playing or _active_stream != null
	stop()
	volume_db = _target_volume_db
	_active_stream = null
	stream = null
	if was_active:
		voice_stopped.emit()


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
