shader_type spatial;
// Terreno: color de cada vértice (bioma, altura, pendiente) + detalle con ruido para que
// no se vea liso de cerca ni repetido de lejos.

uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float large = texture(detail_noise, world_pos.xz * 0.012).r;
	float medium = texture(detail_noise, world_pos.xz * 0.09).r;
	float small = texture(detail_noise, world_pos.xz * 0.7).r;
	vec3 color = COLOR.rgb * (0.82 + 0.3 * large) * (0.9 + 0.2 * medium) * (0.94 + 0.12 * small);
	ALBEDO = color;
	ROUGHNESS = 0.9 + small * 0.08;
}
