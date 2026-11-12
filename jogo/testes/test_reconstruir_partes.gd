extends Caso
## Desempenho (2026-11-12): a Fabrica remonta só a metade que a obra tocou (Fabrica.reconstruir("esteiras"/"resto")).
## Dois mundos iguais recebem a mesma sequência de obras com a simulação rodando entre elas: um remonta por partes,
## o outro remonta tudo. Itens nas esteiras, baús, braços e o estoque do núcleo têm que terminar idênticos.

const DT := 1.0 / 30.0


func _mundo() -> Array:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	for x in range(-8, 26):
		for y in range(-8, 10):
			m.limpar_obstaculo(Vector2i(x, y))
	var c := Construtor.new(m)
	var f := Fabrica.new(m)
	f.estoque_nucleo = {}
	return [c, f]


## Remonta como o mundo faz depois de uma obra: por partes (pelo tipo das peças) ou tudo.
func _remontar(f: Fabrica, nomes: Array, partes: bool) -> void:
	if not partes:
		f.reconstruir()
		return
	var de_esteira := nomes.filter(func(n): return Fabrica.eh_peca_esteira(n)).size()
	f.reconstruir("" if de_esteira > 0 and de_esteira < nomes.size() else ("esteiras" if de_esteira > 0 else "resto"))


func _rodar(f: Fabrica, s: float) -> void:
	for i in int(s / DT):
		f.tick(DT)


## Retrato do que importa: caminhos (tiles, itens, espaços), baús, braços e o núcleo.
func _retrato(f: Fabrica) -> Dictionary:
	var cs := []
	for c in f.caminhos:
		var e: EsteiraCaminho = c.esteira
		cs.append([c.tiles, e.itens.duplicate(), Array(e.espacos), e.saida.is_valid(), e.proximo != null])
	var bs := {}
	for id in f.bracos:
		bs[id] = [f.bracos[id].segurando, f.bracos[id].estado, f.bracos[id].origem != null, f.bracos[id].destino != null]
	return {"caminhos": cs, "baus": f.baus.duplicate(true), "bracos": bs, "nucleo": f.estoque_nucleo.duplicate()}


## A sequência de obras: [descrição, função(c, ids) → nomes das peças mexidas].
func _obras() -> Array:
	return [
		["energia e alimentador", func(c: Construtor, ids: Dictionary) -> Array:
			ids.gerador = c.mapa.colocar("gerador", Vector2i(8, 6), 0)
			for t in [Vector2i(11, 6), Vector2i(5, 3), Vector2i(-1, 3), Vector2i(17, 3), Vector2i(11, -4)]:
				c.mapa.colocar("poste_energia", t, 0)
			ids.fonte = c.mapa.colocar("bau", Vector2i(-3, -2), 0)
			ids.alimenta = c.mapa.colocar("braco", Vector2i(-3, -1), 0)
			return ["gerador", "poste_energia", "bau", "braco"]],
		["esteira principal", func(c: Construtor, _ids: Dictionary) -> Array:
			c.executar(c.plano_linha("esteira", Vector2i(-3, 0), Vector2i(8, 0), 0))
			return ["esteira_reta"]],
		["braço e baú no meio", func(c: Construtor, ids: Dictionary) -> Array:
			ids.braco1 = c.mapa.colocar("braco", Vector2i(1, 1), 0)
			ids.bau1 = c.mapa.colocar("bau", Vector2i(1, 2), 0)
			c.mapa.estruturas[ids.braco1]["filtros"] = ["carvao"]
			return ["braco", "bau"]],
		["esteira estendida", func(c: Construtor, _ids: Dictionary) -> Array:
			c.executar(c.plano_linha("esteira", Vector2i(9, 0), Vector2i(13, 0), 0))
			return ["esteira_reta"]],
		["núcleo na ponta", func(c: Construtor, ids: Dictionary) -> Array:
			ids.nucleo = c.mapa.colocar("nucleo", Vector2i(14, -1), 0)
			return ["nucleo"]],
		["tira um pedaço da esteira", func(c: Construtor, _ids: Dictionary) -> Array:
			c.mapa.remover(c.mapa.tiles[Vector2i(5, 0)])
			return ["esteira_reta"]],
		["põe de volta", func(c: Construtor, _ids: Dictionary) -> Array:
			c.executar(c.plano_peca("esteira", Vector2i(5, 0), 0))
			return ["esteira_reta"]],
		["tira o núcleo (a ponta perde o destino)", func(c: Construtor, ids: Dictionary) -> Array:
			c.mapa.remover(ids.nucleo)
			return ["nucleo"]],
		["tira o braço do meio", func(c: Construtor, ids: Dictionary) -> Array:
			c.mapa.remover(ids.braco1)
			return ["braco"]],
		["braço e baú na ponta", func(c: Construtor, ids: Dictionary) -> Array:
			ids.braco2 = c.mapa.colocar("braco", Vector2i(13, 1), 0)
			ids.bau2 = c.mapa.colocar("bau", Vector2i(13, 2), 0)
			return ["braco", "bau"]],
		["curva e ramal novo", func(c: Construtor, _ids: Dictionary) -> Array:
			c.executar(c.plano_linha("esteira", Vector2i(20, -6), Vector2i(20, -2), 0))
			c.executar(c.plano_linha("esteira", Vector2i(21, -2), Vector2i(24, -2), 0))
			return ["esteira_reta", "esteira_curva_dir"]],
	]


