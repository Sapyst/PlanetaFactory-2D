class_name Drones
extends RefCounted
## Drones das estações (fase 2.6; arte de estudo_drones.py), lógica pura — o desenho fica em DesenhoDrones.
##
##  estação   estacao_drones 2×2 (regra "drones" em estruturas.json) é uma máquina: com energia e água pelo cano,
##            monta o item drone (4 placas de ferro + 1 motor + 2 circuitos + 50 de água). Cada drone pronto entra
##            na frota da estação (até `frota`, + melhorias); com a frota cheia a máquina para (saída cheia). O
##            drone nasce em holograma vermelho na fabricadora e entra no hangar. No hangar recarrega a bateria
##            (e o casco) com a energia da estação.
##  tipo      escolhido no painel da estação ("drones_tipo" na estrutura do mapa, vai no salvamento):
##            reparo     acha construção danificada no alcance, voa até ela, escaneia e solda: `reparo_ps` ♥/s;
##                       paga como o reparo à mão (1 placa de ferro do núcleo a cada 25 ♥; no modo demo, de graça);
##            combate    aranha no alcance: decola, orbita a aranha e atira (`dano`, `cadencia`, `alcance_tiro`);
##                       aranha a menos de `alcance_mordida` morde o drone (vida 0 = derrubado, cai e vira sucata);
##            logistico  (pesquisa drones_logisticos) leva itens de baú provedor para baú requisitante no alcance
##                       (papel escolhido no painel do baú: "logistica" = provedor/requisitante; o requisitante pede
##                       um item até uma quantidade). A estação é o porto. O que sobra na garra vai para o baú de
##                       estoque mais perto com lugar (lote 16; sem ele, volta ao núcleo); requisitante que nenhum
##                       provedor atende é servido do estoque.
##  bateria   voando gasta 1 s por s; volta para o berço antes de acabar (distância / velocidade + folga).
##  raios     com raios caindo (tempestade, tufão) os drones não voam — os que estão no ar voltam — até a pesquisa
##            drones_tempestade ("drones blindados").
## Melhorias (Pesquisa.bonus): drones_frota (+n drones), drones_bateria (+tempo de voo), drones_velocidade,
## drones_dano e drones_vida (drones de defesa), drones_carga (+n itens), drones_alcance (porto logístico 2×),
## drones_tempestade. O tipo logístico é liberado pela pesquisa drones_logisticos ("modos" em progressao.json).
## Tudo que o desenho precisa (holograma, tiro, cápsula, derrubado) sai em `eventos` a cada tick.

enum E { HANGAR, NASCENDO, DECOLANDO, INDO, TRABALHANDO, VOLTANDO, POUSANDO, CAINDO }
const ESTACAO := "estacao_drones"
const TIPOS := ["reparo", "combate", "logistico"]
const NOMES_TIPO := {"reparo": "Reparo", "combate": "Combate", "logistico": "Logístico"}
const NOMES_ESTADO := {E.HANGAR: "no hangar", E.NASCENDO: "nascendo", E.DECOLANDO: "decolando", E.INDO: "a caminho",
		E.TRABALHANDO: "trabalhando", E.VOLTANDO: "voltando", E.POUSANDO: "pousando", E.CAINDO: "caindo"}
const VIDA_POR_PLACA := 25.0       ## o mesmo do reparo à mão (mundo_demo.custo_reparo)

var mapa: MapaOcupacao
var fabrica: Fabrica
var colonia: Colonia
var bonus: Callable                ## (opcional) func(chave) -> float: melhorias pesquisadas (Pesquisa.bonus)
var livre := false                 ## modo demonstração: o tipo logístico já vem liberado
var logistica_ok: Callable         ## (opcional) func() -> bool: pesquisa drones_logisticos concluída
var inventario: Dictionary = {}    ## estoque do núcleo (o reparo paga placas daqui; a sobra do logístico volta para ele)
var cobrar := false                ## modo novo: reparo custa placa
var raios_agora: Callable          ## (opcional) func() -> bool: raios caindo no planeta agora
var drones: Dictionary = {}        ## id → {id, est, tipo, e, t, pos: Vector2, alt, bateria, vida, alvo, recarga, ang,
                                   ##        item, n, de, para, fase}
