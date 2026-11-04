// Chão por chunk: cada tile escolhe uma camada do Texture2DArray (bioma, jazida, praia, água).
// Texturas em loop (geradas sem emenda) repetem a cada 4 m; ruído de detalhe quebra a repetição.
// Bordas orgânicas: em terra, a camada é lida do mapa 34×34 do chunk numa posição deformada por ruído, e duas
// leituras com deformações diferentes se misturam — a troca de bioma vira uma faixa irregular e suave, não degrau.
// Água: camadas ≥ 'primeira_agua' ondulam e brilham; rio corre na direção da correnteza (COLOR.gb).
// Margens naturais: a grade 1×1 é só das construções — água × terra é decidido por pixel num campo suave
// (interpolação entre os centros dos tiles + ruído), então lagos e rios têm borda arredondada e irregular, com uma
// faixa de terra molhada na beira; raso × fundo também passa suave.
shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform sampler2DArray texturas : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detalhe : filter_linear_mipmap, repeat_enable;
uniform sampler2D mapa_camadas : filter_nearest;
uniform vec2 origem_mapa;          // tile (grade) do pixel (0, 0) do mapa de camadas
uniform sampler2D mapa_ambiente : filter_linear, hint_default_transparent;   // R sujeira, G óleo, B água suja (0..0,45) ou brasa (0,5..1), A queimado
uniform sampler2D mapa_teia : filter_linear, hint_default_black;   // R = infestação da toca das aranhas (Infestacao)
uniform sampler2D tex_teia : filter_linear_mipmap, repeat_enable, hint_default_transparent;   // fios de seda (alfa)
uniform sampler2D mapa_fabrica : filter_nearest, hint_default_transparent;   // R piso, G nível alvo, B aplainar, A água de jogo (buraco cheio)
uniform float camada_piso = 9.0;
uniform float camada_jazida = 7.0;  // zona de minério nunca vira piso
uniform float primeira_agua = 8.0;
uniform float escala = 0.25;
uniform float camada_rocha = 3.0;
global uniform vec3 piso_crescer;   // (x, y da grade, raio): piso de fábrica só até esse raio (abertura); 1e6 = livre
// vento_dir (grade: direção × força do vento — o fogo corre nessa direção) vem de clima.gdshaderinc
global uniform vec4 grade_construcao;   // (centro na grade, raio, força 0..1): grade no chão no modo construção
uniform float alt_nivel = 1.0;      // metros por nível de relevo   // barranco (encosta íngreme) mostra pedra
#include "res://render/shaders/clima.gdshaderinc"

varying vec3 fluxo;                // xy = direção da correnteza (grade), z = 1 se rio
varying vec3 mundo;
varying vec3 normal_mundo;
varying float oclusao;            // pé de barranco (UV.x da malha)
varying float baixa;              // baixada (UV.y da malha): onde a chuva junta poça; aplainado = 0
varying vec2 mar_v;               // (fração de mar, fração de fundo) do campo contínuo (UV2)
varying float agua_jogo;          // buraco/canal escavado que encheu (AguaJogo), interpolado entre tiles

// Construção molda o chão: onde o mapa da fábrica tem piso, o vértice vai para o nível da construção (R = força,
// G = nível + 8), aplainando ondulação e encosta — some quando a construção sai.
float aplainar(vec2 grade, out float alvo, out float cheio) {
	vec2 p = grade - origem_mapa - 0.5;
	ivec2 i0 = ivec2(floor(p));
	vec2 f = fract(p);
	float melhor = 0.0;
	alvo = 0.0;
	cheio = 0.0;
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k % 2, k / 2);
		vec4 tx = texelFetch(mapa_fabrica, clamp(i0 + o, ivec2(0), ivec2(33)), 0);
		float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		s += tx.b * w;                                   // B = aplainar (construção ou Terraplenagem)
		cheio += tx.a * w;
		if (tx.b > melhor) { melhor = tx.b; alvo = (floor(tx.g * 255.0 + 0.5) - 8.0) * alt_nivel; }
	}
	return s;
}

