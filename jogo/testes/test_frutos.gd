extends Caso
## Patch fauna, fase 3 (docs/PLANO_FAUNA.md): frutos que caem e viram comida (e apodrecem), pássaros que comem e levam
## a semente da árvore, sementes no vento que viram mudas na troca de estação, mudas que crescem pela estação.

const DT := 1.0 / 30.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var eco := Ecossistema.new(g, m, amb)
	return {"g": g, "m": m, "amb": amb, "eco": eco}


func _clima(estacao: int, estado := "limpo", frac := 0.5) -> Clima:
	var c := Clima.new(3)
	c.ciclo = false
	c.tempo_real = false
	c.estacao = estacao
	c.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * frac
	c.forcar(estado, true)
	c.restante = 1.0e9
	return c


## Lugar com mais plantas de um tipo de fruto perto (bolota, pinha, baga).
func _lugar(eco: Ecossistema, fruto: String) -> Vector2:
	var melhor := Vector2.ZERO
	var n := -1
	for y in range(-160, 161, 40):
		for x in range(-160, 161, 40):
			var lista := eco.arbustos_perto(Vector2(x, y), 20.0) if fruto == "baga" else eco.arvores_perto(Vector2(x, y), 20.0)
			var k := lista.filter(func(a): return Frutos.fruto_de(String(a.nome)) == fruto).size()
			if k > n:
				n = k
				melhor = Vector2(x, y)
	return melhor


func _frutas(eco: Ecossistema, especie := "") -> Array:
	return eco.comida.values().filter(func(f): return f.tipo == "fruta" and (especie == "" or f.especie == especie))


func test_especie_e_fruto_pelo_nome() -> void:
	igual(Ecossistema.especie_arvore("arv_carvalho_3"), "arv_carvalho", "carvalho")
	igual(Ecossistema.especie_arvore("arv_fungo_cristal_6"), "arv_fungo_cristal", "nome com _ no meio")
	igual(Ecossistema.especie_arvore("arbusto"), "arbusto", "sem número fica igual")
	igual(Frutos.fruto_de("arv_carvalho_1"), "bolota", "carvalho dá bolota")
	igual(Frutos.fruto_de("arv_pinheiro_4"), "pinha", "pinheiro dá pinha")
	igual(Frutos.fruto_de("arbusto"), "baga", "arbusto dá baga")
	igual(Frutos.fruto_de("arv_betula_2"), "", "bétula não dá fruto de comer")
	igual(Ecossistema.perfil_folha("arvore_campina_a"), -1, "a campina não muda de copa (não solta folha)")
	igual(Ecossistema.perfil_folha("arv_acacia_2"), 3, "acácia tem perfil próprio")


func test_arbustos_perto() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c := _lugar(eco, "baga")
	var arb := eco.arbustos_perto(c, 20.0)
	verificar(arb.size() >= 1, "acha arbustos (%d)" % arb.size())
	for a in arb:
		verificar(String(a.nome).begins_with("arbusto"), "só arbusto (%s)" % a.nome)
	for a in eco.arvores_perto(c, 20.0):
		verificar(not String(a.nome).begins_with("arbusto"), "árvore não traz arbusto")
	# raios diferentes não se atrapalham (cada um tem a sua busca guardada)
	var n20 := eco.arvores_perto(c, 20.0).size()
	var n8 := eco.arvores_perto(c, 8.0).size()
	verificar(n8 <= n20, "raio menor, menos árvores")
	igual(eco.arvores_perto(c, 20.0).size(), n20, "a busca do raio 20 continua certa")


