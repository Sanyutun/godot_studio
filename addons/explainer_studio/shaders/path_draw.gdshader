shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 line_color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float width : hint_range(0.0, 20.0) = 4.0;
uniform float glow : hint_range(0.0, 2.0) = 0.5;

void fragment() {
	// For Line2D, we'll use the texture coordinates
	// The progress masks the line from start to end
	vec4 tex = texture(TEXTURE, UV);
	
	// Use UV.x as progress along the line (Line2D uses texture)
	if (UV.x > progress) {
		discard;
	}
	
	// Add subtle glow
	vec4 glow_color = line_color;
	glow_color.a *= glow * (1.0 - UV.x / max(progress, 0.001));
	COLOR = mix(glow_color, line_color, 0.7);
	COLOR.a *= tex.a;
}
