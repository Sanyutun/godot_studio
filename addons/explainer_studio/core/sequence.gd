@tool
class_name Sequence
extends Resource
## Ordered shot list plus named markers.
##
## A sequence is the unit the [Director] plays and the Studio dock edits. It is
## a plain [Resource], so saving/loading is `ResourceSaver`/`ResourceLoader` —
## no custom format, no version drift.

## Emitted when shots or markers change through the helper methods. Dock code
## (M5) uses this to mark the edited resource dirty and push undo entries.
signal sequence_changed

## Human readable name shown in the dock and logs.
@export var display_name: String = ""

## Shots in playback order.
@export var shots: Array[Shot] = []

## Named times in seconds from the sequence start:
## `{"name": String, "time": float}`. VO beat snapping (M3) consumes these.
@export var markers: Array[Dictionary] = []


## Appends a shot and notifies listeners.
func add_shot(shot: Shot) -> void:
	if shot == null:
		return
	shots.append(shot)
	_notify_changed()


## Inserts a shot at [param index] (clamped) and notifies listeners.
func insert_shot(index: int, shot: Shot) -> void:
	if shot == null:
		return
	shots.insert(clampi(index, 0, shots.size()), shot)
	_notify_changed()


## Removes the shot at [param index] when it exists.
func remove_shot(index: int) -> void:
	if index < 0 or index >= shots.size():
		return
	shots.remove_at(index)
	_notify_changed()


## Total playback length in seconds.
func get_total_duration() -> float:
	var total := 0.0
	for shot in shots:
		if shot != null:
			total += shot.get_safe_duration()
	return total


## Start time of the shot at [param index] in seconds.
func get_shot_start_time(index: int) -> float:
	var total := 0.0
	var last := mini(index, shots.size())
	for i in range(last):
		var shot := shots[i]
		if shot != null:
			total += shot.get_safe_duration()
	return total


## Adds or retimes a named marker.
func add_marker(marker_name: String, time: float) -> void:
	for marker: Dictionary in markers:
		if String(marker.get("name", "")) == marker_name:
			marker["time"] = time
			_notify_changed()
			return
	markers.append({"name": marker_name, "time": time})
	_notify_changed()


## Whether a marker with [param marker_name] exists.
func has_marker(marker_name: String) -> bool:
	for marker: Dictionary in markers:
		if String(marker.get("name", "")) == marker_name:
			return true
	return false


## Marker time in seconds, or `-1.0` when the marker is unknown.
func get_marker_time(marker_name: String) -> float:
	for marker: Dictionary in markers:
		if String(marker.get("name", "")) == marker_name:
			return float(marker.get("time", 0.0))
	return -1.0


## Names of all markers, in insertion order.
func get_marker_names() -> PackedStringArray:
	var names := PackedStringArray()
	for marker: Dictionary in markers:
		names.append(String(marker.get("name", "")))
	return names


## Marker dictionary nearest to [param time], or an empty dictionary when the
## sequence has no markers.
func get_nearest_marker(time: float) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance := INF
	for marker: Dictionary in markers:
		var distance := absf(float(marker.get("time", 0.0)) - time)
		if distance < best_distance:
			best_distance = distance
			nearest = marker
	return nearest


## Time of the marker nearest to [param time], or [param fallback] when the
## sequence has no markers.
func get_nearest_marker_time(time: float, fallback: float = -1.0) -> float:
	var nearest := get_nearest_marker(time)
	if nearest.is_empty():
		return fallback
	return float(nearest.get("time", fallback))


## Snaps [param time] to the nearest marker when it is within [param tolerance]
## seconds. Returns [param time] unchanged when no marker is close enough.
func snap_to_marker(time: float, tolerance: float = 0.25) -> float:
	var nearest := get_nearest_marker(time)
	if nearest.is_empty():
		return time
	var marker_time := float(nearest.get("time", time))
	if absf(marker_time - time) <= maxf(tolerance, 0.0):
		return marker_time
	return time


## Removes a named marker. Returns `true` when one was removed.
func remove_marker(marker_name: String) -> bool:
	for index in markers.size():
		if String(markers[index].get("name", "")) == marker_name:
			markers.remove_at(index)
			_notify_changed()
			return true
	return false


## Removes every marker.
func clear_markers() -> void:
	markers.clear()
	_notify_changed()


## Authoring sanity checks. Returns human readable issues; empty means clean.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	var index := 0
	for shot in shots:
		if shot == null:
			issues.append("Shot %d is null." % index)
		else:
			if shot.duration < 0.0:
				issues.append("Shot %d has a negative duration." % index)
			if shot.kind == Shot.Kind.FIT_RECT and not _has_usable_rect(shot):
				issues.append("Shot %d FIT_RECT needs a rect (or target) with area." % index)
			for cue in shot.cues:
				if cue == null:
					issues.append("Shot %d has a null cue." % index)
				elif not cue.marker.is_empty():
					if not has_marker(cue.marker):
						issues.append(
							"Shot %d cue marker '%s' is not defined." % [index, cue.marker]
						)
				elif cue.time < 0.0 or cue.time > shot.duration:
					issues.append(
						"Shot %d cue at %.2fs is outside [0, %.2fs]; it will be clamped."
						% [index, cue.time, shot.duration]
					)
		index += 1
	return issues


func _notify_changed() -> void:
	sequence_changed.emit()
	emit_changed()


func _has_usable_rect(shot: Shot) -> bool:
	if shot.rect.size.x > 0.0 and shot.rect.size.y > 0.0:
		return true
	return not shot.target.is_empty()
