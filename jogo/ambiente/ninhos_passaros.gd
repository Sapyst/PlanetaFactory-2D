class_name NinhosPassaros
extends RefCounted
## Patch fauna, fase 6 (docs/PLANO_FAUNA.md), lógica pura: os ninhos dos pássaros pequenos nas árvores.
## Na primavera e no começo do verão, um bando que pousa nas copas às vezes faz ninho numa delas (um por árvore, longe
## de outro ninho e de construção, em chão saudável). O ninho passa por:
##   OBRA      o casal leva graveto e capim (visitas); o desenho faz o ninho crescer;
##   OVOS      quieto;
##   FILHOTES  piam (som perto da câmera) e os adultos do bando vêm trazer comida (visitas);
##   VAZIO     os filhotes voaram: entram no bando da espécie mais perto (ou saem como um bando novo).
## Vazio na primavera/verão, o ninho é usado de novo quando a espécie volta; no inverno, o ninho velho desmancha e cai.
## Se a árvore some (cortada, queimada, caída, corroída), pega fogo ou encostam construção, o ninho cai junto.
## Os bandos gostam de ficar perto dos ninhos da espécie (Passaros._lugar_bom).
## Eventos para o desenho/som: "novo", "fase", "visita", "voaram", "caiu".

enum F { OBRA, OVOS, FILHOTES, VAZIO }

var passaros: Passaros
var ninhos: Dictionary = {}          ## tile da árvore (Vector2i) → {id, tile, arvore, pos, alto, especie, tipo, n, fase, t,
                                     ##   idade, ovos, ninhadas, t_visita}
var eventos: Array = []
var _d: Dictionary
var _rng := RandomNumberGenerator.new()
var _prox := 1
var _t := 0.0


func _init(p_passaros: Passaros, semente := 211) -> void:
	passaros = p_passaros
	passaros.ninhos = self
	_rng.seed = semente
	_d = Registro.fauna.get("ninhos", {})


func _n(k: String, padrao: float) -> float:
	return float(_d.get(k, padrao))


func _faixa(k: String, padrao: Array) -> float:
	var a: Array = _d.get(k, padrao)
	return _rng.randf_range(float(a[0]), float(a[1]))


## Há ninho da espécie a até `raio` de `p`? (o bando prefere pousar perto)
func da_especie_perto(esp: String, p: Vector2, raio: float) -> bool:
	for n in ninhos.values():
		if n.especie == esp and (n.pos as Vector2).distance_to(p) <= raio:
			return true
	return false


func perto(c: Vector2, raio: float) -> Array:
	return ninhos.values().filter(func(n): return (n.pos as Vector2).distance_to(c) <= raio)


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	if not bool(_d.get("liga", true)):
		return
	var dia := clima == null or clima.luz_dia() >= 0.2
	var est := clima.estacao if clima != null else 0
	for t in ninhos.keys():
		if ninhos.has(t):
			_avancar(ninhos[t], dt, est, dia)
	_t -= dt
	if _t <= 0.0:
		_t = _n("olha_s", 2.0)
		_conferir()
		_fazer(est, dia, foco)


func _avancar(n: Dictionary, dt: float, est: int, dia: bool) -> void:
	n.idade = float(n.idade) + dt
	n.t = float(n.t) + dt
	match int(n.fase):
		F.OBRA:
			_visitas(n, dt, dia, "graveto")
			if n.t >= _n("obra_s", 240.0):
				_fase(n, F.OVOS)
				var o: Array = _d.get("ovos", [2, 4])
				n.ovos = _rng.randi_range(int(o[0]), int(o[1]))
		F.OVOS:
			if n.t >= _n("ovos_s", 600.0):
				_fase(n, F.FILHOTES)
		F.FILHOTES:
			_visitas(n, dt, dia, "comida")
			if n.t >= _n("filhotes_s", 600.0):
				_voar(n)
				_fase(n, F.VAZIO)
		F.VAZIO:
			# no inverno o ninho velho (vazio há tempo) desmancha e cai
			if est == 3 and n.t >= _n("velho_s", 3600.0) and _rng.randf() < dt / maxf(1.0, _n("cai_s", 600.0)):
				_cair(n, "velho")


func _fase(n: Dictionary, f: int) -> void:
	n.fase = f
	n.t = 0.0
	eventos.append({"tipo": "fase", "tile": n.tile, "id": n.id, "fase": f, "pos": n.pos})


## Um adulto do bando da espécie (se houver um perto, de dia) vem ao ninho: com graveto (obra) ou comida (filhotes).
func _visitas(n: Dictionary, dt: float, dia: bool, leva: String) -> void:
	n.t_visita = float(n.get("t_visita", 0.0)) - dt
	if n.t_visita > 0.0 or not dia:
		return
	n.t_visita = _faixa("visita_s", [12, 25])
	var b := _bando_perto(n, _n("visita_raio", 40.0))
	if not b.is_empty():
		eventos.append({"tipo": "visita", "tile": n.tile, "id": n.id, "pos": n.pos, "alto": n.alto, "especie": n.especie,
				"bando": b.id, "de": b.pos, "leva": leva})


func _bando_perto(n: Dictionary, raio: float) -> Dictionary:
	var melhor: Dictionary = {}
	var dm := raio
	for b in passaros.bandos.values():
		if b.especie != n.especie or bool(b.get("migra", false)):
			continue
		var d := (b.pos as Vector2).distance_to(n.pos)
		if d < dm:
			dm = d
			melhor = b
	return melhor


