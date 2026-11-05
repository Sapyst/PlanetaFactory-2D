extends Caso
## Patch fauna, fase 8 (docs/PLANO_FAUNA.md): o jeito de cada espécie alienígena, a procriação pela regra dela, a
## guerra entre aranhas e larvas (brigam, disputam território, atacam a toca do outro) e a caça de rato e pássaro.

const DT := 1.0 / 20.0


func _base() -> Dictionary:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var p := Poluicao.new(m.gerador)
	var c := Colonia.new(m, p, 3)
	for x in range(-60, 61):
		for y in range(-24, 25):
			m.limpar_obstaculo(Vector2i(x, y))
	return {"m": m, "p": p, "c": c}


func _rodar(c: Colonia, s: float, fontes: Array[Dictionary] = []) -> Array:
	var evs: Array = []
	for i in int(s / DT):
		c.tick(DT, fontes)
		evs.append_array(c.eventos)
	return evs


func test_relacoes() -> void:
	var c: Colonia = _base().c
	verificar(c.hostil("aranha", "larva") and c.hostil("larva", "aranha"), "aranha × larva = hostis")
	verificar(not c.hostil("aranha", "aranha") and not c.hostil("larva", "larva"), "a mesma espécie não briga")
	igual(float(c.comp("larva").ataque_raio), 80.0, "a larva fica perto da cratera (ataca só até 80 m)")
	igual(float(c.comp("aranha").ataque_raio), 160.0, "a aranha vai longe")


func test_bichos_brigam() -> void:
	var b := _base()
	var c: Colonia = b.c
	var ni := c._criar_ninho(Vector2i(-20, 0), 1.0, "aranha")
	var cr := c._criar_ninho(Vector2i(20, 0), 1.0, "larva")
	var a1 := c._nova_aranha(ni)
	var l1 := c._nova_aranha(cr)
	c.aranhas[a1].pos = Vector2(0, 0)
	c.aranhas[l1].pos = Vector2(6, 0)
	var evs := _rodar(c, 0.6)
	igual(int(c.aranhas.get(a1, {}).get("estado", -1)), Colonia.E.BRIGANDO, "a aranha viu a larva e foi brigar")
	evs = _rodar(c, 40.0)
	var mortes := evs.filter(func(e): return e.tipo == "aranha_morta")
	verificar(mortes.size() >= 1, "alguém morreu na briga")
	verificar(String(mortes[0].get("por", "")) in ["aranha", "larva"], "morto pela outra espécie (%s)" % String(mortes[0].get("por", "")))
	# longe uma da outra, não se veem
	var b2 := _base()
	var c2: Colonia = b2.c
	var n2 := c2._criar_ninho(Vector2i(-40, 0), 1.0, "aranha")
	var cr2 := c2._criar_ninho(Vector2i(40, 0), 1.0, "larva")
	var a2 := c2._nova_aranha(n2)
	var l2 := c2._nova_aranha(cr2)
	_rodar(c2, 3.0)
	verificar(int(c2.aranhas[a2].estado) != Colonia.E.BRIGANDO and int(c2.aranhas[l2].estado) != Colonia.E.BRIGANDO, "de longe, cada uma no seu canto")


func test_territorio_o_mais_forte_cobre() -> void:
	var b := _base()
	var c: Colonia = b.c
	var forte := c._criar_ninho(Vector2i(-5, 0), 1.0, "aranha")
	var fraco := c._criar_ninho(Vector2i(4, 0), 1.0, "larva")
	for i in 4:
		c._nova_aranha(forte)
	c.ninhos[fraco].vida = 25.0
	var r0 := Infestacao.raio_de(c.ninhos[forte])
	var caiu := {}
	for i in int(60.0 / DT):
		c.tick(DT, [])
		for e in c.eventos:
			if e.tipo == "ninho_destruido" and int(e.id) == fraco:
				caiu = e
		if not caiu.is_empty():
			break
	verificar(not caiu.is_empty(), "a cratera mais fraca caiu na disputa")
	igual(String(caiu.get("por", "")), "aranha", "derrubada pelas aranhas")
	verificar(not b.m.estruturas.has(fraco), "a toca saiu do mapa")
	verificar(Infestacao.raio_de(c.ninhos[forte]) > r0 + 0.05, "o ninho vencedor cresceu por cima (%.2f → %.2f)" % [r0, Infestacao.raio_de(c.ninhos[forte])])


