extends Caso
## Patch RTS (docs/PLANO_RTS_DRONES.md): construir e remover viram obras que os drones construtores do núcleo fazem.

const DT := 1.0 / 30.0


func _base(cobrar := true, inv := {"placa_ferro": 100, "engrenagem": 20, "placa_cobre": 20}) -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	for x in range(-60, 90):
		for y in range(-60, 60):
			m.limpar_obstaculo(Vector2i(x, y))
	var f := Fabrica.new(m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	var dr := Drones.new(m, f, col)
	var inventario := inv.duplicate()
	var c := Construtor.new(m)
	c.cobrar = cobrar
	c.inventario = inventario
	c.fila_de_obras = true
	var nu := m.colocar("nucleo", _lugar(m, "nucleo", Vector2i(0, 0)), 0)
	var ob := Obras.new(m, c, dr, inventario)
	ob.cobrar = cobrar
	var aplicados: Array = []
	ob.aplicar = func(rel: Dictionary) -> void: aplicados.append(rel)
	ob.dar_iniciais()
	return {"g": g, "m": m, "f": f, "col": col, "dr": dr, "c": c, "ob": ob, "inv": inventario, "nu": nu, "aplicados": aplicados}


func _lugar(m: MapaOcupacao, nome: String, perto: Vector2i) -> Vector2i:
	for r in 30:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and m.motivo_bloqueio(nome, perto + Vector2i(dx, dy), 0) == "":
					return perto + Vector2i(dx, dy)
	return Vector2i(9999, 9999)


func _rodar(b: Dictionary, s: float) -> void:
	for i in int(s / DT):
		(b.dr as Drones).tick(DT)


func _rodar_ate(b: Dictionary, s: float, cond: Callable) -> float:
	var t := 0.0
	while t < s:
		(b.dr as Drones).tick(DT)
		t += DT
		if cond.call():
			return t
	return -1.0


func _pedir(b: Dictionary, nome: String, tile: Vector2i) -> int:
	return int((b.ob as Obras).encomendar((b.c as Construtor).plano_peca(nome, tile, 0)).n)


func _tem(m: MapaOcupacao, nome: String, tile: Vector2i) -> bool:
	for id in m.ids_no_tile(tile):
		if m.estruturas[id].nome == nome:
			return true
	return false


func test_dados() -> void:
	var r: Dictionary = Registro.estruturas.nucleo.construtores
	igual(int(r.inicial), 2, "começa com 2 construtores")
	igual(int(r.custo.engrenagem), 1, "fabricar custa 1 engrenagem")
	igual(r.custo.size(), 1, "só a engrenagem")
	verificar(Registro.modelos.has("drone_reparo"), "usa o modelo do drone de reparo (braço de solda)")


func test_comeca_com_dois_orbitando() -> void:
	var b := _base()
	var ob: Obras = b.ob
	igual(ob.construtores().size(), 2, "2 construtores no jogo novo")
	ob.dar_iniciais()
	igual(ob.construtores().size(), 2, "dar de novo não duplica")
	var dr: Drones = b.dr
	var c := dr.centro(b.nu)
	_rodar(b, 1.0)
	for d in ob.construtores():
		igual(d.e, Drones.E.HANGAR, "parado")
		perto((d.pos as Vector2).distance_to(c), 1.9, 0.05, "orbita o cristal")
		verificar(float(d.alt) > 2.61, "acima do núcleo (não atravessa o modelo)")


func test_construir_nao_e_instantaneo() -> void:
	var b := _base()
	var m: MapaOcupacao = b.m
	var t := Vector2i(14, 0)
	var antes := int(b.inv.placa_ferro)
	igual(_pedir(b, "bau", t), 1, "1 obra encomendada")
	verificar(not _tem(m, "bau", t), "a peça ainda não está no mapa")
	igual(m.motivo_bloqueio("bau", t, 0), "ocupado", "o tile fica reservado")
	igual(int(b.inv.placa_ferro), antes, "nada pago antes do drone sair")
	var dt := _rodar_ate(b, 20.0, func(): return _tem(m, "bau", t))
	verificar(dt > 0.0, "o drone foi lá e construiu")
	verificar(dt > 1.0, "levou o voo + a solda (%.1f s)" % dt)
	igual(int(b.inv.placa_ferro), antes - 4, "o baú custou 4 placas, pagas na saída")
	verificar(not m.reservas.has(t), "reserva solta")
	igual((b.aplicados as Array).size(), 1, "o mundo recebeu o relatório (desenha e monta)")
	var dr: Drones = b.dr
	verificar(_rodar_ate(b, 20.0, func(): return (b.ob as Obras).construtores().all(func(d): return d.e == Drones.E.HANGAR)) > 0.0,
			"voltou ao núcleo")


func test_sai_so_com_o_que_ja_foi_pedido() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	for d in ob.construtores().slice(1):
		(b.dr as Drones).drones.erase(d.id)          # um drone só: dá para ver a volta
	_pedir(b, "bau", Vector2i(30, 0))
	_pedir(b, "bau", Vector2i(30, 3))
	_rodar(b, 0.6)
	var d: Dictionary = ob.construtores()[0]
	verificar(d.e != Drones.E.HANGAR, "saiu")
	igual((d.obras as Array).size(), 2, "levou as 2 que já estavam pedidas")
	igual(int(d.carga.get("placa_ferro", 0)), 8, "com a carga das duas (8 placas)")
	_pedir(b, "bau", Vector2i(30, 6))                # pedida depois da saída
	_rodar(b, 0.6)
	igual((d.obras as Array).size(), 2, "a nova não entra no lote em voo")
	verificar(_rodar_ate(b, 30.0, func(): return _tem(m, "bau", Vector2i(30, 0)) and _tem(m, "bau", Vector2i(30, 3))) > 0.0, "fez as duas")
	verificar(not _tem(m, "bau", Vector2i(30, 6)), "a terceira ainda não")
	var voltou := [false]                            # (lambda copia variável simples: array é referência)
	var feita := _rodar_ate(b, 40.0, func():
		voltou[0] = voltou[0] or d.e == Drones.E.POUSANDO or d.e == Drones.E.HANGAR
		return _tem(m, "bau", Vector2i(30, 6)))
	verificar(feita > 0.0, "a terceira foi feita na viagem seguinte")
	verificar(voltou[0], "voltando ao núcleo para buscar o recurso antes")


func test_falta_recurso_fica_fantasma() -> void:
	var b := _base(true, {"placa_ferro": 5, "engrenagem": 3})
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	_pedir(b, "bau", Vector2i(14, 0))                # 4 placas: dá
	_pedir(b, "bau", Vector2i(14, 3))                # mais 4: não dá (só sobra 1)
	_pedir(b, "esteira", Vector2i(14, 6))            # 1 placa: dá, não fica presa pela de cima
	_rodar(b, 0.6)
	var o2: Dictionary = {}
	for o in ob.obras.values():
		if o.item.minimo == Vector2i(14, 3):
			o2 = o
	verificar(not o2.is_empty() and o2.espera, "a sem recurso espera (fantasma âmbar)")
	igual(ob.esperando(), 1, "uma esperando")
	verificar(_rodar_ate(b, 30.0, func(): return _tem(m, "bau", Vector2i(14, 0)) and not m.ids_no_tile(Vector2i(14, 6)).is_empty()) > 0.0,
			"as outras foram feitas mesmo assim")
	verificar(not _tem(m, "bau", Vector2i(14, 3)), "a que falta recurso continua só fantasma")
	b.inv["placa_ferro"] = 10                        # chegou placa no núcleo
	verificar(_rodar_ate(b, 30.0, func(): return _tem(m, "bau", Vector2i(14, 3))) > 0.0, "com recurso, sai e é feita")


func test_remover_por_drone_devolve() -> void:
	var b := _base()
	var m: MapaOcupacao = b.m
	var ob: Obras = b.ob
	var id := m.colocar("bau", Vector2i(16, 2), 0)
	var antes := int(b.inv.placa_ferro)
	verificar(ob.remover(id), "remoção encomendada")
	verificar(m.estruturas.has(id), "continua lá até o drone chegar")
	verificar(m.estruturas[id].get("a_remover", false), "marcada (fantasma vermelho)")
	verificar(_rodar_ate(b, 20.0, func(): return not m.estruturas.has(id)) > 0.0, "o drone desmontou")
	igual(int(b.inv.placa_ferro), antes, "a devolução vem na carga, ainda não entrou")
	verificar(_rodar_ate(b, 20.0, func(): return int(b.inv.placa_ferro) == antes + 4) > 0.0, "ao pousar, as 4 placas entram no estoque")
	verificar(not ob.remover(b.nu), "o núcleo não sai")


func test_fabricar_custa_uma_engrenagem() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var antes := int(b.inv.engrenagem)
	var id := ob.fabricar()
	verificar(id >= 0, "fabricou")
	igual(int(b.inv.engrenagem), antes - 1, "1 engrenagem")
	igual((b.dr as Drones).drones[id].e, Drones.E.NASCENDO, "nasce em holograma")
	_rodar(b, 4.2)
	igual((b.dr as Drones).drones[id].e, Drones.E.HANGAR, "pronto em 4 s")
	while ob.fabricar() >= 0:
		pass
	igual(ob.construtores().size(), ob.frota_max(), "até o máximo")
	igual(ob.pode_fabricar(), "frota cheia", "o botão diz por quê")
	var b2 := _base(true, {"placa_ferro": 10})
	verificar((b2.ob as Obras).fabricar() < 0, "sem engrenagem não fabrica")


func test_cada_drone_um_lote_e_cancelar() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	_pedir(b, "bau", Vector2i(14, 0))
	_pedir(b, "bau", Vector2i(-40, 0))               # longe da primeira: outro lote
	_rodar(b, 1.2)
	var fora := ob.construtores().filter(func(d): return d.e != Drones.E.HANGAR)
	igual(fora.size(), 2, "os dois drones saíram, cada um com seu lote")
	_pedir(b, "bau", Vector2i(20, 10))
	verificar(ob.cancelar_ultimo(), "desfazer cancela a última encomenda")
	verificar(m.motivo_bloqueio("bau", Vector2i(20, 10), 0) == "", "a reserva saiu")
	verificar(_rodar_ate(b, 40.0, func(): return ob.pendentes() == 0) > 0.0, "o resto foi feito")
	verificar(_tem(m, "bau", Vector2i(-40, 0)) and _tem(m, "bau", Vector2i(14, 0)), "as duas obras")


func test_aranha_derruba_e_obras_voltam() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var col: Colonia = b.col
	var m: MapaOcupacao = b.m
	for d in ob.construtores().slice(1):
		(b.dr as Drones).drones.erase(d.id)
	var t := Vector2i(30, 0)
	_pedir(b, "bau", t)
	var c := Vector2(t) + Vector2(0.5, 0.5)
	for k in 6:
		col.aranhas[800 + k] = {"id": 800 + k, "pos": c + Vector2.from_angle(k * TAU / 6.0) * 1.2, "vida": 600.0, "ninho": -1,
				"estado": Colonia.E.PARADA, "alvo": -1, "destino": c, "mordendo": false, "t": 0.0, "preso": 0.0}
	var caiu := _rodar_ate(b, 30.0, func(): return ob.construtores().is_empty() or ob.construtores()[0].e == Drones.E.CAINDO)
	verificar(caiu > 0.0, "as aranhas derrubaram o construtor baixo")
	verificar(ob.pendentes() == 1 and ob.obras.values()[0].estado == "fila", "a obra voltou para a fila")
	verificar(not _tem(m, "bau", t), "não foi construída")


func test_sem_cobrar_e_salvar() -> void:
	var b := _base(false, {})
	var m: MapaOcupacao = b.m
	_pedir(b, "bau", Vector2i(14, 0))
	_pedir(b, "bau", Vector2i(14, 3))
	var ob: Obras = b.ob
	var salvo: Dictionary = str_to_var(var_to_str(ob.estado()))
	var dsalvo: Dictionary = str_to_var(var_to_str((b.dr as Drones).estado()))
	verificar(_rodar_ate(b, 30.0, func(): return _tem(m, "bau", Vector2i(14, 0))) > 0.0, "modo livre também vai de drone, de graça")
	# carregar o save de antes
	var b2 := _base(false, {})
	(b2.dr as Drones).restaurar(dsalvo)
	(b2.ob as Obras).restaurar(salvo)
	igual((b2.ob as Obras).pendentes(), 2, "a fila volta com o save")
	igual((b2.m as MapaOcupacao).motivo_bloqueio("bau", Vector2i(14, 0), 0), "ocupado", "e as reservas")
	igual((b2.ob as Obras).construtores().size(), 2, "os construtores voltam (sem ganhar mais)")
	verificar(_rodar_ate(b2, 40.0, func(): return (b2.ob as Obras).pendentes() == 0) > 0.0, "e são feitas depois de carregar")
