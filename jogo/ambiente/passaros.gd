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
## Fase 6 do patch fauna (pássaros completos):
##  morte   explosão e raio derrubam quem está perto e baixo; velhice e doença (chão envenenado, inverno) levam um de
##          vez em quando. O corpo cai e vira carcaça (Ecossistema.morreu → Carcacas), como o rato e a larva.
##  planador desce em espiral na carcaça com carne, POUSA do lado e come (a carne acaba mais rápido: Carcacas.bicar);
##          e caça rato em campo aberto: MERGULHA, o rato pode ver e correr para a toca; se pega, pousa e come.
##  migração na janela de troca de estação passam revoadas grandes e altas (MIGRANDO) das espécies que vão embora,
##          e as que chegam vêm num bando grande que desce e fica; na troca, quem vai embora sobe e parte junto.
## Eventos para o desenho/som: "revoada", "canto", "semente", "juntou", "morreu", "mergulho", "migracao".

enum E { VOANDO, POUSANDO, POUSADO, DECOLANDO, FUGINDO, CIRCULANDO, MERGULHANDO, MIGRANDO }

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
var carcacas: Carcacas                 ## patch fauna, fase 4: o planador desce e circula por cima da carne (o mundo põe)
var ratos: Ratos                       ## fase 6: o planador caça rato em campo aberto (o mundo põe)
var ninhos: NinhosPassaros             ## fase 6: os bandos ficam perto dos ninhos da espécie (o mundo põe)
var plantadas := 0                     ## mudas que os pássaros plantaram (contagem)
var mortes := 0                        ## fase 6: pássaros que morreram (contagem)
var _prox_corpo := 1
var _t_morte := 0.0
var _t_mig := 0.0
var _estacao := -1
var _sessao := randi() % 100000                ## os corpos de pássaro não se repetem entre sessões (não são salvos)
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
	_migrar(dt, foco, clima, noite)
	for id in bandos.keys():
		var b: Dictionary = bandos[id]
		if (b.pos as Vector2).distance_to(foco) > float(_d.raio_vida) * 1.4:
			bandos.erase(id)                               # saiu de perto: some (o mundo dele segue sem desenho)
			continue
		_bando(b, dt, foco, clima, noite)
	_juntar()
	_morrer_de_velho(dt, clima)
	_sustos.clear()


## Bandos da mesma espécie voando perto viram um só (o maior absorve o menor, até bando_max_n).
func _juntar() -> void:
	var ids := bandos.keys()
	for i in ids.size():
		var a: Dictionary = bandos.get(ids[i], {})
		if a.is_empty() or not int(a.estado) in [E.VOANDO, E.FUGINDO] or bool(a.get("migra", false)):
			continue
		for j in range(i + 1, ids.size()):
			var b: Dictionary = bandos.get(ids[j], {})
			if b.is_empty() or b.especie != a.especie or not int(b.estado) in [E.VOANDO, E.FUGINDO] or bool(b.get("migra", false)):
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
		if eco.etapa_em(p) < Ecossistema.Rec.PASSAROS:
			continue                                       # fase 7: chão voltando não aguenta pássaro ainda
		soma += saude(Vector2i(p.floor())) * (1.0 - eco.disturbio(p))
	var media := soma / 16.0
	return int(round(float(_d.bandos_max) * clampf((media - 0.12) / 0.45, 0.0, 1.0)))


func _povoar(foco: Vector2, clima: Clima) -> void:
	if clima != null and clima.luz_dia() < 0.2:
		return                                             # ninguém chega de noite
	var locais := bandos.values().filter(func(x): return not bool(x.get("migra", false)))
	if locais.size() >= lotacao(foco):
		return
	var pesos := {}
	var conta := {}
	for b in locais:
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
			"vel": Vector2.ZERO, "destino": pos, "pousar": false, "estado": E.VOANDO, "t": 0.0, "sementes": 0, "semente_esp": "",
			"t_canto": _rng.randf_range(1.0, float(s.canto_s)), "t_olha": 0.0, "t_semente": 1.0, "dormindo": false,
			"centro": pos, "ang": _rng.randf() * TAU, "raio": _rng.randf_range(10.0, 16.0), "poleiros": [], "frutas": []}


