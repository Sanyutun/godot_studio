@tool
class_name PixelRigLimb
extends Skeleton2D
## Rigged limb with bone posing

func _ready() -> void:
	# Ensure pixel snapping
	for child in get_children():
		_apply_pixel_snap(child)
	for child in find_children("*", "Sprite2D", true, false):
		_apply_pixel_snap(child)

func _apply_pixel_snap(node: Node) -> void:
	if node is CanvasItem:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if node.material == null:
			var shader = load("res://addons/explainer_studio/shaders/pixel_outline.gdshader")
			if shader:
				var mat = ShaderMaterial.new()
				mat.shader = shader
				mat.set_shader_parameter("outline_width", 1.0)
				mat.set_shader_parameter("outline_color", Color.BLACK)
				node.material = mat

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"pose_limb":
		var data = event.cue.data
		var bone_poses = data.get("bone_poses", {})
		var duration = float(data.get("duration", 1.0))
		var anim_type = String(data.get("animation", "wave"))
		if anim_type == "wave":
			_wave_animation(duration)
		elif anim_type == "flex":
			_flex_animation(duration)
		else:
			_pose_limb(bone_poses, duration)
	elif event.cue.action == &"wave":
		_wave_animation(float(event.cue.data.get("duration", 1.5)))
	elif event.cue.action == &"flex":
		_flex_animation(float(event.cue.data.get("duration", 1.0)))

func _wave_animation(duration: float) -> void:
	var bones = []
	for i in range(get_bone_count()):
		bones.append(get_bone(i))
	
	if bones.is_empty():
		return
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_loops(2)
	
	# Wave motion
	tween.tween_property(bones[0], "rotation", deg_to_rad(40), duration * 0.25)
	if bones.size() > 1:
		tween.parallel().tween_property(bones[1], "rotation", deg_to_rad(20), duration * 0.25)
	if bones.size() > 2:
		tween.parallel().tween_property(bones[2], "rotation", deg_to_rad(-10), duration * 0.25)
	
	tween.tween_property(bones[0], "rotation", deg_to_rad(10), duration * 0.25)
	if bones.size() > 1:
		tween.parallel().tween_property(bones[1], "rotation", deg_to_rad(30), duration * 0.25)
	if bones.size() > 2:
		tween.parallel().tween_property(bones[2], "rotation", deg_to_rad(15), duration * 0.25)
	
	tween.tween_property(bones[0], "rotation", deg_to_rad(-20), duration * 0.25)
	if bones.size() > 1:
		tween.parallel().tween_property(bones[1], "rotation", deg_to_rad(10), duration * 0.25)
	if bones.size() > 2:
		tween.parallel().tween_property(bones[2], "rotation", deg_to_rad(25), duration * 0.25)
	
	tween.tween_property(bones[0], "rotation", 0, duration * 0.25)
	if bones.size() > 1:
		tween.parallel().tween_property(bones[1], "rotation", 0, duration * 0.25)
	if bones.size() > 2:
		tween.parallel().tween_property(bones[2], "rotation", 0, duration * 0.25)

func _flex_animation(duration: float) -> void:
	var bones = []
	for i in range(get_bone_count()):
		bones.append(get_bone(i))
	
	if bones.is_empty():
		return
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	if bones.size() > 0:
		tween.tween_property(bones[0], "rotation", deg_to_rad(30), duration * 0.4)
	if bones.size() > 1:
		tween.tween_property(bones[1], "rotation", deg_to_rad(-45), duration * 0.4)
	if bones.size() > 2:
		tween.tween_property(bones[2], "rotation", deg_to_rad(20), duration * 0.4)
	
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), duration * 0.2)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), duration * 0.4)
	
	tween.tween_interval(duration * 0.2)
	
	if bones.size() > 0:
		tween.tween_property(bones[0], "rotation", 0, duration * 0.3)
	if bones.size() > 1:
		tween.tween_property(bones[1], "rotation", 0, duration * 0.3)
	if bones.size() > 2:
		tween.tween_property(bones[2], "rotation", 0, duration * 0.3)

func _pose_limb(bone_poses: Dictionary, duration: float) -> void:
	if bone_poses.is_empty():
		_wave_animation(duration)
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	
	for bone_name in bone_poses:
		var bone_idx = find_bone(bone_name)
		if bone_idx >= 0:
			var target = bone_poses[bone_name]
			if target is float:
				tween.tween_property(get_bone(bone_idx), "rotation", deg_to_rad(target), duration)
			elif target is Dictionary:
				if target.has("rotation"):
					tween.tween_property(get_bone(bone_idx), "rotation", deg_to_rad(float(target["rotation"])), duration)
