// Clima (parâmetros globais, escritos por Clima/DesenhoClima): sombra das nuvens correndo com o vento e chão molhado.
global uniform sampler2D nuvem_ruido : filter_linear_mipmap, repeat_enable;
global uniform sampler2D nuvem_mapa : filter_linear_mipmap, repeat_enable;   // R = nuvens, G = rasgos
global uniform float nuvem_cobertura;
global uniform vec2 nuvem_deslocamento;
global uniform float molhado;
global uniform float pocas;           // 0..1: quanto as baixadas já encheram de água da chuva
global uniform float chuva_agora;     // 0..1: força da chuva neste instante (anéis das gotas na água)
global uniform float visao_recursos;  // 0..1: visão de recursos ligada (mapa apagado, jazidas em destaque)
global uniform vec3 sol_dir;          // direção PARA o sol (mundo, normalizada)
const float ALTURA_NUVENS = 90.0;      // camada bem acima do chão

// 0 = sol direto, 1 = nenhuma luz direta. A nuvem é uma camada alta com espessura variável: onde é grossa a luz não
// passa; nas partes finas passa só uma parte (transmissão cai com a espessura); nos rasgos o sol entra direto.
// O ponto é levado até a camada na direção do sol: a sombra cai inclinada como a luz, e os raios de sol
// (raios_sol.gdshader) descem exatamente sobre as manchas claras.
float sombra_nuvem(vec3 p) {
	if (nuvem_cobertura <= 0.01) { return 0.0; }
	vec2 nuvem = p.xz + sol_dir.xz / max(sol_dir.y, 0.2) * (ALTURA_NUVENS - p.y);
	vec2 q = (nuvem - nuvem_deslocamento) * 0.005;          // o mapa repete a cada 200 m
	vec2 m = texture(nuvem_mapa, q).rg;
	float n = m.r + (texture(nuvem_ruido, q * 9.0).r - 0.5) * 0.1;    // franja e fiapos
	// espessura: 0 fora da nuvem, sobe da borda para o miolo; cobertura alta engrossa tudo
	float esp = clamp((n - (1.0 - nuvem_cobertura)) / 0.3, 0.0, 1.0) + max(nuvem_cobertura - 0.75, 0.0) * 2.0;
	float transmite = exp(-3.2 * esp);
	// rasgos: passagem direta (céu quase fechado; some na chuva forte)
	float rasgo = m.g * smoothstep(0.6, 0.72, nuvem_cobertura) * (1.0 - smoothstep(0.86, 0.94, nuvem_cobertura));
	return 1.0 - mix(transmite, 1.0, rasgo);
}

// Visão de recursos: tira a cor e escurece (o que importa — jazidas e nomes — fica por cima).
vec3 apagar_visao(vec3 c, float quanto) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(l * 0.6 + 0.04), visao_recursos * quanto);
}


