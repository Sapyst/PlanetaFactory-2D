extends Caso
## Patch fauna, fase 6 (docs/PLANO_FAUNA.md): pássaros completos — morrem (explosão, raio, velhice, doença) e viram
## carcaça; o planador pousa para comer carniça e caça rato em campo aberto (mergulho; o rato pode escapar); revoadas
## de migração na troca de estação (quem vai embora parte junto; quem chega desce e fica); ninhos nas árvores
## (obra → ovos → filhotes → voam e entram no bando; caem com a árvore; o velho cai no inverno).

const DT := 1.0 / 20.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	var p := Passaros.new(g, m, amb, col)
	p._t_nasce = 1.0e9                                     # sem bando chegando sozinho (o teste põe os seus)
	var eco: Ecossistema = p.eco
	var car := Carcacas.new(eco, amb)
	p.carcacas = car
	var r := Ratos.new(eco, amb, 5)
	r._t_toca = 1.0e9                                      # as tocas são as do teste (nem abandona, nem nasce outra)
	eco.registrar_fonte("rato", r.para_ecossistema)
	return {"g": g, "m": m, "amb": amb, "col": col, "p": p, "eco": eco, "car": car, "r": r}


func _clima(hora := 0.45, estacao := 1) -> Clima:
	var c := Clima.new(3)
	c.ciclo = false
	c.tempo_real = false
	c.estacao = estacao
	c.hora = hora
	c.forcar("limpo", true)
	c.restante = 1.0e9
	return c


## Lugar vivo (onde a região aguenta bandos) com chão de terra.
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


## Campo aberto de terra (sem árvore nem arbusto a 2 m) perto de `c`.
func _aberto(w: Dictionary, c: Vector2) -> Vector2:
	var eco: Ecossistema = w.eco
	var g: GeradorMundo = w.g
	for raio in range(0, 40, 2):
		for k in 16:
			var p := c + Vector2.from_angle(TAU * k / 16.0) * raio
			if g.terreno(Vector2i(p.floor())) == GeradorMundo.Terreno.TERRA and eco.arbustos_perto(p, 2.0).is_empty() \
					and eco.arvores_perto(p, 2.5).is_empty() and not eco.perto_de_construcao(Vector2i(p.floor()), 4):
				return Vector2(p.floor()) + Vector2(0.5, 0.5)
	return Vector2.INF


func _rodar(w: Dictionary, s: float, foco: Vector2, cl: Clima = null) -> void:
	for i in int(s / DT):
		(w.r as Ratos).tick(DT, cl, foco)
		(w.p as Passaros).tick(DT, foco, cl)
		(w.eco as Ecossistema).tick(DT, foco)
		(w.car as Carcacas).tick(DT)
		(w.p as Passaros).eventos.clear()


func _bando(p: Passaros, esp: String, pos: Vector2, n := 10, alt := 0.0, estado := Passaros.E.POUSADO) -> Dictionary:
	var b := p._novo(esp, pos)
	b.n = n
	b.alt = alt
	b.alt_alvo = alt
	b.estado = estado
	b.t = 1.0e6
	p.bandos[b.id] = b
	return b