func test_bolotas_no_outono() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := _lugar(eco, "bolota")
	var f := Frutos.new(eco, w.amb, 5)
	var cl := _clima(2)
	for i in 30 * 90:
		eco.tick(DT, foco)
		f.tick(DT, cl, foco)
	var bolotas := _frutas(eco, "bolota")
	verificar(bolotas.size() >= 8, "no outono caem bolotas (%d)" % bolotas.size())
	var oaks := eco.arvores_perto(foco, 30.0).filter(func(a): return Frutos.fruto_de(String(a.nome)) == "bolota")
	for b in bolotas:
		var embaixo := oaks.any(func(a): return (a.pos as Vector2).distance_to(b.pos) <= float(a.copa) * 1.05 + 0.31)
		verificar(embaixo, "bolota embaixo de um carvalho (%s)" % str(b.pos))
		verificar(b.fonte == "arv_carvalho", "sabe de que árvore veio")
		verificar(float(b.vida) > 0.0, "tem vida (apodrece)")
		var tl := Vector2i((b.pos as Vector2).floor())
		verificar(w.g.terreno(tl) == GeradorMundo.Terreno.TERRA and not w.m.tiles.has(tl), "no chão de terra livre")
	verificar(_frutas(eco).size() <= int(Registro.fauna.frutos.cair.max), "não passa do máximo perto da câmera")
	# embaixo do mesmo carvalho não junta montanha
	for a in oaks:
		var n := eco.comida_perto(a.pos, float(a.copa) + 0.8, "fruta").size()
		verificar(n <= int(Registro.fauna.frutos.tipos.bolota.por_fonte) * 2, "poucas por árvore (%d)" % n)


func test_estacao_decide_o_fruto() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := _lugar(eco, "bolota")
	var f := Frutos.new(eco, w.amb, 5)
	var cl := _clima(0)                                   # primavera: carvalho não dá bolota
	for i in 30 * 60:
		f.tick(DT, cl, foco)
	igual(_frutas(eco, "bolota").size(), 0, "primavera sem bolota")
	var w2 := _mundo()
	var eco2: Ecossistema = w2.eco
	var foco2 := _lugar(eco2, "baga")
	var f2 := Frutos.new(eco2, w2.amb, 5)
	var verao := _clima(1)
	for i in 30 * 120:
		f2.tick(DT, verao, foco2)
	verificar(_frutas(eco2, "baga").size() >= 1, "verão: baga embaixo do arbusto (%d)" % _frutas(eco2, "baga").size())
	var w3 := _mundo()
	var eco3: Ecossistema = w3.eco
	var f3 := Frutos.new(eco3, w3.amb, 5)
	var inverno := _clima(3)
	var foco3 := _lugar(eco3, "baga")
	for i in 30 * 120:
		f3.tick(DT, inverno, foco3)
	igual(_frutas(eco3, "baga").size(), 0, "inverno: sem baga")


func test_fruto_apodrece() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var id := eco.por_comida("fruta", Vector2(3, 3), 1.0)
	eco.comida[id].vida = 20.0
	eco.comida[id].especie = "baga"
	var sem_vida := eco.por_comida("semente", Vector2(4, 4), 1.0)
	for i in 30 * 10:
		eco.tick(DT, Vector2.ZERO)
	perto(Ecossistema.podre(eco.comida[id]), 0.0, 0.3, "no meio da vida ainda pouco podre")
	for i in 30 * 9:
		eco.tick(DT, Vector2.ZERO)
	verificar(Ecossistema.podre(eco.comida[id]) > 0.6, "perto do fim, quase podre (%.2f)" % Ecossistema.podre(eco.comida[id]))
	var apodreceu := false
	for i in 30 * 3:
		eco.tick(DT, Vector2.ZERO)
		for ev in eco.eventos:
			apodreceu = apodreceu or (ev.tipo == "apodreceu" and ev.especie == "baga")
	verificar(not eco.comida.has(id), "passou da vida: sumiu")
	verificar(apodreceu, "avisou que apodreceu")
	verificar(eco.comida.has(sem_vida), "comida sem vida não apodrece")


