extends Caso
## Pássaros (patch fauna): vivem onde a natureza está viva, pousam e decolam, fogem do susto/fogo/monstro, levam
## semente para chão morto (vira muda), dormem à noite e migram com a estação.

func _mundo() -> Array:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	return [g, m, amb, col]


func _lugar_vivo(p: Passaros) -> Vector2:
	var melhor := Vector2.ZERO
	var nota := -1.0
	for y in range(-120, 121, 12):
		for x in range(-120, 121, 12):
			var s := p.lotacao(Vector2(x, y))
			if s > nota:
				nota = s
				melhor = Vector2(x, y)
	return melhor


func test_vivem_onde_ha_vida() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var foco := _lugar_vivo(p)
	verificar(p.lotacao(foco) >= 3, "região viva aguenta bandos (%d)" % p.lotacao(foco))
	for i in 30 * 60:
		p.tick(1.0 / 30.0, foco)
	verificar(p.bandos.size() >= 2, "bandos chegaram (%d)" % p.bandos.size())
	var pousou := false
	for i in 30 * 90:
		p.tick(1.0 / 30.0, foco)
		for b in p.bandos.values():
			if b.estado == Passaros.E.POUSADO:
				pousou = true
	verificar(pousou, "algum bando pousou para comer")
	# a mesma região toda queimada e suja: não aguenta pássaro
	var amb: AmbienteVivo = w[2]
	for y in range(int(foco.y) - 70, int(foco.y) + 71):
		for x in range(int(foco.x) - 70, int(foco.x) + 71):
			amb.somar(Vector2i(x, y), AmbienteVivo.QUEIM, 1.0)
	igual(p.lotacao(foco), 0, "chão morto: nenhum bando")


func test_fogem_do_susto() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var foco := _lugar_vivo(p)
	var b := p._novo("pardelo", foco)
	b.estado = Passaros.E.POUSADO
	b.alt = 0.0
	b.t = 100.0
	p.bandos[b.id] = b
	p.assustar(foco + Vector2(2, 0), 6.0)
	p.tick(0.1, foco)
	igual(b.estado, Passaros.E.FUGINDO, "o tiro perto espanta o bando")
	verificar(p.eventos.any(func(e): return e.tipo == "revoada"), "revoada (som e animação de decolar)")
	verificar((b.destino as Vector2).distance_to(foco + Vector2(2, 0)) > 15.0, "foge para longe do susto")
	# monstro perto também espanta
	var b2 := p._novo("cobrico", foco + Vector2(5, 5))
	b2.estado = Passaros.E.POUSADO
	b2.alt = 0.0
	b2.t = 100.0
	p.bandos[b2.id] = b2
	var col: Colonia = w[3]
	col.aranhas[999] = {"id": 999, "pos": foco + Vector2(7, 5)}
	p.tick(0.6, foco)
	igual(b2.estado, Passaros.E.FUGINDO, "aranha perto espanta")


func test_semente_vira_muda_no_chao_morto() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var amb: AmbienteVivo = w[2]
	var foco := _lugar_vivo(p)
	var g: GeradorMundo = w[0]
	# uma faixa de 30 tiles de terra firme perto do foco (sem água no caminho)
	var achou := false
	for dy in range(-40, 41, 4):
		for dx in range(-40, 41, 4):
			if achou:
				break
			var ok := true
			for k in range(-1, 31):
				for j in range(-3, 4):
					if g.terreno(Vector2i(int(foco.x) + dx + k, int(foco.y) + dy + j)) != GeradorMundo.Terreno.TERRA:
						ok = false
			if ok:
				foco += Vector2(dx, dy)
				achou = true
	verificar(achou, "achou faixa de terra para o teste")
	# faixa queimada (morta) no caminho, limpa de obstáculo
	var m: MapaOcupacao = w[1]
	for y in range(int(foco.y) - 3, int(foco.y) + 4):
		for x in range(int(foco.x), int(foco.x) + 30):
			m.limpar_obstaculo(Vector2i(x, y))
			amb.somar(Vector2i(x, y), AmbienteVivo.QUEIM, 0.8)
	var b := p._novo("pardelo", foco)
	b.sementes = 2
	b.destino = foco + Vector2(29, 0)
	b.pousar = false
	b.alt = 5.0
	p.bandos[b.id] = b
	var antes := amb.plantas.size()
	var plantou := false
	for i in 30 * 40:
		p.tick(1.0 / 30.0, foco)
		for e in p.eventos:
			if e.tipo == "semente":
				plantou = true
		p.eventos.clear()
		if plantou:
			break
	verificar(plantou, "deixou cair semente no chão morto")
	verificar(amb.plantas.size() > antes, "nasceu muda (%d → %d)" % [antes, amb.plantas.size()])


func test_noite_e_migracao() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var foco := _lugar_vivo(p)
	var clima := Clima.new(3)
	clima.ciclo = false
	clima.hora = 0.02                          # madrugada
	var b := p._novo("rubro", foco)
	b.estado = Passaros.E.POUSADO
	b.alt = 0.0
	b.t = 0.5
	p.bandos[b.id] = b
	for i in 30 * 10:
		p.tick(1.0 / 30.0, foco, clima)
	igual(b.estado, Passaros.E.POUSADO, "de noite fica pousado (dormindo)")
	verificar(b.dormindo, "dormindo")
	var n0 := p.bandos.size()
	for i in 30 * 20:
		p.tick(1.0 / 30.0, foco, clima)
	igual(p.bandos.size(), n0, "ninguém chega de noite")
	# inverno: o azulão migrou (peso 0), não aparece
	clima.estacao = 3
	igual(p._fator_estacao("azulao", clima), 0.0, "azulão some no inverno")
	verificar(p._fator_estacao("pardelo", clima) > 0.0, "pardelo fica")


func test_planador_circula_alto() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var foco := _lugar_vivo(p)
	var b := p._novo("planador", foco)
	b.estado = Passaros.E.CIRCULANDO
	b.centro = foco
	p.bandos[b.id] = b
	var mais_longe := 0.0
	for i in 30 * 30:
		p.tick(1.0 / 30.0, foco)
		mais_longe = maxf(mais_longe, (b.pos as Vector2).distance_to(b.centro))
	igual(b.estado, Passaros.E.CIRCULANDO, "nunca pousa")
	verificar(float(b.alt) > 12.0, "voa alto (%.1f m)" % float(b.alt))
	verificar(mais_longe > 6.0 and mais_longe < 22.0, "circula em volta do centro (%.1f)" % mais_longe)


func test_bandos_se_juntam() -> void:
	var w := _mundo()
	var p := Passaros.new(w[0], w[1], w[2], w[3])
	var foco := _lugar_vivo(p)
	var a := p._novo("pardelo", foco)
	var b := p._novo("pardelo", foco + Vector2(3, 0))
	var c := p._novo("cobrico", foco + Vector2(2, 1))
	a.n = 10
	b.n = 8
	for x in [a, b, c]:
		x.destino = foco + Vector2(40, 0)
		x.pousar = false
		p.bandos[x.id] = x
	p.tick(0.1, foco)
	verificar(not (p.bandos.has(a.id) and p.bandos.has(b.id)), "os dois bandos de pardelo viraram um")
	var junto: Dictionary = p.bandos.get(a.id, p.bandos.get(b.id, {}))
	igual(int(junto.get("n", 0)), 18, "o bando grande somou os pássaros")
	verificar(p.bandos.has(c.id), "outra espécie não se mistura")
	verificar(p.eventos.any(func(e): return e.tipo == "juntou"), "evento para o desenho passar os pássaros")