# ------------------------------------------------------------------ morte
func test_explosao_derruba_quem_esta_perto_e_baixo() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var foco := _lugar_vivo(p)
	var baixo := _bando(p, "pardelo", foco, 20, 0.0)
	var alto := _bando(p, "cobrico", foco + Vector2(1, 0), 12, 14.0, Passaros.E.VOANDO)
	var longe := _bando(p, "rubro", foco + Vector2(25, 0), 4, 0.0)
	var mortos := p.ferir(foco, 4.0, 1.0, "explosao")
	verificar(mortos > 0, "a explosão matou pássaros do bando no chão (%d)" % mortos)
	verificar(mortos <= 6, "no máximo max_por_vez por bando (%d)" % mortos)
	igual(int(baixo.n), 20 - mortos, "o bando perdeu os que morreram")
	igual(int(alto.n), 12, "quem voa alto não é atingido")
	igual(int(longe.n), 4, "quem está longe não é atingido")
	var ev: Array = p.eventos.filter(func(e): return e.tipo == "morreu")
	igual(ev.size(), mortos, "um evento 'morreu' por pássaro (o desenho derruba o corpo)")
	verificar(String(ev[0].corpo).begins_with("passaro_"), "o corpo tem chave própria (não colide com rato/aranha)")
	verificar((ev[0].pos as Vector2).distance_to(foco) < 3.0, "cai perto de onde estava")
	# vira carcaça de pássaro, da espécie certa
	(w.eco as Ecossistema).tick(DT, foco)
	(w.car as Carcacas).tick(DT)
	var cs: Array = (w.eco as Ecossistema).comida.values().filter(func(f): return f.tipo == "carcaca" and f.especie == "passaro")
	igual(cs.size(), mortos, "cada morto vira carcaça")
	igual(String(cs[0].get("variante", "")), "pardelo", "a carcaça sabe a espécie (o desenho escolhe o modelo)")
	igual(String(cs[0].bicho), String(ev[0].corpo), "e qual corpo adotar")
	# o bando que acaba some
	var pequeno := _bando(p, "azulao", foco + Vector2(-30, 0), 1, 0.0)
	var tentativas := 0
	while p.bandos.has(pequeno.id) and tentativas < 50:
		p.ferir(pequeno.pos, 3.0, 1.0, "raio")
		tentativas += 1
	verificar(not p.bandos.has(pequeno.id), "o último que morre leva o bando junto")


func test_velhice_e_doenca() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var foco := _lugar_vivo(p)
	var m: Dictionary = p._d.morte
	var antes := float(m.natural_h)
	m.natural_h = 3600.0 * 0.004                         # 0,4% por pássaro por segundo: o teste não espera horas
	var b := _bando(p, "pardelo", foco, 30, 0.0)
	for i in 60:
		p._morrer_de_velho(1.0, null)
	var saudavel := 30 - int(b.n)
	# o mesmo bando num lugar envenenado morre mais
	var amb: AmbienteVivo = w.amb
	var ruim := foco + Vector2(0, 40)
	for y in range(-8, 9):
		for x in range(-8, 9):
			amb.somar(Vector2i(ruim.floor()) + Vector2i(x, y), AmbienteVivo.QUEIM, 1.0)
	var b2 := _bando(p, "pardelo", ruim, 30, 0.0)
	b.n = 30
	var d1 := 0
	var d2 := 0
	for i in 60:
		var n1 := int(b.n)
		var n2 := int(b2.n)
		p._morrer_de_velho(1.0, null)
		d1 += n1 - int(p.bandos.get(b.id, {"n": 0}).n)
		d2 += n2 - int(p.bandos.get(b2.id, {"n": 0}).n)
	m.natural_h = antes
	verificar(saudavel > 0, "morre de velho de vez em quando (%d em 60 s)" % saudavel)
	verificar(d2 > d1, "no chão envenenado morrem mais (%d contra %d)" % [d2, d1])
	verificar(p.mortes > 0, "contagem de mortes")


# ------------------------------------------------------------------ planador
func test_planador_pousa_na_carnica_e_come() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var eco: Ecossistema = w.eco
	var car: Carcacas = w.car
	var foco := _lugar_vivo(p)
	var onde := _aberto(w, foco)
	verificar(onde != Vector2.INF, "achou campo aberto")
	var id := car.morreu("rato", onde, "rato_7")
	var pl := _bando(p, "planador", onde + Vector2(10, 0), 1, 20.0, Passaros.E.CIRCULANDO)
	pl.centro = onde + Vector2(8, 0)
	pl.raio = 12.0
	var pousou := false
	var comeu_em := -1.0
	var idade_antes := float(eco.comida[id].idade)
	var t := 0.0
	while t < 90.0:
		_rodar(w, 0.5, foco)
		t += 0.5
		if int(pl.estado) == Passaros.E.POUSADO:
			if not pousou:
				pousou = true
				comeu_em = t
				verificar((pl.pos as Vector2).distance_to(onde) < 1.6, "pousou do lado da carcaça (%.2f m)" % (pl.pos as Vector2).distance_to(onde))
				idade_antes = float(eco.comida[id].idade)
		if pousou and int(pl.estado) == Passaros.E.CIRCULANDO:
			break
	verificar(pousou, "o planador desceu em espiral e pousou na carniça")
	verificar(comeu_em > 10.0, "só depois de rodar um tempo por cima (%.0f s)" % comeu_em)
	var f: Dictionary = eco.comida.get(id, {})
	verificar(not f.is_empty() and car.etapa(f) == Carcacas.Etapa.RESTOS, "comeu a carne: sobraram os restos")
	igual(int(pl.estado), Passaros.E.CIRCULANDO, "voltou a circular alto")
	# susto perto: não desce
	var w2 := _mundo()
	var p2: Passaros = w2.p
	var id2 := (w2.car as Carcacas).morreu("larva", onde, 8)
	var pl2 := _bando(p2, "planador", onde + Vector2(6, 0), 1, 9.0, Passaros.E.CIRCULANDO)
	pl2.centro = onde
	(w2.col as Colonia).aranhas[999] = {"id": 999, "pos": onde + Vector2(2, 0)}
	var desceu := false
	for i in 60:
		_rodar(w2, 0.5, foco)
		desceu = desceu or int(pl2.estado) in [Passaros.E.POUSADO, Passaros.E.POUSANDO]
	verificar(not desceu, "com aranha do lado da carniça, só circula")
	verificar((w2.eco as Ecossistema).comida.has(id2), "a carcaça segue lá")


