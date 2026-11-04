extends Caso
## Poluição (emite, espalha, o chão absorve) e a colônia: ninhos do mapa, poluição vira aranha, grupo ataca a
## fonte, muro no caminho é mordido, torre derruba aranhas e ninho, expansão constrói ninho novo.

func _base() -> Array:
	var m := MapaOcupacao.new(GeradorMundo.new(1337))
	var p := Poluicao.new(m.gerador)
	return [m, p, Colonia.new(m, p, 3)]


func test_poluicao_espalha_e_some() -> void:
	var p: Poluicao = _base()[1]
	p.emitir(Vector2i(5, 5), 500.0)
	for i in 10:
		p.tick(1.0)
	verificar(p.em_chunk(Vector2i(1, 0)) > 0.0, "vazou para o chunk vizinho")
	verificar(p.em_chunk(Vector2i(0, 0)) > p.em_chunk(Vector2i(1, 0)), "a fonte continua mais suja")
	var t10 := p.total()
	verificar(t10 < 500.0, "o chão absorve (%.1f de 500)" % t10)
	for i in 3000:
		p.tick(1.0)
	verificar(p.total() < 1.0, "sem fonte, a nuvem some (%.2f)" % p.total())
	# fonte constante: equilíbrio, não cresce para sempre
	var q: Poluicao = _base()[1]
	var tot := []
	for i in 2400:
		q.emitir(Vector2i(5, 5), 0.75)
		q.tick(1.0)
		if i % 600 == 599:
			tot.append(q.total())
	verificar(tot[3] < tot[2] * 1.05, "fonte constante tende a equilíbrio (%s)" % str(tot))


func test_ninhos_do_mapa() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-6, 7):
		for y in range(-6, 7):
			c.descobrir_chunk(Vector2i(x, y))
	verificar(c.ninhos.size() >= 10, "vários ninhos num raio de ~200 tiles (%d)" % c.ninhos.size())
	var mais_perto := INF
	for id in c.ninhos:
		mais_perto = minf(mais_perto, c.ninhos[id].centro.length())
		igual(m.estruturas[id].nome, Colonia.toca_de(c.ninhos[id].especie), "toca ocupa o mapa")
	verificar(mais_perto >= 52.0, "nenhum ninho perto do spawn (%.0f)" % mais_perto)
	# determinístico: outra colônia com o mesmo mundo acha os mesmos lugares
	var b2 := _base()
	var c2: Colonia = b2[2]
	for x in range(-6, 7):
		for y in range(-6, 7):
			c2.descobrir_chunk(Vector2i(x, y))
	igual(c2.ninhos.size(), c.ninhos.size(), "mesma semente, mesmos ninhos")
	# o jogador não remove ninho com a ferramenta
	var con := Construtor.new(m)
	var n: Dictionary = c.ninhos.values()[0]
	var pl := con.plano_remocao(Vector2i(n.centro.floor()), Vector2i(n.centro.floor()))
	igual(pl[0].motivo, "inimigo")


## Cenário (dentro do quadrado seco do spawn): fábrica (fonte) em x = −34, ninho em x = 30, ~65 tiles.
func _cenario() -> Array:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-38, 37):
		for y in range(-6, 8):
			m.limpar_obstaculo(Vector2i(x, y))
	var fonte := m.colocar("fornalha", Vector2i(-34, 0), 0)
	var ninho := c._criar_ninho(Vector2i(30, 0), 1.0)
	return [m, b[1], c, fonte, ninho]