var pago: Dictionary = {}          ## id da estrutura → ♥ já pagos (placas gastas) e ainda não soldados
var eventos: Array[Dictionary] = []
var obras: Obras = null            ## patch RTS: fila dos drones construtores do núcleo (tipo "construtor")
var _prox := 1
var _relogio := 0.0
var _versao := -1
var _lista: Array[int] = []
var _t_tarefa := 0.0
var _r: Dictionary


func _init(p_mapa: MapaOcupacao, p_fabrica: Fabrica, p_colonia: Colonia) -> void:
	mapa = p_mapa
	fabrica = p_fabrica
	colonia = p_colonia
	_r = Registro.estruturas.get(ESTACAO, {}).get("drones", {})


# ------------------------------------------------------------------ números (com melhorias)
func _b(chave: String) -> float:
	return float(bonus.call(chave)) if bonus.is_valid() else 0.0


func frota_max() -> int:
	return int(_r.get("frota", 8)) + roundi(_b("drones_frota"))


func voo_max() -> float:
	return float(_r.get("voo_s", 120.0)) * (1.0 + _b("drones_bateria"))


func velocidade() -> float:
	return float(_r.get("velocidade", 6.0)) * (1.0 + _b("drones_velocidade"))


func vida_max() -> float:
	return float(_r.get("vida", 60.0)) * (1.0 + _b("drones_vida"))


func dano() -> float:
	return float(_r.get("dano", 4.0)) * (1.0 + _b("drones_dano"))


func carga_max() -> int:
	return int(_r.get("carga", 1)) + roundi(_b("drones_carga"))


func alcance(est: int) -> float:
	var a := float(_r.get("alcance", 45.0))
	return a * (1.0 + _b("drones_alcance")) if tipo_de(est) == "logistico" else a


func logistica_liberada() -> bool:
	return livre or (logistica_ok.is_valid() and bool(logistica_ok.call()))


## Voam agora? Com raios caindo, só os blindados (drones_tempestade).
func pode_voar() -> bool:
	return not (raios_agora.is_valid() and bool(raios_agora.call())) or _b("drones_tempestade") > 0.0


func tipo_de(est: int) -> String:
	if mapa.estruturas.get(est, {}).get("nome", "") == "nucleo":
		return "construtor"
	var t: String = String(mapa.estruturas.get(est, {}).get("drones_tipo", "reparo"))
	if t == "logistico" and not logistica_liberada():
		return "reparo"
	return t if t in TIPOS else "reparo"


func definir_tipo(est: int, tipo: String) -> void:
	if mapa.estruturas.has(est) and tipo in TIPOS:
		mapa.estruturas[est]["drones_tipo"] = tipo
		for d in drones.values():                      # os que estão no ar terminam o serviço e voltam
			if d.est == est and d.e in [E.INDO, E.TRABALHANDO]:
				_voltar(d)


# ------------------------------------------------------------------ estação
func centro(est: int) -> Vector2:
	var e: Dictionary = mapa.estruturas[est]
	return Grade.centro_da_area(e.minimo, e.area, e.rot)


## Ponto da estação (coordenadas do modelo, x leste / y norte, girado com a peça) no plano da grade.
func ponto_estacao(est: int, local: Vector2) -> Vector2:
	return centro(est) + Grade.girar(local, int(mapa.estruturas[est].rot))


func berco(d: Dictionary) -> Vector2:
	if d.tipo == "construtor":                         # parado: orbita o cristal do núcleo
		var a := float(d.id) * 2.39996 + _relogio * obras.n("giro_orbita", 0.35)
		return centro(d.est) + Vector2.from_angle(a) * obras.n("orbita", 1.9)
	var bs: Array = _r.get("bercos", [[0.5, 0.5], [0.5, -0.5]])
	var b: Array = bs[int(d.id) % bs.size()]
	return ponto_estacao(d.est, Vector2(float(b[0]), float(b[1])))