func _rato_fora(w: Dictionary, onde: Vector2, toca_dist: float, esp := "pardo") -> Dictionary:
	var r: Ratos = w.r
	var t := r.nova_toca(onde + Vector2(toca_dist, 0), esp)
	var rid := -1
	for k in r.ratos:
		if int(r.ratos[k].toca) == t:
			rid = k
	var rt: Dictionary = r.ratos[rid]
	rt.estado = Ratos.E.FAREJANDO
	rt.pos = onde
	rt.t = 1.0e6
	return rt


func test_planador_caca_rato_no_aberto() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var r: Ratos = w.r
	p.ratos = r
	var foco := _lugar_vivo(p)
	var onde := _aberto(w, foco)
	var rt := _rato_fora(w, onde, 15.0)
	var pl := _bando(p, "planador", onde + Vector2(0, 12), 1, 20.0, Passaros.E.CIRCULANDO)
	pl.centro = onde + Vector2(0, 8)
	p._d.caca.chance = 1.0
	var mergulhou := false
	var pegou := false
	var cl := _clima(0.45)
	for i in int(30.0 / DT):
		if int(pl.estado) == Passaros.E.MERGULHANDO and not mergulhou:
			mergulhou = true
			pl.viu = false                                # este rato não viu a sombra
		r.tick(DT, cl, foco)
		p.tick(DT, foco, cl)
		(w.eco as Ecossistema).tick(DT, foco)
		(w.car as Carcacas).tick(DT)
		for e in p.eventos:
			pegou = pegou or e.tipo == "pegou"
		p.eventos.clear()
		if pegou and int(pl.estado) == Passaros.E.POUSADO:
			break
	p._d.caca.chance = 0.3
	verificar(mergulhou, "viu o rato no campo aberto e mergulhou")
	verificar(pegou, "pegou o rato distraído")
	verificar(not r.ratos.has(int(rt.id)), "o rato morreu")
	igual(int(pl.estado), Passaros.E.POUSADO, "pousou em cima para comer")
	var cs: Array = (w.eco as Ecossistema).comida.values().filter(func(f): return f.tipo == "carcaca" and f.especie == "rato")
	igual(cs.size(), 1, "o rato virou carcaça embaixo dele")
	igual(String(cs[0].bicho), Ratos.corpo_id(int(rt.id)), "chave do corpo do rato: 'rato_<id>'")


func test_rato_que_ve_a_sombra_escapa() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var r: Ratos = w.r
	p.ratos = r
	var foco := _lugar_vivo(p)
	var onde := _aberto(w, foco)
	var rt := _rato_fora(w, onde, 1.5, "saltador")        # a toca do lado
	var pl := _bando(p, "planador", onde + Vector2(0, 22), 1, 24.0, Passaros.E.CIRCULANDO)
	pl.centro = onde + Vector2(0, 20)
	p._d.caca.chance = 1.0
	var cl := _clima(0.45)
	var mergulhou := false
	var pegou := false
	var desistiu := false
	for i in int(30.0 / DT):
		if int(pl.estado) == Passaros.E.MERGULHANDO and not mergulhou:
			mergulhou = true
			pl.viu = true                                 # este viu
		r.tick(DT, cl, foco)
		p.tick(DT, foco, cl)
		for e in p.eventos:
			pegou = pegou or e.tipo == "pegou"
		p.eventos.clear()
		if mergulhou and int(pl.estado) == Passaros.E.CIRCULANDO:
			desistiu = true
			break
	p._d.caca.chance = 0.3
	verificar(mergulhou, "mergulhou")
	verificar(not pegou, "o rato viu a sombra e entrou na toca a tempo")
	verificar(r.ratos.has(int(rt.id)), "o rato está vivo")
	verificar(desistiu, "o planador subiu e voltou a circular")
	verificar(float(pl.t_caca) > 5.0, "e espera um pouco antes de tentar de novo")


