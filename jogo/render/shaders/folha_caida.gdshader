shader_type spatial;
// Patch fauna, fase 2 (DesenhoPlantasReagem): folha seca do outono. Caindo: virada para a câmera e girando (a escala
// em X vem por instância, o quad "vira de lado" como folha de verdade); no chão: deitada (`plano`). Iluminada como o
// resto do mundo (à noite escurece junto). Tamanho por instância em INSTANCE_CUSTOM.x/y (m).
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform bool plano = false;
uniform bool redondo = false;     // fase 3: fruto e semente no vento — ponto redondo, sombreado como bolinha
varying vec4 cor;

void vertex() {
	vec2 esc = INSTANCE_CUSTOM.xy;
	if (!plano) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * esc.x, INV_VIEW_MATRIX[1] * esc.y,
				INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
	cor = COLOR;
}

void fragment() {
	vec2 p = UV - 0.5;
	if (redondo) {
		if (length(p) > 0.5) {
			discard;
		}
		// bolinha: luz de cima à esquerda, borda de baixo mais escura
		ALBEDO = cor.rgb * (1.0 - 0.35 * smoothstep(0.1, 0.5, length(p - vec2(-0.12, -0.14))));
		ROUGHNESS = 0.7;
	} else {
		// folha em losango com ponta: fora dele, nada
		if (abs(p.x) * 1.9 + abs(p.y) * 1.25 > 0.62) {
			discard;
		}
		float nervura = 1.0 - smoothstep(0.0, 0.05, abs(p.x)) * 0.25;
		ALBEDO = cor.rgb * (0.82 + 0.18 * nervura);
		ROUGHNESS = 0.85;
	}
}
