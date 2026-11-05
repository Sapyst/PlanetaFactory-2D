shader_type spatial;
// Patch fauna, fase 2 (DesenhoPlantasReagem): galho caído e cogumelo, malhas pequenas feitas por código, em
// MultiMesh. A cor vem por instância (casca, chapéu); UV.y diz a parte: 1 = casca/chapéu, 0,5 = lamelas embaixo do
// chapéu (mais escuras), 0 = pé do cogumelo (claro).
render_mode diffuse_lambert, specular_disabled;

// Cogumelo: luz rebatida do chão e da copa de dia (o cogumelo mora na sombra da árvore e sumia preto) e chapéu fino
// que deixa passar luz por trás. De noite não brilha.
uniform float realce = 0.0;
global uniform vec3 sol_dir;

varying vec4 cor;

void vertex() {
	cor = COLOR;
}

void fragment() {
	vec3 pe = vec3(0.86, 0.83, 0.74);
	vec3 c = UV.y > 0.75 ? cor.rgb : (UV.y > 0.25 ? cor.rgb * 0.45 + vec3(0.1, 0.08, 0.06) : pe);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	float dia = smoothstep(-0.05, 0.3, sol_dir.y);
	EMISSION = c * realce * 0.2 * dia;
	BACKLIGHT = vec3(realce * 0.35);
}