func test_nao_caca_debaixo_do_mato() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var eco: Ecossistema = w.eco
	var foco := _lugar_vivo(p)
	# um ponto com arbusto em cima: escondido
	var esc := Vector2.INF
	for y in range(-60, 61, 2):
		for x in range(-60, 61, 2):
			var q := foco + Vector2(x, y)
			if not eco.arbustos_perto(q, 0.8).is_empty():
				esc = q
				break
		if esc != Vector2.INF:
			break
	verificar(esc != Vector2.INF, "achou um arbusto")
	verificar(not p._aberto(esc), "embaixo do arbusto o planador não vê")
	var ab := _aberto(w, foco)
	verificar(p._aberto(ab), "no campo aberto vê")


# ------------------------------------------------------------------ migração
func test_quem_vai_embora_parte_junto_na_troca() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var foco := _lugar_vivo(p)
	var cl := _clima(0.45, 2)                             # outono: o azulão ainda fica um pouco
	var a := _bando(p, "azulao", foco, 5, 0.0)
	var b := _bando(p, "azulao", foco + Vector2(10, 4), 4, 0.0)
	var c := _bando(p, "pardelo", foco + Vector2(-6, 0), 12, 0.0)
	p.tick(DT, foco, cl)
	igual(int(a.estado), Passaros.E.POUSADO, "no outono o azulão ainda está aqui")
	cl.estacao = 3                                        # inverno: o azulão vai embora
	p.tick(DT, foco, cl)
	var az: Array = p.bandos.values().filter(func(x): return x.especie == "azulao")
	igual(az.size(), 1, "os bandos de azulão se juntaram num só")
	igual(int(az[0].n), 9, "com todos os pássaros")
	igual(int(az[0].estado), Passaros.E.MIGRANDO, "e partiram em migração")
	verificar(p.eventos.any(func(e): return e.tipo == "juntou"), "evento para o desenho passar os pássaros")
	verificar(p.eventos.any(func(e): return e.tipo == "migracao"), "evento da revoada (som)")
	verificar((az[0].rumo_mig as Vector2).dot(Vector2.UP) > 0.9, "no inverno, para o norte")
	igual(int(c.estado), Passaros.E.POUSADO, "o pardelo fica")
	var alt0 := float(az[0].alt)
	for i in int(20.0 / DT):
		p.tick(DT, foco, cl)
	verificar(not p.bandos.has(az[0].id) or float(az[0].alt) > alt0 + 8.0, "sobe alto e vai embora")


