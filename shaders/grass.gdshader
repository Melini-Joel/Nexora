shader_type spatial;
// Pasto que se mueve con el viento. UV.y = altura relativa de la hoja (0 base, 1 punta).
render_mode cull_disabled, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.16, 0.34, 0.12, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.76, 0.3, 1.0);
uniform float wind_strength = 0.14;

varying float height;

void vertex() {
	height = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * 1.7 + world.x * 0.35 + world.z * 0.27) + sin(TIME * 2.9 + world.x * 0.9) * 0.35;
	VERTEX.x += wave * wind_strength * height * height;
	VERTEX.z += cos(TIME * 1.3 + world.z * 0.31) * wind_strength * 0.6 * height * height;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(base_color.rgb, tip_color.rgb, height) * COLOR.rgb;
	ROUGHNESS = 0.95;
}
