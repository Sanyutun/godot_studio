@tool
class_name PixelOrganAnimator
extends Node2D
## Wrapper for anatomical AnimationPlayer setups

@export var animation_name: String = ""
@export var default_speed_scale: float = 1.0
@export var use_outline: bool = true

func _ready() -> void:
	if use_outline:
		for child in get_children():
			if child is Sprite2D and child.material == null:
				var shader = load("res://addons/explainer_studio/shaders/pixel_outline.gdshader")
				if shader:
					var mat = ShaderMaterial.new()
					mat.shader = shader
					mat.set_shader_parameter("outline_width", 1.0)
					mat.set_shader_parameter("outline_color", Color.BLACK)
					child.material = mat

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"play_organ":
		var anim_player = get_node_or_null("AnimationPlayer")
		if anim_player == null:
			anim_player = find_child("AnimationPlayer", true, false)
		if anim_player and anim_player is AnimationPlayer:
			var anim = event.cue.data.get("animation_name", animation_name)
			var speed = float(event.cue.data.get("speed_scale", default_speed_scale))
			anim_player.speed_scale = speed
			if anim and anim_player.has_animation(anim):
				anim_player.play(anim)
				# Add breathing scale effect
				var sprite = get_node_or_null("Sprite2D")
				if sprite == null:
					sprite = find_child("Sprite2D", true, false)
				if sprite:
					_add_pulse_effect(sprite)
	elif event.cue.action == &"stop_organ":
		var anim_player = get_node_or_null("AnimationPlayer")
		if anim_player == null:
			anim_player = find_child("AnimationPlayer", true, false)
		if anim_player and anim_player is AnimationPlayer:
			anim_player.stop()
	elif event.cue.action == &"beat":
		var sprite = get_node_or_null("Sprite2D")
		if sprite == null:
			sprite = find_child("Sprite2D", true, false)
		if sprite:
			_heartbeat(sprite)

func _add_pulse_effect(sprite: Sprite2D) -> void:
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "scale", Vector2(1.05, 1.05), 0.4)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.4)

func _heartbeat(sprite: Sprite2D) -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.1)
	tween.tween_property(sprite, "scale", Vector2(0.95, 0.95), 0.1)
	tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.1)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.15)