func test_poluicao_vira_ataque() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var p: Poluicao = s[1]
	var c: Colonia = s[2]
	var fonte: int = s[3]
	var fontes: Array[Dictionary] = [{"id": fonte, "pos": Vector2(-33, 1)}]
	var atacou := false
	var destruiu := false
	var nasceram := 0
	for i in 30 * 400:
		if i % 30 == 0:
			p.emitir(Vector2i(31, 1), 6.0)               # nuvem chegando ao ninho
		p.tick(1.0 / 30.0)
		c.tick(1.0 / 30.0, fontes)
		for e in c.eventos:
			if e.tipo == "aranha_nova": nasceram += 1
			if e.tipo == "ataque": atacou = true
			if e.tipo == "destruida" and e.id == fonte: destruiu = true
		if destruiu:
			break
	verificar(nasceram >= 4, "poluição absorvida virou aranhas (%d)" % nasceram)
	verificar(atacou, "grupo saiu para atacar")
	verificar(destruiu, "a fornalha (fonte) foi destruída")
	verificar(not m.estruturas.has(fonte), "e saiu do mapa")


func test_muro_no_caminho_e_esteira_por_baixo() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var c: Colonia = s[2]
	var fonte: int = s[3]
	# muro atravessando o caminho (x = −10) e uma esteira (baixa) em x = 10
	var muros: Array[int] = []
	for y in range(-6, 8):
		muros.append(m.colocar("muro_centro", Vector2i(-10, y), 0))
	var est := m.colocar("esteira_reta", Vector2i(10, 1), 0)
	for k in 4:
		var a := c._nova_aranha(s[4])
		c.aranhas[a].estado = Colonia.E.ATACANDO
		c.aranhas[a].alvo = fonte
	var mordeu_muro := false
	var fontes: Array[Dictionary] = [{"id": fonte, "pos": Vector2(-33, 1)}]
	for i in 30 * 120:
		c.tick(1.0 / 30.0, fontes)
		for e in c.eventos:
			if e.tipo == "destruida" and e.id in muros: mordeu_muro = true
	verificar(mordeu_muro, "muro no caminho foi derrubado")
	verificar(m.estruturas.has(est), "esteira (baixa) ficou: as aranhas passam por cima")
	verificar(not m.estruturas.has(fonte), "depois do muro chegaram à fonte")


func test_torre_defende() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var c: Colonia = s[2]
	var fonte: int = s[3]
	var torre := m.colocar("torre_defesa", Vector2i(-28, 0), 0)
	verificar(torre >= 0)
	for k in 4:
		var a := c._nova_aranha(s[4])
		c.aranhas[a].estado = Colonia.E.ATACANDO
		c.aranhas[a].alvo = fonte
	var tiros := 0
	var mortas := 0
	var fontes: Array[Dictionary] = [{"id": fonte, "pos": Vector2(-33, 1)}]
	for i in 30 * 90:
		c.tick(1.0 / 30.0, fontes)
		for e in c.eventos:
			if e.tipo == "tiro": tiros += 1
			if e.tipo == "aranha_morta": mortas += 1
	igual(mortas, 4, "torre matou as 4")
	verificar(m.estruturas.has(fonte), "a fornalha sobreviveu")
	igual(c.torres[torre].municao, 60 - tiros, "cada tiro gasta munição")
	# sem munição não atira
	c.torres[torre].municao = 0
	var a := c._nova_aranha(s[4])
	c.aranhas[a].pos = Vector2(-20, 1)
	c.tick(0.5, fontes)
	igual(c.eventos.filter(func(e): return e.tipo == "tiro").size(), 0, "sem munição, sem tiro")


func test_torre_derruba_ninho() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-2, 16):
		for y in range(-4, 6):
			m.limpar_obstaculo(Vector2i(x, y))
	var ninho := c._criar_ninho(Vector2i(12, 0), 1.0)
	var torre := m.colocar("torre_defesa", Vector2i(0, 0), 0)
	c.torres[torre] = {"municao": 200, "recarga": 0.0, "mira": Vector2.ZERO, "mirando": false}
	for i in 30 * 40:
		c.tick(1.0 / 30.0, [] as Array[Dictionary])
	verificar(not c.ninhos.has(ninho), "ninho no alcance caiu")
	verificar(not m.estruturas.has(ninho), "e saiu do mapa")


