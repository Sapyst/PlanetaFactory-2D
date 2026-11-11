class_name Obras
extends RefCounted
## Patch RTS (docs/PLANO_RTS_DRONES.md): construir não é instantâneo. Lógica pura — o desenho fica em DesenhoObras
## (fantasmas) e DesenhoDrones (o drone construtor, modelo drone_reparo).
##
##  encomenda  o plano confirmado vira obras na ordem do clique (colocar, trocar classe de esteira, remover). A peça
##             não entra no mapa: os tiles ficam reservados (MapaOcupacao.reservas) e aparece o holograma. Limpar,
##             aplainar, escavar e trem continuam instantâneos.
##  saída      a cada `tarefa_s`, um construtor parado no núcleo pega um lote: as obras da fila (ordem do clique) que
##             ninguém pegou, perto da primeira (raio_lote), enquanto couberem na carga e o estoque pagar. Paga na hora
##             (posto avançado que cobre a obra primeiro, como o Construtor) e os itens vão para a carga do drone. Obra
##             que o estoque não paga fica esperando (fantasma âmbar); as seguintes não ficam presas por ela.
##  trabalho   voa até cada obra do lote, solda `tempo()` e a peça entra no mapa (relatório → mundo.sincronizar,
##             que monta a peça parte por parte). Remover: desmonta e os itens vão para a carga.
##  volta      fim do lote → núcleo; ao pousar, a carga (sobra e o que veio das remoções) entra no estoque. Obras que
##             ficaram com ele (raios, cancelada) voltam para a fila. Derrubado: a carga se perde, as obras voltam.
##  fabricar   botão no painel do núcleo: 1 engrenagem, nasce em holograma na órbita do cristal (até `max`).
##  postos     (2026-11-11) o posto avançado (e a colônia) também é casa de construtor: fabrica (1 engrenagem do estoque
##             dele, sem ela do núcleo; até `max_posto`), chama um do núcleo ou manda de volta. A obra é da base com
##             construtor mais perto; outra base só pega depois de `emprestar_s` de espera. A sobra da carga entra no
##             estoque da base onde ele pousa (posto até lotar, o resto no núcleo). Posto que some: os construtores
##             dele mudam para a base mais perto (não caem).

var mapa: MapaOcupacao
var construtor: Construtor
var drones: Drones
var inventario: Dictionary
var cobrar := false
var aplicar: Callable                    ## func(rel) — o mundo desenha o que mudou (mundo.sincronizar)
var obras: Dictionary = {}               ## id → {id, acao, item, nome, pos, lote, estado ("fila"/"carregada"), drone,
                                         ##        espera, prog, custo, tiles, altos, pago_local, local_id}
var ordem: Array[int] = []               ## ordem do clique
var eventos: Array[Dictionary] = []
var iniciais_dados := false              ## os drones iniciais já foram dados (save antigo ganha uma vez)
var versao := 0                          ## muda quando a fila muda (o desenho refaz os fantasmas)
var _prox := 1
var _lote := 0
var _t_tarefa := 0.0
var _r: Dictionary
var _nucleo := -1
var _nucleo_versao := -1
var _bases: Array[int] = []
var _bases_versao := -1


func _init(p_mapa: MapaOcupacao, p_construtor: Construtor, p_drones: Drones, p_inventario: Dictionary) -> void:
	mapa = p_mapa
	construtor = p_construtor
	drones = p_drones
	inventario = p_inventario
	_r = Registro.estruturas.get("nucleo", {}).get("construtores", {})
	drones.obras = self


func n(chave: String, padrao: float) -> float:
	return float(_r.get(chave, padrao))


func nucleo() -> int:
	if _nucleo_versao != mapa.versao or not mapa.estruturas.has(_nucleo):
		_nucleo_versao = mapa.versao
		_nucleo = -1
		for id in mapa.estruturas:
			if mapa.estruturas[id].nome == "nucleo":
				_nucleo = id
				break
	return _nucleo


func construtores() -> Array:
	return drones.drones.values().filter(func(d): return d.tipo == "construtor")


## Máximo de construtores morando no núcleo.
func frota_max() -> int:
	return int(_r.get("max", 6)) + roundi(drones._b("construtores_frota"))


