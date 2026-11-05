// Grama em massa (uma MultiMesh = uma chamada de desenho): cada instância é um tufo de folhas finas. O vento é todo
// na GPU, na direção e força do vento do clima (vento_dir): onda que atravessa o campo + trancos + a rajada de verdade
// (faixa larga que passa, a mesma que a turbina sente) + tremor fino por folha; dobra mais na ponta.
// Cor: base escura (sombra do tufo) → ponta clara, variando por instância (COLOR do MultiMesh).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform vec3 cor_base : source_color = vec3(0.16, 0.24, 0.10);
uniform vec3 cor_ponta : source_color = vec3(0.47, 0.58, 0.28);
uniform float forca = 0.35;
uniform sampler2D mapa_fabrica : filter_nearest, hint_default_black;   // do chunk: R = piso, B = aplainado
uniform vec2 origem_mapa;
uniform sampler2D mapa_ambiente : filter_linear, hint_default_transparent;   // A = queimado, R = sujeira
uniform sampler2D mapa_teia : filter_linear, hint_default_black;           // R = infestação da toca: a teia abafa a grama
uniform float raio_vista = 38.0;
uniform float raio_detalhe = 1.0e6;   // camada de detalhe: some em degradê a partir daqui
uniform bool compensa = false;
const float raio_detalhe_ref = 16.0;  // = DesenhoChunk.RAIO_DETALHE         // camada esparsa: tufos de longe um pouco maiores (o campo não fica ralo)
global uniform vec3 alvo_camera;
// patch fauna, fase 5: trilha dos bichos (Ratos.passagem) e o capim aberto em volta de cada rato, 64×64 tiles em
// volta da câmera (4 pixels por tile): R = trilha (o chão também gasta), G = aberto agora em volta de um rato
global uniform sampler2D trilha_mapa : filter_linear, hint_default_black;
global uniform vec3 trilha_origem;     // x, y = canto (grade), z = lado (tiles)
#include "res://render/shaders/clima.gdshaderinc"

varying float altura;
varying float queimando;
varying vec3 tom;
varying float flor;                 // patch fauna, fase 2: tufo com flor (0/1)
varying vec3 cor_flor;
varying float abre;                 // 0 fechada (noite) .. 1 aberta (dia)

float _h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float _ruido(vec2 p) {                                   // ruído de valor suave (borda orgânica da infestação)
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h(i), _h(i + vec2(1, 0)), f.x), mix(_h(i + vec2(0, 1)), _h(i + vec2(1, 1)), f.x), f.y);
}

// Estação no capim: primavera verde-clara, verão normal, outono dourado, inverno pardo (troca no 1º quarto).
vec3 cor_estacao(float e) {
	vec3 c[4] = vec3[4](vec3(0.94, 1.08, 0.9), vec3(1.0), vec3(1.12, 0.98, 0.66), vec3(0.86, 0.84, 0.74));
	int i = int(floor(e)) % 4;
	return mix(c[(i + 3) % 4], c[i], smoothstep(0.0, 0.25, fract(e)));
}

// Quantas flores na estação: muitas na primavera, menos no verão, quase nada no outono, nenhuma no inverno.
float flores_estacao(float e) {
	float f[4] = float[4](1.0, 0.55, 0.12, 0.0);
	int i = int(floor(e)) % 4;
	return mix(f[(i + 3) % 4], f[i], smoothstep(0.0, 0.25, fract(e)));
}