func test_por_partes_igual_a_tudo() -> void:
	var a := _mundo()
	var b := _mundo()
	var ids_a := {}
	var ids_b := {}
	var obras := _obras()
	var conferidas := 0
	for i in obras.size():
		var nomes_a: Array = obras[i][1].call(a[0], ids_a)
		var nomes_b: Array = obras[i][1].call(b[0], ids_b)
		_remontar(a[1], nomes_a, true)
		_remontar(b[1], nomes_b, false)
		if i == 0:
			for f: Fabrica in [a[1], b[1]]:
				f.baus[ids_a.fonte] = {"carvao": 400, "pedra": 400}
				for id in f.combustivel:
					f.combustivel[id] = 200.0
		_rodar(a[1], 6.0)
		_rodar(b[1], 6.0)
		var ra := _retrato(a[1])
		var rb := _retrato(b[1])
		verificar(ra == rb, "depois de \"%s\": igual a remontar tudo" % obras[i][0])
		if ra != rb:
			for ch in ra:
				if ra[ch] != rb[ch]:
					print("  diferente em %s:\n    partes %s\n    tudo   %s" % [ch, ra[ch], rb[ch]])
		conferidas += 1
	var fa: Fabrica = a[1]
	verificar(int(fa.baus.get(ids_a.bau1, {}).get("carvao", 0)) > 0 or not fa.baus.has(ids_a.bau1), "o braço do meio trabalhou")
	verificar(int(fa.estoque_nucleo.get("pedra", 0)) + int(fa.estoque_nucleo.get("carvao", 0)) > 0, "o núcleo recebeu itens (%s)" % fa.estoque_nucleo)
	verificar(int(fa.baus.get(ids_a.bau2, {}).get("pedra", 0)) + int(fa.baus.get(ids_a.bau2, {}).get("carvao", 0)) > 0, "o baú da ponta recebeu (%s)" % fa.baus.get(ids_a.bau2, {}))
	igual(conferidas, obras.size(), "todas as obras conferidas")


## A rede de segurança: pedir "resto" com uma esteira mudada por fora (girada à mão) remonta tudo.
func test_resto_com_esteira_mudada_remonta_tudo() -> void:
	var w := _mundo()
	var c: Construtor = w[0]
	var f: Fabrica = w[1]
	c.executar(c.plano_linha("esteira", Vector2i(0, 0), Vector2i(6, 0), 0))
	f.reconstruir()
	var antes := f.caminhos.size()
	c.mapa.estruturas[c.mapa.tiles[Vector2i(3, 0)]].rot = 1                 # girou sem passar pela obra
	f.reconstruir("resto")
	verificar(f.caminhos.size() > antes, "os caminhos foram remontados (%d → %d)" % [antes, f.caminhos.size()])


## Cada modo pula mesmo a outra metade: "resto" mantém os caminhos (e os itens neles), "esteiras" mantém a rede.
func test_cada_modo_pula_a_outra_metade() -> void:
	var w := _mundo()
	var c: Construtor = w[0]
	var f: Fabrica = w[1]
	c.mapa.colocar("gerador", Vector2i(8, 6), 0)
	c.mapa.colocar("poste_energia", Vector2i(5, 3), 0)
	c.executar(c.plano_linha("esteira", Vector2i(0, 0), Vector2i(6, 0), 0))
	f.reconstruir()
	var cam: Dictionary = f.caminhos[0]
	(cam.esteira as EsteiraCaminho).inserir_na_entrada("pedra")
	c.mapa.colocar("bau", Vector2i(3, 2), 0)
	f.reconstruir("resto")
	verificar(is_same(f.caminhos[0], cam), "resto: o mesmo caminho (não remontou as esteiras)")
	igual((f.caminhos[0].esteira as EsteiraCaminho).itens, ["pedra"] as Array[String], "e o item continua nele")
	var rede := f.rede
	c.executar(c.plano_linha("esteira", Vector2i(7, 0), Vector2i(9, 0), 0))
	f.reconstruir("esteiras")
	verificar(is_same(f.rede, rede), "esteiras: a mesma rede de energia (não remontou o resto)")
	verificar(not is_same(f.caminhos[0], cam), "e os caminhos foram refeitos")


## Obra numa esteira não mexe na outra: o trecho que não mudou volta com a mesma EsteiraCaminho (itens no lugar exato).
func test_trecho_igual_reaproveitado() -> void:
	var w := _mundo()
	var c: Construtor = w[0]
	var f: Fabrica = w[1]
	c.executar(c.plano_linha("esteira", Vector2i(0, 0), Vector2i(6, 0), 0))
	c.executar(c.plano_linha("esteira", Vector2i(0, 4), Vector2i(6, 4), 0))
	f.reconstruir()
	var a: EsteiraCaminho = f.caminhos[f._no_tile[Vector2i(0, 0)][0]].esteira
	var b: EsteiraCaminho = f.caminhos[f._no_tile[Vector2i(0, 4)][0]].esteira
	a.inserir_em("pedra", 3.3)
	var espacos := a.espacos.duplicate()
	c.executar(c.plano_linha("esteira", Vector2i(7, 4), Vector2i(9, 4), 0))
	f.reconstruir("esteiras")
	verificar(is_same(f.caminhos[f._no_tile[Vector2i(0, 0)][0]].esteira, a), "a esteira de cima não mudou: a mesma")
	verificar(a.espacos == espacos, "o item ficou exatamente onde estava")
	verificar(not is_same(f.caminhos[f._no_tile[Vector2i(0, 4)][0]].esteira, b), "a de baixo cresceu: esteira nova")
	perto(float(f.caminhos[f._no_tile[Vector2i(0, 4)][0]].esteira.comprimento), 10.0, 0.001, "com 10 tiles")
