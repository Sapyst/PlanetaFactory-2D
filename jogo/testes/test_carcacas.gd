extends Caso
## Patch fauna, fase 4 (docs/PLANO_FAUNA.md): o ciclo da morte — carcaça que apodrece em etapas e aduba o chão,
## aranha que vira sucata (óleo, ferrugem, afunda), moscas em volta da carne, planador que desce por cima, corpo que
## fica no lugar (o mesmo nó da morte) e é recriado ao carregar.

const DT := 1.0 / 30.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var eco := Ecossistema.new(g, m, amb)
	var c := Carcacas.new(eco, amb, 3)
	return {"g": g, "m": m, "amb": amb, "eco": eco, "c": c}


func _raiz() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## Avança o mundo (o Ecossistema envelhece a comida; Carcacas lê os eventos dele).
func _passar(w: Dictionary, s: float, passo := 1.0) -> void:
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var n := int(ceil(s / passo))
	for i in n:
		eco.tick(passo, eco.foco)
		c.tick(passo)


func _carcacas(eco: Ecossistema) -> Array:
	return eco.comida.values().filter(func(f): return f.tipo == "carcaca")


func test_larva_fica_e_apodrece_em_etapas() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var p := Vector2(12.3, -7.6)
	eco.morreu("alien", "larva", p, {"id": 44})
	_passar(w, 1.0)
	var cs := _carcacas(eco)
	igual(cs.size(), 1, "a larva morta virou carcaça")
	if cs.is_empty():
		return
	var f: Dictionary = cs[0]
	igual(String(f.especie), "larva", "espécie")
	igual(f.bicho, 44, "sabe de qual bicho é (o desenho adota o nó da morte)")
	verificar((f.pos as Vector2).distance_to(p) < 0.01, "no lugar onde morreu")
	var vida := float(f.vida)
	var base := float(Registro.fauna.carcacas.tipos.larva.vida_s)
	verificar(vida > base * 0.8 and vida < base * 1.2, "vida perto da do tipo (%.0f)" % vida)
	igual(c.etapa(f), Carcacas.Etapa.INTEIRO, "começa inteira")
	_passar(w, vida * 0.5, 5.0)
	igual(c.etapa(f), Carcacas.Etapa.INCHADO, "no meio da vida, inchada")
	verificar(c.moscas(f) > 0.9, "inchada: o auge das moscas (%.2f)" % c.moscas(f))
	_passar(w, vida * 0.3, 5.0)
	igual(c.etapa(f), Carcacas.Etapa.RESTOS, "perto do fim, restos")
	verificar(c.moscas(f) < 0.3, "restos: quase nenhuma mosca")
	verificar(c.com_carne(p, 5.0).is_empty(), "restos não contam como carne para o carniceiro")
	igual(eco.fertil_em(Vector2i(p.floor())), 0.0, "o chão ainda não foi adubado")
	var apodreceu := false
	for i in int(vida * 0.3):
		eco.tick(1.0, eco.foco)
		c.tick(1.0)
		apodreceu = apodreceu or eco.eventos.any(func(ev): return ev.tipo == "apodreceu" and ev.comida == "carcaca")
	verificar(apodreceu, "avisou que apodreceu")
	igual(_carcacas(eco).size(), 0, "sumiu")
	verificar(eco.fertil_em(Vector2i(p.floor())) > 0.5, "o chão embaixo ficou adubado (%.2f)" % eco.fertil_em(Vector2i(p.floor())))
	verificar(eco.fertil_em(Vector2i(p.floor()) + Vector2i(1, 0)) > 0.2, "em volta também")
	igual(eco.fertil_em(Vector2i(p.floor()) + Vector2i(4, 0)), 0.0, "longe não")
	# o adubo some devagar
	var antes := eco.fertil_em(Vector2i(p.floor()))
	for i in 100:
		eco.envelhecer(10.0)
	verificar(eco.fertil_em(Vector2i(p.floor())) < antes, "o adubo vai sumindo")
	verificar(eco.saude_tile(Vector2i(p.floor())) >= 0.0, "saúde continua válida")


func test_aranha_vira_sucata_com_oleo() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var amb: AmbienteVivo = w.amb
	var p := Vector2(3.5, 4.5)
	eco.morreu("alien", "aranha", p, {"id": 7})
	_passar(w, 1.0)
	igual(c.sucatas.size(), 1, "a aranha morta virou sucata")
	igual(_carcacas(eco).size(), 0, "sucata não é carne")
	if c.sucatas.is_empty():
		return
	var s: Dictionary = c.sucatas[0]
	igual(s.bicho, 7, "sabe de qual aranha é")
	verificar(amb.valor(Vector2i(p.floor()), AmbienteVivo.OLEO) > 0.2, "vazou óleo da hidráulica no chão")
	verificar(amb.valor(Vector2i(p.floor()) + Vector2i(1, 0), AmbienteVivo.OLEO) > 0.0, "um pouco em volta")
	igual(c.moscas(s), 0.0, "máquina não dá mosca")
	_passar(w, float(s.vida) + 2.0, 10.0)
	igual(c.sucatas.size(), 0, "no fim da vida, a sucata some")
	igual(eco.fertil_em(Vector2i(p.floor())), 0.0, "sucata não aduba")