# ------------------------------------------------------------------ bases (núcleo e postos avançados)
func eh_base(id: int) -> bool:
	if not mapa.estruturas.has(id):
		return false
	var nome: String = mapa.estruturas[id].nome
	return nome == "nucleo" or Fabrica.eh_posto(nome)


## O núcleo primeiro, depois os postos (e colônias).
func bases() -> Array[int]:
	if _bases_versao != mapa.versao:
		_bases_versao = mapa.versao
		_bases.clear()
		for id in mapa.estruturas:
			if Fabrica.eh_posto(mapa.estruturas[id].nome):
				_bases.append(id)
		_bases.sort()
		if nucleo() >= 0:
			_bases.push_front(nucleo())
	return _bases


func max_de(base: int) -> int:
	if base == nucleo():
		return frota_max()
	return int(_r.get("max_posto", 3)) + roundi(drones._b("construtores_frota"))


func construtores_de(base: int) -> Array:
	return drones.drones.values().filter(func(d): return d.tipo == "construtor" and int(d.est) == base)


## Altura da órbita parada: acima do cristal do núcleo ou da antena do posto.
func alt_orbita(base: int) -> float:
	if base == nucleo() or not mapa.estruturas.has(base):
		return n("alt_orbita", 3.1)
	return n("alt_orbita_posto", 3.2)


## A base (núcleo ou posto) mais perto do ponto; `so_com` = só as que estão nesse conjunto (ids → true).
func base_mais_perto(p: Vector2, so_com := {}, fora := -1) -> int:
	var melhor := -1
	var dm := INF
	for b in bases():
		if b == fora or (not so_com.is_empty() and not so_com.has(b)):
			continue
		var dd := drones.centro(b).distance_to(p)
		if dd < dm:
			dm = dd
			melhor = b
	return melhor


## Bases com pelo menos um construtor (ids → true).
func _bases_com_drone() -> Dictionary:
	var com := {}
	for d in construtores():
		if eh_base(int(d.est)):
			com[int(d.est)] = true
	return com


## A casa do construtor sumiu (posto destruído ou desmontado): muda para a base mais perto e voa para lá.
func nova_casa(d: Dictionary) -> bool:
	var b := base_mais_perto(d.pos)
	if b < 0:
		return false
	d.est = b
	if d.e in [Drones.E.HANGAR, Drones.E.NASCENDO, Drones.E.POUSANDO]:
		d.e = Drones.E.VOLTANDO
		d.t = 0.0
	eventos.append({"tipo": "construtor_mudou", "id": d.id, "para": b})
	return true


func _parados_em(base: int) -> Array:
	return construtores_de(base).filter(func(d): return d.e == Drones.E.HANGAR and float(d.vida) >= n("vida", 40.0) * 0.5)


## Painel do posto: um construtor parado no núcleo vem morar no posto. "" = foi.
func chamar(posto: int) -> String:
	var mot := _pode_mudar(posto, nucleo(), posto)
	if mot == "":
		_mudar(_parados_em(nucleo())[0], posto)
	return mot


## Painel do posto: um construtor parado no posto volta a morar no núcleo. "" = foi.
func mandar_ao_nucleo(posto: int) -> String:
	var mot := _pode_mudar(posto, posto, nucleo())
	if mot == "":
		_mudar(_parados_em(posto)[0], nucleo())
	return mot


func pode_chamar(posto: int) -> String:
	return _pode_mudar(posto, nucleo(), posto)


func pode_mandar(posto: int) -> String:
	return _pode_mudar(posto, posto, nucleo())


func _pode_mudar(posto: int, de: int, para: int) -> String:
	if not eh_base(posto) or posto == nucleo() or nucleo() < 0:
		return "sem núcleo"
	if construtores_de(para).size() >= max_de(para):
		return "%s cheio" % ("núcleo" if para == nucleo() else "posto")
	if _parados_em(de).is_empty():
		return "nenhum parado no %s" % ("núcleo" if de == nucleo() else "posto")
	return ""


func _mudar(d: Dictionary, para: int) -> void:
	d.est = para
	d.obras = []
	d.alvo = -1
	d.e = Drones.E.VOLTANDO
	d.t = 0.0
	eventos.append({"tipo": "construtor_mudou", "id": d.id, "para": para})


