extends Caso
## Patch fauna, fase 9 (docs/PLANO_FAUNA.md): herbívoros em manada (pastam, viajam, fogem, filhotes, migração),
## o predador nativo de matilha (covil, ronda, caça de herbívoro e de rato, briga com aranhas e larvas) e os peixes
## dos lagos (pulam; morrem e boiam na água suja; voltam na limpa).

const DT := 1.0 / 20.0


func _mundo() -> Dictionary:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	for x in range(-70, 71):
		for y in range(-40, 41):
			m.limpar_obstaculo(Vector2i(x, y))
	var amb := AmbienteVivo.new(m.gerador, m)
	var eco := Ecossistema.new(m.gerador, m, amb)
	var p := Poluicao.new(m.gerador)
	var c := Colonia.new(m, p, 3)
	eco.registrar_fonte("alien", func() -> Array:
		var out: Array = []
		for ar in c.aranhas.values():
			out.append({"id": ar.id, "pos": ar.pos, "especie": ar.get("especie", "aranha"), "espreita": ar.get("espreita", false)})
		return out)
	var r := Ratos.new(eco, amb, 5)
	r._t_toca = 1.0e9
	eco.registrar_fonte("rato", r.para_ecossistema)
	var car := Carcacas.new(eco, amb)
	var h := Manadas.new(eco, amb, 7)
	h._t_nasce = 1.0e9
	var pr := Predadores.new(eco, amb, 9)
	pr._t_nasce = 1.0e9
	pr.manadas = h
	pr.ratos = r
	pr.carcacas = car
	pr.colonia = c
	c.eco = eco
	c.ratos = r
	c.carcacas = car
	c.manadas = h
	c.fauna = pr
	eco.registrar_fonte("herbivoro", h.para_ecossistema)
	eco.registrar_fonte("predador", pr.para_ecossistema)
	var cl := Clima.new(1)
	cl.hora = 0.5
	cl.estacao = 1
	return {"m": m, "amb": amb, "eco": eco, "c": c, "r": r, "car": car, "h": h, "pr": pr, "cl": cl}


func _rodar(w: Dictionary, s: float, ate := Callable()) -> Array:
	var evs: Array = []
	for i in int(s / DT):
		(w.eco as Ecossistema).tick(DT, Vector2.ZERO)
		(w.h as Manadas).tick(DT, w.cl, Vector2.ZERO)
		(w.pr as Predadores).tick(DT, w.cl, Vector2.ZERO)
		(w.r as Ratos).tick(DT, w.cl, Vector2.ZERO)
		(w.c as Colonia).tick(DT, [])
		(w.car as Carcacas).tick(DT)
		evs.append_array((w.h as Manadas).eventos)
		evs.append_array((w.pr as Predadores).eventos)
		evs.append_array((w.c as Colonia).eventos)
		if ate.is_valid() and bool(ate.call()):
			break
	return evs


func _da_manada(h: Manadas, id: int) -> Array:
	return h.bichos.values().filter(func(b): return int(b.manada) == id)


# ------------------------------------------------------------------ manadas
func test_manada_nasce_em_pasto_bom() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	verificar(h.bom_pasto(Vector2(10.5, 5.5)), "campo aberto e vivo é pasto")
	(w.m as MapaOcupacao).colocar("fornalha", Vector2i(12, 5), 0)
	verificar(not h.bom_pasto(Vector2(10.5, 5.5)), "perto da fábrica não é")
	var w2 := _mundo()
	var h2: Manadas = w2.h
	h2._t_nasce = 0.0
	h2.tick(DT, w2.cl, Vector2.ZERO)
	igual(h2.manadas.size(), 1, "nasceu uma manada")
	var m: Dictionary = h2.manadas.values()[0]
	var d: float = (m.centro as Vector2).length()
	verificar(d >= 40.0 and d <= 90.0, "longe da câmera (%.0f m): entra andando" % d)
	var n := _da_manada(h2, int(m.id)).size()
	verificar(n >= 4 and n <= 10, "de 4 a 8 adultos e filhotes (%d)" % n)


