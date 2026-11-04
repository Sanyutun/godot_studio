@tool
class_name StickerFrame
extends TextureRect
## Sticker frame with crisp outline shader for PaperClip aesthetic.

@export var outline_width_px: float = 10.0:
	set(value):
		outline_width_px = value
		if material is ShaderMaterial:
			material.set_shader_parameter("outline_width_px", value)

@export var outline_color: Color = Color.WHITE:
	set(value):
		outline_color = value
		if material is ShaderMaterial:
			material.set_shader_parameter("outline_color", value)

@export var shadow_offset: Vector2 = Vector2(4, 6):
	set(value):
		shadow_offset = value
		if material is ShaderMaterial:
			material.set_shader_parameter("shadow_offset", value)

@export var shadow_alpha: float = 0.18:
	set(value):
		shadow_alpha = value
		if material is ShaderMaterial:
			material.set_shader_parameter("shadow_alpha", value)

func _ready() -> void:
	if material == null:
		var shader = load("res://addons/explainer_studio/shaders/sticker_outline.gdshader")
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			material = mat
	
	if material is ShaderMaterial and texture:
		material.set_shader_parameter("texture_size", texture.get_size())

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"sticker" or event.cue.action == &"show":
		visible = true
		modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.3)
	elif event.cue.action == &"hide_sticker":
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func(): visible = false)