func fabricadora(est: int) -> Vector2:
	var f: Array = _r.get("fabricadora", [-0.5, 0.0])
	return ponto_estacao(est, Vector2(float(f[0]), float(f[1])))


func frota(est: int) -> int:
	var n := 0
	for d in drones.values():
		if d.est == est:
			n += 1
	return n


func no_hangar(est: int) -> int:
	var n := 0
	for d in drones.values():
		if d.est == est and d.e == E.HANGAR:
			n += 1
	return n


func _listas() -> void:
	if mapa.versao == _versao:
		return
	_versao = mapa.versao
	_lista.clear()
	for id in mapa.estruturas:
		if mapa.estruturas[id].nome == ESTACAO:
			_lista.append(id)


func estacoes() -> Array[int]:
	_listas()
	return _lista


# ------------------------------------------------------------------ tick
func tick(dt: float) -> void:
	eventos.clear()
	_relogio += dt
	_listas()
	for est in _lista:
		_montar(est)
	var voa := pode_voar()
	for id in drones.keys():
		if drones.has(id):
			_drone(drones[id], dt, voa)
	_t_tarefa -= dt
	if _t_tarefa <= 0.0:
		_t_tarefa = float(_r.get("tarefa_s", 0.5))
		if voa:
			for est in _lista:
				_lancar(est)
	if obras != null:
		obras.tick(dt, voa)


## Drone pronto na saída da máquina entra na frota (até o máximo).
func _montar(est: int) -> void:
	var m: Maquina = fabrica.maquinas.get(est)
	if m == null or int(m.saidas.get("drone", 0)) <= 0 or frota(est) >= frota_max():
		return
	m.saidas["drone"] = int(m.saidas["drone"]) - 1
	m.acordar()
	novo(est)


## Drone novo na fabricadora da estação (holograma → matéria → hangar).
func novo(est: int, tipo := "") -> int:
	var id := _prox
	_prox += 1
	drones[id] = {"id": id, "est": est, "tipo": tipo if tipo != "" else tipo_de(est), "e": E.NASCENDO, "t": 0.0,
			"pos": fabricadora(est), "alt": float(_r.get("alt_fabricadora", 1.0)), "bateria": voo_max(), "vida": vida_max(),
			"alvo": -1, "recarga": 0.0, "ang": randf() * TAU, "item": "", "n": 0, "de": -1, "para": -1, "fase": ""}
	eventos.append({"tipo": "drone_novo", "id": id, "est": est})
	return id


