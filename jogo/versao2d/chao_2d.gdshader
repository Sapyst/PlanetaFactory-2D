// Chão da versão 2D: a mesma malha (relevo) e os mesmos mapas do chão 3D (camadas, fábrica, ambiente), desenhados
// em pixel art: camada por tile com borda deformada e pontilhada; água animada com espuma; piso de fábrica que cresce
// em volta das construções (mapa de fábrica, igual ao 3D) misturado ao chão de antes; sujeira, óleo, água suja,
// brasa e queimado (mapa de ambiente); luz nas encostas. As texturas são da vista de 35° (1 tile = 35 × 20 px).
shader_type canvas_item;

uniform sampler2DArray texturas : filter_nearest, repeat_enable;
uniform sampler2D agua_rasa : filter_nearest, repeat_enable;
uniform sampler2D agua_funda : filter_nearest, repeat_enable;
uniform sampler2D detalhe : filter_linear, repeat_enable;
uniform sampler2D mapa_camadas : filter_nearest;
uniform vec2 origem_mapa;
uniform sampler2D mapa_ambiente : filter_linear, hint_default_transparent;
uniform sampler2D mapa_fabrica : filter_nearest, hint_default_transparent;
uniform float camada_piso = 9.0;
uniform float camada_jazida = 7.0;
uniform float camada_praia = 10.0;
uniform float primeira_agua = 11.0;

varying vec2 grade;
varying vec2 px;
varying vec4 dados;      // r = água (campo contínuo), g = fundo, b = luz da encosta

const vec2 TEX = vec2(140.0, 80.0);

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

float camada_em(vec2 g) {
	vec2 t = floor(g) - origem_mapa;
	return floor(texture(mapa_camadas, (t + 0.5) / 34.0).r * 255.0 + 0.5);
}

bool eh_agua(float c) { return c >= primeira_agua; }

vec4 fabrica_em(vec2 g) { return texture(mapa_fabrica, (floor(g) - origem_mapa + 0.5) / 34.0); }

void vertex() {
	grade = UV;
	px = VERTEX;
	dados = COLOR;
}

void fragment() {
	float b = bayer(px);
	vec2 w1 = vec2(texture(detalhe, grade * 0.06).r, texture(detalhe, grade * 0.06 + vec2(0.37, 0.71)).r) - 0.5;
	vec2 w2 = vec2(texture(detalhe, grade * 0.17 + vec2(0.53, 0.19)).r, texture(detalhe, grade * 0.17 + vec2(0.11, 0.83)).r) - 0.5;
	vec2 uvt = mod(px, TEX) / TEX;
	vec4 fab = fabrica_em(grade);
	float wf = max(dados.r, fab.a) + (texture(detalhe, grade * 0.031).r - 0.5) * 0.12;
	vec3 cor;
	if (wf + (b - 0.5) * 0.12 > 0.5) {
		// água: 8 quadros andando; rasa perto da beira, funda longe; espuma na beira
		float q = mod(floor(TIME * 6.0), 8.0);
		vec2 uva = vec2((uvt.x + q) / 8.0, uvt.y);
		vec3 rasa = texture(agua_rasa, uva).rgb;
		vec3 funda = texture(agua_funda, uva).rgb;
		cor = dados.g + (b - 0.5) * 0.3 > 0.5 ? funda : rasa;
		if (wf < 0.56 && b < 0.75) { cor = mix(cor, vec3(0.62, 0.70, 0.70), 0.6); }
	} else {
		// terra: camada no ponto deformado (borda ondulada) + pontilhado na passagem
		vec2 pw = grade + w1 * 1.1 + w2 * 0.35 + (b - 0.5) * 0.3;
		float lk = camada_em(pw);
		if (eh_agua(lk)) { lk = camada_em(grade); }
		if (eh_agua(lk)) { lk = camada_praia; }
		cor = texture(texturas, vec3(uvt, lk)).rgb;
		// margem molhada
		float beira = smoothstep(0.2, 0.5, wf);
		cor *= 1.0 - 0.3 * step(0.5, beira + (b - 0.5) * 0.4);
		// piso de fábrica: o mapa já vem espalhado em volta das construções (e cresce a partir delas); 4 leituras
		// deformadas dão a borda irregular; o pontilhado mistura com o chão de antes. Jazida nunca vira piso.
		float f = (fabrica_em(grade + w1 * 1.3).r + fabrica_em(grade + w2 * 1.0).r
				+ fabrica_em(grade + vec2(w2.y, -w1.x) * 1.4).r + fab.r) * 0.25;
		f = smoothstep(0.18, 0.55, f);
		if (lk == camada_jazida) { f = 0.0; }
		if (f + (b - 0.5) * 0.5 > 0.5) {
			vec2 tp = vec2(fract(grade.x / 4.0), 1.0 - fract(grade.y / 4.0));
			cor = texture(texturas, vec3(tp, camada_piso)).rgb;
		}
		// ambiente: R sujeira, G óleo, B água suja (0..0,45) ou brasa (0,5..1), A queimado — mancha orgânica
		vec2 ap = (grade + w1 * 1.6 - origem_mapa) / 34.0;
		vec2 bp = (grade + w2 * 2.4 + vec2(w1.y, -w1.x) * 0.8 - origem_mapa) / 34.0;
		vec4 amb = (texture(mapa_ambiente, ap) + texture(mapa_ambiente, bp)) * 0.5;
		if (amb.a + (b - 0.5) * 0.3 > 0.35) { cor = mix(cor, vec3(0.07, 0.06, 0.055), 0.75); }          // queimado
		if (amb.r + (b - 0.5) * 0.3 > 0.3) { cor = mix(cor, vec3(0.16, 0.11, 0.07), 0.55 * amb.r + 0.2); }  // sujeira
		if (amb.g + (b - 0.5) * 0.3 > 0.3) { cor = mix(cor, vec3(0.03, 0.03, 0.035), 0.7); }              // óleo
		if (amb.b < 0.5 && amb.b + (b - 0.5) * 0.2 > 0.2) { cor = mix(cor, vec3(0.20, 0.22, 0.12), 0.6); } // água suja
		if (amb.b >= 0.5) {                                                                                 // brasa
			float br = (amb.b - 0.5) * 2.0 * (0.7 + 0.3 * sin(TIME * 7.0 + grade.x * 3.1));
			if (br + (b - 0.5) * 0.4 > 0.35) { cor = mix(vec3(0.55, 0.10, 0.02), vec3(1.0, 0.55, 0.12), step(0.7, br)); }
		}
	}
	COLOR = vec4(cor * dados.b, 1.0);
}