float _hash_gota(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Anéis das gotas batendo na água (poça, rio, lago): em cada célula de ~30 cm uma gota cai em hora sorteada e o
// anel abre e some. Duas grades defasadas para não parecer padrão. Devolve o brilho do anel (0..1).
float aneis_chuva(vec2 p, float t) {
	float s = 0.0;
	for (int k = 0; k < 2; k++) {
		vec2 q = p * 3.3 + float(k) * vec2(0.5, 0.37);
		vec2 cel = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = _hash_gota(cel + float(k) * 17.0);
		float fase = fract(t * (1.1 + 0.5 * h) + h * 7.0);
		vec2 o = vec2(_hash_gota(cel + 3.1), _hash_gota(cel + 9.7)) - 0.5;
		float r = length(f - o * 0.45);
		float anel = 1.0 - smoothstep(0.0, 0.035, abs(r - fase * 0.4));
		s = max(s, anel * (1.0 - fase) * step(0.6, h));
	}
	return s;
}

// Vento (grade: +x leste, +y norte; mundo = (x, −z)). vento_dir = direção × (0,4 + força). rajada = frente da onda
// ao longo do vento (m), amplitude, largura (m): uma faixa de vento mais forte que atravessa o mapa.
global uniform vec2 vento_dir;
global uniform vec3 rajada;
global uniform float vento_tempo;     // relógio do vento (Clima.ritmo_vento): sobe só um pouco de ritmo com a força e nunca salta
float rajada_em(vec3 mundo) {
	vec2 d = length(vento_dir) > 0.01 ? normalize(vento_dir) : vec2(1.0, 0.0);
	float x = dot(vec2(mundo.x, -mundo.z), d) - rajada.x;
	return rajada.y * exp(-x * x / (rajada.z * rajada.z));
}
// direção do vento no mundo (x, z), unitária
vec2 vento_mundo() {
	vec2 d = length(vento_dir) > 0.01 ? normalize(vento_dir) : vec2(1.0, 0.0);
	return vec2(d.x, -d.y);
}

// Força do vento agora, 0 calmaria .. 1 ventania, e a parte "forte" dela: 0 no vento de um dia limpo, 1 na tempestade.
// O que distingue vento forte é ISTO multiplicando amplitude e inclinação, não a velocidade da animação: frequência
// multiplicada por força faz a planta parecer um vídeo acelerado (e dá salto de fase quando a força muda).
float vento_intensidade() { return clamp(length(vento_dir) - 0.4, 0.0, 1.0); }
float vento_forte() { return smoothstep(0.35, 1.0, vento_intensidade()); }

// Uma rajada irregular por vez: frentes que andam a favor do vento (vizinhos pegam quase juntos, `sorte` atrasa cada
// planta), com subida rápida e volta lenta; cada frente tem a sua força e parte delas nem vem.
float _vento_frente(float c) {
	float id = floor(c);
	float f = c - id;
	float g = fract(sin(id * 12.9898 + 4.1) * 43758.5453);
	return smoothstep(0.0, 0.09, f) * (1.0 - f) * (1.0 - f) * mix(0.35, 1.0, g) * smoothstep(0.12, 0.3, g) * 1.3;
}
// Tranco de uma camada só (grama: milhões de vértices). p em (x, z) do mundo, d = vento_mundo(). 0..1
float vento_tranco_leve(vec2 p, vec2 d, float sorte) {
	float lado = dot(p, vec2(-d.y, d.x));
	return _vento_frente(vento_tempo * 0.14 - dot(p, d) * 0.03 + sin(lado * 0.06) * 0.2 + sorte * 0.1);
}
// Duas camadas sem múltiplo comum entre si: o ritmo das rajadas não se repete (árvores e arbustos). 0..1
float vento_tranco(vec2 p, vec2 d, float sorte) {
	float lado = dot(p, vec2(-d.y, d.x));
	float a = vento_tranco_leve(p, d, sorte);
	float b = _vento_frente(vento_tempo * 0.083 - dot(p, d) * 0.018 + sin(lado * 0.04 + 1.3) * 0.25 + sorte * 0.22 + 0.37);
	return 1.0 - (1.0 - clamp(a, 0.0, 1.0)) * (1.0 - clamp(b, 0.0, 1.0));
}

// Estação para a folhagem: índice (0 primavera, 1 verão, 2 outono, 3 inverno) + fração já passada dela.
global uniform float estacao_atual;
global uniform float vico_grama;      // patch fauna, fase 2: −1 capim seco … 0 normal … +1 viçoso depois da chuva

// Oval de visão (ambiente/visao.gd): dentro desenha normal; borda em degradê; fora, névoa escura — quase preta onde
// nunca foi visto, escurecida e sem cor onde já foi descoberto (visao_mapa, 1 pixel = 2×2 tiles).
global uniform vec4 visao_oval;          // centro (grade), eixo horizontal da tela (grade)
global uniform vec2 visao_raios;
global uniform sampler2D visao_mapa : filter_linear, hint_default_black;
global uniform vec3 visao_mapa_origem;   // origem (grade, tiles), lado (tiles)
const vec3 COR_NEVOA = vec3(0.012, 0.014, 0.02);
float visao_dentro(vec3 p_mundo) {
	vec2 d = vec2(p_mundo.x, -p_mundo.z) - visao_oval.xy;
	vec2 ex = visao_oval.zw;
	float e = length(vec2(dot(d, ex) / visao_raios.x, dot(d, vec2(-ex.y, ex.x)) / visao_raios.y));
	return 1.0 - smoothstep(0.78, 1.05, e);
}
float visao_descoberto(vec3 p_mundo) {
	vec2 uv = (vec2(p_mundo.x, -p_mundo.z) - visao_mapa_origem.xy) / visao_mapa_origem.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(visao_mapa, uv).r;
}
vec3 aplicar_visao(vec3 cor_in, vec3 p_mundo) {
	float dentro = visao_dentro(p_mundo);
	if (dentro >= 0.999) {
		return cor_in;
	}
	float desc = visao_descoberto(p_mundo);
	float cinza = dot(cor_in, vec3(0.3, 0.5, 0.2));
	vec3 lembrada = mix(vec3(cinza), cor_in, 0.35) * 0.32;          // já visto: escuro e quase sem cor
	vec3 fora = mix(COR_NEVOA, lembrada, desc);
	return mix(fora, cor_in, dentro);
}