func _drone(d: Dictionary, dt: float, voa: bool) -> void:
	if not mapa.estruturas.has(d.est):                 # estação desmontada/destruída: quem está fora cai
		if d.e in [E.HANGAR, E.NASCENDO, E.POUSANDO, E.DECOLANDO]:
			drones.erase(d.id)
			return
		elif d.e != E.CAINDO:
			_derrubar(d)
	if d.tipo == "construtor" and d.e in [E.HANGAR, E.NASCENDO]:
		d.pos = berco(d)
		d.alt = obras.n("alt_orbita", 3.1)
		if d.e == E.NASCENDO:
			d.t = float(d.t) + dt
			if d.t >= obras.n("nascer_s", 4.0):
				d.e = E.HANGAR
		else:
			d.vida = minf(obras.n("vida", 40.0), float(d.vida) + obras.n("vida", 40.0) / 15.0 * dt)   # o núcleo conserta
		return
	match int(d.e):
		E.HANGAR:
			var en := fabrica.energia(d.est)
			var rec := float(_r.get("recarga_s", 15.0))
			d.bateria = minf(voo_max(), float(d.bateria) + voo_max() / rec * dt * en)
			d.vida = minf(vida_max(), float(d.vida) + vida_max() / rec * dt * en)
			return
		E.NASCENDO:
			d.t = float(d.t) + dt
			if d.t >= float(_r.get("nascer_s", 3.0)):
				d.e = E.HANGAR
			return
		E.DECOLANDO:
			d.t = float(d.t) + dt
			d.alt = float(d.alt) + float(_r.get("subida", 1.6)) * dt
			if d.t >= float(_r.get("decolar_s", 0.9)):
				d.e = E.INDO
			return
		E.POUSANDO:
			d.t = float(d.t) + dt
			var alvo_alt := float(_r.get("alt_pouso", 0.97)) + (0.04 if d.tipo == "logistico" else 0.0)   # garra recolhida
			if d.tipo == "construtor":
				alvo_alt = obras.n("alt_orbita", 3.1)
			d.alt = move_toward(float(d.alt), alvo_alt, 1.4 * dt)
			d.pos = (d.pos as Vector2).move_toward(berco(d), 2.0 * dt)
			if d.t >= float(_r.get("pousar_s", 1.0)) and absf(float(d.alt) - alvo_alt) < 0.02:
				_guardar(d)
			return
		E.CAINDO:
			d.t = float(d.t) + dt
			d.alt = maxf(0.25, float(d.alt) - (2.0 + 9.0 * float(d.t)) * dt)
			if d.t >= 1.6:
				eventos.append({"tipo": "drone_sucata", "id": d.id, "pos": d.pos})
				drones.erase(d.id)
			return
	# no ar
	if d.tipo == "construtor":                         # sem bateria (o núcleo é a casa); raios: volta
		if not voa:
			_voltar(d)
		if d.e != E.VOLTANDO:
			obras.trabalhar(d, dt)
		_mordidas(d, dt)
		if d.e == E.VOLTANDO and drones.has(d.id) and d.e != E.CAINDO:
			if _voar_para(d, berco(d), obras.n("alt_orbita", 3.1), dt):
				d.e = E.POUSANDO
				d.t = 0.0
		return
	d.bateria = float(d.bateria) - dt
	if d.e != E.VOLTANDO:
		var volta := (berco(d) - (d.pos as Vector2)).length() / velocidade() + float(_r.get("folga_s", 6.0))
		if not voa or float(d.bateria) <= volta:
			_voltar(d)
	if float(d.bateria) <= 0.0:                        # sem bateria longe de casa: cai
		_derrubar(d)
		return
	match String(d.tipo):
		"reparo": _reparo(d, dt)
		"combate": _combate(d, dt)
		"logistico": _logistico(d, dt)
	if d.e == E.VOLTANDO:
		if _voar_para(d, berco(d), float(_r.get("alt_pouso", 0.97)) + 1.0, dt):
			d.e = E.POUSANDO
			d.t = 0.0


## Anda na direção do ponto: sobe à altura de voo enquanto está longe, desce à de trabalho perto. true = chegou.
func _voar_para(d: Dictionary, alvo: Vector2, alt_alvo: float, dt: float) -> bool:
	var dif := alvo - (d.pos as Vector2)
	var dist := dif.length()
	var alt_desejada := alt_alvo if dist < float(_r.get("perto", 4.0)) else maxf(alt_alvo, float(_r.get("alt_voo", 4.0)))
	if d.tipo == "construtor" and dist >= float(_r.get("perto", 4.0)):
		alt_desejada = maxf(alt_alvo, obras.n("alt_voo", 4.0))
	d.alt = move_toward(float(d.alt), alt_desejada, float(_r.get("subida", 1.6)) * 1.5 * dt)
	if dist > 1e-4:
		var v := obras.n("velocidade", 8.0) * (1.0 + _b("drones_velocidade")) if d.tipo == "construtor" else velocidade()
		d.pos = (d.pos as Vector2) + dif / dist * minf(dist, v * dt)
	return dist < 0.3 and absf(float(d.alt) - alt_alvo) < 0.35


func _voltar(d: Dictionary) -> void:
	if d.e in [E.INDO, E.TRABALHANDO, E.DECOLANDO]:
		d.e = E.VOLTANDO
		d.alvo = -1
		d.fase = ""


