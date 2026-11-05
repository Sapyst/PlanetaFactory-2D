class_name DesenhoVidaPequena
extends Node3D
## Patch fauna, fase 1 (docs/PLANO_FAUNA.md): a vida pequena perto da câmera — bichos sem lógica própria, presos
## no mundo, que só leem o Ecossistema (saúde do chão, tocas) e o Clima (hora, estação, chuva, vento).
##
##  vagalumes  à noite, em enxames sobre capim saudável (mais na beira d'água): voo lento e errante, cada um pisca
##             no seu ritmo (clarão curto, escuro longo) deixando um rastro curto; o clarão acende um disco fraco no
##             capim embaixo (a "luz micro"). Somem no inverno, na chuva e na ventania.
##  insetos    de dia, nuvenzinhas de mosquito: pontinhos escuros, voo nervoso com rastro curto. Somem com chuva,
##             vento forte, inverno e zoom longe.
##  olhos      à noite, raro: um par de olhos brilhando no mato por alguns segundos, piscando, e some.
##  sons       grilos à noite e insetos de dia (laços de ambiente, pela estação e pela saúde do lugar); sapos na
##             beira d'água depois da chuva; perto de ninho, cratera ou aranha tudo se cala — o silêncio avisa.
## Tudo vem de enxames em tiles fixos (sorteio por hash do tile), refeitos só quando a câmera anda: a mesma noite
## mostra os mesmos lugares. Um MultiMesh por material (poucas chamadas de desenho, bom para o celular).
## O 2D desenha os mesmos pontos (`vagalumes`, `insetos`, `olhos`, já em coordenadas do mundo).

const AMARELO := Color(0.78, 1.0, 0.32)
const OLHO := Color(0.85, 1.0, 0.55)
const INSETO := Color(0.92, 0.9, 0.8)          ## asa pegando sol: de dia o mosquito aparece claro contra o chão

var eco: Ecossistema
var clima: Clima
var camera: CameraJogo

## Saída para o 2D (e testes): pontos do quadro em coordenadas do mundo.
var vagalumes: Array = []      ## {pos: Vector3, brilho: 0..1, rastro: [Vector3, Vector3], chao: Vector3}
var insetos: Array = []        ## {pos: Vector3, rastro: [Vector3, Vector3]}
var olhos: Array = []          ## {a: Vector3, b: Vector3, brilho}
var fatores := {"vagalumes": 0.0, "insetos": 0.0, "noite": 0.0, "silencio": 0.0}

var _d: Dictionary
var _enx_v: Array = []         ## {c: Vector2, y: float, n: int, s: float}
var _enx_i: Array = []
var _mato: Array = []          ## tiles de mato perto (olhos)
var _foco_ancoras := Vector2.INF
var _t_ancoras := 0.0
var _t := 0.0
var _t_som := 0.0
var _t_sapo := 2.0
var _mm_brilho: MultiMeshInstance3D
var _mm_chao: MultiMeshInstance3D
var _mm_ponto: MultiMeshInstance3D
var _k_px := 0.0               ## metros por pixel a 1 m da câmera


func _ready() -> void:
	_d = Registro.fauna.get("vida_pequena", {})
	_mm_brilho = _multimesh(preload("res://render/shaders/vida_brilho.gdshader"), false, 2.2)
	_mm_chao = _multimesh(preload("res://render/shaders/vida_brilho.gdshader"), true, 1.6)
	_mm_ponto = _multimesh(preload("res://render/shaders/vida_ponto.gdshader"), false, 1.2)