func test_passaro_come_fruto_e_leva_a_semente() -> void:
	var w := _mundo()
	var p := Passaros.new(w.g, w.m, w.amb)
	p.eco = w.eco
	var eco: Ecossistema = w.eco
	var c := Vector2(10.5, 10.5)
	var ids: Array = []
	for i in 3:
		var id := eco.por_comida("fruta", c + Vector2(i * 0.5, 0), 1.0)
		eco.comida[id].fonte = "arv_carvalho"
		ids.append(id)
	var b := {"id": 1, "pos": c, "n": 12, "sementes": 0, "semente_esp": ""}
	p._comer(b)
	verificar(int(b.sementes) > 0, "comeu fruto: leva semente")
	igual(String(b.semente_esp), "arv_carvalho", "a semente é da árvore do fruto")
	var sobrou := ids.filter(func(id): return eco.comida.has(id)).size()
	igual(sobrou, 1, "bando de 12 comeu 2 dos 3 frutos")
	eco.tick(DT, c)
	verificar(eco.eventos.any(func(ev): return ev.tipo == "comeu" and ev.quem == "passaro" and ev.comida == "fruta"), "evento comeu")
	# leva a semente e ela vira muda de carvalho no chão morto
	var morto: Variant = null
	for y in range(-60, 61, 3):
		for x in range(-60, 61, 3):
			var t := Vector2i(x, y)
			if (w.amb as AmbienteVivo).pode_plantar(t) and morto == null:
				(w.amb as AmbienteVivo).somar(t, AmbienteVivo.QUEIM, 1.0)
				if eco.morto(t):
					morto = t
	verificar(morto != null, "achou chão morto para o teste")
	if morto == null:
		return
	b.pos = Vector2(morto) + Vector2(0.5, 0.5)
	b.t_semente = 0.0
	b.alt = 5.0
	b.especie = "pardelo"
	var plantou := false
	for i in 40:
		p._semear(b, 1.0)
		if p.plantadas > 0:
			plantou = true
			break
	verificar(plantou, "a semente caiu e nasceu muda")
	var amb: AmbienteVivo = w.amb
	var de_carvalho := amb.especies.values().has("arv_carvalho")
	verificar(de_carvalho, "a muda é de carvalho (da bolota que ele comeu)")


func test_passaro_sem_fruto_em_chao_saudavel() -> void:
	var w := _mundo()
	var p := Passaros.new(w.g, w.m, w.amb)
	p.eco = w.eco
	var eco: Ecossistema = w.eco
	var bom := Vector2.ZERO
	for y in range(-80, 81, 4):
		for x in range(-80, 81, 4):
			if eco.saude(Vector2i(x, y)) >= 0.6:
				bom = Vector2(x, y)
	var b := {"id": 1, "pos": bom, "n": 8, "sementes": 0, "semente_esp": "x"}
	p._comer(b)
	verificar(int(b.sementes) > 0, "come semente do mato")
	igual(String(b.semente_esp), "", "semente do bioma (sem espécie do fruto)")


func test_sementes_no_vento_na_troca_de_estacao() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var amb: AmbienteVivo = w.amb
	var foco := Vector2.ZERO
	var n := -1
	for y in range(-160, 161, 40):
		for x in range(-160, 161, 40):
			var k := eco.arvores_perto(Vector2(x, y), 30.0).filter(func(a):
				return Ecossistema.especie_arvore(String(a.nome)) in ["arv_betula", "arv_pinheiro"]).size()
			if k > n:
				n = k
				foco = Vector2(x, y)
	verificar(n >= 3, "bosque de bétula/pinheiro (%d)" % n)
	var f := Frutos.new(eco, amb, 7)
	var cl := _clima(1, "limpo", 0.99)
	cl.direcao_vento = Vector2(1, 0)
	f.tick(DT, cl, foco)
	igual(amb.plantas.size(), 0, "sem troca de estação, nenhuma muda")
	cl.estacao = 2                                         # o outono chega: bétula e pinheiro soltam sementes
	cl.t_estacao = 0.0
	f.tick(DT, cl, foco)
	var mudas: Array = f.eventos.filter(func(ev): return ev.tipo == "muda_semente")
	verificar(mudas.size() >= 1, "nasceram mudas de semente (%d)" % mudas.size())
	verificar(mudas.size() <= int(Registro.fauna.frutos.sementes.max_por_vez), "até max_por_vez")
	igual(f.semeadas, mudas.size(), "conta")
	var a_favor := 0
	for ev in mudas:
		var t: Vector2i = ev.tile
		verificar(amb.plantas.has(t), "muda no mapa")
		verificar(String(amb.especies.get(t, "")) in ["arv_betula", "arv_pinheiro"], "da espécie da árvore (%s)" % amb.especies.get(t, ""))
		igual(String(amb.especies.get(t, "")), String(ev.especie), "a espécie do evento")
		var d: Vector2 = Vector2(t) + Vector2(0.5, 0.5) - (ev.de as Vector2)
		if d.x > 0.0:
			a_favor += 1
		verificar(d.length() <= 22.0 * 1.07 + 1.0, "longe no máximo dist (%.1f)" % d.length())
	igual(a_favor, mudas.size(), "todas a favor do vento (leste)")
	# a mesma estação não semeia de novo
	var antes := amb.plantas.size()
	for i in 30:
		f.tick(DT, cl, foco)
	igual(amb.plantas.size(), antes, "uma vez por troca")
	# salva e volta: lembra a estação (não semeia de novo ao carregar)
	var f2 := Frutos.new(eco, amb, 7)
	f2.restaurar(str_to_var(var_to_str(f.estado())))
	f2.tick(DT, cl, foco)
	igual(amb.plantas.size(), antes, "carregar não semeia de novo")
	igual(f2.semeadas, f.semeadas, "contagem vai no save")


