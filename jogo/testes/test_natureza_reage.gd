extends Caso
## Patch fauna, fase 7 (docs/PLANO_FAUNA.md): a natureza reage à fábrica — o chão limpo volta em etapas (insetos →
## mato → ratos → pássaros → árvores), a fauna se afasta do barulho e da fumaça.

func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var col := Colonia.new(m, Poluicao.new(g), 3)
	var p := Passaros.new(g, m, amb, col)
	p._t_nasce = 1.0e9
	var eco: Ecossistema = p.eco
	var r := Ratos.new(eco, amb, 5)
	r._t_toca = 1.0e9
	var nn := NinhosPassaros.new(p, 9)
	return {"g": g, "m": m, "amb": amb, "col": col, "p": p, "eco": eco, "r": r, "nn": nn}


## Uma célula de mato saudável, só de terra, longe de construção, onde dá toca de rato.
func _celula_boa(w: Dictionary) -> Vector2i:
	var eco: Ecossistema = w.eco
	var r: Ratos = w.r
	r._d = r._d.duplicate()
	r._d.aberto_chance = 1.0
	for y in range(-14, 15):
		for x in range(-14, 15):
			var k := Vector2i(x, y)
			if eco._ocupada(k) or eco.saude_celula(k) < 0.45:
				continue
			var c := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
			var ok := false
			for d in [Vector2(0, 0), Vector2(1.5, 0), Vector2(-1.5, 1), Vector2(0.5, -1.5)]:
				if r.especie_de_toca(Vector2i((c + d).floor())) != "":
					ok = true
			if ok:
				return k
	return Vector2i(9999, 9999)


func _queimar(w: Dictionary, k: Vector2i, v: float) -> void:
	for y in 8:
		for x in 8:
			(w.amb as AmbienteVivo).somar(Vector2i(k.x * 8 + x, k.y * 8 + y), AmbienteVivo.QUEIM, v)


func _toca_em(w: Dictionary, k: Vector2i) -> bool:
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
	for d in [Vector2(0, 0), Vector2(1.5, 0), Vector2(-1.5, 1), Vector2(0.5, -1.5)]:
		if (w.r as Ratos).especie_de_toca(Vector2i((c + d).floor())) != "":
			return true
	return false


func test_volta_em_etapas() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var amb: AmbienteVivo = w.amb
	var k := _celula_boa(w)
	verificar(k != Vector2i(9999, 9999), "achou célula de mato boa")
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
	eco.foco = c
	igual(eco.etapa_em(c), Ecossistema.Rec.ARVORES, "nunca ferida: completa")
	verificar(_toca_em(w, k), "dá toca de rato antes")
	_queimar(w, k, 1.0)
	eco.recuperar(2.0)
	igual(eco.etapa_em(c), Ecossistema.Rec.MORTA, "queimou: chão morto")
	perto(eco.mato_em(c), 0.0, 1e-6, "sem capim")
	verificar(not _toca_em(w, k), "chão morto: sem toca")
	_queimar(w, k, -1.0)                                  # o coletor/semeador limpou
	eco.recuperar(2.0)
	igual(eco.etapa_em(c), Ecossistema.Rec.INSETOS, "limpou: os insetos voltam primeiro")
	verificar(not _toca_em(w, k), "rato ainda não")
	var p: Passaros = w.p
	var b := p._novo("pardelo", c)
	verificar(p._lugar_bom(b, c, c, 3.0) == null, "pássaro ainda não pousa ali")
	var etapas := []                                      # (o "insetos" de agora chega no próximo tick)
	var mudas0 := amb.plantas.size()
	var t := 0.0
	var mato_meio := -1.0
	while t < 800.0:
		eco.tick(2.0, c)
		t += 2.0
		for e in eco.eventos:
			if e.tipo == "etapa" and e.cel == k:
				etapas.append(int(e.etapa))
		if t > 44.0 and t < 47.0:
			mato_meio = eco.mato_em(c)
		if eco.etapa_em(c) == Ecossistema.Rec.RATOS and not _toca_em(w, k):
			verificar(false, "na etapa dos ratos a toca já pode")
	eco.tick(0.1, c)
	for e in eco.eventos:
		if e.tipo == "etapa" and e.cel == k:
			etapas.append(int(e.etapa))
	igual(etapas, [Ecossistema.Rec.INSETOS, Ecossistema.Rec.MATO, Ecossistema.Rec.RATOS, Ecossistema.Rec.PASSAROS,
			Ecossistema.Rec.ARVORES], "insetos → mato → ratos → pássaros → árvores")
	verificar(mato_meio > 0.3 and mato_meio < 0.7, "o capim volta aos poucos (%.2f no meio do caminho)" % mato_meio)
	igual(eco.etapa_em(c), Ecossistema.Rec.ARVORES, "completa de novo")
	verificar(not eco.recuperacao.has(k), "saiu da lista")
	verificar(amb.plantas.size() > mudas0, "a mata volta: brotaram mudas (%d)" % (amb.plantas.size() - mudas0))
	verificar(_toca_em(w, k), "e o rato pode voltar")


