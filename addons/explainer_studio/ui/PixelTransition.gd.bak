@tool
class_name PixelTransition
extends CanvasLayer
## Pixel art transition effects

@export var transition_color: Color = Color.BLACK

func fade_in(duration: float = 0.5) -> void:
	var rect = ColorRect.new()
	rect.color = transition_color
	rect.size = get_viewport().get_visible_rect().size
	add_child(rect)
	rect.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration)
	tween.tween_callback(rect.queue_free)

func fade_out(duration: float = 0.5) -> void:
	var rect = ColorRect.new()
	rect.color = transition_color
	rect.size = get_viewport().get_visible_rect().size
	add_child(rect)
	rect.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, duration)

func pixel_dissolve(duration: float = 0.8) -> void:
	var rect = ColorRect.new()
	rect.color = transition_color
	rect.size = get_viewport().get_visible_rect().size
	add_child(rect)
	
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float pixel_size = 4.0;
	vec2 pixel_uv = floor(UV * pixel_size) / pixel_size;
	float noise = fract(sin(dot(pixel_uv, vec2(12.9898, 78.233))) * 43758.5453);
	if (noise < progress) {
		discard;
	}
	COLOR = vec4(0.0, 0.0, 0.0, 1.0);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	mat.set_shader_parameter("progress", 0.0)
	
	var tween = create_tween()
	tween.tween_method(func(p): mat.set_shader_parameter("progress", p), 0.0, 1.0, duration)
	tween.tween_callback(rect.queue_free)
