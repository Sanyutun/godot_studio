shader_type canvas_item;
render_mode blend_mix;

// Dilation-based outline shader for crisp sticker look
uniform float outline_width_px : hint_range(0.0, 50.0) = 10.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 shadow_offset = vec2(4.0, 6.0);
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.18;

// For resolution-independent look
uniform vec2 texture_size = vec2(512.0, 512.0);

void fragment() {
	vec2 size = texture_size;
	if (size.x < 1.0 || size.y < 1.0) {
		size = vec2(1.0 / TEXTURE_PIXEL_SIZE.x, 1.0 / TEXTURE_PIXEL_SIZE.y);
	}
	
	vec2 pixel_size = 1.0 / size;
	float outline_width = outline_width_px * pixel_size.x;
	
	// Sample alpha in radius to create dilation
	float alpha = texture(TEXTURE, UV).a;
	float max_alpha = alpha;
	
	// Sample in a circle for smooth outline
	int samples = 16;
	for (int i = 0; i < samples; i++) {
		float angle = float(i) * 6.283185 / float(samples);
		vec2 offset = vec2(cos(angle), sin(angle)) * outline_width * 2.0;
		max_alpha = max(max_alpha, texture(TEXTURE, UV + offset).a);
		// Also sample at half radius for smoother falloff
		offset = vec2(cos(angle), sin(angle)) * outline_width;
		max_alpha = max(max_alpha, texture(TEXTURE, UV + offset).a);
	}
	
	// Shadow
	vec2 shadow_uv = UV + shadow_offset * pixel_size;
	float shadow = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 6.283185 / 8.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * outline_width * 1.5;
		shadow = max(shadow, texture(TEXTURE, shadow_uv + offset).a);
	}
	
	vec4 tex = texture(TEXTURE, UV);
	
	// Composite: shadow underneath, outline, then texture on top
	if (tex.a > 0.01) {
		// Draw texture
		COLOR = tex;
	} else if (max_alpha > 0.01) {
		// Draw outline
		COLOR = outline_color;
		COLOR.a = max_alpha;
	} else if (shadow > 0.01) {
		// Draw shadow
		COLOR = vec4(0.0, 0.0, 0.0, shadow * shadow_alpha);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
