extends Caso
## Larvas ácidas: a cratera aparece no mapa (parte dos ninhos), solta larvas da espécie certa, a larva para a ~9 m e
## cospe (metade do alcance da torre padrão), a gosma cai e fere/suja, a torre mata a larva (evento com a espécie) e
## a cratera deixa o chão corroído (canal G da infestação), não a teia.

func _base() -> Array:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var p := Poluicao.new(m.gerador)
	return [m, p, Colonia.new(m, p, 3)]


func _cenario() -> Array:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-38, 37):
		for y in range(-6, 8):
			m.limpar_obstaculo(Vector2i(x, y))
	var alvo := m.colocar("fornalha", Vector2i(-10, 0), 0)
	var cratera := c._criar_ninho(Vector2i(20, 0), 1.0, "larva")
	return [m, b[1], c, alvo, cratera]


func test_cratera_no_mapa() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-8, 9):
		for y in range(-8, 9):
			c.descobrir_chunk(Vector2i(x, y))
	var crateras := 0
	var tocas := 0
	for id in c.ninhos:
		tocas += 1
		var n: Dictionary = c.ninhos[id]
		igual(m.estruturas[id].nome, Colonia.toca_de(n.especie), "toca certa para a espécie")
		if n.especie == "larva":
			crateras += 1
	verificar(crateras >= 2, "crateras de larva no mapa (%d de %d tocas)" % [crateras, tocas])
	verificar(crateras < tocas, "e também ninhos de aranha")
	verificar(Colonia.eh_toca("cratera_larva") and Colonia.eh_toca("ninho_aranha") and not Colonia.eh_toca("fornalha"))


func test_larva_cospe_de_longe() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var c: Colonia = s[2]
	var alvo: int = s[3]
	var l := c._nova_aranha(s[4])
	igual(c.aranhas[l].especie, "larva", "a cratera solta larva")
	igual(c.aranhas[l].vida, float(Registro.inimigos.larva.vida), "vida da larva")
	c.aranhas[l].estado = Colonia.E.ATACANDO
	c.aranhas[l].alvo = alvo
	var fontes: Array[Dictionary] = []
	var cuspes := 0
	var respingos := 0
	var dist_cuspe := INF
	var ferida := false
	for i in 30 * 60:
		c.tick(1.0 / 30.0, fontes)
		for e in c.eventos:
			if e.tipo == "cuspe":
				cuspes += 1
				dist_cuspe = minf(dist_cuspe, Colonia._dist_estrutura(c.aranhas[l].pos, m.estruturas[alvo]))
			if e.tipo == "respingo":
				respingos += 1
				verificar(bool(e.get("larva", false)) or e.has("pos"))
		if c.vida.has(alvo):
			ferida = true
		if cuspes >= 3 and respingos >= 3:
			break
	verificar(cuspes >= 3, "cuspiu (%d)" % cuspes)
	verificar(respingos >= 1, "a gosma caiu (%d)" % respingos)
	verificar(dist_cuspe > 6.0 and dist_cuspe <= 9.0, "cospe de longe, até 9 m (%.1f)" % dist_cuspe)
	var meio := float(Registro.estruturas.torre_defesa.get("alcance", 18)) * 0.5
	verificar(float(Registro.inimigos.larva.alcance_cuspe) <= meio + 0.01, "metade do alcance da torre padrão")
	verificar(ferida or not m.estruturas.has(alvo), "o ácido fere a construção")


func test_torre_mata_larva() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var c: Colonia = s[2]
	var alvo: int = s[3]
	var torre := m.colocar("torre_defesa", Vector2i(-4, 0), 0)
	verificar(torre >= 0)
	for k in 3:
		var l := c._nova_aranha(s[4])
		c.aranhas[l].estado = Colonia.E.ATACANDO
		c.aranhas[l].alvo = alvo
	var mortas := 0
	var fontes: Array[Dictionary] = []
	for i in 30 * 90:
		c.tick(1.0 / 30.0, fontes)
		for e in c.eventos:
			if e.tipo == "aranha_morta":
				igual(e.get("especie", ""), "larva", "evento de morte com a espécie (sangue verde)")
				mortas += 1
		if mortas >= 3:
			break
	verificar(mortas >= 3, "a torre matou as larvas (%d)" % mortas)


func test_chao_corroido() -> void:
	var s := _cenario()
	var c: Colonia = s[2]
	var cr: int = s[4]
	var inf := Infestacao.new(c)
	inf.tick(1.0)
	var t := Vector2i(c.ninhos[cr].centro.floor()) + Vector2i(2, 0)
	verificar(inf.valor_larva(t) > 0.5, "chão corroído em volta da cratera (%.2f)" % inf.valor_larva(t))
	var k := Grade.chunk_de(t)
	var img := inf.imagem(k)
	var px := t - k * Grade.TAM_CHUNK + Vector2i.ONE
	var cor := img.get_pixel(px.x, px.y)
	verificar(cor.g > 0.5 and cor.r < 0.05, "canal G (corrosão), sem teia (%s)" % str(cor))