void vertex() {
	fluxo = vec3(COLOR.g * 2.0 - 1.0, COLOR.b * 2.0 - 1.0, COLOR.a);
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = NORMAL;
	float alvo;
	float cheio;
	float plano = smoothstep(0.0, 0.75, aplainar(vec2(mundo.x, -mundo.z), alvo, cheio));
	agua_jogo = cheio;
	oclusao = UV.x * (1.0 - plano);
	baixa = UV.y * (1.0 - plano);
	if (plano > 0.0) {
		VERTEX.y = mix(VERTEX.y, alvo, plano);
		n = normalize(mix(n, vec3(0.0, 1.0, 0.0), plano));
		NORMAL = n;
		mundo.y = VERTEX.y;
	}
	normal_mundo = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	mar_v = UV2;
	// onda só onde há água (COLOR.r = fração de água no vértice; cantos compartilhados mexem igual)
	// buraco cheio: a superfície fica 0,12 m abaixo do nível, como a água natural
	VERTEX.y -= 0.12 * agua_jogo;
	VERTEX.y += sin(TIME * 0.9 + mundo.x * 0.7 + mundo.z * 0.5) * 0.02 * max(COLOR.r, agua_jogo);
}

float fabrica_em(vec2 grade) {
	ivec2 px = clamp(ivec2(floor(grade - origem_mapa)), ivec2(0), ivec2(33));
	return texelFetch(mapa_fabrica, px, 0).r;
}

float camada_em(vec2 grade) {
	ivec2 px = clamp(ivec2(floor(grade - origem_mapa)), ivec2(0), ivec2(33));
	return floor(texelFetch(mapa_camadas, px, 0).r * 255.0 + 0.5);
}

// Camada de terra mais perto (para a parte seca de um tile de água); sem nenhuma, praia.
float terra_perto(vec2 g) {
	for (int k = 0; k < 8; k++) {
		vec2 o = vec2(float(k % 3) - 1.0, float(k / 3) - 1.0);
		if (k == 4) { o = vec2(1.0, 1.0); }
		float c = camada_em(g + o);
		if (c < primeira_agua) { return c; }
	}
	return primeira_agua - 1.0;
}

// Ambiente (sujeira, óleo, água suja, queimado) num ponto: leitura LINEAR do mapa do chunk (centros de tile) com o
// ponto deformado por ruído e uma segunda leitura mais deformada — mancha orgânica, nunca quadrado de tile.
vec4 ambiente_em(vec2 grade, vec2 w1, vec2 w2) {
	vec2 a = (grade + w1 * 1.6 - origem_mapa) / 34.0;
	vec2 b = (grade + w2 * 2.4 + vec2(w1.y, -w1.x) * 0.8 - origem_mapa) / 34.0;
	return (texture(mapa_ambiente, a) + texture(mapa_ambiente, b)) * 0.5;
}

