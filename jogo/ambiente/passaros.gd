class_name Passaros
extends RefCounted
## Pássaros nativos (patch fauna; lógica pura, posição em tiles e altura em metros). Bandos vivem em volta de onde a
## câmera olha, só onde a natureza está viva — quanto mais árvore e mato, mais bandos; fábrica, cinza e ácido
## espantam. Pequenos (pardelo, cobrico, azulão, rubro): voam até um lugar saudável, POUSAM (freando), ficam
## comendo/olhando em volta e cantando, DECOLAM (revoada) e seguem; às vezes exploram mais longe. Quem comeu em área
## saudável leva semente: voando sobre chão morto (queimado, sem vida), deixa cair e nasce uma muda
## (AmbienteVivo.plantar_perto) — os pássaros reflorestam. Fogem (FUGINDO) de fogo, monstro, rajada forte, trovão,
## tiro e explosão (`assustar`) e de construção nova perto. À noite pousam e dormem. Migram com a estação
## (fauna.json "estacoes"). O planador-cinza não pousa: CIRCULA alto em volta de um centro que deriva devagar.
## Em massa: bandos grandes (pardelo até ~30); dois bandos da mesma espécie que se cruzam no ar viram um só ("juntou").
## Eventos para o desenho/som: "revoada", "canto", "semente", "juntou".

enum E { VOANDO, POUSANDO, POUSADO, DECOLANDO, FUGINDO, CIRCULANDO }

const POUSO_S := 1.0          ## s da freada até as asas fecharem (animação "pousar")
const DECOLA_S := 0.7         ## s da decolagem (o "pousar" ao contrário)

var gerador: GeradorMundo
var mapa: MapaOcupacao
var ambiente: AmbienteVivo
var colonia: Colonia
var infestacao: Infestacao
var eco: Ecossistema                   ## fundação do patch fauna (saúde do chão, índice, eventos)
var bandos: Dictionary = {}           ## id → bando (ver _novo)
var eventos: Array[Dictionary] = []
var plantadas := 0                     ## mudas que os pássaros plantaram (contagem)
var _d: Dictionary
var _rng := RandomNumberGenerator.new()
var _prox := 1
var _t_nasce := 0.0
var _sustos: Array = []                ## [centro, raio] assustando neste passo


func _init(p_gerador: GeradorMundo, p_mapa: MapaOcupacao, p_ambiente: AmbienteVivo = null, p_colonia: Colonia = null,
		p_infestacao: Infestacao = null, semente := 31) -> void:
	gerador = p_gerador
	mapa = p_mapa
	ambiente = p_ambiente
	colonia = p_colonia
	infestacao = p_infestacao
	_rng.seed = semente
	_d = Registro.fauna
	eco = Ecossistema.new(gerador, mapa, ambiente, infestacao)     # o mundo troca pelo dele (o mesmo de todos)
	eco.registrar_fonte("passaro", para_ecossistema)


## Algo assustou (tiro, explosão, trovão, construção): os bandos no raio fogem dali.
func assustar(c: Vector2, raio: float) -> void:
	_sustos.append([c, maxf(raio, float(_d.medo.get("susto_min", 6)))])


func tick(dt: float, foco: Vector2, clima: Clima = null) -> void:
	_t_nasce -= dt
	if _t_nasce <= 0.0:
		_t_nasce = float(_d.get("nasce_s", 6.0))
		_povoar(foco, clima)
	var noite := clima != null and clima.luz_dia() < 0.15
	for id in bandos.keys():
		var b: Dictionary = bandos[id]
		if (b.pos as Vector2).distance_to(foco) > float(_d.raio_vida) * 1.4:
			bandos.erase(id)                               # saiu de perto: some (o mundo dele segue sem desenho)
			continue
		_bando(b, dt, foco, clima, noite)
	_juntar()
	_sustos.clear()