func test_especie_sem_corpo_e_limite() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	igual(c.morreu("fantasma", Vector2.ZERO), 0, "espécie fora da lista: sem corpo")
	verificar(Carcacas.fica_corpo("larva") and Carcacas.fica_corpo("aranha"), "larva e aranha deixam corpo")
	verificar(not Carcacas.fica_corpo("fantasma"), "o resto não")
	var mx := int(Registro.fauna.carcacas.tipos.larva.max)
	for i in mx + 3:
		c.morreu("larva", Vector2(i, 0), i)
		eco.envelhecer(1.0)
	var vivas := _carcacas(eco).filter(func(f): return float(f.idade) < float(f.vida) - 9.0)
	verificar(vivas.size() <= mx, "não passa do máximo: as mais velhas vão sumindo (%d)" % vivas.size())
	var mxa := int(Registro.fauna.carcacas.tipos.aranha.max)
	for i in mxa + 2:
		c.morreu("aranha", Vector2(0, i), 100 + i)
		c.tick(1.0)
	var inteiras := c.sucatas.filter(func(s): return float(s.idade) < float(s.vida) - 9.0)
	verificar(inteiras.size() <= mxa, "sucata também tem máximo (%d)" % inteiras.size())


func test_planador_desce_sobre_a_carne() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var pa := Passaros.new(w.g, w.m, w.amb)
	pa.eco = eco
	pa.carcacas = c
	var carne := Vector2(30, 10)
	c.morreu("larva", carne, 1)
	var b := {"id": 1, "especie": "planador", "pos": Vector2(0, 0), "centro": Vector2(0, 0), "raio": 14.0, "ang": 0.0,
			"alt": 22.0, "alt_alvo": 22.0}
	for i in 30 * 20:
		pa._carniceiro(b, DT, false)
	verificar((b.centro as Vector2).distance_to(carne) < 5.0, "o centro do giro foi para cima da carcaça (%.1f)" % (b.centro as Vector2).distance_to(carne))
	perto(float(b.raio), float(Registro.fauna.carcacas.carniceiro.giro), 0.5, "fecha a volta")
	perto(float(b.alt_alvo), float(Registro.fauna.carcacas.carniceiro.alt), 0.5, "desce")
	# a noite (ou a carcaça seca) manda de volta ao giro alto
	for i in 30 * 20:
		pa._carniceiro(b, DT, true)
	perto(float(b.raio), 14.0, 0.1, "volta ao raio de antes")
	perto(float(b.alt_alvo), 22.0, 0.1, "e à altura de antes")
	verificar(not b.has("raio0"), "esquece o giro guardado")
	# carne longe demais: nem liga
	var b2 := {"id": 2, "especie": "planador", "pos": Vector2(0, 0), "centro": Vector2(-200, 0), "raio": 14.0, "ang": 0.0,
			"alt": 22.0, "alt_alvo": 22.0}
	for i in 30 * 5:
		pa._carniceiro(b2, DT, false)
	perto(float(b2.raio), 14.0, 0.01, "longe: continua no giro dele")


func test_adubo_puxa_semente_e_cogumelo() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var amb: AmbienteVivo = w.amb
	# um lugar saudável com chão livre
	var alvo := Vector2i.ZERO
	for y in range(-80, 81, 4):
		for x in range(-80, 81, 4):
			var t := Vector2i(x, y)
			if alvo == Vector2i.ZERO and amb.pode_plantar(t) and eco.saude(t) >= 0.4:
				alvo = t
	verificar(alvo != Vector2i.ZERO, "achou chão bom")
	eco.adubar(Vector2(alvo) + Vector2(0.5, 0.5), 1.6, 0.9)
	var p := PlantasReagem.new(eco, 5)
	var n := 0
	for i in 20:
		n += p.brotar(Vector2(alvo))
	var no_adubo := p.cogumelos.filter(func(cg): return eco.fertil_em(Vector2i((cg.pos as Vector2).floor())) > 0.0).size()
	verificar(no_adubo > 0, "cogumelo brotou no chão adubado (%d de %d)" % [no_adubo, p.cogumelos.size()])


func test_salva_e_volta() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	c.morreu("aranha", Vector2(1, 1), 5)
	c.morreu("larva", Vector2(2, 2), 6)
	eco.adubar(Vector2(9, 9), 1.5, 0.7)
	_passar(w, 30.0)
	var w2 := _mundo()
	(w2.eco as Ecossistema).restaurar(str_to_var(var_to_str(eco.estado())))
	(w2.c as Carcacas).restaurar(str_to_var(var_to_str(c.estado())))
	igual((w2.c as Carcacas).sucatas.size(), 1, "sucata vai no save")
	igual(_carcacas(w2.eco).size(), 1, "carcaça vai no save (é comida do Ecossistema)")
	perto(float((w2.c as Carcacas).sucatas[0].idade), float(c.sucatas[0].idade), 0.01, "com a idade")
	perto((w2.eco as Ecossistema).fertil_em(Vector2i(9, 9)), eco.fertil_em(Vector2i(9, 9)), 1e-4, "o adubo também")


