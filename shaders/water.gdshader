shader_type spatial;
// Agua: olas, ondas finas que se mueven (mapa de normales) y brillo en los bordes (Fresnel).
render_mode blend_mix, cull_disabled;

uniform vec4 water_color : source_color = vec4(0.08, 0.34, 0.5, 1.0);
uniform vec4 shine_color : source_color = vec4(0.65, 0.85, 0.95, 1.0);
uniform float wave_height = 0.08;  // Más alto = mar picado (tormenta).
uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float speed = 1.0 + wave_height * 2.0;
	VERTEX.y += (sin(world.x * 0.15 + TIME * 0.8 * speed) + cos(world.z * 0.12 + TIME * 0.6 * speed)) * wave_height
		+ sin(world.x * 0.4 + world.z * 0.3 + TIME * 2.1 * speed) * wave_height * 0.35;
	world_pos = world;
}

void fragment() {
	vec2 uv_a = world_pos.xz * 0.045 + vec2(TIME * 0.012, TIME * 0.008);
	vec2 uv_b = world_pos.xz * 0.07 - vec2(TIME * 0.009, TIME * 0.014);
	NORMAL_MAP = mix(texture(ripple_normal, uv_a).rgb, texture(ripple_normal, uv_b).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.5 + wave_height * 2.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(water_color.rgb, shine_color.rgb, fresnel * 0.45);
	ALPHA = mix(0.82, 0.96, fresnel);
	ROUGHNESS = 0.04;
	METALLIC = 0.1;
	SPECULAR = 0.9;
}
