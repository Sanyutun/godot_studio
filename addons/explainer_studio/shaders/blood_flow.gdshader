shader_type canvas_item;

uniform float flow_speed : hint_range(0.0, 5.0) = 1.0;
uniform vec4 flow_color : source_color = vec4(0.8, 0.1, 0.2, 1.0);
uniform float flow_width : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 uv = UV;
	float time = TIME * flow_speed;
	
	// Create flowing pattern
	float flow = sin(uv.x * 10.0 - time * 3.0) * 0.5 + 0.5;
	flow *= sin(uv.y * 5.0 + time) * 0.3 + 0.7;
	
	vec4 base = texture(TEXTURE, uv);
	vec4 flow_effect = flow_color * flow;
	
	COLOR = mix(base, flow_effect, flow * flow_width);
	COLOR.a = base.a;
}