func test_pasta_espalhada_e_viaja_junta() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var id := h.nova_manada(Vector2(0, 0), "galhudo", false)
	_rodar(w, 20.0)
	var bs := _da_manada(h, id)
	verificar(bs.any(func(b): return int(b.estado) == Manadas.E.PASTANDO), "pastando")
	verificar(bs.all(func(b): return (b.pos as Vector2).distance_to(h.manadas[id].centro) < 7.0), "espalhados perto do centro")
	h.manadas[id].t = 0.0
	_rodar(w, 0.2)
	igual(int(h.manadas[id].estado), Manadas.M.VIAGEM, "acabou o pasto: viaja")
	var alvo: Vector2 = h.manadas[id].alvo
	verificar(alvo.distance_to(Vector2.ZERO) > 10.0, "para outro pasto (%.0f m)" % alvo.length())
	_rodar(w, 60.0, func(): return int(h.manadas[id].estado) == Manadas.M.PASTO)
	igual(int(h.manadas[id].estado), Manadas.M.PASTO, "chegou e voltou a pastar")
	verificar(_da_manada(h, id).all(func(b): return (b.pos as Vector2).distance_to(h.manadas[id].centro) < 9.0), "chegaram todos juntos")


func test_nao_se_atravessam_nem_entram_em_construcao() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var m: MapaOcupacao = w.m
	m.colocar("fornalha", Vector2i(6, -1), 0)
	var id := h.nova_manada(Vector2(0, 0), "galhudo", true)
	h.manadas[id].estado = Manadas.M.VIAGEM
	h.manadas[id].alvo = Vector2(16, 0)
	var dentro := false
	var colados := 9.0
	for i in int(25.0 / DT):
		(w.eco as Ecossistema).tick(DT, Vector2.ZERO)
		h.tick(DT, w.cl, Vector2.ZERO)
		var bs := _da_manada(h, id)
		for a in bs:
			dentro = dentro or m.tiles.has(Vector2i((a.pos as Vector2).floor()))
			for b in bs:
				if int(a.id) < int(b.id) and not (bool(a.filhote) or bool(b.filhote)):
					colados = minf(colados, (a.pos as Vector2).distance_to(b.pos))
	verificar(not dentro, "nenhum pisou na máquina")
	verificar(colados > 0.9, "adultos nunca colados um no outro (mín %.2f m)" % colados)


func test_foge_de_aranha_e_de_fogo() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var c: Colonia = w.c
	var id := h.nova_manada(Vector2(0, 0), "galhudo", false)
	var ni := c._criar_ninho(Vector2i(30, 30), 1.0, "aranha")
	var a := c._nova_aranha(ni)
	c.aranhas[a].pos = Vector2(14, 0)
	c.aranhas[a].estado = Colonia.E.PARADA
	var evs := _rodar(w, 1.0)
	igual(int(h.manadas[id].estado), Manadas.M.FUGA, "viu a aranha: a manada dispara")
	verificar(evs.any(func(e): return e.tipo == "alarme"), "deu o alarme (som)")
	verificar(_da_manada(h, id).all(func(b): return int(b.estado) == Manadas.E.CORRENDO), "todos correm")
	_rodar(w, 4.0)
	var c0: Vector2 = h.manadas[id].centro
	verificar(c0.distance_to(Vector2(14, 0)) > 25.0, "fugiu para o lado oposto (%.0f m da aranha)" % c0.distance_to(Vector2(14, 0)))
	# fogo
	var w2 := _mundo()
	var h2: Manadas = w2.h
	var id2 := h2.nova_manada(Vector2(0, 0), "galhudo", false)
	(w2.amb as AmbienteVivo).fogo[Vector2i(-12, 0)] = 30.0
	_rodar(w2, 1.0)
	igual(int(h2.manadas[id2].estado), Manadas.M.FUGA, "fogo perto: foge")
	# susto (tiro)
	var w3 := _mundo()
	var h3: Manadas = w3.h
	var id3 := h3.nova_manada(Vector2(0, 0), "galhudo", false)
	h3.assustar(Vector2(20, 0), 30.0)
	_rodar(w3, 0.1)
	igual(int(h3.manadas[id3].estado), Manadas.M.FUGA, "tiro perto: foge")


func test_filhotes_na_primavera_perto_da_mae() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var cl: Clima = w.cl
	cl.estacao = 0
	h._d = h._d.duplicate(true)
	h._d.filhote_s = 10.0
	var id := h.nova_manada(Vector2(0, 0), "galhudo", false)
	h.manadas[id].t = 1.0e9                              # fica pastando
	var n0 := _da_manada(h, id).size()
	h._t_nasce = 0.0
	var evs := _rodar(w, 12.0)
	verificar(evs.any(func(e): return e.tipo == "nasceu"), "nasceu filhote")
	var f: Array = _da_manada(h, id).filter(func(b): return bool(b.filhote))
	verificar(not f.is_empty(), "o filhote está na manada (%d → %d)" % [n0, _da_manada(h, id).size()])
	if not f.is_empty():
		var mae: Dictionary = h.bichos.get(int(f[0].mae), {})
		verificar(not mae.is_empty() and (f[0].pos as Vector2).distance_to(mae.pos) < 4.0, "colado na mãe")
		verificar(float(f[0].escala) < 0.8, "menor que o adulto (%.2f)" % float(f[0].escala))
	cl.estacao = 2
	h._d.filhote_s = 1.0
	var n1 := _da_manada(h, id).size()
	_rodar(w, 12.0)
	igual(_da_manada(h, id).size(), n1, "no outono não nasce")


