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
#include "res://render/shaders/clima.gdshaderinc"

varying float altura;
varying float queimando;
varying vec3 tom;

float _h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float _ruido(vec2 p) {                                   // ruído de valor suave (borda orgânica da infestação)
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h(i), _h(i + vec2(1, 0)), f.x), mix(_h(i + vec2(0, 1)), _h(i + vec2(1, 1)), f.x), f.y);
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