## Bandos da mesma espécie voando perto viram um só (o maior absorve o menor, até bando_max_n).
func _juntar() -> void:
	var ids := bandos.keys()
	for i in ids.size():
		var a: Dictionary = bandos.get(ids[i], {})
		if a.is_empty() or not int(a.estado) in [E.VOANDO, E.FUGINDO]:
			continue
		for j in range(i + 1, ids.size()):
			var b: Dictionary = bandos.get(ids[j], {})
			if b.is_empty() or b.especie != a.especie or not int(b.estado) in [E.VOANDO, E.FUGINDO]:
				continue
			if (a.pos as Vector2).distance_to(b.pos) > float(_d.get("junta_dist", 6.0)) or int(a.n) + int(b.n) > int(_d.get("bando_max_n", 40)):
				continue
			var fica: Dictionary = a if int(a.n) >= int(b.n) else b
			var sai: Dictionary = b if fica == a else a
			fica.n = int(fica.n) + int(sai.n)
			fica.sementes = maxi(int(fica.sementes), int(sai.sementes))
			bandos.erase(sai.id)
			eventos.append({"tipo": "juntou", "de": sai.id, "para": fica.id})
			if sai == a:
				break


# ------------------------------------------------------------------ população
func _fator_estacao(esp: String, clima: Clima) -> float:
	if clima == null:
		return 1.0
	var e: Array = _d.especies[esp].get("estacoes", [1, 1, 1, 1])
	return float(e[clampi(clima.estacao, 0, e.size() - 1)])


## Quantos bandos a região aguenta: a média de saúde em volta do foco (fábrica e cinza = poucos ou nenhum).
func lotacao(foco: Vector2) -> int:
	var soma := 0.0
	for i in 16:
		var p := foco + Vector2.from_angle(TAU * i / 16.0 + 0.3) * float(_d.raio_vida) * (0.25 + 0.6 * float(i % 4) / 3.0)
		soma += saude(Vector2i(p.floor()))
	var media := soma / 16.0
	return int(round(float(_d.bandos_max) * clampf((media - 0.12) / 0.45, 0.0, 1.0)))


func _povoar(foco: Vector2, clima: Clima) -> void:
	if clima != null and clima.luz_dia() < 0.2:
		return                                             # ninguém chega de noite
	if bandos.size() >= lotacao(foco):
		return
	var pesos := {}
	var conta := {}
	for b in bandos.values():
		conta[b.especie] = int(conta.get(b.especie, 0)) + 1
	var total := 0.0
	for esp in _d.especies:
		var s: Dictionary = _d.especies[esp]
		if int(conta.get(esp, 0)) >= int(s.get("max", 99)):
			continue
		pesos[esp] = float(s.peso) * _fator_estacao(esp, clima)
		total += pesos[esp]
	if total <= 0.0:
		return
	var r := _rng.randf() * total
	var esp := ""
	for k in pesos:
		r -= pesos[k]
		if r <= 0.0:
			esp = k
			break
	if esp == "":
		return
	var de := foco + Vector2.from_angle(_rng.randf() * TAU) * float(_d.raio_vida) * 0.9
	var b := _novo(esp, de)
	if esp == "planador":
		b.centro = foco + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(5.0, 25.0)
		b.estado = E.CIRCULANDO
		bandos[b.id] = b
		return
	var alvo: Variant = _lugar_bom(b, foco, foco, 30.0)
	if alvo == null:
		return                                             # nada vivo por perto: não vem ninguém
	b.destino = alvo
	b.pousar = true
	bandos[b.id] = b


func _novo(esp: String, pos: Vector2) -> Dictionary:
	var s: Dictionary = _d.especies[esp]
	var id := _prox
	_prox += 1
	var alt: Array = s.alt
	return {"id": id, "especie": esp, "n": _rng.randi_range(int(s.bando[0]), int(s.bando[1])), "pos": pos,
			"alt": _rng.randf_range(float(alt[0]), float(alt[1])), "alt_alvo": _rng.randf_range(float(alt[0]), float(alt[1])),
			"vel": Vector2.ZERO, "destino": pos, "pousar": false, "estado": E.VOANDO, "t": 0.0, "sementes": 0,
			"t_canto": _rng.randf_range(1.0, float(s.canto_s)), "t_olha": 0.0, "t_semente": 1.0, "dormindo": false,
			"centro": pos, "ang": _rng.randf() * TAU, "raio": _rng.randf_range(10.0, 16.0), "poleiros": []}