func test_migra_no_outono() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var cl: Clima = w.cl
	h._d = h._d.duplicate(true)
	h._d.migra_chance = 1.0
	var id := h.nova_manada(Vector2(0, 0), "galhudo", false)
	h.tick(DT, cl, Vector2.ZERO)
	cl.estacao = 2
	var evs := _rodar(w, 0.2)
	verificar(evs.any(func(e): return e.tipo == "partiu"), "na troca para o outono a manada parte")
	igual(int(h.manadas[id].estado), Manadas.M.MIGRA, "migrando")
	var rumo := ((h.manadas[id].alvo as Vector2) - Vector2.ZERO).normalized()
	verificar(rumo.dot(Passaros.rumo_migracao(2, false)) > 0.9, "no rumo da migração dos pássaros")


# ------------------------------------------------------------------ predador
func test_matilha_dorme_de_dia_e_ronda_no_crepusculo() -> void:
	var w := _mundo()
	var pr: Predadores = w.pr
	var cl: Clima = w.cl
	var id := pr.nova_matilha(Vector2(-10, 0), "uivador", 3)
	pr.matilhas[id].t = 0.0
	_rodar(w, 3.0)
	igual(int(pr.matilhas[id].estado), Predadores.P.COVIL, "meio-dia: no covil")
	verificar(pr.bichos.values().all(func(b): return int(b.estado) == Predadores.E.DEITADO), "deitados")
	cl.hora = 0.77
	_rodar(w, 1.0)
	igual(int(pr.matilhas[id].estado), Predadores.P.RONDA, "entardecer: sai para rondar")
	_rodar(w, 8.0)
	verificar(pr.bichos.values().all(func(b): return (b.pos as Vector2).distance_to(Vector2(-10, 0)) > 1.0 or int(b.estado) == Predadores.E.ANDANDO), "andando")
	var lider: Dictionary = pr._lider(pr.matilhas[id])
	verificar(pr.bichos.values().all(func(b): return (b.pos as Vector2).distance_to(lider.pos) < 8.0), "andam juntos atrás do líder")


func test_matilha_caca_herbivoro() -> void:
	var w := _mundo()
	var pr: Predadores = w.pr
	var h: Manadas = w.h
	var eco: Ecossistema = w.eco
	var cl: Clima = w.cl
	cl.hora = 0.77
	var mid := h.nova_manada(Vector2(30, 0), "galhudo", false)
	h.manadas[mid].t = 1.0e9
	var id := pr.nova_matilha(Vector2(-10, 0), "uivador", 3)
	pr.matilhas[id].estado = Predadores.P.RONDA
	pr.matilhas[id].fome = 1.0
	pr.matilhas[id].alvo = Vector2(-10, 0)
	var viu := {"espreita": false, "correu": false}      # (a função vê o dicionário; uma variável seria cópia)
	var evs := _rodar(w, 60.0, func():
		for b in pr.bichos.values():
			viu.espreita = viu.espreita or int(b.estado) == Predadores.E.ESPREITANDO
			viu.correu = viu.correu or int(b.estado) == Predadores.E.CORRENDO
		return int(pr.matilhas[id].estado) == Predadores.P.COMER)
	verificar(viu.espreita, "chegaram espreitando")
	verificar(viu.correu, "deram o bote correndo")
	verificar(evs.any(func(e): return e.tipo == "pegou" and e.presa == "herbivoro"), "pegaram um herbívoro")
	igual(int(pr.matilhas[id].estado), Predadores.P.COMER, "comem juntos")
	verificar(evs.any(func(e): return e.tipo == "alarme"), "a manada deu o alarme")
	_rodar(w, 0.5)
	var carc := eco.comida.values().filter(func(f): return f.tipo == "carcaca" and String(f.especie) == "herbivoro")
	igual(carc.size(), 1, "o morto virou carcaça grande")
	var idade0 := float(carc[0].idade) if not carc.is_empty() else 0.0
	_rodar(w, 50.0, func(): return int(pr.matilhas[id].estado) != Predadores.P.COMER)
	igual(float(pr.matilhas[id].fome), 0.0, "comeram: sem fome")
	verificar(carc.is_empty() or float(carc[0].idade) > idade0 + 600.0, "a carne foi comida (a carcaça foi para perto dos ossos)")
	igual(int(pr.matilhas[id].estado), Predadores.P.VOLTA, "voltam ao covil")