func _derrubar(d: Dictionary) -> void:
	if d.tipo == "construtor" and obras != null:
		obras.liberar(d, true)
	d.e = E.CAINDO
	d.t = 0.0
	eventos.append({"tipo": "drone_abatido", "id": d.id, "pos": d.pos, "alt": d.alt})


## Pousou: entra no hangar. O que estava na garra (logístico) vai para o núcleo.
func _guardar(d: Dictionary) -> void:
	if d.tipo == "construtor" and obras != null:
		obras.liberar(d, false)
	d.e = E.HANGAR
	d.alvo = -1
	d.fase = ""
	if String(d.item) != "" and int(d.n) > 0:
		inventario[d.item] = int(inventario.get(d.item, 0)) + int(d.n)
	d.item = ""
	d.n = 0
	d.de = -1
	d.para = -1
	eventos.append({"tipo": "drone_pousou", "id": d.id, "est": d.est})


func _decolar(d: Dictionary) -> void:
	d.e = E.DECOLANDO
	d.t = 0.0
	d.pos = berco(d)
	if d.tipo == "construtor":
		d.alt = obras.n("alt_orbita", 3.1)
		d.t = 1.0                                      # já está no ar: segue direto
	else:
		d.alt = float(_r.get("alt_pouso", 0.97))
		d.tipo = tipo_de(d.est)
	eventos.append({"tipo": "drone_decolou", "id": d.id, "est": d.est})


## Drone do hangar com bateria e casco para sair (o mais carregado).
func _disponivel(est: int) -> Dictionary:
	var melhor := {}
	for d in drones.values():
		if d.est == est and d.e == E.HANGAR and float(d.bateria) >= voo_max() * float(_r.get("sai_com", 0.6)) \
				and float(d.vida) >= vida_max() * 0.5 and (melhor.is_empty() or float(d.bateria) > float(melhor.bateria)):
			melhor = d
	return melhor


# ------------------------------------------------------------------ tarefas
func _lancar(est: int) -> void:
	if not fabrica.ligada(est):
		return
	var d := _disponivel(est)
	if d.is_empty():
		return
	match tipo_de(est):
		"reparo":
			var a := alvo_reparo(est, centro(est))
			if a >= 0 and _pode_pagar(a):
				_decolar(d)
				d.alvo = a
		"combate":
			var a := alvo_combate(est, centro(est))
			if a >= 0:
				_decolar(d)
				d.alvo = a
		"logistico":
			var t := tarefa_logistica(est)
			if not t.is_empty():
				_decolar(d)
				d.merge(t, true)
				d.fase = "pegar"


func _mirados(campo: String, tipo: String) -> Dictionary:
	var out := {}
	for d in drones.values():
		if d.tipo == tipo and d.e in [E.DECOLANDO, E.INDO, E.TRABALHANDO] and int(d[campo]) >= 0:
			out[int(d[campo])] = int(out.get(int(d[campo]), 0)) + 1
	return out


## Construção danificada mais perto de `perto`, no alcance da estação, que nenhum drone já está consertando.
func alvo_reparo(est: int, perto: Vector2) -> int:
	var c := centro(est)
	var ocupados := _mirados("alvo", "reparo")
	var melhor := -1
	var md := INF
	for id in colonia.vida:
		if ocupados.has(id) or not mapa.estruturas.has(id):
			continue
		var e: Dictionary = mapa.estruturas[id]
		if Colonia.eh_toca(e.nome) or e.nome == "pilar":
			continue
		var p := Grade.centro_da_area(e.minimo, e.area, e.rot)
		if p.distance_to(c) > alcance(est):
			continue
		var dd := p.distance_to(perto)
		if dd < md:
			md = dd
			melhor = id
	return melhor


func _vida_max_de(id: int) -> float:
	return float(Registro.estruturas.get(mapa.estruturas[id].nome, {}).get("vida", 100))


