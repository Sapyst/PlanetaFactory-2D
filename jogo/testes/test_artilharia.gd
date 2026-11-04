extends Caso
## Artilharia (artilharia, fase 2.4): modelo do estudo (estudo_artilharia.py; conv_combate_meio.py) com o obus elevado
## a 55°; granada (2 liga leve + 1 foguete + 2 tijolos → 1) por esteira/braço pela boca sul; só mira ninhos, de 32 a
## 120 m; a granada voa em arco e explode com dano em área (150, raio 4). A pesquisa pede a cartografia (Varredura
## profunda), que vem depois do sensor de varredura (lote 17): pesquisável pela árvore.


func _int(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


func test_dados_e_modelo() -> void:
	var r: Dictionary = Registro.estruturas.get("artilharia", {})
	perto(float(r.alcance), 120.0, 1e-6, "alcance 120 m (árvore)")
	igual(r.get("alvo", ""), "ninhos", "mira em ninhos (árvore)")
	igual(Colonia.item_municao("artilharia"), "granada", "munição: granada")
	igual(Colonia.tiros_por_item("artilharia"), 1)
	var md: Dictionary = Registro.modelos.get("artilharia", {})
	igual(Registro.area("artilharia"), Vector2i(3, 3), "3×3")
	igual(md.get("estudo", ""), "estudo_artilharia.py", "convertida do estudo")
	verificar(int(md.tris) <= 10000, "orçamento (%d triângulos)" % md.tris)
	verificar(float(md.dims[0]) <= 3.01, "a base não passa da área (%s)" % str(md.dims))
	var partes := {}
	for p in md.get("partes", []):
		partes[p.nome] = p.pai
	igual(partes.get("giro"), "base", "giro na base")
	igual(partes.get("canhao"), "giro", "obus no giro")
	verificar(float(md.boca[2]) > 3.5, "obus elevado: boca a %.1f m" % float(md.boca[2]))
	# na borda da área (1,5 m do centro, girando) o cano já passa de 3,5 m: não varre as peças vizinhas
	var piv := Vector3(0.0, 0.05, 1.55)
	var dir := (Vector3(md.boca[0], md.boca[1], md.boca[2]) - piv).normalized()
	var t := (1.5 - piv.y) / dir.y
	verificar(piv.z + dir.z * t > 3.5, "na borda o cano está a %.2f m" % (piv.z + dir.z * t))
	verificar(md.has("ejecao") and float(md.get("capsula", {}).get("escala", 1.0)) > 2.0, "estojo grande sai pela calha")
	var portas: Array = md.get("portas", [])
	verificar(portas.size() == 1 and portas[0].nome == "PORTA_ITEM_ENT_S1", "granadas pela boca sul (S1)")
	verificar(ResourceLoader.exists("res://assets/icones/artilharia.png"), "ícone na barra")
	verificar(Registro.menu.categorias.any(func(cat): return "artilharia" in cat.pecas), "no menu (Defesa)")
	verificar(not Registro.progressao.custos.get("artilharia", {}).is_empty(), "custo de construção")


func test_granada_e_pesquisa() -> void:
	verificar(Registro.itens.has("granada"), "item granada")
	verificar(ResourceLoader.exists("res://assets/icones/itens/granada.png"), "ícone da granada")
	var r: Dictionary = Registro.receitas.granada
	igual(r.maquina, "montadora")
	igual(_int(r.entradas), {"liga_leve": 2, "foguete": 1, "tijolo": 2}, "receita da árvore")
	var p := Pesquisa.new()
	verificar(p.jogavel("artilharia"), "pesquisa ligada")
	igual(p.custo("artilharia"), {"pacote_pesquisa": 100, "pacote_automacao": 100, "pacote_militar": 100, "pacote_quimico": 100}, "custo da árvore")
	p.concluidas = {"torre_foguetes": true, "liga_leve": true}
	verificar(not p.disponivel("artilharia"), "travada: espera a cartografia")
	verificar(p.jogavel("cartografia"), "cartografia jogável (sensor de varredura, lote 17)")
	p.concluidas.merge({"sensor_varredura": true, "processador": true, "cartografia": true})
	verificar(p.disponivel("artilharia"), "com a cartografia a artilharia se pesquisa")
	verificar(p.jogavel("dano_artilharia_1") and p.jogavel("alcance_artilharia_1"), "melhorias da artilharia ligadas (fase 2.5, tempestade)")
	p.concluidas["ciencia_tempestade"] = true
	verificar(not p.disponivel("dano_artilharia_1"), "melhorias esperam a própria artilharia")
	p.concluidas["artilharia"] = true
	verificar(p.disponivel("dano_artilharia_1") and p.disponivel("alcance_artilharia_1"), "artilharia + tempestade: melhorias pesquisáveis")
	p.livre = true
	verificar(p.peca_liberada("artilharia") and p.receita_liberada("granada"), "no modo livre (demo) já se constrói")


func _base() -> Array:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var c := Colonia.new(m, Poluicao.new(m.gerador), 3)
	for x in range(-4, 6):
		for y in range(-4, 6):
			m.limpar_obstaculo(Vector2i(x, y))
	return [m, c]


## Ninho perto de `t` (procura chão firme na mesma distância do centro: o mapa tem rio e lago).
func _ninho(m: MapaOcupacao, c: Colonia, t: Vector2i) -> int:
	var r := Vector2(t).length()
	for k in 72:
		var p := Vector2i((Vector2.from_angle(Vector2(t).angle() + (k / 2) * 0.05 * (1 if k % 2 == 0 else -1)) * r).round())
		for x in range(-1, 5):
			for y in range(-1, 5):
				m.limpar_obstaculo(p + Vector2i(x, y))
		var id := c._criar_ninho(p, 1.0)
		if id >= 0:
			return id
	verificar(false, "sem chão para ninho perto de %s" % str(t))
	return -1


func test_so_ninhos_no_alcance() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[1]
	var t := m.colocar("artilharia", Vector2i(-1, -1), 0)
	verificar(t >= 0, "coube")
	c.carregar_torre(t, 10)
	var perto_n := _ninho(m, c, Vector2i(22, -1))         # ~22 m: perto demais (mínimo 32 m: arma grande, de longe)
	var a := c._nova_aranha(perto_n)
	c.aranhas[a].pos = Vector2(20, 0)
	var tiros := []
	for i in 30 * 5:
		c.tick(1.0 / 30.0, [])
		for e in c.eventos:
			if e.tipo == "tiro": tiros.append(e)
	igual(tiros.size(), 0, "não atira em aranha nem em ninho a menos de 32 m")
	var longe := _ninho(m, c, Vector2i(90, 30))          # ~95 m
	var v0: float = c.ninhos[longe].vida
	tiros.clear()
	var explosoes := []
	for i in 30 * 14:
		c.tick(1.0 / 30.0, [])
		for e in c.eventos:
			if e.tipo == "tiro": tiros.append(e)
			if e.tipo == "explosao": explosoes.append(e)
	verificar(tiros.size() >= 3 and tiros.size() <= 4, "um disparo a cada 4 s (%d em 14 s)" % tiros.size())
	verificar(tiros.all(func(e): return e.ninho == longe and e.get("projetil", false)), "todos no ninho de longe")
	verificar(float(tiros[0].dur) > 2.0, "granada voa ~%.1f s" % float(tiros[0].dur))
	verificar(explosoes.size() >= 2, "explodiram")
	var feito: float = v0 - (float(c.ninhos[longe].vida) if c.ninhos.has(longe) else 0.0)
	verificar(feito >= 150.0 * mini(explosoes.size(), 2) - 1e-3, "150 por granada no ninho (%.0f)" % feito)
	# 3 granadas derrubam um ninho (400 ♥)
	for i in 30 * 10:
		c.tick(1.0 / 30.0, [])
	verificar(not c.ninhos.has(longe), "ninho de longe destruído")
	var alem := _ninho(m, c, Vector2i(130, 0))
	var n := 0
	for i in 30 * 6:
		c.tick(1.0 / 30.0, [])
		for e in c.eventos:
			if e.tipo == "tiro" and e.ninho == alem: n += 1
	igual(n, 0, "além de 120 m não alcança")


func test_braco_traz_granada() -> void:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	for x in range(-6, 22):
		for y in range(-12, 10):
			m.limpar_obstaculo(Vector2i(x, y))
	var col := Colonia.new(m, Poluicao.new(m.gerador), 3)
	var f := Fabrica.new(m)
	var g := m.colocar("gerador", Vector2i(8, 6), 0)
	for t in [Vector2i(11, 6), Vector2i(17, 3), Vector2i(17, -2)]:
		m.colocar("poste_energia", t, 0)
	var torre := m.colocar("artilharia", Vector2i(18, -8), 0)
	var bau := m.colocar("bau", Vector2i(19, -4), 0)
	verificar(torre >= 0 and bau >= 0 and m.colocar("braco", Vector2i(19, -5), 2) >= 0, "montagem")
	f.torre_receber = func(id: int, n: int) -> void: col.carregar_torre(id, n)
	f.torre_aceita = col.aceita_municao
	f.reconstruir()
	f.combustivel[g] = 30.0
	f.baus[bau].merge({"granada": 14, "foguete": 3})
	for i in 30 * 30:
		f.tick(1.0 / 30.0)
	igual(int(col.torres[torre].municao), 10, "encheu com 10 granadas")
	igual(int(f.baus[bau].get("granada", 0)), 4, "o resto ficou no baú")
	igual(int(f.baus[bau].get("foguete", 0)), 3, "foguete não serve à artilharia")


# ------------------------------------------------------------------ desenho
func _raiz() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func test_estojo_e_arco() -> void:
	var md: Dictionary = Registro.modelos.artilharia
	var n: Node3D = (load(md.modelo) as PackedScene).instantiate()
	_raiz().add_child(n)
	var a := Animador.new()
	a.modelo = "artilharia"
	n.add_child(a)
	if not a.is_inside_tree():
		a._ready()
	var ej := a.ejecao()
	verificar(ej.size() == 2, "saída do estojo")
	verificar(a.boca() != Vector3.INF and a.boca().y > 3.5, "boca alta (obus a 55°)")
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var dc := DesenhoColonia.new()
	dc.mapa = m
	dc.colonia = Colonia.new(m, Poluicao.new(m.gerador), 3)
	dc.animadores_torre = func(_id: int) -> Animador: return a
	_raiz().add_child(dc)
	if not dc.is_inside_tree():
		dc._ready()
	var ev: Array[Dictionary] = [{"tipo": "tiro", "torre": 5, "nome": "artilharia", "bala": true, "projetil": true, "dur": 2.0,
			"de": Vector2.ZERO, "para": Vector2(40, 0), "aranha": -1, "ninho": 9}]
	dc.atualizar(ev, 0.0)
	igual(dc.capsulas(), 1, "cada disparo ejeta o estojo")
	perto(float(dc._capsulas[0].esc), float(md.capsula.escala), 1e-6, "estojo grande")
	igual(dc.voando(), 1, "granada voando")
	var alto := -INF
	for i in 19:
		dc.atualizar([] as Array[Dictionary], 0.1)
		if dc.voando() > 0:
			alto = maxf(alto, (dc._voos[0].no as Node3D).position.y)
	verificar(alto > 10.0, "arco alto de artilharia (%.1f m)" % alto)
	dc.queue_free()
	n.queue_free()