func test_grupo_vai_contra_a_toca_inimiga() -> void:
	var b := _base()
	var c: Colonia = b.c
	var m: MapaOcupacao = b.m
	var ni := c._criar_ninho(Vector2i(-30, 0), 1.0, "aranha")
	var cr := c._criar_ninho(Vector2i(0, 0), 1.0, "larva")
	var fab := m.colocar("fornalha", Vector2i(-30, 20), 0)
	var longe: Array[Dictionary] = [{"id": fab, "pos": Vector2(-29, 21)}]
	m.remover(fab)
	fab = m.colocar("fornalha", Vector2i(55, 0), 0)
	longe = [{"id": fab, "pos": Vector2(56, 1)}]
	for i in int(Registro.inimigos.ninho.grupo_ataque):
		c._nova_aranha(ni)
	c.tick(DT, longe)
	var ev: Array = c.eventos.filter(func(e): return e.tipo in ["guerra", "ataque"] and int(e.ninho) == ni)
	verificar(not ev.is_empty(), "o ninho mandou o grupo")
	igual(String(ev[0].tipo), "guerra", "contra a cratera, que está mais perto que a fábrica")
	igual(int(ev[0].alvo), cr, "alvo: a cratera")
	# o grupo chega e fere a cratera (a mordida vale na toca inimiga)
	var v0 := float(c.ninhos[cr].vida)
	_rodar(c, 30.0, longe)
	verificar(not c.ninhos.has(cr) or float(c.ninhos[cr].vida) < v0, "a cratera levou mordida (%.0f → %.0f)" % [v0, float(c.ninhos.get(cr, {}).get("vida", 0.0))])


func test_larva_fica_perto_da_cratera() -> void:
	var b := _base()
	var c: Colonia = b.c
	var m: MapaOcupacao = b.m
	var cr := c._criar_ninho(Vector2i(-50, 0), 1.0, "larva")
	var fab := m.colocar("fornalha", Vector2i(52, 0), 0)
	var fontes: Array[Dictionary] = [{"id": fab, "pos": Vector2(53, 1)}]
	for i in int(Registro.inimigos.cratera.grupo_ataque) + 1:
		c._nova_aranha(cr)
	c.tick(DT, fontes)
	verificar(not c.eventos.any(func(e): return e.tipo == "ataque"), "a 100 m, a larva não vai")
	var b2 := _base()
	var c2: Colonia = b2.c
	var ni := c2._criar_ninho(Vector2i(-50, 0), 1.0, "aranha")
	var fab2 := (b2.m as MapaOcupacao).colocar("fornalha", Vector2i(52, 0), 0)
	for i in int(Registro.inimigos.ninho.grupo_ataque):
		c2._nova_aranha(ni)
	c2.tick(DT, [{"id": fab2, "pos": Vector2(53, 1)}] as Array[Dictionary])
	verificar(c2.eventos.any(func(e): return e.tipo == "ataque"), "a aranha vai")


# ------------------------------------------------------------------ caça
func _mundo_vivo() -> Dictionary:
	var b := _base()
	var m: MapaOcupacao = b.m
	var amb := AmbienteVivo.new(m.gerador, m)
	var eco := Ecossistema.new(m.gerador, m, amb)
	var c: Colonia = b.c
	eco.registrar_fonte("alien", func() -> Array:
		var out: Array = []
		for ar in c.aranhas.values():
			out.append({"id": ar.id, "pos": ar.pos, "especie": ar.get("especie", "aranha"), "espreita": ar.get("espreita", false)})
		return out)
	var r := Ratos.new(eco, amb, 5)
	r._t_toca = 1.0e9
	eco.registrar_fonte("rato", r.para_ecossistema)
	var car := Carcacas.new(eco, amb)
	c.eco = eco
	c.ratos = r
	c.carcacas = car
	c._b = c._b.duplicate(true)
	c._b.aranha.caca.chance = 1.0
	c._b.larva.caca.chance = 1.0
	b.merge({"amb": amb, "eco": eco, "r": r, "car": car})
	return b


func test_aranhas_cacam_rato_em_dupla() -> void:
	var w := _mundo_vivo()
	var c: Colonia = w.c
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	var ni := c._criar_ninho(Vector2i(-2, -2), 1.0, "aranha")
	for i in 3:
		c._nova_aranha(ni)
	var t := r.nova_toca(Vector2(18, 10), "pardo")
	var rt: Dictionary = r.ratos.values().filter(func(x): return int(x.toca) == t)[0]
	rt.estado = Ratos.E.FAREJANDO
	rt.pos = Vector2(9, 3)
	rt.t = 1.0e6
	var cacando := 0
	var pegou := false
	var espreitou := false
	for i in int(40.0 / DT):
		eco.tick(DT, Vector2.ZERO)
		r.tick(DT, null, Vector2.ZERO)
		c.tick(DT, [])
		var n := 0
		for a in c.aranhas.values():
			if int(a.estado) == Colonia.E.CACANDO:
				n += 1
			espreitou = espreitou or bool(a.get("espreita", false))
		cacando = maxi(cacando, n)
		for e in c.eventos:
			pegou = pegou or (e.tipo == "pegou" and e.presa == "rato")
		if not r.ratos.has(int(rt.id)):
			break
	igual(cacando, 2, "caçam em dupla (uma fica em casa)")
	verificar(espreitou, "chegam espreitando")
	verificar(pegou or not r.ratos.has(int(rt.id)), "pegaram o rato")
	verificar(not r.ratos.has(int(rt.id)) or bool(r.ratos[int(rt.id)].get("morto", false)), "o rato morreu (vira carcaça)")


