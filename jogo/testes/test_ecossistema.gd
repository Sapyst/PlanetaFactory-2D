extends Caso
## Patch fauna, fases 0 e 1 (docs/PLANO_FAUNA.md): a fundação (Ecossistema: índice de quem vive perto, eventos,
## comida, saúde do chão, orçamento) e a vida pequena (vagalumes à noite, insetos de dia, olhos no mato, silêncio
## perto de ninho).

const DT := 1.0 / 30.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	var eco := Ecossistema.new(g, m, amb)
	return {"g": g, "m": m, "amb": amb, "col": col, "eco": eco}


## Campo de capim saudável (terra, longe de água funda), para a vida pequena.
func _campo(w: Dictionary) -> Vector2:
	var eco: Ecossistema = w.eco
	var melhor := Vector2.ZERO
	var nota := -1.0
	for y in range(-120, 121, 10):
		for x in range(-120, 121, 10):
			var s := 0.0
			for j in range(-12, 13, 6):
				for i in range(-12, 13, 6):
					s += eco.saude(Vector2i(x + i, y + j))
			if s > nota:
				nota = s
				melhor = Vector2(x, y)
	return melhor


func _clima(hora: float, estacao := 1, chuva := 0.0) -> Clima:
	var c := Clima.new(3)
	c.ciclo = false
	c.tempo_real = false
	c.estacao = estacao
	c.hora = hora
	c.valores = {"nuvens": 0.0, "neblina": 0.0, "chuva": chuva, "luz": 1.0, "vento": 0.0}
	return c


func _vida(eco: Ecossistema, clima: Clima) -> DesenhoVidaPequena:
	var v := DesenhoVidaPequena.new()
	v.eco = eco
	v.clima = clima
	v._ready()
	for i in 6:
		v._process(DT)
	return v


func test_indice_e_perto() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var bichos := [{"id": 1, "pos": Vector2(0, 0), "especie": "a"}, {"id": 2, "pos": Vector2(5, 0), "especie": "a"},
			{"id": 3, "pos": Vector2(60, 60), "especie": "b"}]
	eco.registrar_fonte("rato", func() -> Array: return bichos)
	eco.registrar_fonte("toca", func() -> Array: return [{"id": 9, "pos": Vector2(3, 3)}])
	eco.tick(DT, Vector2.ZERO)
	igual(int(eco.contagem.rato), 3, "contou os ratos")
	igual(eco.perto(Vector2(1, 0), 6.0, "rato").size(), 2, "dois ratos perto")
	igual(eco.perto(Vector2(1, 0), 6.0).size(), 3, "com a toca, três coisas perto")
	perto(eco.distancia(Vector2(0, 0), "toca", 10.0), Vector2(3, 3).length(), 0.01, "distância até a toca")
	verificar(eco.distancia(Vector2(0, 0), "toca", 2.0) == INF, "fora do raio = INF")
	bichos.append({"id": 4, "pos": Vector2(1, 1)})
	eco.tick(0.6, Vector2.ZERO)                          # o índice se refaz sozinho a cada indice_s
	igual(eco.perto(Vector2(1, 0), 6.0, "rato").size(), 3, "o índice pegou o novo")
	igual(eco.detalhe(Vector2(10, 0)), 2, "perto da câmera: completo")
	igual(eco.detalhe(Vector2(60, 0)), 1, "meio")
	igual(eco.detalhe(Vector2(200, 0)), 0, "longe: só contagem")


func test_eventos_e_comida() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	eco.morreu("alien", "larva", Vector2(4, 4))
	verificar(eco.eventos.is_empty(), "o aviso vale do próximo tick")
	eco.tick(DT, Vector2.ZERO)
	igual(eco.eventos.size(), 1, "morreu")
	igual(eco.eventos[0].quem, "alien", "quem")
	igual(eco.eventos[0].especie, "larva", "espécie")
	eco.tick(DT, Vector2.ZERO)
	verificar(eco.eventos.is_empty(), "e some no passo seguinte")
	var f := eco.por_comida("fruta", Vector2(2, 2))
	igual(eco.comida_perto(Vector2.ZERO, 5.0, "fruta").size(), 1, "fruta no chão")
	verificar(eco.comer(f, "rato"), "comeu")
	verificar(not eco.comer(f, "rato"), "não come duas vezes")
	eco.tick(DT, Vector2.ZERO)
	igual(eco.eventos[0].tipo, "comeu", "aviso de comer")
	eco.por_comida("semente", Vector2(1, 1))
	var e2 := Ecossistema.new(w.g, w.m)
	e2.restaurar(str_to_var(var_to_str(eco.estado())))
	igual(e2.comida.size(), 1, "comida vai no save")


