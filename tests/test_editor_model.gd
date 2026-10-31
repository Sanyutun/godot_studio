extends "res://tests/support/test_case.gd"
## M5 test — editor-neutral sequence model: selection, structural edits, cues,
## markers, validation and undo-friendly duplicate helpers.


func _run_tests() -> void:
	_check_selection()
	_check_structural_edits()
	_check_cue_edits()
	_check_marker_edits()
	_check_cue_times()
	finish()


func _shot(duration: float = 1.0, kind: int = Shot.Kind.HOLD) -> Shot:
	var shot := Shot.new()
	shot.kind = kind
	shot.duration = duration
	return shot


func _cue(time: float, marker: StringName = &"") -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.marker = marker
	cue.action = Cue.ACTION_CAPTION
	return cue


func _sequence_with_shots(durations: Array) -> Sequence:
	var sequence := Sequence.new()
	for duration in durations:
		sequence.add_shot(_shot(float(duration)))
	return sequence


func _check_selection() -> void:
	var model := SequenceEditorModel.new()
	var empty := Sequence.new()
	model.set_sequence(empty)
	check(model.shot_index == -1, "empty sequence has no shot selection")
	check(model.get_selected_shot() == null, "empty sequence has no selected shot")

	var sequence := _sequence_with_shots([1.0, 2.0, 3.0])
	model.set_sequence(sequence)
	check(model.shot_index == 0, "loading a sequence selects its first shot")
	check(model.cue_index == -1, "loading a sequence clears cue selection")

	model.select_shot(99)
	check(model.shot_index == 2, "shot selection clamps high")
	model.select_shot(-4)
	check(model.shot_index == -1, "shot selection clamps to -1")
	model.select_cue(0)
	check(model.cue_index == -1, "cue selection needs a shot")

	model.select_shot(1)
	model.select_cue(99)
	check(model.cue_index == -1, "empty shot cannot select a cue")
	model.select_cue(-2)
	check(model.cue_index == -1, "cue selection clamps to -1")


func _check_structural_edits() -> void:
	var model := SequenceEditorModel.new()
	var sequence := _sequence_with_shots([1.0, 2.0, 3.0])
	model.set_sequence(sequence)
	var changes: Array = [0]
	var selections: Array[int] = []
	model.changed.connect(func() -> void: changes[0] += 1)
	model.selection_changed.connect(
		func(shot_index: int, _cue_index: int) -> void: selections.append(shot_index)
	)

	var inserted := _shot(0.5)
	model.insert_shot(1, inserted)
	check(sequence.shots.size() == 4, "insert_shot grows the sequence")
	check(sequence.shots[1] == inserted, "insert_shot places the shot")
	check(model.shot_index == 1, "insert_shot selects the new shot")

	var appended := _shot(0.75)
	model.add_shot(appended)
	check(sequence.shots[3] == appended, "add_shot appends")
	check(model.shot_index == 3, "add_shot selects the appended shot")

	var source := sequence.shots[1]
	source.cues = [_cue(0.1)]
	var copy := model.duplicate_shot(1)
	check(copy != null and copy != source, "duplicate_shot returns a distinct resource")
	check(copy.cues.size() == 1, "duplicate_shot copies cues")
	check(copy.cues[0] != source.cues[0], "duplicate_shot deep-copies cues")
	check(sequence.shots[2] == copy, "duplicate_shot inserts directly after the source")
	check(model.shot_index == 2, "duplicate_shot selects the copy")

	model.move_shot(2, 0)
	check(sequence.shots[0] == copy, "move_shot moves the shot")
	check(model.shot_index == 0, "move_shot follows the moved shot")
	model.move_shot(99, 0)
	check(sequence.shots[0] == copy, "invalid move ignores the source")

	model.remove_shot(0)
	check(sequence.shots.size() == 3, "remove_shot shrinks the sequence")
	check(model.shot_index == 0, "remove_shot clamps the selection")
	while not sequence.shots.is_empty():
		model.remove_shot(0)
	check(model.shot_index == -1, "removing every shot clears selection")
	check(changes[0] > 0, "structural edits emit changed")
	check(selections.size() > 0, "structural edits emit selection_changed")


