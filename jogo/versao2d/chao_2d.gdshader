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
uniform sampler2D mapa_teia : filter_linear, hint_default_black;   // R = infestação da toca das aranhas (Infestacao)
uniform sampler2D tex_teia : filter_linear_mipmap, repeat_enable, hint_default_transparent;   // fios de seda (alfa)
uniform float camada_piso = 9.0;
uniform float camada_jazida = 7.0;
uniform float camada_praia = 10.0;
uniform float primeira_agua = 11.0;

varying vec2 grade;
varying vec2 px;
varying vec4 dados;      // r = água (campo contínuo), g = fundo, b = luz da encosta, a = 1 rio / 0,35 lago
global uniform float estacao_atual;      // patch fauna, fase 2: capim e flores pela estação, limo
global uniform float vico_grama;         // −1 seco … +1 viçoso depois da chuva
global uniform vec3 sol_dir;             // y > 0 = dia (flor aberta)
global uniform sampler2D trilha_mapa : filter_linear, hint_default_black;   // patch fauna, fase 5: R = trilha dos ratos
global uniform vec3 trilha_origem;

vec3 cor_estacao(float e) {
	vec3 c[4] = vec3[4](vec3(0.94, 1.08, 0.9), vec3(1.0), vec3(1.12, 0.98, 0.66), vec3(0.86, 0.84, 0.74));
	int i = int(floor(e)) % 4;
	return mix(c[(i + 3) % 4], c[i], smoothstep(0.0, 0.25, fract(e)));
}

float por_estacao(float e, vec4 v) {
	float f[4] = float[4](v.x, v.y, v.z, v.w);
	int i = int(floor(e)) % 4;
	return mix(f[(i + 3) % 4], f[i], smoothstep(0.0, 0.25, fract(e)));
}

float _hp(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

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
		// limo (fase 2): só água parada (lago), na parte rasa; manchas grandes que juntam na beira
		float parada = step(0.15, dados.a) * step(dados.a, 0.6);
		if (parada > 0.0) {
			float temporada = por_estacao(estacao_atual, vec4(0.45, 1.0, 0.65, 0.1));
			float mancha = texture(detalhe, grade * 0.12 + vec2(TIME * 0.002, TIME * 0.0015)).r;
			float beira_l = smoothstep(0.95, 0.55, wf);
			float rasa = 1.0 - smoothstep(0.1, 0.55, dados.g);
			if (temporada * rasa > 0.05 && mancha * 0.75 + beira_l * 0.42 + (b - 0.5) * 0.06 > 0.54 + (1.0 - temporada * rasa) * 0.4) {
				cor = mix(vec3(0.15, 0.23, 0.07), vec3(0.22, 0.31, 0.09), step(0.8, b));
			}
		}
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
		// capim pela estação e pelo viço (fase 2: chuva verde, seca palha) — só no que é verde na textura — e
		// flores de 1 pixel que abrem de dia (primavera muitas, inverno nenhuma)
		float verde = clamp((cor.g - max(cor.r, cor.b)) * 8.0, 0.0, 1.0);
		if (verde > 0.0) {
			vec3 tn = cor_estacao(estacao_atual);
			tn *= mix(vec3(1.0), vec3(0.86, 1.15, 0.8), max(vico_grama, 0.0));
			tn *= mix(vec3(1.0), vec3(1.5, 1.15, 0.5), max(-vico_grama, 0.0));
			cor = mix(cor, cor * tn, verde);
			vec2 cel = floor(px);
			if (_hp(cel) < 0.012 * por_estacao(estacao_atual, vec4(1.0, 0.55, 0.12, 0.0)) * verde && sol_dir.y > 0.0) {
				float k = _hp(cel + 17.0);
				cor = k < 0.35 ? vec3(0.92, 0.9, 0.78) : (k < 0.6 ? vec3(0.95, 0.76, 0.16) : (k < 0.82 ? vec3(0.52, 0.42, 0.84) : vec3(0.86, 0.34, 0.42)));
			}
		}
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
		// infestação da toca: terra escura e orgânica com fios de teia por cima, fechando perto da toca
		float inf = (texture(mapa_teia, ap).r + texture(mapa_teia, bp).r) * 0.5;
		if (inf + (b - 0.5) * 0.3 > 0.12) { cor = mix(cor, vec3(0.09, 0.08, 0.07), 0.55 + 0.25 * inf); }
		float tufos = texture(detalhe, grade * 0.08 + vec2(0.13, 0.57)).r + inf * 0.3;              // teia em tufos
		float fio = max(texture(tex_teia, grade * 0.21).a, texture(tex_teia, grade * 0.09 + vec2(0.31, 0.77)).a * step(0.6, inf));
		if (fio > 0.25 && tufos + (b - 0.5) * 0.15 > 0.62 && inf + (b - 0.5) * 0.4 > 0.3) { cor = mix(cor, vec3(0.56, 0.54, 0.50), 0.45 + 0.3 * inf); }
		// corrosão da cratera das larvas (G): a terra cinza-parda da cratera escorre para fora — perto, a cor da
		// cratera; no meio, terra queimada; na beira, pontilhado torto que se mistura ao chão; veias e poças de ácido
		float cl = (texture(mapa_teia, ap).g + texture(mapa_teia, bp).g) * 0.5;
		float mancha = texture(detalhe, grade * 0.21 + vec2(0.27, 0.61)).r;
		if (cl + (mancha - 0.5) * 0.35 + (b - 0.5) * 0.25 > 0.12) {
			vec3 queimada = vec3(0.15, 0.13, 0.10);
			vec3 da_cratera = vec3(0.27, 0.25, 0.20) * (0.9 + 0.2 * mancha);
			cor = (cl + (mancha - 0.5) * 0.25 + (b - 0.5) * 0.2 > 0.55) ? da_cratera : queimada;
			if (b > 0.8) { cor *= 0.88; }
			float veia = abs(texture(detalhe, grade * 0.07 + w2 * 0.45 + vec2(0.71, 0.29)).r - 0.5);
			if (veia < 0.018 && cl > 0.35 && mancha > 0.42) { cor = vec3(0.22, 0.30, 0.07); }
			float fundo_a = texture(detalhe, grade * 0.09 + vec2(0.41, 0.13)).r + cl * 0.08 + (b - 0.5) * 0.04;
			if (fundo_a > 0.77 && cl > 0.6) { cor = mix(vec3(0.24, 0.36, 0.05), vec3(0.38, 0.54, 0.10), step(0.81, fundo_a)); }
		}
		if (amb.b >= 0.5) {                                                                                 // brasa
			float br = (amb.b - 0.5) * 2.0 * (0.7 + 0.3 * sin(TIME * 7.0 + grade.x * 3.1));
			if (br + (b - 0.5) * 0.4 > 0.35) { cor = mix(vec3(0.55, 0.10, 0.02), vec3(1.0, 0.55, 0.12), step(0.7, br)); }
		}
	}
	// trilha dos bichos: terra batida no meio do capim (o mesmo mapa do 3D)
	float trl = texture(trilha_mapa, (grade - trilha_origem.xy) / max(trilha_origem.z, 1.0)).r;
	trl = smoothstep(0.2, 0.8, trl + (_hp(floor(grade * 8.0)) - 0.5) * 0.3);
	cor = mix(cor, vec3(0.21, 0.17, 0.12) * (0.85 + 0.3 * _hp(floor(grade * 8.0) + 3.0)), trl * 0.7);
	COLOR = vec4(cor * dados.b, 1.0);
}
