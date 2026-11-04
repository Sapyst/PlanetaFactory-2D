extends Caso
## Braço posto antes da broca (pedido de Sapyst): baú, braço e só depois a broca de carvão atrás dele. Quando a broca
## começa a soltar carvão, o braço pega e leva até o baú, sem travar segurando o item.

func _cenario() -> Dictionary:
	var g := GeradorMundo.new(1337)
	g.relevo_ativo = false
	var m := MapaOcupacao.new(g)
	var pos := Vector2i(9999, 9999)
	for x in range(-30, 30):
		for y in range(-30, 30):
			var t := Vector2i(x, y)
			var j := g.distribuicao.jazida(t)
			if not j.is_empty() and j.tipo == "jazida_carvao" and not g.distribuicao.jazida(t + Vector2i(1, 1)).is_empty():
				pos = t
				break
		if pos.x != 9999:
			break
	for x in range(pos.x - 4, pos.x + 12):
		for y in range(pos.y - 12, pos.y + 4):
			m.limpar_obstaculo(Vector2i(x, y))
	return {"mapa": m, "fabrica": Fabrica.new(m), "pos": pos}


func _rodar(f: Fabrica, s: float) -> void:
	for i in int(s * 30):
		f.tick(1.0 / 30.0)


func test_braco_antes_da_broca() -> void:
	var c := _cenario()
	var m: MapaOcupacao = c.mapa
	var f: Fabrica = c.fabrica
	var pos: Vector2i = c.pos
	verificar(pos.x != 9999, "achou jazida de carvão")
	print("BRACO pos=", pos, " motivo nucleo=", m.motivo_bloqueio("nucleo", pos + Vector2i(5, -6), 0), " bau=", m.motivo_bloqueio("bau", pos + Vector2i(0, -2), 0))
	var nuc := m.colocar("nucleo", pos + Vector2i(5, -6), 0)
	var bau := m.colocar("bau", pos + Vector2i(0, -2), 0)
	var braco := m.colocar("braco", pos + Vector2i(0, -1), Construtor.rot_do_fluxo(2))
	verificar(nuc >= 0 and bau >= 0 and braco >= 0, "núcleo, baú e braço (%s)" % m.motivo_bloqueio("braco", pos + Vector2i(0, -1), Construtor.rot_do_fluxo(2)))
	f.reconstruir()
	_rodar(f, 3.0)
	var broca := m.colocar("broca_minerio", pos, 0)
	verificar(broca >= 0, "broca depois (%s)" % m.motivo_bloqueio("broca_minerio", pos, 0))
	f.reconstruir()
	var b: Braco = f.bracos[braco]
	var travado := 0.0
	var entregues := 0
	for i in 60 * 30:
		f.tick(1.0 / 30.0)
		if b.segurando != "" and b.estado == Braco.Estado.ESPERANDO_DESTINO:
			travado += 1.0 / 30.0
	print("BRACO estado=%s segurando=%s energia=%.2f entregues=%d travado=%.1fs bau=%s rede_braco=%s" % [
		b.estado, b.segurando, b.energia, b.entregues, travado, f.baus.get(bau), f._membros.get(braco, {}).get("rede")])
	verificar(b.entregues > 0, "braço levou carvão ao baú")


## O mesmo, soltando numa esteira que leva ao núcleo (como na fábrica de Sapyst).
func test_braco_antes_da_broca_na_esteira() -> void:
	var c := _cenario()
	var m: MapaOcupacao = c.mapa
	var f: Fabrica = c.fabrica
	var pos: Vector2i = c.pos
	var con := Construtor.new(m)
	con.cobrar = false
	var nuc := m.colocar("nucleo", pos + Vector2i(5, -6), 0)
	con.executar(con.plano_linha("esteira", pos + Vector2i(0, -2), pos + Vector2i(4, -2), 1))
	var braco := m.colocar("braco", pos + Vector2i(0, -1), Construtor.rot_do_fluxo(2))
	verificar(nuc >= 0 and braco >= 0, "núcleo e braço")
	f.reconstruir()
	_rodar(f, 3.0)
	var broca := m.colocar("broca_minerio", pos, 0)
	verificar(broca >= 0, "broca depois")
	f.reconstruir()
	var b: Braco = f.bracos[braco]
	_rodar(f, 60.0)
	print("BRACO2 estado=%s segurando=%s energia=%.2f entregues=%d nucleo=%s" % [b.estado, b.segurando, b.energia, b.entregues, f.estoque_nucleo])
	verificar(b.entregues > 5, "braço continua levando carvão para a esteira")