## Estoque do posto (o baú dele na fábrica), ou vazio.
func _estoque_posto(base: int) -> Dictionary:
	if base == nucleo() or drones.fabrica == null:
		return {}
	var b: Variant = drones.fabrica.baus.get(base)
	return b if b is Dictionary else {}


## A carga entra no estoque da base: no posto até lotar, o resto no núcleo.
func _depositar(base: int, carga: Dictionary) -> void:
	var est := _estoque_posto(base)
	var livre := 0
	if not est.is_empty() or (drones.fabrica != null and drones.fabrica.baus.has(base)):
		livre = drones.fabrica.capacidade_bau(base) - _soma(est)
	for k in carga:
		var q := int(carga[k])
		if q <= 0:
			continue
		var no_posto := clampi(q, 0, maxi(0, livre))
		if no_posto > 0:
			est[k] = int(est.get(k, 0)) + no_posto
			livre -= no_posto
		if q - no_posto > 0:
			inventario[k] = int(inventario.get(k, 0)) + q - no_posto


func custo_drone() -> Dictionary:
	return _r.get("custo", {"engrenagem": 1})


# ------------------------------------------------------------------ fabricar
## Pode fabricar um construtor nesta base (núcleo por padrão)? "" = pode.
func pode_fabricar(base := -1) -> String:
	var b := nucleo() if base < 0 else base
	if nucleo() < 0 or not eh_base(b):
		return "sem núcleo"
	if construtores_de(b).size() >= max_de(b):
		return "frota cheia"
	if cobrar:
		var c := custo_drone()
		var est := _estoque_posto(b)
		for k in c:
			if int(inventario.get(k, 0)) + int(est.get(k, 0)) < int(c[k]):
				return "falta %s" % k
	return ""


## Fabrica um construtor na base (núcleo por padrão). Paga do estoque do posto primeiro, o resto do núcleo. -1 se não pode.
func fabricar(gratis := false, base := -1) -> int:
	var b := nucleo() if base < 0 else base
	if nucleo() < 0 or not eh_base(b) or construtores_de(b).size() >= max_de(b):
		return -1
	if not gratis:
		if pode_fabricar(b) != "":
			return -1
		if cobrar:
			var c := custo_drone()
			var est := _estoque_posto(b)
			for k in c:
				var do_posto := mini(int(c[k]), int(est.get(k, 0)))
				if do_posto > 0:
					est[k] = int(est[k]) - do_posto
				inventario[k] = int(inventario.get(k, 0)) - (int(c[k]) - do_posto)
	var id := drones.novo(b, "construtor")
	var d: Dictionary = drones.drones[id]
	d.vida = n("vida", 40.0)
	d.bateria = INF
	d.obras = []
	d.carga = {}
	d.pos = drones.berco(d)
	d.alt = alt_orbita(b)
	return id


## Jogo novo (ou save antigo sem nenhum): os construtores iniciais, de graça, uma vez.
func dar_iniciais() -> void:
	if iniciais_dados or nucleo() < 0:
		return
	iniciais_dados = true
	for i in int(_r.get("inicial", 2)) - construtores_de(nucleo()).size():
		var id := fabricar(true)
		if id >= 0:
			drones.drones[id].e = Drones.E.HANGAR             # já chegam prontos (sem holograma)


# ------------------------------------------------------------------ encomendar
## Plano confirmado → obras. Devolve {n: obras novas, rel: relatório do que foi instantâneo (limpar, aplainar, trem)}.
func encomendar(plano: Array[Dictionary]) -> Dictionary:
	_lote += 1
	var imediato: Array[Dictionary] = []
	var novas := 0
	for it in plano:
		if it.motivo != "":
			continue
		match String(it.get("acao", "colocar")):
			"colocar":
				_nova(it, "colocar")
				novas += 1
			"substituir":
				if mapa.estruturas.has(int(it.get("id_antigo", -1))):
					_nova(it, "colocar")
					novas += 1
			"remover":
				var id := int(it.get("id", -1))
				if mapa.estruturas.has(id) and not mapa.estruturas[id].get("a_remover", false) and mapa.estruturas[id].nome != "nucleo":
					mapa.estruturas[id]["a_remover"] = true
					_nova(it, "remover")
					novas += 1
			"igual":
				pass
			_:
				imediato.append(it)
	var rel: Dictionary = construtor.executar(imediato) if not imediato.is_empty() else {}
	if novas > 0:
		versao += 1
	return {"n": novas, "rel": rel}


