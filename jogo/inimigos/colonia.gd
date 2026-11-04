class_name Colonia
extends RefCounted
## As aranhas do planeta, lógica pura (o desenho fica em DesenhoColonia). O planeta reage à poluição:
##
##  ninhos   nascem do mapa (um sorteio por célula de 48×48, longe do spawn) e são estruturas no MapaOcupacao.
##           Cada ninho absorve a poluição do próprio chunk; essa "raiva" vira aranha (custo_aranha).
##  ataque   juntou grupo_ataque aranhas paradas → o grupo marcha até a fonte de poluição mais perto do ninho.
##           No caminho, estrutura alta (muro, máquina) que barra a passagem é atacada; esteira e trilho, baixos,
##           ficam por baixo das pernas. Água desvia. Sem alvo perto, voltam para o ninho.
##  expansão de tempos em tempos um ninho que absorveu poluição manda construtoras a 14–30 tiles, a 26+ de qualquer estrutura; elas erguem um
##           ninho novo (obra de 10 s) que depois produz aranhas como os outros.
##  fúria    chão sujo em volta do ninho (AmbienteVivo.furia_em) deixa as aranhas furiosas: nascem mais rápido,
##           atacam em grupos menores e de mais longe, andam mais rápido e mordem mais forte.
##  torres   atiram na aranha mais perto (ou no ninho, se não houver aranha) dentro do alcance. A torre de energia
##           gasta a carga guardada da rede (munição é reserva); a metralhadora (torre_metralhadora) só atira bala:
##           cada munição que chega por braço/esteira vira Fabrica.TIROS_POR_MUNICAO tiros, até municao_max.
##           Tiro de bala sai com "bala" no evento (o desenho ejeta a cápsula). Melhorias: dano_bala, cadencia_bala.
##           Torre de projétil (lança-foguetes, artilharia: regra "projetil"): o tiro voa (velocidade, tempo) e explode
##           no ponto mirado com dano em área ("raio"; cai até a metade na borda). A munição é o item da regra
##           "municao_item" (foguete, granada), "tiros_por_item" tiros cada. Artilharia ("alvo": "ninhos") só mira
##           ninhos, entre alcance_min e alcance. Melhorias pela regra: bonus_dano, bonus_cadencia, bonus_alcance.
##  mina     mina de pulso (regra "pulso"): aranha a menos de "gatilho" dispara; toda aranha no "raio" fica atordoada
##           (parada, sem morder) por "atordoa" s; a mina rearma em "rearme" s.
##  escudo   gerador de escudo (regra "escudo"): mordida em estrutura que fica no raio da bolha não tira vida — gasta
##           a energia guardada do gerador (mj_por_dano, via torre_energia = Fabrica.gastar_torre); sem carga, passa.
##  campo    muro de campo (regra "regenera"): recupera ♥/s × energia da rede que chega nele (callable `energia`).
##
## Tudo que o desenho precisa saber sai em `eventos` (tiro, morte, ninho novo, estrutura destruída) a cada tick.

enum E { PARADA, ATACANDO, VOLTANDO, CONSTRUINDO, OBRA }
const FURIA_ZERO := 0.01     ## fúria até aqui conta como "em paz" (Convivência com ninhos, Simbiose)
const TORRES := ["torre_defesa", "torre_metralhadora", "torre_foguetes", "artilharia"]

var mapa: MapaOcupacao
var poluicao: Poluicao
var ambiente: AmbienteVivo        ## (opcional) de onde vem a fúria
var ninhos: Dictionary = {}       ## id da estrutura → {id, centro: Vector2, vida, raiva, obra (0..1; 1 = pronto)}
var aranhas: Dictionary = {}      ## id → {id, pos: Vector2, vida, ninho, estado, alvo (id estrutura), destino: Vector2, mordendo}
var torres: Dictionary = {}       ## id da estrutura → {municao, recarga, mira: Vector2, mirando}
var torre_energia: Callable       ## func(id, mj) -> bool: tiro com a energia guardada na torre (Fabrica.gastar_torre)
var energia: Callable             ## (opcional) func(id) -> float 0..1: energia da rede que chega na estrutura (muro de campo)
var projeteis: Array[Dictionary] = []   ## foguetes/granadas no ar: {torre, nome, de, para, t, dur, dano, raio}
var minas: Dictionary = {}        ## id da mina → {recarga: s até rearmar (0 = armada)}
var _lista_minas: Array[int] = []
var _lista_escudos: Array[int] = []
var _t_escudo: Dictionary = {}    ## id do gerador → s até o próximo evento de impacto (desenho)
var bonus: Callable               ## (opcional) func(chave) -> float: melhorias pesquisadas (Pesquisa.bonus)
var artilharia_auto: Callable     ## (opcional) func() -> bool: Mira automática pesquisada? Sem ela, a artilharia só atira com a ordem do painel. Vazio = atira sozinha
var harmonia: Callable            ## (opcional) func() -> bool: Convivência com ninhos (ninho com fúria 0 não expande rumo à fábrica)
var ninhos_paz: Callable          ## (opcional) func() -> bool: Simbiose (ninho com fúria 0 não ataca)
var vida: Dictionary = {}         ## id da estrutura → vida atual (só as que levaram dano)
var eventos: Array[Dictionary] = []
## Quem tira do mapa a estrutura que as aranhas derrubaram (o mundo troca por Construtor.destruir + desenho).
var destruir: Callable
var _celulas: Dictionary = {}
var _prox := 1
var _rng := RandomNumberGenerator.new()
var _lista_torres: Array[int] = []      ## cache: refeito só quando o mapa muda de tamanho
var _tamanho_mapa := -1                 ## versão do mapa da última lista
var _t_expansao := 0.0
var _n: Dictionary
var _a: Dictionary
var _x: Dictionary
var _f: Dictionary


