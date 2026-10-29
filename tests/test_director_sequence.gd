extends "res://tests/support/test_case.gd"
## M1 test 1 — director advances shots in order, fires cues, survives stop(),
## and the whole sequence round-trips through `.tres`.

const ROUNDTRIP_PATH := "user://m1_sequence_roundtrip.tres"


func _run_tests() -> void:
	var scratch := make_root("DirectorTest")
	var target := Node2D.new()
	target.name = "Target"
	target.position = Vector2(400.0, 300.0)
	scratch.add_child(target)

	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)

	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)

	var sequence := _build_sequence()
	sequence.add_marker("beat_1", 0.2)

	var started: Array[int] = []
	var finished: Array[int] = []
	var cues: Array[StringName] = []
	var completed: Array[bool] = [false]
	director.shot_started.connect(
		func(index: int, _shot: Shot) -> void: started.append(index)
	)
	director.shot_finished.connect(
		func(index: int, _shot: Shot) -> void: finished.append(index)
	)
	director.cue_fired.connect(
		func(cue: Cue, _index: int) -> void: cues.append(cue.action)
	)
	director.sequence_finished.connect(
		func(_seq: Sequence) -> void: completed[0] = true
	)

	await director.play(sequence)

	check(started.size() == 3, "three shots started")
	check(started == [0, 1, 2], "shots start in order: %s" % [started])
	check(finished == [0, 1, 2], "shots finish in order: %s" % [finished])
	check(completed[0], "sequence_finished emitted")
	check(cues.size() == 3, "one cue per shot fired: %s" % [cues])
	check(not director.is_playing(), "director idle after take")
	check(not camera.is_shot_active(), "camera idle after take")

	check_approx(camera.position.x, 400.0, 0.5, "pan reached target x")
	check_approx(camera.position.y, 300.0, 0.5, "pan reached target y")
	check_approx(camera.zoom.x, 2.0, 0.001, "punch_in applied zoom")

	check_approx(sequence.get_total_duration(), 0.4, 0.0001, "total duration")
	check_approx(sequence.get_shot_start_time(1), 0.1, 0.0001, "shot 1 start time")
	check_approx(sequence.get_marker_time("beat_1"), 0.2, 0.0001, "marker time")
	check(sequence.has_marker("beat_1"), "marker lookup")
	check(sequence.validate().is_empty(), "clean sequence validates without issues")

	_check_roundtrip(sequence)
	await _check_stop(scratch, director, camera)

	await dispose(scratch)
	finish()


func _build_sequence() -> Sequence:
	var sequence := Sequence.new()
	sequence.display_name = "order-test"

	var hold := Shot.new()
	hold.kind = Shot.Kind.HOLD
	hold.duration = 0.1
	hold.cues = [_cue(0.0, Cue.ACTION_CAPTION)]

	var pan := Shot.new()
	pan.kind = Shot.Kind.PAN
	pan.target = NodePath("../Target")
	pan.duration = 0.15
	pan.cues = [_cue(0.05, Cue.ACTION_CALLOUT)]

	var punch := Shot.new()
	punch.kind = Shot.Kind.PUNCH_IN
	punch.zoom = 2.0
	punch.duration = 0.15
	punch.cues = [_cue(0.05, Cue.ACTION_LOWER_THIRD)]

	sequence.add_shot(hold)
	sequence.add_shot(pan)
	sequence.add_shot(punch)
	return sequence


func _cue(time: float, action: StringName) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = action
	return cue


func _check_roundtrip(sequence: Sequence) -> void:
	var save_error := ResourceSaver.save(sequence, ROUNDTRIP_PATH)
	check(save_error == OK, "sequence saves to .tres (error %d)" % save_error)
	var loaded := ResourceLoader.load(ROUNDTRIP_PATH) as Sequence
	check(loaded != null, "sequence loads back")
	if loaded == null:
		return
	check(loaded.display_name == "order-test", "display_name survives round-trip")
	check(loaded.shots.size() == 3, "shot count survives round-trip")
	check(loaded.shots[0] is Shot, "shots keep their Shot type")
	check(loaded.shots[2].kind == Shot.Kind.PUNCH_IN, "shot kind survives round-trip")
	check_approx(loaded.shots[2].zoom, 2.0, 0.0001, "shot zoom survives round-trip")
	check(loaded.shots[1].cues.size() == 1, "cues survive round-trip")
	check(loaded.shots[1].cues[0].action == Cue.ACTION_CALLOUT, "cue action survives round-trip")
	check_approx(loaded.get_marker_time("beat_1"), 0.2, 0.0001, "marker survives round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUNDTRIP_PATH))


func _check_stop(scratch: Node, director: Director, camera: ExplainerCamera) -> void:
	var long_take := Sequence.new()
	var first := Shot.new()
	first.kind = Shot.Kind.HOLD
	first.duration = 1.0
	long_take.add_shot(first)
	var second := Shot.new()
	second.kind = Shot.Kind.HOLD
	second.duration = 1.0
	long_take.add_shot(second)

	var stopped: Array[bool] = [false]
	director.sequence_stopped.connect(
		func(_seq: Sequence) -> void: stopped[0] = true
	)
	director.play(long_take)
	await wait(0.12)
	check(director.is_playing(), "long take is playing")
	check(camera.is_shot_active(), "camera is driving the long take")

	director.stop()
	await process_frame
	check(not director.is_playing(), "stop() ends playback")
	check(not camera.is_shot_active(), "stop() resets camera state")
	check(stopped[0], "sequence_stopped emitted")

	# Keep the scratch reference alive for the caller's cleanup.
	if scratch == null:
		push_error("scratch node vanished")
