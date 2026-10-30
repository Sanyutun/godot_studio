@tool
class_name VoiceTrack
extends Resource
## Serialized voice-over clip and mix settings for [VoiceOver].
##
## Attach one to a cue's `data` under the `track` key so the clip, gain, bus and
## fades live in a single `.tres` resource. A cue can still override any value
## with its own `data` keys.

## Audio clip to play.
@export var stream: AudioStream

## Playback gain in decibels.
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var volume_db: float = 0.0

## Audio bus name.
@export var bus: StringName = &"Master"

## Fade-in duration in seconds; `0` starts at full gain.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var fade_in: float = 0.0

## Fade-out duration in seconds used by [method VoiceOver.stop_voice].
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var fade_out: float = 0.15

## Start playback from this offset, in seconds.
@export_range(0.0, 600.0, 0.01, "or_greater", "suffix:s")
var start_offset: float = 0.0


## Whether the track has a playable stream.
func is_playable() -> bool:
	return stream != null


## Clip length in seconds, or `0.0` when no stream is set.
func get_length() -> float:
	return 0.0 if stream == null else stream.get_length()
