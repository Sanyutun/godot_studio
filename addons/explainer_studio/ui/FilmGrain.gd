extends ColorRect
## Film grain overlay for PaperClip aesthetic

@export var noise_texture: NoiseTexture2D
var shader_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	
	if material is ShaderMaterial:
		shader_material = material
	else:
		var shader = Shader.new()
		shader.code = """
shader_type canvas_item;

uniform sampler2D noise_tex: repeat_enable;
uniform float time = 0.0;
uniform float intensity = 0.05;

void fragment() {
	vec4 noise = texture(noise_tex, UV + vec2(time * 0.1, time * 0.07));
	float grain = (noise.r - 0.5) * intensity;
	COLOR = vec4(vec3(grain), grain);
}
"""
		shader_material = ShaderMaterial.new()
		shader_material.shader = shader
		material = shader_material
	
	if noise_texture == null:
		noise_texture = NoiseTexture2D.new()
		var noise = FastNoiseLite.new()
		noise.seed = 12345
		noise.frequency = 0.05
		noise.fractal_octaves = 4
		noise_texture.noise = noise
		noise_texture.seamless = true
		noise_texture.width = 256
		noise_texture.height = 256
	
	shader_material.set_shader_parameter("noise_tex", noise_texture)
	
	# Animate time
	var tween = create_tween()
	tween.set_loops()
	tween.tween_method(_set_time, 0.0, 100.0, 300.0)  # Very slow loop

func _set_time(t: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("time", t * 0.3)
