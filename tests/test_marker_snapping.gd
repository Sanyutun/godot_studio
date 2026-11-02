extends "res://tests/support/test_case.gd"
## M3 test — sequence marker helpers and Director marker→shot-relative snapping.


func _run_tests() -> void:
	_check_sequence_helpers()
	_check_validation()
	await _check_director_resolution_and_order()
	await _check_equal_time_order()
	finish()


func _cue(time: float, marker: StringName = &"") -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = Cue.ACTION_CAPTION
	cue.marker = marker
	return cue


func _check_sequence_helpers() -> void:
	var sequence := Sequence.new()
	check(sequence.get_nearest_marker(1.0).is_empty(), "empty sequence has no nearest marker")
	check_approx(
		sequence.get_nearest_marker_time(1.0, -1.0), -1.0, 0.0001, "nearest marker falls back"
	)
	check_approx(sequence.snap_to_marker(1.0), 1.0, 0.0001, "snap without markers is a no-op")

	sequence.add_marker("intro", 0.2)
	sequence.add_marker("beat", 1.5)
	sequence.add_marker("outro", 9.0)
	check(
		sequence.get_marker_names() == PackedStringArray(["intro", "beat", "outro"]),
		"marker names keep insertion order"
	)
	check_approx(sequence.get_marker_time("beat"), 1.5, 0.0001, "marker time lookup")
	check_approx(sequence.get_marker_time("missing"), -1.0, 0.0001, "unknown marker time is -1")

	var nearest := sequence.get_nearest_marker(1.4)
	check(String(nearest.get("name", "")) == "beat", "nearest marker is the closest one")
	check_approx(
		sequence.get_nearest_marker_time(1.4), 1.5, 0.0001, "nearest marker time is the closest"
	)
	check_approx(sequence.snap_to_marker(1.45, 0.1), 1.5, 0.0001, "snap inside tolerance")
	check_approx(
		sequence.snap_to_marker(1.45, 0.01), 1.45, 0.0001, "snap outside tolerance is unchanged"
	)
	check_approx(sequence.snap_to_marker(1.5, 0.0), 1.5, 0.0001, "exact marker snaps at zero tolerance")

	check(sequence.remove_marker("beat"), "remove_marker removes a known marker")
	check(not sequence.remove_marker("beat"), "remove_marker is idempotent")
	check(not sequence.has_marker("beat"), "removed marker is gone")
	sequence.clear_markers()
	check(sequence.get_marker_names().is_empty(), "clear_markers removes every marker")

	check_approx(Director.clamp_cue_time(-1.0, 2.0), 0.0, 0.0001, "clamp low")
	check_approx(Director.clamp_cue_time(3.0, 2.0), 2.0, 0.0001, "clamp high")
	check_approx(Director.clamp_cue_time(1.0, -1.0), 0.0, 0.0001, "clamp negative duration")


func _check_validation() -> void:
	var sequence := Sequence.new()
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 1.0
	shot.cues = [_cue(0.5, &"missing")]
	sequence.add_shot(shot)

	var issues := sequence.validate()
	check(issues.size() == 1, "undefined cue marker is reported once")
	check(
		issues.size() == 1 and issues[0].contains("missing"),
		"undefined cue marker names the marker"
	)

	sequence.add_marker("missing", 0.5)
	check(sequence.validate().is_empty(), "marker cue validates once the marker exists")

	# Marker cues validate their resolved time: this marker is outside the
	# sequence, so both the marker table and the cue are flagged.
	sequence.add_marker("missing", 5.0)
	var out_of_bounds := sequence.validate()
	check(out_of_bounds.size() == 2, "out-of-sequence marker is reported twice")
	check(
		out_of_bounds.size() == 2 and out_of_bounds[0].contains("outside"),
		"marker table reports out-of-bounds time"
	)
	check(
		out_of_bounds.size() == 2 and out_of_bounds[1].contains("resolves"),
		"cue reports its resolved out-of-bounds time"
	)

	var end_marker := Sequence.new()
	end_marker.add_marker("end", 1.0)
	var end_shot := Shot.new()
	end_shot.kind = Shot.Kind.HOLD
	end_shot.duration = 1.0
	end_shot.cues = [_cue(0.0, &"end")]
	end_marker.add_shot(end_shot)
	check(end_marker.validate().is_empty(), "marker at the sequence end is valid")

	var duplicates := Sequence.new()
	var marker_shot := Shot.new()
	marker_shot.kind = Shot.Kind.HOLD
	marker_shot.duration = 1.0
	duplicates.add_shot(marker_shot)
	duplicates.markers = [
		{"name": "beat", "time": 0.0},
		{"name": "beat", "time": 0.5},
		{"name": "", "time": 0.2},
	]
	var marker_issues := duplicates.validate()
	check(
		marker_issues.size() == 2
		and marker_issues[0].contains("duplicates")
		and marker_issues[1].contains("empty name"),
		"marker table reports duplicate and empty names: %s" % [marker_issues]
	)


