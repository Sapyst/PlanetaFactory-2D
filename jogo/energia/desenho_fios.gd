class_name DesenhoFios
extends Node3D
## Desenha as ligações elétricas do mapa: cabo escuro que verga (catenária simples) entre poste ↔ poste e
## poste ↔ máquina; ligação de torre sem fio = feixe ciano tracejado que corre na direção da energia.
## Fita deitada (larga vista de cima, a câmera é quase top-down). Refaz só quando o mapa ou os fios mudam.
## Faísca: rara e curta, corre um trecho do cabo que passa energia de verdade (RedeEnergia.fluxo_em nas duas pontas), na
## cor da rede. Limite por perfil em dados/luzes.json, contando o que está em cena; só nasce dentro do oval de visão.

const SEGMENTOS := 10
const LARGURA := 0.05

const FAISCA_PERIODO := 0.2            ## s entre sorteios
const FAISCA_FORCA := 2.2              ## força do shader de raio: bem abaixo do raio de verdade (6)
const FAISCA_LARGURA := 0.022
const FAISCA_HALO := 0.075

var mapa: MapaOcupacao
var fabrica: Fabrica
var faiscas_ligadas := true            ## medição sem as faíscas
var forcar_faiscas := false            ## medição (roteiro carga): todo cabo conta como energizado
var _lista: Array = []                 ## cabos de verdade: [a, b, flecha, id, o]
var _soltos: Array = []                ## fase 7: pedaços de cabo roído caídos (Array de pontos), do poste até o chão
var _faiscas: Array = []               ## em cena: {a, b, flecha, ini, fim, t, vida, cor}
var _espera := 0.0
var _malha_faisca := ImmediateMesh.new()
var _mi_faisca: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _lim: Dictionary
var _cor_base := Color(0.72, 0.52, 1.0)
var _cor_geradores := Color(1.0, 0.8, 0.22)
var _cabos: MeshInstance3D
var _feixes: MeshInstance3D
var _assinatura := ""


func _ready() -> void:
	_cabos = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cabos.material_override = m
	_cabos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cabos)
	_feixes = MeshInstance3D.new()
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://energia/feixe.gdshader")
	_feixes.material_override = sm
	_feixes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_feixes)
	_mi_faisca = MeshInstance3D.new()
	_mi_faisca.mesh = _malha_faisca
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://render/shaders/raio.gdshader")
	fm.set_shader_parameter("forca", FAISCA_FORCA)
	_mi_faisca.material_override = fm
	_mi_faisca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi_faisca.extra_cull_margin = 1.0e4
	add_child(_mi_faisca)
	_lim = Registro.luzes.get("celular" if Sessao.eh_celular() else "pc", {})
	var cs: Dictionary = Registro.luzes.get("cores", {})
	if cs.has("base"):
		_cor_base = Color(cs.base[0], cs.base[1], cs.base[2])
		_cor_geradores = Color(cs.geradores[0], cs.geradores[1], cs.geradores[2])


func _process(delta: float) -> void:
	if mapa == null:
		return
	_atualizar_faiscas(delta)
	var n := 0
	var nc := 0
	for id in mapa.estruturas:
		n += mapa.estruturas[id].get("fios", []).size()
		nc += mapa.estruturas[id].get("cortados", []).size()
	var ass := "%d|%d|%d" % [mapa.versao, n, nc]
	if ass == _assinatura:
		return
	_assinatura = ass
	refazer()