func test_revoadas_de_passagem_e_chegada() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var foco := _lugar_vivo(p)
	var cl := _clima(0.45, 2)
	var dur := float(Registro.clima.get("estacao_s", 604800))
	cl.t_estacao = dur * 0.8                              # fim do outono: quem cai no inverno está indo
	p._estacao = cl.estacao
	var passagens := []
	for i in int(900.0 / 0.5):
		p.tick(0.5, foco, cl)
		for e in p.eventos:
			if e.tipo == "migracao" and not passagens.has(e.id):
				passagens.append(e.id)
		p.eventos.clear()
	verificar(passagens.size() >= 2, "passaram revoadas no fim do outono (%d em 15 min)" % passagens.size())
	# uma revoada grande, alta, que não pousa nem se junta com os daqui
	var b := p.passagem("cobrico", foco, 2, false)
	verificar(int(b.n) >= 25, "revoada grande (%d)" % int(b.n))
	verificar(float(b.alt) >= 16.0, "alta (%.0f m)" % float(b.alt))
	var local := _bando(p, "cobrico", (b.pos as Vector2) + Vector2(2, 0), 8, 5.0, Passaros.E.VOANDO)
	local.destino = foco
	p.tick(DT, foco, cl)
	verificar(p.bandos.has(local.id) and p.bandos.has(b.id), "não se mistura com o bando daqui")
	var cruzou := false
	for i in int(40.0 / DT):
		p.tick(DT, foco, cl)
		if not p.bandos.has(b.id):
			cruzou = true
			break
		if i == 0:
			igual(int(b.estado), Passaros.E.MIGRANDO, "segue migrando")
	verificar(cruzou, "cruzou o céu e sumiu do outro lado")
	# quem chega desce e fica
	var ch := p.passagem("pardelo", foco, 0, true)
	var virou_local := false
	for i in int(60.0 / DT):
		p.tick(DT, foco, cl)
		if p.bandos.has(ch.id) and not bool(ch.get("migra", true)):
			virou_local = true
			break
	verificar(virou_local, "o bando que chega desce e vira bando daqui")
	verificar(int(ch.n) <= int(p._d.bando_max_n), "do tamanho de um bando normal")
	# migrante de passagem não ocupa a lotação dos daqui
	verificar(Passaros.rumo_migracao(2, false) == Vector2.DOWN, "outono: vão para o sul")
	verificar(Passaros.rumo_migracao(0, true) == Vector2.UP, "primavera: chegam do sul (rumo norte)")


# ------------------------------------------------------------------ ninhos
func _ninhos(w: Dictionary) -> NinhosPassaros:
	var n := NinhosPassaros.new(w.p, 9)
	return n


## Um bando pousado nas copas de árvores vivas (poleiros) perto do foco.
func _pousado_nas_copas(p: Passaros, esp: String, foco: Vector2) -> Dictionary:
	for y in range(-40, 41, 3):
		for x in range(-40, 41, 3):
			var q := foco + Vector2(x, y)
			var pol := p.poleiros_em(q)
			if pol.size() >= 2 and p.eco.saude(Vector2i(q.floor())) > 0.5 and not p.eco.perto_de_construcao(Vector2i(q.floor()), 6):
				var b := _bando(p, esp, q, 10, 0.0)
				b.poleiros = pol
				return b
	return {}


func test_ninho_do_comeco_ao_voo() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var nn := _ninhos(w)
	var foco := _lugar_vivo(p)
	var cl := _clima(0.45, 0)                             # primavera, dia
	var b := _pousado_nas_copas(p, "pardelo", foco)
	verificar(not b.is_empty(), "bando pousado nas copas")
	nn._d.chance_s = 1.0
	nn.tick(0.1, cl, foco)
	nn._d.chance_s = 0.0                                  # só esse (o bando segue pousado nas outras copas)
	igual(nn.ninhos.size(), 1, "fez um ninho numa das árvores")
	var n: Dictionary = nn.ninhos.values()[0]
	igual(String(n.especie), "pardelo", "da espécie do bando")
	igual(String(n.tipo), "taca", "do tipo da espécie (fauna.json)")
	igual(int(n.fase), NinhosPassaros.F.OBRA, "começa em obra")
	verificar(nn.eventos.any(func(e): return e.tipo == "novo"), "evento 'novo' (desenho)")
	var pol: Array = b.poleiros
	verificar(p._lugar_bom(b, n.pos, foco, 6.0) != null, "o bando acha lugar bom perto do ninho")
	b.poleiros = pol
	var visitas := 0
	var fases := []
	var n0 := int(b.n)
	var voaram := 0
	for i in int(1500.0 / 0.5):
		nn.tick(0.5, cl, foco)
		for e in nn.eventos:
			if e.tipo == "visita":
				visitas += 1
			elif e.tipo == "fase":
				fases.append(int(e.fase))
			elif e.tipo == "voaram":
				voaram = int(e.n)
		nn.eventos.clear()
	igual(fases, [NinhosPassaros.F.OVOS, NinhosPassaros.F.FILHOTES, NinhosPassaros.F.VAZIO], "obra → ovos → filhotes → vazio")
	verificar(visitas >= 10, "os adultos vieram trazer graveto e comida (%d visitas)" % visitas)
	verificar(voaram >= 2, "os filhotes voaram (%d)" % voaram)
	igual(int(b.n), n0 + voaram, "e entraram no bando")
	igual(int(n.ninhadas), 1, "uma ninhada")
	# de novo na primavera: reaproveita o vazio
	nn._d.chance_s = 1.0
	nn.tick(2.1, cl, foco)
	nn._d.chance_s = 0.04
	igual(nn.ninhos.size(), 1, "não fez outro: reformou o mesmo")
	igual(int(n.fase), NinhosPassaros.F.OBRA, "o vazio voltou para a obra")