## Copas de árvore viva perto de `c` (até 4): [centro, altura da copa, tile da árvore, modelo]. O bando pousa nelas
## (comendo fruta, à vista) e, na primavera, faz ninho nelas (NinhosPassaros).
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
			out.append([Grade.centro_da_area(o.ancora, o.area, 0), float(dims[2]) * 0.92, Vector2i(o.ancora), String(o.nome)])
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
	var comem_fruta := bool(_d.especies.get(b.especie, {}).get("sementes", false))
	for i in 12:
		var p := de + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, alcance)
		if p.distance_to(foco) > float(_d.raio_vida):
			p = foco + (p - foco).limit_length(float(_d.raio_vida) * 0.8)
		var t := Vector2i(p.floor())
		if gerador.terreno(t) != GeradorMundo.Terreno.TERRA or _perto_de_construcao(t, int(_d.medo.construcao)):
			continue
		if _ameaca_em(p, 3.0) != null:
			continue
		if eco.etapa_em(p) < Ecossistema.Rec.PASSAROS:
			continue                                       # fase 7: chão voltando ainda não tem pássaro
		var s := saude(t) + _rng.randf() * 0.05 + (0.3 if not poleiros_em(p).is_empty() else 0.0)   # gostam de árvore
		s -= float(_d.get("disturbio_peso", 1.2)) * eco.disturbio(p)   # barulho e fumaça da fábrica: longe
		if comem_fruta and not eco.comida_perto(p, 2.5, "fruta").is_empty():
			s += 0.45                                                                  # e de fruto no chão
		if ninhos != null and ninhos.da_especie_perto(String(b.especie), p, 8.0):
			s += 0.3                                                                   # e de ficar perto do ninho
		if s > nota:
			nota = s
			melhor = Vector2(t) + Vector2(0.5, 0.5)
	if melhor != null:
		b.poleiros = poleiros_em(melhor)
		b.frutas = []
		if comem_fruta:                                    # o desenho põe os do chão em volta dos frutos (bicando)
			for f in eco.comida_perto(melhor, float(_d.semente.get("fruta_raio", 3.0)), "fruta"):
				b.frutas.append(f.pos)
				if b.frutas.size() >= 4:
					break
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
		var vista := float(Registro.inimigos.get("comportamento", {}).get("aranha", {}).get("caca", {}).get("vista", 3.0)) + folga
		for ar in colonia.aranhas.values():
			if p.distance_to(ar.pos) < (vista if bool(ar.get("espreita", false)) else r):   # fase 8: espreitando, só de perto
				return ar.pos
	if eco != null:                                       # fase 9: o predador nativo (espreitando, só de perto)
		var rp := float(m.get("predador", 8.0)) + folga
		for a in eco.perto(p, rp, "predador"):
			if not bool(a.get("espreita", false)) or p.distance_to(a.pos) < 3.0 + folga:
				return a.pos
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
	if int(b.estado) == E.MIGRANDO:
		_migrando(b, dt, foco, clima)
		return
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
			if de == null and b.estado == E.POUSADO and eco.disturbio(b.pos) > float(_d.get("disturbio_foge", 0.55)):
				de = b.pos                                                  # fase 7: a máquina do lado começou a fazer barulho
			if de != null:
				_fugir(b, de, foco)
	match int(b.estado):
		E.CIRCULANDO:
			if carcacas != null:
				_carniceiro(b, dt, noite or some)
				if int(b.estado) != E.CIRCULANDO:
					return                                 # desceu para pousar na carne
			if ratos != null:
				_cacar(b, dt, noite or some)
				if int(b.estado) != E.CIRCULANDO:
					return                                 # viu um rato: mergulhou
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
			b.vel = (b.vel as Vector2) * maxf(0.0, 1.0 - dt * 6.0)     # freia: escorrega ~vel/6 m
			b.pos = (b.pos as Vector2) + (b.vel as Vector2) * dt
			if b.get("olha") != null:                      # o planador pousa do lado da carne, não passa dela
				b.vel = Vector2.ZERO
				b.pos = (b.pos as Vector2).move_toward(b.destino, dt * 2.5)
			if b.t <= 0.0:
				b.alt = 0.0
				b.vel = Vector2.ZERO
				b.estado = E.POUSADO
				var ps: Array = s.get("pousa_s", [10, 20])
				b.t = _rng.randf_range(float(ps[0]), float(ps[1])) * (6.0 if noite else 1.0)
				b.dormindo = noite
		E.MERGULHANDO:
			_mergulho(b, s, dt)
		E.POUSADO:
			b.t = float(b.t) - dt
			if s.has("giro"):                              # planador no chão: come a carne até acabar (ou anoitecer)
				_comer_carne(b, dt)
				if noite or some:
					b.t = minf(float(b.t), 0.0)
				if b.t <= 0.0:
					b.estado = E.DECOLANDO
					b.t = DECOLA_S * 2.0
					eventos.append({"tipo": "revoada", "id": b.id, "pos": b.pos, "especie": b.especie})
				return
			if noite:
				b.t = maxf(float(b.t), 2.0)                # dorme até o dia
				b.dormindo = true
				return
			b.dormindo = false
			_cantar(b, s, dt, 1.0)
			if b.t <= 0.0 or some:
				if bool(s.get("sementes", false)):
					_comer(b)
				b.estado = E.DECOLANDO
				b.t = DECOLA_S
				eventos.append({"tipo": "revoada", "id": b.id, "pos": b.pos, "especie": b.especie})
		E.DECOLANDO:
			b.t = float(b.t) - dt
			b.alt = float(b.alt) + dt * (1.6 if s.has("giro") else 3.0)    # o planador sobe pesado
			if b.t <= 0.0:
				_seguir(b, foco, noite)


