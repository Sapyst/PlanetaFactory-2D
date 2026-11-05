shader_type spatial;
// Patch fauna, fase 1 (DesenhoVidaPequena): inseto de dia — pontinho escuro com o rastro curto do voo. Billboard
// preso no mundo (com profundidade); tamanho por instância em INSTANCE_CUSTOM.x (m).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float dureza = 1.2;
varying vec4 cor;

void vertex() {
	float esc = INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * esc, INV_VIEW_MATRIX[1] * esc,
			INV_VIEW_MATRIX[2] * esc, MODEL_MATRIX[3]);
	cor = COLOR;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = cor.rgb;
	ALPHA = pow(clamp(1.0 - d, 0.0, 1.0), dureza) * cor.a;
}
