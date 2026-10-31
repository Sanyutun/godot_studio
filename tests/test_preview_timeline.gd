extends "res://tests/support/test_case.gd"
## M5 test — preview timeline maths: projection, scrubbing, hit-testing,
## cue/marker events, ruler ticks and marker snapping.


func _run_tests() -> void:
	_check_projection()
	_check_hit_testing()
	_check_events()
	_check_snapping()
	finish()


func _shot(duration: float) -> Shot:
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = duration
	return shot


func _cue(time: float, marker: StringName = &"") -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.marker = marker
	return cue


func _make_sequence() -> Sequence:
	var sequence := Sequence.new()
	var first := _shot(1.0)
	first.cues = [_cue(0.5)]
	var second := _shot(2.0)
	second.cues = [
		_cue(0.1, &"beat"),
		_cue(0.25),
		_cue(0.5, &"late"),
		_cue(0.2, &"unknown"),
	]
	var third := _shot(3.0)
	third.cues = [_cue(0.1)]
	sequence.add_shot(first)
	sequence.add_shot(second)
	sequence.add_shot(third)
	sequence.add_marker("intro", 0.2)
	sequence.add_marker("beat", 1.75)
	sequence.add_marker("late", 5.0)
	return sequence


func _check_projection() -> void:
	var timeline := PreviewTimeline.new()
	check(not timeline.has_content(), "empty timeline has no content")
	check_approx(timeline.get_duration(), 0.0, 0.0001, "empty timeline duration")
	check_approx(timeline.time_to_x(1.0, 200.0), 10.0, 0.0001, "empty timeline stays at padding")
	check_approx(timeline.x_to_time(150.0, 200.0), 0.0, 0.0001, "empty timeline seeks to zero")
	check_approx(timeline.get_tick_interval(), 1.0, 0.0001, "empty ruler defaults to 1s")

	var sequence := _make_sequence()
	timeline.set_sequence(sequence)
	check(timeline.has_content(), "loaded timeline has content")
	check_approx(timeline.get_duration(), 6.0, 0.0001, "timeline duration sums shots")
	check_approx(PreviewTimeline.get_padding(200.0), 10.0, 0.0001, "normal padding")
	check_approx(PreviewTimeline.get_padding(20.0), 3.0, 0.0001, "tiny widths scale padding")
	check_approx(PreviewTimeline.get_padding(0.0), 0.0, 0.0001, "zero width has no padding")

	check_approx(timeline.time_to_x(0.0, 200.0), 10.0, 0.0001, "start maps to left padding")
	check_approx(timeline.time_to_x(3.0, 200.0), 100.0, 0.0001, "midpoint maps to centre")
	check_approx(timeline.time_to_x(6.0, 200.0), 190.0, 0.0001, "end maps to right padding")
	check_approx(timeline.time_to_x(-1.0, 200.0), 10.0, 0.0001, "negative time clamps left")
	check_approx(timeline.time_to_x(99.0, 200.0), 190.0, 0.0001, "late time clamps right")
	check_approx(timeline.x_to_time(100.0, 200.0), 3.0, 0.0001, "centre maps to midpoint")
	check_approx(timeline.x_to_time(-20.0, 200.0), 0.0, 0.0001, "left overflow clamps")
	check_approx(timeline.x_to_time(400.0, 200.0), 6.0, 0.0001, "right overflow clamps")
	check_approx(
		timeline.x_to_time(timeline.time_to_x(4.25, 320.0), 320.0),
		4.25,
		0.0001,
		"time round-trips through pixels"
	)
	check_approx(timeline.seconds_per_pixel(200.0), 6.0 / 180.0, 0.0001, "pixels to seconds")
	check_approx(timeline.get_tick_interval(), 1.0, 0.0001, "six seconds uses one-second ticks")


