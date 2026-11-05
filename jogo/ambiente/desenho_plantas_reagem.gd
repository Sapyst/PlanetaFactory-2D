class_name DesenhoPlantasReagem
extends Node3D
## Patch fauna, fase 2 (docs/PLANO_FAUNA.md): desenho do que as plantas fazem com o tempo, perto da câmera.
##  folhas     no outono as árvores caducas soltam folhas: caem girando, levadas pelo vento, e ficam um tanto no
##             chão em volta da árvore (juntando), até apagar. Sem estado: cada folha é função do tempo e da árvore.
##  galhos     os da lógica (PlantasReagem): deitados no capim, somem afundando.
##  cogumelos  os da lógica: crescem do chão, murcham.
## O 2D lê `folhas` (já no mundo) e a lógica (galhos, cogumelos).

const CORES_FOLHA := [Color(0.72, 0.36, 0.09), Color(0.55, 0.19, 0.07), Color(0.82, 0.62, 0.14), Color(0.42, 0.29, 0.13)]
const CORES_COGUMELO := [Color(0.88, 0.82, 0.68), Color(0.55, 0.36, 0.2), Color(0.8, 0.42, 0.12), Color(0.68, 0.62, 0.55)]
const CASCA := Color(0.3, 0.22, 0.15)

var eco: Ecossistema
var clima: Clima
var plantas: PlantasReagem
var camera: Camera3D

var folhas: Array = []          ## {pos: Vector3, cor: Color, chao: bool, giro: float}
var _arvs_base: Array = []
var _arvs: Array = []
var _d: Dictionary
var _t := 0.0
var _mm_cai: MultiMeshInstance3D
var _mm_chao: MultiMeshInstance3D
var _mm_galho: MultiMeshInstance3D
var _mm_cog: MultiMeshInstance3D
var _k_px := 0.0


func _ready() -> void:
	_d = Registro.fauna.get("plantas_reagem", {})
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_mm_cai = _mm(q, preload("res://render/shaders/folha_caida.gdshader"), {"plano": false}, true)
	_mm_chao = _mm(q, preload("res://render/shaders/folha_caida.gdshader"), {"plano": true}, true)
	_mm_galho = _mm(malha_galho(), preload("res://render/shaders/planta_pequena.gdshader"), {}, false)
	_mm_cog = _mm(malha_cogumelo(), preload("res://render/shaders/planta_pequena.gdshader"), {}, false)


