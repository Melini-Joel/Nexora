shader_type spatial;
// Material de los objetos hechos por código (árboles, rocas, plantas, construcciones).
// El color viene de cada vértice. El canal alfa del color dice cuánto se mueve con el
// viento esa parte (0 = rígido, como troncos y rocas; 1 = hojas y plantas).

uniform float wind_strength = 0.05;

void vertex() {
	float sway = COLOR.a;
	if (sway > 0.01) {
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float height = max(VERTEX.y, 0.0);
		float wave = sin(TIME * 1.3 + world.x * 0.15 + world.z * 0.11) * 0.6 + sin(TIME * 2.7 + world.x * 0.4 + world.z * 0.2) * 0.25;
		VERTEX.x += wave * wind_strength * height * sway;
		VERTEX.z += cos(TIME * 1.1 + world.z * 0.13) * wind_strength * 0.6 * height * sway;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