func test_espreita_so_e_vista_de_perto() -> void:
	var w := _mundo_vivo()
	var c: Colonia = w.c
	var g: GeradorMundo = (w.m as MapaOcupacao).gerador
	var p := Passaros.new(g, w.m, w.amb, c)
	var ni := c._criar_ninho(Vector2i(-2, -2), 1.0, "aranha")
	var a := c._nova_aranha(ni)
	c.aranhas[a].pos = Vector2(5, 0)
	verificar(p._ameaca_em(Vector2.ZERO) != null, "andando normal, o pássaro vê a 5 m")
	c.aranhas[a].espreita = true
	verificar(p._ameaca_em(Vector2.ZERO) == null, "espreitando, a 5 m não vê")
	c.aranhas[a].pos = Vector2(2, 0)
	verificar(p._ameaca_em(Vector2.ZERO) != null, "a 2 m vê")


func test_aranha_pega_passaro_no_chao() -> void:
	var w := _mundo_vivo()
	var c: Colonia = w.c
	var g: GeradorMundo = (w.m as MapaOcupacao).gerador
	var p := Passaros.new(g, w.m, w.amb, c)
	p._t_nasce = 1.0e9
	p.eco = w.eco
	c.passaros = p
	c._b.aranha.caca.presas = ["passaro"]
	var ni := c._criar_ninho(Vector2i(-2, -2), 1.0, "aranha")
	for i in 3:
		c._nova_aranha(ni)
	var mortos := 0
	for tent in 6:                                       # o bote às vezes erra (o bando vê e voa)
		var b := p._novo("pardelo", Vector2(11, 8))       # fora dos 9 m das que rondam o ninho
		b.n = 12
		b.estado = Passaros.E.POUSADO
		b.alt = 0.0
		b.t = 1.0e6
		b.poleiros = []
		p.bandos[b.id] = b
		for i in int(30.0 / DT):
			p.tick(DT, Vector2.ZERO)
			c.tick(DT, [])
			mortos += p.eventos.filter(func(e): return e.tipo == "morreu" and e.causa == "aranha").size()
			p.eventos.clear()
			if not p.bandos.has(b.id) or int(b.estado) != Passaros.E.POUSADO:
				break
		p.bandos.clear()
		if mortos > 0:
			break
	verificar(mortos >= 1, "a aranha pegou um pássaro no chão (%d)" % mortos)


func test_larva_come_carcaca_e_a_cratera_cresce() -> void:
	var w := _mundo_vivo()
	var c: Colonia = w.c
	var car: Carcacas = w.car
	var eco: Ecossistema = w.eco
	var cr := c._criar_ninho(Vector2i(-2, -2), 1.0, "larva")
	for i in 2:
		c._nova_aranha(cr)
	var id := car.morreu("rato", Vector2(7, 3), "rato_9")
	var raiva0 := float(c.ninhos[cr].raiva)
	var comeu := false
	for i in int(60.0 / DT):
		eco.tick(DT, Vector2.ZERO)
		c.tick(DT, [])
		for e in c.eventos:
			comeu = comeu or e.tipo == "comeu"
		if comeu:
			break
	verificar(comeu, "a larva foi até a carcaça e comeu")
	igual(car.etapa(eco.comida[id]), Carcacas.Etapa.RESTOS, "sobraram os ossos")
	verificar(float(c.ninhos[cr].raiva) >= raiva0 + float(c.comp("larva").procria.carcaca) - 0.01, "a cratera ganhou raiva (vira larva)")


func test_arvore_dissolvida_alimenta_a_cratera() -> void:
	var b := _base()
	var c: Colonia = b.c
	var cr := c._criar_ninho(Vector2i(-2, -2), 1.0, "larva")
	var ni := c._criar_ninho(Vector2i(40, 0), 1.0, "aranha")
	var r0 := float(c.ninhos[cr].raiva)
	var r1 := float(c.ninhos[ni].raiva)
	c.alimentar(Vector2(5, 2), "arvore")
	perto(float(c.ninhos[cr].raiva), r0 + float(c.comp("larva").procria.arvore), 1e-4, "árvore dissolvida perto: a cratera come")
	c.alimentar(Vector2(41, 1), "arvore")
	perto(float(c.ninhos[ni].raiva), r1, 1e-6, "a aranha não come matéria morta")
	c.alimentar(Vector2(-40, 0), "arvore")
	perto(float(c.ninhos[cr].raiva), r0 + float(c.comp("larva").procria.arvore), 1e-4, "longe da cratera: nada")
	# a poluição pesa menos para a larva
	verificar(float(c.comp("larva").procria.poluicao) < float(c.comp("aranha").procria.poluicao), "larva procria menos pela poluição")


func test_salva_a_guerra() -> void:
	var b := _base()
	var c: Colonia = b.c
	var ni := c._criar_ninho(Vector2i(-5, 0), 1.0, "aranha")
	c.ninhos[ni].raio_extra = 1.5
	var a := c._nova_aranha(ni)
	c.aranhas[a].estado = Colonia.E.BRIGANDO
	var c2 := Colonia.new(b.m, b.p, 4)
	c2.restaurar(str_to_var(var_to_str(c.estado())))
	perto(float(c2.ninhos[ni].raio_extra), 1.5, 1e-6, "o território ganho vai no save")
	igual(int(c2.aranhas[a].estado), Colonia.E.BRIGANDO, "o estado novo também")