func _init(p_mapa: MapaOcupacao, p_poluicao: Poluicao, semente := 7) -> void:
	mapa = p_mapa
	poluicao = p_poluicao
	_rng.seed = semente
	_n = Registro.inimigos.get("ninho", {})
	_a = Registro.inimigos.get("aranha", {})
	_x = Registro.inimigos.get("expansao", {})
	_f = Registro.inimigos.get("furia", {})
	_t_expansao = _x.get("intervalo_s", 150.0)
	destruir = func(id: int) -> void: mapa.remover(id)


# ------------------------------------------------------------------ ninhos do mapa
## Garante os ninhos das células que tocam o chunk (chamado quando o chunk aparece). Determinístico pela semente.
func descobrir_chunk(k: Vector2i) -> void:
	var cel: int = _n.get("celula", 48)
	var a := Vector2(k * Grade.TAM_CHUNK) / cel
	var b := Vector2((k + Vector2i.ONE) * Grade.TAM_CHUNK) / cel
	for cx in range(floori(a.x), ceili(b.x)):
		for cy in range(floori(a.y), ceili(b.y)):
			var c := Vector2i(cx, cy)
			if _celulas.has(c):
				continue
			_celulas[c] = true
			_ninho_da_celula(c, cel)


func _ninho_da_celula(c: Vector2i, cel: int) -> void:
	var centro := (Vector2(c) + Vector2(0.5, 0.5)) * cel
	var dist := centro.length()
	var raio: float = _n.get("raio_sem_ninho", 52)
	if dist < raio:
		return
	var chance: float = _n.get("chance", 0.6) if dist < raio * 2.0 else _n.get("chance_longe", 0.9)
	if Distribuicao.h(c.x, c.y, 501) > chance:
		return
	for tentativa in 8:
		var off := Vector2i(int(Distribuicao.h(c.x, c.y, 510 + tentativa) * (cel - 8)) + 2,
				int(Distribuicao.h(c.x, c.y, 520 + tentativa) * (cel - 8)) + 2)
		var minimo := c * cel + off
		if (Vector2(minimo) + Vector2(1.5, 1.5)).length() < raio:
			continue
		if mapa.motivo_bloqueio("ninho_aranha", minimo, 0) == "":
			var id := _criar_ninho(minimo, 1.0)
			for i in int(_n.get("aranhas_iniciais", 2)):
				_nova_aranha(id)
			return


func _criar_ninho(minimo: Vector2i, obra: float) -> int:
	var id := mapa.colocar("ninho_aranha", minimo, 0)
	if id < 0:
		return -1
	ninhos[id] = {"id": id, "centro": Vector2(minimo) + Vector2(1.5, 1.5), "vida": float(_n.get("vida", 400)),
			"raiva": 0.0, "obra": obra, "absorvido": 0.0, "idade": Infestacao.MADURA_S if obra >= 1.0 else 0.0}
	eventos.append({"tipo": "ninho_novo", "id": id, "obra": obra})
	return id


func _nova_aranha(ninho: int) -> int:
	var n: Dictionary = ninhos[ninho]
	var id := _prox
	_prox += 1
	var ang := _rng.randf() * TAU
	aranhas[id] = {"id": id, "pos": n.centro + Vector2.from_angle(ang) * 2.4, "vida": float(_a.get("vida", 60)),
			"ninho": ninho, "estado": E.PARADA, "alvo": -1, "destino": n.centro + Vector2.from_angle(ang) * 2.4,
			"mordendo": false, "t": _rng.randf() * 5.0, "preso": 0.0}
	eventos.append({"tipo": "aranha_nova", "id": id})
	return id


func aranhas_do_ninho(ninho: int, estado := -1) -> Array[int]:
	var out: Array[int] = []
	for id in aranhas:
		var ar: Dictionary = aranhas[id]
		if ar.ninho == ninho and (estado < 0 or ar.estado == estado):
			out.append(id)
	return out


# ------------------------------------------------------------------ tick
## fontes: [{id (estrutura), pos: Vector2}] — quem polui (alvo dos ataques).
func tick(dt: float, fontes: Array[Dictionary]) -> void:
	eventos.clear()
	_listas()
	_ninhos(dt, fontes)
	_obras(dt)
	for id in aranhas.keys():
		if aranhas.has(id):
			_aranha(aranhas[id], dt)
	_separar()
	_torres(dt)
	_voar(dt)
	_minas(dt)
	_regenerar(dt)
	_expandir(dt)