func test_sozinho_caca_rato() -> void:
	var w := _mundo()
	var pr: Predadores = w.pr
	var r: Ratos = w.r
	var cl: Clima = w.cl
	cl.hora = 0.77
	var t := r.nova_toca(Vector2(20, 10), "pardo")
	var rt: Dictionary = r.ratos.values().filter(func(x): return int(x.toca) == t)[0]
	rt.estado = Ratos.E.FAREJANDO
	rt.pos = Vector2(6, 0)
	rt.t = 1.0e6
	var id := pr.nova_matilha(Vector2(-6, 0), "uivador", 1)
	pr.matilhas[id].estado = Predadores.P.RONDA
	pr.matilhas[id].fome = 1.0
	var evs := _rodar(w, 20.0, func(): return not r.ratos.has(int(rt.id)))
	verificar(evs.any(func(e): return e.tipo == "pegou" and e.presa == "rato") or not r.ratos.has(int(rt.id)), "um sozinho caça rato")


func test_briga_com_aranhas() -> void:
	var w := _mundo()
	var pr: Predadores = w.pr
	var c: Colonia = w.c
	verificar(Colonia.hostil_em("uivador", "aranha") and Colonia.hostil_em("aranha", "uivador") and Colonia.hostil_em("larva", "uivador"), "uivador × aranha e larva = hostis")
	var ni := c._criar_ninho(Vector2i(30, 30), 1.0, "aranha")
	var a := c._nova_aranha(ni)
	c.aranhas[a].pos = Vector2(8, 0)
	c.aranhas[a].estado = Colonia.E.PARADA
	var vida_a := float(c.aranhas[a].vida)
	var id := pr.nova_matilha(Vector2(-2, 0), "uivador", 3)
	var vida_p := 0.0
	for b in pr.bichos.values():
		vida_p += float(b.vida)
	var evs := _rodar(w, 1.0)
	igual(int(pr.matilhas[id].estado), Predadores.P.BRIGA, "viram a aranha: atacam (são mais)")
	verificar(evs.any(func(e): return e.tipo == "briga"), "evento de briga (rosnado)")
	_rodar(w, 3.0)
	verificar(not c.aranhas.has(a) or float(c.aranhas[a].vida) < vida_a, "morderam a aranha")
	var depois := 0.0
	for b in pr.bichos.values():
		depois += float(b.vida)
	verificar(depois < vida_p or not c.aranhas.has(a), "a aranha mordeu de volta (ou morreu antes)")
	evs = _rodar(w, 30.0, func(): return not c.aranhas.has(a))
	verificar(not c.aranhas.has(a), "a matilha matou a aranha")
	var morte: Array = evs.filter(func(e): return e.tipo == "aranha_morta")
	verificar(morte.is_empty() or String(morte[0].get("por", "")) == "uivador", "morta pelo uivador")
	# muitas: fogem
	var w2 := _mundo()
	var pr2: Predadores = w2.pr
	var c2: Colonia = w2.c
	var n2 := c2._criar_ninho(Vector2i(30, 30), 1.0, "aranha")
	for k in 5:
		var a2 := c2._nova_aranha(n2)
		c2.aranhas[a2].pos = Vector2(9, k - 2.0)
		c2.aranhas[a2].estado = Colonia.E.PARADA
	var id2 := pr2.nova_matilha(Vector2(-2, 0), "uivador", 2)
	_rodar(w2, 1.0)
	igual(int(pr2.matilhas[id2].estado), Predadores.P.FUGA, "aranhas demais: a matilha foge")