## Próximo destino depois de decolar/chegar: comer num lugar bom (70%) ou explorar (30%); de noite, pousar.
## O planador não: volta a circular alto em volta de onde está.
func _seguir(b: Dictionary, foco: Vector2, noite: bool) -> void:
	var alt: Array = _d.especies[b.especie].alt
	if _d.especies[b.especie].has("giro"):
		_voltar_a_circular(b)
		return
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


## Planador carniceiro (fase 4): carcaça com carne por perto, de dia, e o centro do giro vai para cima dela; ele
## desce e fecha a volta. De longe, quem joga vê que ali morreu alguma coisa. Sem carne, volta ao giro alto de antes.
func _carniceiro(b: Dictionary, dt: float, sai: bool) -> void:
	var c: Dictionary = _d.get("carcacas", {}).get("carniceiro", {})
	b.t_carne = float(b.get("t_carne", 0.0)) - dt
	if b.t_carne <= 0.0:
		b.t_carne = 2.0
		b.carne = null
		if not sai:
			var perto := INF
			for f in carcacas.com_carne(b.centro, float(c.get("raio", 45.0))):
				var d := (f.pos as Vector2).distance_to(b.centro)
				if d < perto:
					perto = d
					b.carne = f.pos
					b.carne_id = int(f.id)
	if b.get("carne") != null:
		if not b.has("raio0"):
			b.raio0 = b.raio
			b.alt0 = b.alt_alvo
		b.centro = (b.centro as Vector2).move_toward(b.carne, 3.0 * dt)
		# fase 6: depois de rodar um tempo por cima (e nada assustando ali), desce em espiral e pousa do lado
		if (b.centro as Vector2).distance_to(b.carne) < 2.0:
			b.t_sobre = float(b.get("t_sobre", 0.0)) + dt
		var pousa := float(b.get("t_sobre", 0.0)) >= float(c.get("pousa_apos_s", 12.0)) and _pode_pousar(b.carne)
		b.raio = move_toward(float(b.raio), 2.2 if pousa else float(c.get("giro", 6.0)), 1.5 * dt)
		b.alt_alvo = move_toward(float(b.alt_alvo), 1.4 if pousa else float(c.get("alt", 9.0)), (2.0 if pousa else 1.2) * dt)
		if pousa and float(b.alt) < 2.4:
			_pousar_em(b, b.carne, int(b.get("carne_id", -1)))
	elif b.has("raio0"):
		b.raio = move_toward(float(b.raio), float(b.raio0), 1.5 * dt)
		b.alt_alvo = move_toward(float(b.alt_alvo), float(b.alt0), 1.2 * dt)
		if is_equal_approx(float(b.raio), float(b.raio0)) and is_equal_approx(float(b.alt_alvo), float(b.alt0)):
			b.erase("raio0")
			b.erase("alt0")


## Dá para pousar ali? (nada assustando perto, nenhuma construção encostada)
func _pode_pousar(p: Vector2) -> bool:
	return _ameaca_em(p, 4.0) == null and not _perto_de_construcao(Vector2i(p.floor()), 4)