func refazer() -> void:
	var cabos := SurfaceTool.new()
	cabos.begin(Mesh.PRIMITIVE_TRIANGLES)
	var feixes := SurfaceTool.new()
	feixes.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lista.clear()
	var tem_cabo := false
	var tem_feixe := false
	for id in mapa.estruturas:
		var e: Dictionary = mapa.estruturas[id]
		for o in e.get("fios", []):
			if o <= id or not mapa.estruturas.has(o):
				continue
			var f: Dictionary = mapa.estruturas[o]
			var a := Fiacao.ponto_fio(e, Fiacao.centro(f))
			var b := Fiacao.ponto_fio(f, Fiacao.centro(e))
			if Fiacao.liga_sem_cabo(e, f):
				_fita(feixes, a, b, 0.0, 0.10, true)
				tem_feixe = true
			else:
				_fita(cabos, a, b, minf(0.06 * a.distance_to(b), 0.7), LARGURA, false)
				_lista.append([a, b, minf(0.06 * a.distance_to(b), 0.7), id, o])
				tem_cabo = true
	_soltos.clear()
	for id in mapa.estruturas:                         # fase 7: cabo roído — cada ponta pende partida até o chão
		var e: Dictionary = mapa.estruturas[id]
		for o in e.get("cortados", []):
			if not mapa.estruturas.has(o):
				continue
			var f: Dictionary = mapa.estruturas[o]
			var a := Fiacao.ponto_fio(e, Fiacao.centro(f))
			var b := Fiacao.ponto_fio(f, Fiacao.centro(e))
			var pts := _pedaco_caido(a, b, 0.3 if a.y - Grade.altura_em(Vector2(a.x, -a.z)) > b.y - Grade.altura_em(Vector2(b.x, -b.z)) else 0.12)
			_linha(cabos, pts, LARGURA)
			_soltos.append(pts)
			tem_cabo = true
	_cabos.mesh = cabos.commit() if tem_cabo else null
	_feixes.mesh = feixes.commit() if tem_feixe else null