## Os filhotes voam: entram no bando da espécie mais perto; sem bando por perto, saem como um bando novo.
func _voar(n: Dictionary) -> void:
	var qt := int(n.get("ovos", 2))
	n.ninhadas = int(n.get("ninhadas", 0)) + 1
	if qt <= 0:
		return
	var b := _bando_perto(n, float(passaros._d.raio_vida))
	if not b.is_empty():
		b.n = mini(int(b.n) + qt, int(passaros._d.get("bando_max_n", 40)))
	else:
		b = passaros._novo(String(n.especie), n.pos)
		b.n = qt
		b.alt = float(n.alto)
		b.alt_alvo = b.alt + 3.0
		b.estado = Passaros.E.VOANDO
		b.destino = (n.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 12.0
		b.pousar = false
		passaros.bandos[b.id] = b
	eventos.append({"tipo": "voaram", "tile": n.tile, "id": n.id, "pos": n.pos, "alto": n.alto, "especie": n.especie,
			"n": qt, "para": b.id})


## A árvore do ninho ainda está de pé, sem fogo e sem construção encostada?
func _conferir() -> void:
	var eco := passaros.eco
	var amb := passaros.ambiente
	for t in ninhos.keys():
		var n: Dictionary = ninhos[t]
		var motivo := ""
		if eco.arvore_em(t) == "":
			motivo = "arvore"
		elif amb != null and amb.fogo.has(t):
			motivo = "fogo"
		elif eco.perto_de_construcao(t, int(_n("cai_construcao", 2))):
			motivo = "construcao"
		if motivo != "":
			_cair(n, motivo)


func _cair(n: Dictionary, motivo: String) -> void:
	ninhos.erase(n.tile)
	eventos.append({"tipo": "caiu", "tile": n.tile, "id": n.id, "pos": n.pos, "alto": n.alto, "fase": n.fase,
			"especie": n.especie, "tipo_ninho": n.tipo, "n": n.n, "arvore": n.arvore, "motivo": motivo})


## Bandos pousados nas copas (primavera e começo do verão, de dia) às vezes fazem ninho: reaproveitam o ninho vazio
## da espécie numa dessas árvores ou fazem um novo numa árvore livre, longe de outro ninho e de construção.
func _fazer(est: int, dia: bool, foco: Vector2) -> void:
	if not dia:
		return
	var fe: Array = _d.get("estacoes", [1.0, 0.6, 0.0, 0.0])
	var k := float(fe[est % fe.size()])
	if k <= 0.0:
		return
	var raio := float(passaros._d.raio_vida)
	var ativos := perto(foco, raio).filter(func(n): return int(n.fase) != F.VAZIO).size()
	for b in passaros.bandos.values():
		if ativos >= int(_n("max", 8)):
			return
		if int(b.estado) != Passaros.E.POUSADO or bool(b.get("migra", false)):
			continue
		var tipo := String(passaros._d.especies[b.especie].get("ninho", ""))
		var pol: Array = b.get("poleiros", [])
		if tipo == "" or pol.is_empty() or _rng.randf() > _n("chance_s", 0.04) * k:
			continue
		var feito := false
		for p in pol:                                     # o vazio da espécie, de novo
			var t: Vector2i = p[2] if p.size() > 2 else Vector2i((p[0] as Vector2).floor())
			var v: Dictionary = ninhos.get(t, {})
			if not v.is_empty() and v.especie == b.especie and int(v.fase) == F.VAZIO:
				v.t_visita = 0.0
				_fase(v, F.OBRA)
				v.t = _n("obra_s", 240.0) * 0.7               # só uma reforma
				if v.tipo == "bolsa":
					v.n = mini(int(v.n) + 1, int(_n("bolsas_max", 3)))
				feito = true
				break
		if feito:
			ativos += 1
			continue
		for p in pol:
			if p.size() < 4:
				continue
			var t: Vector2i = p[2]
			if ninhos.has(t) or not _lugar_ok(t, p[0]):
				continue
			var n := {"id": _prox, "tile": t, "arvore": String(p[3]), "pos": p[0], "alto": float(p[1]), "especie": b.especie,
					"tipo": tipo, "n": _rng.randi_range(1, int(_n("bolsas_max", 3))) if tipo == "bolsa" else 1,
					"fase": F.OBRA, "t": 0.0, "idade": 0.0, "ovos": 0, "ninhadas": 0, "t_visita": 1.0}
			_prox += 1
			ninhos[t] = n
			eventos.append({"tipo": "novo", "tile": t, "id": n.id, "pos": n.pos, "alto": n.alto, "especie": n.especie,
					"tipo_ninho": tipo})
			ativos += 1
			break


func _lugar_ok(t: Vector2i, pos: Vector2) -> bool:
	var eco := passaros.eco
	if eco.arvore_em(t) == "" or eco.perto_de_construcao(t, int(_n("longe_construcao", 6))):
		return false
	if eco.saude(t) < float(passaros._d.saude_min) + _n("saude_extra", 0.1):
		return false
	for n in ninhos.values():
		if (n.pos as Vector2).distance_to(pos) < _n("dist_min", 5.0):
			return false
	return true


# ------------------------------------------------------------------ salvamento
func estado() -> Dictionary:
	return {"ninhos": ninhos, "prox": _prox, "rng": _rng.state}


func restaurar(d: Dictionary) -> void:
	ninhos = {}
	var nn: Dictionary = d.get("ninhos", {})
	for k in nn:
		var n: Dictionary = nn[k]
		ninhos[Vector2i(n.tile)] = n
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
