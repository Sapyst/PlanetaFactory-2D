class_name Predadores
extends RefCounted
## Patch fauna, fase 9 (docs/PLANO_FAUNA.md), lógica pura: o uivador, predador nativo de matilha.
##  covil   a matilha mora num covil na beira da mata (árvores perto), em chão vivo e quieto, longe da fábrica; nasce a
##          nasce_dist m da câmera e cabe `max` matilha perto. Fica no save. Covil que estragou (fábrica, fogo, chão
##          morto): a matilha muda para outro ali perto, ou vai embora.
##  rotina  bicho de crepúsculo e de noite: de dia a matilha descansa deitada no covil; ativa, ronda o território (até
##          `territorio` m do covil), junta, atrás do líder.
##  caça    com fome procura presa: herbívoro (o filhote ou o que se afastou da manada) se a matilha tem 2 ou mais;
##          senão, rato fora da toca. Espreita devagar (só é vista de perto) até o bote, então corre; em
##          `perseguicao_s` sem pegar, cansa e desiste. Pegou: comem juntos em volta da carcaça e voltam ao covil.
##  guerra  aranha e larva são hostis (inimigos.json "relacoes"): perto da matilha ou do covil, se não são muitas, a
##          matilha ataca (mordida); se são muitas, foge. Aranha e larva também atacam a matilha (Colonia.fauna).
##  medo    fogo, susto (tiro, explosão, raio) e máquina barulhenta: foge. Não ataca a fábrica.
## O desenho lê `bichos` (pos, rumo, estado). Eventos: "uivo", "pegou", "briga", "fugiu".

enum P { COVIL, RONDA, CACA, COMER, BRIGA, FUGA, VOLTA }
enum E { DEITADO, ANDANDO, ESPREITANDO, CORRENDO, MORDENDO, COMENDO }