func _check_hit_testing() -> void:
	var timeline := PreviewTimeline.new(_make_sequence())
	check(timeline.get_shot_index_at(-1.0) == 0, "negative time is in shot 0")
	check(timeline.get_shot_index_at(0.0) == 0, "sequence start is in shot 0")
	check(timeline.get_shot_index_at(0.999) == 0, "inside shot 0")
	check(timeline.get_shot_index_at(1.0) == 1, "shot boundary belongs to the next shot")
	check(timeline.get_shot_index_at(2.999) == 1, "inside shot 1")
	check(timeline.get_shot_index_at(3.0) == 2, "second boundary belongs to shot 2")
	check(timeline.get_shot_index_at(6.0) == 2, "end stays on the last shot")
	check(timeline.get_shot_index_at(99.0) == 2, "late time stays on the last shot")

	var state := timeline.get_shot_local_time(3.5)
	check(int(state.get("index", -1)) == 2, "local state reports the shot")
	check_approx(float(state.get("start", 0.0)), 3.0, 0.0001, "local state start")
	check_approx(float(state.get("time", 0.0)), 0.5, 0.0001, "local state offset")
	check_approx(float(state.get("duration", 0.0)), 3.0, 0.0001, "local state duration")

	var clamped := timeline.get_shot_local_time(99.0)
	check_approx(float(clamped.get("time", 0.0)), 3.0, 0.0001, "local time clamps at shot end")
	check(timeline.get_shot_local_time(-5.0).get("index", -1) == 0, "negative seek clamps")

	check(timeline.get_shot_span(-1).is_empty(), "invalid span is empty")
	check(timeline.get_shot_span(9).is_empty(), "out-of-range span is empty")
	var span := timeline.get_shot_span(1)
	check_approx(float(span.get("start", 0.0)), 1.0, 0.0001, "span start")
	check_approx(float(span.get("end", 0.0)), 3.0, 0.0001, "span end")
	check_approx(float(span.get("duration", 0.0)), 2.0, 0.0001, "span duration")
	check(timeline.get_segments().size() == 3, "one segment per shot")

	var empty := PreviewTimeline.new()
	check(empty.get_shot_index_at(1.0) == -1, "empty timeline has no shot")
	check(empty.get_shot_local_time(1.0).is_empty(), "empty timeline has no local state")
	check(empty.get_segments().is_empty(), "empty timeline has no segments")


func _check_events() -> void:
	var timeline := PreviewTimeline.new(_make_sequence())
	var events := timeline.get_cue_events()
	check(events.size() == 6, "all cues become events")
	if events.size() == 6:
		var expected := [0.5, 1.2, 1.25, 1.75, 3.0, 3.1]
		for index in expected.size():
			check_approx(
				float(events[index].get("time", -1.0)),
				float(expected[index]),
				0.0001,
				"cue event %d is in firing order" % index
			)
		check(not bool(events[1].get("marker", true)), "plain cue is not a marker cue")
		check(bool(events[3].get("marker", false)), "resolved marker cue is flagged")
		check(int(events[3].get("shot_index", -1)) == 1, "marker cue keeps the shot index")
		check(int(events[3].get("cue_index", -1)) == 0, "marker cue keeps the cue index")
		check_approx(
			float(events[3].get("local_time", 0.0)), 0.75, 0.0001, "marker local time"
		)
		check_approx(float(events[1].get("local_time", 0.0)), 0.2, 0.0001, "plain local time")

	var markers := timeline.get_marker_events()
	check(markers.size() == 3, "all markers become events")
	if markers.size() == 3:
		check(String(markers[0].get("name", "")) == "intro", "markers sort by time")
		check_approx(float(markers[1].get("time", 0.0)), 1.75, 0.0001, "marker event time")
		check(String(markers[2].get("name", "")) == "late", "last marker event")

	var empty := PreviewTimeline.new()
	check(empty.get_cue_events().is_empty(), "empty timeline has no cue events")
	check(empty.get_marker_events().is_empty(), "empty timeline has no marker events")


func _check_snapping() -> void:
	var timeline := PreviewTimeline.new(_make_sequence())
	check_approx(
		timeline.snap_time_to_marker(1.60, 200.0), 1.75, 0.0001, "snaps inside pixel tolerance"
	)
	check_approx(
		timeline.snap_time_to_marker(1.0, 200.0), 1.0, 0.0001, "outside tolerance is unchanged"
	)
	check_approx(
		timeline.snap_time_to_marker(1.60, 200.0, 0.0), 1.60, 0.0001, "zero tolerance is unchanged"
	)

	var plain := PreviewTimeline.new()
	check_approx(plain.snap_time_to_marker(1.6, 200.0), 1.6, 0.0001, "no sequence is a no-op")

	var sequence := _make_sequence()
	var marker_cue := _cue(0.4, &"beat")
	check_approx(
		PreviewTimeline.resolve_cue_local_time(sequence, marker_cue, 0),
		1.0,
		0.0001,
		"static resolver clamps marker cues"
	)
	check_approx(
		PreviewTimeline.resolve_cue_local_time(sequence, marker_cue, 1),
		0.75,
		0.0001,
		"static resolver handles shot-relative markers"
	)
	var unknown := _cue(0.4, &"missing")
	check_approx(
		PreviewTimeline.resolve_cue_local_time(sequence, unknown, 1),
		0.4,
		0.0001,
		"static resolver falls back for unknown markers"
	)
	check_approx(
		PreviewTimeline.resolve_cue_local_time(sequence, marker_cue, -1),
		0.4,
		0.0001,
		"static resolver returns raw time for invalid shots"
	)
	check_approx(
		PreviewTimeline.resolve_cue_local_time(null, marker_cue, 0),
		0.0,
		0.0001,
		"static resolver tolerates a null sequence"
	)