func test_expansao_constroi_ninho() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	var ninho := -1
	for x in range(-120, -60):
		if ninho >= 0:
			break
		for y in range(40, 100, 3):
			if m.motivo_bloqueio("ninho_aranha", Vector2i(x, y), 0) == "":
				ninho = c._criar_ninho(Vector2i(x, y), 1.0)
				break
	verificar(ninho >= 0, "ninho de teste")
	for k in 3:
		c._nova_aranha(ninho)
	c._t_expansao = 0.0
	c.ninhos[ninho].absorvido = 100.0          # ninho "irritado" pela poluição
	var antes := c.ninhos.size()
	var pronto := false
	for i in 30 * 80:
		c.tick(1.0 / 30.0, [] as Array[Dictionary])
		for e in c.eventos:
			if e.tipo == "ninho_pronto": pronto = true
	igual(c.ninhos.size(), antes + 1, "construíram um ninho novo")
	verificar(pronto, "a obra terminou")
	for id in c.ninhos:
		if id != ninho:
			var d: float = c.ninhos[id].centro.distance_to(c.ninhos[ninho].centro)
			verificar(d >= 12.0 and d <= 33.0, "a 14–30 tiles do ninho de origem (%.1f)" % d)


func test_aranha_presa_desiste() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	for x in range(-6, 30):
		for y in range(-6, 8):
			m.limpar_obstaculo(Vector2i(x, y))
	var ninho := c._criar_ninho(Vector2i(20, 0), 1.0)
	# aranha construtora num cercado de muro (só ataque abre caminho mordendo; construtora fica presa)
	for x in range(-3, 4):
		for y in range(-3, 4):
			if maxi(absi(x), absi(y)) == 3:
				m.colocar("muro_centro", Vector2i(x, y), 0)
	var a := c._nova_aranha(ninho)
	c.aranhas[a].pos = Vector2(0.5, 0.5)
	c.aranhas[a].estado = Colonia.E.CONSTRUINDO
	c.aranhas[a].destino = Vector2(-20, 0)
	c.aranhas[a].obra_em = Vector2i(-21, -1)
	var virou := false
	var sumiu := false
	for i in 30 * 40:
		c.tick(1.0 / 30.0, [] as Array[Dictionary])
		if c.aranhas.has(a) and c.aranhas[a].estado == Colonia.E.VOLTANDO:
			virou = true
		if not c.aranhas.has(a):
			sumiu = true
			break
	verificar(virou, "presa ~15 s, desiste da obra e tenta voltar")
	verificar(sumiu, "presa de novo voltando, some (volta ao ninho por baixo da terra)")


func test_sem_poluicao_nao_expande() -> void:
	var b := _base()
	var m: MapaOcupacao = b[0]
	var c: Colonia = b[2]
	var ninho := -1
	for x in range(-120, -60):
		if ninho >= 0:
			break
		for y in range(40, 100, 3):
			if m.motivo_bloqueio("ninho_aranha", Vector2i(x, y), 0) == "":
				ninho = c._criar_ninho(Vector2i(x, y), 1.0)
				break
	for k in 4:
		c._nova_aranha(ninho)
	c._t_expansao = 0.0
	for i in 30 * 30:
		c.tick(1.0 / 30.0, [] as Array[Dictionary])
	igual(c.ninhos.size(), 1, "ninho sem poluição não manda construtoras")


func test_aranha_nunca_entra_em_construcao() -> void:
	var s := _cenario()
	var m: MapaOcupacao = s[0]
	var c: Colonia = s[2]
	var fonte: int = s[3]
	# obstáculos no caminho: máquinas e um muro com fresta
	for y in [-4, -1, 2, 5]:
		m.colocar("fornalha", Vector2i(-18, y), 0)
	for k in 6:
		var a := c._nova_aranha(s[4])
		c.aranhas[a].estado = Colonia.E.ATACANDO
		c.aranhas[a].alvo = fonte
	var fontes: Array[Dictionary] = [{"id": fonte, "pos": Vector2(-33, 1)}]
	var dentro := 0
	for i in 30 * 90:
		c.tick(1.0 / 30.0, fontes)
		for id in c.aranhas:
			var p: Vector2 = c.aranhas[id].pos
			if c._bloqueio(Vector2i(p.floor())) >= 0:
				dentro += 1
	igual(dentro, 0, "o centro de uma aranha nunca está dentro de construção")