void vertex() {
	altura = UV.y;                                        // 0 = pé, 1 = ponta
	tom = COLOR.rgb;
	// tufo some (encolhe) sob construção/piso de fábrica — acompanha o piso crescendo — e longe do ponto olhado
	vec3 o = MODEL_MATRIX[3].xyz;
	ivec2 px = clamp(ivec2(floor(vec2(o.x, -o.z) - origem_mapa)), ivec2(0), ivec2(33));
	vec3 fb = texelFetch(mapa_fabrica, px, 0).rgb;
	vec4 amb = texelFetch(mapa_ambiente, px, 0);                      // o tile do próprio tufo (exato)
	float some = smoothstep(0.12, 0.35, max(fb.r, fb.b));
	// queima: só o tufo do tile que queima — escurece e encolhe enquanto o fogo come, some quando acaba
	float q = amb.a;
	queimando = smoothstep(0.51, 0.7, amb.b) * (1.0 - smoothstep(0.6, 0.9, q));   // B ≥ 0,5 = brasa (abaixo é água suja)
	some = max(some, smoothstep(0.1, 0.7, q));
	tom *= mix(vec3(1.0), vec3(0.18, 0.12, 0.08), smoothstep(0.0, 0.25, q));
	tom *= mix(vec3(1.0), vec3(0.72, 0.62, 0.42), smoothstep(0.1, 0.6, amb.r));   // suja: amarelada
	// infestação: amostra suave e torta (não o tile): a borda vira mancha orgânica, sem quadrados; cada tufo tem o
	// seu limiar, então a beira fica rala aos poucos
	vec2 g = vec2(o.x, -o.z);
	vec2 torto = vec2(_ruido(g * 0.13), _ruido(g * 0.13 + vec2(17.3, 5.1))) - 0.5;
	vec2 inf_rg = texture(mapa_teia, (g + torto * 3.0 - origem_mapa) / 34.0).rg;
	float sorte = _h(g * 3.17) * 0.25 - 0.12;
	float inf = inf_rg.r;
	float cor_l = inf_rg.g;
	tom *= mix(vec3(1.0), vec3(0.55, 0.52, 0.46), smoothstep(0.05, 0.4, inf));     // tomada pela teia: murcha
	tom *= mix(vec3(1.0), vec3(0.55, 0.47, 0.30), smoothstep(0.0, 0.35, cor_l + sorte));   // o ácido seca a grama
	some = max(some, smoothstep(0.35, 0.8, inf + sorte));
	some = max(some, smoothstep(0.15, 0.5, cor_l + sorte));                              // e come os tufos
	// estação e viço (fase 2 do patch fauna): a chuva deixa o campo mais verde e alto por uns dias; a seca amarela e
	// baixa (Clima.vico)
	tom *= cor_estacao(estacao_atual);
	float vv = vico_grama;
	tom *= mix(vec3(1.0), vec3(0.84, 1.2, 0.78), max(vv, 0.0));
	tom *= mix(vec3(1.0), vec3(1.6, 1.2, 0.45), max(-vv, 0.0));        // seca: palha
	VERTEX.y *= 1.0 + 0.18 * max(vv, 0.0) - 0.22 * max(-vv, 0.0);
	// trilha: onde os bichos passam muito o capim fica baixo e amassado, mais pálido, e deita para um lado; em volta
	// do rato que passa, o capim se abre (o bicho empurra) e ele aparece
	vec2 trg = textureLod(trilha_mapa, (g + torto * 0.25 - trilha_origem.xy) / max(trilha_origem.z, 1.0), 0.0).rg;
	float trilha = smoothstep(0.1, 0.75, trg.r + sorte * 0.25);
	float tr = max(trilha, smoothstep(0.05, 0.6, trg.g));
	VERTEX.y *= 1.0 - 0.85 * tr;
	some = max(some, smoothstep(0.6, 1.0, trilha + sorte * 0.6) * 0.7);    // na trilha batida alguns tufos somem
	VERTEX.xz += normalize(vec2(_h(g * 5.1) - 0.5, _h(g * 6.3) - 0.5) + vec2(1e-4)) * UV.y * 0.06 * tr;
	tom *= mix(vec3(1.0), vec3(1.15, 1.05, 0.75), tr);
	// flores: alguns tufos de capim saudável florescem pela estação; cada um com a sua cor; abrem de dia
	float viva = (1.0 - smoothstep(0.1, 0.3, q)) * (1.0 - smoothstep(0.1, 0.4, amb.r)) * (1.0 - smoothstep(0.05, 0.3, inf + cor_l));
	flor = step(_h(g * 1.91 + vec2(3.7, 1.3)), 0.075 * flores_estacao(estacao_atual) * viva * (0.8 + 0.4 * max(vv, 0.0)));
	float k = _h(g * 4.3 + vec2(0.7, 9.1));
	cor_flor = k < 0.35 ? vec3(0.92, 0.9, 0.78) : (k < 0.6 ? vec3(0.95, 0.76, 0.16) : (k < 0.82 ? vec3(0.52, 0.42, 0.84) : vec3(0.86, 0.34, 0.42)));
	abre = smoothstep(-0.05, 0.3, sol_dir.y);
	// só 2 das 5 folhas do tufo têm flor (pelo ângulo da folha, igual no pé e na ponta)
	float setor = fract(atan(VERTEX.z, VERTEX.x) / 6.2832 * 5.0 + _h(g * 2.7) * 5.0);
	flor *= step(setor, 0.4);
	if (flor > 0.5 && altura > 0.95) {
		// a ponta abre num miolo pequeno (~1,5 cm aberta, meio fechada)
		vec2 radial = normalize(VERTEX.xz + vec2(1e-4));
		vec2 lado = vec2(-radial.y, radial.x);
		float pet = 0.007 + 0.011 * abre;
		VERTEX.xz += lado * UV.x * pet + radial * pet;
		VERTEX.y += pet;
	}
	float dist = distance(o.xz, alvo_camera.xz);
	some = max(some, smoothstep(raio_vista - 6.0, raio_vista, dist));
	some = max(some, smoothstep(raio_detalhe - 6.0, raio_detalhe, dist));
	some = max(some, 1.0 - visao_dentro(o));                 // fora do oval de visão a grama some em degradê
	if (compensa) {
		VERTEX *= 1.0 + 0.45 * smoothstep(raio_detalhe_ref - 6.0, raio_detalhe_ref, dist);
	}
	some = max(some, visao_recursos);                       // visão de recursos/vento: o chão fica limpo para ler
	VERTEX *= 1.0 - some;
	if (some < 0.999 && altura > 0.01) {                    // o pé e o tufo sumido não precisam da conta (são milhões de vértices)
		vec3 mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 d = vento_mundo();
		float intensidade = vento_intensidade();                // 0 calmaria .. 1 ventania
		float forte = vento_forte();
		float sorte = fract(o.x * 3.17 + o.z * 5.23);
		float fase = dot(mundo.xz, d) * 0.35 - vento_tempo * 1.5;
		// ondas que passam pelo campo; respiração lenta por cima. Vento forte deita o campo (média alta) e os trancos e a
		// rajada do clima dobram mais, voltando devagar: força é amplitude e inclinação, não ritmo (vento_tempo quase não acelera).
		float onda = pow(0.5 + 0.5 * sin(fase), 3.0) * (0.75 + 0.25 * sin(vento_tempo * 0.37 + mundo.x * 0.05));
		float tremor = sin(vento_tempo * 6.0 + mundo.x * 3.1 + mundo.z * 2.3) * (0.05 + 0.05 * intensidade);
		float tranco = vento_tranco_leve(o.xz, d, sorte);
		float curva = altura * altura;
		float deita = 0.04 + 0.1 * intensidade + 0.2 * forte + (0.12 * intensidade + 0.32 * forte) * tranco + rajada_em(mundo) * 0.5;
		vec2 empurra = (d * (onda * forca * (0.4 + 0.7 * intensidade) + deita) + vec2(tremor, -tremor) * 0.5) * curva;
		// no máximo deitada, nunca esticada: a ponta desce o que anda para o lado (mundo.y − o.y = altura deste ponto)
		float alto = max(mundo.y - o.y, 0.01);
		float anda = length(empurra);
		if (anda > alto * 0.85) {
			empurra *= alto * 0.85 / anda;
			anda = alto * 0.85;
		}
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(empurra.x, -anda * anda / (2.0 * alto), empurra.y);
	}
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
}

