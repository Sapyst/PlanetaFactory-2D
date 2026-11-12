extends Caso
## Desempenho (2026-11-11): a busca de árvores e arbustos perto (Ecossistema.arvores_perto/arbustos_perto) usa a
## vegetação guardada por chunk. Tem que devolver exatamente o mesmo que a varredura antiga do gerador, tile a tile,
## em busca pequena e grande, e depois que o mapa muda (limpar, construir, árvore morta).


func _antiga(eco: Ecossistema, c: Vector2, raio: float, arbusto: bool) -> Array:
	var mapa := eco.mapa
	var out: Array = []
	var r := int(ceil(raio))
	var ct := Vector2i(c.round())
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var t := ct + Vector2i(x, y)
			if Vector2(x, y).length() > raio or mapa.limpos.has(t) or mapa.tiles.has(t):
				continue
			var o := eco.gerador.distribuicao.obstaculo(t)
			if o.is_empty() or Vector2i(o.ancora) != t:
				continue
			var nome := String(o.nome)
			var md: Dictionary = Registro.modelos.get(nome, {})
			if md.get("categoria", "") != "mapa/vegetacao" or nome.begins_with("arbusto") != arbusto:
				continue
			if not arbusto and not nome.begins_with("arv"):
				continue
			if nome == "arvore_morta" or not mapa.arvores.get(t, {}).is_empty():
				continue
			var dims: Array = md.get("dims", [1, 1, 2])
			var perfil := Ecossistema.perfil_folha(nome)
			out.append({"tile": t, "pos": Vector2(t) + Vector2(0.5, 0.5), "nome": nome, "alto": float(dims[2]),
					"copa": maxf(float(dims[0]), float(dims[1])) * 0.5, "perfil": perfil, "caduca": perfil >= 1})
	return out


func _conferir(eco: Ecossistema, rotulo: String) -> int:
	var total := 0
	for c in [Vector2(0, 0), Vector2(-37.4, 51.2), Vector2(120.6, -88.1), Vector2(31.9, 31.9), Vector2(-64, -64)]:
		for raio in [1.2, 1.5, 3.0, 5.0, 8.0, 14.0, 28.0, 30.0]:
			var nova := eco.arvores_perto(c, raio)
			var velha := _antiga(eco, c, raio, false)
			verificar(nova == velha, "%s: árvores em %s raio %.1f (%d × %d)" % [rotulo, c, raio, nova.size(), velha.size()])
			var nb := eco.arbustos_perto(c, raio)
			var vb := _antiga(eco, c, raio, true)
			verificar(nb == vb, "%s: arbustos em %s raio %.1f (%d × %d)" % [rotulo, c, raio, nb.size(), vb.size()])
			total += nova.size() + nb.size()
	return total


func test_igual_a_varredura_antiga() -> void:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var eco := Ecossistema.new(g, m, AmbienteVivo.new(g, m))
	var n := _conferir(eco, "mapa novo")
	verificar(n > 100, "achou bastante vegetação (%d)" % n)
	# o mapa muda: árvores limpas, uma construção, árvores queimadas e mortas
	var achadas := eco.arvores_perto(Vector2(0, 0), 28.0)
	verificar(achadas.size() >= 6, "árvores perto da origem (%d)" % achadas.size())
	for i in 3:
		m.limpar_obstaculo(achadas[i].tile)
	m.arvores[achadas[3].tile] = {"e": "queimada"}
	m.arvores[achadas[4].tile] = {"e": "corroida"}
	var t5: Vector2i = achadas[5].tile
	m.limpar_obstaculo(t5)
	m.colocar("bau", t5, 0)
	_conferir(eco, "depois de limpar, construir e queimar")
	verificar(not eco.arvores_perto(Vector2(0, 0), 28.0).any(func(a): return a.tile == achadas[0].tile), "a limpa saiu da lista")
