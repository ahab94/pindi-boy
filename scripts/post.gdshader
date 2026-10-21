// Full-screen finishing pass, drawn over the street and under the HUD:
// a soft glow on bright things, a little more contrast and colour, a warm
// grade and a vignette. Godot note: hint_screen_texture gives a shader
// the picture drawn so far, so this ColorRect can rework it.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.34;
uniform float contrast = 1.07;
uniform float saturation = 1.1;
uniform vec3 tint = vec3(1.03, 1.0, 0.96);
uniform float bloom = 0.25;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.3;
		vec2 o = vec2(cos(a), sin(a)) * SCREEN_PIXEL_SIZE * 6.0;
		glow += max(texture(screen_tex, uv + o).rgb - 0.8, 0.0);
		glow += max(texture(screen_tex, uv + o * 2.6).rgb - 0.8, 0.0);
	}
	col += glow / 16.0 * bloom * 2.5;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= tint;
	float v = length((uv - 0.5) * vec2(1.0, 0.85));
	col *= 1.0 - vignette * smoothstep(0.32, 0.85, v);
	COLOR = vec4(col, 1.0);
}