func _nova(it: Dictionary, acao: String) -> void:
	var id := _prox
	_prox += 1
	var item := it.duplicate(true)
	var area: Vector2i = mapa.registro.area(item.nome)
	var o := {"id": id, "acao": acao, "item": item, "nome": item.nome, "lote": _lote, "estado": "fila", "drone": -1,
			"espera": false, "prog": 0.0, "custo": {}, "tiles": [], "altos": [], "pago_local": {}, "local_id": -1, "fila_s": 0.0,
			"pos": Grade.centro_da_area(item.minimo, area, item.rot)}
	if acao == "colocar":
		var troca: bool = item.get("acao", "") == "substituir" and int(item.get("classe", 1)) != int(item.get("classe_antiga", 1))
		if cobrar and (item.get("acao", "") == "colocar" or troca):
			o.custo = Construtor.custo_de(item.nome, int(item.get("classe", 1))).duplicate()
		_reservar(o)
	obras[id] = o
	ordem.append(id)


func _reservar(o: Dictionary) -> void:
	var it: Dictionary = o.item
	var nv := int(it.get("nivel", 0))
	if nv > 0:
		var k := Vector3i(it.minimo.x, it.minimo.y, nv)
		mapa.reservas_altas[k] = o.id
		o.altos = [k]
	else:
		var ts: Array = []
		for t in Grade.tiles_da_area(it.minimo, mapa.registro.area(it.nome), it.rot):
			mapa.reservas[t] = o.id
			ts.append(t)
		o.tiles = ts
	mapa.versao += 1


func _soltar_reserva(o: Dictionary) -> void:
	for t in o.tiles:
		if int(mapa.reservas.get(t, -1)) == int(o.id):
			mapa.reservas.erase(t)
	for k in o.altos:
		if int(mapa.reservas_altas.get(k, -1)) == int(o.id):
			mapa.reservas_altas.erase(k)
	o.tiles = []
	o.altos = []


func _tirar(o: Dictionary) -> void:
	_soltar_reserva(o)
	if o.acao == "remover":
		var id := int(o.item.get("id", -1))
		if mapa.estruturas.has(id):
			mapa.estruturas[id].erase("a_remover")
	obras.erase(int(o.id))
	ordem.erase(int(o.id))
	versao += 1


## Há obra encomendada que ainda não foi feita?
func pendentes() -> int:
	return obras.size()


func esperando() -> int:
	var k := 0
	for o in obras.values():
		if o.espera:
			k += 1
	return k


## Desfazer: cancela o último lote encomendado que ainda tem obra por fazer. O que já foi carregado volta com o drone.
func cancelar_ultimo() -> bool:
	var ult := -1
	for o in obras.values():
		ult = maxi(ult, int(o.lote))
	if ult < 0:
		return false
	for id in ordem.duplicate():
		var o: Dictionary = obras[id]
		if int(o.lote) == ult:
			_tirar(o)
	eventos.append({"tipo": "obras_canceladas"})
	return true


## Remoção pedida para uma estrutura (painel). true = encomendou.
func remover(id: int) -> bool:
	if not mapa.estruturas.has(id):
		return false
	var e: Dictionary = mapa.estruturas[id]
	var plano: Array[Dictionary] = []
	for it in construtor.plano_remocao(e.minimo, e.minimo):
		if it.get("id", -1) == id and it.motivo == "":
			plano.append(it)
	return int(encomendar(plano).n) > 0