func _multimesh(sh: Shader, plano: bool, dureza: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = sh
	if sh.get_shader_uniform_list().any(func(u): return u.name == "plano"):
		mat.set_shader_parameter("plano", plano)
	mat.set_shader_parameter("dureza", dureza)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0                     # os pontos andam: não deixa o recorte sumir com o lote
	add_child(mi)
	return mi


func _sub(chave: String) -> Dictionary:
	return _d.get(chave, {})


func _liga(chave: String) -> bool:
	return bool(_d.get("liga", true)) and bool(_sub(chave).get("liga", true))


static func _h(t: Vector2i, k: int) -> float:
	return fposmod(sin(float(t.x) * 127.1 + float(t.y) * 311.7 + float(k) * 74.7) * 43758.5453, 1.0)


# ------------------------------------------------------------------ quanto de cada coisa agora
func _fatores() -> void:
	var luz := clima.luz_dia() if clima != null else 1.0
	var est := clampi(clima.estacao if clima != null else 1, 0, 3)
	var chuva := float(clima.valores.get("chuva", 0.0)) if clima != null else 0.0
	var vento := float(clima.valores.get("vento", 0.0)) if clima != null else 0.0
	var noite := clampf((0.42 - luz) / 0.22, 0.0, 1.0)
	var dia := clampf((luz - 0.45) / 0.2, 0.0, 1.0)
	var ev: Array = _sub("vagalumes").get("estacoes", [1, 1, 1, 0])
	var ei: Array = _sub("insetos").get("estacoes", [1, 1, 1, 0])
	fatores.noite = noite
	fatores.vagalumes = noite * float(ev[est]) * (1.0 - 0.9 * chuva) * (1.0 - clampf((vento - 0.5) / 0.4, 0.0, 1.0)) \
			if _liga("vagalumes") else 0.0
	var zoom := 1.0
	if camera != null:
		zoom = clampf((float(_sub("insetos").get("zoom_max", 55)) - camera.distancia) / 15.0, 0.0, 1.0)
	fatores.insetos = dia * float(ei[est]) * (1.0 - chuva) * (1.0 - clampf((vento - 0.45) / 0.35, 0.0, 1.0)) * zoom \
			if _liga("insetos") else 0.0
	var st: Array = _sub("sons").get("silencio_toca", [12, 34])
	var dt_toca := eco.distancia(eco.foco, "toca", float(st[1])) if eco != null else INF
	var silencio := 1.0 - clampf((dt_toca - float(st[0])) / (float(st[1]) - float(st[0])), 0.0, 1.0)
	if eco != null and eco.distancia(eco.foco, "alien", float(_sub("sons").get("silencio_alien", 15))) < INF:
		silencio = maxf(silencio, 0.8)
	fatores.silencio = silencio


# ------------------------------------------------------------------ enxames (tiles fixos perto da câmera)
func _ancoras() -> void:
	_enx_v = _enxames("vagalumes", 1) if fatores.vagalumes > 0.0 else []
	_enx_i = _enxames("insetos", 2) if fatores.insetos > 0.0 else []
	_mato.clear()
	if _liga("olhos") and fatores.noite > 0.5:
		var r := int(_sub("olhos").get("raio", 22))
		var f := Vector2i(eco.foco.round())
		for y in range(-r, r + 1, 2):
			for x in range(-r, r + 1, 2):
				var t := f + Vector2i(x, y)
				if Vector2(x, y).length() > r or eco.mapa.limpos.has(t):
					continue
				var o := eco.gerador.distribuicao.obstaculo(t)
				if o.is_empty() or Registro.modelos.get(o.nome, {}).get("categoria", "") != "mapa/vegetacao":
					continue
				if eco.saude_tile(t) > 0.5 and eco.distancia(Vector2(t), "toca", 14.0) == INF:
					_mato.append(t)


func _enxames(tipo: String, k: int) -> Array:
	var c: Dictionary = _sub(tipo)
	var r := int(c.get("raio", 30))
	var passo := int(c.get("passo", 3))
	var dens := float(c.get("densidade", 0.07))
	var bonus := float(c.get("agua_bonus", 2.0))
	var pe: Array = c.get("por_enxame", [3, 6])
	var f := Vector2i(eco.foco.round())
	f = Vector2i(f.x - posmod(f.x, passo), f.y - posmod(f.y, passo))       # grade fixa no mundo (não anda com a câmera)
	var out: Array = []
	var total := 0
	for y in range(-r, r + 1, passo):
		for x in range(-r, r + 1, passo):
			var t := f + Vector2i(x, y)
			if Vector2(t).distance_to(eco.foco) > r:
				continue
			var h := _h(t, k)
			if h >= dens * (1.0 + bonus):
				continue
			if h >= dens and not eco.perto_da_agua(t, 3):
				continue                                   # só a beira d'água tem a densidade a mais
			if eco.saude(t) < float(c.get("saude_min", 0.45)) or eco.perto_de_construcao(t, 2):
				continue
			if eco.distancia(Vector2(t), "toca", float(c.get("longe_toca", 14))) < INF:
				continue
			var cc := Vector2(t) + Vector2(_h(t, k + 3), _h(t, k + 5)) * float(passo)
			var n := int(pe[0]) + int(_h(t, k + 7) * (int(pe[1]) - int(pe[0]) + 1))
			out.append({"c": cc, "y": Grade.altura_em(cc), "n": n, "s": _h(t, k + 11), "t": t})
			total += n
	out.sort_custom(func(a, b): return (a.c as Vector2).distance_squared_to(eco.foco) < (b.c as Vector2).distance_squared_to(eco.foco))
	var mx := int(c.get("max", 100))
	var soma := 0
	var cortado: Array = []
	for e in out:                                          # orçamento: os mais perto da câmera primeiro
		if soma + int(e.n) > mx:
			break
		soma += int(e.n)
		cortado.append(e)
	return cortado


# ------------------------------------------------------------------ quadro
func _process(delta: float) -> void:
	if eco == null:
		return
	_t += delta
	_fatores()
	_t_ancoras -= delta
	if _t_ancoras <= 0.0 or eco.foco.distance_to(_foco_ancoras) > 4.0:
		_t_ancoras = 2.0
		_foco_ancoras = eco.foco
		_ancoras()
	var vp := get_viewport()
	var alt_tela := vp.get_visible_rect().size.y if vp != null else 720.0
	var fov := camera.fov if camera != null else 50.0
	_k_px = 2.0 * tan(deg_to_rad(fov) / 2.0) / maxf(alt_tela, 1.0)
	_calcular()
	if vp == null or not vp.disable_3d:                  # versão 2D: o 3D está desligado, só os pontos servem
		_desenhar()
	_t_som -= delta
	if _t_som <= 0.0:
		_t_som = 0.35
		_sons(0.35)


## Posição de um vagalume j do enxame e (no tempo t).
func _voo_vagalume(e: Dictionary, j: int, t: float) -> Vector3:
	var s1 := _h(e.t, 20 + j)
	var s2 := _h(e.t, 40 + j)
	var s3 := _h(e.t, 60 + j)
	var w := 0.22 + 0.3 * s1
	var p: Vector2 = e.c + Vector2(sin(t * w + s2 * TAU) * 1.3 + sin(t * w * 2.3 + s3 * 9.0) * 0.35,
			cos(t * w * 1.3 + s3 * TAU) * 1.3 + cos(t * w * 2.9 + s1 * 7.0) * 0.35)
	var h := 0.3 + 1.0 * s3 + 0.22 * sin(t * 0.8 + s1 * 11.0)
	return Vector3(p.x, float(e.y) + h, -p.y)


## Luz do vagalume (0..1), cada um no seu ritmo. Metade pisca (clarão curto que apaga devagar, escuro longo); a
## outra metade brilha baixo e respira devagar — de longe sempre há alguns acesos.
func _pisca(e: Dictionary, j: int, t: float) -> float:
	var per := 2.0 + 2.6 * _h(e.t, 80 + j)
	var ph := fposmod(t / per + _h(e.t, 100 + j), 1.0)
	if _h(e.t, 140 + j) < 0.5:
		var sobe := clampf(ph / 0.06, 0.0, 1.0)
		return sobe * sobe * exp(-maxf(ph - 0.06, 0.0) / 0.12)
	return 0.3 + 0.7 * pow(0.5 + 0.5 * sin(ph * TAU), 3.0)


func _voo_inseto(e: Dictionary, j: int, t: float) -> Vector3:
	var s1 := _h(e.t, 20 + j)
	var s2 := _h(e.t, 40 + j)
	var s3 := _h(e.t, 60 + j)
	var p: Vector2 = e.c + Vector2(sin(t * (2.6 + 2.0 * s1) + s2 * TAU) * 0.45 + sin(t * 9.1 + s3 * 20.0) * 0.12,
			cos(t * (2.9 + 1.7 * s2) + s3 * TAU) * 0.45 + cos(t * 8.3 + s1 * 20.0) * 0.12)
	var h := 0.55 + 0.6 * s3 + 0.18 * sin(t * (4.0 + 3.0 * s2) + s1 * 9.0)
	return Vector3(p.x, float(e.y) + h, -p.y)


func _calcular() -> void:
	vagalumes.clear()
	insetos.clear()
	olhos.clear()
	if fatores.vagalumes > 0.0:
		for e in _enx_v:
			for j in int(e.n):
				if _h(e.t, 120 + j) > fatores.vagalumes:
					continue                               # ao anoitecer acendem aos poucos
				var b := _pisca(e, j, _t)
				var p := _voo_vagalume(e, j, _t)
				vagalumes.append({"pos": p, "brilho": b, "rastro": [_voo_vagalume(e, j, _t - 0.09), _voo_vagalume(e, j, _t - 0.18)],
						"b_rastro": [_pisca(e, j, _t - 0.09), _pisca(e, j, _t - 0.18)], "chao": Vector3(p.x, float(e.y) + 0.03, p.z)})
	if fatores.insetos > 0.0:
		for e in _enx_i:
			for j in int(e.n):
				if _h(e.t, 120 + j) > fatores.insetos:
					continue
				insetos.append({"pos": _voo_inseto(e, j, _t), "rastro": [_voo_inseto(e, j, _t - 0.035), _voo_inseto(e, j, _t - 0.07)]})
	if _liga("olhos") and fatores.noite > 0.7 and not _mato.is_empty() and fatores.silencio < 0.5:
		var c: Dictionary = _sub("olhos")
		var slot_s := float(c.get("slot_s", 7.0))
		var vida: Array = c.get("vida_s", [2.5, 5.5])
		var cam := camera.global_position if camera != null else Vector3(0, 30, 0)
		for k in int(c.get("max_pares", 3)):
			var tt := _t + k * 2.3
			var slot := floori(tt / slot_s)
			var sv := Vector2i(slot, k)
			if _h(sv, 3) > float(c.get("chance", 0.55)):
				continue
			var dentro := tt - slot * slot_s
			var dura := lerpf(float(vida[0]), float(vida[1]), _h(sv, 5))
			if dentro < 0.6 or dentro > 0.6 + dura:
				continue
			var tile: Vector2i = _mato[int(_h(sv, 7) * _mato.size()) % _mato.size()]
			var pc := Vector2(tile) + Vector2(0.3 + 0.4 * _h(sv, 9), 0.3 + 0.4 * _h(sv, 11))
			var base := Grade.ponto_mundo(pc, 0.2 + 0.15 * _h(sv, 13))
			var lado := (cam - base).cross(Vector3.UP).normalized() * 0.04
			var u := dentro - 0.6
			var b := clampf(u / 0.25, 0.0, 1.0) * clampf((dura - u) / 0.3, 0.0, 1.0)
			var pisc := fposmod(u + _h(sv, 15) * 3.0, 2.2)
			if pisc < 0.13:
				b = 0.0                                    # piscou
			olhos.append({"a": base - lado, "b": base + lado, "brilho": b * fatores.noite})


func _tam(p: Vector3, px: float) -> float:
	var cam := camera.global_position if camera != null else p + Vector3(0, 30, 0)
	return maxf(0.012, px * _k_px * cam.distance_to(p))


func _desenhar() -> void:
	var cv: Dictionary = _sub("vagalumes")
	var px := float(cv.get("px", 1.8))
	var halo := float(cv.get("halo_px", 9.0))
	var bri: Array = []                                    # [pos, tam, cor]
	var chao: Array = []
	for v in vagalumes:
		var b := float(v.brilho)
		bri.append([v.pos, _tam(v.pos, px), Color(AMARELO, 0.3 + 0.7 * b)])
		if b > 0.05:
			bri.append([v.pos, _tam(v.pos, halo) * (0.55 + 0.45 * b), Color(AMARELO, 0.6 * b)])
			var alto := clampf(1.0 - (float(v.pos.y) - float(v.chao.y)) / 1.4, 0.0, 1.0)      # só acende o capim de perto
			if alto > 0.0:
				chao.append([v.chao, 0.22 + 0.18 * b, Color(AMARELO, 0.06 * b * alto)])
		for i in 2:
			var br := float(v.b_rastro[i])
			if br > 0.05:
				bri.append([v.rastro[i], _tam(v.rastro[i], px * (0.8 - 0.2 * i)), Color(AMARELO, br * (0.45 - 0.2 * i))])
	for o in olhos:
		var b := float(o.brilho)
		if b > 0.0:
			var t := _tam(o.a, float(_sub("olhos").get("px", 1.6)))
			bri.append([o.a, t, Color(OLHO, b)])
			bri.append([o.b, t, Color(OLHO, b)])
	var pts: Array = []
	var pxi := float(_sub("insetos").get("px", 1.4))
	for ins in insetos:
		pts.append([ins.pos, _tam(ins.pos, pxi), Color(INSETO, 0.8)])
		pts.append([ins.rastro[0], _tam(ins.rastro[0], pxi * 0.8), Color(INSETO, 0.4)])
		pts.append([ins.rastro[1], _tam(ins.rastro[1], pxi * 0.6), Color(INSETO, 0.18)])
	_encher(_mm_brilho, bri, false)
	_encher(_mm_chao, chao, true)
	_encher(_mm_ponto, pts, false)


## Um buffer só por MultiMesh (transform 12 + cor 4 + custom 4 por instância): uma chamada por quadro.
func _encher(mi: MultiMeshInstance3D, itens: Array, plano: bool) -> void:
	var mm := mi.multimesh
	if mm.instance_count < itens.size() or mm.instance_count > itens.size() * 2 + 64:
		mm.instance_count = itens.size() + 32
	var n := mm.instance_count
	var buf := PackedFloat32Array()
	buf.resize(n * 20)
	for i in itens.size():
		var p: Vector3 = itens[i][0]
		var s: float = itens[i][1]
		var c: Color = itens[i][2]
		var o := i * 20
		if plano:                                          # deitado no chão: X e Z do quad no plano do capim
			buf[o] = s; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
			buf[o + 4] = 0.0; buf[o + 5] = 0.0; buf[o + 6] = -s; buf[o + 7] = p.y
			buf[o + 8] = 0.0; buf[o + 9] = s; buf[o + 10] = 0.0; buf[o + 11] = p.z
		else:
			buf[o] = 1.0; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
			buf[o + 4] = 0.0; buf[o + 5] = 1.0; buf[o + 6] = 0.0; buf[o + 7] = p.y
			buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = 1.0; buf[o + 11] = p.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		buf[o + 16] = s
	for i in range(itens.size(), n):                       # as que sobram: escala zero, longe
		var o := i * 20
		buf[o + 7] = -10000.0
	mm.buffer = buf
	mm.visible_instance_count = itens.size()


# ------------------------------------------------------------------ sons de ambiente
func _sons(passo: float) -> void:
	var cs: Dictionary = _sub("sons")
	if not _liga("sons") or clima == null:
		Som.tocar_loop_ambiente("amb_grilos", 0.0)
		Som.tocar_loop_ambiente("amb_insetos_dia", 0.0)
		return
	var est := clampi(clima.estacao, 0, 3)
	var chuva := float(clima.valores.get("chuva", 0.0))
	var vivo := clampf(eco.saude(Vector2i(eco.foco.round())) * 1.6, 0.0, 1.0)      # chão morto, fábrica: quieto
	var perto := clampf(1.25 - (camera.distancia if camera != null else 30.0) / 90.0, 0.25, 1.0)
	var cala: float = 1.0 - float(fatores.silencio)
	var gr: Array = cs.get("grilos", [1, 1, 1, 0])
	var idia: Array = cs.get("insetos_dia", [1, 1, 1, 0])
	var luz := clima.luz_dia()
	var noite := clampf((0.4 - luz) / 0.2, 0.0, 1.0)
	var dia := clampf((luz - 0.5) / 0.2, 0.0, 1.0)
	Som.tocar_loop_ambiente("amb_grilos", 0.55 * noite * float(gr[est]) * (1.0 - 0.8 * chuva) * vivo * perto * cala)
	Som.tocar_loop_ambiente("amb_insetos_dia", 0.4 * dia * float(idia[est]) * (1.0 - chuva) * vivo * perto * cala)
	# sapos: beira d'água, depois da chuva, do entardecer à madrugada
	_t_sapo -= passo
	if _t_sapo > 0.0:
		return
	var faixa: Array = cs.get("sapo_s", [1.6, 4.5])
	_t_sapo = randf_range(float(faixa[0]), float(faixa[1]))
	if clima.molhado < float(cs.get("sapo_molhado", 0.25)) or luz > 0.55 or est == 3 or fatores.silencio > 0.5:
		return
	for tentativa in 12:
		var t := Vector2i((eco.foco + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 26.0)).round())
		if eco.gerador.eh_agua(eco.gerador.terreno(t)) or not eco.perto_da_agua(t, 1):
			continue
		if eco.saude_tile(t) < 0.3:
			continue
		Som.tocar("sapo", Grade.centro_mundo(t, 0.1), -4.0 + 4.0 * clima.molhado)
		return
