@tool
class_name PreviewTimeline
extends RefCounted
## Pure timeline maths shared by the Studio preview scrubber and its tests.
##
## The sequence is projected onto a horizontal track: shot spans, cue events and
## named markers all become plain dictionaries with seconds and pixel helpers.
## No [Control], [Director] or engine clock is involved, so scrubbing, snapping
## and hit-testing are deterministic in headless test runs.

## Space kept free at both ends so the first/last markers are not clipped.
const EDGE_PADDING := 10.0
## Candidate ruler intervals, in seconds, from finest to coarsest.
const TICK_STEPS: Array[float] = [
	0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0
]

## Sequence being previewed. May be `null`.
var sequence: Sequence = null


func _init(value: Sequence = null) -> void:
	sequence = value


## Replaces the previewed sequence.
func set_sequence(value: Sequence) -> void:
	sequence = value


## Total sequence duration in seconds.
func get_duration() -> float:
	if sequence == null:
		return 0.0
	return sequence.get_total_duration()


## Whether there is anything to scrub.
func has_content() -> bool:
	return get_duration() > 0.0


## Horizontal padding used for [param width], clamped for tiny docks.
static func get_padding(width: float) -> float:
	if width <= 0.0:
		return 0.0
	return minf(EDGE_PADDING, width * 0.15)


## Maps a sequence time to a pixel coordinate inside [param width].
func time_to_x(time: float, width: float) -> float:
	var pad := get_padding(width)
	var usable := maxf(width - pad * 2.0, 1.0)
	var duration := get_duration()
	if duration <= 0.0:
		return pad
	return pad + clampf(time / duration, 0.0, 1.0) * usable


## Maps a pixel coordinate inside [param width] to sequence time.
func x_to_time(x: float, width: float) -> float:
	var pad := get_padding(width)
	var usable := maxf(width - pad * 2.0, 1.0)
	var duration := get_duration()
	if duration <= 0.0:
		return 0.0
	return clampf((x - pad) / usable, 0.0, 1.0) * duration


## Seconds represented by one pixel at [param width].
func seconds_per_pixel(width: float) -> float:
	var pad := get_padding(width)
	var usable := maxf(width - pad * 2.0, 1.0)
	return get_duration() / usable


## Snaps [param time] to a nearby marker within [param pixel_tolerance] pixels.
func snap_time_to_marker(time: float, width: float, pixel_tolerance: float = 6.0) -> float:
	if sequence == null:
		return time
	var tolerance := seconds_per_pixel(width) * maxf(pixel_tolerance, 0.0)
	return sequence.snap_to_marker(time, tolerance)


## Index of the shot that owns [param time]. Time at a boundary belongs to the
## next shot; times at or past the end clamp to the last shot.
func get_shot_index_at(time: float) -> int:
	if sequence == null or sequence.shots.is_empty():
		return -1
	var clamped := maxf(time, 0.0)
	var cursor := 0.0
	for index in sequence.shots.size():
		var shot := sequence.shots[index]
		var duration := 0.0 if shot == null else shot.get_safe_duration()
		var end := cursor + duration
		if clamped < end or index == sequence.shots.size() - 1:
			return index
		cursor = end
	return sequence.shots.size() - 1


## Shot-relative playback state at [param time].
func get_shot_local_time(time: float) -> Dictionary:
	var index := get_shot_index_at(time)
	if index < 0:
		return {}
	var shot := sequence.shots[index]
	var start := sequence.get_shot_start_time(index)
	var duration := 0.0 if shot == null else shot.get_safe_duration()
	return {
		"index": index,
		"time": clampf(time - start, 0.0, duration),
		"duration": duration,
		"start": start,
	}


## Start, end and duration of the shot at [param index].
func get_shot_span(index: int) -> Dictionary:
	if sequence == null or index < 0 or index >= sequence.shots.size():
		return {}
	var shot := sequence.shots[index]
	var start := sequence.get_shot_start_time(index)
	var duration := 0.0 if shot == null else shot.get_safe_duration()
	return {
		"index": index,
		"start": start,
		"end": start + duration,
		"duration": duration,
	}


## All shot spans in playback order.
func get_segments() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if sequence == null:
		return segments
	for index in sequence.shots.size():
		segments.append(get_shot_span(index))
	return segments


## Cue events with sequence-absolute times, in firing order.
func get_cue_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if sequence == null:
		return events
	for shot_index in sequence.shots.size():
		var shot := sequence.shots[shot_index]
		if shot == null:
			continue
		var start := sequence.get_shot_start_time(shot_index)
		for cue_index in shot.cues.size():
			var cue := shot.cues[cue_index]
			if cue == null:
				continue
			var local := resolve_cue_local_time(sequence, cue, shot_index)
			events.append({
				"cue": cue,
				"shot_index": shot_index,
				"cue_index": cue_index,
				"time": start + local,
				"local_time": local,
				"marker": (
					not cue.marker.is_empty()
					and sequence.has_marker(cue.marker)
				),
			})
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_time := float(a.get("time", 0.0))
			var b_time := float(b.get("time", 0.0))
			if not is_equal_approx(a_time, b_time):
				return a_time < b_time
			if int(a.get("shot_index", 0)) != int(b.get("shot_index", 0)):
				return int(a.get("shot_index", 0)) < int(b.get("shot_index", 0))
			return int(a.get("cue_index", 0)) < int(b.get("cue_index", 0))
	)
	return events


## Named markers with sequence-absolute times. Markers outside the sequence are
## kept because authoring needs to see and fix them.
func get_marker_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if sequence == null:
		return events
	for marker: Dictionary in sequence.markers:
		events.append({
			"name": String(marker.get("name", "")),
			"time": float(marker.get("time", 0.0)),
		})
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return events


## Ruler interval that keeps the tick count near ten for the current duration.
func get_tick_interval() -> float:
	var duration := get_duration()
	if duration <= 0.0:
		return 1.0
	for step in TICK_STEPS:
		if duration / step <= 10.0:
			return step
	return TICK_STEPS[TICK_STEPS.size() - 1]


## Resolves a cue to shot-relative seconds, mirroring [Director] marker snapping.
static func resolve_cue_local_time(
	sequence_value: Sequence, cue: Cue, shot_index_value: int
) -> float:
	if sequence_value == null or cue == null:
		return 0.0
	if shot_index_value < 0 or shot_index_value >= sequence_value.shots.size():
		return maxf(cue.time, 0.0)
	var shot := sequence_value.shots[shot_index_value]
	if shot == null:
		return maxf(cue.time, 0.0)
	var local := cue.time
	if not cue.marker.is_empty():
		var marker_time := sequence_value.get_marker_time(cue.marker)
		if marker_time >= 0.0:
			local = marker_time - sequence_value.get_shot_start_time(shot_index_value)
	return clampf(local, 0.0, shot.get_safe_duration())