func test_ninho_cai_com_a_arvore_e_no_inverno() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var m: MapaOcupacao = w.m
	var nn := _ninhos(w)
	var foco := _lugar_vivo(p)
	var cl := _clima(0.45, 0)
	var b := _pousado_nas_copas(p, "cobrico", foco)
	nn._d.chance_s = 1.0
	nn.tick(0.1, cl, foco)
	nn._d.chance_s = 0.04
	igual(nn.ninhos.size(), 1, "ninho feito")
	var n: Dictionary = nn.ninhos.values()[0]
	igual(String(n.tipo), "bolsa", "cobrico tece bolsa")
	verificar(int(n.n) >= 1 and int(n.n) <= 3, "1 a 3 bolsas na árvore (%d)" % int(n.n))
	# cortaram a árvore
	m.arvores[n.tile] = {"e": "queimada"}
	nn.tick(2.1, cl, foco)
	igual(nn.ninhos.size(), 0, "a árvore queimou: o ninho caiu")
	var ev: Array = nn.eventos.filter(func(e): return e.tipo == "caiu")
	igual(ev.size(), 1, "evento 'caiu' (o desenho derruba)")
	igual(String(ev[0].motivo), "arvore", "por causa da árvore")
	m.arvores.erase(n.tile)
	# ninho vazio velho no inverno desmancha
	nn.eventos.clear()
	nn._d.chance_s = 1.0
	nn.tick(2.1, cl, foco)
	nn._d.chance_s = 0.04
	var v: Dictionary = nn.ninhos.values()[0]
	v.fase = NinhosPassaros.F.VAZIO
	v.t = 0.0
	cl.estacao = 3
	for i in int(7200.0 / 2.0):
		nn.tick(2.0, cl, foco)
		if nn.ninhos.is_empty():
			break
	verificar(nn.ninhos.is_empty(), "no inverno o ninho velho caiu")
	verificar(nn.eventos.any(func(e): return e.tipo == "caiu" and e.motivo == "velho"), "de velho")


func test_ninho_regras_e_salvar() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var nn := _ninhos(w)
	var foco := _lugar_vivo(p)
	var b := _pousado_nas_copas(p, "rubro", foco)
	nn._d.chance_s = 1.0
	nn.tick(0.1, _clima(0.45, 2), foco)                   # outono: não faz ninho
	igual(nn.ninhos.size(), 0, "no outono ninguém faz ninho")
	nn.tick(2.1, _clima(0.02, 0), foco)                   # primavera de madrugada: também não
	igual(nn.ninhos.size(), 0, "nem de noite")
	b.estado = Passaros.E.VOANDO
	nn.tick(2.1, _clima(0.45, 0), foco)
	igual(nn.ninhos.size(), 0, "nem voando (só quem pousou na copa)")
	b.estado = Passaros.E.POUSADO
	nn.tick(2.1, _clima(0.45, 0), foco)
	nn._d.chance_s = 0.04
	igual(nn.ninhos.size(), 1, "pousado na copa, primavera, de dia: fez")
	var n: Dictionary = nn.ninhos.values()[0]
	n.fase = NinhosPassaros.F.FILHOTES
	n.ovos = 3
	var d := nn.estado()
	var nn2 := NinhosPassaros.new(p, 3)
	nn2.restaurar(str_to_var(var_to_str(d)))
	igual(nn2.ninhos.size(), 1, "salvou e carregou o ninho")
	var n2: Dictionary = nn2.ninhos.values()[0]
	igual(int(n2.fase), NinhosPassaros.F.FILHOTES, "na mesma fase")
	igual(Vector2i(n2.tile), Vector2i(n.tile), "na mesma árvore")
	verificar(nn2.ninhos.has(Vector2i(n.tile)), "chave pelo tile da árvore")


