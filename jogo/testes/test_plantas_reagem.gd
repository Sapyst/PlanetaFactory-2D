extends Caso
## Patch fauna, fase 2 (docs/PLANO_FAUNA.md): plantas que reagem — viço do capim com chuva e seca, árvores perto
## (para folhas, galhos e cogumelos), galhos depois da tempestade, cogumelos depois da chuva, folhas no outono.

const DT := 1.0 / 30.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var eco := Ecossistema.new(g, m, amb)
	return {"g": g, "m": m, "amb": amb, "eco": eco}


## Lugar com muitas árvores caducas perto.
func _bosque(eco: Ecossistema) -> Vector2:
	var melhor := Vector2.ZERO
	var n := -1
	for y in range(-150, 151, 25):
		for x in range(-150, 151, 25):
			var k := eco.arvores_perto(Vector2(x, y), 14.0).filter(func(a): return a.caduca).size()
			if k > n:
				n = k
				melhor = Vector2(x, y)
	return melhor


func _clima(estacao: int, estado := "limpo") -> Clima:
	var c := Clima.new(3)
	c.ciclo = false
	c.tempo_real = false
	c.estacao = estacao
	c.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * 0.5
	c.forcar(estado, true)
	c.restante = 1.0e9
	return c


func test_vico_do_capim() -> void:
	var c := _clima(0, "chuva")
	var v0 := c.vico
	for i in 30 * 120:
		c.tick(DT)
	verificar(c.vico > v0 + 0.25, "2 min de chuva deixam o capim viçoso (%.2f)" % c.vico)
	var depois := c.vico
	c.forcar("limpo", true)
	c.restante = 1.0e9
	for i in 30 * 60:
		c.tick(DT)
	verificar(c.vico < depois and c.vico > depois - 0.1, "sem chuva volta devagar (uns dias de jogo) (%.2f)" % c.vico)
	var verao := _clima(1)
	for i in 30 * 600:
		verao.tick(DT)
	verificar(verao.vico < -0.1, "verão seco puxa para amarelo (%.2f)" % verao.vico)
	var c2 := Clima.new(3)
	c2.restaurar(str_to_var(var_to_str(verao.estado())))
	perto(c2.vico, verao.vico, 1e-4, "vai no save")


func test_arvores_perto() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _bosque(eco)
	var arvs := eco.arvores_perto(c, 14.0)
	verificar(arvs.size() >= 5, "acha árvores (%d)" % arvs.size())
	verificar(arvs.any(func(a): return a.caduca), "algumas caducas")
	for a in arvs:
		verificar((a.pos as Vector2).distance_to(c) <= 15.0, "no raio")
		verificar(float(a.alto) > 1.0, "altura do modelo")
	var t: Vector2i = arvs[0].tile
	(w.m as MapaOcupacao).arvores[t] = {"e": "queimada"}
	verificar(not eco.arvores_perto(c, 14.0).any(func(a): return a.tile == t), "queimada sai da lista")


func test_galhos_depois_da_tempestade() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := _bosque(eco)
	var p := PlantasReagem.new(eco)
	var c := _clima(1, "tempestade")
	for i in 30 * 5:
		p.tick(DT, c, foco)
	verificar(p.tormenta > 0.9, "tempestade anotada")
	igual(p.galhos.size(), 0, "durante a tempestade ainda não")
	c.forcar("limpo", true)
	c.restante = 1.0e9
	for i in 30 * 5:
		p.tick(DT, c, foco)
	verificar(p.galhos.size() >= 6, "depois dela, galhos no chão (%d)" % p.galhos.size())
	for g in p.galhos:
		var tl := Vector2i((g.pos as Vector2).floor())
		igual((w.g as GeradorMundo).terreno(tl), GeradorMundo.Terreno.TERRA, "no chão de terra")
		verificar(eco.arvores_perto(g.pos, 3.5).size() > 0, "embaixo de árvore")
	var n := p.galhos.size()
	var c2 := _clima(1, "chuva")                          # chuva comum não quebra galho
	var p2 := PlantasReagem.new(eco)
	for i in 30 * 5:
		p2.tick(DT, c2, foco)
	c2.forcar("limpo", true)
	for i in 30 * 5:
		p2.tick(DT, c2, foco)
	igual(p2.galhos.size(), 0, "chuva comum não derruba galho")
	p.t += 1080.0 * 1.3 + 61.0
	p.tick(DT, c, foco)
	verificar(p.galhos.size() < n, "uns dias depois somem")


