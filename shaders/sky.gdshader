shader_type sky;
// Cielo: degradé según la hora, disco del sol con brillo, nubes que se mueven y estrellas de noche.
// Los colores los cambia el ciclo de día y noche (day_night.gd).

uniform vec3 sky_top_color : source_color = vec3(0.3, 0.5, 0.82);
uniform vec3 sky_horizon_color : source_color = vec3(0.72, 0.8, 0.88);
uniform vec3 ground_horizon_color : source_color = vec3(0.5, 0.65, 0.75);
uniform vec3 ground_bottom_color : source_color = vec3(0.12, 0.3, 0.42);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_coverage = 0.45;
uniform float star_intensity = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color;
	if (dir.y >= 0.0) {
		color = mix(sky_horizon_color, sky_top_color, pow(clamp(dir.y, 0.0, 1.0), 0.55));
		if (LIGHT0_ENABLED) {
			float d = max(dot(dir, LIGHT0_DIRECTION), 0.0);
			color += LIGHT0_COLOR * min(LIGHT0_ENERGY, 1.5) * (pow(d, 1200.0) * 8.0 + pow(d, 24.0) * 0.3);
		}
		// Estrellas: puntitos en una grilla esférica (sin estirarse cerca del horizonte).
		vec2 star_uv = vec2(atan(dir.x, dir.z) * 70.0, acos(clamp(dir.y, -1.0, 1.0)) * 70.0);
		vec2 cell = floor(star_uv);
		float h = hash(cell);
		float star = step(0.975, h) * smoothstep(0.12, 0.0, length(fract(star_uv) - 0.5)) * star_intensity * smoothstep(0.02, 0.3, dir.y);
		color += vec3(star) * (0.7 + 0.3 * sin(TIME * 2.0 + h * 60.0));
		vec2 cloud_uv = dir.xz / (dir.y + 0.1) * 1.4 + vec2(TIME * 0.004, TIME * 0.0025);
		float n = fbm(cloud_uv * 2.0);
		float clouds = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.28, n) * smoothstep(0.0, 0.18, dir.y);
		vec3 shade = cloud_color * (0.78 + 0.22 * fbm(cloud_uv * 4.0 + 3.7));
		color = mix(color, shade, clouds * 0.9);
	} else {
		color = mix(ground_horizon_color, ground_bottom_color, clamp(-dir.y * 3.0, 0.0, 1.0));
	}
	COLOR = color;
}