func _ninhos(dt: float, fontes: Array[Dictionary]) -> void:
	var custo: float = _n.get("custo_aranha", 16)
	var maximo: int = _n.get("max_aranhas", 8)
	var grupo: int = _n.get("grupo_ataque", 4)
	# Convivência com ninhos: 25% menos grupos de ataque = aranhas 1/0,75 mais caras (o ninho junta raiva no mesmo ritmo)
	var menos_grupos := clampf(_bonus("grupos_ataque"), 0.0, 0.9)
	var paz := ninhos_paz.is_valid() and bool(ninhos_paz.call())
	for id in ninhos.keys():
		var n: Dictionary = ninhos[id]
		if not mapa.estruturas.has(id):
			ninhos.erase(id)
			continue
		if n.obra < 1.0:
			continue
		n.idade = float(n.get("idade", 0.0)) + dt          # a infestação do chão em volta cresce com ela (Infestacao)
		n.t_furia = float(n.get("t_furia", 0.0)) - dt
		if n.t_furia <= 0.0:
			n.t_furia = float(_f.get("recalcula_s", 5.0))
			n.furia = ambiente.furia_em(n.centro) if ambiente != null else 0.0
		var fu := float(n.get("furia", 0.0))
		var k := Grade.chunk_de(Vector2i(n.centro.floor()))
		var tirou := poluicao.absorver(k, poluicao.em_chunk(k) * float(_n.get("taxa_absorcao", 0.06)) * dt)
		n.raiva += tirou
		n.absorvido += tirou
		var custo_aqui := custo / (1.0 + float(_f.get("producao", 1.0)) * fu) / (1.0 - menos_grupos)
		if n.raiva >= custo_aqui and aranhas_do_ninho(id).size() < maximo:
			n.raiva -= custo_aqui
			_nova_aranha(id)
		if paz and fu <= FURIA_ZERO:                      # Simbiose: ninho em paz não manda grupo
			continue
		var grupo_aqui := maxi(2, grupo - roundi(float(_f.get("grupo_menos", 2)) * fu))
		var paradas := aranhas_do_ninho(id, E.PARADA)
		if paradas.size() >= grupo_aqui:
			var alvo := _fonte_mais_perto(n.centro, fontes, 1.0 + float(_f.get("raio_ataque", 0.5)) * fu)
			if alvo >= 0:
				for a in paradas.slice(0, grupo_aqui):
					aranhas[a].estado = E.ATACANDO
					aranhas[a].alvo = alvo
				eventos.append({"tipo": "ataque", "ninho": id, "alvo": alvo})


func _fonte_mais_perto(p: Vector2, fontes: Array[Dictionary], mult := 1.0) -> int:
	var melhor := -1
	var md: float = float(_n.get("raio_ataque", 160)) * mult
	for f in fontes:
		if not mapa.estruturas.has(f.id):
			continue
		var d: float = p.distance_to(f.pos)
		if d < md:
			md = d
			melhor = f.id
	return melhor


func _aranha(ar: Dictionary, dt: float) -> void:
	ar.mordendo = false
	ar.t += dt
	if float(ar.get("atordoada", 0.0)) > 0.0:          # pulso da mina: parada, sem morder
		ar.atordoada = maxf(0.0, float(ar.atordoada) - dt)
		return
	# presa (água no caminho, sem saída): desiste da obra/ataque; presa voltando, some no chão de volta ao ninho
	if ar.preso > 15.0 and ar.estado in [E.ATACANDO, E.CONSTRUINDO, E.VOLTANDO]:
		ar.preso = 0.0
		if ar.estado == E.VOLTANDO or not ninhos.has(ar.ninho):
			aranhas.erase(ar.id)
			eventos.append({"tipo": "aranha_sumiu", "id": ar.id})
			return
		if ar.estado in [E.ATACANDO, E.CONSTRUINDO]:
			ar.estado = E.VOLTANDO
	match ar.estado:
		E.PARADA:
			if not ninhos.has(ar.ninho):
				ar.estado = E.ATACANDO                      # ninho caiu: as que sobraram vão à luta
				ar.alvo = _estrutura_perto(ar.pos, float(_a.get("raio_procura", 20)) * 3.0)
				return
			# rondando o ninho
			if ar.pos.distance_to(ar.destino) < 0.3:
				var n: Dictionary = ninhos[ar.ninho]
				ar.destino = n.centro + Vector2.from_angle(_rng.randf() * TAU) * (2.2 + _rng.randf() * 1.6)
			_mover(ar, ar.destino, dt, 0.35)
		E.ATACANDO:
			if not mapa.estruturas.has(ar.alvo):
				ar.alvo = _estrutura_perto(ar.pos, float(_a.get("raio_procura", 20)))
				if ar.alvo < 0:
					ar.estado = E.VOLTANDO
					return
			var e: Dictionary = mapa.estruturas[ar.alvo]
			if _dist_estrutura(ar.pos, e) <= float(_a.get("alcance", 1.2)):
				_morder(ar, ar.alvo, dt)
			else:
				_mover(ar, Grade.centro_da_area(e.minimo, e.area, e.rot), dt, 1.0)
		E.VOLTANDO:
			if not ninhos.has(ar.ninho):
				ar.estado = E.ATACANDO
				return
			var n: Dictionary = ninhos[ar.ninho]
			if ar.pos.distance_to(n.centro) < 2.6:
				ar.estado = E.PARADA
				ar.destino = ar.pos
			else:
				_mover(ar, n.centro, dt, 1.0)
		E.CONSTRUINDO:
			if ar.pos.distance_to(ar.destino) < 0.6:
				_chegou_obra(ar)
			else:
				_mover(ar, ar.destino, dt, 1.0)
		E.OBRA:
			if not ninhos.has(ar.ninho):
				ar.estado = E.ATACANDO
				ar.alvo = -1
				return
			var n: Dictionary = ninhos[ar.ninho]
			if n.obra >= 1.0:
				ar.estado = E.PARADA
				ar.destino = ar.pos
				return
			var ang: float = ar.t * 0.8 + ar.id
			_mover(ar, n.centro + Vector2.from_angle(ang) * 2.3, dt, 0.5)
			ar.mordendo = true                              # pernas trabalhando na obra