func _pode_pagar(id: int) -> bool:
	return not cobrar or float(pago.get(id, 0.0)) > 0.0 or int(inventario.get("placa_ferro", 0)) > 0


func _reparo(d: Dictionary, dt: float) -> void:
	if d.e == E.VOLTANDO:
		return
	var a: int = d.alvo
	if a < 0 or not mapa.estruturas.has(a) or not colonia.vida.has(a):
		var outro := alvo_reparo(d.est, d.pos)
		if outro >= 0 and _pode_pagar(outro):
			d.alvo = outro
			d.e = E.INDO
			a = outro
		else:
			_voltar(d)
			return
	var e: Dictionary = mapa.estruturas[a]
	var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
	var dims: Array = Registro.modelos.get(e.nome, {}).get("dims", [1, 1, 1])
	# para ao lado, um pouco acima do topo, olhando para a peça (o braço solda e o scan desce por ela)
	var lado := Vector2.from_angle(float(d.ang)) * (0.45 * maxf(e.area.x, e.area.y) + 0.6)
	var cheg := _voar_para(d, c + lado, float(dims[2]) + float(_r.get("acima_reparo", 0.9)), dt)
	if d.e == E.INDO:
		if cheg:
			d.e = E.TRABALHANDO
			d.t = 0.0
		return
	d.t = float(d.t) + dt
	var falta := _vida_max_de(a) - float(colonia.vida[a])
	var faz := minf(float(_r.get("reparo_ps", 25.0)) * dt, falta)
	if cobrar:
		if float(pago.get(a, 0.0)) < faz:
			if int(inventario.get("placa_ferro", 0)) <= 0:
				eventos.append({"tipo": "drone_sem_placa", "id": d.id})
				_voltar(d)
				return
			inventario["placa_ferro"] = int(inventario["placa_ferro"]) - 1
			pago[a] = float(pago.get(a, 0.0)) + VIDA_POR_PLACA
		pago[a] = float(pago[a]) - faz
	colonia.vida[a] = float(colonia.vida[a]) + faz
	if float(colonia.vida[a]) >= _vida_max_de(a) - 1e-3:
		colonia.vida.erase(a)
		eventos.append({"tipo": "drone_reparou", "id": d.id, "alvo": a})
		d.alvo = -1                                       # procura a próxima no tick seguinte


## Aranha mais perto de `perto` dentro do alcance da estação (cada aranha chama no máximo 3 drones).
func alvo_combate(est: int, perto: Vector2) -> int:
	var c := centro(est)
	var mirados := _mirados("alvo", "combate")
	var melhor := -1
	var md := INF
	for a in colonia.aranhas:
		var p: Vector2 = colonia.aranhas[a].pos
		if p.distance_to(c) > alcance(est) or int(mirados.get(a, 0)) >= 3:
			continue
		var dd := p.distance_to(perto)
		if dd < md:
			md = dd
			melhor = a
	return melhor


func _combate(d: Dictionary, dt: float) -> void:
	if d.e == E.VOLTANDO:
		_mordidas(d, dt)
		return
	var a: int = d.alvo
	if a < 0 or not colonia.aranhas.has(a):
		a = alvo_combate(d.est, d.pos)
		d.alvo = a
		if a < 0:
			_voltar(d)
			return
		d.e = E.INDO
	var ar: Vector2 = colonia.aranhas[a].pos
	d.ang = fposmod(float(d.ang) + float(_r.get("giro_orbita", 0.9)) * dt, TAU)
	var orbita := ar + Vector2.from_angle(float(d.ang)) * float(_r.get("orbita", 2.0))
	_voar_para(d, orbita, float(_r.get("alt_combate", 2.4)), dt)
	var dist := (d.pos as Vector2).distance_to(ar)
	if dist <= float(_r.get("alcance_tiro", 8.0)):
		d.e = E.TRABALHANDO
		d.recarga = float(d.recarga) - dt
		if float(d.recarga) <= 0.0:
			d.recarga = maxf(float(d.recarga), -dt) + 1.0 / float(_r.get("cadencia", 2.5))
			eventos.append({"tipo": "drone_tiro", "id": d.id, "de": d.pos, "alt": d.alt, "para": ar, "aranha": a})
			colonia.ferir_aranha(a, dano())
	else:
		d.e = E.INDO
	_mordidas(d, dt)