var eco: Ecossistema
var ambiente: AmbienteVivo
var manadas: Manadas              ## (opcional) presa grande
var ratos: Ratos                  ## (opcional) presa pequena
var carcacas: Carcacas            ## (opcional) a carne que comem
var colonia: Colonia              ## (opcional) as aranhas e larvas que mordem
var matilhas: Dictionary = {}     ## id → {id, especie, covil, estado: P, alvo, presa, t, fome, t_caca, antes}
var bichos: Dictionary = {}       ## id → {id, matilha, especie, pos, rumo, estado: E, t, vida, lugar, inimigo}
var eventos: Array = []
var mortos: Dictionary = {}
var _sustos: Array = []
var _t_nasce := 0.0
var _t_olha := 0.0
var _prox := 1
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, p_ambiente: AmbienteVivo = null, semente := 137) -> void:
	eco = p_eco
	ambiente = p_ambiente
	_rng.seed = semente
	_d = Registro.fauna.get("predadores", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


func _faixa(chave: String, a: float, b: float) -> float:
	var f: Array = _d.get(chave, [a, b])
	return _rng.randf_range(float(f[0]), float(f[1]))


## Os predadores como o Ecossistema os vê (fonte "predador"); quem espreita só é visto de perto.
func para_ecossistema() -> Array:
	var out: Array = []
	for b in bichos.values():
		out.append({"id": b.id, "pos": b.pos, "especie": String(b.especie), "espreita": int(b.estado) == E.ESPREITANDO})
	return out


func assustar(c: Vector2, raio: float) -> void:
	_sustos.append([c, raio])


static func corpo_id(id: int) -> String:
	return "predador_%d" % id


## Quantos acordados querem estar fora agora (0..1): crepúsculo e noite muito, meio-dia pouco.
static func atividade(clima: Clima) -> float:
	if clima == null:
		return 1.0
	var h := clima.hora
	var noite := 1.0 if h < 0.22 or h > 0.8 else 0.0
	var crepusculo := maxf(1.0 - absf(h - 0.25) / 0.06, 1.0 - absf(h - 0.77) / 0.06)
	return clampf(maxf(noite, crepusculo), 0.0, 1.0)


# ------------------------------------------------------------------ o que a Colônia pergunta (aranhas e larvas brigando)
## Predadores hostis à espécie `esp` a até `raio` de `p`: [{id, pos}].
func hostis_perto(p: Vector2, raio: float, esp: String) -> Array:
	var out: Array = []
	for b in bichos.values():
		if (b.pos as Vector2).distance_to(p) <= raio and Colonia.hostil_em(esp, String(b.especie)):
			out.append({"id": b.id, "pos": b.pos})
	return out


func pos_de(id: int) -> Variant:
	return bichos[id].pos if bichos.has(id) and not bichos[id].get("morto", false) else null


## Dano (mordida, gosma): a matilha que leva dano briga com quem fez, ou foge se eles são muitos.
func ferir(id: int, dano: float, por := "") -> void:
	if not bichos.has(id):
		return
	var b: Dictionary = bichos[id]
	b.vida = float(b.vida) - dano
	if float(b.vida) <= 0.0:
		b.morto = true
		b.causa = por
	var m: Dictionary = matilhas.get(int(b.matilha), {})
	if not m.is_empty() and int(m.estado) not in [P.BRIGA, P.FUGA]:
		m.t_olha = 0.0


func ferir_area(p: Vector2, raio: float, dano: float, por := "") -> void:
	for b in bichos.values():
		if (b.pos as Vector2).distance_to(p) <= raio and Colonia.hostil_em(por, String(b.especie)):
			ferir(int(b.id), dano, por)


# ------------------------------------------------------------------ tick
func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	eventos.clear()
	if not bool(_d.get("liga", true)):
		_sustos.clear()
		return
	eco.esquecer_passagem(dt)
	_t_nasce -= dt
	if _t_nasce <= 0.0:
		_t_nasce = _n("nasce_s", 12.0)
		_nascer(foco)
		_cuidar_covis()
	var ativo := atividade(clima)
	_t_olha -= dt
	var olhar := _t_olha <= 0.0 or not _sustos.is_empty()
	if olhar:
		_t_olha = 0.5
	for m in matilhas.values():
		m.t_olha = float(m.get("t_olha", 0.0)) - dt
		if olhar or float(m.t_olha) <= 0.0:
			m.t_olha = 0.5
			_olhar(m)
		_matilha(m, dt, ativo)
	for b in bichos.values():
		_bicho(b, dt)
	eco.separar(bichos.values(), _n("entre_bichos", 0.9))
	for id in mortos.keys():
		mortos[id] = float(mortos[id]) + dt
		if float(mortos[id]) > 5.0:
			mortos.erase(id)
	var morreram: Array = bichos.values().filter(func(b): return b.get("morto", false) \
			or (ambiente != null and ambiente.fogo.has(Vector2i((b.pos as Vector2).floor()))))
	for b in morreram:
		bichos.erase(b.id)
		mortos[b.id] = 0.0
		eco.morreu("predador", "predador", b.pos, {"id": corpo_id(b.id), "variante": String(b.especie),
				"rumo": float(b.rumo), "causa": String(b.get("causa", "fogo"))})
	for id in matilhas.keys():
		var m: Dictionary = matilhas[id]
		if not bichos.values().any(func(b): return int(b.matilha) == int(id)) \
				or (m.covil as Vector2).distance_to(foco) > _n("raio_sim", 160.0):
			_tirar(int(id))
	_sustos.clear()


# ------------------------------------------------------------------ covil
## Covil bom: chão vivo e quieto na beira da mata (árvores perto, mas o lugar em si passa), longe da fábrica e da
## água.
func bom_covil(p: Vector2) -> bool:
	var tl := Vector2i(p.floor())
	if not eco.passavel(p) or eco.gerador.terreno(tl) != GeradorMundo.Terreno.TERRA:
		return false
	if eco.saude(tl) < _n("saude_min", 0.38) or eco.perto_de_construcao(tl, int(_n("longe_construcao", 16))):
		return false
	if eco.etapa_em(p) < Ecossistema.Rec.ARVORES or eco.disturbio(p) > _n("disturbio_max", 0.15):
		return false
	if eco.perto_da_agua(tl, 2):
		return false
	return eco.arvores_perto(p, _n("mata_raio", 8.0)).size() >= int(_n("mata_min", 2))


func _nascer(foco: Vector2) -> void:
	var perto := matilhas.values().filter(func(m): return (m.covil as Vector2).distance_to(foco) <= _n("raio_vida", 110.0))
	if perto.size() >= int(_n("max", 1)):
		return
	for tentativa in 14:
		var p := foco + Vector2.from_angle(_rng.randf() * TAU) * _faixa("nasce_dist", 50.0, 95.0)
		if bom_covil(p):
			nova_matilha(p)
			return


func nova_matilha(covil: Vector2, especie := "uivador", n := -1) -> int:
	var id := _prox
	_prox += 1
	matilhas[id] = {"id": id, "especie": especie, "covil": covil, "estado": P.COVIL, "alvo": covil, "presa": {},
			"t": _rng.randf_range(5.0, 30.0), "fome": _rng.randf_range(0.2, 0.6), "t_caca": 0.0, "antes": P.COVIL,
			"t_olha": 0.0, "de": covil}
	var k := n if n > 0 else int(round(_faixa("por_matilha", 2.0, 4.0)))
	for i in k:
		var bid := _prox
		_prox += 1
		var lugar := Vector2.from_angle(TAU * i / k + _rng.randf_range(-0.3, 0.3)) * _rng.randf_range(0.9, 1.8)
		bichos[bid] = {"id": bid, "matilha": id, "especie": especie, "pos": covil + lugar, "rumo": _rng.randf() * TAU,
				"estado": E.DEITADO, "t": 0.0, "vida": _n("vida", 110.0), "lugar": lugar, "inimigo": -1, "ordem": i}
	return id


func _cuidar_covis() -> void:
	for m in matilhas.values():
		if bom_covil(m.covil) and not _fogo_perto(m.covil, _n("fogo_raio", 18.0)):
			continue
		var novo: Vector2 = m.covil
		for tentativa in 12:
			var p: Vector2 = (m.covil as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(25.0, 60.0)
			if bom_covil(p):
				novo = p
				break
		if novo == m.covil:
			m.covil = (m.covil as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _n("raio_sim", 160.0) * 1.2
		else:
			m.covil = novo
		if int(m.estado) == P.COVIL:
			m.estado = P.VOLTA


func _tirar(id: int) -> void:
	for b in bichos.values().filter(func(b): return int(b.matilha) == id):
		bichos.erase(b.id)
	matilhas.erase(id)


func _meus(m: Dictionary) -> Array:
	var out := bichos.values().filter(func(b): return int(b.matilha) == int(m.id))
	out.sort_custom(func(a, b): return int(a.ordem) < int(b.ordem))
	return out


func _lider(m: Dictionary) -> Dictionary:
	var meus := _meus(m)
	return meus[0] if not meus.is_empty() else {}


# ------------------------------------------------------------------ olhar em volta (medo, guerra, presa)
func _fogo_perto(p: Vector2, raio: float) -> bool:
	if ambiente == null or ambiente.fogo.is_empty():
		return false
	var n := 0
	for t: Vector2i in ambiente.fogo:
		if p.distance_to(Vector2(t) + Vector2(0.5, 0.5)) < raio:
			return true
		n += 1
		if n > 300:
			break
	return false


func _olhar(m: Dictionary) -> void:
	var meus := _meus(m)
	if meus.is_empty():
		return
	var lider: Dictionary = meus[0]
	var p: Vector2 = lider.pos
	# medo: susto, fogo, máquina barulhenta
	for s in _sustos:
		if meus.any(func(b): return (b.pos as Vector2).distance_to(s[0]) < float(s[1])):
			_fugir(m, s[0])
			return
	if _fogo_perto(p, _n("fogo_raio", 18.0)):
		_fugir(m, p + Vector2(0.1, 0))
		return
	if eco.disturbio(p) > _n("disturbio_foge", 0.5) and int(m.estado) != P.FUGA:
		_fugir(m, p + Vector2(0.1, 0))
		return
	# guerra: aranha e larva perto da matilha ou do covil
	var ve := _n("ve", 14.0)
	var hostis: Array = []
	for a in eco.perto(p, ve, "alien") + eco.perto(m.covil, ve, "alien"):
		if Colonia.hostil_em(String(m.especie), String(a.get("especie", "aranha"))) and not hostis.any(func(x): return x.id == a.id):
			hostis.append(a)
	if not hostis.is_empty():
		if hostis.size() > meus.size() + int(_n("coragem", 1)):
			if int(m.estado) != P.FUGA:
				_fugir(m, (hostis[0].pos as Vector2))
		elif int(m.estado) not in [P.BRIGA, P.FUGA]:
			m.antes = int(m.estado) if int(m.estado) != P.COMER else P.VOLTA
			m.estado = P.BRIGA
			m.t = 30.0
			eventos.append({"tipo": "briga", "matilha": m.id, "pos": p})
		return
	if int(m.estado) == P.BRIGA:
		m.estado = int(m.get("antes", P.VOLTA))
		for b in meus:
			b.inimigo = -1
	# presa: com fome, rondando
	if int(m.estado) == P.RONDA and float(m.fome) >= _n("fome_caca", 0.5):
		var presa := _presa_perto(p, meus.size())
		if not presa.is_empty():
			m.presa = presa
			m.estado = P.CACA
			m.t_caca = 0.0
			m.correndo = false


func _presa_perto(p: Vector2, n: int) -> Dictionary:
	if manadas != null and n >= int(_n("caca_grande_min", 2)):
		var h := manadas.presa_perto(p, _n("procura_grande", 45.0))
		if h >= 0:
			return {"tipo": "herbivoro", "id": h}
	if ratos != null:
		var md := _n("procura_rato", 20.0)
		var melhor := -1
		for x in ratos.ratos.values():
			if x.estado in [Ratos.E.TOCA, Ratos.E.ENTRANDO, Ratos.E.SAINDO] or x.get("morto", false):
				continue
			var d: float = (x.pos as Vector2).distance_to(p)
			if d < md:
				md = d
				melhor = int(x.id)
		if melhor >= 0:
			return {"tipo": "rato", "id": melhor}
	return {}


func _presa_pos(pr: Dictionary) -> Variant:
	match String(pr.get("tipo", "")):
		"herbivoro":
			if manadas == null or not manadas.bichos.has(int(pr.id)) or manadas.bichos[int(pr.id)].get("morto", false):
				return null
			return manadas.bichos[int(pr.id)].pos
		"rato":
			var x: Dictionary = ratos.ratos.get(int(pr.id), {}) if ratos != null else {}
			if x.is_empty() or x.estado in [Ratos.E.TOCA, Ratos.E.ENTRANDO] or x.get("morto", false):
				return null
			return x.pos
	return null


func _fugir(m: Dictionary, de: Vector2) -> void:
	var lider := _lider(m)
	var p: Vector2 = lider.pos if not lider.is_empty() else m.covil
	var dir := p - de
	var ang := dir.angle() if dir.length() > 0.1 else _rng.randf() * TAU
	m.alvo = p
	for tentativa in 12:
		var q := p + Vector2.from_angle(ang + _rng.randf_range(-0.6, 0.6)) * _n("foge_dist", 35.0)
		if eco.passavel(q) and eco.linha_passavel(p, q):
			m.alvo = q
			break
	m.estado = P.FUGA
	m.t = _n("foge_s", 7.0)
	m.de = de
	m.presa = {}
	eventos.append({"tipo": "fugiu", "matilha": m.id, "pos": p})


# ------------------------------------------------------------------ a matilha
func _matilha(m: Dictionary, dt: float, ativo: float) -> void:
	m.t = float(m.t) - dt
	m.fome = minf(1.0, float(m.fome) + dt / maxf(1.0, _n("fome_s", 900.0)))
	var lider := _lider(m)
	if lider.is_empty():
		return
	match int(m.estado):
		P.COVIL:
			if ativo > 0.5 and float(m.t) <= 0.0:
				m.estado = P.RONDA
				m.alvo = _ponto_de_ronda(m)
				if _rng.randf() < _n("uivo_chance", 0.5):
					eventos.append({"tipo": "uivo", "matilha": m.id, "pos": m.covil})
		P.RONDA:
			if ativo < 0.3:
				m.estado = P.VOLTA
			elif (lider.pos as Vector2).distance_to(m.alvo) < 1.5:
				m.alvo = _ponto_de_ronda(m)
		P.CACA:
			m.t_caca = float(m.t_caca) + dt
			var alvo: Variant = _presa_pos(m.presa)
			if alvo == null or float(m.t_caca) > _n("desiste_s", 40.0) \
					or (bool(m.get("correndo", false)) and float(m.get("t_corre", 0.0)) > _n("perseguicao_s", 12.0)):
				m.estado = P.RONDA
				m.presa = {}
				m.alvo = _ponto_de_ronda(m)
				m.t = _n("cansado_s", 20.0)
				return
			var d := (lider.pos as Vector2).distance_to(alvo)
			var bote := _n("bote_grande", 16.0) if String(m.presa.tipo) == "herbivoro" else _n("bote_rato", 5.0)
			var visto := String(m.presa.tipo) == "herbivoro" and manadas.fugindo(int(m.presa.id))
			if not bool(m.get("correndo", false)) and (d <= bote or visto):
				m.correndo = true
				m.t_corre = 0.0
			if bool(m.get("correndo", false)):
				m.t_corre = float(m.get("t_corre", 0.0)) + dt
			m.alvo = alvo
			for b in _meus(m):
				if (b.pos as Vector2).distance_to(alvo) <= _n("pega", 1.3):
					_pegar(m, alvo)
					return
		P.COMER:
			if float(m.t) <= 0.0:
				_terminar_de_comer(m)
		P.BRIGA:
			if float(m.t) <= 0.0:
				m.estado = int(m.get("antes", P.VOLTA))
		P.FUGA:
			if float(m.t) <= 0.0 or (lider.pos as Vector2).distance_to(m.alvo) < 1.5:
				m.estado = P.VOLTA
		P.VOLTA:
			if (lider.pos as Vector2).distance_to(m.covil) < 2.0:
				m.estado = P.COVIL
				m.t = _rng.randf_range(20.0, 60.0)


func _ponto_de_ronda(m: Dictionary) -> Vector2:
	var lider := _lider(m)
	var de: Vector2 = lider.pos if not lider.is_empty() else m.covil
	for tentativa in 12:
		var p: Vector2 = (m.covil as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, _n("territorio", 60.0))
		var tl := Vector2i(p.floor())
		if eco.passavel(p) and not eco.perto_de_construcao(tl, int(_n("longe_construcao", 16)) - 6) \
				and eco.disturbio(p) < _n("disturbio_foge", 0.5) * 0.6 and eco.linha_passavel(de, p):
			return p
	return m.covil


func _pegar(m: Dictionary, alvo: Vector2) -> void:
	var pr: Dictionary = m.presa
	if String(pr.tipo) == "herbivoro":
		manadas.matar(int(pr.id), String(m.especie))
		m.t = _n("comer_grande_s", 45.0)
	else:
		ratos.matar(int(pr.id), String(m.especie))
		m.t = _n("comer_rato_s", 8.0)
	eventos.append({"tipo": "pegou", "matilha": m.id, "presa": pr.tipo, "pos": alvo})
	m.estado = P.COMER
	m.alvo = alvo
	m.comida = pr.tipo
	m.presa = {}
	m.correndo = false


func _terminar_de_comer(m: Dictionary) -> void:
	if eco != null and carcacas != null:
		for f in eco.comida_perto(m.alvo, 2.5, "carcaca"):       # comer = a carne vai mais rápido para os ossos
			var parte := _n("come_parte", 0.6) if String(m.get("comida", "")) == "herbivoro" else 1.0
			carcacas.bicar(int(f.id), float(f.get("vida", 600.0)) * parte)
			break
	m.fome = 0.0
	m.estado = P.VOLTA


# ------------------------------------------------------------------ um bicho
func _bicho(b: Dictionary, dt: float) -> void:
	if not matilhas.has(int(b.matilha)):
		return
	var m: Dictionary = matilhas[int(b.matilha)]
	var meus := _meus(m)
	var lider: Dictionary = meus[0]
	var eu_lider := int(lider.id) == int(b.id)
	var atras := Vector2.from_angle(float(lider.rumo) + PI)
	var fila: Vector2 = (lider.pos as Vector2) + atras * (1.6 * float(b.ordem)) \
			+ Vector2(-atras.y, atras.x) * (0.8 if int(b.ordem) % 2 == 1 else -0.8) * minf(1.0, float(b.ordem))
	match int(m.estado):
		P.COVIL:
			if eco.andar_grande(b, (m.covil as Vector2) + (b.lugar as Vector2), _n("vel_andar", 1.4), dt, 0.3):
				b.estado = E.DEITADO
			else:
				b.estado = E.ANDANDO
		P.RONDA, P.VOLTA:
			b.estado = E.ANDANDO
			var alvo: Vector2 = (m.alvo if int(m.estado) == P.RONDA else m.covil) if eu_lider else fila
			eco.andar_grande(b, alvo, _n("vel_andar", 1.4) * (1.0 if eu_lider else 1.3), dt, 0.6)
		P.CACA:
			var alvo: Vector2 = m.alvo
			if bool(m.get("correndo", false)):
				b.estado = E.CORRENDO
				eco.andar_grande(b, alvo, _n("vel_correr", 9.2), dt, 0.1)
			else:
				b.estado = E.ESPREITANDO
				var lado := Vector2.from_angle((alvo - (b.pos as Vector2)).angle() + PI * 0.5) * (float(b.ordem) - 1.0) * 2.5
				eco.andar_grande(b, alvo + (lado if not eu_lider else Vector2.ZERO), _n("vel_espreita", 1.4), dt, 0.6)
		P.COMER:
			var lugar: Vector2 = (m.alvo as Vector2) + Vector2.from_angle(TAU * float(b.ordem) / maxf(1.0, meus.size())) * 1.15
			if eco.andar_grande(b, lugar, _n("vel_andar", 1.4) * 1.5, dt, 0.2):
				b.estado = E.COMENDO
				b.rumo = lerp_angle(float(b.rumo), ((m.alvo as Vector2) - (b.pos as Vector2)).angle(), minf(1.0, dt * 4.0))
			else:
				b.estado = E.ANDANDO
		P.BRIGA:
			_brigar(b, m, dt)
		P.FUGA:
			b.estado = E.CORRENDO
			eco.andar_grande(b, (m.alvo as Vector2) if eu_lider else fila, _n("vel_correr", 9.2) * (0.9 if eu_lider else 1.0), dt, 0.6)


## Briga: cada um vai na aranha/larva hostil mais perto e morde.
func _brigar(b: Dictionary, m: Dictionary, dt: float) -> void:
	var alvo: Variant = null
	if colonia != null and colonia.aranhas.has(int(b.inimigo)):
		alvo = colonia.aranhas[int(b.inimigo)].pos
	else:
		b.inimigo = -1
		var md := _n("ve", 14.0) * 1.5
		for a in eco.perto(b.pos, md, "alien"):
			if Colonia.hostil_em(String(b.especie), String(a.get("especie", "aranha"))):
				var d := (a.pos as Vector2).distance_to(b.pos)
				if d < md:
					md = d
					b.inimigo = int(a.id)
					alvo = a.pos
	if alvo == null:
		b.estado = E.ANDANDO
		eco.andar_grande(b, m.covil, _n("vel_andar", 1.4), dt, 1.0)
		return
	var d := (b.pos as Vector2).distance_to(alvo)
	if d <= _n("morde_dist", 1.7):
		b.estado = E.MORDENDO
		b.rumo = lerp_angle(float(b.rumo), ((alvo as Vector2) - (b.pos as Vector2)).angle(), minf(1.0, dt * 6.0))
		if colonia != null and colonia.aranhas.has(int(b.inimigo)):
			colonia.ferir_aranha(int(b.inimigo), _n("dano", 16.0) * dt, String(b.especie))
	else:
		b.estado = E.CORRENDO
		eco.andar_grande(b, alvo, _n("vel_correr", 9.2) * 0.8, dt, _n("morde_dist", 1.7) * 0.8)


# ------------------------------------------------------------------ save
func estado() -> Dictionary:
	return {"matilhas": matilhas, "bichos": bichos, "prox": _prox, "rng": _rng.state}


func restaurar(d: Dictionary) -> void:
	matilhas = {}
	for k in d.get("matilhas", {}):
		var m: Dictionary = d.matilhas[k]
		m.estado = P.VOLTA                                  # carregou: voltam ao covil
		m.presa = {}
		m.correndo = false
		matilhas[int(k)] = m
	bichos = {}
	for k in d.get("bichos", {}):
		var b: Dictionary = d.bichos[k]
		b.matilha = int(b.matilha)
		b.inimigo = -1
		bichos[int(k)] = b
	_prox = int(d.get("prox", 1))
	_rng.state = int(d.get("rng", _rng.state))
