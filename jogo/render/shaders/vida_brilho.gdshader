shader_type spatial;
// Patch fauna, fase 1 (DesenhoVidaPequena): luz de bicho pequeno — vagalume (núcleo, halo e o rastro do voo),
// o reflexo da luz dele no capim (`plano`: o quad deitado no chão) e os olhos no mato. Só luz somada, presa no
// mundo (com profundidade): nunca é filtro de tela. Tamanho por instância em INSTANCE_CUSTOM.x (m).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool plano = false;
uniform float dureza = 2.0;
varying vec4 cor;

void vertex() {
	float esc = INSTANCE_CUSTOM.x;
	if (!plano) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * esc, INV_VIEW_MATRIX[1] * esc,
				INV_VIEW_MATRIX[2] * esc, MODEL_MATRIX[3]);
	}
	cor = COLOR;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), dureza);
	ALBEDO = cor.rgb * a * cor.a;
}