## Fita de a até b em SEGMENTOS pedaços; `flecha` = quanto verga no meio; UV.x = metros ao longo (para o feixe correr).
func _fita(st: SurfaceTool, a: Vector3, b: Vector3, flecha: float, largura: float, uv: bool) -> void:
	var dir := (b - a)
	var lado := Vector3(-dir.z, 0, dir.x).normalized() * largura * 0.5
	if lado.length() < 1e-5:
		lado = Vector3(largura * 0.5, 0, 0)
	var comp := dir.length()
	var pts: Array[Vector3] = []
	for i in SEGMENTOS + 1:
		var t := float(i) / SEGMENTOS
		pts.append(a.lerp(b, t) - Vector3.UP * flecha * 4.0 * t * (1.0 - t))
	for i in SEGMENTOS:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var u0 := comp * i / SEGMENTOS
		var u1 := comp * (i + 1) / SEGMENTOS
		var v := [[p0 - lado, Vector2(u0, 0)], [p0 + lado, Vector2(u0, 1)], [p1 + lado, Vector2(u1, 1)], [p1 - lado, Vector2(u1, 0)]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			if uv:
				st.set_uv(v[k][1])
			st.add_vertex(v[k][0])


## O pedaço que sobrou presa em `a` depois de partir: vai um trecho (`frac` do vão) na direção de `b`, verga e cai até
## o chão, onde fica deitado um pouco.
func _pedaco_caido(a: Vector3, b: Vector3, frac: float) -> Array:
	var h := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var comp := h.length() * frac
	h = h.normalized() if h.length() > 1e-4 else Vector3.RIGHT
	var pts: Array = []
	for i in 8:
		var t := i / 7.0
		var p := a + h * comp * t
		var chao := Grade.altura_em(Vector2(p.x, -p.z)) + 0.015
		p.y = maxf(lerpf(a.y, chao, pow(t, 1.4)), chao)         # verga e cai: mais rápido perto do fim
		pts.append(p)
	var fim: Vector3 = pts[-1]
	pts.append(Vector3(fim.x, Grade.altura_em(Vector2(fim.x, -fim.z)) + 0.015, fim.z) + h * 0.25)
	return pts


func _linha(st: SurfaceTool, pts: Array, largura: float) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := p1 - p0
		var lado := Vector3(-d.z, 0, d.x).normalized() * largura * 0.5
		if lado.length() < 1e-5:
			lado = Vector3(largura * 0.5, 0, 0)
		for q in [p0 - lado, p0 + lado, p1 + lado, p0 - lado, p1 + lado, p1 - lado]:
			st.set_normal(Vector3.UP)
			st.add_vertex(q)


## Está passando energia por este cabo? Devolve a cor da rede ou null.
func _cor_do_cabo(c: Array):
	if forcar_faiscas:
		return _cor_base if int(c[3]) % 2 == 0 else _cor_geradores
	if fabrica == null or not fabrica.rede.fluxo_em(c[3]) or not fabrica.rede.fluxo_em(c[4]):
		return null
	match fabrica.rede.origem_de(c[3]):
		RedeEnergia.BASE: return _cor_base
		RedeEnergia.GERADORES: return _cor_geradores
	return null


func faiscas_em_cena() -> int:
	return _faiscas.size()


func _atualizar_faiscas(delta: float) -> void:
	var maximo := int(_lim.get("faiscas", 0))
	if faiscas_ligadas and maximo > 0 and not _lista.is_empty():
		_espera -= delta
		if _espera <= 0.0:
			_espera = FAISCA_PERIODO
			# sorteios proporcionais ao número de cabos: cada cabo acende, em média, a cada 30–50 s
			var q := float(_lista.size()) * float(_lim.get("faisca_por_cabo_s", 0.03)) * FAISCA_PERIODO
			var tentativas := int(q) + (1 if _rng.randf() < fmod(q, 1.0) else 0)
			for k in tentativas:
				if _faiscas.size() >= maximo:
					break
				_nascer(_lista[_rng.randi() % _lista.size()])
	for i in range(_faiscas.size() - 1, -1, -1):
		_faiscas[i].t += delta / float(_faiscas[i].vida)
		if _faiscas[i].t >= 1.0:
			_faiscas.remove_at(i)
	_malha_faisca.clear_surfaces()
	if _faiscas.is_empty():
		return
	_malha_faisca.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in _faiscas:
		_desenhar_faisca(f)
	_malha_faisca.surface_end()


func _nascer(c: Array) -> void:
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var meio := (a + b) * 0.5
	if not Visao.dentro(Vector2(meio.x, -meio.z), 1.0):
		return
	var cor = _cor_do_cabo(c)
	if cor == null:
		return
	var trecho := _rng.randf_range(0.25, 0.45)
	var ini := _rng.randf_range(0.0, 1.0 - trecho)
	var ida := _rng.randf() < 0.5
	_faiscas.append({"a": a, "b": b, "flecha": c[2], "ini": ini if ida else ini + trecho, "fim": ini + trecho if ida else ini,
			"t": 0.0, "vida": _rng.randf_range(0.28, 0.5), "cor": cor})


## Ponto do cabo em s (0..1), com a mesma catenária do desenho.
static func ponto_cabo(a: Vector3, b: Vector3, flecha: float, s: float) -> Vector3:
	return a.lerp(b, s) - Vector3.UP * flecha * 4.0 * s * (1.0 - s)


func _desenhar_faisca(f: Dictionary) -> void:
	var a: Vector3 = f.a
	var b: Vector3 = f.b
	var t: float = f.t
	var s1: float = lerpf(f.ini, f.fim, t)
	var s0: float = lerpf(f.ini, f.fim, maxf(t - 0.28, 0.0))         # o rabo vem atrás da cabeça
	var lado := Vector3(-(b - a).z, 0, (b - a).x).normalized()
	var cor: Color = f.cor
	var brilho := sin(t * PI)                                         # nasce e morre sem estalo
	var n := 4
	var pts: Array[Vector3] = []
	for i in n + 1:
		var u := float(i) / n
		var p := ponto_cabo(a, b, f.flecha, lerpf(s0, s1, u))
		if i > 0 and i < n:
			p += lado * _rng.randf_range(-0.03, 0.03) + Vector3.UP * _rng.randf_range(-0.03, 0.03)
		pts.append(p)
	var nucleo := cor.lerp(Color.WHITE, 0.3)
	nucleo.a = brilho
	var halo := cor
	halo.a = brilho * 0.16
	for camada in [[FAISCA_HALO, halo], [FAISCA_LARGURA, nucleo]]:
		_malha_faisca.surface_set_color(camada[1])
		for i in n:
			var w: Vector3 = lado * float(camada[0])
			var c := Vector3.UP * float(camada[0])
			for eixo in [w, c]:
				for v in [pts[i] - eixo, pts[i] + eixo, pts[i + 1] + eixo, pts[i] - eixo, pts[i + 1] + eixo, pts[i + 1] - eixo]:
					_malha_faisca.surface_add_vertex(v)
