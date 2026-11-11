extends Caso
## Patch RTS, postos como base (docs/PLANO_RTS_DRONES.md, 2026-11-11): o posto avançado também é casa de construtor.

const DT := 1.0 / 30.0
const POSTO := Vector2i(60, 0)


func _base(inv := {"placa_ferro": 100, "engrenagem": 20, "placa_cobre": 20}) -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	for x in range(-60, 110):
		for y in range(-60, 60):
			m.limpar_obstaculo(Vector2i(x, y))
	var f := Fabrica.new(m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	var dr := Drones.new(m, f, col)
	var inventario := inv.duplicate()
	var c := Construtor.new(m)
	c.cobrar = true
	c.inventario = inventario
	c.fila_de_obras = true
	var nu := m.colocar("nucleo", Vector2i(-1, -1), 0)
	var po := m.colocar("posto_avancado", POSTO, 0)
	f.reconstruir()
	c.estoque_local = func(t: Vector2i) -> Dictionary:
		var p := f.posto_que_cobre(t)
		return {} if p < 0 else {"id": p, "estoque": f.baus[p]}
	var ob := Obras.new(m, c, dr, inventario)
	ob.cobrar = true
	ob.dar_iniciais()
	return {"g": g, "m": m, "f": f, "col": col, "dr": dr, "c": c, "ob": ob, "inv": inventario, "nu": nu, "po": po}


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


## Um construtor pronto morando no posto.
func _no_posto(b: Dictionary) -> Dictionary:
	var ob: Obras = b.ob
	var id := ob.fabricar(true, b.po)
	var d: Dictionary = (b.dr as Drones).drones[id]
	d.e = Drones.E.HANGAR
	return d


func test_dados() -> void:
	var r: Dictionary = Registro.estruturas.nucleo.construtores
	igual(int(r.max_posto), 3, "até 3 por posto")
	perto(float(r.emprestar_s), 20.0, 0.01, "outra base pega depois de 20 s")
	var dims: Array = Registro.modelos.posto_avancado.dims
	verificar(float(r.alt_orbita_posto) > float(dims[2]) + 0.3, "a órbita do posto passa acima da antena")


func test_posto_e_base() -> void:
	var b := _base()
	var ob: Obras = b.ob
	verificar(ob.eh_base(b.nu) and ob.eh_base(b.po), "núcleo e posto são bases")
	igual(ob.bases(), [b.nu, b.po] as Array[int], "o núcleo primeiro")
	igual(ob.construtores_de(b.po).size(), 0, "posto novo começa sem construtor")
	igual(ob.construtores_de(b.nu).size(), 2, "os 2 iniciais ficam no núcleo")


func test_fabricar_no_posto_paga_do_estoque_dele() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var f: Fabrica = b.f
	f.baus[b.po]["engrenagem"] = 2
	var antes := int(b.inv.engrenagem)
	var id := ob.fabricar(false, b.po)
	verificar(id >= 0, "fabricou no posto")
	igual(int(f.baus[b.po].engrenagem), 1, "a engrenagem saiu do estoque do posto")
	igual(int(b.inv.engrenagem), antes, "o núcleo não pagou")
	f.baus[b.po]["engrenagem"] = 0
	verificar(ob.fabricar(false, b.po) >= 0, "sem engrenagem no posto, paga do núcleo")
	igual(int(b.inv.engrenagem), antes - 1, "1 do núcleo")
	verificar(ob.fabricar(false, b.po) >= 0, "terceiro")
	igual(ob.pode_fabricar(b.po), "frota cheia", "até 3 no posto")
	verificar(ob.fabricar(false, b.po) < 0, "o quarto não")
	verificar(ob.pode_fabricar() == "", "o núcleo tem limite próprio")
	_rodar(b, 4.5)
	var c := (b.dr as Drones).centro(b.po)
	for d in ob.construtores_de(b.po):
		igual(d.e, Drones.E.HANGAR, "pronto")
		perto((d.pos as Vector2).distance_to(c), 1.9, 0.05, "orbita a torre do posto")
		verificar(float(d.alt) > float(Registro.modelos.posto_avancado.dims[2]), "acima do posto (não atravessa o modelo)")


func test_obra_perto_do_posto_sai_do_posto() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	var d := _no_posto(b)
	var t := POSTO + Vector2i(6, 6)
	_pedir(b, "bau", t)
	_rodar(b, 0.6)
	verificar(d.e != Drones.E.HANGAR, "o construtor do posto saiu")
	verificar(ob.construtores_de(b.nu).all(func(x): return x.e == Drones.E.HANGAR), "os do núcleo ficaram")
	verificar(_rodar_ate(b, 20.0, func(): return _tem(m, "bau", t)) > 0.0, "construiu")
	verificar(_rodar_ate(b, 20.0, func(): return d.e == Drones.E.HANGAR) > 0.0, "voltou")
	perto((d.pos as Vector2).distance_to((b.dr as Drones).centro(b.po)), 1.9, 0.05, "para o posto, a casa dele")
	_pedir(b, "bau", Vector2i(10, 0))
	_rodar(b, 0.6)
	igual(d.e, Drones.E.HANGAR, "obra perto do núcleo: o do posto fica")
	verificar(ob.construtores_de(b.nu).any(func(x): return x.e != Drones.E.HANGAR), "sai um do núcleo")


func test_outra_base_so_pega_depois_de_esperar() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var d := _no_posto(b)
	d.e = Drones.E.VOLTANDO                          # o do posto está longe, voltando (~38 s de voo)
	d.pos = (b.dr as Drones).centro(b.po) + Vector2(0, 300)
	d.alt = 4.0
	_pedir(b, "bau", POSTO + Vector2i(-6, 4))
	var saiu := _rodar_ate(b, 30.0, func(): return ob.construtores_de(b.nu).any(func(x): return x.e != Drones.E.HANGAR))
	verificar(saiu > 19.0 and saiu < 22.0, "o núcleo só pega depois de 20 s de espera (%.1f s)" % saiu)
	var b2 := _base()
	var ob2: Obras = b2.ob
	_pedir(b2, "bau", POSTO + Vector2i(-6, 4))
	_rodar(b2, 0.6)
	verificar(ob2.construtores_de(b2.nu).any(func(x): return x.e != Drones.E.HANGAR), "posto sem construtor: o núcleo vai na hora")


func test_volta_deposita_no_posto() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	var f: Fabrica = b.f
	var d := _no_posto(b)
	var id := m.colocar("bau", POSTO + Vector2i(5, -5), 0)
	var antes := int(b.inv.placa_ferro)
	verificar(ob.remover(id), "remoção encomendada")
	verificar(_rodar_ate(b, 20.0, func(): return not m.estruturas.has(id)) > 0.0, "o do posto desmontou")
	verificar(_rodar_ate(b, 20.0, func(): return d.e == Drones.E.HANGAR) > 0.0, "pousou no posto")
	igual(int(f.baus[b.po].get("placa_ferro", 0)), 4, "as 4 placas entraram no estoque do posto")
	igual(int(b.inv.placa_ferro), antes, "não no núcleo")
	f.baus[b.po]["placa_ferro"] = f.capacidade_bau(b.po) - 1  # posto quase lotado
	ob._depositar(b.po, {"placa_ferro": 4})
	igual(int(f.baus[b.po].placa_ferro), f.capacidade_bau(b.po), "o posto lota")
	igual(int(b.inv.placa_ferro), antes + 3, "o que não coube foi para o núcleo")


func test_chamar_e_mandar() -> void:
	var b := _base()
	var ob: Obras = b.ob
	igual(ob.pode_mandar(b.po), "nenhum parado no posto", "nada para mandar")
	igual(ob.chamar(b.po), "", "chamou")
	igual(ob.construtores_de(b.po).size(), 1, "passa a morar no posto")
	igual(ob.construtores_de(b.nu).size(), 1, "sai do núcleo")
	var d: Dictionary = ob.construtores_de(b.po)[0]
	verificar(_rodar_ate(b, 20.0, func(): return d.e == Drones.E.HANGAR) > 6.0, "voou até o posto (60 m)")
	perto((d.pos as Vector2).distance_to((b.dr as Drones).centro(b.po)), 1.9, 0.05, "orbita o posto")
	igual(ob.mandar_ao_nucleo(b.po), "", "mandou de volta")
	igual(ob.construtores_de(b.nu).size(), 2, "voltou a morar no núcleo")
	verificar(_rodar_ate(b, 20.0, func(): return d.e == Drones.E.HANGAR) > 6.0, "voou de volta")
	ob.chamar(b.po)
	ob.chamar(b.po)
	igual(ob.pode_chamar(b.po), "nenhum parado no núcleo", "os dois já foram")


func test_posto_destruido_muda_de_casa() -> void:
	var b := _base()
	var ob: Obras = b.ob
	var m: MapaOcupacao = b.m
	var d := _no_posto(b)
	var total := ob.construtores().size()
	m.remover(b.po)
	_rodar(b, 0.2)
	igual(int(d.est), int(b.nu), "mudou para o núcleo")
	igual(d.e, Drones.E.VOLTANDO, "voando para lá")
	igual(ob.construtores().size(), total, "não caiu")
	verificar(_rodar_ate(b, 20.0, func(): return d.e == Drones.E.HANGAR) > 0.0, "chegou")
	perto((d.pos as Vector2).distance_to((b.dr as Drones).centro(b.nu)), 1.9, 0.05, "orbita o núcleo")


func test_salvar_mantem_a_casa() -> void:
	var b := _base()
	var d := _no_posto(b)
	var salvo: Dictionary = str_to_var(var_to_str((b.dr as Drones).estado()))
	var b2 := _base()
	(b2.dr as Drones).restaurar(salvo)
	(b2.ob as Obras).restaurar((b.ob as Obras).estado())
	igual((b2.ob as Obras).construtores_de(b2.po).size(), 1, "o construtor do posto volta no posto")
	igual((b2.ob as Obras).construtores_de(b2.nu).size(), 2, "e os do núcleo no núcleo")
	verificar(int(d.est) == int(b.po), "(casa original)")
