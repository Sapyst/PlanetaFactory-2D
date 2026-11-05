class_name Manadas
extends RefCounted
## Patch fauna, fase 9 (docs/PLANO_FAUNA.md), lógica pura: os herbívoros grandes, em manada (o galhudo).
##  manadas  nascem no campo aberto saudável e quieto (chão que já voltou até as árvores, longe da fábrica), a
##           nasce_min–nasce_max m da câmera: entram andando. Ficam no save; a que se afasta além de raio_sim vai
##           embora. Quantas cabem muda com a estação (no inverno, poucas).
##  rotina   pastam num lugar (cada bicho num canto da manada, cabeça baixa, às vezes alerta, anda um pouco e volta a
##           pastar); depois de um tempo a manada viaja junta para o próximo pasto.
##  migração na troca para o outono parte uma parte das manadas, junta, no rumo da migração dos pássaros, e some.
##  medo     predador nativo (o espreitando só é visto de perto), aranha e larva, fogo, susto (tiro, explosão, raio) e
##           máquina barulhenta: quem vê dá o alarme e a manada inteira dispara para o lado oposto por alguns
##           segundos, e depois fica alerta.
##  filhotes na primavera e no verão nascem filhotes (menores, andam perto da mãe) até max_n; crescem devagar.
##  morte    o predador pega um (`matar`), aranha e larva também; fogo no tile. Vira carcaça grande (fase 4).
## O desenho lê `bichos` (pos, rumo, estado, filhote) e `manadas` (estado: o galope soa na fuga).
## Eventos: "alarme", "nasceu", "partiu".

enum M { PASTO, VIAGEM, FUGA, MIGRA }
enum E { PASTANDO, ANDANDO, ALERTA, CORRENDO }