func test_fabrica_e_agua_nao_contam() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var g: GeradorMundo = w.g
	var agua := Vector2i(9999, 9999)
	for y in range(-30, 31):
		for x in range(-30, 31):
			var k := Vector2i(x, y)
			var n := 0
			for j in 3:
				for i in 3:
					if g.terreno(Vector2i(k.x * 8 + 1 + 3 * i, k.y * 8 + 1 + 3 * j)) != GeradorMundo.Terreno.TERRA:
						n += 1
			if n == 9:
				agua = k
				break
		if agua != Vector2i(9999, 9999):
			break
	verificar(agua != Vector2i(9999, 9999), "achou célula de água")
	eco.foco = (Vector2(agua) + Vector2(0.5, 0.5)) * 8.0
	eco.recuperar(2.0)
	verificar(not eco.recuperacao.has(agua), "lago não é chão morto")
	igual(eco.etapa_em(eco.foco), Ecossistema.Rec.ARVORES, "fica completo")


func test_disturbio_afasta() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var p: Passaros = w.p
	var k := _celula_boa(w)
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
	verificar(_toca_em(w, k), "quieto: dá toca")
	var b := p._novo("pardelo", c)
	var lot0 := p.lotacao(c)
	eco.fonte_disturbio = func(q: Vector2) -> float: return 0.9 if q.distance_to(c) < 30.0 else 0.0
	verificar(not _toca_em(w, k), "barulho: rato não faz toca")
	verificar(p._lugar_bom(b, c, c, 6.0) == null, "barulho: pássaro não pousa")
	verificar(p.lotacao(c) < lot0, "barulho: menos bandos na região (%d → %d)" % [lot0, p.lotacao(c)])
	var nn: NinhosPassaros = w.nn
	verificar(not nn._lugar_ok(Vector2i(c.floor()), c), "barulho: sem ninho")
	perto(eco.disturbio(c + Vector2(100, 0)), 0.0, 1e-6, "longe, quieto")
	# a toca que já existe perto de máquina barulhenta é abandonada
	var r: Ratos = w.r
	var t := r.nova_toca(c, "pardo")
	r._cuidar_tocas(c)
	verificar(not r.tocas.has(t), "toca abandonada com o barulho")


func test_recuperacao_salva() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var k := _celula_boa(w)
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
	eco.foco = c
	_queimar(w, k, 1.0)
	eco.recuperar(2.0)
	_queimar(w, k, -1.0)
	for i in 60:
		eco.recuperar(2.0)
	var d: Dictionary = str_to_var(var_to_str(eco.estado()))
	var e2 := Ecossistema.new(w.g, w.m, w.amb)
	e2.restaurar(d)
	igual(e2.etapa_em(c), eco.etapa_em(c), "carregou na mesma etapa (%d)" % eco.etapa_em(c))
	perto(e2.mato_em(c), eco.mato_em(c), 1e-4, "o capim no mesmo ponto")


# ------------------------------------------------------------------ barulho e fumaça da fábrica
## Um canto de terra livre (sem obstáculo) de lado `n` perto do núcleo.
func _limpo(m: MapaOcupacao, n: int) -> Vector2i:
	for y in range(-60, 61, 4):
		for x in range(20, 80, 4):
			var ok := true
			for j in n:
				for i in n:
					var t := Vector2i(x + i, y + j)
					ok = ok and m.gerador.terreno(t) == GeradorMundo.Terreno.TERRA and not m.tiles.has(t) \
							and m.gerador.distribuicao.jazida(t).is_empty()
			if ok:
				for j in n:
					for i in n:
						m.limpar_obstaculo(Vector2i(x + i, y + j))
				if m.motivo_bloqueio("fornalha", Vector2i(x, y), 0) != "" or m.motivo_bloqueio("braco", Vector2i(x + 3, y), 0) != "":
					continue
				return Vector2i(x, y)
	return Vector2i(9999, 9999)