# ------------------------------------------------------------------ carcaça bicada
func test_bicar_para_nos_restos() -> void:
	var w := _mundo()
	var car: Carcacas = w.car
	var eco: Ecossistema = w.eco
	var id := car.morreu("passaro", Vector2(3, 3), "passaro_x")
	verificar(car.bicar(id, 10.0), "ainda tem carne")
	var f: Dictionary = eco.comida[id]
	for i in 200:
		car.bicar(id, 10.0)
	igual(car.etapa(f), Carcacas.Etapa.RESTOS, "comeu até os restos")
	var e: Array = Registro.fauna.carcacas.tipos.passaro.etapas
	perto(float(f.idade), float(f.vida) * float(e[1]), 0.01, "mas não passa do começo dos restos (o osso fica)")
	verificar(not car.bicar(id, 10.0), "sem carne")


# ------------------------------------------------------------------ dados e desenho
func test_dados_da_fase() -> void:
	var esp: Dictionary = Registro.fauna.especies
	verificar(esp.has("geado"), "o geado (chega no inverno) está nos dados")
	var e: Array = esp.geado.estacoes
	verificar(float(e[3]) > 0.9 and float(e[0]) == 0.0 and float(e[1]) == 0.0, "só no fim do outono e no inverno")
	verificar(Registro.modelos.has("passaro_geado"), "modelo do geado")
	for n in esp:
		var tipo := String(esp[n].get("ninho", ""))
		if tipo != "":
			verificar(Registro.modelos.has("ninho_" + tipo), "modelo do ninho de %s (%s)" % [n, tipo])
	igual(String(esp.pardelo.ninho), "taca", "pardelo: taça")
	igual(String(esp.cobrico.ninho), "bolsa", "cobrico: bolsa")
	# cada árvore do jogo tem onde pôr a taça e as bolsas
	var f := FileAccess.open("res://dados/ninhos_arvores.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var arvores := 0
	for nome in Registro.modelos:
		if not Distribuicao.eh_arvore(nome) or nome == "arvore_morta":
			continue
		arvores += 1
		verificar(d.has(nome), "pontos de ninho em %s" % nome)
		var alto := float(Registro.modelos[nome].dims[2])
		var ps := DesenhoNinhosPassaros.pontos(nome, "taca")
		igual(ps.size(), 1, "uma taça em %s" % nome)
		var pt: Vector3 = ps[0].p
		verificar(pt.y > 0.3 and pt.y < alto, "a taça fica no tronco/forquilha de %s (%.2f m de %.2f)" % [nome, pt.y, alto])
		var bs := DesenhoNinhosPassaros.pontos(nome, "bolsa")
		verificar(bs.size() >= 1 and bs.size() <= 3, "1 a 3 bolsas em %s" % nome)
		for b in bs:
			verificar(b.has("galho"), "a bolsa sabe de qual galho pende (%s)" % nome)
			verificar((b.p as Vector3).y > 0.4, "a bolsa pende no alto (%s, %.2f m)" % [nome, (b.p as Vector3).y])
	verificar(arvores >= 38, "todas as árvores (%d)" % arvores)


func test_morto_de_lado_ou_de_costas() -> void:
	var lado := 0
	var costas := 0
	for k in 200:
		var c := "passaro_7_%d" % k
		if k < 3:
			igual(DesenhoPassaros.de_costas(c), DesenhoPassaros.de_costas(c), "o mesmo corpo cai sempre do mesmo jeito")
		if DesenhoPassaros.de_costas(c):
			costas += 1
		else:
			lado += 1
	verificar(lado > 60 and costas > 60, "sorteado meio a meio (%d de lado, %d de costas)" % [lado, costas])


func test_muda_brota_na_cinza() -> void:
	var w := _mundo()
	var amb: AmbienteVivo = w.amb
	var p: Passaros = w.p
	var foco := _lugar_vivo(p)
	var t := Vector2i(foco.floor()) + Vector2i(3, 3)
	(w.m as MapaOcupacao).limpar_obstaculo(t)
	amb.somar(t, AmbienteVivo.QUEIM, 1.0)
	verificar(amb.plantar_em(t, "arv_carvalho"), "plantou na cinza")
	verificar(amb.valor(t, AmbienteVivo.QUEIM) <= 0.3, "a muda abriu um ponto vivo: o tile dela não é mais carvão (%.2f)" % amb.valor(t, AmbienteVivo.QUEIM))
