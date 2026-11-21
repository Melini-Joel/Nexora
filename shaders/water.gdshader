shader_type spatial;
// Agua con olas suaves y brillo en los bordes (efecto Fresnel).
render_mode blend_mix, cull_disabled;

uniform vec4 water_color : source_color = vec4(0.1, 0.38, 0.55, 1.0);
uniform vec4 shine_color : source_color = vec4(0.65, 0.85, 0.95, 1.0);
uniform float wave_height = 0.08;  // Más alto = mar picado (tormenta).

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float speed = 1.0 + wave_height * 2.0;
	VERTEX.y += (sin(world.x * 0.15 + TIME * 0.8 * speed) + cos(world.z * 0.12 + TIME * 0.6 * speed)) * wave_height
		+ sin(world.x * 0.4 + world.z * 0.3 + TIME * 2.1 * speed) * wave_height * 0.35;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(water_color.rgb, shine_color.rgb, fresnel * 0.5);
	ALPHA = mix(0.8, 0.95, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.15;
	SPECULAR = 0.8;
}