void fragment() {
	float brasa = 0.0;
	vec2 grade = vec2(mundo.x, -mundo.z);
	float camada = camada_em(grade);
	vec2 uv = mundo.xz * escala;
	float d = texture(detalhe, mundo.xz * 0.031).r;
	vec2 w1 = vec2(texture(detalhe, grade * 0.06).r, texture(detalhe, grade * 0.06 + vec2(0.37, 0.71)).r) - 0.5;
	vec2 w2 = vec2(texture(detalhe, grade * 0.17 + vec2(0.53, 0.19)).r, texture(detalhe, grade * 0.17 + vec2(0.11, 0.83)).r) - 0.5;
	// quanto deste pixel é água (borda suave, antisserrilhada)
	// toda água (mar, rio, lago) vem do campo contínuo da malha — o mundo não é feito de tiles
	float wf = max(mar_v.x, agua_jogo) + (d - 0.5) * 0.12;
	float aa = max(fwidth(wf), 0.02);
	float agua = smoothstep(0.5 - aa, 0.5 + aa, wf);
	float beira = smoothstep(0.12, 0.5, wf) * (1.0 - agua);        // terra molhada na margem
	vec3 c_terra = vec3(0.0);
	float junta = 0.0;
	float a = camada;
	if (agua < 1.0) {
		// bioma/jazida/praia: mistura suave das 4 camadas em volta de um ponto deformado por ruído (sem franja de
		// tile); o peso afina perto do centro de cada tile e a troca vira degradê orgânico. Água vira a terra vizinha.
		float base = camada >= primeira_agua ? terra_perto(grade) : camada;
		vec2 pw = grade + w1 * 2.2 + w2 * 0.7 - 0.5;
		vec2 i0 = floor(pw);
		vec2 fr = fract(pw);
		fr = smoothstep(0.15, 0.85, fr);
		float soma = 0.0;
		float melhor = -1.0;
		for (int k = 0; k < 4; k++) {
			vec2 o = vec2(float(k % 2), float(k / 2));
			float lk = camada_em(i0 + o + 0.5);
			if (lk >= primeira_agua) { lk = base; }
			float wk = (o.x > 0.5 ? fr.x : 1.0 - fr.x) * (o.y > 0.5 ? fr.y : 1.0 - fr.y);
			if (wk > 0.001) {
				c_terra += texture(texturas, vec3(uv, lk)).rgb * wk;
				soma += wk;
			}
			if (wk > melhor) { melhor = wk; a = lk; }
		}
		c_terra /= max(soma, 1e-4);
		// piso de fábrica: o mapa já vem espalhado 2 tiles em volta das construções (forte perto, fraco longe);
		// 4 leituras deformadas dão a borda irregular e suave. Jazida nunca vira piso.
		float f = fabrica_em(grade + w1 * 1.3) + fabrica_em(grade + w2 * 1.0)
				+ fabrica_em(grade + vec2(w2.y, -w1.x) * 1.4) + fabrica_em(grade);
		f = smoothstep(0.18, 0.55, f * 0.25);
		if (camada == camada_jazida || a == camada_jazida) { f = 0.0; }   // recurso fica à vista
		if (piso_crescer.z < 1.0e5) {
			// cresce do centro com borda irregular (o mesmo ruído das bordas)
			float r = piso_crescer.z * (0.85 + 0.3 * d) + w1.x * 1.2;
			f *= smoothstep(r, r - 1.2, distance(grade, piso_crescer.xy));
		}
		if (f > 0.0) {
			vec3 piso = texture(texturas, vec3(grade * vec2(0.25, -0.25), camada_piso)).rgb;
			c_terra = mix(c_terra, piso, f);
			junta = f * (1.0 - smoothstep(0.025, 0.06, dot(piso, vec3(0.333))));   // vão entre blocos: água junta ali
		}
		c_terra *= 1.0 - 0.35 * beira;
	}
	vec3 c_agua = vec3(0.0);
	float onda = 0.0;
	float suja = 0.0;
	if (agua > 0.0) {
		vec2 corre = fluxo.z > 0.5 ? vec2(fluxo.x, -fluxo.y) * 0.35 : vec2(0.02, 0.013);
		vec2 uva = uv + corre * TIME;
		float fundo = smoothstep(0.2, 0.8, mar_v.y + (d - 0.5) * 0.2);
		c_agua = mix(texture(texturas, vec3(uva, primeira_agua)).rgb, texture(texturas, vec3(uva, primeira_agua + 1.0)).rgb, fundo);
		vec2 corre_onda = fluxo.z > 0.5 ? vec2(fluxo.x, -fluxo.y) * 0.12 : vec2(0.05, 0.0);
		onda = texture(detalhe, mundo.xz * 0.12 + corre_onda * TIME).r;
		c_agua *= 0.9 + 0.25 * onda;
		// cachoeira/corredeira: onde a superfície da água inclina, espuma branca correndo rio abaixo
		float queda = smoothstep(0.992, 0.90, normal_mundo.y);
		if (queda > 0.0) {
			vec2 desce = normalize(vec2(normal_mundo.x, normal_mundo.z) + vec2(1e-4));
			float estria = texture(detalhe, vec2(dot(mundo.xz, vec2(-desce.y, desce.x)) * 0.9, dot(mundo.xz, desce) * 0.25 - TIME * 1.6)).r;
			c_agua = mix(c_agua, vec3(0.86, 0.9, 0.92), queda * smoothstep(0.35, 0.75, estria) * 0.9);
		}
		// espuma rala bem na linha da margem
		c_agua = mix(c_agua, vec3(0.62, 0.66, 0.66), smoothstep(0.62, 0.5, wf) * 0.35 * smoothstep(0.4, 0.7, onda));
		// água contaminada: turva (marrom-esverdeada) com espuma suja em manchas
		vec4 amb_a = ambiente_em(grade, w1, w2);
		suja = smoothstep(0.009, 0.18, min(amb_a.b, 0.45));
		c_agua = mix(c_agua, vec3(0.20, 0.19, 0.11) * (0.8 + 0.4 * onda), suja * 0.85);
		c_agua = mix(c_agua, vec3(0.42, 0.40, 0.30), suja * smoothstep(0.62, 0.8, onda) * 0.6);
		// lixo boiando: pedacinhos claros e escuros levados pela correnteza (mesmo passo da textura da água)
		if (suja > 0.05) {
			float lx = texture(detalhe, mundo.xz * 0.9 + corre * 3.6 * TIME).r;
			float ly = texture(detalhe, mundo.xz * 1.7 + corre * 6.8 * TIME + vec2(0.31, 0.77)).r;
			c_agua = mix(c_agua, vec3(0.55, 0.50, 0.40), smoothstep(0.80, 0.84, lx) * suja);
			c_agua = mix(c_agua, vec3(0.08, 0.07, 0.05), smoothstep(0.82, 0.86, ly) * suja);
		}
	}
	// barranco: onde a encosta é íngreme aparece a pedra (com faixas horizontais de estrato)
	float ingreme = 1.0 - smoothstep(0.55, 0.85, normal_mundo.y);
	if (ingreme > 0.0) {
		vec3 rocha = texture(texturas, vec3(vec2(mundo.x + mundo.z, mundo.y * 2.0) * 0.3, camada_rocha)).rgb;
		rocha *= 0.78 + 0.22 * sin(mundo.y * 9.0 + d * 3.0);
		c_terra = mix(c_terra, rocha * 0.85, ingreme);
	}
	c_terra *= 1.0 - 0.45 * oclusao;
	// ambiente vivo: sujeira (terra escura e acinzentada), queimado (carvão com cinza), óleo (mancha preta brilhante)
	vec4 amb = ambiente_em(grade, w1, w2);
	float grao = texture(detalhe, mundo.xz * 0.21).r;
	float suj = smoothstep(0.02, 0.5, amb.r) * (0.65 + 0.7 * grao);
	c_terra = mix(c_terra, c_terra * vec3(0.55, 0.50, 0.46) + vec3(0.05, 0.045, 0.04), clamp(suj, 0.0, 0.9));
	float queim = smoothstep(0.05, 0.6, amb.a);
	vec3 carvao = mix(vec3(0.05, 0.045, 0.045), vec3(0.32, 0.30, 0.29), smoothstep(0.55, 0.85, grao));
	c_terra = mix(c_terra, carvao, queim * 0.92);
	float oleo = smoothstep(0.35, 0.55, amb.g + (grao - 0.5) * 0.35);
	vec3 arco = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + dot(mundo.xz, vec2(0.7, 0.4)) * 0.8 + TIME * 0.05));
	c_terra = mix(c_terra, vec3(0.03, 0.03, 0.035) + arco * 0.06, oleo);
	// brasa: onde queima agora o chão brilha laranja, tremendo (é a luz do fogo no Factorio: rente ao chão)
	// só onde o fogo é recente (B alto) e em pontos do grão: brasas, não um tapete
	// fogo no próprio chão (nada de sprite): línguas esticadas e correndo com o vento, cor pela temperatura
	// B é brasa em terra e água suja na água: perto da margem o filtro mistura os dois — fogo só em terra firme
	float terra_firme = 1.0 - smoothstep(0.04, 0.2, wf);
	float fogo_i = smoothstep(0.51, 0.75, amb.b) * terra_firme;
	if (fogo_i > 0.0) {
		vec2 vd = length(vento_dir) > 0.01 ? normalize(vento_dir) : vec2(1.0, 0.0);
		vec2 pp = vec2(dot(grade, vd), dot(grade, vec2(-vd.y, vd.x)));
		vec2 q1 = vec2(pp.x * 0.35 - TIME * 1.4, pp.y * 1.3);          // estica ao longo do vento
		float n = texture(detalhe, q1 * 0.5).r * 0.6 + texture(detalhe, q1 * 1.3 + vec2(-TIME * 0.9, 0.37)).r * 0.4;
		float lingua = smoothstep(0.42, 0.78, n + fogo_i * 0.45 - 0.22);
		float tremor = 0.8 + 0.2 * sin(TIME * 11.0 + n * 17.0);
		brasa = lingua * fogo_i * tremor;
		float brasa_fundo = smoothstep(0.5, 0.8, grao) * fogo_i * 0.5;  // pontos de brasa entre as línguas
		brasa = max(brasa, brasa_fundo);
	}
	c_terra = mix(c_terra, vec3(0.05, 0.035, 0.03), smoothstep(0.47, 0.62, amb.b) * 0.85 * terra_firme);   // queimando: chão escuro
	// infestação (toca das aranhas): terra escura e orgânica com a teia de fios por cima, fechando perto da toca
	float inf = (texture(mapa_teia, (grade + w1 * 1.4 - origem_mapa) / 34.0).r
			+ texture(mapa_teia, (grade + w2 * 2.0 - origem_mapa) / 34.0).r) * 0.5 * terra_firme;
	if (inf > 0.002) {
		float sujo_inf = smoothstep(0.0, 0.55, inf) * (0.7 + 0.5 * grao);
		c_terra = mix(c_terra, vec3(0.05, 0.043, 0.038) + c_terra * 0.2, clamp(sujo_inf, 0.0, 0.9));
		// teia em tufos (mancha de ruído), mais fechada perto da toca; entre os tufos, só a terra suja
		float tufos = smoothstep(0.5, 0.8, texture(detalhe, grade * 0.08 + vec2(0.13, 0.57)).r + inf * 0.25);
		float fio = texture(tex_teia, grade * 0.42).a * 0.8;
		float fio2 = texture(tex_teia, grade * 0.17 + vec2(0.31, 0.77)).a * smoothstep(0.55, 0.95, inf);
		float teia = max(fio, fio2) * smoothstep(0.25, 0.85, inf) * tufos;
		c_terra = mix(c_terra, vec3(0.50, 0.48, 0.45), clamp(teia, 0.0, 1.0) * 0.5);
	}
	// corrosão (cratera das larvas, canal G): a mesma terra cinza-parda da cratera escorre dela para fora — perto, é a
	// terra da cratera (cor da textura dela); no meio, terra queimada pelo ácido; na beira, mancha torta e manchada que
	// se mistura ao chão. Veias de ácido esverdeadas correm pela terra e juntam poças nas baixadas, perto da cratera.
	float cor_l = (texture(mapa_teia, (grade + w1 * 1.4 - origem_mapa) / 34.0).g
			+ texture(mapa_teia, (grade + w2 * 2.0 - origem_mapa) / 34.0).g) * 0.5 * terra_firme;
	float acido = 0.0;
	if (cor_l > 0.002) {
		float mancha = texture(detalhe, grade * 0.21 + vec2(0.27, 0.61)).r;
		float k = smoothstep(0.0, 0.45, cor_l + (mancha - 0.5) * 0.35);              // beira torta e manchada
		vec3 queimada = vec3(0.080, 0.070, 0.052) * (0.85 + 0.3 * grao);
		vec3 da_cratera = vec3(0.135, 0.118, 0.084) * (0.82 + 0.36 * grao) * (0.9 + 0.2 * mancha);
		vec3 terra_l = mix(queimada, da_cratera, smoothstep(0.35, 0.85, cor_l + (mancha - 0.5) * 0.25));
		c_terra = mix(c_terra, terra_l, k);
		// veias de ácido (linhas finas e tortas), mais densas perto da cratera
		float veia = 1.0 - smoothstep(0.0, 0.022, abs(texture(detalhe, grade * 0.07 + w2 * 0.45 + vec2(0.71, 0.29)).r - 0.5));
		veia *= smoothstep(0.3, 0.8, cor_l) * smoothstep(0.35, 0.6, mancha);
		c_terra = mix(c_terra, vec3(0.12, 0.17, 0.03), veia * 0.7);
		// poças de ácido nas baixadas, só perto da cratera
		float fundo_a = texture(detalhe, grade * 0.09 + vec2(0.41, 0.13)).r + baixa * 0.15 + cor_l * 0.08;
		acido = smoothstep(0.76, 0.80, fundo_a) * smoothstep(0.55, 0.9, cor_l);
		c_terra = mix(c_terra, vec3(0.20, 0.32, 0.03) * (0.8 + 0.3 * grao), acido * 0.85);
		acido = max(acido, veia * 0.3);
	}
	vec3 c = mix(c_terra, c_agua, agua);
	c *= 0.88 + 0.24 * d;
	float poca = 0.0;
	if (agua < 1.0 && (molhado > 0.0 || pocas > 0.0)) {
		// chão molhado escurece; a água da chuva junta nas baixadas do relevo de verdade (enche do mais fundo para
		// o raso e seca do raso para o fundo) e nos vãos entre os blocos do piso
		float fundo_p = baixa + (d - 0.5) * 0.22 + (w1.x * 0.12);
		float limiar = 1.0 - pocas * 0.78;
		poca = smoothstep(limiar, limiar + 0.05, fundo_p);
		poca = max(poca, smoothstep(0.25, 0.7, pocas) * junta);
		poca *= 1.0 - agua;
		c *= 1.0 - 0.30 * molhado * (1.0 - agua);
		c = mix(c, c * 0.45 + vec3(0.10, 0.12, 0.14), poca * 0.75);       // lâmina d'água: escura, puxa o céu
	}
	if (chuva_agora > 0.05) {
		float aneis = aneis_chuva(grade, TIME) * chuva_agora * max(poca, agua);
		c += vec3(0.22, 0.24, 0.27) * aneis;
	}
	c *= 1.0 - 0.6 * sombra_nuvem(mundo);
	if (visao_recursos > 0.0) {
		c = apagar_visao(c, (camada == camada_jazida && agua < 0.5) ? 0.0 : 0.85);
	}
	float vd = visao_dentro(mundo);
	ALBEDO = aplicar_visao(c, mundo);                // fora do oval de visão: névoa escura (ambiente/visao.gd)
	// modo construção: grade 1×1 no chão em volta do cursor (linhas finas, some em degradê)
	if (grade_construcao.w > 0.0) {
		vec2 f = fract(grade);
		vec2 aa = fwidth(grade) * 1.2;
		vec2 l = smoothstep(aa, vec2(0.0), min(f, 1.0 - f) - 0.006);
		float linha = max(l.x, l.y);
		float perto = 1.0 - smoothstep(grade_construcao.z * 0.55, grade_construcao.z, distance(grade, grade_construcao.xy));
		float g = linha * perto * grade_construcao.w;
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.86, 0.55), g * 0.28);      // traço de giz quente, discreto
		EMISSION += vec3(0.5, 0.4, 0.2) * g * 0.12;
	}
	vec3 fogo_cor = mix(vec3(0.55, 0.05, 0.01), vec3(1.0, 0.33, 0.04), smoothstep(0.25, 0.7, brasa));
	fogo_cor = mix(fogo_cor, vec3(1.0, 0.85, 0.45), smoothstep(0.7, 1.0, brasa));
	EMISSION += fogo_cor * brasa * 1.3 * (1.0 - agua) * vd;
	EMISSION += vec3(0.20, 0.32, 0.02) * acido * 0.35 * (0.85 + 0.15 * sin(TIME * 1.7 + grade.x)) * vd;   // ácido: brilho fraco
	float oleo_r = smoothstep(0.35, 0.55, ambiente_em(grade, w1, w2).g);
	ROUGHNESS = mix(mix(mix(mix(0.92, 0.55, molhado), 0.06, poca), 0.15, max(oleo_r, acido) * (1.0 - agua)), mix(0.08, 0.45, suja), agua);
	SPECULAR = mix(0.5 + 0.4 * poca, mix(0.8, 0.3, suja), agua) * mix(0.05, 1.0, vd);   // água suja é opaca: reflete menos o céu
}
