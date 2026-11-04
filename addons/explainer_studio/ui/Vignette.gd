extends ColorRect
## Vignette overlay for PaperClip aesthetic

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D vignette_tex;

void fragment() {
	vec4 tex = texture(vignette_tex, UV);
	COLOR = tex;
}
"""
	shader_material.shader = shader
	material = shader_material
	
	# Create radial gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0, 0, 0, 0))
	gradient.add_point(0.6, Color(0, 0, 0, 0))
	gradient.add_point(1.0, Color(0, 0, 0, 0.4))
	
	var gradient_tex = GradientTexture2D.new()
	gradient_tex.gradient = gradient
	gradient_tex.fill = GradientTexture2D.FILL_RADIAL
	gradient_tex.fill_from = Vector2(0.5, 0.5)
	gradient_tex.fill_to = Vector2(1.0, 0.5)
	
	shader_material.set_shader_parameter("vignette_tex", gradient_tex)
