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


func test_acido_consome_arvores() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-8, 9):
		for y in range(-8, 9):
			c.descobrir_chunk(Vector2i(x, y))
	var inf := Infestacao.new(c)
	var arvores_antes := {}                  # árvores no raio das crateras, antes do ácido
	for id in c.ninhos:
		if c.ninhos[id].especie != "larva":
			continue
		var ct: Vector2 = c.ninhos[id].centro
		for y in range(int(ct.y) - 8, int(ct.y) + 9):
			for x in range(int(ct.x) - 8, int(ct.x) + 9):
				var t := Vector2i(x, y)
				var o := m.gerador.distribuicao.obstaculo(t)
				if not o.is_empty() and Distribuicao.eh_arvore(o.nome) and Vector2i(o.ancora) == t and not m.limpos.has(t):
					arvores_antes[t] = true
	verificar(arvores_antes.size() >= 3, "há árvores perto das crateras (%d)" % arvores_antes.size())
	inf.tick(1.0)                            # crateras antigas do mapa: o perto já foi consumido, sem animação
	var sumiram := 0
	var mortas := 0
	for t in arvores_antes:
		if m.limpos.has(t): sumiram += 1
		elif m.arvores.get(t, {}).get("e", "") == "corroida": mortas += 1
	verificar(sumiram >= 1, "as do centro já sumiram (%d)" % sumiram)
	for ev in inf.eventos:
		if ev.tipo == "arvore_dissolvida":
			verificar(ev.silencioso, "cratera antiga: some sem animação")
	inf.eventos.clear()
	var animadas := 0
	for i in 120:
		inf.tick(1.0)
		for ev in inf.eventos:
			if ev.tipo == "arvore_dissolvida" and not ev.silencioso: animadas += 1
		inf.eventos.clear()
	var de_pe := 0
	for t in arvores_antes:
		if not m.limpos.has(t) and inf.valor_larva(t) >= Infestacao.ARVORE_MIN * 1.8:
			de_pe += 1
	igual(de_pe, 0, "com o tempo, o ácido forte não deixa árvore de pé")
	verificar(animadas + sumiram >= sumiram + mortas, "as mortas afundaram depois (%d animadas, %d mortas)" % [animadas, mortas])
	# arbusto e cogumelo também afundam; pedra fica
	var outras := 0
	for id in c.ninhos:
		if c.ninhos[id].especie != "larva":
			continue
		var ct: Vector2 = c.ninhos[id].centro
		for y in range(int(ct.y) - 6, int(ct.y) + 7):
			for x in range(int(ct.x) - 6, int(ct.x) + 7):
				var t := Vector2i(x, y)
				var o := m.gerador.distribuicao.obstaculo(t)
				if o.is_empty() or Vector2i(o.ancora) != t or Distribuicao.eh_arvore(o.nome) or inf.valor_larva(t) < 0.7:
					continue
				if Registro.modelos.get(o.nome, {}).get("categoria", "") == "mapa/vegetacao":
					outras += 1
					verificar(m.limpos.has(t), "%s no ácido forte afundou" % o.nome)
	verificar(outras >= 1, "havia arbusto/cogumelo no ácido (%d)" % outras)
	# a beira (ácido fraco) não chega às raízes
	for t in arvores_antes:
		if inf.valor_larva(t) < Infestacao.ARVORE_MIN * 0.5:
			verificar(not m.limpos.has(t) and not m.arvores.has(t), "árvore fora da mancha fica intacta")


func test_cratera_antiga_nao_apressa_as_outras() -> void:
	# cratera nova (jovem) com árvore em volta; outra antiga aparece longe: a jovem segue no seu ritmo (com animação)
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	var inf := Infestacao.new(c)
	var jovem := -1
	var arv := Vector2i.ZERO
	for y in range(-60, 61, 3):
		for x in range(-60, 61, 3):
			if jovem >= 0:
				break
			var p := Vector2i(x, y)
			if m.motivo_bloqueio("cratera_larva", p, 0) != "":
				continue
			for dy in range(-2, 5):
				for dx in range(-2, 5):
					var t := p + Vector2i(dx, dy)
					var o := m.gerador.distribuicao.obstaculo(t)
					if jovem < 0 and not o.is_empty() and Distribuicao.eh_arvore(o.nome) and Vector2i(o.ancora) == t \
							and (Vector2(t) + Vector2(0.5, 0.5)).distance_to(Vector2(p) + Vector2(1.5, 1.5)) < 2.6:
						jovem = c._criar_ninho(p, 1.0, "larva")
						arv = t
	verificar(jovem >= 0, "achou lugar com árvore perto")
	c.ninhos[jovem].idade = 0.0
	inf.tick(1.0)
	verificar(not m.limpos.has(arv), "cratera jovem: a árvore ainda está de pé")
	var antiga := c._criar_ninho(Vector2i(200, 200), 1.0, "larva")
	if antiga >= 0:
		inf.tick(1.0)
		verificar(not m.limpos.has(arv), "a cratera antiga longe não apressa a jovem")