void fragment() {
	vec3 c = mix(cor_base, cor_ponta, smoothstep(0.0, 1.0, altura)) * tom;
	if (flor > 0.5 && altura > 0.74 - 0.06 * abre) {
		// botão fechado à noite (verde e escuro com a cor por dentro); aberto de dia
		c = mix(mix(cor_flor * 0.45, vec3(0.22, 0.3, 0.12), 0.55), cor_flor, abre);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.32, 0.12) * altura;          // luz atravessando a folha
	if (queimando > 0.0) {
		// a frente de fogo sobe pela folha: ponta em brasa, meio laranja, pé ainda escuro
		// cada tufo pega fogo no seu tempo (não acende o tile inteiro de uma vez); a chama sobe pela folha e treme
		float sorte = fract(tom.r * 37.1 + tom.g * 13.7);
		float aceso = smoothstep(sorte * 0.7, sorte * 0.7 + 0.15, queimando);
		float fl = 0.55 + 0.45 * sin(TIME * 14.0 + sorte * 40.0 + altura * 7.0);
		float chama = smoothstep(0.35, 0.95, altura) * aceso * fl;
		vec3 c2 = mix(vec3(0.65, 0.07, 0.01), vec3(1.0, 0.36, 0.04), smoothstep(0.55, 1.0, altura));
		EMISSION = c2 * chama * 1.3;
		ALBEDO *= 1.0 - 0.85 * aceso;
	}
}