## Copas de árvore viva perto de `c` (até 4): [centro, altura da copa]. O bando pousa nelas (comendo fruta, à vista).
func poleiros_em(c: Vector2) -> Array:
	var out := []
	for j in range(-2, 3):
		for i in range(-2, 3):
			var t := Vector2i(c.floor()) + Vector2i(i, j)
			if mapa.limpos.has(t) or mapa.arvores.has(t):
				continue
			var o := gerador.distribuicao.obstaculo(t)
			if o.is_empty() or not Distribuicao.eh_arvore(o.nome) or Vector2i(o.ancora) != t:
				continue
			var dims: Array = Registro.modelos.get(o.nome, {}).get("dims", [1, 1, 2])
			out.append([Grade.centro_da_area(o.ancora, o.area, 0), float(dims[2]) * 0.92])
			if out.size() >= 4:
				return out
	return out


# ------------------------------------------------------------------ o lugar
## Saúde do chão, chão morto e fábrica perto: agora são do Ecossistema (fase 0 do patch fauna), o mesmo para todos
## os bichos. Os nomes ficam aqui para quem já usava (testes, desenho).
func saude(t: Vector2i) -> float:
	return eco.saude(t)


func _saude_tile(t: Vector2i) -> float:
	return eco.saude_tile(t)


func morto(t: Vector2i) -> bool:
	return eco.morto(t)


func _perto_de_construcao(t: Vector2i, r: int) -> bool:
	return eco.perto_de_construcao(t, r)


## Os bandos como o Ecossistema os vê (fonte "passaro"): posição, espécie e quantos.
func para_ecossistema() -> Array:
	var out: Array = []
	for b in bandos.values():
		out.append({"id": b.id, "pos": b.pos, "especie": b.especie, "n": b.n})
	return out


## Melhor lugar para pousar e comer perto de `de` (sorteia candidatos; longe de fábrica, fogo e monstro).
func _lugar_bom(b: Dictionary, de: Vector2, foco: Vector2, alcance: float) -> Variant:
	var melhor: Variant = null
	var nota := float(_d.saude_min)
	for i in 12:
		var p := de + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, alcance)
		if p.distance_to(foco) > float(_d.raio_vida):
			p = foco + (p - foco).limit_length(float(_d.raio_vida) * 0.8)
		var t := Vector2i(p.floor())
		if gerador.terreno(t) != GeradorMundo.Terreno.TERRA or _perto_de_construcao(t, int(_d.medo.construcao)):
			continue
		if _ameaca_em(p, 3.0) != null:
			continue
		var s := saude(t) + _rng.randf() * 0.05 + (0.3 if not poleiros_em(p).is_empty() else 0.0)   # gostam de árvore
		if s > nota:
			nota = s
			melhor = Vector2(t) + Vector2(0.5, 0.5)
	if melhor != null:
		b.poleiros = poleiros_em(melhor)
	return melhor


