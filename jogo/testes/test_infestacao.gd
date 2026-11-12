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


## Desempenho (2026-11-11): a imagem só usa as fontes que alcançam o chunk; tem que sair igual à de todas as fontes.
func test_imagem_igual_com_fontes_do_chunk() -> void:
	var c := _cenario()
	var col: Colonia = c.colonia
	var inf: Infestacao = c.inf
	col._criar_ninho(Vector2i(-1, -1), 1.0)
	col._criar_ninho(Vector2i(28, 4), 1.0)
	col._criar_ninho(Vector2i(-40, -30), 1.0, "larva")
	inf.tick(1.0)
	var fs := inf.fontes()
	var conferidos := 0
	for k in inf.chunks():
		var img := inf.imagem(k)
		var base: Vector2i = k * Grade.TAM_CHUNK - Vector2i.ONE
		var ref := Image.create(Grade.TAM_CHUNK + 2, Grade.TAM_CHUNK + 2, false, Image.FORMAT_RG8)   # o jeito antigo
		for j in Grade.TAM_CHUNK + 2:
			for i in Grade.TAM_CHUNK + 2:
				var p := Vector2(base + Vector2i(i, j)) + Vector2(0.5, 0.5)
				var v := inf._valor(p, fs, false)
				var g := inf._valor(p, fs, true)
				if v > 0.0 or g > 0.0:
					ref.set_pixel(i, j, Color(v, g, 0))
		verificar(img.get_data() == ref.get_data(), "chunk %s igual ao de todas as fontes" % k)
		conferidos += 1
	verificar(conferidos >= 3, "conferiu os chunks tocados (%d)" % conferidos)
	var k0 := Grade.chunk_de(Vector2i(-1, -1))
	var assin := inf.assinatura(k0, fs)
	inf.tick(1.0)
	igual(inf.assinatura(k0, inf.fontes()), assin, "nada mudou: a assinatura do chunk fica igual (não redesenha)")
	verificar(inf.assinatura(Grade.chunk_de(Vector2i(-40, -30)), fs) != assin, "outro chunk, outra assinatura")