func test_moscas_de_dia_em_volta_da_carne() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var p := Vector2(5.5, 5.5)
	c.morreu("larva", p, 1)
	var f: Dictionary = _carcacas(eco)[0]
	f.idade = float(f.vida) * 0.45                          # inchada
	eco.tick(DT, p)
	var cl := Clima.new(3)
	cl.ciclo = false
	cl.tempo_real = false
	cl.estacao = 1
	cl.hora = 0.45
	cl.forcar("limpo", true)
	cl.restante = 1.0e9
	var d := DesenhoVidaPequena.new()
	d.eco = eco
	d.clima = cl
	d.carcacas = c
	d._d = Registro.fauna.get("vida_pequena", {})
	d._fatores()
	d._calcular()
	verificar(d.moscas.size() >= 6, "moscas em volta da carcaça inchada (%d)" % d.moscas.size())
	var pousadas := 0
	for m in d.moscas:
		var q := Vector2(m.pos.x, -m.pos.z)
		verificar(q.distance_to(p) <= 1.0, "perto do corpo")
		verificar(float(m.pos.y) >= Grade.altura_em(q) + 0.05, "acima do chão")
		if m.pousada:
			pousadas += 1
	verificar(d._zumbido > 0.5, "zumbido perto (%.2f)" % d._zumbido)
	cl.hora = 0.02
	d._fatores()
	d._calcular()
	igual(d.moscas.size(), 0, "de noite, nenhuma")
	cl.hora = 0.45
	cl.estacao = 3
	d._fatores()
	d._calcular()
	igual(d.moscas.size(), 0, "no inverno, nenhuma")
	d.free()


func test_corpo_fica_e_e_adotado() -> void:
	var w := _mundo()
	var eco: Ecossistema = w.eco
	var c: Carcacas = w.c
	var dc := DesenhoCarcacas.new()
	dc.carcacas = c
	dc.eco = eco
	_raiz().add_child(dc)
	# a aranha morre: o mesmo nó para na pose final e é adotado
	var ar := Aranha.new(Vector3(4, 0, -4))
	_raiz().add_child(ar)
	ar.fica = true
	ar.set_meta("bicho", 11)
	DesenhoCarcacas.corpos[11] = ar
	ar.morrer()
	c.morreu("aranha", Vector2(4, 4), 11)
	for i in 30:
		ar._process(1.0 / 20.0)
	verificar(is_instance_valid(ar) and not ar.is_queued_for_deletion(), "o corpo não some")
	verificar(bool(ar.get_meta("pronta", false)), "parou na pose final")
	dc._process(DT)
	igual(dc.nos.size(), 1, "adotou")
	verificar(dc.nos.values()[0].no == ar, "o mesmo nó da morte (sem troca)")
	igual(ar.get_parent(), dc, "mudou de pai")
	# cada corpo com a própria cópia do material (fora da árvore a aranha não monta as peças: testa com uma caixa)
	var caixa := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sm := ShaderMaterial.new()
	bm.material = sm
	mi.mesh = bm
	caixa.add_child(mi)
	var mats := dc._materiais_unicos(caixa)
	igual(mats.size(), 1, "achou o material da superfície")
	verificar(mats[0] != sm and mi.get_surface_override_material(0) == mats[0], "cópia própria, posta por cima")
	caixa.free()
	# envelhece: a ferrugem sobe
	c.sucatas[0].idade = float(c.sucatas[0].vida) * 0.5
	dc._process(DT)
	verificar(float(ar.get_meta("ferrugem", 0.0)) > 0.5, "enferrujou (%.2f)" % float(ar.get_meta("ferrugem", 0.0)))
	# carregar o jogo: a carcaça de larva é recriada já morta
	c.morreu("larva", Vector2(-3, 2), 99)
	var fl: Dictionary = _carcacas(eco)[0]
	dc._process(DT)
	igual(dc.nos.size(), 1, "recém-morta: espera o nó da morte")
	fl.idade = 30.0
	dc._process(DT)
	igual(dc.nos.size(), 2, "sem nó da morte (carregou): recriou")
	var nl: Node3D = dc.nos["c%d" % int(fl.id)].no
	verificar(nl is Larva, "é uma larva")
	verificar(nl.scale.y < 0.6, "murcha (achatada)")
	# inchada cresce, restos achatam
	fl.idade = float(fl.vida) * 0.6
	dc._process(DT)
	var inchada := nl.scale.y
	fl.idade = float(fl.vida) * 0.95
	dc._process(DT)
	verificar(inchada > nl.scale.y * 2.0, "inchada mais alta que os restos (%.2f, %.2f)" % [inchada, nl.scale.y])
	verificar(float(nl.get_meta("podre", 0.0)) > 0.8, "restos: podre perto de 1")
	# a carcaça some: o nó some junto
	eco.comida.erase(int(fl.id))
	c.sucatas.clear()
	dc._process(DT)
	igual(dc.nos.size(), 0, "sem corpo na lógica, sem nó")
	dc.queue_free()