## O planador desce do giro e pousa do lado de `alvo` (a carne), de frente para ela.
func _pousar_em(b: Dictionary, alvo: Vector2, id: int) -> void:
	var de := ((b.pos as Vector2) - alvo)
	de = de.normalized() if de.length() > 0.05 else Vector2.RIGHT
	b.estado = E.VOANDO
	b.destino = alvo + de * 0.5
	b.pousar = true
	b.alt_alvo = 0.0
	b.come_id = id
	b.come_pos = alvo
	b.olha = alvo
	b.t_sobre = 0.0


## Planador no chão: bica a carcaça (a carne acaba mais rápido); sem carne, termina logo e vai embora.
func _comer_carne(b: Dictionary, dt: float) -> void:
	if carcacas == null or b.get("come_pos") == null:
		b.t = minf(float(b.t), 1.0)
		return
	if int(b.get("come_id", -1)) < 0 or not eco.comida.has(int(b.come_id)):
		b.come_id = -1                                   # o rato que pegou vira carcaça no tick seguinte
		for f in carcacas.com_carne(b.come_pos, 1.2):
			b.come_id = int(f.id)
			break
	if int(b.come_id) < 0:
		b.t_sem_carne = float(b.get("t_sem_carne", 0.0)) + dt
		if float(b.t_sem_carne) > 2.0:
			b.t = minf(float(b.t), 1.0)
		return
	b.t_sem_carne = 0.0
	if not carcacas.bicar(int(b.come_id), dt * float(_d.get("caca", {}).get("come_x", 6.0))):
		b.t = minf(float(b.t), 1.5)                      # acabou a carne: só restos