## Melhoria pesquisada (Pesquisa.bonus) aumenta o dano: menos tiros para matar a mesma aranha.
func test_torre_com_melhoria_de_dano() -> void:
	var tiros := []
	for b in [0.0, 1.0]:
		var s := _cenario()
		var m: MapaOcupacao = s[0]
		var c: Colonia = s[2]
		var fonte: int = s[3]
		var bonus_energia: float = b
		c.bonus = func(chave: String) -> float: return bonus_energia if chave == "dano_torre_energia" else 0.0
		c.torre_energia = func(_id: int, _mj: float) -> bool: return true          # sempre com energia guardada
		m.colocar("torre_defesa", Vector2i(-28, 0), 0)
		var a := c._nova_aranha(s[4])
		c.aranhas[a].estado = Colonia.E.ATACANDO
		c.aranhas[a].alvo = fonte
		var n := 0
		var fontes: Array[Dictionary] = [{"id": fonte, "pos": Vector2(-33, 1)}]
		for i in 30 * 60:
			c.tick(1.0 / 30.0, fontes)
			for e in c.eventos:
				if e.tipo == "tiro": n += 1
			if not c.aranhas.has(a):
				break
		verificar(not c.aranhas.has(a), "aranha morreu (bônus %s)" % b)
		tiros.append(n)
	verificar(tiros[1] < tiros[0], "com +100%% de dano precisa de menos tiros (%d < %d)" % [tiros[1], tiros[0]])


## Cadência da torre de energia (cadencia_energia_1/2): mais tiros no mesmo tempo; e −10% de energia por tiro.
func test_torre_com_melhoria_de_cadencia() -> void:
	var tiros := []
	var gasto := []
	for b in [0.0, 1.0]:
		var s := _cenario()
		var m: MapaOcupacao = s[0]
		var c: Colonia = s[2]
		var fonte: int = s[3]
		var bonus_cad: float = b
		c.bonus = func(chave: String) -> float:
			return bonus_cad if chave == "cadencia_torre_energia" else (0.1 if chave == "economia_tiro_torre" and bonus_cad > 0.0 else 0.0)
		var mjs := []
		c.torre_energia = func(_id: int, mj: float) -> bool:
			mjs.append(mj)
			return true
		m.colocar("torre_defesa", Vector2i(-28, 0), 0)
		var a := c._nova_aranha(s[4])
		c.aranhas[a].estado = Colonia.E.ATACANDO
		c.aranhas[a].alvo = fonte
		c.aranhas[a].pos = Vector2(-31, 1)
		var n := 0
		for i in 30 * 2:
			c.aranhas[a].vida = 1e9                     # não morre: conta só a cadência
			c.aranhas[a].pos = Vector2(-31, 1)
			c.tick(1.0 / 30.0, [])
			for e in c.eventos:
				if e.tipo == "tiro": n += 1
		tiros.append(n)
		gasto.append(mjs[0] if not mjs.is_empty() else 0.0)
	verificar(tiros[0] > 0, "torre atirou (%d tiros em 2 s)" % tiros[0])
	verificar(tiros[1] >= tiros[0] * 3 / 2, "com +100%% de cadência atira bem mais (%d × %d; recarga anda em passos de 1/30 s)" % [tiros[1], tiros[0]])
	var base := float(Registro.estruturas.torre_defesa.tiro_mj)
	perto(gasto[0], base, 1e-6, "tiro normal gasta %.3f MJ" % base)
	perto(gasto[1], base * 0.9, 1e-6, "com a melhoria, −10% de energia por tiro")
