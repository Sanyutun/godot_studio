extends "res://tests/support/test_case.gd"
## M2 test — lower thirds reveal, hold and dismiss inside the shot budget.
##
## The cue path is exercised through a real [Director], so the assertion covers
## cue clamping → [CueEvent.remaining] budget → slide/fade tween.

const FRAME := 1.0 / 60.0
const TIMING_TOLERANCE := FRAME * 2.0


func _run_tests() -> void:
	await _check_cue_budget_timing()
	await _check_retarget_without_pop()
	await _check_direct_hide()
	await _check_cue_hide()
	finish()


func _build_stage(stage_name: String) -> Array[Node]:
	var scratch := make_root(stage_name)
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	scratch.add_child(layer)
	var lower := LowerThird.new()
	lower.name = "LowerThird"
	layer.add_child(lower)
	lower.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)
	await process_frame
	return [scratch, camera, lower, director]


func _check_cue_budget_timing() -> void:
	var stage := await _build_stage("LowerThirdCue")
	var scratch: Node = stage[0]
	var lower := stage[2] as LowerThird
	var director := stage[3] as Director

	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.7
	var cue := Cue.new()
	cue.time = 0.25
	cue.action = Cue.ACTION_LOWER_THIRD
	cue.target = NodePath("../HUD/LowerThird")
	cue.data = {
		"title": "Deterministic",
		"subtitle": "UI on the camera clock",
		"kicker": "M2",
		"reveal": 0.2,
	}
	shot.cues = [cue]
	var sequence := Sequence.new()
	sequence.add_shot(shot)

	var shot_end_usec: Array[int] = [0]
	var hidden_usec: Array[int] = [0]
	var shown: Array[bool] = [false]
	director.shot_finished.connect(
		func(_index: int, _shot: Shot) -> void: shot_end_usec[0] = Time.get_ticks_usec()
	)
	lower.lower_third_shown.connect(
		func(_title: String, _subtitle: String) -> void: shown[0] = true
	)
	lower.lower_third_hidden.connect(
		func() -> void: hidden_usec[0] = Time.get_ticks_usec()
	)

	await director.play(sequence)
	# The auto-dismiss is budgeted to the shot end; let the last frame land.
	for _frame in 6:
		if hidden_usec[0] > 0:
			break
		await process_frame

	check(shown[0], "cue showed the lower third")
	check(lower.get_title() == "Deterministic", "cue title reached the card")
	check(lower.get_subtitle() == "UI on the camera clock", "cue subtitle reached the card")
	check(lower.get_kicker() == "M2", "cue kicker reached the card")
	check(hidden_usec[0] > 0, "lower third auto-hid")
	check(not lower.is_lower_third_visible(), "lower third is hidden after the shot")

	if hidden_usec[0] > 0 and shot_end_usec[0] > 0:
		var delta_seconds := absf(
			float(hidden_usec[0] - shot_end_usec[0]) / 1_000_000.0
		)
		check(
			delta_seconds <= TIMING_TOLERANCE,
			"lower third settles within ±2 frames of the shot (%.4fs)" % delta_seconds
		)

	await dispose(scratch)


func _check_retarget_without_pop() -> void:
	var stage := await _build_stage("LowerThirdRetarget")
	var scratch: Node = stage[0]
	var lower := stage[2] as LowerThird
	var panel := lower.get_panel()
	check(panel != null, "lower third builds its panel")
	if panel == null:
		await dispose(scratch)
		return

	lower.show_lower_third(
		"First", "one", 0.0, 0.4, Tween.TRANS_CUBIC, Tween.EASE_OUT, -1.0, "kicker"
	)
	await wait(0.12)
	var alpha_before := panel.modulate.a
	check(alpha_before > 0.05, "retarget: slide/fade is mid-flight (alpha %.2f)" % alpha_before)

	var retarget_tween := lower.retarget("Second", "two", 0.2, "kicker")
	check(lower.get_title() == "Second", "retarget: title updates immediately")
	check(lower.get_subtitle() == "two", "retarget: subtitle updates immediately")
	check(
		panel.modulate.a >= alpha_before - 0.02,
		"retarget: alpha does not pop back to zero"
	)
	if retarget_tween != null:
		await retarget_tween.finished
	check(lower.is_lower_third_visible(), "retarget: card is still visible")
	check(panel.modulate.a > 0.99, "retarget: reveal still completes")

	await dispose(scratch)


func _check_direct_hide() -> void:
	var stage := await _build_stage("LowerThirdHide")
	var scratch: Node = stage[0]
	var lower := stage[2] as LowerThird
	var hidden: Array[int] = [0]
	lower.lower_third_hidden.connect(func() -> void: hidden[0] += 1)

	lower.show_lower_third("Hide me", "", 0.0, 0.0)
	var hide_tween := lower.hide_lower_third(0.05)
	check(hide_tween != null, "hide_lower_third returns a tween")
	if hide_tween != null:
		await hide_tween.finished
	check(not lower.is_lower_third_visible(), "hide_lower_third hides the card")
	check(hidden[0] == 1, "lower_third_hidden emitted once")

	await dispose(scratch)


func _check_cue_hide() -> void:
	var stage := await _build_stage("LowerThirdCueHide")
	var scratch: Node = stage[0]
	var lower := stage[2] as LowerThird
	lower.show_lower_third("Visible", "until the hide cue", 0.0, 0.0)

	var cue := Cue.new()
	cue.action = Cue.ACTION_LOWER_THIRD
	cue.data = {"hide": true, "duration": 0.05}
	var event := CueEvent.new()
	event.cue = cue
	event.remaining = 0.5
	lower.on_cue(event)
	await wait(0.12)

	check(not lower.is_lower_third_visible(), "hide cue dismisses the card")
	await dispose(scratch)