## Aranha embaixo pula e morde o drone baixo (combate).
func _mordidas(d: Dictionary, dt: float) -> void:
	if float(d.alt) > float(_r.get("alt_mordida", 3.0)):
		return
	var r := float(_r.get("alcance_mordida", 2.2))
	var dano_ar := float(Registro.inimigos.get("aranha", {}).get("dano", 15)) * float(_r.get("mordida", 0.4))
	for a in colonia.aranhas:
		if (colonia.aranhas[a].pos as Vector2).distance_to(d.pos) <= r:
			d.vida = float(d.vida) - dano_ar * dt
	if float(d.vida) <= 0.0:
		_derrubar(d)


# ------------------------------------------------------------------ logística
## Papel do baú para os drones ("logistica" na estrutura): "", "provedor" ou "requisitante"; o baú de estoque é sempre
## "estoque" (lote 16: guarda a sobra da garra e serve o requisitante quando nenhum provedor tem o item).
func papel(id: int) -> String:
	var e: Dictionary = mapa.estruturas.get(id, {})
	if e.get("nome", "") == "bau_estoque" or Fabrica.eh_posto(String(e.get("nome", ""))):
		return "estoque"                         # (o posto avançado é o estoque da região)
	return String(e.get("logistica", ""))


func _baus_no_alcance(est: int, papel_q: String) -> Array[int]:
	var c := centro(est)
	var out: Array[int] = []
	for id in fabrica.baus:
		if papel(id) == papel_q and mapa.estruturas.has(id):
			var e: Dictionary = mapa.estruturas[id]
			if Grade.centro_da_area(e.minimo, e.area, e.rot).distance_to(c) <= alcance(est):
				out.append(id)
	return out


func _a_caminho(campo: String, id: int, item: String) -> int:
	var n := 0
	for d in drones.values():
		if d.tipo == "logistico" and int(d[campo]) == id and String(d.item) == item and d.e in [E.DECOLANDO, E.INDO, E.TRABALHANDO]:
			if campo == "para" or d.fase == "pegar":
				n += int(d.n)
	return n


## Próxima viagem do porto: requisitante no alcance pedindo um item que algum provedor no alcance tem.
func tarefa_logistica(est: int) -> Dictionary:
	var provs := _baus_no_alcance(est, "provedor")
	if provs.is_empty() and _baus_no_alcance(est, "estoque").is_empty():
		return {}
	for req in _baus_no_alcance(est, "requisitante"):
		var e: Dictionary = mapa.estruturas[req]
		var item := String(e.get("pede_item", ""))
		if item == "":
			continue
		var falta := int(e.get("pede_qtd", 100)) - int(fabrica.baus[req].get(item, 0)) - _a_caminho("para", req, item)
		falta = mini(falta, fabrica.quanto_cabe(req, item))     # filtro do baú: não busca o que ele não aceita
		if falta <= 0:
			continue
		var cr := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var melhor := _mais_perto_com(provs, req, item, cr)
		if melhor < 0:
			melhor = _mais_perto_com(_baus_no_alcance(est, "estoque"), req, item, cr)   # nenhum provedor: o estoque
		if melhor >= 0:
			var tem2 := int(fabrica.baus[melhor].get(item, 0)) - _a_caminho("de", melhor, item)
			return {"de": melhor, "para": req, "item": item, "n": mini(carga_max(), mini(falta, tem2))}
	return {}