# ------------------------------------------------------------------ tick
func tick(dt: float, voa: bool) -> void:
	_t_tarefa -= dt
	if _t_tarefa > 0.0:
		return
	_t_tarefa = 0.5
	_conferir_remocoes()
	if not voa or obras.is_empty():
		return
	for o in obras.values():                             # quanto tempo a obra espera na fila (para outra base pegar)
		if o.estado == "fila":
			o.fila_s = float(o.get("fila_s", 0.0)) + 0.5
	var com := _bases_com_drone()
	var sem_lote := {}                                   # base cujo drone não achou lote: os outros dela também não acham
	for d in construtores():
		if d.e != Drones.E.HANGAR or not eh_base(int(d.est)) or float(d.vida) < n("vida", 40.0) * 0.5 \
				or sem_lote.has(int(d.est)):
			continue
		var lote := _montar_lote(d, com)
		if lote.is_empty():
			sem_lote[int(d.est)] = true
			continue
		d.obras = lote
		d.alvo = lote[0]
		drones._decolar(d)


## Remoção cuja estrutura sumiu (aranha destruiu) sai da fila.
func _conferir_remocoes() -> void:
	for id in ordem.duplicate():
		var o: Dictionary = obras[id]
		if o.acao == "remover" and not mapa.estruturas.has(int(o.item.id)) and o.estado == "fila":
			_tirar(o)


static func _soma(c: Dictionary) -> int:
	var s := 0
	for k in c:
		s += int(c[k])
	return s


## A obra é desta base? (a base com construtor mais perto dela; outra só depois de `emprestar_s` na fila)
func _da_base(o: Dictionary, base: int, com: Dictionary) -> bool:
	if com.size() <= 1 or float(o.get("fila_s", 0.0)) >= n("emprestar_s", 20.0):
		return true
	return base_mais_perto(o.pos, com) == base


func _montar_lote(d: Dictionary, com := {}) -> Array:
	var out: Array = []
	var soma := 0
	var p0 := Vector2.INF
	var carga := int(_r.get("carga", 30)) + roundi(drones._b("construtores_carga"))
	for id in ordem:
		var o: Dictionary = obras[id]
		if o.estado != "fila" or not _da_base(o, int(d.est), com):
			continue
		if out.size() >= int(_r.get("obras_lote", 12)):
			break
		if p0 != Vector2.INF and (o.pos as Vector2).distance_to(p0) > n("raio_lote", 20.0):
			continue
		var s := _soma(o.custo)
		if not out.is_empty() and soma + s > carga:
			continue
		if not _pagar(o):
			if not o.espera:
				o.espera = true
				versao += 1
			continue
		if o.espera:
			o.espera = false
			versao += 1
		o.estado = "carregada"
		o.fila_s = 0.0
		o.drone = int(d.id)
		out.append(int(id))
		soma += s
		for k in o.custo:
			d.carga[k] = int(d.carga.get(k, 0)) + int(o.custo[k])
		if p0 == Vector2.INF:
			p0 = o.pos
	if not out.is_empty():
		eventos.append({"tipo": "construtor_saiu", "id": d.id, "obras": out.size()})
	return out


## Paga a obra agora (posto avançado que cobre o tile primeiro, o resto do núcleo). false = falta recurso.
func _pagar(o: Dictionary) -> bool:
	if not cobrar or o.custo.is_empty():
		return true
	var loc := construtor._local(o.item.minimo)
	var est: Dictionary = loc.get("estoque", {})
	for k in o.custo:
		if int(inventario.get(k, 0)) + int(est.get(k, 0)) < int(o.custo[k]):
			return false
	o.pago_local = {}
	o.local_id = int(loc.get("id", -1))
	for k in o.custo:
		var falta := int(o.custo[k])
		var dl := mini(falta, int(est.get(k, 0)))
		if dl > 0:
			est[k] = int(est[k]) - dl
			o.pago_local[k] = dl
		inventario[k] = int(inventario.get(k, 0)) - (falta - dl)
	return true


# ------------------------------------------------------------------ o drone no ar
func tempo(o: Dictionary) -> float:
	if o.acao == "remover":
		return n("remover_s", 0.5)
	var itens := _soma(Construtor.custo_de(o.nome, int(o.item.get("classe", 1))))
	return clampf(n("construir_s", 0.6) + n("por_item_s", 0.05) * itens, 0.1, n("max_s", 5.0))