var eco: Ecossistema
var ambiente: AmbienteVivo
var manadas: Dictionary = {}     ## id → {id, especie, centro, alvo, estado: M, t, rumo, de: Vector2}
var bichos: Dictionary = {}      ## id → {id, manada, especie, pos, rumo, estado: E, t, lugar: Vector2, filhote, idade, mae}
var eventos: Array = []
var mortos: Dictionary = {}      ## id → s desde que morreu (o desenho deita o corpo)
var _sustos: Array = []
var _t_nasce := 0.0
var _t_medo := 0.0
var _estacao := -1
var _prox := 1
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo = null, semente := 131) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("manadas", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


func _faixa(chave: String, a: float, b: float) -> float:
	var f: Array = _d.get(chave, [a, b])
	return _rng.randf_range(float(f[0]), float(f[1]))


## Os herbívoros como o Ecossistema os vê (fonte "herbivoro").
func para_ecossistema() -> Array:
	var out: Array = []
	for b in bichos.values():
		out.append({"id": b.id, "pos": b.pos, "especie": String(b.especie), "n": 1})
	return out


func assustar(c: Vector2, raio: float) -> void:
	_sustos.append([c, raio])


## Um predador (ou aranha, larva) pegou o bicho: morre no próximo passo e vira carcaça.
func matar(id: int, causa := "") -> void:
	if bichos.has(id):
		bichos[id].morto = true
		bichos[id].causa = causa


static func corpo_id(id: int) -> String:
	return "herbivoro_%d" % id


## A manada dele está fugindo? (o predador que persegue sabe que foi visto)
func fugindo(id: int) -> bool:
	return bichos.has(id) and manadas.has(int(bichos[id].manada)) and int(manadas[int(bichos[id].manada)].estado) == M.FUGA


## O mais fácil de pegar a até `raio` de `p`: filhote primeiro, senão o que está mais longe do centro da manada.
func presa_perto(p: Vector2, raio: float) -> int:
	var melhor := -1
	var nota := -INF
	for b in bichos.values():
		var d := (b.pos as Vector2).distance_to(p)
		if d > raio or b.get("morto", false):
			continue
		var c: Vector2 = manadas[int(b.manada)].centro if manadas.has(int(b.manada)) else b.pos
		var v := (8.0 if bool(b.filhote) else 0.0) + (b.pos as Vector2).distance_to(c) - d * 0.15
		if v > nota:
			nota = v
			melhor = int(b.id)
	return melhor


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	eventos.clear()
	if not bool(_d.get("liga", true)):
		_sustos.clear()
		return
	eco.esquecer_passagem(dt)
	if clima != null and clima.estacao != _estacao:
		var antes := _estacao
		_estacao = clima.estacao
		if antes >= 0 and _estacao == 2:
			_partir(foco)
	_t_nasce -= dt
	if _t_nasce <= 0.0:
		_t_nasce = _n("nasce_s", 10.0)
		_nascer(clima, foco)
		_filhotes(clima)
	_t_medo -= dt
	if _t_medo <= 0.0 or not _sustos.is_empty():
		_t_medo = 0.25
		for m in manadas.values():
			_olhar(m)
	for m in manadas.values():
		_manada(m, dt)
	for b in bichos.values():
		_bicho(b, dt)
	_separar()
	for id in mortos.keys():
		mortos[id] = float(mortos[id]) + dt
		if float(mortos[id]) > 5.0:
			mortos.erase(id)
	var morreram: Array = bichos.values().filter(func(b): return b.get("morto", false) \
			or (ambiente != null and ambiente.fogo.has(Vector2i((b.pos as Vector2).floor()))))
	for b in morreram:
		bichos.erase(b.id)
		mortos[b.id] = 0.0
		eco.morreu("herbivoro", "herbivoro", b.pos, {"id": corpo_id(b.id), "variante": String(b.especie),
				"rumo": float(b.rumo), "causa": String(b.get("causa", "fogo")), "filhote": bool(b.filhote)})
	for m in manadas.values():                           # alarme de quem perdeu um: a manada foge do lugar
		if morreram.any(func(b): return int(b.manada) == int(m.id)) and int(m.estado) != M.MIGRA:
			_fugir(m, (morreram.filter(func(b): return int(b.manada) == int(m.id))[0].pos as Vector2))
	for id in manadas.keys():
		var m: Dictionary = manadas[id]
		var tem := bichos.values().any(func(b): return int(b.manada) == int(id))
		if not tem or (m.centro as Vector2).distance_to(foco) > _n("raio_sim", 150.0):
			_tirar(int(id))
	_sustos.clear()


# ------------------------------------------------------------------ nascer, partir
func _cabem(clima: Clima) -> int:
	var e: Array = _d.get("estacoes", [1.0, 1.0, 0.7, 0.35])
	var f := float(e[clampi(clima.estacao if clima != null else 0, 0, e.size() - 1)])
	return int(round(_n("max", 2) * f))


func _nascer(clima: Clima, foco: Vector2) -> void:
	var perto := manadas.values().filter(func(m): return (m.centro as Vector2).distance_to(foco) <= _n("raio_vida", 90.0) \
			and int(m.estado) != M.MIGRA)
	if perto.size() >= _cabem(clima):
		return
	for tentativa in 12:
		var p := foco + Vector2.from_angle(_rng.randf() * TAU) * _faixa("nasce_dist", 45.0, 85.0)
		if not bom_pasto(p):
			continue
		if manadas.values().any(func(m): return (m.centro as Vector2).distance_to(p) < _n("entre_manadas", 40.0)):
			continue
		nova_manada(p, "galhudo", clima != null and clima.estacao <= 1)
		return


func nova_manada(p: Vector2, especie := "galhudo", com_filhotes := true) -> int:
	var id := _prox
	_prox += 1
	manadas[id] = {"id": id, "especie": especie, "centro": p, "alvo": p, "estado": M.PASTO,
			"t": _faixa("pasto_s", 50.0, 110.0), "rumo": _rng.randf() * TAU, "de": p}
	var n := int(round(_faixa("por_manada", 4.0, 8.0)))
	var adultos: Array[int] = []
	for k in n:
		adultos.append(_novo_bicho(id, false, -1).id)
	if com_filhotes:
		for k in int(round(_faixa("filhotes", 0.0, 2.0))):
			_novo_bicho(id, true, adultos[_rng.randi() % adultos.size()])
	return id


func _novo_bicho(manada: int, filhote: bool, mae: int) -> Dictionary:
	var m: Dictionary = manadas[manada]
	var id := _prox
	_prox += 1
	var lugar := _lugar_novo()
	if mae >= 0 and bichos.has(mae):
		lugar = (bichos[mae].lugar as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 1.3
	var p: Vector2 = (m.centro as Vector2) + lugar
	if mae >= 0 and bichos.has(mae):
		p = (bichos[mae].pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 1.2
	var b := {"id": id, "manada": manada, "especie": String(m.especie), "pos": p, "rumo": _rng.randf() * TAU,
			"estado": E.PASTANDO, "t": _rng.randf_range(2.0, 10.0), "lugar": lugar, "filhote": filhote,
			"idade": 0.0 if filhote else 1.0, "mae": mae}
	bichos[id] = b
	return b


func _lugar_novo() -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * _n("espalha", 4.5)


## Primavera e verão: nascem filhotes perto de uma mãe (até max_n); o filhote cresce até virar adulto.
func _filhotes(clima: Clima) -> void:
	var passo := _n("nasce_s", 10.0)
	for b in bichos.values():
		if bool(b.filhote):
			b.idade = float(b.idade) + passo / maxf(1.0, _n("cresce_s", 1209600.0))
			if float(b.idade) >= 1.0:
				b.filhote = false
				b.idade = 1.0
	if clima == null or clima.estacao > 1:
		return
	for m in manadas.values():
		if int(m.estado) != M.PASTO:
			continue
		var meus := bichos.values().filter(func(b): return int(b.manada) == int(m.id))
		if meus.size() >= int(_n("max_n", 9)):
			continue
		if _rng.randf() > passo / maxf(1.0, _n("filhote_s", 600.0)):
			continue
		var maes := meus.filter(func(b): return not bool(b.filhote))
		if maes.is_empty():
			continue
		var f := _novo_bicho(int(m.id), true, int(maes[_rng.randi() % maes.size()].id))
		eventos.append({"tipo": "nasceu", "id": f.id, "pos": f.pos})


## Outono: parte das manadas vai embora junta no rumo da migração.
func _partir(foco: Vector2) -> void:
	var rumo := Passaros.rumo_migracao(2, false)
	for m in manadas.values():
		if _rng.randf() > _n("migra_chance", 0.6):
			continue
		m.estado = M.MIGRA
		m.alvo = (m.centro as Vector2) + rumo * _n("migra_dist", 220.0)
		m.t = 600.0
		eventos.append({"tipo": "partiu", "manada": m.id, "pos": m.centro})


func _tirar(id: int) -> void:
	for b in bichos.values().filter(func(b): return int(b.manada) == id):
		bichos.erase(b.id)
	manadas.erase(id)


# ------------------------------------------------------------------ chão
## Pasto bom: terra viva e quieta, campo aberto (poucas árvores), longe da fábrica e da água.
func bom_pasto(p: Vector2) -> bool:
	var tl := Vector2i(p.floor())
	if not livre(p) or eco.gerador.terreno(tl) != GeradorMundo.Terreno.TERRA:
		return false
	if eco.saude(tl) < _n("saude_min", 0.38) or eco.perto_de_construcao(tl, int(_n("longe_construcao", 10))):
		return false
	if eco.etapa_em(p) < Ecossistema.Rec.ARVORES or eco.disturbio(p) > _n("disturbio_max", 0.2):
		return false
	if eco.perto_da_agua(tl, 2):
		return false
	return eco.arvores_perto(p, 5.0).size() <= 2


func livre(p: Vector2) -> bool:
	return eco.passavel(p)


## Para onde ir a `dist` m (mais ou menos no rumo `ang`, se dado): um lugar bom com caminho livre.
func _destino(de: Vector2, dist: float, ang := INF, so_livre := false) -> Vector2:
	for tentativa in 16:
		var a := _rng.randf() * TAU if ang == INF else ang + _rng.randf_range(-0.5, 0.5) * (1.0 + tentativa * 0.15)
		var p := de + Vector2.from_angle(a) * dist * _rng.randf_range(0.8, 1.1)
		if (bom_pasto(p) or (so_livre and livre(p))) and eco.linha_passavel(de, p):
			return p
	return de


# ------------------------------------------------------------------ medo
## O que assusta em `p`: susto, predador (o espreitando só de perto), aranha/larva, fogo, máquina barulhenta.
func ameaca_em(p: Vector2) -> Variant:
	for s in _sustos:
		if p.distance_to(s[0]) < float(s[1]):
			return s[0]
	var md: Dictionary = _d.get("medo", {})
	for a in eco.perto(p, float(md.get("predador", 24.0)), "predador"):
		if bool(a.get("espreita", false)) and p.distance_to(a.pos) > float(md.get("predador_espreita", 10.0)):
			continue
		return a.pos
	var vista := float(Registro.inimigos.get("comportamento", {}).get("aranha", {}).get("caca", {}).get("vista", 3.0))
	for a in eco.perto(p, float(md.get("alien", 20.0)), "alien"):
		if bool(a.get("espreita", false)) and p.distance_to(a.pos) > vista * 1.5:
			continue
		return a.pos
	if ambiente != null and not ambiente.fogo.is_empty():
		var rf := float(md.get("fogo", 22.0))
		var n := 0
		for t: Vector2i in ambiente.fogo:
			if p.distance_to(Vector2(t) + Vector2(0.5, 0.5)) < rf:
				return Vector2(t) + Vector2(0.5, 0.5)
			n += 1
			if n > 300:
				break
	if eco.disturbio(p) > float(md.get("disturbio", 0.5)):
		return p + Vector2(0.1, 0.0)
	return null


func _olhar(m: Dictionary) -> void:
	if int(m.estado) == M.MIGRA:
		return
	for b in bichos.values():
		if int(b.manada) != int(m.id):
			continue
		var de: Variant = ameaca_em(b.pos)
		if de != null:
			if int(m.estado) != M.FUGA or (de as Vector2).distance_to(m.de) > 4.0:
				_fugir(m, de)
			else:
				m.t = maxf(float(m.t), _n("foge_s", 8.0) * 0.5)     # ainda está vendo: continua correndo
			return


func _fugir(m: Dictionary, de: Vector2) -> void:
	var c: Vector2 = m.centro
	var dir := c - de
	var ang := dir.angle() if dir.length() > 0.1 else _rng.randf() * TAU
	m.alvo = _destino(c, _n("foge_dist", 40.0), ang, true)
	if (m.alvo as Vector2) == c:
		m.alvo = _destino(c, _n("foge_dist", 40.0) * 0.6, ang + PI * 0.5, true)
	m.estado = M.FUGA
	m.de = de
	m.t = _n("foge_s", 8.0)
	for b in bichos.values():
		if int(b.manada) == int(m.id):
			b.estado = E.CORRENDO
	eventos.append({"tipo": "alarme", "manada": m.id, "pos": c})


# ------------------------------------------------------------------ a manada
func _manada(m: Dictionary, dt: float) -> void:
	m.t = float(m.t) - dt
	var c: Vector2 = m.centro
	match int(m.estado):
		M.PASTO:
			if float(m.t) <= 0.0:
				var alvo := _destino(c, _faixa("pasto_dist", 14.0, 34.0))
				if alvo != c:
					m.alvo = alvo
					m.estado = M.VIAGEM
				m.t = _faixa("pasto_s", 50.0, 110.0)
		M.VIAGEM, M.MIGRA:
			if _centro_anda(m, _n("vel_andar", 1.1), dt):
				m.estado = M.PASTO
				m.t = _faixa("pasto_s", 50.0, 110.0)
		M.FUGA:
			var chegou := _centro_anda(m, _n("vel_correr", 7.0), dt)
			if chegou or float(m.t) <= 0.0:
				m.estado = M.PASTO
				m.t = _faixa("pasto_s", 50.0, 110.0)
				for b in bichos.values():
					if int(b.manada) == int(m.id):
						b.estado = E.ALERTA
						b.t = _rng.randf_range(3.0, 6.0)


## O centro anda até o alvo (o rumo da manada); devolve se chegou.
func _centro_anda(m: Dictionary, vel: float, dt: float) -> bool:
	var c: Vector2 = m.centro
	var d: Vector2 = (m.alvo as Vector2) - c
	if d.length() < 0.5:
		return true
	# a manada não vai mais rápido que o mais lento dos seus (o filhote fica para trás e ela espera)
	var atraso := 0.0
	for b in bichos.values():
		if int(b.manada) == int(m.id):
			atraso = maxf(atraso, (b.pos as Vector2).distance_to(c + _lugar_de(m, b)))
	var v := vel * clampf(1.4 - atraso / 8.0, 0.35, 1.0)
	m.rumo = d.angle()
	m.centro = c + d.normalized() * minf(d.length(), v * dt)
	return ((m.alvo as Vector2) - (m.centro as Vector2)).length() < 0.5


## O canto do bicho na manada: espalhada pastando, junta (e alongada no rumo) viajando e correndo.
func _lugar_de(m: Dictionary, b: Dictionary) -> Vector2:
	var l: Vector2 = b.lugar
	if int(m.estado) == M.PASTO:
		return l
	var aperta := 0.55 if int(m.estado) == M.FUGA else 0.7
	var r := Vector2.from_angle(float(m.rumo))
	var lado := Vector2(-r.y, r.x)
	return (r * l.x * 1.4 + lado * l.y * 0.6) * aperta


# ------------------------------------------------------------------ um bicho
func _bicho(b: Dictionary, dt: float) -> void:
	if not manadas.has(int(b.manada)):
		return
	var m: Dictionary = manadas[int(b.manada)]
	b.t = float(b.t) - dt
	var escala := 1.0 if not bool(b.filhote) else lerpf(float(_n("filhote_escala", 0.6)), 1.0, float(b.idade))
	var alvo: Vector2 = (m.centro as Vector2) + _lugar_de(m, b)
	if bool(b.filhote) and bichos.has(int(b.mae)):     # o filhote anda colado na mãe
		alvo = (bichos[int(b.mae)].pos as Vector2) + Vector2.from_angle(float(bichos[int(b.mae)].rumo) + 2.3) * 1.4
	var d := (b.pos as Vector2).distance_to(alvo)
	match int(m.estado):
		M.FUGA:
			b.estado = E.CORRENDO
			# quem ficou para trás corre só um pouco mais; o filhote é mais lento (é ele que o predador pega)
			_andar(b, alvo, _n("vel_correr", 7.0) * (1.1 if d > 2.0 else 1.0) * (0.85 if bool(b.filhote) else 1.0), dt)
		M.VIAGEM, M.MIGRA:
			if d > 0.6:
				b.estado = E.ANDANDO if d < 6.0 else E.CORRENDO
				_andar(b, alvo, _n("vel_andar", 1.1) * (1.35 if d > 2.0 else 1.0) * (3.0 if d >= 6.0 else 1.0), dt)
			else:
				b.estado = E.ANDANDO
				b.rumo = lerp_angle(float(b.rumo), float(m.rumo), minf(1.0, dt * 2.0))
		M.PASTO:
			match int(b.estado):
				E.CORRENDO, E.ANDANDO:
					if _andar(b, alvo, _n("vel_pastando", 0.55) * (1.0 if d < 3.0 else 2.5), dt):
						b.estado = E.PASTANDO
						b.t = _rng.randf_range(5.0, 14.0)
				E.PASTANDO:
					if float(b.t) <= 0.0:
						if _rng.randf() < _n("alerta_chance", 0.25):
							b.estado = E.ALERTA
							b.t = _rng.randf_range(2.0, 4.0)
						else:
							b.lugar = _lugar_novo() if not bool(b.filhote) else b.lugar
							b.estado = E.ANDANDO
				E.ALERTA:
					if float(b.t) <= 0.0:
						b.estado = E.PASTANDO
						b.t = _rng.randf_range(4.0, 10.0)
	b.escala = escala


func _andar(b: Dictionary, alvo: Vector2, vel: float, dt: float) -> bool:
	return eco.andar_grande(b, alvo, vel, dt)


func _separar() -> void:
	eco.separar(bichos.values(), _n("entre_bichos", 1.3),
			func(a, b): return 0.75 if bool(a.filhote) or bool(b.filhote) else 1.0)


# ------------------------------------------------------------------ save
func estado() -> Dictionary:
	return {"manadas": manadas, "bichos": bichos, "prox": _prox, "rng": _rng.state, "estacao": _estacao}


func restaurar(d: Dictionary) -> void:
	manadas = {}
	for k in d.get("manadas", {}):
		var m: Dictionary = d.manadas[k]
		if int(m.estado) == M.FUGA:
			m.estado = M.PASTO
		manadas[int(k)] = m
	bichos = {}
	for k in d.get("bichos", {}):
		var b: Dictionary = d.bichos[k]
		b.manada = int(b.manada)
		b.mae = int(b.get("mae", -1))
		if int(b.estado) == E.CORRENDO:
			b.estado = E.PASTANDO
		bichos[int(k)] = b
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
	_estacao = int(d.get("estacao", -1))