func test_barulho_e_fumaca() -> void:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var fab := Fabrica.new(m)
	var pol := Poluicao.new(g)
	var d := DisturbioFabrica.new(m, fab, pol)
	var c := _limpo(m, 6)
	verificar(c != Vector2i(9999, 9999), "achou chão livre")
	var id := m.colocar("fornalha", c, 0)
	verificar(id >= 0, "pôs a fornalha")
	var maq := Maquina.new("fornalha")
	fab.maquinas[id] = maq
	var centro := Grade.centro_da_area(c, Vector2i(2, 2), 0)
	maq.estado = Maquina.Estado.PRONTIDAO
	d.atualizar(centro)
	perto(d.em(centro), 0.0, 1e-6, "parada: sem barulho")
	maq.estado = Maquina.Estado.TRABALHANDO
	d.atualizar(centro)
	verificar(d.em(centro) > 0.7, "trabalhando: barulho forte do lado (%.2f)" % d.em(centro))
	var r := d.raio_de("fornalha", Vector2i(2, 2))
	verificar(d.em(centro + Vector2(r * 0.5, 0)) < d.em(centro), "cai com a distância")
	perto(d.em(centro + Vector2(r + 6.0, 0)), 0.0, 1e-6, "fora do raio, quieto")
	igual(d.raio_de("painel_solar", Vector2i(2, 2)), 0.0, "painel solar não faz barulho")
	# fumaça no ar: o chunk poluído deixa o capim cinza e conta no distúrbio
	var longe := centro + Vector2(200, 0)
	perto(d.fuligem(longe), 0.0, 1e-6, "ar limpo")
	pol.emitir(Vector2i(longe.floor()), 400.0)
	verificar(d.fuligem(longe) > 0.5, "ar sujo: fuligem (%.2f)" % d.fuligem(longe))
	verificar(d.em(longe) > 0.3 and d.em(longe) <= 0.61, "a fumaça perturba, menos que o barulho (%.2f)" % d.em(longe))


# ------------------------------------------------------------------ espécies que se adaptam
func test_pardelo_faz_ninho_no_poste() -> void:
	var w := _mundo()
	var p: Passaros = w.p
	var m: MapaOcupacao = w.m
	var nn: NinhosPassaros = w.nn
	var amb: AmbienteVivo = w.amb
	var c := _limpo(m, 2)
	var poste := m.colocar("poste_energia", c, 0)
	verificar(poste >= 0, "pôs o poste")
	var pc := Grade.centro_da_area(c, Vector2i.ONE, 0)
	var b := p._novo("pardelo", pc + Vector2(4, 0))
	b.estado = Passaros.E.POUSADO
	b.t = 1.0e6
	b.poleiros = []
	p.bandos[b.id] = b
	var cl := Clima.new(3)
	cl.ciclo = false
	cl.tempo_real = false
	cl.estacao = 0
	cl.hora = 0.45
	nn._d = nn._d.duplicate(true)
	nn._d.estruturas.chance_s = 1.0
	nn._d.chance_s = 0.0
	nn.tick(0.1, cl, pc)
	igual(nn.ninhos.size(), 1, "fez ninho no alto do poste")
	var n: Dictionary = nn.ninhos.values()[0]
	igual(int(n.get("estrutura", -1)), poste, "no poste")
	perto(float(n.alto), float(Registro.fauna.ninhos.estruturas.topo.poste_energia), 1e-3, "no alto do corpo do poste")
	var e0 := float(amb.encardido.get(poste, 0.0))
	for i in 100:
		nn.tick(6.0, cl, pc)
	verificar(float(amb.encardido.get(poste, 0.0)) > e0 + 0.05, "ocupado, o ninho suja o poste (%.3f)" % float(amb.encardido.get(poste, 0.0)))
	# o cobrico (não se adapta) não faz ninho em poste
	var w2 := _mundo()
	var c2 := _limpo(w2.m, 2)
	var poste2 := (w2.m as MapaOcupacao).colocar("poste_energia", c2, 0)
	var b2 := (w2.p as Passaros)._novo("cobrico", Grade.centro_da_area(c2, Vector2i.ONE, 0) + Vector2(3, 0))
	b2.estado = Passaros.E.POUSADO
	b2.t = 1.0e6
	b2.poleiros = []
	(w2.p as Passaros).bandos[b2.id] = b2
	var nn2: NinhosPassaros = w2.nn
	nn2._d = nn2._d.duplicate(true)
	nn2._d.estruturas.chance_s = 1.0
	nn2._d.chance_s = 0.0
	nn2.tick(0.1, cl, Grade.centro_da_area(c2, Vector2i.ONE, 0))
	igual(nn2.ninhos.size(), 0, "o cobrico não usa poste (%d)" % poste2)
	# tiraram o poste: o ninho cai
	m.estruturas.erase(poste)
	nn.eventos.clear()
	nn.tick(2.1, cl, pc)
	igual(nn.ninhos.size(), 0, "sem poste, sem ninho")
	verificar(nn.eventos.any(func(e): return e.tipo == "caiu"), "evento do ninho caindo")