func altura(o: Dictionary) -> float:
	var nome := Construtor.modelo_de(o.item)
	var dims: Array = Registro.modelos.get(nome, Registro.modelos.get(o.nome, {})).get("dims", [1, 1, 1])
	return float(dims[2]) + int(o.item.get("nivel", 0)) * 0.5


## Chamado por Drones._drone com o construtor no ar (fora VOLTANDO).
func trabalhar(d: Dictionary, dt: float) -> void:
	var lista: Array = d.obras
	while not lista.is_empty() and not obras.has(int(lista[0])):
		lista.pop_front()                                # cancelada (desfazer): pula
	if lista.is_empty():
		drones._voltar(d)
		return
	var o: Dictionary = obras[int(lista[0])]
	d.alvo = int(o.id)
	var area: Vector2i = mapa.registro.area(o.nome)
	var lado := Vector2.from_angle(float(d.ang)) * (0.45 * maxf(area.x, area.y) + 0.6)
	var cheg := drones._voar_para(d, (o.pos as Vector2) + lado, altura(o) + n("acima", 0.55), dt)
	if d.e == Drones.E.INDO:
		if cheg:
			d.e = Drones.E.TRABALHANDO
			d.t = 0.0
		return
	d.t = float(d.t) + dt
	o.prog = clampf(float(d.t) / tempo(o), 0.0, 1.0)
	if float(d.t) < tempo(o):
		return
	if o.acao == "colocar":
		_construir(o, d)
	else:
		_desmontar(o, d)
	_tirar(o)
	lista.pop_front()
	d.e = Drones.E.INDO
	d.t = 0.0
	d.ang = randf() * TAU


func _sem_cobrar(it: Dictionary) -> Dictionary:
	var c := construtor.cobrar
	construtor.cobrar = false
	var rel := construtor.executar([it] as Array[Dictionary])
	construtor.cobrar = c
	return rel


func _construir(o: Dictionary, d: Dictionary) -> void:
	_soltar_reserva(o)
	var it: Dictionary = o.item
	var velho: Dictionary = mapa.estruturas.get(int(it.get("id_antigo", -1)), {}).duplicate() if it.get("acao", "") == "substituir" else {}
	var rel := _sem_cobrar(it)
	var ok: bool = not rel.colocados.is_empty()
	if ok and cobrar:
		for k in o.custo:                                # o desfazer devolve como se o Construtor tivesse cobrado
			var do_nucleo := int(o.custo[k]) - int(o.pago_local.get(k, 0))
			rel.estoque[k] = int(rel.estoque.get(k, 0)) - do_nucleo
			d.carga[k] = maxi(0, int(d.carga.get(k, 0)) - int(o.custo[k]))
		if not o.pago_local.is_empty() and int(o.local_id) >= 0:
			rel.locais[int(o.local_id)] = o.pago_local.duplicate()
		if not velho.is_empty() and int(velho.get("classe", 1)) != int(it.get("classe", 1)):
			var volta := Construtor.custo_de(velho.nome, int(velho.get("classe", 1)))
			for k in volta:                              # a peça velha da troca de classe volta para o núcleo
				inventario[k] = int(inventario.get(k, 0)) + int(volta[k])
				rel.estoque[k] = int(rel.estoque.get(k, 0)) + int(volta[k])
	eventos.append({"tipo": "obra_pronta" if ok else "obra_falhou", "id": d.id, "obra": o.id, "nome": o.nome, "pos": o.pos})
	if aplicar.is_valid():
		aplicar.call(rel)


func _desmontar(o: Dictionary, d: Dictionary) -> void:
	var id := int(o.item.get("id", -1))
	if not mapa.estruturas.has(id):
		return
	var e: Dictionary = mapa.estruturas[id]
	var volta := {}
	if cobrar:
		volta = Construtor.custo_de(e.nome, int(e.get("classe", 1))).duplicate()
		for md in e.get("modulos", []):
			volta[md] = int(volta.get(md, 0)) + 1
	e.erase("a_remover")
	var it: Dictionary = o.item.duplicate()
	it.motivo = ""
	var rel := _sem_cobrar(it)
	for k in volta:                                      # os itens vão na carga; entram no estoque quando ele pousar
		d.carga[k] = int(d.carga.get(k, 0)) + int(volta[k])
		rel.estoque[k] = int(rel.estoque.get(k, 0)) + int(volta[k])
	eventos.append({"tipo": "obra_removida", "id": d.id, "obra": o.id, "nome": o.nome, "pos": o.pos})
	if aplicar.is_valid():
		aplicar.call(rel)