func test_a_aranha_briga_com_o_predador() -> void:
	var w := _mundo()
	var pr: Predadores = w.pr
	var c: Colonia = w.c
	var ni := c._criar_ninho(Vector2i(30, 30), 1.0, "aranha")
	var a := c._nova_aranha(ni)
	c.aranhas[a].pos = Vector2(5, 0)
	c.aranhas[a].estado = Colonia.E.PARADA
	var id := pr.nova_matilha(Vector2(0, 0), "uivador", 1)
	pr.matilhas[id].estado = Predadores.P.FUGA             # não vai brigar: só a aranha
	pr.matilhas[id].t = 1.0e9
	pr.matilhas[id].alvo = Vector2(0, 0)
	c.tick(0.6, [])
	(w.eco as Ecossistema).tick(DT, Vector2.ZERO)
	c._t_guerra = 0.0
	c.tick(DT, [])
	igual(int(c.aranhas[a].estado), Colonia.E.BRIGANDO, "a aranha viu o uivador e foi brigar")
	verificar(int(c.aranhas[a].get("inimigo_fauna", -1)) >= 0, "o inimigo é o predador")


func test_medo_do_predador() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var pr: Predadores = w.pr
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	var pid := pr.nova_matilha(Vector2(18, 0), "uivador", 1)
	var b: Dictionary = pr.bichos.values()[0]
	b.estado = Predadores.E.ANDANDO
	eco.reindexar()
	verificar(h.ameaca_em(Vector2.ZERO) != null, "andando a 18 m, a manada vê")
	b.estado = Predadores.E.ESPREITANDO
	eco.reindexar()
	verificar(h.ameaca_em(Vector2.ZERO) == null, "espreitando a 18 m, não vê")
	b.pos = Vector2(6, 0)
	eco.reindexar()
	verificar(h.ameaca_em(Vector2.ZERO) != null, "espreitando a 6 m, vê")
	b.estado = Predadores.E.ANDANDO
	eco.reindexar()
	verificar(r._perigo(Vector2(0, 0)) != null, "o rato tem medo do predador")
	var g: GeradorMundo = (w.m as MapaOcupacao).gerador
	var ps := Passaros.new(g, w.m, w.amb, w.c)
	ps.eco = eco
	verificar(ps._ameaca_em(Vector2(0, 0)) != null, "o pássaro no chão também")
	igual(pid > 0, true, "matilha criada")


# ------------------------------------------------------------------ peixes
func _lago(g: GeradorMundo) -> Dictionary:
	for lg in g.hidro.lagos(Vector2i(-400, -400), Vector2i(400, 400)):
		if float(lg.raio) >= 7.0:
			return lg
	return {}


func test_peixes_pulam_e_morrem_na_agua_suja() -> void:
	var w := _mundo()
	var g: GeradorMundo = (w.m as MapaOcupacao).gerador
	var lg := _lago(g)
	verificar(not lg.is_empty(), "achou um lago no mundo de teste")
	if lg.is_empty():
		return
	var pe := Peixes.new(w.eco, w.amb, 3)
	pe._d = pe._d.duplicate(true)
	pe._d.pulos_por_min = 120.0
	var foco: Vector2 = lg.centro
	var pulos := 0
	var alto := 0.0
	for i in int(20.0 / DT):
		pe.tick(DT, null, foco)
		for e in pe.eventos:
			if e.tipo == "pulo":
				pulos += 1
		for p in pe.pulos:
			alto = maxf(alto, float(Peixes.no_ar(p)[1]))
	var k := Peixes.chave(lg.centro)
	verificar(pe.lagos.has(k), "o lago tem peixes")
	verificar(not (pe.lagos[k].pontos as Array).is_empty(), "achou água funda para pular")
	verificar(pulos >= 3, "pularam (%d)" % pulos)
	verificar(alto > 0.2 and alto < 0.8, "pulo de até uns palmos (%.2f m)" % alto)
	for q: Vector2 in pe.lagos[k].pontos:
		verificar(g.terreno(Vector2i(q.floor())) in [GeradorMundo.Terreno.LAGO, GeradorMundo.Terreno.LAGOA], "ponto dentro do lago")
		break
	# água suja: morrem e boiam (viram carcaça na água)
	var amb: AmbienteVivo = w.amb
	for q: Vector2 in pe.lagos[k].pontos:
		amb.somar(Vector2i(q.floor()), AmbienteVivo.AGUA, 0.8)
	pe._d.boia_s = 2.0
	pe.lagos[k].t_morto = 0.0
	var car: Carcacas = w.car
	var eco: Ecossistema = w.eco
	var boiou := 0
	for i in int(20.0 / DT):
		pe.tick(DT, null, foco)
		eco.tick(DT, foco)
		car.tick(DT)
		for e in pe.eventos:
			if e.tipo == "boiou":
				boiou += 1
	verificar(boiou >= 2, "peixes mortos boiando (%d)" % boiou)
	verificar(float(pe.lagos[k].pop) < 1.0, "a população caiu (%.2f)" % float(pe.lagos[k].pop))
	var mortos := eco.comida.values().filter(func(f): return f.tipo == "carcaca" and String(f.especie) == "peixe")
	verificar(not mortos.is_empty(), "o peixe morto é carcaça (com mosca)")
	# limpa: volta
	for q: Vector2 in pe.lagos[k].pontos:
		amb.somar(Vector2i(q.floor()), AmbienteVivo.AGUA, -1.0)
	var p0 := float(pe.lagos[k].pop)
	pe._d.volta_s = 30.0
	for i in int(10.0 / DT):
		pe.tick(DT, null, foco)
	verificar(float(pe.lagos[k].pop) > p0, "água limpa: os peixes voltam (%.2f → %.2f)" % [p0, float(pe.lagos[k].pop)])


