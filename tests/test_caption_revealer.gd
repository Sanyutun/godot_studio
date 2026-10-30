extends "res://tests/support/test_case.gd"
## M2 test — caption reveals finish within ±1 frame of the shot end.
##
## Each mode is driven through a real [Director] cue, so the assertion covers the
## whole chain: cue clamping → CueEvent.remaining budget → reveal tween.

const FRAME := 1.0 / 60.0
const TIMING_TOLERANCE := FRAME * 1.25


func _run_tests() -> void:
	await _check_mode_timing(CaptionRevealer.Mode.TYPEWRITER, "typewriter")
	await _check_mode_timing(CaptionRevealer.Mode.FADE_UP, "fade_up")
	await _check_mode_timing(CaptionRevealer.Mode.SLIDE_LEFT, "slide_left")
	await _check_retarget_without_pop()
	finish()


func _build_stage(stage_name: String) -> Array[Node]:
	var scratch := make_root(stage_name)
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	scratch.add_child(layer)
	var caption := CaptionRevealer.new()
	caption.name = "Caption"
	layer.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var director := Director.new()
	director.name = "Director"
	director.camera = camera
	scratch.add_child(director)
	await process_frame
	return [scratch, camera, caption, director]


func _check_mode_timing(active_mode: int, mode_name: String) -> void:
	var stage := await _build_stage("Caption_%s" % mode_name)
	var scratch: Node = stage[0]
	var caption := stage[2] as CaptionRevealer
	var director := stage[3] as Director

	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.7
	var cue := Cue.new()
	cue.time = 0.25
	cue.action = Cue.ACTION_CAPTION
	cue.target = NodePath("../HUD/Caption")
	cue.data = {"text": "mode %s" % mode_name, "mode": mode_name}
	shot.cues = [cue]
	var sequence := Sequence.new()
	sequence.add_shot(shot)

	var shot_start_usec: Array[int] = [0]
	var shot_end_usec: Array[int] = [0]
	var reveal_end_usec: Array[int] = [0]
	director.shot_started.connect(
		func(_index: int, _shot: Shot) -> void: shot_start_usec[0] = Time.get_ticks_usec()
	)
	director.shot_finished.connect(
		func(_index: int, _shot: Shot) -> void: shot_end_usec[0] = Time.get_ticks_usec()
	)
	caption.reveal_finished.connect(
		func() -> void: reveal_end_usec[0] = Time.get_ticks_usec()
	)

	await director.play(sequence)
	# Cues are frame-quantised: a cue authored at 0.25 s fires on the next frame
	# boundary, so the reveal can settle up to one frame after the shot does.
	# Give it that bounded window before asserting the timestamp.
	for _frame in 3:
		if reveal_end_usec[0] > 0:
			break
		await process_frame

	check(caption.visible, "%s: caption is visible" % mode_name)
	check(caption.get_text() == "mode %s" % mode_name, "%s: text applied" % mode_name)
	check(caption.is_revealed(), "%s: caption fully revealed" % mode_name)
	check(reveal_end_usec[0] > 0, "%s: reveal_finished emitted" % mode_name)

	if reveal_end_usec[0] > 0 and shot_end_usec[0] > 0:
		var delta_seconds := absf(
			float(reveal_end_usec[0] - shot_end_usec[0]) / 1_000_000.0
		)
		check(
			delta_seconds <= TIMING_TOLERANCE,
			"%s: reveal ends within ±1 frame of the shot (%.4fs)" % [mode_name, delta_seconds]
		)
		var shot_length := float(shot_end_usec[0] - shot_start_usec[0]) / 1_000_000.0
		check(
			shot_length >= 0.65,
			"%s: shot ran to its authored length (%.3fs)" % [mode_name, shot_length]
		)

	await dispose(scratch)


func _check_retarget_without_pop() -> void:
	var stage := await _build_stage("CaptionRetarget")
	var scratch: Node = stage[0]
	var caption := stage[2] as CaptionRevealer

	caption.reveal("First caption", CaptionRevealer.Mode.FADE_UP, 0.4)
	await wait(0.12)
	var alpha_before := caption.modulate.a
	check(alpha_before > 0.05, "retarget: fade is mid-flight (alpha %.2f)" % alpha_before)

	var retarget_tween := caption.retarget("Second caption", 0.2)
	check(caption.get_text() == "Second caption", "retarget: text updates immediately")
	check(
		caption.modulate.a >= alpha_before - 0.02,
		"retarget: alpha does not pop back to zero"
	)
	if retarget_tween != null:
		await retarget_tween.finished
	check(caption.is_revealed(), "retarget: reveal still completes")

	caption.reveal("Hello", CaptionRevealer.Mode.TYPEWRITER, 0.3)
	await wait(0.1)
	var characters_before := caption.get_label().visible_characters
	if characters_before < 0:
		characters_before = 5
	var type_tween := caption.retarget("Hello again", 0.2)
	check(
		caption.get_label().visible_characters >= characters_before,
		"typewriter retarget keeps revealed glyphs (no pop)"
	)
	if type_tween != null:
		await type_tween.finished
	check(caption.get_label().visible_ratio >= 0.999, "typewriter retarget finishes revealing")

	await dispose(scratch)