## Baú da lista mais perto de `cr` que tem `item` (descontado o que já está a caminho), fora `req`; -1 se nenhum.
func _mais_perto_com(lista: Array[int], req: int, item: String, cr: Vector2) -> int:
	var melhor := -1
	var md := INF
	for p in lista:
		if p == req:
			continue
		var tem := int(fabrica.baus[p].get(item, 0)) - _a_caminho("de", p, item)
		if tem <= 0:
			continue
		var ep: Dictionary = mapa.estruturas[p]
		var dd := Grade.centro_da_area(ep.minimo, ep.area, ep.rot).distance_to(cr)
		if dd < md:
			md = dd
			melhor = p
	return melhor


## Baú de estoque no alcance da estação, mais perto de `de`, com lugar para `n` itens; -1 se nenhum.
func estoque_livre(est: int, de: Vector2, n: int, item := "") -> int:
	var melhor := -1
	var md := INF
	for id in _baus_no_alcance(est, "estoque"):
		var tem := 0
		for k in fabrica.baus[id]:
			tem += int(fabrica.baus[id][k])
		if fabrica.capacidade_bau(id) - tem < n or (item != "" and fabrica.quanto_cabe(id, item) < n):
			continue
		var e: Dictionary = mapa.estruturas[id]
		var dd := Grade.centro_da_area(e.minimo, e.area, e.rot).distance_to(de)
		if dd < md:
			md = dd
			melhor = id
	return melhor


func _logistico(d: Dictionary, dt: float) -> void:
	if d.e == E.VOLTANDO:
		return
	var alvo: int = d.de if d.fase == "pegar" else d.para
	if alvo < 0 or not mapa.estruturas.has(alvo) or not fabrica.baus.has(alvo):
		_voltar(d)
		return
	var e: Dictionary = mapa.estruturas[alvo]
	var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
	var dims: Array = Registro.modelos.get(e.nome, {}).get("dims", [1, 1, 1])
	var cheg := _voar_para(d, c, float(dims[2]) + float(_r.get("acima_bau", 1.1)), dt)
	if d.e == E.INDO:
		if cheg:
			d.e = E.TRABALHANDO
			d.t = 0.0
		return
	d.t = float(d.t) + dt
	if float(d.t) < float(_r.get("garra_s", 0.8)):
		return
	var b: Dictionary = fabrica.baus[alvo]
	if d.fase == "pegar":
		var n := mini(int(d.n), int(b.get(d.item, 0)))
		if n <= 0:
			_voltar(d)
			return
		b[d.item] = int(b[d.item]) - n
		d.n = n
		d.fase = "levar"
		d.e = E.INDO
		eventos.append({"tipo": "drone_pegou", "id": d.id, "item": d.item, "n": n})
	else:
		var poe := mini(int(d.n), maxi(0, fabrica.quanto_cabe(alvo, d.item)))   # capacidade + filtro do baú
		if poe > 0:
			b[d.item] = int(b.get(d.item, 0)) + poe
		d.n = int(d.n) - poe
		eventos.append({"tipo": "drone_entregou", "id": d.id, "item": d.item, "n": poe})
		if int(d.n) > 0:
			var sobra := estoque_livre(d.est, c, int(d.n), d.item) if papel(alvo) != "estoque" else -1
			if sobra >= 0:                              # não coube: a sobra vai para o baú de estoque
				d.para = sobra
				d.e = E.INDO
				return
			_voltar(d)                                  # sem estoque com lugar: a sobra volta com ele (vai para o núcleo)
			return
		d.item = ""
		var t := tarefa_logistica(d.est)                # emenda a próxima viagem se a bateria deixar
		if not t.is_empty():
			d.merge(t, true)
			d.fase = "pegar"
			d.e = E.INDO
		else:
			_voltar(d)


# ------------------------------------------------------------------ consulta / salvamento
func da_estacao(est: int) -> Array:
	return drones.values().filter(func(d): return d.est == est)


func estado() -> Dictionary:
	return {"drones": drones, "prox": _prox, "pago": pago}


func restaurar(d: Dictionary) -> void:
	drones.clear()
	var ds: Dictionary = d.get("drones", {})
	for k in ds:
		drones[int(k)] = ds[k]
	_prox = int(d.get("prox", 1))
	pago = d.get("pago", {})
	_versao = -1