## Pousou (perdeu = false) ou caiu (true): obras dele voltam para a fila; a carga entra no estoque (ou se perde).
func liberar(d: Dictionary, perdeu: bool) -> void:
	for id in d.get("obras", []):
		if obras.has(int(id)):
			var o: Dictionary = obras[int(id)]
			o.estado = "fila"
			o.drone = -1
			o.prog = 0.0
	d.obras = []
	d.alvo = -1
	var carga: Dictionary = d.get("carga", {})
	if not perdeu:
		_depositar(int(d.est), carga)
	elif not carga.is_empty():
		eventos.append({"tipo": "carga_perdida", "id": d.id, "carga": carga.duplicate()})
	d.carga = {}
	versao += 1


# ------------------------------------------------------------------ salvamento
func estado() -> Dictionary:
	return {"obras": obras, "ordem": ordem, "prox": _prox, "lote": _lote, "iniciais": iniciais_dados}


func restaurar(dados: Dictionary) -> void:
	obras.clear()
	ordem.clear()
	mapa.reservas.clear()
	mapa.reservas_altas.clear()
	var os: Dictionary = dados.get("obras", {})
	for k in os:
		var o: Dictionary = os[k]
		o.id = int(o.id)
		o.lote = int(o.lote)
		o.drone = -1
		o.estado = "fila"                               # carregadas: o drone pousou com o save (a carga voltou)
		o.prog = 0.0
		var it: Dictionary = o.item
		it.minimo = _v2i(it.minimo)
		it.rot = int(it.rot)
		if it.has("nivel"):
			it.nivel = int(it.nivel)
		if it.has("id"):
			it.id = int(it.id)
		if it.has("id_antigo"):
			it.id_antigo = int(it.id_antigo)
		if it.has("classe"):
			it.classe = int(it.classe)
		o.pos = _v2(o.pos)
		var c := {}
		for ck in o.get("custo", {}):
			c[ck] = int(o.custo[ck])
		o.custo = c
		o.pago_local = {}
		o.local_id = -1
		obras[o.id] = o
		if o.acao == "colocar":
			_reservar(o)
		elif mapa.estruturas.has(int(it.get("id", -1))):
			mapa.estruturas[int(it.id)]["a_remover"] = true
	for d in construtores():                             # construtor salvo no ar: volta à órbita e a carga ao estoque
		if not d.has("carga") or not d.carga is Dictionary:
			d.carga = {}
		d.obras = []
		if d.e != Drones.E.HANGAR and d.e != Drones.E.NASCENDO:
			for k in d.carga:
				inventario[k] = int(inventario.get(k, 0)) + int(d.carga[k])
			d.e = Drones.E.HANGAR
			d.alvo = -1
		d.carga = {}
		d.bateria = INF
	for id in dados.get("ordem", []):
		if obras.has(int(id)):
			ordem.append(int(id))
	for id in obras:
		if not ordem.has(id):
			ordem.append(id)
	_prox = int(dados.get("prox", 1))
	_lote = int(dados.get("lote", 0))
	iniciais_dados = bool(dados.get("iniciais", false))
	for id in mapa.estruturas:                           # marca de remoção sem obra (save velho) sai
		if mapa.estruturas[id].get("a_remover", false):
			var tem := false
			for o in obras.values():
				if o.acao == "remover" and int(o.item.get("id", -1)) == int(id):
					tem = true
			if not tem:
				mapa.estruturas[id].erase("a_remover")
	versao += 1


static func _v2i(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(v)
	if v is String:
		var p := (v as String).trim_prefix("(").trim_suffix(")").split(",")
		return Vector2i(int(p[0]), int(p[1]))
	if v is Array:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO


static func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v)
	if v is String:
		var p := (v as String).trim_prefix("(").trim_suffix(")").split(",")
		return Vector2(float(p[0]), float(p[1]))
	if v is Array:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