func _mm(malha: Mesh, sh: Shader, params: Dictionary, custom: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = malha
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for k in params:
		mat.set_shader_parameter(k, params[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


# ------------------------------------------------------------------ malhas (código, baixíssimo polígono)
static func _tubo(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, lados: int, uv_y: float) -> void:
	var eixo := (b - a).normalized()
	var u := eixo.cross(Vector3.UP if absf(eixo.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := eixo.cross(u)
	for i in lados:
		var a0 := TAU * i / lados
		var a1 := TAU * (i + 1) / lados
		var n0 := u * cos(a0) + w * sin(a0)
		var n1 := u * cos(a1) + w * sin(a1)
		for par in [[a + n0 * ra, n0], [b + n0 * rb, n0], [b + n1 * rb, n1], [a + n0 * ra, n0], [b + n1 * rb, n1], [a + n1 * ra, n1]]:
			st.set_normal(par[1])
			st.set_uv(Vector2(0, uv_y))
			st.add_vertex(par[0])


## Galho quebrado deitado: um ramo de ~70 cm que afina, com dois galhinhos para os lados (tudo rente ao chão).
static func malha_galho() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.018
	_tubo(st, Vector3(-0.36, y, 0), Vector3(0.36, y * 0.7, 0.02), 0.018, 0.009, 5, 1.0)
	_tubo(st, Vector3(0.05, y, 0.0), Vector3(0.22, y * 0.6, 0.15), 0.009, 0.004, 4, 1.0)
	_tubo(st, Vector3(-0.14, y, 0.0), Vector3(-0.26, y * 0.6, -0.11), 0.008, 0.004, 4, 1.0)
	return st.commit()


## Cogumelo: pé claro (UV.y 0), chapéu em cúpula (UV.y 1) e lamelas embaixo (UV.y 0,5). ~15 cm de altura (o capim
## tem 20–35 cm: menor que isso ninguém via).
static func malha_cogumelo() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var esc := 2.4                                         # do tamanho que aparece acima do capim (~15 cm)
	_tubo(st, Vector3(0, 0, 0), Vector3(0, 0.045 * esc, 0), 0.011 * esc, 0.009 * esc, 6, 0.0)
	var lados := 8
	var r := 0.032 * esc
	var base := 0.04 * esc
	var aneis := [[r, base], [r * 0.85, base + 0.012 * esc], [r * 0.5, base + 0.02 * esc], [0.0, base + 0.023 * esc]]
	for k in aneis.size() - 1:
		for i in lados:
			var a0 := TAU * i / lados
			var a1 := TAU * (i + 1) / lados
			var p := []
			for par in [[k, a0], [k + 1, a0], [k + 1, a1], [k, a1]]:
				var an: Array = aneis[par[0]]
				p.append(Vector3(cos(par[1]) * float(an[0]), float(an[1]), sin(par[1]) * float(an[0])))
			var n: Vector3 = ((p[1] - p[0]) as Vector3).cross(p[3] - p[0]).normalized()
			if n.y < 0.0:
				n = -n
			for v in [p[0], p[1], p[2], p[0], p[2], p[3]]:
				st.set_normal(n)
				st.set_uv(Vector2(0, 1))
				st.add_vertex(v)
	for i in lados:                                        # lamelas: disco embaixo do chapéu
		var a0 := TAU * i / lados
		var a1 := TAU * (i + 1) / lados
		for v in [Vector3(0, base, 0), Vector3(cos(a0) * r, base, sin(a0) * r), Vector3(cos(a1) * r, base, sin(a1) * r)]:
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(0, 0.5))
			st.add_vertex(v)
	return st.commit()


static func _h(t: Vector2i, k: int) -> float:
	return fposmod(sin(float(t.x) * 127.1 + float(t.y) * 311.7 + float(k) * 74.7) * 43758.5453, 1.0)


# ------------------------------------------------------------------ quadro
func _process(delta: float) -> void:
	if eco == null:
		return
	_t += delta
	var vp := get_viewport()
	if camera != null and vp != null:
		_k_px = 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / maxf(vp.get_visible_rect().size.y, 1.0)
	_calcular_folhas()
	if vp != null and vp.disable_3d:                       # versão 2D: só os dados servem
		return
	_desenhar()


## Quanto as caducas soltam agora (0..1): pela estação (troca no 1º quarto) e mais com vento.
func taxa_folhas() -> float:
	var c: Dictionary = _d.get("folhas", {})
	if not bool(c.get("liga", true)) or not bool(_d.get("liga", true)) or clima == null:
		return 0.0
	var es: Array = c.get("estacoes", [0, 0, 1, 0.1])
	var e := clampi(clima.estacao, 0, 3)
	var f := float(Registro.clima.get("estacao_s", 604800))
	var taxa := lerpf(float(es[(e + 3) % 4]), float(es[e]), smoothstep(0.0, 0.25, clima.t_estacao / f))
	var vento := float(clima.valores.get("vento", 0.0))
	return clampf(taxa * (0.6 + 0.8 * vento), 0.0, 1.0)


func _calcular_folhas() -> void:
	folhas.clear()
	var taxa := taxa_folhas()
	if taxa <= 0.0:
		return
	var c: Dictionary = _d.get("folhas", {})
	var ciclo := float(c.get("ciclo_s", 26.0))
	var mx := int(c.get("max", 220))
	var vento := clima.direcao_vento * (0.3 + 1.6 * float(clima.valores.get("vento", 0.0)))
	var arvs := eco.arvores_perto(eco.foco, float(c.get("raio", 28.0)))
	if arvs != _arvs_base:                                 # orçamento: as árvores mais perto da câmera primeiro
		_arvs_base = arvs
		_arvs = arvs.duplicate()
		var f := eco.foco
		_arvs.sort_custom(func(x, y): return (x.pos as Vector2).distance_squared_to(f) < (y.pos as Vector2).distance_squared_to(f))
	for a in _arvs:
		if not a.caduca:
			continue
		var t: Vector2i = a.tile
		for k in int(c.get("por_arvore", 7)):
			if folhas.size() >= mx:
				return
			if _h(t, 200 + k) > taxa:
				continue
			var fase := fposmod(_t / ciclo + _h(t, 220 + k), 1.0) * ciclo
			var h0 := float(a.alto) * lerpf(0.55, 0.9, _h(t, 240 + k))
			var vq := 0.45 + 0.25 * _h(t, 260 + k)                  # m/s de queda
			var cai := h0 / vq
			var ini: Vector2 = a.pos + Vector2.from_angle(_h(t, 280 + k) * TAU) * float(a.copa) * _h(t, 300 + k)
			var tt := minf(fase, cai)
			var lado := Vector2(-vento.y, vento.x).normalized() if vento.length() > 0.01 else Vector2.RIGHT
			var p: Vector2 = ini + vento * tt + lado * sin(tt * 2.6 + float(k)) * 0.25
			var chao := fase >= cai
			if chao and float(clima.valores.get("vento", 0.0)) > 0.55:
				p += vento * (fase - cai) * 0.15                       # ventania arrasta a folha no chão
			var y := Grade.altura_em(p)
			var pousa := 0.2 + 0.16 * _h(t, 380 + k)                  # no chão fica por cima do capim (que segura a folha)
			var pos := Vector3(p.x, y + (pousa if chao else maxf(pousa, h0 - vq * tt)), -p.y)
			var apaga := clampf((ciclo - fase) / 3.0, 0.0, 1.0) if chao else 1.0
			var cor: Color = CORES_FOLHA[int(_h(t, 320 + k) * 4.0) % 4]
			cor.a = apaga
			folhas.append({"pos": pos, "cor": cor, "chao": chao, "giro": tt * (3.0 + 2.0 * _h(t, 340 + k)) + _h(t, 360 + k) * TAU})


func _tam(p: Vector3, real: float, px: float) -> float:
	if camera == null:
		return real
	return maxf(real, px * _k_px * camera.global_position.distance_to(p))


func _desenhar() -> void:
	var px := float(_d.get("folhas", {}).get("px", 1.6))
	var cai: Array = []
	var chao: Array = []
	for f in folhas:
		var c: Color = f.cor
		var s := _tam(f.pos, 0.1, px)
		if f.chao:
			if c.a > 0.02:                                  # apagando: encolhe (vira terra), não escurece
				var sc := s * c.a
				var b := Basis(Vector3.UP, float(f.giro)) * Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(sc, sc * 1.3, 1.0))
				chao.append([Transform3D(b, f.pos), Color(c.r, c.g, c.b), Color(sc, sc, 0, 0)])
		else:
			var vira := absf(cos(float(f.giro)))
			cai.append([Transform3D(Basis(), f.pos), c, Color(s * (0.25 + 0.75 * vira), s * 1.3, 0, 0)])
	_encher(_mm_cai, cai)
	_encher(_mm_chao, chao)
	var gal: Array = []
	if plantas != null:
		for g in plantas.galhos:
			var some := plantas.some_galho(g)
			var p: Vector2 = g.pos
			var b := Basis(Vector3.UP, float(g.ang)).scaled(Vector3.ONE * float(g.tam) * 1.4 * (1.0 - 0.5 * some))
			# deitado por cima do capim (que segura o galho); some afundando nele
			gal.append([Transform3D(b, Vector3(p.x, Grade.altura_em(p) + 0.16 - 0.2 * some, -p.y)), CASCA, Color()])
	_encher(_mm_galho, gal)
	var cog: Array = []
	if plantas != null:
		for c in plantas.cogumelos:
			var e := plantas.escala_cogumelo(c)
			if e <= 0.01:
				continue
			var p: Vector2 = c.pos
			var b := Basis(Vector3.UP, float(c.ang)).scaled(Vector3.ONE * float(c.tam) * e)
			var cor: Color = CORES_COGUMELO[int(c.cor) % 4]
			cog.append([Transform3D(b, Vector3(p.x, Grade.altura_em(p), -p.y)), cor, Color()])
	_encher(_mm_cog, cog)


## Um buffer por MultiMesh (transform 12 + cor 4 [+ custom 4]): uma chamada por quadro, mesmo com 500 folhas.
func _encher(mi: MultiMeshInstance3D, itens: Array) -> void:
	var mm := mi.multimesh
	if mm.instance_count < itens.size() or mm.instance_count > itens.size() * 2 + 64:
		mm.instance_count = itens.size() + 32
	var passo := 20 if mm.use_custom_data else 16
	var buf := PackedFloat32Array()
	buf.resize(mm.instance_count * passo)
	for i in itens.size():
		var t: Transform3D = itens[i][0]
		var c: Color = itens[i][1]
		var o := i * passo
		buf[o] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		if passo == 20:
			var u: Color = itens[i][2]
			buf[o + 16] = u.r; buf[o + 17] = u.g; buf[o + 18] = u.b; buf[o + 19] = u.a
	mm.buffer = buf
	mm.visible_instance_count = itens.size()