## Anda em linha reta; água desvia (tenta ângulos maiores); estrutura alta no caminho vira alvo de mordida.
func _mover(ar: Dictionary, para: Vector2, dt: float, ritmo: float) -> void:
	var d: Vector2 = para - ar.pos
	if d.length() < 0.05:
		return
	# "presa" = não chega mais perto do destino (andar em círculo num cercado também conta)
	if ar.get("para_ant", Vector2.INF) != para:
		ar.para_ant = para
		ar.melhor = INF
		ar.preso = 0.0
	if d.length() < ar.melhor - 0.3:
		ar.melhor = d.length()
		ar.preso = 0.0
	else:
		ar.preso += dt
	var dir := d.normalized()
	var passo: float = minf(float(_a.get("velocidade", 1.4)) * (1.0 + float(_f.get("velocidade", 0.4)) * furia(ar)) * ritmo * dt, d.length())
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, 2.6, -2.6]:
		var tent := dir.rotated(ang)
		var novo: Vector2 = ar.pos + tent * passo
		if mapa.gerador.eh_agua(mapa.gerador.terreno(Vector2i((ar.pos + tent * 0.7).floor()))):
			continue
		# corpo com raio: nenhuma parte da aranha entra numa construção (nem no alvo: morde pela borda)
		var bloq := _corpo_bloqueado(novo)
		if bloq >= 0 and ar.estado == E.ATACANDO and ang == 0.0:
			_morder(ar, bloq, dt)                        # no caminho (ou é o alvo): morde dali
			return
		if bloq >= 0:
			continue
		ar.pos = novo
		return


const RAIO_CORPO := 0.55     ## aranha + pernas no chão: distância mínima de qualquer construção que barra


## Construção que o corpo da aranha tocaria nesta posição (−1 = livre).
func _corpo_bloqueado(p: Vector2) -> int:
	for o in [Vector2.ZERO, Vector2(RAIO_CORPO, 0), Vector2(-RAIO_CORPO, 0), Vector2(0, RAIO_CORPO), Vector2(0, -RAIO_CORPO),
			Vector2(0.39, 0.39), Vector2(-0.39, 0.39), Vector2(0.39, -0.39), Vector2(-0.39, -0.39)]:
		var b := _bloqueio(Vector2i((p + o).floor()))
		if b >= 0:
			return b
	return -1


## Estrutura que barra a passagem neste tile (alta o bastante); ninho não barra aranha.
func _bloqueio(t: Vector2i) -> int:
	var id: int = mapa.tiles.get(t, -1)
	if id < 0:
		return -1
	var nome: String = mapa.estruturas[id].nome
	if nome == "ninho_aranha":
		return -1
	var dims: Array = Registro.modelos.get(nome, {}).get("dims", [0, 0, 0])
	return id if float(dims[2]) > float(_a.get("altura_que_bloqueia", 0.5)) else -1


func _morder(ar: Dictionary, id: int, dt: float) -> void:
	ar.mordendo = true
	ar.preso = 0.0                                    # mordendo está fazendo progresso
	if not mapa.estruturas.has(id):
		return
	var em: Dictionary = mapa.estruturas[id]
	ar.mordida = Grade.centro_da_area(em.minimo, em.area, em.rot)       # para onde as pernas golpeiam (desenho)
	var nome: String = mapa.estruturas[id].nome
	var dano := float(_a.get("dano", 15)) * (1.0 + float(_f.get("dano", 0.8)) * furia(ar)) * dt
	if _escudo_absorve(id, dano, ar.pos):
		return
	var v: float = vida.get(id, float(Registro.estruturas.get(nome, {}).get("vida", 100)))
	v -= dano
	vida[id] = v
	if v <= 0.0:
		vida.erase(id)
		var e: Dictionary = mapa.estruturas[id]
		eventos.append({"tipo": "destruida", "id": id, "nome": nome, "centro": Grade.centro_da_area(e.minimo, e.area, e.rot)})
		destruir.call(id)


## Ninhos com fúria a partir de `limite` (aviso da Leitura ambiental).
func ninhos_furiosos(limite := 0.5) -> Array:
	var out := []
	for id in ninhos:
		if float(ninhos[id].get("furia", 0.0)) >= limite:
			out.append(id)
	return out


## Fúria da aranha = a do ninho dela (0 se o ninho caiu).
func furia(ar: Dictionary) -> float:
	var n: Variant = ninhos.get(ar.ninho)
	return float(n.get("furia", 0.0)) if n != null else 0.0


func _estrutura_perto(p: Vector2, raio: float) -> int:
	var melhor := -1
	var md := raio
	for id in mapa.estruturas:
		var e: Dictionary = mapa.estruturas[id]
		if e.nome == "ninho_aranha" or e.nome == "pilar":
			continue
		var d := _dist_estrutura(p, e)
		if d < md:
			md = d
			melhor = id
	return melhor


static func _dist_estrutura(p: Vector2, e: Dictionary) -> float:
	var a := Vector2(e.minimo)
	var r := Rect2(a, Vector2(Grade.area_girada(e.area, e.rot)))
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


## Aranhas não se empilham (empurrão leve entre vizinhas).
func _separar() -> void:
	var lista := aranhas.values()
	for i in lista.size():
		for j in range(i + 1, lista.size()):
			var d: Vector2 = lista[j].pos - lista[i].pos
			var l := d.length()
			if l < 1.4 and l > 1e-4:
				var em := d / l * (1.4 - l) * 0.25
				# o empurrão nunca joga uma aranha para dentro de uma construção
				if _corpo_bloqueado(lista[i].pos - em) < 0:
					lista[i].pos -= em
				if _corpo_bloqueado(lista[j].pos + em) < 0:
					lista[j].pos += em


