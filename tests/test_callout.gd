extends "res://tests/support/test_case.gd"
## M2 test — callouts track a moving world node through camera zoom changes,
## clamp to the viewport, and retarget without popping.


func _run_tests() -> void:
	await _check_zoom_tracking()
	await _check_edge_clamping()
	await _check_retarget_and_hide()
	await _check_cue_drives_callout()
	finish()


func _build_stage(stage_name: String) -> Array[Node]:
	var scratch := make_root(stage_name)
	var camera := ExplainerCamera.new()
	camera.name = "Camera"
	scratch.add_child(camera)
	camera.enabled = true
	camera.make_current()
	var target := Node2D.new()
	target.name = "Target"
	target.position = Vector2.ZERO
	scratch.add_child(target)
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	scratch.add_child(layer)
	var callout := Callout.new()
	callout.name = "Callout"
	layer.add_child(callout)
	await process_frame
	return [scratch, camera, target, callout]


func _projected(callout: Callout, target: Node2D) -> Vector2:
	return callout.get_viewport().get_canvas_transform() * target.global_position


func _check_zoom_tracking() -> void:
	var stage := await _build_stage("CalloutZoom")
	var scratch: Node = stage[0]
	var camera := stage[1] as ExplainerCamera
	var target := stage[2] as Node2D
	var callout := stage[3] as Callout

	callout.show_callout("Anchored", target, 0.0, 0.0)
	await wait(0.06)
	callout.refresh(0.0)
	var first := callout.get_anchor_screen_position()
	check(
		first.distance_to(_projected(callout, target)) < 0.5,
		"callout projects the world anchor at 1x zoom"
	)

	camera.position = Vector2(200.0, 100.0)
	camera.zoom = Vector2(2.0, 2.0)
	await process_frame
	callout.refresh(0.0)
	var second := callout.get_anchor_screen_position()
	var second_expected := _projected(callout, target)
	check(
		second.distance_to(second_expected) < 0.5,
		"callout re-projects through camera pan + 2x zoom"
	)
	check(first.distance_to(second) > 10.0, "anchor visibly moved with the camera")

	await dispose(scratch)


func _check_edge_clamping() -> void:
	var stage := await _build_stage("CalloutClamp")
	var scratch: Node = stage[0]
	var camera := stage[1] as ExplainerCamera
	var target := stage[2] as Node2D
	var callout := stage[3] as Callout
	camera.zoom = Vector2.ONE
	camera.position = Vector2.ZERO
	await process_frame

	callout.show_callout("Off-screen anchor", target, 0.0, 0.0)
	await wait(0.06)
	target.position = Vector2(100000.0, -100000.0)
	callout.refresh(0.0)

	var viewport_size := callout.get_viewport_rect().size
	var anchor := callout.get_anchor_screen_position()
	var bubble := callout.get_bubble_position()
	check(
		anchor.x >= callout.edge_margin - 1.0 and anchor.x <= viewport_size.x - callout.edge_margin + 1.0,
		"anchor x clamped into the visible world rect (%.1f)" % anchor.x
	)
	check(
		anchor.y >= callout.edge_margin - 1.0 and anchor.y <= viewport_size.y - callout.edge_margin + 1.0,
		"anchor y clamped into the visible world rect (%.1f)" % anchor.y
	)
	check(
		bubble.x >= callout.edge_margin - 1.0 and bubble.x <= viewport_size.x - callout.edge_margin + 1.0,
		"bubble stays inside the viewport horizontally"
	)
	check(
		bubble.y >= callout.edge_margin - 1.0 and bubble.y <= viewport_size.y - callout.edge_margin + 1.0,
		"bubble stays inside the viewport vertically"
	)
	await dispose(scratch)


func _check_retarget_and_hide() -> void:
	var stage := await _build_stage("CalloutRetarget")
	var scratch: Node = stage[0]
	var target := stage[2] as Node2D
	var callout := stage[3] as Callout
	var other := Node2D.new()
	other.name = "Other"
	other.position = Vector2(300.0, 200.0)
	scratch.add_child(other)

	callout.show_callout("First", target, 0.0, 0.2)
	await wait(0.25)
	var bubble := callout.get_node_or_null("Bubble") as Control
	check(bubble != null, "callout builds its bubble")
	if bubble == null:
		await dispose(scratch)
		return
	var alpha_before := bubble.modulate.a
	check(alpha_before > 0.9, "callout reveal completed before retarget")

	callout.show_callout("Second", other, 0.0, 0.2)
	check(callout.get_text() == "Second", "retarget updates the text")
	check(callout.get_target_node() == other, "retarget swaps the anchor node")
	check(
		bubble.modulate.a >= alpha_before - 0.01,
		"retarget does not reset bubble alpha"
	)

	var hide_tween := callout.hide_callout(0.05)
	check(hide_tween != null, "hide_callout returns a tween")
	if hide_tween != null:
		await hide_tween.finished
	check(not callout.is_callout_visible(), "hide_callout hides the bubble")
	await dispose(scratch)


func _check_cue_drives_callout() -> void:
	var stage := await _build_stage("CalloutCue")
	var scratch: Node = stage[0]
	var callout := stage[3] as Callout
	var director := Director.new()
	director.name = "Director"
	director.camera = stage[1] as ExplainerCamera
	scratch.add_child(director)

	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 0.4
	var cue := Cue.new()
	cue.time = 0.05
	cue.action = Cue.ACTION_CALLOUT
	cue.target = NodePath("../HUD/Callout")
	cue.data = {
		"text": "From a cue",
		"anchor": NodePath("../../Target"),
		"hold": 0.3,
		"reveal": 0.05,
	}
	shot.cues = [cue]
	var sequence := Sequence.new()
	sequence.add_shot(shot)
	await director.play(sequence)
	# The auto-hide is budgeted to the shot end; let the last frame land.
	for _frame in 4:
		if not callout.is_callout_visible():
			break
		await process_frame

	check(callout.get_text() == "From a cue", "cue text reached the callout")
	check(callout.get_target_node() != null, "cue anchor reached the callout")
	check(not callout.is_callout_visible(), "callout auto-hid inside the shot budget")
	await dispose(scratch)
