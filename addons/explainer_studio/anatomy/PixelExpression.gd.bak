@tool
class_name PixelExpression
extends Sprite2D
## Facial expression controller

@export var emotions: Dictionary = {
	"happy": "",
	"dizzy": "",
	"angry": "",
	"painful": "",
	"sad": "",
	"surprised": ""
}

func _ready() -> void:
	if material == null:
		var shader = load("res://addons/explainer_studio/shaders/pixel_outline.gdshader")
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("outline_width", 1.0)
			mat.set_shader_parameter("outline_color", Color(0.2, 0.15, 0.1, 1))
			material = mat

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"set_expression":
		var emotion = String(event.cue.data.get("emotion", ""))
		_set_expression(emotion)
	elif event.cue.action == &"emote":
		var emotion = String(event.cue.data.get("emotion", ""))
		_set_expression(emotion)

func _set_expression(emotion: String) -> void:
	if emotions.has(emotion) and emotions[emotion] != "":
		var tex_path = emotions[emotion]
		var tex = load(tex_path)
		if tex:
			texture = tex
	
	if emotion == "dizzy":
		_dizzy_effect()
	elif emotion == "painful":
		_pain_effect()
	elif emotion == "happy":
		_happy_effect()
	elif emotion == "angry":
		_angry_effect()
	elif emotion == "surprised":
		_surprised_effect()

func _dizzy_effect() -> void:
	var tween = create_tween()
	tween.set_loops(3)
	tween.set_trans(Tween.TRANS_SINE)
	for i in range(6):
		tween.tween_property(self, "position", position + Vector2(randf_range(-3, 3), randf_range(-2, 2)), 0.04)
	tween.tween_property(self, "position", position, 0.04)
	tween.tween_property(self, "rotation", deg_to_rad(5), 0.05)
	tween.tween_property(self, "rotation", deg_to_rad(-5), 0.05)
	tween.tween_property(self, "rotation", 0, 0.05)

func _pain_effect() -> void:
	var tween = create_tween()
	tween.set_loops(4)
	tween.tween_property(self, "scale", Vector2(1.1, 0.9), 0.08)
	tween.tween_property(self, "scale", Vector2(0.9, 1.1), 0.08)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	modulate = Color(1.2, 0.8, 0.8, 1)
	await get_tree().create_timer(0.5).timeout
	modulate = Color.WHITE

func _happy_effect() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.2)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3)

func _angry_effect() -> void:
	var tween = create_tween()
	tween.tween_property(self, "rotation", deg_to_rad(-3), 0.1)
	tween.tween_property(self, "rotation", deg_to_rad(3), 0.1)
	tween.tween_property(self, "rotation", 0, 0.1)
	modulate = Color(1.3, 0.7, 0.7, 1)
	await get_tree().create_timer(0.3).timeout
	modulate = Color.WHITE

func _surprised_effect() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.3)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4)