## Para onde voar sem pousar: longe, de preferência por cima de chão morto quando leva semente.
func _lugar_explorar(b: Dictionary, foco: Vector2) -> Vector2:
	var melhor := Vector2.ZERO
	var nota := -1.0
	for i in 8:
		var p := (b.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(14.0, 34.0)
		p = foco + (p - foco).limit_length(float(_d.raio_vida) * 0.85)
		var s := _rng.randf()
		if int(b.sementes) > 0 and morto(Vector2i(p.floor())):
			s += 1.0
		if s > nota:
			nota = s
			melhor = p
	return melhor


# ------------------------------------------------------------------ medo
## Algo assustador perto de `p` (dentro de `folga` além do raio de cada medo): devolve de onde vem, senão nulo.
func _ameaca_em(p: Vector2, folga := 0.0) -> Variant:
	for s in _sustos:
		if p.distance_to(s[0]) < float(s[1]) + folga:
			return s[0]
	var m: Dictionary = _d.medo
	if ambiente != null and not ambiente.fogo.is_empty():
		var r := float(m.fogo) + folga
		var n := 0
		for t: Vector2i in ambiente.fogo:
			if p.distance_to(Vector2(t)) < r:
				return Vector2(t)
			n += 1
			if n > 400:
				break
	if colonia != null:
		var r := float(m.monstro) + folga
		for ar in colonia.aranhas.values():
			if p.distance_to(ar.pos) < r:
				return ar.pos
	return null


func _fugir(b: Dictionary, de: Vector2, foco: Vector2) -> void:
	var dir := ((b.pos as Vector2) - de).normalized()
	if dir.length() < 0.1:
		dir = Vector2.from_angle(_rng.randf() * TAU)
	if b.estado == E.CIRCULANDO:
		b.centro = (b.centro as Vector2) + dir * 25.0
		return
	var era_chao: bool = b.estado in [E.POUSADO, E.POUSANDO]
	b.estado = E.FUGINDO
	b.destino = foco + ((b.pos as Vector2) + dir * _rng.randf_range(22.0, 32.0) - foco).limit_length(float(_d.raio_vida) * 0.9)
	b.pousar = false
	b.dormindo = false
	var alt: Array = _d.especies[b.especie].alt
	b.alt_alvo = float(alt[1]) * 1.3
	if era_chao or float(b.alt) < 2.0:
		eventos.append({"tipo": "revoada", "id": b.id, "pos": b.pos, "especie": b.especie})


# ------------------------------------------------------------------ um bando
func _bando(b: Dictionary, dt: float, foco: Vector2, clima: Clima, noite: bool) -> void:
	var s: Dictionary = _d.especies[b.especie]
	var some := _fator_estacao(b.especie, clima) <= 0.0      # migrou: vai embora (sai do raio e some)
	# medo (fogo, monstro, susto; rajada derruba de onde está)
	b.t_olha = float(b.t_olha) - dt
	if b.t_olha <= 0.0 or not _sustos.is_empty():
		b.t_olha = 0.5
		if b.estado != E.FUGINDO:
			var de: Variant = _ameaca_em(b.pos)
			if de == null and clima != null and clima.vento_em(b.pos) > float(_d.medo.rajada) and b.estado in [E.POUSADO, E.CIRCULANDO]:
				de = (b.pos as Vector2) - clima.direcao_vento * 10.0       # a rajada empurra: foge vento abaixo
			if de == null and b.estado == E.POUSADO and _perto_de_construcao(Vector2i((b.pos as Vector2).floor()), 3):
				de = b.pos                                                  # construíram do lado
			if de != null:
				_fugir(b, de, foco)
	match int(b.estado):
		E.CIRCULANDO:
			b.centro = (b.centro as Vector2) + Vector2.from_angle(float(b.ang) * 0.13) * 0.25 * dt
			if some or noite:
				b.centro = (b.centro as Vector2) + ((b.centro as Vector2) - foco).normalized() * 3.0 * dt
			b.ang = float(b.ang) + float(s.vel) / float(b.raio) * dt
			var alvo := (b.centro as Vector2) + Vector2.from_angle(float(b.ang)) * float(b.raio)
			_voar(b, alvo, float(s.vel), dt)
			b.alt = lerpf(float(b.alt), float(b.alt_alvo) + 2.0 * sin(float(b.ang) * 0.5), dt * 0.4)
			_cantar(b, s, dt, 0.4)
		E.VOANDO, E.FUGINDO:
			var vel := float(s.vel) * (1.6 if b.estado == E.FUGINDO else 1.0)
			var chegou := _voar(b, b.destino, vel, dt)
			b.alt = lerpf(float(b.alt), float(b.alt_alvo), dt * (1.2 if b.estado == E.FUGINDO else 0.5))
			_semear(b, dt)
			if chegou:
				if some:
					b.destino = foco + ((b.pos as Vector2) - foco).normalized() * float(_d.raio_vida) * 1.6
				elif b.pousar:
					b.estado = E.POUSANDO
					b.t = POUSO_S
				else:
					_seguir(b, foco, noite)
		E.POUSANDO:
			b.t = float(b.t) - dt
			b.alt = maxf(0.0, float(b.alt) * (1.0 - dt * 4.0) - dt * 2.0)
			b.vel = (b.vel as Vector2) * (1.0 - dt * 3.0)
			b.pos = (b.pos as Vector2) + (b.vel as Vector2) * dt
			if b.t <= 0.0:
				b.alt = 0.0
				b.vel = Vector2.ZERO
				b.estado = E.POUSADO
				var ps: Array = s.get("pousa_s", [10, 20])
				b.t = _rng.randf_range(float(ps[0]), float(ps[1])) * (6.0 if noite else 1.0)
				b.dormindo = noite
		E.POUSADO:
			b.t = float(b.t) - dt
			if noite:
				b.t = maxf(float(b.t), 2.0)                # dorme até o dia
				b.dormindo = true
				return
			b.dormindo = false
			_cantar(b, s, dt, 1.0)
			if b.t <= 0.0 or some:
				if bool(s.get("sementes", false)) and saude(Vector2i((b.pos as Vector2).floor())) >= float(_d.saude_min):
					b.sementes = int(_d.semente.por_bando)  # comeu fruta/semente aqui: leva
				b.estado = E.DECOLANDO
				b.t = DECOLA_S
				eventos.append({"tipo": "revoada", "id": b.id, "pos": b.pos, "especie": b.especie})
		E.DECOLANDO:
			b.t = float(b.t) - dt
			b.alt = float(b.alt) + dt * 3.0
			if b.t <= 0.0:
				_seguir(b, foco, noite)


## Próximo destino depois de decolar/chegar: comer num lugar bom (70%) ou explorar (30%); de noite, pousar.
func _seguir(b: Dictionary, foco: Vector2, noite: bool) -> void:
	var alt: Array = _d.especies[b.especie].alt
	b.estado = E.VOANDO
	b.alt_alvo = _rng.randf_range(float(alt[0]), float(alt[1]))
	var bom: Variant = null
	if noite or _rng.randf() < 0.7:
		bom = _lugar_bom(b, b.pos, foco, 26.0)
	if bom != null:
		b.destino = bom
		b.pousar = true
	else:
		b.destino = _lugar_explorar(b, foco)
		b.pousar = false


## Anda em direção a `alvo` com curva suave (a velocidade vira, não pula). Devolve true ao chegar.
func _voar(b: Dictionary, alvo: Vector2, vel: float, dt: float) -> bool:
	var d: Vector2 = alvo - (b.pos as Vector2)
	var quer := d.normalized() * vel * clampf(d.length() / 2.0, 0.35, 1.0)
	b.vel = (b.vel as Vector2).lerp(quer, clampf(dt * 2.5, 0.0, 1.0))
	b.pos = (b.pos as Vector2) + (b.vel as Vector2) * dt
	return d.length() < 0.8


## Semente: voando sobre chão morto, de vez em quando cai uma e nasce uma muda.
func _semear(b: Dictionary, dt: float) -> void:
	if int(b.sementes) <= 0 or ambiente == null:
		return
	b.t_semente = float(b.t_semente) - dt
	if b.t_semente > 0.0:
		return
	b.t_semente = 1.0
	var t := Vector2i((b.pos as Vector2).floor())
	if not morto(t) or _rng.randf() > float(_d.semente.chance_s):
		return
	var onde: Variant = ambiente.plantar_perto(b.pos, float(_d.semente.raio), true)
	if onde != null:
		b.sementes = int(b.sementes) - 1
		plantadas += 1
		eventos.append({"tipo": "semente", "id": b.id, "pos": Vector2(onde) + Vector2(0.5, 0.5), "de": b.pos,
				"alt": b.alt, "especie": b.especie})


func _cantar(b: Dictionary, s: Dictionary, dt: float, chance: float) -> void:
	b.t_canto = float(b.t_canto) - dt
	if b.t_canto > 0.0:
		return
	b.t_canto = _rng.randf_range(0.6, 1.6) * float(s.canto_s)
	if _rng.randf() < chance:
		eventos.append({"tipo": "canto", "id": b.id, "pos": b.pos, "alt": b.alt, "especie": b.especie, "som": s.canto})