# ------------------------------------------------------------------ torres
## Torres, minas e geradores de escudo do mapa (refeito só quando o mapa muda).
func _listas() -> void:
	if mapa.versao == _tamanho_mapa:
		return
	_tamanho_mapa = mapa.versao
	_lista_torres.clear()
	_lista_minas.clear()
	_lista_escudos.clear()
	for id in mapa.estruturas:
		var nome: String = mapa.estruturas[id].nome
		var r: Dictionary = Registro.estruturas.get(nome, {})
		if nome in TORRES:
			_lista_torres.append(id)
		elif r.has("pulso"):
			_lista_minas.append(id)
		elif r.has("escudo"):
			_lista_escudos.append(id)


## Alcance da torre (melhoria de alcance pela regra "bonus_alcance").
func alcance_de(nome: String) -> float:
	var regra: Dictionary = Registro.estruturas.get(nome, {})
	return float(regra.get("alcance", 18)) * (1.0 + _bonus(String(regra.get("bonus_alcance", ""))))


func _torres(dt: float) -> void:
	for id in _lista_torres:
		if not mapa.estruturas.has(id):
			continue
		var e: Dictionary = mapa.estruturas[id]
		_garantir_torre(id)
		var t: Dictionary = torres[id]
		t.recarga -= dt
		var regra: Dictionary = Registro.estruturas[e.nome]
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var alcance := alcance_de(e.nome)
		var minimo := float(regra.get("alcance_min", 0.0))
		var alvo := -1
		var md := alcance
		if regra.get("alvo", "") != "ninhos":
			for a in aranhas:
				var d: float = c.distance_to(aranhas[a].pos)
				if d < md and d >= minimo:
					md = d
					alvo = a
		var ninho := -1
		if alvo < 0 and _pode_mirar_ninho(regra, t):
			for n in ninhos:
				var d: float = c.distance_to(ninhos[n].centro)
				if d < md and d >= minimo:
					md = d
					ninho = n
		t.mirando = alvo >= 0 or ninho >= 0
		if ninho < 0 and t.has("ordem"):
			t.erase("ordem")                                  # não há mais ninho no alcance: a ordem acabou
		if not t.mirando:
			continue
		t.mira = aranhas[alvo].pos if alvo >= 0 else ninhos[ninho].centro
		if t.recarga > 0.0:
			continue
		# torre de energia: atira com a energia guardada; munição (se algum braço trouxe) é a reserva quando a energia
		# acaba. Torres de munição (sem carga_mj): só com o item delas, na cadência delas (+ melhoria da regra).
		var chave := "dano_torre_energia"                     # melhoria que vale para este tiro
		var cadencia := float(regra.get("cadencia", 3))
		var bala := false
		var municao := ""                                     # munição especial usada (vazio = a comum)
		var efeito := {}                                       # munição especial deste tiro (regra municao_especial)
		if regra.has("carga_mj") and torre_energia.is_valid() and torre_energia.call(id, tiro_mj()):
			cadencia *= 1.0 + _bonus("cadencia_torre_energia")
		elif t.municao > 0 or not especial_da_vez(t, regra).is_empty():
			var esp := especial_da_vez(t, regra)
			if esp.is_empty():
				t.municao -= 1
			else:
				t.especial[esp] = int(t.especial[esp]) - 1
				efeito = regra.municao_especial[esp]
				municao = esp
			chave = String(regra.get("bonus_dano", "dano_bala"))
			bala = true
			if not regra.has("carga_mj"):
				cadencia *= 1.0 + _bonus(String(regra.get("bonus_cadencia", "cadencia_bala")))
		else:
			continue
		t.recarga = maxf(t.recarga, -dt) + 1.0 / cadencia   # sobra do tick conta: 10 tiros/s mesmo a 30 quadros/s
		var dano: float = float(regra.get("dano", 8)) * (1.0 + _bonus(chave)) * float(efeito.get("dano", 1.0))
		var ev := {"tipo": "tiro", "torre": id, "nome": e.nome, "bala": bala, "municao": municao, "de": c, "para": t.mira, "aranha": alvo, "ninho": ninho}
		if regra.has("projetil"):                       # foguete/granada: voa e explode no ponto mirado
			var pj: Dictionary = regra.projetil
			var dur := c.distance_to(t.mira) / float(pj.get("velocidade", 25.0)) + float(pj.get("tempo_extra", 0.0))
			projeteis.append({"torre": id, "nome": e.nome, "de": c, "para": t.mira, "t": 0.0, "dur": dur, "dano": dano,
					"raio": float(pj.get("raio", 2.0)), "ogivas": int(efeito.get("ogivas", 0)), "ogiva_dano": float(efeito.get("ogiva_dano", 0.5)),
					"ogiva_raio": float(efeito.get("ogiva_raio", 2.0)), "abre": float(efeito.get("abre", 3.0))})
			ev.projetil = true
			ev.dur = dur
			eventos.append(ev)
			continue
		eventos.append(ev)
		if alvo >= 0:
			var de_onde: Vector2 = aranhas[alvo].pos
			_ferir_aranha(alvo, dano)
			_efeito_bala(efeito, alvo, de_onde, dano)
		else:
			_ferir_ninho(ninho, dano)


