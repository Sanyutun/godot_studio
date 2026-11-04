shader_type canvas_item;

uniform float glow_intensity : hint_range(0.0, 4.0) = 1.5;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	
	// Create pulsing glow
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	vec4 glow = glow_color * glow_intensity * pulse;
	
	// Add glow around bright areas
	float brightness = (tex.r + tex.g + tex.b) / 3.0;
	if (brightness > 0.3) {
		COLOR = tex + glow * brightness * 0.5;
	} else {
		COLOR = tex;
	}
	COLOR.a = tex.a;
}