## Desempenho (2026-11-11): o ácido guarda a vegetação em volta de cada cratera e só olha as crateras vizinhas.
## O resultado tem que ser idêntico ao do jeito antigo (varrer o gerador e todas as fontes a cada segundo).
class InfAntiga extends Infestacao:
	func _consumir(passo: float, silencioso := false, so_centro := Vector2.INF) -> void:
		var mapa: MapaOcupacao = colonia.mapa
		var fs := fontes()
		var mudaram: Array = []
		for f in fs:
			if not bool(f[3]):
				continue
			var c: Vector2 = f[0]
			if so_centro != Vector2.INF and c != so_centro:
				continue
			var alcance := int(ceil(float(f[1]) * 1.3 + BORDA))
			for y in range(int(c.y) - alcance, int(c.y) + alcance + 1):
				for x in range(int(c.x) - alcance, int(c.x) + alcance + 1):
					var t := Vector2i(x, y)
					if mapa.limpos.has(t):
						continue
					var o := mapa.gerador.distribuicao.obstaculo(t)
					if o.is_empty() or Vector2i(o.ancora) != t:
						continue
					var arvore := Distribuicao.eh_arvore(o.nome)
					if not arvore and Registro.modelos.get(o.nome, {}).get("categoria", "") != "mapa/vegetacao":
						continue
					var v := _valor(Vector2(t) + Vector2(0.5, 0.5), fs, true)
					if v < ARVORE_MIN:
						continue
					var e: String = mapa.arvores.get(t, {}).get("e", "")
					if e == "caida":
						continue
					var acc: float = float(_corroendo.get(t, 0.0)) + passo * v
					if acc >= (DISSOLVE_S if arvore else CORROI_S):
						_corroendo.erase(t)
						mapa.arvores.erase(t)
						mapa.limpar_obstaculo(t)
						eventos.append({"tipo": "arvore_dissolvida", "tile": t, "nome": o.nome, "silencioso": silencioso,
								"tiles": Grade.tiles_da_area(o.ancora, o.area, 0)})
						continue
					_corroendo[t] = acc
					if acc >= CORROI_S and e != "corroida":
						mapa.arvores[t] = {"e": "corroida"}
						mudaram.append(t)
		if not mudaram.is_empty():
			eventos.append({"tipo": "arvores_mudaram", "tiles": mudaram})


func _mundo_larvas() -> Array:
	var b := _base()
	var c: Colonia = b[2]
	for x in range(-8, 9):
		for y in range(-8, 9):
			c.descobrir_chunk(Vector2i(x, y))
	return b


func test_acido_igual_ao_jeito_antigo() -> void:
	var a := _mundo_larvas()
	var b := _mundo_larvas()
	var ma: MapaOcupacao = a[0]
	var mb: MapaOcupacao = b[0]
	var ca: Colonia = a[2]
	var cb: Colonia = b[2]
	var larvas := 0
	for id in ca.ninhos:
		if ca.ninhos[id].especie == "larva":
			larvas += 1
			ca.ninhos[id].idade = 300.0          # crateras jovens: crescem durante o teste (o alcance muda)
			cb.ninhos[id].idade = 300.0
	verificar(larvas >= 2, "há crateras de larva (%d)" % larvas)
	var nova := Infestacao.new(ca)
	var velha := InfAntiga.new(cb)
	var ev_a := []
	var ev_b := []
	for i in 150:
		if i == 70:                               # uma cratera cai no meio: a lista dela sai, o resto segue igual
			for id in ca.ninhos.keys():
				if ca.ninhos[id].especie == "larva":
					ca.ninhos.erase(id)
					cb.ninhos.erase(id)
					break
		for id in ca.ninhos:
			ca.ninhos[id].idade += 1.0
			cb.ninhos[id].idade += 1.0
		nova.tick(1.0)
		velha.tick(1.0)
		ev_a.append_array(nova.eventos)
		ev_b.append_array(velha.eventos)
		nova.eventos.clear()
		velha.eventos.clear()
	igual(ev_a.size(), ev_b.size(), "os mesmos eventos (%d)" % ev_a.size())
	verificar(ev_a == ev_b, "eventos idênticos, na mesma ordem")
	verificar(ev_a.size() >= 3, "o ácido trabalhou no teste (%d eventos)" % ev_a.size())
	verificar(nova._corroendo == velha._corroendo, "o ácido acumulado igual em cada tile (%d)" % nova._corroendo.size())
	verificar(ma.limpos == mb.limpos, "as mesmas árvores sumiram")
	verificar(ma.arvores == mb.arvores, "as mesmas mortas de pé")
	verificar(nova._veg.size() <= larvas, "a lista guardada é só das crateras que existem")