## Volta ao giro alto em volta de onde está (depois de comer ou de errar o mergulho).
func _voltar_a_circular(b: Dictionary) -> void:
	var alt: Array = _d.especies[b.especie].alt
	b.estado = E.CIRCULANDO
	b.centro = (b.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 3.0
	b.ang = ((b.pos as Vector2) - (b.centro as Vector2)).angle()
	if not b.has("raio0"):                               # o carniceiro devolve devagar; sem ele, o giro de sempre
		b.raio0 = _rng.randf_range(10.0, 16.0)
		b.alt0 = _rng.randf_range(float(alt[0]), float(alt[1]))
	b.raio = maxf(float(b.raio), 4.0)
	b.alt_alvo = maxf(float(b.alt_alvo), 6.0)
	b.come_pos = null
	b.come_id = -1
	b.olha = null
	b.t_sobre = -30.0                                    # não desce de novo na mesma hora


## Rato em campo aberto? (sem arbusto nem árvore em cima: o planador vê)
func _aberto(p: Vector2) -> bool:
	return eco.arbustos_perto(p, 1.2).is_empty() and eco.arvores_perto(p, 1.5).is_empty()


## Planador caçando: de vez em quando olha os ratos fora da toca em campo aberto e mergulha no mais perto.
func _cacar(b: Dictionary, dt: float, sai: bool) -> void:
	var c: Dictionary = _d.get("caca", {})
	if not bool(c.get("liga", true)) or sai or b.get("carne") != null:
		return
	b.t_caca = float(b.get("t_caca", _rng.randf_range(2.0, 6.0))) - dt
	if b.t_caca > 0.0:
		return
	b.t_caca = float(c.get("olha_s", 2.5))
	if _rng.randf() > float(c.get("chance", 0.3)):
		return
	var melhor: Dictionary = {}
	var perto := float(c.get("raio", 30.0))
	for r in ratos.ratos.values():
		if not int(r.estado) in [Ratos.E.ANDANDO, Ratos.E.FAREJANDO, Ratos.E.COMENDO, Ratos.E.CAVANDO] or r.get("morto", false):
			continue
		var d := (r.pos as Vector2).distance_to(b.pos)
		if d < perto and _aberto(r.pos):
			perto = d
			melhor = r
	if melhor.is_empty():
		return
	if not b.has("raio0"):
		b.raio0 = b.raio
		b.alt0 = b.alt_alvo
	var esp_r: Dictionary = Registro.fauna.get("ratos", {}).get("especies", {}).get(String(melhor.get("especie", "pardo")), {})
	b.presa = int(melhor.id)
	b.estado = E.MERGULHANDO
	b.t = float(c.get("mergulho_max_s", 6.0))
	b.viu = _rng.randf() < float(esp_r.get("alerta", c.get("alerta", 0.45)))
	b.avisou = false
	eventos.append({"tipo": "mergulho", "id": b.id, "pos": b.pos, "alt": b.alt, "especie": b.especie})


## Mergulho: vai atrás do rato descendo rápido; o rato que viu a sombra chegando corre para a toca. Pegou: pousa em
## cima e come (o rato vira carcaça). Escapou ou demorou: sobe e volta a circular.
func _mergulho(b: Dictionary, s: Dictionary, dt: float) -> void:
	var c: Dictionary = _d.get("caca", {})
	var r: Dictionary = ratos.ratos.get(int(b.get("presa", -1)), {}) if ratos != null else {}
	b.t = float(b.t) - dt
	var fora: bool = not r.is_empty() and not int(r.estado) in [Ratos.E.TOCA, Ratos.E.ENTRANDO] and not bool(r.get("morto", false))
	if not fora or b.t <= 0.0:
		b.t_caca = float(c.get("espera_s", 25.0))
		b.presa = -1
		_voltar_a_circular(b)
		b.t_sobre = 0.0
		return
	var alvo: Vector2 = r.pos
	var d := alvo.distance_to(b.pos)
	if bool(b.get("viu", false)) and not bool(b.get("avisou", false)) and d < float(c.get("ve_dist", 14.0)):
		b.avisou = true
		ratos.assustar_do_ceu(alvo, 1.5)
	_voar(b, alvo, float(s.vel) * float(c.get("mergulho_vel", 2.0)), dt)
	b.alt = move_toward(float(b.alt), 0.3 + d * 0.6, dt * 12.0)      # desce em mergulho, rente ao chão no fim
	if d < float(c.get("pega_dist", 0.9)) and float(b.alt) < 1.4:
		ratos.matar(int(b.presa), "planador")
		eventos.append({"tipo": "pegou", "id": b.id, "pos": alvo, "especie": b.especie})
		b.presa = -1
		b.estado = E.POUSANDO
		b.t = POUSO_S
		b.come_pos = alvo
		b.come_id = -1
		b.olha = alvo


# ------------------------------------------------------------------ morte (fase 6)
## Explosão ou raio em `c`: quem está perto e baixo (até morte.alt_max m) pode cair morto; mais perto, mais chance.
## Devolve quantos morreram.
func ferir(c: Vector2, raio: float, chance: float, causa := "") -> int:
	var m: Dictionary = _d.get("morte", {})
	if not bool(m.get("liga", true)):
		return 0
	var n := 0
	for id in bandos.keys():
		var b: Dictionary = bandos.get(id, {})
		if b.is_empty() or bool(b.get("migra", false)) or float(b.alt) > float(m.get("alt_max", 9.0)):
			continue
		var esp := _espalha(b)
		var d := (b.pos as Vector2).distance_to(c)
		if d > raio + esp:
			continue
		var k := chance * clampf(1.0 - maxf(0.0, d - esp * 0.5) / raio, 0.0, 1.0)
		var quantos := 0
		for i in int(b.n):
			if _rng.randf() < k:
				quantos += 1
		for i in mini(quantos, int(m.get("max_por_vez", 6))):
			if not bandos.has(id):
				break
			_matar(b, causa, c)
			n += 1
	return n


## Quanto o bando se espalha (m): o mesmo que o desenho usa para pôr os pássaros em volta do centro.
func _espalha(b: Dictionary) -> float:
	return 0.0 if _d.especies[b.especie].has("giro") else 0.7 + sqrt(float(b.n)) * 0.32


## Velhice e doença: de vez em quando morre um (mais no chão envenenado e no inverno). Cai de onde está.
func _morrer_de_velho(dt: float, clima: Clima) -> void:
	var m: Dictionary = _d.get("morte", {})
	if not bool(m.get("liga", true)):
		return
	_t_morte -= dt
	if _t_morte > 0.0:
		return
	_t_morte = 1.0
	var base := float(m.get("natural_h", 0.03)) / 3600.0
	if clima != null and clima.estacao == 3:
		base *= float(m.get("inverno_x", 1.5))
	for id in bandos.keys():
		var b: Dictionary = bandos.get(id, {})
		if b.is_empty() or bool(b.get("migra", false)):
			continue
		var p := base * float(b.n)
		if saude(Vector2i((b.pos as Vector2).floor())) < float(m.get("doente_saude", 0.15)):
			p *= float(m.get("doente_x", 5.0))
		if _rng.randf() < p:
			_matar(b, "velhice")


## Um pássaro do bando morre: o corpo cai perto de onde estava (de cima do galho, embaixo da copa) e vira carcaça.
func _matar(b: Dictionary, causa: String, perto: Variant = null) -> void:
	var esp := _espalha(b)
	var pos: Vector2
	if perto != null:
		pos = (b.pos as Vector2) + ((perto as Vector2) - (b.pos as Vector2)).limit_length(esp * 0.6)
	else:
		pos = (b.pos as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * esp * 0.6
	var pol: Array = b.get("poleiros", [])
	if int(b.estado) in [E.POUSADO, E.POUSANDO] and not pol.is_empty() and _rng.randf() < 0.6:
		var c: Array = pol[_rng.randi() % pol.size()]
		pos = (c[0] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * 0.55
	var corpo := "passaro_%d_%d" % [_sessao, _prox_corpo]
	_prox_corpo += 1
	b.n = int(b.n) - 1
	mortes += 1
	eventos.append({"tipo": "morreu", "id": b.id, "corpo": corpo, "pos": pos, "alt": float(b.alt), "especie": b.especie,
			"causa": causa})
	eco.morreu("passaro", "passaro", pos, {"id": corpo, "variante": String(b.especie), "rumo": _rng.randf() * TAU,
			"causa": causa})
	if int(b.n) <= 0:
		bandos.erase(b.id)


# ------------------------------------------------------------------ migração (fase 6)
## Para onde a migração anda nessa estação: no fim do verão e no outono, para o sul; no inverno e na primavera,
## para o norte. Quem chega vem no sentido da estação (primavera e verão do sul; outono e inverno do norte).
static func rumo_migracao(estacao: int, chegando: bool) -> Vector2:
	if chegando:
		return Vector2.UP if estacao in [0, 1] else Vector2.DOWN
	return Vector2.DOWN if estacao in [1, 2] else Vector2.UP


func _migrar(dt: float, foco: Vector2, clima: Clima, noite: bool) -> void:
	var m: Dictionary = _d.get("migracao", {})
	if clima == null or not bool(m.get("liga", true)):
		return
	if _estacao != clima.estacao:                        # trocou a estação: quem vai embora sobe e parte junto
		var antes := _estacao
		_estacao = clima.estacao
		if antes >= 0:
			_partir_todos(foco, clima)
	if noite:
		return
	_t_mig -= dt
	if _t_mig > 0.0:
		return
	var iv: Array = m.get("intervalo_s", [120, 240])
	_t_mig = _rng.randf_range(float(iv[0]), float(iv[1]))
	var frac := clima.t_estacao / maxf(1.0, float(Registro.clima.get("estacao_s", 604800)))
	var opcoes: Array = []                               # [espécie, chegando]
	for esp in _d.especies:
		var e: Array = _d.especies[esp].get("estacoes", [1, 1, 1, 1])
		var agora := float(e[clima.estacao % e.size()])
		if float(e[(clima.estacao + 1) % e.size()]) < agora - 0.25 and frac >= float(m.get("vai_depois", 0.5)):
			opcoes.append([esp, false])
		if agora > float(e[(clima.estacao + 3) % e.size()]) + 0.25 and frac <= float(m.get("chega_ate", 0.5)):
			opcoes.append([esp, true])
	if opcoes.is_empty():
		return
	var o: Array = opcoes[_rng.randi() % opcoes.size()]
	passagem(String(o[0]), foco, clima.estacao, bool(o[1]))


## Uma revoada de migração cruzando o céu perto do foco (de um lado a outro, alta). `chegando`: desce e fica.
func passagem(esp: String, foco: Vector2, estacao: int, chegando: bool) -> Dictionary:
	var m: Dictionary = _d.get("migracao", {})
	var rumo := rumo_migracao(estacao, chegando)
	var lado := Vector2(-rumo.y, rumo.x) * _rng.randf_range(-22.0, 22.0)
	var b := _novo(esp, foco - rumo * float(_d.raio_vida) * 1.25 + lado)
	var nb: Array = m.get("bando_chega" if chegando else "bando", [25, 45])
	b.n = mini(_rng.randi_range(int(nb[0]), int(nb[1])), int(_d.get("bando_max_n", 40)) if chegando else 999)
	var alt: Array = m.get("alt", [16, 24])
	b.alt = _rng.randf_range(float(alt[0]), float(alt[1]))
	b.alt_alvo = b.alt
	b.estado = E.MIGRANDO
	b.migra = true
	b.chega = chegando
	b.rumo_mig = rumo
	b.destino = foco + rumo * float(_d.raio_vida) * 1.7 + lado
	b.vel = rumo * float(m.get("vel", 9.0))
	bandos[b.id] = b
	eventos.append({"tipo": "migracao", "id": b.id, "pos": b.pos, "alt": b.alt, "especie": esp, "n": b.n, "chega": chegando})
	return b


## Na troca de estação: os bandos das espécies que vão embora (fator 0) se juntam no maior e partem alto.
func _partir_todos(foco: Vector2, clima: Clima) -> void:
	var m: Dictionary = _d.get("migracao", {})
	var por_esp := {}
	for b in bandos.values():
		if not bool(b.get("migra", false)) and _fator_estacao(b.especie, clima) <= 0.0 and not _d.especies[b.especie].has("giro"):
			if not por_esp.has(b.especie):
				por_esp[b.especie] = []
			por_esp[b.especie].append(b)
	var alt: Array = m.get("alt", [16, 24])
	for esp in por_esp:
		var lista: Array = por_esp[esp]
		lista.sort_custom(func(a, b): return int(a.n) > int(b.n))
		var fica: Dictionary = lista[0]
		for i in range(1, lista.size()):
			fica.n = int(fica.n) + int(lista[i].n)
			bandos.erase(lista[i].id)
			eventos.append({"tipo": "juntou", "de": lista[i].id, "para": fica.id})
		var rumo := rumo_migracao(clima.estacao, false)
		fica.estado = E.MIGRANDO
		fica.migra = true
		fica.chega = false
		fica.rumo_mig = rumo
		fica.pousar = false
		fica.dormindo = false
		fica.destino = (fica.pos as Vector2) + rumo * float(_d.raio_vida) * 2.0
		fica.alt_alvo = _rng.randf_range(float(alt[0]), float(alt[1]))
		eventos.append({"tipo": "revoada", "id": fica.id, "pos": fica.pos, "especie": esp})
		eventos.append({"tipo": "migracao", "id": fica.id, "pos": fica.pos, "alt": fica.alt, "especie": esp, "n": fica.n,
				"chega": false})


func _migrando(b: Dictionary, dt: float, foco: Vector2, clima: Clima) -> void:
	var m: Dictionary = _d.get("migracao", {})
	var chegou := _voar(b, b.destino, float(m.get("vel", 9.0)), dt)
	b.alt = lerpf(float(b.alt), float(b.alt_alvo), dt * 0.6)
	b.t_canto = float(b.t_canto) - dt
	if b.t_canto <= 0.0:
		b.t_canto = _rng.randf_range(4.0, 6.0)
		eventos.append({"tipo": "migracao", "id": b.id, "pos": b.pos, "alt": b.alt, "especie": b.especie, "n": b.n,
				"chega": bool(b.get("chega", false))})
	if bool(b.get("chega", false)) and (b.pos as Vector2).distance_to(foco) < float(_d.raio_vida) * 0.35:
		b.migra = false                                  # chegou: desce e vira bando daqui
		b.chega = false
		_seguir(b, foco, false)
		b.alt_alvo = minf(float(b.alt_alvo), 10.0)
		return
	if chegou:
		b.destino = (b.pos as Vector2) + (b.rumo_mig as Vector2) * float(_d.raio_vida)


## Antes de decolar: come os frutos do chão em volta (patch fauna, fase 3) e leva a semente da árvore deles; sem fruto,
## em chão saudável come semente do mato e leva semente do bioma.
func _comer(b: Dictionary) -> void:
	var fr: Array = eco.comida_perto(b.pos, float(_d.semente.get("fruta_raio", 3.0)), "fruta")
	var come := mini(fr.size(), clampi(int(ceil(float(b.n) / 8.0)), 1, 4))
	var esp := ""
	for i in come:
		if eco.comer(int(fr[i].id), "passaro") and esp == "":
			esp = String(fr[i].get("fonte", ""))
	if come > 0:
		b.sementes = int(_d.semente.por_bando)
		b.semente_esp = esp
	elif saude(Vector2i((b.pos as Vector2).floor())) >= float(_d.saude_min):
		b.sementes = int(_d.semente.por_bando)
		b.semente_esp = ""


## Semente: voando sobre chão morto, de vez em quando cai uma e nasce uma muda (da árvore do fruto que comeu).
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
		if String(b.get("semente_esp", "")) != "":
			ambiente.especies[onde] = String(b.semente_esp)
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