## A ordem do painel vale para a artilharia ("alvo": "ninhos"); sem a Mira automática, ela só atira com a ordem.
func _pode_mirar_ninho(regra: Dictionary, t: Dictionary) -> bool:
	if regra.get("alvo", "") != "ninhos" or not artilharia_auto.is_valid() or bool(artilharia_auto.call()):
		return true
	return bool(t.get("ordem", false))


## A artilharia está esperando ordem (sem a Mira automática)?
func artilharia_espera_ordem(id: int) -> bool:
	return artilharia_auto.is_valid() and not bool(artilharia_auto.call()) and not bool(torres.get(id, {}).get("ordem", false))


## Ordem do painel: a artilharia atira nos ninhos no alcance até não sobrar nenhum.
func ordenar_disparo(id: int) -> void:
	_garantir_torre(id)
	torres[id]["ordem"] = true


## Bala especial: perfurante atravessa para a(s) aranha(s) mais perto (dano cheio); carregada salta (arco, dano menor).
func _efeito_bala(efeito: Dictionary, alvo: int, de: Vector2, dano: float) -> void:
	if efeito.is_empty():
		return
	var atravessa := int(efeito.get("atravessa", 0))
	var salta := int(efeito.get("salta", 0))
	var n := atravessa + salta
	if n <= 0:
		return
	var raio := float(efeito.get("raio_atravessa", efeito.get("raio_salto", 3.0)))
	var perto: Array = []
	for a in aranhas:
		if a != alvo and aranhas[a].pos.distance_to(de) <= raio:
			perto.append(a)
	perto.sort_custom(func(x, y): return aranhas[x].pos.distance_to(de) < aranhas[y].pos.distance_to(de))
	for a in perto.slice(0, n):
		var para: Vector2 = aranhas[a].pos
		eventos.append({"tipo": "salto", "de": de, "para": para, "eletrico": salta > 0})
		_ferir_aranha(a, dano * (float(efeito.get("salto_dano", 1.0)) if salta > 0 else 1.0))


## Tiro de fora da colônia (drone de combate): fere a aranha se ela ainda existe.
func ferir_aranha(a: int, dano: float) -> void:
	if aranhas.has(a):
		_ferir_aranha(a, dano)


func _ferir_aranha(a: int, dano: float) -> void:
	aranhas[a].vida -= dano
	if aranhas[a].vida <= 0.0:
		eventos.append({"tipo": "aranha_morta", "id": a, "pos": aranhas[a].pos})
		aranhas.erase(a)


func _ferir_ninho(n: int, dano: float) -> void:
	ninhos[n].vida -= dano
	if ninhos[n].vida <= 0.0:
		eventos.append({"tipo": "ninho_destruido", "id": n, "pos": ninhos[n].centro})
		ninhos.erase(n)
		mapa.remover(n)


## Foguetes e granadas no ar: chegou, explode (dano em área, metade na borda do raio; ninho conta pela borda).
func _voar(dt: float) -> void:
	if projeteis.is_empty():
		return
	var vivos: Array[Dictionary] = []
	for p in projeteis:
		p.t += dt
		if p.t < p.dur:
			vivos.append(p)
			continue
		var onde: Vector2 = p.para
		if int(p.get("ogivas", 0)) > 0:                  # foguete de enxame: abre em ogivas menores em volta do ponto
			for k in int(p.ogivas):
				var alvo_og: Vector2 = onde + Vector2.from_angle(TAU * k / float(p.ogivas)) * float(p.abre)
				vivos.append({"torre": p.torre, "nome": p.nome, "de": onde, "para": alvo_og, "t": 0.0, "dur": 0.25,
						"dano": float(p.dano) * float(p.ogiva_dano), "raio": float(p.ogiva_raio)})
			eventos.append({"tipo": "explosao", "torre": p.torre, "nome": p.nome, "pos": onde, "raio": 1.0})
			continue
		eventos.append({"tipo": "explosao", "torre": p.torre, "nome": p.nome, "pos": onde, "raio": p.raio})
		for a in aranhas.keys():
			var d: float = aranhas[a].pos.distance_to(onde)
			if d <= p.raio:
				_ferir_aranha(a, p.dano * (1.0 - 0.5 * d / p.raio))
		for n in ninhos.keys():
			if ninhos[n].centro.distance_to(onde) <= p.raio + 1.5:
				_ferir_ninho(n, p.dano)
	projeteis = vivos


# ------------------------------------------------------------------ mina de pulso
func _minas(dt: float) -> void:
	for id in _lista_minas:
		if not mapa.estruturas.has(id):
			minas.erase(id)
			continue
		if not minas.has(id):
			minas[id] = {"recarga": 0.0}
		var m: Dictionary = minas[id]
		if m.recarga > 0.0:
			m.recarga = maxf(0.0, m.recarga - dt)
			continue
		var e: Dictionary = mapa.estruturas[id]
		var p: Dictionary = Registro.estruturas[e.nome].pulso
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var pisou := false
		for a in aranhas:
			if aranhas[a].pos.distance_to(c) <= float(p.get("gatilho", 1.2)):
				pisou = true
				break
		if not pisou:
			continue
		m.recarga = float(p.get("rearme", 20.0))
		var n := 0
		for a in aranhas:
			if aranhas[a].pos.distance_to(c) <= float(p.get("raio", 3.0)):
				aranhas[a].atordoada = maxf(float(aranhas[a].get("atordoada", 0.0)), float(p.get("atordoa", 3.0)))
				aranhas[a].mordendo = false
				n += 1
		eventos.append({"tipo": "pulso", "id": id, "pos": c, "raio": float(p.get("raio", 3.0)), "atordoadas": n})


