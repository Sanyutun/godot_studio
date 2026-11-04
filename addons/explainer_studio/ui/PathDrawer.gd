@tool
class_name PathDrawer
extends Line2D
## Cue-driven path drawer with shader-based animation

signal path_finished

func _ready() -> void:
	if material == null:
		var shader = load("res://addons/explainer_studio/shaders/path_draw.gdshader")
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("progress", 0.0)
			material = mat
	else:
		if material is ShaderMaterial:
			material.set_shader_parameter("progress", 0.0)

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"draw_path" or event.cue.action == &"path":
		_draw_path(event)

func _draw_path(event: CueEvent) -> void:
	var data = event.cue.data
	var duration = float(data.get("duration", 1.0))
	
	if material is ShaderMaterial:
		material.set_shader_parameter("progress", 0.0)
		var tween = create_tween()
		tween.tween_method(func(p): 
			if material is ShaderMaterial:
				material.set_shader_parameter("progress", p)
		, 0.0, 1.0, duration)
		tween.set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(func(): path_finished.emit())
	else:
		# Fallback: animate width
		width = 0.0
		var tween = create_tween()
		tween.tween_property(self, "width", 4.0, duration)
		tween.finished.connect(func(): path_finished.emit())