func test_saude_e_passaros_usam_a_mesma() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var p := Passaros.new(w.g, w.m, w.amb, w.col)
	p.eco = eco
	var c := _campo(w)
	var t := Vector2i(c)
	perto(p.saude(t), eco.saude(t), 1e-6, "pássaros e ecossistema veem a mesma saúde")
	var antes := eco.saude(t)
	for j in range(-3, 4):
		for i in range(-3, 4):
			(w.amb as AmbienteVivo).somar(t + Vector2i(i, j), AmbienteVivo.QUEIM, 1.0)
	verificar(eco.saude(t) < antes * 0.3, "queimado: saúde cai (%.2f → %.2f)" % [antes, eco.saude(t)])
	verificar(eco.perto_da_agua(t, 0) == (w.g as GeradorMundo).eh_agua((w.g as GeradorMundo).terreno(t)), "água no próprio tile")


func test_vagalumes_a_noite_no_capim() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _campo(w)
	eco.tick(DT, c)
	var v := _vida(eco, _clima(0.02))
	verificar(v.fatores.vagalumes > 0.9, "noite de verão: vagalumes (%.2f)" % v.fatores.vagalumes)
	verificar(v.vagalumes.size() >= 10, "um bom tanto perto (%d)" % v.vagalumes.size())
	verificar(v.vagalumes.size() <= int(Registro.fauna.vida_pequena.vagalumes.max), "dentro do orçamento")
	verificar(v.insetos.is_empty(), "sem mosquito de noite")
	var acesos := 0
	for g in v.vagalumes:
		var p: Vector3 = g.pos
		var chao := Grade.altura_em(Vector2(p.x, -p.z))
		verificar(p.y > chao + 0.1 and p.y < chao + 2.2, "voa baixo sobre o capim")
		verificar(Vector2(p.x, -p.z).distance_to(c) < 40.0, "perto da câmera")
		if float(g.brilho) > 0.5:
			acesos += 1
	verificar(acesos < v.vagalumes.size(), "piscam: nem todos acesos ao mesmo tempo")
	var p0: Vector3 = v.vagalumes[0].pos
	for i in 15:
		v._process(DT)
	verificar((v.vagalumes[0].pos as Vector3).distance_to(p0) > 0.01, "voam")
	verificar(v._mm_brilho.multimesh.visible_instance_count > 0, "desenhados num MultiMesh")
	v.free()


func test_insetos_de_dia_e_estacoes() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _campo(w)
	eco.tick(DT, c)
	var v := _vida(eco, _clima(0.5))
	verificar(v.vagalumes.is_empty(), "sem vagalume ao meio-dia")
	verificar(v.insetos.size() >= 6, "mosquitos de dia (%d)" % v.insetos.size())
	v.free()
	var inv := _vida(eco, _clima(0.02, 3))
	verificar(inv.vagalumes.is_empty(), "inverno: nenhum vagalume")
	inv.free()
	var ch := _vida(eco, _clima(0.5, 1, 1.0))
	verificar(ch.insetos.is_empty(), "chuva forte: nenhum mosquito")
	ch.free()


func test_silencio_perto_do_ninho() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _campo(w)
	eco.registrar_fonte("toca", func() -> Array: return [{"id": 1, "pos": c, "especie": "aranha"}])
	eco.tick(DT, c)
	var v := _vida(eco, _clima(0.02))
	verificar(v.fatores.silencio > 0.9, "em cima do ninho: silêncio (%.2f)" % v.fatores.silencio)
	for g in v.vagalumes:
		var p: Vector3 = g.pos
		verificar(Vector2(p.x, -p.z).distance_to(c) > 11.0, "nenhum vagalume perto do ninho")
	v.free()


func test_olhos_no_mato_raros() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _campo(w)
	eco.tick(DT, c)
	var v := _vida(eco, _clima(0.02))
	var vistos := 0
	var max_pares := 0
	for i in 30 * 40:                                    # 40 s de noite
		v._process(DT)
		var n := 0
		for o in v.olhos:
			if float(o.brilho) > 0.0:
				n += 1
				verificar(absf((o.a as Vector3).distance_to(o.b) - 0.08) < 0.01, "par de olhos, 8 cm")
		max_pares = maxi(max_pares, n)
		if n > 0:
			vistos += 1
	verificar(vistos > 0, "algum par de olhos apareceu no mato")
	verificar(vistos < 30 * 40, "e não ficam o tempo todo")
	verificar(max_pares <= int(Registro.fauna.vida_pequena.olhos.max_pares), "no máximo %d pares" % max_pares)
	v.free()