# ------------------------------------------------------------------ enxames
func _vida_em(eco: Ecossistema, foco: Vector2, est: int, molhado: float, chuva := 0.0) -> DesenhoVidaPequena:
	var cl := Clima.new(1)
	cl.hora = 0.5
	cl.estacao = est
	cl.molhado = molhado
	cl.valores.chuva = chuva
	cl.valores.vento = 0.0
	eco.tick(DT, foco)
	var v := DesenhoVidaPequena.new()
	v.eco = eco
	v.clima = cl
	v._ready()
	for i in 6:
		v._process(DT)
	return v


func test_enxames_no_verao_umido_na_beira_dagua() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var g: GeradorMundo = (w.m as MapaOcupacao).gerador
	var lg := _lago(g)
	if lg.is_empty():
		verificar(false, "sem lago no mundo de teste")
		return
	var foco: Vector2 = (lg.centro as Vector2) + Vector2(float(lg.raio) + 3.0, 0.0)
	var v := _vida_em(eco, foco, 1, 1.0)
	verificar(float(v.fatores.enxame) > 0.2, "verão depois da chuva: enxame (%.2f)" % float(v.fatores.enxame))
	var nuvem: Array = v.insetos.filter(func(i): return i.has("enxame"))
	verificar(nuvem.size() >= 40, "uma nuvem de mosquitos (%d)" % nuvem.size())
	var perto_agua := 0
	for i in nuvem:
		var p: Vector3 = i.pos
		if eco.perto_da_agua(Vector2i(Vector2(p.x, -p.z).floor()), 4):
			perto_agua += 1
	verificar(perto_agua >= nuvem.size() * 0.6, "quase todos na beira d'água (%d de %d)" % [perto_agua, nuvem.size()])
	v.free()
	var seco := _vida_em(eco, foco, 1, 0.0)
	verificar(seco.insetos.filter(func(i): return i.has("enxame")).is_empty(), "verão seco: sem enxame")
	seco.free()
	var inv := _vida_em(eco, foco, 3, 1.0)
	verificar(inv.insetos.filter(func(i): return i.has("enxame")).is_empty(), "inverno: sem enxame")
	inv.free()
	var ch := _vida_em(eco, foco, 1, 1.0, 1.0)
	verificar(ch.insetos.filter(func(i): return i.has("enxame")).is_empty(), "chovendo: sem enxame")
	ch.free()


# ------------------------------------------------------------------ save
func test_salva_a_fauna_grande() -> void:
	var w := _mundo()
	var h: Manadas = w.h
	var pr: Predadores = w.pr
	h.nova_manada(Vector2(0, 0), "galhudo", true)
	pr.nova_matilha(Vector2(-10, 0), "uivador", 3)
	_rodar(w, 2.0)
	var dh: Dictionary = str_to_var(var_to_str(h.estado()))
	var dp: Dictionary = str_to_var(var_to_str(pr.estado()))
	var w2 := _mundo()
	var h2: Manadas = w2.h
	var pr2: Predadores = w2.pr
	h2.restaurar(dh)
	pr2.restaurar(dp)
	igual(h2.bichos.size(), h.bichos.size(), "herbívoros voltaram do save")
	igual(pr2.bichos.size(), pr.bichos.size(), "predadores voltaram do save")
	var b0: Dictionary = h.bichos.values()[0]
	verificar((h2.bichos[int(b0.id)].pos as Vector2).distance_to(b0.pos) < 0.01, "no mesmo lugar")
	_rodar(w2, 2.0)
	verificar(h2.bichos.size() >= h.bichos.size() - 1, "e seguem vivendo")