func test_cabo_cortado_e_consertado() -> void:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var c := _limpo(m, 6)
	var poste := m.colocar("poste_energia", c, 0)
	var bomba := m.colocar("braco", c + Vector2i(3, 0), 0)
	Fiacao.ligar(m, poste, bomba)
	verificar(Fiacao.fios(m.estruturas[bomba]).has(poste), "ligados")
	verificar(Fiacao.cortar(m, poste, bomba), "roeu e partiu")
	verificar(not Fiacao.fios(m.estruturas[bomba]).has(poste) and not Fiacao.fios(m.estruturas[poste]).has(bomba),
			"a ligação saiu dos dois lados")
	Fiacao.ligar(m, poste, bomba)
	verificar(not Fiacao.fios(m.estruturas[bomba]).has(poste), "não religa sozinho")
	Fiacao.completar(m)
	Fiacao._procurar_fontes(m, bomba)
	verificar(not Fiacao.fios(m.estruturas[bomba]).has(poste), "nem procurando fonte")
	verificar(not Fiacao.cortar(m, poste, bomba), "cortar de novo não faz nada")
	igual(Fiacao.consertar(m, bomba), 1, "consertou: religou")
	verificar(Fiacao.fios(m.estruturas[bomba]).has(poste) and Fiacao.fios(m.estruturas[poste]).has(bomba), "voltou dos dois lados")
	verificar(not m.estruturas[bomba].has("cortados") and not m.estruturas[poste].has("cortados"), "sem marca")


func test_rato_roi_o_cabo_ate_partir() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var m: MapaOcupacao = w.m
	var k := _celula_boa(w)
	var casa := (Vector2(k) + Vector2(0.5, 0.5)) * 8.0
	var t := r.nova_toca(casa, "pardo")
	var cabo := {"chave": "1|2", "a": 1, "b": 2, "pos": casa + Vector2(4, 0), "alt": 0.4}
	r.cabos = func() -> Array: return [cabo]
	r._d = r._d.duplicate(true)
	r._d.roer.chance = 1.0
	r._d.roer.roer_s = [1.0, 1.5]
	var roeu := 0
	var cortou := {}
	var foi := false
	for i in int(400.0 / 0.05):
		r.tick(0.05, null, casa)
		for e in r.eventos:
			if e.tipo == "roeu":
				roeu += 1
			elif e.tipo == "cortou":
				cortou = e
		for x in r.ratos.values():
			if String(x.get("roer", "")) != "" and (x.pos as Vector2).distance_to(cabo.pos) < 0.3:
				foi = true
		if not cortou.is_empty():
			break
	verificar(foi, "o rato foi até a ponta baixa do cabo")
	igual(roeu, 3, "rói em 3 sessões")
	igual(int(cortou.get("a", -1)), 1, "e parte o cabo (evento com as duas pontas)")
	igual(int(cortou.get("b", -1)), 2, "ponta b")
	verificar(not r.desgaste.has("1|2"), "o desgaste zera depois de partir")
	# cabo alto (poste a poste) ou lugar barulhento: não rói
	var w2 := _mundo()
	var r2: Ratos = w2.r
	r2._d = r2._d.duplicate(true)
	r2._d.roer.chance = 1.0
	var x := {"id": 1, "pos": casa, "toca": -1, "estado": Ratos.E.ANDANDO, "comida": -1, "carga": "", "fome": 0.0}
	r2.cabos = func() -> Array: return [{"chave": "1|2", "a": 1, "b": 2, "pos": casa + Vector2(3, 0), "alt": 2.2}]
	verificar(not r2._ir_roer(x, casa, 12.0), "cabo lá no alto: não alcança")
	r2.cabos = func() -> Array: return [cabo]
	(w2.eco as Ecossistema).fonte_disturbio = func(q: Vector2) -> float: return 0.9
	verificar(not r2._ir_roer(x, casa, 12.0), "do lado de máquina barulhenta: não vai")
	(w2.eco as Ecossistema).fonte_disturbio = Callable()
	r2._d.roer.liga = false
	verificar(not r2._ir_roer(x, casa, 12.0), "desligado no fauna.json: não rói")
	verificar(t > 0, "toca")