func _check_cue_edits() -> void:
	var model := SequenceEditorModel.new()
	var sequence := _sequence_with_shots([2.0])
	model.set_sequence(sequence)
	var shot := model.get_selected_shot()

	var first := _cue(0.25)
	model.add_cue(0, first)
	check(shot.cues.size() == 1, "add_cue appends")
	check(model.cue_index == 0, "add_cue selects the new cue")
	check(model.get_selected_cue() == first, "selected cue is readable")

	var second := _cue(0.5)
	model.insert_cue(0, 0, second)
	check(shot.cues[0] == second, "insert_cue honours the index")
	check(model.cue_index == 0, "insert_cue selects the inserted cue")

	first.data = {"text": "hello", "nested": {"n": 1}}
	var copy := model.duplicate_cue(0, 1)
	check(copy != null and copy != first, "duplicate_cue returns a distinct resource")
	copy.data["text"] = "copy"
	copy.data["nested"]["n"] = 2
	check(first.data["text"] == "hello", "duplicate_cue deep-copies payload data")
	check(first.data["nested"]["n"] == 1, "duplicate_cue deep-copies nested data")
	check(shot.cues[2] == copy, "duplicate_cue inserts after the source")
	check(model.cue_index == 2, "duplicate_cue selects the copy")

	model.remove_cue(0, 2)
	check(shot.cues.size() == 2, "remove_cue shrinks the cue list")
	check(model.cue_index == 1, "remove_cue clamps the cue selection")
	model.remove_cue(0, 0)
	model.remove_cue(0, 0)
	check(shot.cues.is_empty(), "every cue can be removed")
	check(model.cue_index == -1, "removing all cues clears selection")
	model.remove_cue(0, 0)
	check(shot.cues.is_empty(), "removing an invalid cue is a no-op")


func _check_marker_edits() -> void:
	var model := SequenceEditorModel.new()
	var sequence := _sequence_with_shots([1.0])
	var changes: Array = [0]
	model.changed.connect(func() -> void: changes[0] += 1)
	model.set_sequence(sequence)

	model.set_marker("intro", 0.2)
	check(sequence.has_marker("intro"), "set_marker adds a marker")
	check_approx(sequence.get_marker_time("intro"), 0.2, 0.0001, "marker time stored")
	var before_count := changes[0]
	model.set_marker("intro", 0.4)
	check_approx(sequence.get_marker_time("intro"), 0.4, 0.0001, "set_marker retimes")
	check(
		sequence.get_marker_names() == PackedStringArray(["intro"]),
		"retiming keeps a single marker"
	)
	check(changes[0] == before_count + 1, "retiming emits one change")

	check(model.remove_marker("intro"), "remove_marker removes a known marker")
	check(not model.remove_marker("intro"), "remove_marker is idempotent")
	check(not model.remove_marker("missing"), "remove_marker ignores unknown names")
	check(sequence.get_marker_names().is_empty(), "marker list is empty")


func _check_cue_times() -> void:
	var model := SequenceEditorModel.new()
	var sequence := _sequence_with_shots([1.0, 2.0])
	sequence.add_marker("beat", 1.75)
	sequence.add_marker("late", 5.0)
	model.set_sequence(sequence)

	var first := _shot(1.0)
	first.cues = [_cue(0.5, &"beat")]
	sequence.shots[0] = first
	var second := _shot(2.0)
	second.cues = [
		_cue(0.1, &"beat"),
		_cue(0.25),
		_cue(0.5, &"late"),
		_cue(0.2, &"unknown"),
	]
	sequence.shots[1] = second

	check_approx(
		model.get_cue_absolute_time(first.cues[0], 0),
		1.0,
		0.0001,
		"marker outside shot 0 clamps to the shot end"
	)
	check_approx(
		model.get_cue_absolute_time(second.cues[0], 1),
		1.75,
		0.0001,
		"marker resolves into shot-relative time"
	)
	check_approx(
		model.get_cue_absolute_time(second.cues[1], 1),
		1.25,
		0.0001,
		"plain cue time becomes sequence-absolute"
	)
	check_approx(
		model.get_cue_absolute_time(second.cues[2], 1),
		3.0,
		0.0001,
		"marker after the shot clamps at the shot end"
	)
	check_approx(
		model.get_cue_absolute_time(second.cues[3], 1),
		1.2,
		0.0001,
		"unknown marker falls back to cue.time"
	)

	var issues := model.validate()
	check(issues.size() == 1, "validation reports the unknown cue marker")
	check(
		issues.size() == 1 and issues[0].contains("unknown"),
		"validation names the unknown marker"
	)
