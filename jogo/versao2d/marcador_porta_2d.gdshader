// Marcador de porta no chão, versão 2D (o mesmo desenho do 3D: listras de construção, moldura e seta do fluxo),
// em pixels inteiros: o UV é quantizado para não sair liso no meio do pixel art. A seta aponta para UV.y = 0.
shader_type canvas_item;

uniform float fluido = 0.0;
uniform float passos = 24.0;

float seta(vec2 q) {
	float ponta = max(abs(q.x) - 0.655 * (q.y + 0.60), q.y + 0.02);
	float haste = max(abs(q.x) - 0.11, abs(q.y - 0.25) - 0.27);
	return min(ponta, haste);
}

void fragment() {
	vec2 uv = (floor(UV * passos) + 0.5) / passos;
	vec2 q = uv * 2.0 - 1.0;
	float pulso = 0.82 + 0.18 * sin(TIME * 3.2);
	float borda = max(abs(q.x), abs(q.y));
	float moldura = step(0.80, borda);
	float s = fract((uv.x + uv.y) * 2.75);
	float faixa = step(0.48, s);
	vec3 cor = mix(COLOR.rgb, COLOR.rgb * 0.10, faixa * (1.0 - moldura));
	float d = seta(q / 0.78) * 0.78;
	float miolo = step(d, 0.0);
	float contorno = step(d, 0.07);
	vec3 cor_seta = mix(vec3(0.82, 0.80, 0.72), vec3(0.36, 0.70, 1.0), fluido);
	cor = mix(cor, vec3(0.03), contorno * 0.9);
	cor = mix(cor, cor_seta, miolo);
	COLOR = vec4(cor * (0.75 + 0.25 * pulso), mix(0.62 + 0.14 * pulso, 0.95, max(moldura, contorno)));
}
