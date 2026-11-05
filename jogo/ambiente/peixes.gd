class_name Peixes
extends RefCounted
## Patch fauna, fase 9 (docs/PLANO_FAUNA.md), lógica pura: os peixes dos lagos (o couraça).
##  lagos   cada lago e lagoa perto da câmera (Hidrologia.lagos) tem uma população (0..1, começa cheia) e o quanto a
##          água está suja (AmbienteVivo.AGUA, média de pontos dentro). Fica no save (pela chave do centro).
##  pulos   de vez em quando um peixe pula fora d'água (arco curto, respingo na saída e na volta): mais com a
##          população cheia e no amanhecer/entardecer. `pulos` = os que estão no ar agora (o desenho anima o arco).
##  sujeira acima de `sujo_morre` a população cai e aparecem peixes mortos boiando de barriga para cima (carcaça
##          "peixe" no Ecossistema, com mosca); abaixo de `sujo_limpo` ela volta devagar (os peixes chegam pelo rio).
## Eventos: "pulo", "boiou".

var eco: Ecossistema
var ambiente: AmbienteVivo
var lagos: Dictionary = {}        ## chave (centro) → {centro, raio, tipo, pop, sujo, t_pulo, t_morto, pontos}
var pulos: Array = []             ## {id, de: Vector2, para: Vector2, alt, t, dur, rumo, lago}
var eventos: Array = []
var mortos := 0                   ## quantos morreram na água suja (contagem)
var _t_lagos := 0.0
var _prox := 1
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo = null, semente := 139) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("peixes", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


static func chave(centro: Vector2) -> String:
	return "%d,%d" % [roundi(centro.x), roundi(centro.y)]


static func corpo_id(n: int) -> String:
	return "peixe_%d" % n


## O tile é água de lago ou lagoa?
func _agua_de_lago(t: Vector2i) -> bool:
	var ter := eco.gerador.terreno(t)
	return ter == GeradorMundo.Terreno.LAGO or ter == GeradorMundo.Terreno.LAGOA


## Água funda o bastante para um peixe pular (a 1 tile da margem em toda volta).
func _longe_da_margem(t: Vector2i) -> bool:
	for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _agua_de_lago(t + o):
			return false
	return true


## Hora boa de peixe pular (amanhecer, entardecer): 1,6; meio-dia e noite: 0,6.
static func hora_fator(clima: Clima) -> float:
	if clima == null:
		return 1.0
	var h := clima.hora
	var c := maxf(1.0 - absf(h - 0.27) / 0.07, 1.0 - absf(h - 0.75) / 0.07)
	return 0.6 + clampf(c, 0.0, 1.0)


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	eventos.clear()
	for p in pulos:
		p.t = float(p.t) + dt
	pulos = pulos.filter(func(p): return float(p.t) < float(p.dur))
	if not bool(_d.get("liga", true)):
		return
	_t_lagos -= dt
	if _t_lagos <= 0.0:
		_t_lagos = _n("lagos_s", 5.0)
		_achar_lagos(foco)
	var raio := _n("raio_vida", 45.0)
	for lg in lagos.values():
		var perto := (lg.centro as Vector2).distance_to(foco) - float(lg.raio) <= raio
		_cuidar(lg, dt)
		if not perto or (lg.pontos as Array).is_empty():
			continue
		_pular(lg, dt, clima)
		_boiar(lg, dt)


## Lagos perto da câmera; os que ficaram longe saem (a população fica guardada em `lagos` até sair do raio grande).
func _achar_lagos(foco: Vector2) -> void:
	var r := int(_n("raio_vida", 45.0)) + 20
	var c := Vector2i(foco.floor())
	var achados := {}
	for lg in eco.gerador.hidro.lagos(c - Vector2i(r, r), c + Vector2i(r, r)):
		var k := chave(lg.centro)
		achados[k] = true
		if not lagos.has(k):
			lagos[k] = {"centro": lg.centro, "raio": float(lg.raio), "tipo": int(lg.tipo), "pop": 1.0, "sujo": 0.0,
					"t_pulo": _rng.randf_range(2.0, 8.0), "t_morto": _n("boia_s", 25.0), "pontos": []}
		if (lagos[k].pontos as Array).is_empty():
			lagos[k].pontos = _pontos_de(lagos[k])
	for k in lagos.keys():
		if not achados.has(k) and (lagos[k].centro as Vector2).distance_to(foco) > _n("raio_sim", 160.0):
			lagos.erase(k)


## Pontos de água funda dentro do lago (para pular e boiar; e onde a sujeira é medida).
func _pontos_de(lg: Dictionary) -> Array:
	var out: Array = []
	var r := float(lg.raio)
	for k in 48:
		var q: Vector2 = (lg.centro as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * r
		var t := Vector2i(q.floor())
		if _longe_da_margem(t):
			out.append(Vector2(t) + Vector2(0.5, 0.5))
		if out.size() >= 14:
			break
	return out


## A sujeira da água (média dos pontos) e o que ela faz com a população.
func _cuidar(lg: Dictionary, dt: float) -> void:
	var pts: Array = lg.pontos
	if ambiente != null and not pts.is_empty():
		var s := 0.0
		for q: Vector2 in pts:
			s += ambiente.valor(Vector2i(q.floor()), AmbienteVivo.AGUA)
		lg.sujo = s / pts.size()
	if float(lg.sujo) >= _n("sujo_morre", 0.35):
		lg.pop = maxf(0.0, float(lg.pop) - dt / maxf(1.0, _n("morre_s", 600.0)) * (float(lg.sujo) / _n("sujo_morre", 0.35)))
	elif float(lg.sujo) <= _n("sujo_limpo", 0.12):
		lg.pop = minf(1.0, float(lg.pop) + dt / maxf(1.0, _n("volta_s", 2400.0)))


func _pular(lg: Dictionary, dt: float, clima: Clima) -> void:
	lg.t_pulo = float(lg.t_pulo) - dt
	if float(lg.t_pulo) > 0.0:
		return
	var taxa := _n("pulos_por_min", 4.0) * float(lg.pop) * hora_fator(clima) * clampf(float(lg.raio) / 10.0, 0.5, 1.5)
	if float(lg.sujo) >= _n("sujo_morre", 0.35):
		taxa *= 0.2                                         # na água suja eles quase não pulam
	lg.t_pulo = 60.0 / maxf(0.05, taxa) * _rng.randf_range(0.5, 1.5)
	if taxa < 0.05 or pulos.size() >= int(_n("max_no_ar", 3)):
		return
	pular_em(lg)


## Um peixe pula agora num ponto fundo do lago.
func pular_em(lg: Dictionary) -> Dictionary:
	var pts: Array = lg.pontos
	if pts.is_empty():
		return {}
	var de: Vector2 = (pts[_rng.randi() % pts.size()] as Vector2) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
	var rumo := _rng.randf() * TAU
	var dist := _rng.randf_range(float(_d.get("pulo_dist", [0.7, 1.5])[0]), float(_d.get("pulo_dist", [0.7, 1.5])[1]))
	var para := de + Vector2.from_angle(rumo) * dist
	if not _agua_de_lago(Vector2i(para.floor())):
		para = de - Vector2.from_angle(rumo) * dist
		rumo += PI
	var alt := _rng.randf_range(float(_d.get("pulo_alt", [0.3, 0.75])[0]), float(_d.get("pulo_alt", [0.3, 0.75])[1]))
	var p := {"id": _prox, "de": de, "para": para, "alt": alt, "t": 0.0, "dur": 0.45 + alt * 0.45, "rumo": rumo,
			"lago": chave(lg.centro), "especie": "couraca"}
	_prox += 1
	pulos.append(p)
	eventos.append({"tipo": "pulo", "pos": de, "para": para, "id": p.id})
	return p


## Água suja: de tempos em tempos um peixe morto sobe e boia (vira carcaça na água).
func _boiar(lg: Dictionary, dt: float) -> void:
	if float(lg.sujo) < _n("sujo_morre", 0.35) or float(lg.pop) <= 0.02:
		return
	lg.t_morto = float(lg.t_morto) - dt
	if float(lg.t_morto) > 0.0:
		return
	lg.t_morto = _n("boia_s", 25.0) * _rng.randf_range(0.6, 1.4) / clampf(float(lg.sujo) / _n("sujo_morre", 0.35), 1.0, 3.0)
	boiar_em(lg)


func boiar_em(lg: Dictionary) -> Vector2:
	var pts: Array = lg.pontos
	if pts.is_empty():
		return Vector2.INF
	var p: Vector2 = (pts[_rng.randi() % pts.size()] as Vector2) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
	mortos += 1
	lg.pop = maxf(0.0, float(lg.pop) - _n("por_morto", 0.03))
	var id := corpo_id(_prox)
	_prox += 1
	eco.morreu("peixe", "peixe", p, {"id": id, "variante": "couraca", "rumo": _rng.randf() * TAU, "causa": "agua_suja"})
	eventos.append({"tipo": "boiou", "pos": p, "id": id})
	return p


## Onde o peixe está no pulo (posição no chão, altura acima da água 0..alt, inclinação: + subindo).
static func no_ar(p: Dictionary) -> Array:
	var u := clampf(float(p.t) / float(p.dur), 0.0, 1.0)
	var pos: Vector2 = (p.de as Vector2).lerp(p.para, u)
	var h := 4.0 * float(p.alt) * u * (1.0 - u)
	var incl := atan2(4.0 * float(p.alt) * (1.0 - 2.0 * u), (p.de as Vector2).distance_to(p.para))
	return [pos, h, incl]


func estado() -> Dictionary:
	var pop := {}
	for k in lagos:
		pop[k] = {"centro": lagos[k].centro, "raio": lagos[k].raio, "tipo": lagos[k].tipo, "pop": lagos[k].pop}
	return {"lagos": pop, "mortos": mortos, "prox": _prox, "rng": _rng.state}


func restaurar(d: Dictionary) -> void:
	lagos = {}
	var l: Dictionary = d.get("lagos", {})
	for k in l:
		var lg: Dictionary = l[k]
		lagos[String(k)] = {"centro": lg.centro, "raio": float(lg.raio), "tipo": int(lg.get("tipo", 0)), "pop": float(lg.pop),
				"sujo": 0.0, "t_pulo": _rng.randf_range(2.0, 8.0), "t_morto": _n("boia_s", 25.0), "pontos": []}
	mortos = int(d.get("mortos", 0))
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
	pulos.clear()