## A mina está armada? (rearmando = false)
func mina_armada(id: int) -> bool:
	return float(minas.get(id, {}).get("recarga", 0.0)) <= 0.0


# ------------------------------------------------------------------ escudo e muro de campo
## A mordida em `id` cai num escudo? Gasta a carga do gerador (mj_por_dano) e não tira vida.
func _escudo_absorve(id: int, dano: float, de: Vector2) -> bool:
	if _lista_escudos.is_empty() or not torre_energia.is_valid():
		return false
	var e: Dictionary = mapa.estruturas[id]
	for g in _lista_escudos:
		if not mapa.estruturas.has(g):
			continue
		var eg: Dictionary = mapa.estruturas[g]
		var esc: Dictionary = Registro.estruturas[eg.nome].escudo
		var cg := Grade.centro_da_area(eg.minimo, eg.area, eg.rot)
		var raio := raio_escudo(eg.nome)
		if _dist_estrutura(cg, e) > raio:
			continue
		if not torre_energia.call(g, dano * float(esc.get("mj_por_dano", 0.02))):
			continue
		_t_escudo[g] = float(_t_escudo.get(g, 0.0))
		if _t_escudo[g] <= 0.0:                         # impacto na bolha (desenho): no máximo 4 por segundo
			_t_escudo[g] = 0.25
			var dir := (de - cg)
			eventos.append({"tipo": "escudo", "id": g, "centro": cg, "pos": cg + dir.normalized() * raio if dir.length() > 0.01 else de})
		return true
	return false


## Raio da bolha do gerador de escudo, com a melhoria (escudo 2: "escudo_raio" 0,5 → 8 m vira 12 m).
func raio_escudo(nome: String) -> float:
	return float(Registro.estruturas[nome].escudo.get("raio", 8.0)) * (1.0 + _bonus("escudo_raio"))


func _regenerar(dt: float) -> void:
	for g in _t_escudo.keys():
		_t_escudo[g] = float(_t_escudo[g]) - dt
	for id in vida.keys():
		if not mapa.estruturas.has(id):
			continue
		var r: Dictionary = Registro.estruturas.get(mapa.estruturas[id].nome, {})
		if not r.has("regenera"):
			continue
		var en := float(energia.call(id)) if energia.is_valid() else 0.0
		vida[id] = float(vida[id]) + float(r.regenera) * en * dt
		if float(vida[id]) >= float(r.get("vida", 100)):
			vida.erase(id)


func _bonus(chave: String) -> float:
	return float(bonus.call(chave)) if bonus.is_valid() else 0.0


## Energia de um tiro da torre (MJ): a melhoria "economia_tiro_torre" (cadência de energia 1) gasta menos.
func tiro_mj() -> float:
	return float(Registro.estruturas["torre_defesa"].get("tiro_mj", 0.05)) * maxf(0.1, 1.0 - _bonus("economia_tiro_torre"))


## Munição que chegou à torre (braço/esteira, via Fabrica).
func carregar_torre(id: int, tiros: int) -> void:
	_garantir_torre(id)
	torres[id].municao += tiros


## A torre ainda cabe mais uma munição? (regra municao_max, em tiros; sem ela, cabe sempre.) O braço não entrega
## para a torre cheia: a munição fica no baú/esteira para as outras.
func aceita_municao(id: int) -> bool:
	if not mapa.estruturas.has(id):
		return false
	var nome: String = mapa.estruturas[id].nome
	var maximo := int(Registro.estruturas.get(nome, {}).get("municao_max", 0))
	if maximo <= 0:
		return true
	_garantir_torre(id)
	return int(torres[id].municao) + tiros_especiais(id) + tiros_por_item(nome) <= maximo


## Munição especial que a torre aceita além da comum: item → efeito (dano, atravessa, salta, ogivas, tiros).
static func especiais(nome: String) -> Dictionary:
	return Registro.estruturas.get(nome, {}).get("municao_especial", {})


## Munição especial que chegou à torre (braço/esteira, via Fabrica). A torre gasta a melhor primeiro.
func carregar_especial(id: int, item: String) -> void:
	_garantir_torre(id)
	if not torres[id].has("especial"):
		torres[id]["especial"] = {}
	torres[id].especial[item] = int(torres[id].especial.get(item, 0)) + int(especiais(mapa.estruturas[id].nome)[item].get("tiros", 1))


func tiros_especiais(id: int) -> int:
	var n := 0
	var es: Dictionary = torres.get(id, {}).get("especial", {})
	for k in es:
		n += int(es[k])
	return n


## Que munição especial a torre usa no próximo tiro ("" = a comum): a última da lista da regra que tiver (a mais forte).
func especial_da_vez(t: Dictionary, regra: Dictionary) -> String:
	var es: Dictionary = t.get("especial", {})
	var lista: Array = (regra.get("municao_especial", {}) as Dictionary).keys()
	for i in range(lista.size() - 1, -1, -1):
		if int(es.get(lista[i], 0)) > 0:
			return lista[i]
	return ""


## Item que a torre usa de munição (munição comum, foguete, granada).
static func item_municao(nome: String) -> String:
	return String(Registro.estruturas.get(nome, {}).get("municao_item", "municao"))


## Tiros que cada item de munição rende na torre (bala: Fabrica.TIROS_POR_MUNICAO; foguete e granada: 1).
static func tiros_por_item(nome: String) -> int:
	return int(Registro.estruturas.get(nome, {}).get("tiros_por_item", Fabrica.TIROS_POR_MUNICAO))


