extends Caso
## Desempenho (2026-11-11): o desenho dos itens guarda por caminho a altura do chão de cada tile e o arco de cada curva.
## O guardado tem que dar exatamente o mesmo ponto que Fabrica.ponto_no_tile e a mesma altura que Grade.altura_chao,
## e ser refeito quando a Fabrica remonta ou o nível de um tile muda.


func _fabrica() -> Array:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	for x in range(-20, 20):
		for y in range(-20, 20):
			m.limpar_obstaculo(Vector2i(x, y))
	var f := Fabrica.new(m)
	var c := Construtor.new(m)
	c.executar(c.plano_linha("esteira", Vector2i(-10, 0), Vector2i(5, 0), 0))
	c.executar(c.plano_linha("esteira", Vector2i(6, 0), Vector2i(6, 8), 0))
	c.executar(c.plano_linha("esteira", Vector2i(7, 8), Vector2i(12, 8), 0))
	c.executar(c.plano_linha("esteira", Vector2i(-5, -10), Vector2i(-5, -3), 0))
	f.reconstruir()
	return [g, m, f]


func test_igual_ao_calculo_direto() -> void:
	var antes := Grade.gerador
	var b := _fabrica()
	var g: GeradorMundo = b[0]
	var f: Fabrica = b[2]
	Grade.gerador = g
	var d := DesenhoItens.new()
	d.fabrica = f
	verificar(f.caminhos.size() >= 2, "há caminhos (%d)" % f.caminhos.size())
	var curvas := 0
	var conferidos := 0
	for ci in f.caminhos.size():
		var c: Dictionary = f.caminhos[ci]
		var geo := d._geometria(ci, c)
		for k in c.tiles.size():
			var t: Vector2i = c.tiles[k]
			verificar(geo[2][k] == Grade.altura_chao(t), "altura do chão igual em %s" % t)
			var entra: int = c.entra[k]
			var sai: int = c.sai[k]
			if sai < 0 or sai == entra:
				continue
			curvas += 1
			for f_ in [0.0, 0.13, 0.5, 0.77, 0.9999]:
				var cv: Array = geo[3][k]
				var p := (cv[0] as Vector2) + Vector2.from_angle(float(cv[1]) + float(cv[2]) * f_) * 0.5
				verificar(p == Fabrica.ponto_no_tile(t, entra, sai, f_), "curva em %s, f=%.2f: mesmo ponto" % [t, f_])
				conferidos += 1
	verificar(curvas >= 2, "havia curvas (%d)" % curvas)
	verificar(conferidos >= 10, "pontos conferidos (%d)" % conferidos)
	# guardado: a mesma lista enquanto nada muda; refeita se o nível de um tile muda ou a fábrica remonta
	var g0 := d._geometria(0, f.caminhos[0])
	verificar(is_same(d._geometria(0, f.caminhos[0]), g0), "nada mudou: usa o guardado")
	g.aplainar(Vector2i(40, 40), 2)
	verificar(not is_same(d._geometria(0, f.caminhos[0]), g0), "nível mudou (aplainar): refaz")
	var g1 := d._geometria(0, f.caminhos[0])
	f.reconstruir()
	verificar(not is_same(d._geometria(0, f.caminhos[0]), g1), "fábrica remontou: refaz")
	d.free()
	Grade.gerador = antes
