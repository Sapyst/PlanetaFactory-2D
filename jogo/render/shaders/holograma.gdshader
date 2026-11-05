shader_type spatial;
// Holograma vermelho da IA (drone nascendo na fabricadora, estudo_drones.py): só luz somada, linhas de varredura
// que sobem, borda acesa (fresnel) e tremulação. `corte` (altura no mundo) monta o drone de baixo para cima: acima
// dele nada; perto dele uma franja mais forte. `forca` 0..1 some com o holograma.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform vec4 cor : source_color = vec4(1.0, 0.06, 0.03, 1.0);
uniform float forca = 1.0;
uniform float corte = 1000.0;
uniform float linhas = 55.0;
uniform float faixa = -1000.0;     // obra sendo soldada (patch RTS): faixa clara que sobe na altura do mundo

varying vec3 pm;

void vertex() {
	pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (pm.y > corte) {
		discard;
	}
	float l = abs(fract(pm.y * linhas - TIME * 2.2) - 0.5);
	float varre = 0.35 + 0.65 * smoothstep(0.32, 0.5, l);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float franja = smoothstep(0.08, 0.0, corte - pm.y);
	float trem = 0.82 + 0.18 * sin(TIME * 47.0 + pm.y * 9.0);
	float f = (0.18 + 0.82 * fres) * varre * trem + franja * 1.6;
	f += smoothstep(0.12, 0.0, abs(pm.y - faixa)) * 1.4;
	ALBEDO = cor.rgb * f * forca * 1.6;
}
