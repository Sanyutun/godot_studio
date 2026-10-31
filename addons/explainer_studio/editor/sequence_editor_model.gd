@tool
class_name SequenceEditorModel
extends RefCounted
## Editor-neutral authoring model for a [Sequence].
##
## The Studio dock and its headless tests share this class: it owns the loaded
## sequence, the shot/cue selection and every structural edit. Keeping the
## logic out of [Control] code means add/remove/move/duplicate behaviour, marker
## editing and selection clamping are testable without an editor or a display.
##
## Methods mutate immediately; the dock wraps them in
## [EditorUndoRedoManager] do/undo callables. Inspector edits touch exported
## resource fields directly and then call [method touch].

## Emitted after any structural edit, marker edit or [method touch].
signal changed
## Emitted whenever the selected shot or cue changes, including as a side
## effect of an edit that clamped the selection.
signal selection_changed(shot_index: int, cue_index: int)

## Sequence being edited, or `null` when the dock is empty.
var sequence: Sequence = null

## Selected shot index, or `-1`.
var shot_index: int = -1

## Selected cue index inside [member shot_index], or `-1`.
var cue_index: int = -1


## Replaces the edited sequence and selects its first shot.
func set_sequence(value: Sequence) -> void:
	if sequence == value:
		return
	sequence = value
	if sequence == null or sequence.shots.is_empty():
		shot_index = -1
	else:
		shot_index = 0
	cue_index = -1
	_notify()


## Selects a shot (clamped to the sequence) and clears the cue selection.
func select_shot(index: int) -> void:
	var next_index := _clamp_shot_index(index)
	if next_index == shot_index and cue_index == -1:
		return
	shot_index = next_index
	cue_index = -1
	selection_changed.emit(shot_index, cue_index)


## Selects a cue inside the current shot (clamped) without changing the shot.
func select_cue(index: int) -> void:
	var shot := get_selected_shot()
	var next_index := -1
	if shot != null:
		next_index = clampi(index, -1, shot.cues.size() - 1)
	if next_index == cue_index:
		return
	cue_index = next_index
	selection_changed.emit(shot_index, cue_index)


## Shot at [param index], or `null`.
func get_shot(index: int) -> Shot:
	if sequence == null or index < 0 or index >= sequence.shots.size():
		return null
	return sequence.shots[index]


## Selected shot, or `null`.
func get_selected_shot() -> Shot:
	return get_shot(shot_index)


## Cue at [param cue_index] inside [param shot_index], or `null`.
func get_cue(shot_index_value: int, cue_index_value: int) -> Cue:
	var shot := get_shot(shot_index_value)
	if shot == null or cue_index_value < 0 or cue_index_value >= shot.cues.size():
		return null
	return shot.cues[cue_index_value]


## Selected cue, or `null`.
func get_selected_cue() -> Cue:
	return get_cue(shot_index, cue_index)


## Inserts [param shot] at [param index], selecting it.
func insert_shot(index: int, shot: Shot) -> void:
	if sequence == null or shot == null:
		return
	var target := clampi(index, 0, sequence.shots.size())
	sequence.insert_shot(target, shot)
	shot_index = target
	cue_index = -1
	_notify()


## Appends [param shot] and selects it.
func add_shot(shot: Shot) -> void:
	if sequence == null:
		return
	insert_shot(sequence.shots.size(), shot)


## Removes the shot at [param index] and clamps the selection.
func remove_shot(index: int) -> void:
	if sequence == null or index < 0 or index >= sequence.shots.size():
		return
	sequence.remove_shot(index)
	shot_index = _clamp_shot_index(mini(index, sequence.shots.size() - 1))
	cue_index = -1
	_notify()


## Deep-copies the shot at [param index] directly after it and selects the copy.
func duplicate_shot(index: int) -> Shot:
	var source := get_shot(index)
	if sequence == null or source == null:
		return null
	var copy := source.duplicate(true) as Shot
	if copy == null:
		return null
	insert_shot(index + 1, copy)
	return copy


## Moves a shot, keeping the selection on the moved shot.
func move_shot(from_index: int, to_index: int) -> void:
	if sequence == null:
		return
	if from_index < 0 or from_index >= sequence.shots.size():
		return
	var target := clampi(to_index, 0, sequence.shots.size() - 1)
	if target == from_index:
		return
	var shot := sequence.shots[from_index]
	sequence.shots.remove_at(from_index)
	sequence.shots.insert(target, shot)
	shot_index = target
	cue_index = -1
	sequence.mark_changed()
	_notify()


## Inserts [param cue] into a shot at [param cue_index], selecting it.
func insert_cue(shot_index_value: int, cue_index_value: int, cue: Cue) -> void:
	var shot := get_shot(shot_index_value)
	if shot == null or cue == null:
		return
	var target := clampi(cue_index_value, 0, shot.cues.size())
	shot.cues.insert(target, cue)
	shot_index = shot_index_value
	cue_index = target
	if sequence != null:
		sequence.mark_changed()
	_notify()


## Appends [param cue] to the shot at [param shot_index_value].
func add_cue(shot_index_value: int, cue: Cue) -> void:
	var shot := get_shot(shot_index_value)
	if shot == null:
		return
	insert_cue(shot_index_value, shot.cues.size(), cue)


## Removes a cue and clamps the cue selection.
func remove_cue(shot_index_value: int, cue_index_value: int) -> void:
	var shot := get_shot(shot_index_value)
	if shot == null or cue_index_value < 0 or cue_index_value >= shot.cues.size():
		return
	shot.cues.remove_at(cue_index_value)
	shot_index = shot_index_value
	cue_index = clampi(cue_index_value, -1, shot.cues.size() - 1)
	if sequence != null:
		sequence.mark_changed()
	_notify()


## Deep-copies a cue directly after the source cue and selects the copy.
func duplicate_cue(shot_index_value: int, cue_index_value: int) -> Cue:
	var source := get_cue(shot_index_value, cue_index_value)
	if source == null:
		return null
	var copy := source.duplicate(true) as Cue
	if copy == null:
		return null
	insert_cue(shot_index_value, cue_index_value + 1, copy)
	return copy


## Adds or retimes a marker. Existing names keep their insertion order.
func set_marker(marker_name: String, time: float) -> void:
	if sequence == null:
		return
	sequence.add_marker(marker_name, time)
	_notify()


## Removes a marker. Returns whether one was removed.
func remove_marker(marker_name: String) -> bool:
	if sequence == null:
		return false
	if not sequence.remove_marker(marker_name):
		return false
	_notify()
	return true


## Called after direct inspector edits to exported fields. Keeps the resource's
## `changed` signal and [signal changed] in sync.
func touch() -> void:
	if sequence != null:
		sequence.mark_changed()
	_notify()


## Absolute sequence time of [param cue], honouring marker snapping.
func get_cue_absolute_time(cue: Cue, shot_index_value: int) -> float:
	if sequence == null or cue == null:
		return 0.0
	var shot := get_shot(shot_index_value)
	if shot == null:
		return maxf(cue.time, 0.0)
	var local := PreviewTimeline.resolve_cue_local_time(sequence, cue, shot_index_value)
	return sequence.get_shot_start_time(shot_index_value) + local


## Sequence validation issues, or an empty array without a sequence.
func validate() -> PackedStringArray:
	if sequence == null:
		return PackedStringArray()
	return sequence.validate()


func _clamp_shot_index(index: int) -> int:
	if sequence == null or sequence.shots.is_empty():
		return -1
	return clampi(index, -1, sequence.shots.size() - 1)


func _notify() -> void:
	changed.emit()
	selection_changed.emit(shot_index, cue_index)
