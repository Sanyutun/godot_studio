extends "res://tests/support/test_case.gd"
## M1 test 3 — killed tweens must reset `_shot_active`.
##
## Regression: a punch-in tween killed mid-move used to leave the camera flagged
## as active, so the following punch-out was skipped and the camera drifted. The
## camera now reaps killed tweens via a signal watchdog, self-heals on read, and
## always resets state before starting the next shot.


func _run_tests() -> void:
	await _check_watchdog_reaps_kill()
	await _check_read_self_heals()
	await _check_abort_resets()
	await _check_director_survives_kill()
	finish()


func _make_camera(scratch: Node, at: Vector2) -> ExplainerCamera:
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	camera.position = at
	scratch.add_child(camera)
	return camera


func _punch_in(duration: float, zoom: float) -> Shot:
	var shot := Shot.new()
	shot.kind = Shot.Kind.PUNCH_IN
	shot.zoom = zoom
	shot.duration = duration
	return shot


func _punch_out(duration: float, zoom: float) -> Shot:
	var shot := Shot.new()
	shot.kind = Shot.Kind.PUNCH_OUT
	shot.zoom = zoom
	shot.duration = duration
	return shot


func _check_watchdog_reaps_kill() -> void:
	var scratch := make_root("KillWatchdog")
	var camera := _make_camera(scratch, Vector2(120.0, 80.0))
	var aborted: Array[int] = [0]
	var settled: Array[int] = [0]
	camera.shot_aborted.connect(func(_shot: Shot) -> void: aborted[0] += 1)
	camera.shot_settled.connect(func(_shot: Shot) -> void: settled[0] += 1)

	var tween := camera.play_shot(_punch_in(0.3, 2.0))
	check(camera.is_shot_active(), "shot is active right after play_shot()")
	await wait(0.08)
	tween.kill()

	# No reads in between: only the signal watchdog can clean this up.
	await wait(ExplainerCamera.KILL_WATCHDOG_GRACE + 0.35)
	check(aborted[0] == 1, "watchdog emits shot_aborted once")
	check(settled[0] == 1, "watchdog emits shot_settled once")
	check(not camera.is_shot_active(), "watchdog clears _shot_active")
	await dispose(scratch)


func _check_read_self_heals() -> void:
	var scratch := make_root("KillSelfHeal")
	var camera := _make_camera(scratch, Vector2(200.0, 150.0))
	var aborted: Array[int] = [0]
	camera.shot_aborted.connect(func(_shot: Shot) -> void: aborted[0] += 1)

	var tween := camera.play_shot(_punch_in(0.6, 2.0))
	await wait(0.1)
	tween.kill()
	await wait(0.05)

	var position_at_kill := camera.position
	check(not camera.is_shot_active(), "is_shot_active() self-heals after a kill")
	check(aborted[0] == 1, "self-heal emits shot_aborted once")

	await wait(0.1)
	check(
		camera.position.is_equal_approx(position_at_kill),
		"camera does not drift after a killed punch-in"
	)

	await camera.await_shot(_punch_out(0.15, 1.0))
	check_approx(camera.zoom.x, 1.0, 0.01, "punch-out after a kill reaches baseline zoom")
	check_approx(camera.position.x, position_at_kill.x, 0.5, "punch-out keeps position x")
	check_approx(camera.position.y, position_at_kill.y, 0.5, "punch-out keeps position y")
	check(not camera.is_shot_active(), "camera idle after the recovery shot")
	await dispose(scratch)


func _check_abort_resets() -> void:
	var scratch := make_root("AbortReset")
	var camera := _make_camera(scratch, Vector2.ZERO)
	var aborted: Array[int] = [0]
	camera.shot_aborted.connect(func(_shot: Shot) -> void: aborted[0] += 1)

	var tween := camera.play_shot(_punch_in(1.0, 2.0))
	await wait(0.05)
	camera.abort()

	check(not camera.is_shot_active(), "abort() clears _shot_active")
	check(aborted[0] == 1, "abort() emits shot_aborted once")
	check(not tween.is_valid() or not tween.is_running(), "abort() kills the tween")

	await camera.await_shot(_punch_out(0.1, 1.0))
	check(not camera.is_shot_active(), "camera can start a new shot after abort()")
	await dispose(scratch)


func _check_director_survives_kill() -> void:
	var scratch := make_root("DirectorKill")
	var camera := _make_camera(scratch, Vector2.ZERO)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)

	var sequence := Sequence.new()
	var first := _punch_in(0.3, 2.0)
	first.cues = [_cue(0.0, Cue.ACTION_CALLOUT)]
	sequence.add_shot(first)
	var second := Shot.new()
	second.kind = Shot.Kind.HOLD
	second.duration = 0.1
	sequence.add_shot(second)

	var finished: Array[int] = [0]
	var done: Array[bool] = [false]
	director.shot_finished.connect(
		func(_index: int, _shot: Shot) -> void: finished[0] += 1
	)
	director.sequence_finished.connect(func(_seq: Sequence) -> void: done[0] = true)

	director.play(sequence)
	await wait(0.08)
	var active_tween := camera.get_active_tween()
	check(active_tween != null, "director started a camera tween")
	if active_tween != null:
		active_tween.kill()

	await wait(0.9)
	check(done[0], "director completes after its camera tween was killed")
	check(finished[0] == 2, "director ends both shots (got %d)" % finished[0])
	check(not camera.is_shot_active(), "camera idle at the end of the take")
	await dispose(scratch)


func _cue(time: float, action: StringName) -> Cue:
	var cue := Cue.new()
	cue.time = time
	cue.action = action
	return cue