func test_cogumelos_com_chao_molhado() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := _bosque(eco)
	var p := PlantasReagem.new(eco)
	var c := _clima(0)
	c.molhado = 0.9
	for i in 30 * 30:
		p.tick(DT, c, foco)
		c.molhado = 0.9
	verificar(p.cogumelos.size() >= 4, "brotaram (%d)" % p.cogumelos.size())
	verificar(p.cogumelos.size() <= int(Registro.fauna.plantas_reagem.cogumelos.max), "no máximo o orçamento")
	var co: Dictionary = p.cogumelos[0]
	verificar(p.escala_cogumelo(co) < 1.0, "ainda crescendo")
	p.t = float(co.nasc) + 50.0
	perto(p.escala_cogumelo(co), 1.0, 1e-3, "cresceu")
	p.t = float(co.nasc) + float(co.vida) + 61.0
	perto(p.escala_cogumelo(co), 0.0, 1e-3, "murchou")
	var inv := PlantasReagem.new(eco)
	var ci := _clima(3)
	ci.molhado = 0.9
	for i in 30 * 30:
		inv.tick(DT, ci, foco)
		ci.molhado = 0.9
	igual(inv.cogumelos.size(), 0, "inverno: nenhum")
	var seco := PlantasReagem.new(eco)
	var cs := _clima(0)
	for i in 30 * 30:
		seco.tick(DT, cs, foco)
	igual(seco.cogumelos.size(), 0, "chão seco: nenhum")
	var p3 := PlantasReagem.new(eco)
	p3.restaurar(str_to_var(var_to_str(p.estado())))
	igual(p3.cogumelos.size(), p.cogumelos.size(), "vão no save")


func test_folhas_no_outono() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := _bosque(eco)
	eco.tick(DT, foco)
	var d := DesenhoPlantasReagem.new()
	d.eco = eco
	d.clima = _clima(2)
	d._ready()
	for i in 30 * 8:
		d._process(DT)
	verificar(d.folhas.size() >= 20, "outono: folhas caindo e no chão (%d)" % d.folhas.size())
	var no_chao := d.folhas.filter(func(f): return f.chao).size()
	verificar(no_chao > 0 and no_chao < d.folhas.size(), "umas caindo, outras no chão (%d)" % no_chao)
	for f in d.folhas:
		var p: Vector3 = f.pos
		var chao := Grade.altura_em(Vector2(p.x, -p.z))
		verificar(p.y >= chao + 0.18 and p.y < chao + 3.0, "entre o topo do capim e a copa")
	d.free()
	var pv := DesenhoPlantasReagem.new()
	pv.eco = eco
	pv.clima = _clima(0)
	pv._ready()
	pv._process(DT)
	igual(pv.folhas.size(), 0, "primavera: nenhuma")
	pv.free()


func test_malhas() -> void:
	var g := DesenhoPlantasReagem.malha_galho()
	var c := DesenhoPlantasReagem.malha_cogumelo()
	verificar(g.get_faces().size() > 30 and g.get_faces().size() < 600, "galho de poucos triângulos")
	verificar(c.get_faces().size() > 30 and c.get_faces().size() < 600, "cogumelo de poucos triângulos")
	var ab := c.get_aabb()
	verificar(ab.size.y > 0.12 and ab.size.y < 0.2, "cogumelo de ~15 cm, acima do capim (%.3f)" % ab.size.y)
	verificar(g.get_aabb().size.y < 0.06, "galho rente ao chão")
