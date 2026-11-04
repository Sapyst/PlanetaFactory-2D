extends Caso
## Infestação (teia e sujeira no chão em volta das tocas): nasce com a toca, cresce com a idade, some quando ela cai.


func _cenario() -> Dictionary:
	var g := GeradorMundo.new(1337)
	g.relevo_ativo = false
	var m := MapaOcupacao.new(g)
	for x in range(-12, 12):
		for y in range(-12, 12):
			m.limpar_obstaculo(Vector2i(x, y))
	var col := Colonia.new(m, Poluicao.new(g), 5)
	return {"mapa": m, "colonia": col, "inf": Infestacao.new(col, 5)}


func test_cresce_com_a_idade() -> void:
	var c := _cenario()
	var col: Colonia = c.colonia
	var inf: Infestacao = c.inf
	var id := col._criar_ninho(Vector2i(-1, -1), 1.0)
	verificar(id >= 0, "toca criada")
	igual(float(col.ninhos[id].idade), Infestacao.MADURA_S, "toca que nasce pronta no mapa já é madura")
	inf.tick(1.0)
	verificar(inf.valor(Vector2i(0, 0)) > 0.9, "colada na toca: tomado")
	verificar(inf.valor(Vector2i(4, 0)) > 0.3, "madura: chega a 4 tiles")
	igual(inf.valor(Vector2i(11, 11)), 0.0, "longe: chão limpo")
	col.ninhos[id].idade = 0.0
	inf.tick(1.0)
	verificar(inf.valor(Vector2i(5, 0)) == 0.0, "toca nova: ainda não chegou a 5 tiles")
	verificar(Infestacao.raio_de(col.ninhos[id]) < Infestacao.raio_de({"idade": Infestacao.MADURA_S, "obra": 1.0}), "raio cresce com a idade")
	verificar(Infestacao.raio_de({"idade": 0.0, "obra": 0.2}) < Infestacao.raio_de({"idade": 0.0, "obra": 1.0}), "e com a obra")


func test_some_quando_a_toca_cai() -> void:
	var c := _cenario()
	var col: Colonia = c.colonia
	var inf: Infestacao = c.inf
	var id := col._criar_ninho(Vector2i(-1, -1), 1.0)
	inf.tick(1.0)
	var antes := inf.valor(Vector2i(0, 0))
	col.ninhos.erase(id)
	inf.tick(Infestacao.SOME_S * 0.5)
	var meio := inf.valor(Vector2i(0, 0))
	verificar(meio < antes and meio > 0.0, "sumindo devagar (%.2f → %.2f)" % [antes, meio])
	inf.tick(Infestacao.SOME_S)
	igual(inf.valor(Vector2i(0, 0)), 0.0, "sumiu")
	verificar(inf.chunks().is_empty(), "nenhum chunk tocado")


func test_imagem_do_chunk() -> void:
	var c := _cenario()
	c.colonia._criar_ninho(Vector2i(-1, -1), 1.0)
	var inf: Infestacao = c.inf
	inf.tick(1.0)
	verificar(inf.chunks().has(Vector2i(0, 0)), "chunk da toca tocado")
	var img := inf.imagem(Vector2i(0, 0))
	igual(img.get_width(), Grade.TAM_CHUNK + 2, "mesma moldura do mapa do ambiente")
	verificar(img.get_pixel(1, 1).r > 0.9, "tile (0,0) tomado na imagem")