func test_semente_prefere_chao_morto() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var amb: AmbienteVivo = w.amb
	var foco := Vector2.ZERO
	var n := -1
	for y in range(-160, 161, 40):
		for x in range(-160, 161, 40):
			var k := eco.arvores_perto(Vector2(x, y), 30.0).filter(func(a):
				return Ecossistema.especie_arvore(String(a.nome)) in ["arv_betula", "arv_pinheiro"]).size()
			if k > n:
				n = k
				foco = Vector2(x, y)
	# queima uma faixa larga a leste do bosque
	for y in range(int(foco.y) - 60, int(foco.y) + 61):
		for x in range(int(foco.x) - 60, int(foco.x) + 61):
			amb.somar(Vector2i(x, y), AmbienteVivo.QUEIM, 1.0)
	var f := Frutos.new(eco, amb, 9)
	var cl := _clima(2, "limpo", 0.0)
	cl.direcao_vento = Vector2(1, 0)
	f._estacao_ant = 1
	f.tick(DT, cl, foco)
	var mudas: Array = f.eventos.filter(func(ev): return ev.tipo == "muda_semente")
	verificar(mudas.size() >= 1, "brotou no queimado (%d)" % mudas.size())
	for ev in mudas:
		verificar(amb.valor(ev.tile, AmbienteVivo.QUEIM) > 0.5, "muda no chão queimado")


func test_muda_cresce_pela_estacao() -> void:
	var ritmos: Array = []
	for e in 4:
		var w := _mundo()
		var amb: AmbienteVivo = w.amb
		var t := Vector2i.ZERO
		for y in range(-60, 61, 5):
			for x in range(-60, 61, 5):
				if amb.pode_plantar(Vector2i(x, y)) and t == Vector2i.ZERO:
					t = Vector2i(x, y)
		verificar(amb.plantar_em(t, "arv_betula"), "planta em %s" % str(t))
		var cl := _clima(e)
		cl.molhado = 0.0
		var fab := Fabrica.new(w.m)
		for i in 60:
			amb.tick(1.0, fab, cl)
		ritmos.append(float(amb.plantas[t]))
	verificar(ritmos[0] > ritmos[1] and ritmos[1] > ritmos[2] and ritmos[2] > ritmos[3],
			"primavera > verão > outono > inverno (%s)" % str(ritmos))
	verificar(ritmos[3] > 0.05, "no inverno ainda cresce um pouco (%.3f)" % ritmos[3])


func test_desenho_sementes_e_frutos() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var foco := Vector2.ZERO
	var n := -1
	for y in range(-160, 161, 40):
		for x in range(-160, 161, 40):
			var k := eco.arvores_perto(Vector2(x, y), 28.0).filter(func(a):
				return Ecossistema.especie_arvore(String(a.nome)) in ["arv_betula", "arv_pinheiro"]).size()
			if k > n:
				n = k
				foco = Vector2(x, y)
	eco.tick(DT, foco)
	var d := DesenhoPlantasReagem.new()
	d.eco = eco
	d.clima = _clima(2, "nublado", 0.02)                    # começo do outono, com vento
	d._ready()
	d._process(0.1)
	verificar(d.taxa_sementes("arv_betula") > 0.2, "começo do outono: bétula solta (%.2f)" % d.taxa_sementes("arv_betula"))
	igual(d.taxa_sementes("arv_carvalho"), 0.0, "carvalho não solta semente no vento")
	verificar(d.sementes.size() >= 5, "sementes voando (%d)" % d.sementes.size())
	for s in d.sementes:
		var p := Vector2(s.pos.x, -s.pos.z)
		verificar(float(s.pos.y) >= Grade.altura_em(p) + 0.2, "no ar, acima do capim")
	d.clima = _clima(2, "nublado", 0.6)                      # meio do outono: já passou
	d._process(0.1)
	igual(d.sementes.size(), 0, "fora da janela, nenhuma")
	d.free()
