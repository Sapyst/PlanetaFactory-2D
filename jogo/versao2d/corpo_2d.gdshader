shader_type canvas_item;
// Patch fauna, fase 4 na versão 2D: o corpo morto no sprite, como o material_pf faz no 3D (DesenhoCarcacas manda os
// mesmos valores pelos metas do nó 3D). `desligada`: a cor forte (olho, led, ácido) apaga para um cinza escuro.
// `ferrugem`: a sucata enferruja em manchas por texel (nunca o corpo todo), num marrom com veios alaranjados.
// `podre`: a carcaça escurece com hematomas roxos e verde-oliva (inchada) e seca num couro cinza-marrom (restos).

uniform float ferrugem = 0.0;
uniform float podre = 0.0;
uniform float desligada = 0.0;
uniform float alfa = 1.0;

float _h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h(i), _h(i + vec2(1.0, 0.0)), f.x), mix(_h(i + vec2(0.0, 1.0)), _h(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec4 c = COLOR;
	vec2 tx = floor(UV / TEXTURE_PIXEL_SIZE);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	c.rgb = mix(c.rgb, vec3(lum) * 0.45 + c.rgb * 0.12, desligada * smoothstep(0.25, 0.55, sat));
	if (ferrugem > 0.0) {
		float n = _ruido(tx / 5.0) * 0.6 + _ruido(tx / 1.7) * 0.25 + _h(tx) * 0.15;
		float cobre = ferrugem * 0.6;
		float onde = smoothstep(1.0 - cobre, 1.0 - cobre + 0.28, n);
		vec3 ox = mix(vec3(0.28, 0.14, 0.08), vec3(0.46, 0.24, 0.11), _h(tx + 7.0));
		c.rgb = mix(c.rgb * (1.0 - 0.35 * ferrugem), ox * (0.55 + 0.9 * lum), onde);
	}
	if (podre > 0.0) {
		float hem = smoothstep(0.35, 0.75, _ruido(tx / 6.0));
		vec3 carne = mix(vec3(0.3, 0.32, 0.16), vec3(0.38, 0.19, 0.33), hem);
		vec3 inch = mix(c.rgb * 0.45, carne * (0.5 + lum), 0.65);
		vec3 seco = vec3(0.42, 0.38, 0.32) * (0.6 + 0.8 * lum);
		c.rgb = podre < 0.5 ? mix(c.rgb, inch, podre * 2.0) : mix(inch, seco, (podre - 0.5) * 2.0);
	}
	c.a *= alfa;
	COLOR = c;
}
