extends Caso
## Convivência com ninhos (harmonia_ninhos), Simbiose, Mira automática, dano/alcance de artilharia 2.


func _base() -> Array:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var c := Colonia.new(m, Poluicao.new(m.gerador), 3)
	for x in range(-38, 60):
		for y in range(-20, 20):
			m.limpar_obstaculo(Vector2i(x, y))
	return [m, c]


func test_pesquisas() -> void:
	for id in ["harmonia_ninhos", "simbiose", "artilharia_automatica", "dano_artilharia_2", "alcance_artilharia_2", "escavar_canal"]:
		UtilLote11.pesquisa(self, id, "")
	var p := Pesquisa.new()
	p.concluidas = {"dano_artilharia_1": true, "dano_artilharia_2": true, "alcance_artilharia_1": true, "alcance_artilharia_2": true, "simbiose": true, "harmonia_ninhos": true}
	perto(p.bonus("dano_artilharia"), 0.7, 1e-6, "+30% e +40%")
	perto(p.bonus("alcance_artilharia"), 0.5, 1e-6, "+20% e +30%")
	perto(p.bonus("poluicao_global"), -0.5, 1e-6, "−50% de poluição")
	perto(p.bonus("grupos_ataque"), 0.25, 1e-6, "−25% de grupos")


func test_menos_grupos_de_ataque() -> void:
	var feitas := {}
	for reducao in [0.0, 0.25]:
		var b := _base()
		var c: Colonia = b[1]
		var n := c._criar_ninho(Vector2i(40, 8), 1.0)            # além do mínimo de 32 m
		c.bonus = func(k: String) -> float: return reducao if k == "grupos_ataque" else 0.0
		c.ninhos[n].raiva = float(c._n.get("custo_aranha", 16)) * 3.2
		var k0 := c.aranhas_do_ninho(n).size()
		for i in 10:
			c._ninhos(0.1, [])
		feitas[reducao] = c.aranhas_do_ninho(n).size() - k0 + 0.0
	verificar(float(feitas[0.0]) > float(feitas[0.25]), "aranhas 1/0,75 mais caras: menos grupos (%d contra %d)" % [feitas[0.0], feitas[0.25]])


func test_ninho_em_paz_nao_ataca() -> void:
	for paz in [false, true]:
		var b := _base()
		var m: MapaOcupacao = b[0]
		var c: Colonia = b[1]
		var fonte := m.colocar("fornalha", Vector2i(10, 0), 0)
		var n := c._criar_ninho(Vector2i(40, 8), 1.0)            # além do mínimo de 32 m
		for k in 6:
			c._nova_aranha(n)
		if paz:
			c.ninhos_paz = func() -> bool: return true
		c._ninhos(0.1, [{"id": fonte, "pos": Vector2(11, 1)}])
		var atacando := c.aranhas_do_ninho(n, Colonia.E.ATACANDO).size()
		if paz:
			igual(atacando, 0, "Simbiose: ninho sem fúria não manda grupo")
			c.ninhos[n].furia = 0.5
			c.ninhos[n].t_furia = 99.0
			c._ninhos(0.1, [{"id": fonte, "pos": Vector2(11, 1)}])
			verificar(c.aranhas_do_ninho(n, Colonia.E.ATACANDO).size() > 0, "furioso ataca")
		else:
			verificar(atacando > 0, "sem Simbiose, ataca")


func test_poluicao_global() -> void:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var p := Poluicao.new(m.gerador)
	p.emitir(Vector2i(0, 0), 10.0)
	perto(p.total(), 10.0, 1e-6, "normal")
	p.fator = 0.5
	p.emitir(Vector2i(0, 0), 10.0)
	perto(p.total(), 15.0, 1e-6, "Simbiose: metade")


func test_harmonia_nao_expande_rumo_a_fabrica() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[1]
	m.colocar("fornalha", Vector2i(0, 0), 0)
	var perto_f := Vector2(40, 0)
	var d0 := c.dist_fabrica(perto_f)
	for i in 30:
		var l := c._lugar_de_ninho(perto_f, true)
		if l != Vector2i(-99999, -99999):
			verificar(c.dist_fabrica(Vector2(l) + Vector2(1, 1)) >= d0 - 2.0, "o lugar novo não chega mais perto (%s)" % l)


func test_artilharia_so_com_ordem_ate_a_mira_automatica() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[1]
	var t := m.colocar("artilharia", Vector2i(0, 0), 0)
	var n := c._criar_ninho(Vector2i(40, 8), 1.0)            # além do mínimo de 32 m
	c.carregar_torre(t, 5)
	var auto := [false]
	c.artilharia_auto = func() -> bool: return auto[0]
	c._listas()
	c._torres(0.1)
	igual(int(c.torres[t].municao), 5, "sem a Mira automática e sem ordem: não atira")
	verificar(c.artilharia_espera_ordem(t), "espera ordem")
	c.ordenar_disparo(t)
	verificar(not c.artilharia_espera_ordem(t), "tem ordem")
	c._torres(0.1)
	igual(int(c.torres[t].municao), 4, "com ordem, atira")
	c.ninhos.erase(n)
	c._torres(0.1)
	verificar(not c.torres[t].has("ordem"), "sem ninho no alcance, a ordem acaba")
	var n2 := c._criar_ninho(Vector2i(44, 8), 1.0)
	c.torres[t].recarga = 0.0
	c._torres(0.1)
	igual(int(c.torres[t].municao), 4, "ninho novo: espera outra ordem")
	auto[0] = true
	c._torres(0.1)
	igual(int(c.torres[t].municao), 3, "com a Mira automática, sozinha")
	verificar(n2 >= 0, "ok")


func test_escavar_pede_a_pesquisa() -> void:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var o := UtilLote11.chao(m)
	m.colocar("terraplenagem", o, 0)
	var c := Construtor.new(m)
	c.pesquisa = Pesquisa.new()
	var a := o + Vector2i(6, 6)
	verificar(c.plano_aplainar(a, a, 1).all(func(it): return it.motivo == "sem_pesquisa_canal"), "sem pesquisa, não cava")
	verificar(c.plano_aplainar(a, a).all(func(it): return it.motivo == ""), "aplainar continua")
	verificar(Registro.menu.motivos.has("sem_pesquisa_canal"), "explica por quê")
	c.pesquisa.concluidas["escavar_canal"] = true
	verificar(c.plano_aplainar(a, a, 1).all(func(it): return it.motivo == ""), "com a pesquisa, cava")
