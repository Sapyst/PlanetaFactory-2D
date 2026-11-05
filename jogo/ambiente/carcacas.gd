class_name Carcacas
extends RefCounted
## Patch fauna, fase 4 (docs/PLANO_FAUNA.md), lógica pura: o ciclo da morte. Quem produz a morte avisa o Ecossistema
## (`morreu`); aqui o corpo fica no lugar.
##  carcaça   bicho de carne (a larva hoje; rato e pássaro nas próximas fases) vira comida "carcaca" no Ecossistema e
##            apodrece em etapas pela idade: inteiro → inchado → restos → some. Enquanto tem carne atrai moscas
##            (`moscas`) e o planador, que desce e circula baixo por cima. Quando some, aduba o chão em volta
##            (Ecossistema.fertil).
##  sucata    a aranha é máquina: o corpo vira sucata. Fumega no começo, vaza óleo no chão (AmbienteVivo), enferruja,
##            desmonta e afunda no capim. Não tem mosca nem adubo.
## Perto de `max` de cada tipo, a mais velha some primeiro (combate grande não enche o mapa de corpos).

enum Etapa { INTEIRO, INCHADO, RESTOS }

var eco: Ecossistema
var ambiente: AmbienteVivo
var sucatas: Array = []          ## {id, especie, pos: Vector2, ang, idade, vida, bicho}
var t := 0.0
var _prox := 1
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo = null, semente := 97) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("carcacas", {})


## O corpo dessa espécie fica no chão? (o desenho pergunta antes de deixar o corpo sumir)
static func fica_corpo(especie: String) -> bool:
	var d: Dictionary = Registro.fauna.get("carcacas", {})
	return bool(d.get("liga", true)) and d.get("tipos", {}).has(especie)


func _tipo(especie: String) -> Dictionary:
	return _d.get("tipos", {}).get(especie, {})


func tick(dt: float) -> void:
	t += dt
	if not bool(_d.get("liga", true)):
		return
	for ev in eco.eventos:
		if ev.tipo == "morreu":
			morreu(String(ev.especie), ev.pos, ev.get("id", -1))
		elif ev.tipo == "apodreceu" and ev.comida == "carcaca":
			var c := _tipo(String(ev.especie))
			eco.adubar(ev.pos, float(_d.get("adubo_raio", 1.6)), float(c.get("adubo", 0.6)))
	# a carne incha e vaza: o chão embaixo escurece (molhado de podridão), uma vez por carcaça
	if ambiente != null:
		for f in eco.comida.values():
			if f.tipo == "carcaca" and not f.get("vazou", false) and etapa(f) == Etapa.INCHADO:
				f.vazou = true
				var tl := Vector2i((f.pos as Vector2).floor())
				for y in range(-1, 2):
					for x in range(-1, 2):
						ambiente.somar(tl + Vector2i(x, y), AmbienteVivo.SUJ, float(_tipo(String(f.especie)).get("mancha", 0.25)) * (1.0 if x == 0 and y == 0 else 0.5))
	var some := false
	for s in sucatas:
		s.idade = float(s.idade) + dt
		some = some or float(s.idade) >= float(s.vida)
	if some:
		sucatas = sucatas.filter(func(s): return float(s.idade) < float(s.vida))


## O corpo de quem morreu fica: carcaça (carne) ou sucata (máquina). Devolve o id (0 = espécie sem corpo).
func morreu(especie: String, pos: Vector2, bicho: Variant = -1) -> int:
	var c := _tipo(especie)
	if c.is_empty():
		return 0
	var vida := float(c.get("vida_s", 1200.0)) * _rng.randf_range(0.85, 1.15)
	var ang := _rng.randf() * TAU
	if bool(c.get("sucata", false)):
		_limitar_sucatas(especie)
		var id := _prox
		_prox += 1
		sucatas.append({"id": id, "especie": especie, "pos": pos, "ang": ang, "idade": 0.0, "vida": vida, "bicho": bicho})
		if ambiente != null and float(c.get("oleo", 0.0)) > 0.0:
			var tl := Vector2i(pos.floor())                 # o óleo da hidráulica vaza no chão embaixo
			for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				ambiente.somar(tl + o, AmbienteVivo.OLEO, float(c.oleo) * (1.0 if o == Vector2i.ZERO else 0.4))
		return id
	_limitar_carcacas(especie)
	var idc := eco.por_comida("carcaca", pos, float(c.get("valor", 1.0)))
	var f: Dictionary = eco.comida[idc]
	f.especie = especie
	f.vida = vida
	f.ang = ang
	f.bicho = bicho
	return idc


func _limitar_sucatas(especie: String) -> void:
	var mx := int(_tipo(especie).get("max", 40))
	var minhas := sucatas.filter(func(s): return s.especie == especie and float(s.idade) < float(s.vida) - 9.0)
	if minhas.size() >= mx:
		minhas.sort_custom(func(a, b): return float(a.idade) > float(b.idade))
		var velha: Dictionary = minhas[0]
		velha.idade = maxf(float(velha.idade), float(velha.vida) - 8.0)   # some afundando em alguns segundos


func _limitar_carcacas(especie: String) -> void:
	var mx := int(_tipo(especie).get("max", 40))
	var minhas := eco.comida.values().filter(func(f): return f.tipo == "carcaca" and f.especie == especie \
			and float(f.idade) < float(f.vida) - 9.0)
	if minhas.size() >= mx:
		minhas.sort_custom(func(a, b): return float(a.idade) > float(b.idade))
		var velha: Dictionary = minhas[0]
		velha.idade = maxf(float(velha.idade), float(velha.vida) - 8.0)


## Etapa pela fração da vida (`etapas` = onde começa o inchado e onde começam os restos).
func etapa(f: Dictionary) -> int:
	var e: Array = _tipo(String(f.especie)).get("etapas", [0.3, 0.7])
	var k := float(f.idade) / maxf(float(f.vida), 1.0)
	return Etapa.INTEIRO if k < float(e[0]) else (Etapa.INCHADO if k < float(e[1]) else Etapa.RESTOS)


## 0..1 dentro da vida: 0 recém-morta, 1 sumindo.
static func idade_rel(f: Dictionary) -> float:
	return clampf(float(f.idade) / maxf(float(f.vida), 1.0), 0.0, 1.0)


## Quantas moscas querem estar ali agora (0..1): carne inteira atrai, o inchado é o auge, os restos quase nada.
func moscas(f: Dictionary) -> float:
	if f.get("tipo", "") != "carcaca" or not bool(_tipo(String(f.especie)).get("moscas", false)):
		return 0.0
	match etapa(f):
		Etapa.INTEIRO:
			return lerpf(0.25, 0.7, idade_rel(f) / 0.3)
		Etapa.INCHADO:
			return 1.0
	return 0.15


## Carcaças com carne (inteiro ou inchado) a até `raio` de `c`: o que o carniceiro procura.
func com_carne(c: Vector2, raio: float) -> Array:
	return eco.comida_perto(c, raio, "carcaca").filter(func(f): return etapa(f) != Etapa.RESTOS)


## Afundando no fim da vida (0..1): a sucata e os restos somem no capim, sem sumir do nada.
static func afunda(f: Dictionary, s := 8.0) -> float:
	return clampf((float(f.idade) - (float(f.vida) - s)) / s, 0.0, 1.0)


func estado() -> Dictionary:
	return {"sucatas": sucatas, "t": t, "prox": _prox, "rng": _rng.state}


func restaurar(d: Dictionary) -> void:
	sucatas = d.get("sucatas", [])
	t = float(d.get("t", 0.0))
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