func _garantir_torre(id: int) -> void:
	if not torres.has(id):
		var inicial := int(Registro.inimigos.get("torre", {}).get("municao_inicial", 60))
		if mapa.estruturas.has(id):
			inicial = int(Registro.estruturas.get(mapa.estruturas[id].nome, {}).get("municao_inicial", inicial))
		torres[id] = {"municao": inicial, "recarga": 0.0, "mira": Vector2.ZERO, "mirando": false}


# ------------------------------------------------------------------ salvamento
func estado() -> Dictionary:
	return {"ninhos": ninhos, "aranhas": aranhas, "torres": torres, "vida": vida, "celulas": _celulas.keys(),
			"prox": _prox, "t_expansao": _t_expansao, "rng": _rng.state, "projeteis": projeteis, "minas": minas}


func restaurar(d: Dictionary) -> void:
	ninhos = d.ninhos
	aranhas = d.aranhas
	torres = d.torres
	vida = d.vida
	_celulas.clear()
	for c in d.celulas:
		_celulas[c] = true
	_prox = d.prox
	_t_expansao = d.t_expansao
	_rng.state = d.rng
	projeteis.clear()
	for p in d.get("projeteis", []):
		projeteis.append(p)
	minas = d.get("minas", {})
	_tamanho_mapa = -1


# ------------------------------------------------------------------ expansão
func _expandir(dt: float) -> void:
	_t_expansao -= dt
	if _t_expansao > 0.0:
		return
	_t_expansao = _x.get("intervalo_s", 150.0)
	var prontos := []
	for id in ninhos:
		# só expande quem está sendo "irritado" pela poluição (absorveu o bastante desde a última vez)
		if ninhos[id].obra >= 1.0 and ninhos[id].absorvido >= float(_x.get("poluicao_para_expandir", 30)) \
				and aranhas_do_ninho(id, E.PARADA).size() >= int(_x.get("construtoras", 3)):
			prontos.append(id)
	if prontos.is_empty():
		return
	var origem: int = prontos[_rng.randi() % prontos.size()]
	ninhos[origem].absorvido = 0.0
	var afasta := harmonia.is_valid() and bool(harmonia.call()) and float(ninhos[origem].get("furia", 0.0)) <= FURIA_ZERO
	var lugar := _lugar_de_ninho(ninhos[origem].centro, afasta)
	if lugar == Vector2i(-99999, -99999):
		return
	for a in aranhas_do_ninho(origem, E.PARADA).slice(0, int(_x.get("construtoras", 3))):
		aranhas[a].estado = E.CONSTRUINDO
		aranhas[a].destino = Vector2(lugar) + Vector2(1.5, 1.5)
		aranhas[a].obra_em = lugar
	eventos.append({"tipo": "expansao", "de": origem, "para": lugar})


## `afasta` (Convivência com ninhos, fúria 0): o lugar novo não pode ficar mais perto da fábrica do que o ninho de origem.
func _lugar_de_ninho(perto: Vector2, afasta := false) -> Vector2i:
	var livre: float = _x.get("livre_de_estruturas", 14)
	var de_origem := dist_fabrica(perto) if afasta else 0.0
	for tentativa in 20:
		var d := _rng.randf_range(_x.get("dist_min", 14), _x.get("dist_max", 30))
		var p := perto + Vector2.from_angle(_rng.randf() * TAU) * d
		var minimo := Vector2i(p.floor()) - Vector2i(1, 1)
		if mapa.motivo_bloqueio("ninho_aranha", minimo, 0) != "":
			continue
		if _estrutura_perto(p, livre) >= 0 or p.length() < float(_x.get("longe_do_spawn", 40)):
			continue
		if afasta and dist_fabrica(p) < de_origem:
			continue
		var perto_ninho := false
		for n in ninhos:
			if ninhos[n].centro.distance_to(p) < 8.0:
				perto_ninho = true
		if not perto_ninho:
			return minimo
	return Vector2i(-99999, -99999)


## Distância de `p` até a construção mais perto (ninho não conta).
func dist_fabrica(p: Vector2) -> float:
	var md := INF
	for id in mapa.estruturas:
		var e: Dictionary = mapa.estruturas[id]
		if e.nome != "ninho_aranha":
			md = minf(md, _dist_estrutura(p, e))
	return md


func _chegou_obra(ar: Dictionary) -> void:
	var lugar: Vector2i = ar.obra_em
	var c := Vector2(lugar) + Vector2(1.5, 1.5)
	# outra construtora já começou a obra?
	for n in ninhos:
		if ninhos[n].centro == c:
			ar.ninho = n
			ar.estado = E.OBRA
			return
	var id := _criar_ninho(lugar, 0.0)
	if id < 0:
		ar.estado = E.VOLTANDO                             # alguém construiu ali antes
		return
	ar.ninho = id
	ar.estado = E.OBRA


## Obra de ninho: 10 s com 3 operárias (mais devagar com menos).
func _obras(dt: float) -> void:
	var tempo: float = _x.get("tempo_obra", 10)
	for id in ninhos:
		var n: Dictionary = ninhos[id]
		if n.obra < 1.0:
			var operarias := aranhas_do_ninho(id, E.OBRA).size()
			n.obra = minf(1.0, n.obra + dt / tempo * mini(operarias, 3) / 3.0)
			if n.obra >= 1.0:
				eventos.append({"tipo": "ninho_pronto", "id": id})
