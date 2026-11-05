shader_type canvas_item;
// Copa das árvores do 2D pela estação, como a do 3D (render/shaders/material_pf.gdshaderinc, folhagem()): o pixel de
// folha (verde mais forte que o vermelho, não o contorno) amarela/avermelha pelo perfil e a copa vai abrindo, em
// tufos de 2×2, até sobrar uma névoa de galho. O contorno preto em volta da copa some junto (senão fica o fantasma).
// Na sombra (`sombra`), só fica mais rala. Perfil: 1 carvalho, 2 salgueiro, 3 acácia, 4 bétula (Ecossistema.PERFIS).

global uniform float estacao_atual;
uniform int perfil = 1;
uniform bool sombra = false;

varying vec2 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;     // o pé da árvore no mundo (px): cada uma no seu tempo
}

float _h(vec2 p, float k) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + k * 74.7) * 43758.5453);
}

// O mesmo de material_pf: x = seca (cor), y = queda (abre a copa), z = broto (verde novo).
vec3 folhagem(int pf, float e, float sorte, vec2 p) {
	int est = int(floor(mod(e, 4.0)));
	float f = clamp(fract(e) - sorte * 0.2 + 0.1 + (p.x * 0.00003 + p.y * 0.00002), 0.0, 1.0);
	vec3 r = vec3(0.0);
	if (pf == 1 || pf == 4) {
		if (est == 2) { r.x = smoothstep(0.05, 0.55, f); r.y = smoothstep(0.6, 0.98, f); }
		else if (est == 3) { r.x = 1.0; r.y = 1.0; }
		else if (est == 0) { r.y = 1.0 - smoothstep(0.02, 0.3, f); r.z = 1.0 - smoothstep(0.25, 0.6, f); }
	} else if (pf == 2) {
		if (est == 2) { r.x = 0.3 * smoothstep(0.5, 1.0, f); }
		else if (est == 3) { r.x = 0.3 + 0.35 * smoothstep(0.0, 0.3, f); r.y = 0.3 * smoothstep(0.0, 0.3, f); }
		else if (est == 0) { r.x = 0.65 * (1.0 - smoothstep(0.0, 0.25, f)); r.y = 0.3 * (1.0 - smoothstep(0.0, 0.25, f)); }
	} else if (pf == 3) {
		if (est == 1) { r.x = 0.7 * smoothstep(0.1, 0.5, f); r.y = 0.5 * smoothstep(0.2, 0.6, f); }
		else if (est == 2) { r.x = 0.7 * (1.0 - smoothstep(0.0, 0.3, f)); r.y = 0.5 * (1.0 - smoothstep(0.0, 0.3, f)); }
	}
	return r;
}

// Cor da folha seca (sRGB), a mesma família da folha caída (DesenhoPlantasReagem.CORES_FOLHA).
vec3 pf_seca(int pf, float sorte) {
	if (pf == 1) {
		return mix(vec3(0.62, 0.40, 0.11), vec3(0.55, 0.21, 0.08), sorte);
	}
	if (pf == 4) {
		return vec3(0.60, 0.49, 0.15);
	}
	if (pf == 2) {
		return vec3(0.60, 0.57, 0.28);
	}
	return vec3(0.58, 0.50, 0.26);
}

float folha_em(sampler2D tex, vec2 uv) {
	vec4 t = texture(tex, uv);
	if (t.a < 0.04) {
		return 0.0;
	}
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	return smoothstep(-0.005, 0.03, t.g - t.r) * smoothstep(0.06, 0.1, lum);
}

void fragment() {
	float sorte = _h(floor(v_pos), 3.0);
	vec3 fo = folhagem(perfil, estacao_atual, sorte, v_pos);
	if (sombra) {
		COLOR.a *= 1.0 - 0.6 * fo.y;
	} else if (fo.x + fo.y + fo.z > 0.001) {
		vec4 t = texture(TEXTURE, UV);
		vec2 tx = floor(UV / TEXTURE_PIXEL_SIZE);
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		float folha = folha_em(TEXTURE, UV);
		float borda = 0.0;
		if (folha < 0.5 && lum < 0.12 && fo.y > 0.0) {
			float viz = 0.0;
			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					viz = max(viz, folha_em(TEXTURE, UV + vec2(float(i), float(j)) * TEXTURE_PIXEL_SIZE));
				}
			}
			borda = step(0.5, viz);
		}
		if (folha > 0.0 || borda > 0.0) {
			vec3 c = COLOR.rgb;
			float k = clamp(lum / 0.34, 0.3, 1.15);
			if (folha > 0.0) {
				vec3 seca = pf_seca(perfil, sorte);
				c = mix(c, c * 1.2 + vec3(0.03, 0.06, 0.0), fo.z * folha);
				float v = fo.x * folha * clamp(fo.x * 1.6 - _h(floor(tx / 3.0), 9.0) * 0.6, 0.0, 1.0);
				c = mix(c, seca * k, v);
			}
			if (_h(floor(tx / 2.0), 0.0) < fo.y * max(folha, borda)) {
				if (_h(tx, 5.0) < 0.32 && fo.y > 0.6 && borda < 0.5) {
					c = vec3(0.3, 0.25, 0.21) * k + vec3(0.04, 0.03, 0.03);   // névoa de galho fino
				} else {
					discard;
				}
			}
			COLOR.rgb = c;
		}
	}
}