func _check_equal_time_order() -> void:
	var scratch := make_root("CueOrder")
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)
	await process_frame

	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.2
	var authored: Array[Cue] = []
	for cue_id in [&"first", &"second", &"third", &"fourth"]:
		var cue := _cue(0.0)
		cue.data = {"id": cue_id}
		authored.append(cue)
	shot.cues = authored

	var sequence := Sequence.new()
	sequence.add_shot(shot)

	var fired: Array[StringName] = []
	director.cue_event_fired.connect(
		func(event: CueEvent) -> void: fired.append(StringName(event.get_data("id", "")))
	)
	await director.play(sequence)

	check(
		fired == [&"first", &"second", &"third", &"fourth"],
		"equal-time cues fire in authored order: %s" % [fired]
	)
	await dispose(scratch)


func _check_director_resolution_and_order() -> void:
	var scratch := make_root("MarkerDirector")
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)
	await process_frame

	var beat_cue := _cue(0.0, &"beat")
	var plain_cue := _cue(0.2)
	var late_cue := _cue(0.0, &"late")
	var early_cue := _cue(0.0, &"early")
	var unknown_cue := _cue(0.1, &"nope")

	var first := Shot.new()
	first.kind = Shot.Kind.HOLD
	first.duration = 0.1

	var second := Shot.new()
	second.kind = Shot.Kind.HOLD
	second.duration = 0.3
	second.cues = [beat_cue, plain_cue, late_cue]

	var sequence := Sequence.new()
	sequence.add_marker("early", 0.0)
	sequence.add_marker("beat", 0.25)
	sequence.add_marker("late", 5.0)
	sequence.add_shot(first)
	sequence.add_shot(second)

	var resolved: Array[float] = []
	var resolved_early: Array[float] = []
	var resolved_late: Array[float] = []
	var resolved_unknown: Array[float] = []
	director.shot_started.connect(
		func(index: int, _shot: Shot) -> void:
			if index != 1:
				return
			resolved.append(director.resolve_cue_time(beat_cue, index))
			resolved_early.append(director.resolve_cue_time(early_cue, index))
			resolved_late.append(director.resolve_cue_time(late_cue, index))
			resolved_unknown.append(director.resolve_cue_time(unknown_cue, index))
	)
	var events: Array[CueEvent] = []
	director.cue_event_fired.connect(func(event: CueEvent) -> void: events.append(event))

	await director.play(sequence)

	check(resolved.size() == 1, "shot 1 resolved its cues")
	if resolved.size() == 1:
		check_approx(resolved[0], 0.15, 0.0001, "marker resolves to shot-relative time")
		check_approx(resolved_early[0], 0.0, 0.0001, "marker before the shot clamps to zero")
		check_approx(resolved_late[0], 0.3, 0.0001, "marker after the shot clamps to duration")
		check_approx(resolved_unknown[0], 0.1, 0.0001, "unknown marker falls back to cue.time")

	check(events.size() == 3, "three shot-1 cues fired")
	if events.size() == 3:
		check(events[0].cue == beat_cue, "resolved marker cue fires first")
		check(events[1].cue == plain_cue, "plain cue fires in resolved order")
		check(events[2].cue == late_cue, "clamped marker cue fires last")
		check_approx(events[0].elapsed, 0.15, 0.0001, "event carries resolved marker time")
		check_approx(events[1].elapsed, 0.2, 0.0001, "event carries plain cue time")
		check_approx(events[2].elapsed, 0.3, 0.0001, "event carries clamped marker time")
		check_approx(events[0].remaining, 0.15, 0.0001, "marker cue remaining budget")
		check_approx(events[2].remaining, 0.0, 0.0001, "clamped cue has no remaining budget")

	await dispose(scratch)
