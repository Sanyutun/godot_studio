extends "res://tests/support/test_case.gd"
## M1 test 2 — cue times clamp to shot bounds and fire in clamped order.


func _run_tests() -> void:
	_check_static_clamp()
	await _check_runtime_clamp()
	finish()


func _check_static_clamp() -> void:
	check_approx(Director.clamp_cue_time(-2.0, 1.5), 0.0, 0.0001, "negative time clamps to 0")
	check_approx(Director.clamp_cue_time(9.0, 1.5), 1.5, 0.0001, "late time clamps to duration")
	check_approx(Director.clamp_cue_time(0.5, 1.5), 0.5, 0.0001, "in-range time is untouched")
	check_approx(Director.clamp_cue_time(1.0, 0.0), 0.0, 0.0001, "zero-duration shot clamps to 0")
	check_approx(Director.clamp_cue_time(-1.0, 0.0), 0.0, 0.0001, "zero-duration negative clamps to 0")


func _check_runtime_clamp() -> void:
	var scratch := make_root("CueTest")
	var director := Director.new()
	director.name = "Director"
	scratch.add_child(director)

	var sequence := Sequence.new()
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.4
	shot.cues = [
		_cue(99.0, Cue.ACTION_LOWER_THIRD, "late"),
		_cue(-5.0, Cue.ACTION_CAPTION, "early"),
		_cue(0.1, Cue.ACTION_CALLOUT, "middle"),
	]
	sequence.add_shot(shot)

	var committed: Array[StringName] = []
	var elapsed: Array[float] = []
	var shot_start_usec: Array[int] = [0]
	director.shot_started.connect(
		func(_index: int, _shot: Shot) -> void:
			shot_start_usec[0] = Time.get_ticks_usec()
	)
	director.cue_fired.connect(
		func(cue: Cue, _index: int) -> void:
			committed.append(StringName(cue.get_data("id", "")))
			elapsed.append(float(Time.get_ticks_usec() - shot_start_usec[0]) / 1_000_000.0)
	)

	await director.play(sequence)

	check(committed.size() == 3, "all three cues fired: %s" % [committed])
	if committed.size() != 3:
		await dispose(scratch)
		return
	check(
		committed == [&"early", &"middle", &"late"],
		"cues fire in clamped order: %s" % [committed]
	)
	check_approx(elapsed[0], 0.0, 0.06, "clamped-to-0 cue fires at shot start")
	check_approx(elapsed[1], 0.1, 0.08, "middle cue fires at 0.1s")
	check_approx(elapsed[2], 0.4, 0.1, "clamped-to-duration cue fires near shot end")
	for index in elapsed.size():
		check(
			elapsed[index] <= shot.duration + 0.06,
			"cue %d stays inside shot bounds (%.3fs)" % [index, elapsed[index]]
		)

	await dispose(scratch)


func _cue(time: float, action: StringName, cue_id: String) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = action
	cue.data = {"id": cue_id}
	return cue
