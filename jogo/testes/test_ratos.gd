extends Caso
## Patch fauna, fase 5 (docs/PLANO_FAUNA.md): ratos — tocas no mato, rotina de crepúsculo, comer fruto, enterrar
## semente (e a esquecida vira muda), medo e fuga para a toca, presa de aranha e larva (vira carcaça), trilha no chão.

const DT := 1.0 / 20.0


func _mundo() -> Dictionary:
	var g := GeradorMundo.new(1337)
	var m := MapaOcupacao.new(g)
	var amb := AmbienteVivo.new(g, m)
	var eco := Ecossistema.new(g, m, amb)
	var r := Ratos.new(eco, amb, 5)
	eco.registrar_fonte("rato", r.para_ecossistema)
	return {"g": g, "m": m, "amb": amb, "eco": eco, "r": r}


func _clima(hora: float, estacao := 1) -> Clima:
	var c := Clima.new(3)
	c.ciclo = false
	c.tempo_real = false
	c.estacao = estacao
	c.hora = hora
	c.forcar("limpo", true)
	c.restante = 1.0e9
	return c


## Um campo de mato saudável (lugar bom para toca).
func _campo(w: Dictionary) -> Vector2:
	var r: Ratos = w.r
	for y in range(-120, 121, 8):
		for x in range(-120, 121, 8):
			var t := Vector2i(x, y)
			var ok := true
			for k in 4:
				ok = ok and r.lugar_de_toca(t)
			if ok:
				return Vector2(t) + Vector2(0.5, 0.5)
	return Vector2.ZERO


func _rodar(w: Dictionary, s: float, cl: Clima, foco: Vector2) -> void:
	for i in int(s / DT):
		(w.eco as Ecossistema).tick(DT, foco)
		(w.r as Ratos).tick(DT, cl, foco)


func _fora(r: Ratos) -> int:
	return r.ratos.values().filter(func(x): return x.estado != Ratos.E.TOCA).size()


func test_tocas_nascem_no_mato() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var foco := _campo(w)
	verificar(foco != Vector2.ZERO, "achou mato bom")
	for i in 40:
		r._cuidar_tocas(foco)
	var n := r.tocas.size()
	verificar(n >= 2, "nasceram tocas (%d)" % n)
	verificar(n <= int(Registro.fauna.ratos.tocas_max), "até tocas_max")
	var lista: Array = r.tocas.values()
	for i in lista.size():
		var tc: Dictionary = lista[i]
		var tl := Vector2i((tc.pos as Vector2).floor())
		verificar((w.g as GeradorMundo).terreno(tl) == GeradorMundo.Terreno.TERRA, "em terra")
		verificar((w.eco as Ecossistema).saude(tl) >= float(Registro.fauna.ratos.saude_min) - 0.01, "em mato saudável")
		for j in range(i + 1, lista.size()):
			verificar((tc.pos as Vector2).distance_to(lista[j].pos) >= float(Registro.fauna.ratos.entre_tocas) - 0.01, "longe uma da outra")
	var faixa: Array = Registro.fauna.ratos.por_toca
	for tc in lista:
		var k := r.ratos.values().filter(func(x): return x.toca == tc.id).size()
		verificar(k >= int(faixa[0]) and k <= int(faixa[1]), "ratos por toca (%d)" % k)
	# construção encostada: a toca é abandonada
	var tc0: Dictionary = lista[0]
	(w.m as MapaOcupacao).tiles[Vector2i((tc0.pos as Vector2).floor()) + Vector2i(2, 0)] = 1
	r._cuidar_tocas(tc0.pos)
	verificar(not r.tocas.has(tc0.id), "construíram do lado: abandonou")
	verificar(not r.ratos.values().any(func(x): return x.toca == tc0.id), "e os ratos dela foram embora")


func test_crepusculo_e_noite_mais_que_meio_dia() -> void:
	var noite := _clima(0.02)
	var meio := _clima(0.45)
	var w := _mundo()
	var r: Ratos = w.r
	verificar(r.atividade(noite) > r.atividade(meio) * 2.0, "de noite saem bem mais (%.2f × %.2f)" % [r.atividade(noite), r.atividade(meio)])
	verificar(r.atividade(_clima(0.02, 3)) < r.atividade(noite), "no inverno, menos")
	var foco := _campo(w)
	r.nova_toca(foco)
	r.nova_toca(foco + Vector2(14, 0))
	var soma_n := 0
	for i in 60:
		_rodar(w, 1.0, noite, foco)
		soma_n += _fora(r)
	var w2 := _mundo()
	var r2: Ratos = w2.r
	r2.nova_toca(foco)
	r2.nova_toca(foco + Vector2(14, 0))
	var soma_d := 0
	for i in 60:
		_rodar(w2, 1.0, meio, foco)
		soma_d += _fora(r2)
	verificar(soma_n > soma_d, "mais ratos fora de noite do que ao meio-dia (%d × %d)" % [soma_n, soma_d])
	verificar(soma_n > 0, "à noite saem")


func test_come_fruto_perto_da_toca() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	var foco := _campo(w)
	r._d = r._d.duplicate()
	r._d.leva_chance = 0.0
	r.nova_toca(foco)
	var ids: Array = []
	for k in 4:
		var id := eco.por_comida("fruta", foco + Vector2(3.0 + k * 0.4, 1.0), 1.0)
		eco.comida[id].especie = "baga"
		eco.comida[id].fonte = ""
		ids.append(id)
	var comeu := 0
	var noite := _clima(0.02)
	for i in int(240 / DT):
		eco.tick(DT, foco)
		r.tick(DT, noite, foco)
		for ev in eco.eventos:
			if ev.tipo == "comeu" and ev.quem == "rato":
				comeu += 1
	verificar(comeu >= 1, "comeram fruto (%d)" % comeu)
	verificar(ids.filter(func(id): return eco.comida.has(id)).size() < 4, "sumiu fruto do chão")


func test_enterra_e_a_esquecida_vira_muda() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	var amb: AmbienteVivo = w.amb
	var foco := _campo(w)
	r._d = r._d.duplicate()
	r._d.leva_chance = 1.0
	r._d.esquece_chance = 1.0
	r._d.tocas_max = 1                                     # só a toca do teste
	r.nova_toca(foco)
	for k in 6:
		var id := eco.por_comida("fruta", foco + Vector2(2.5, -1.5 + k * 0.5), 1.0)
		eco.comida[id].especie = "bolota"
		eco.comida[id].fonte = "arv_carvalho"
	var noite := _clima(0.02)
	var enterrou := false
	for i in int(300 / DT):
		eco.tick(DT, foco)
		r.tick(DT, noite, foco)
		enterrou = enterrou or r.eventos.any(func(ev): return ev.tipo == "enterrou")
	verificar(enterrou, "levou a bolota e enterrou")
	verificar(r.enterradas >= 1, "conta as enterradas (%d)" % r.enterradas)
	verificar(r.mudas >= 1, "a esquecida virou muda (%d)" % r.mudas)
	verificar(amb.especies.values().has("arv_carvalho"), "muda de carvalho")
	for t in amb.plantas:
		verificar((Vector2(t) + Vector2(0.5, 0.5)).distance_to(foco) <= 9.8, "enterrou perto da toca (%.1f)" % (Vector2(t) + Vector2(0.5, 0.5)).distance_to(foco))


func test_foge_do_predador_e_morre_se_pego() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	var foco := _campo(w)
	var id_t := r.nova_toca(foco)
	var rato: Dictionary = r.ratos.values()[0]
	rato.estado = Ratos.E.ANDANDO
	rato.pos = foco + Vector2(4, 0)
	rato.alvo = foco + Vector2(7, 0)
	rato.t = 10.0
	var alien := [foco + Vector2(6.5, 0)]
	eco.registrar_fonte("alien", func() -> Array: return [{"id": 1, "pos": alien[0]}])
	eco.reindexar()
	r.tick(DT, _clima(0.02), foco)
	igual(int(rato.estado), Ratos.E.FUGINDO, "viu a aranha: foge")
	verificar(r.eventos.any(func(ev): return ev.tipo == "fugiu"), "evento fugiu")
	verificar((rato.alvo as Vector2).distance_to(foco) < 0.01, "corre para a toca (o perigo não está nela)")
	for i in int(6 / DT):
		r.tick(DT, _clima(0.02), foco)
	verificar(int(rato.estado) in [Ratos.E.ENTRANDO, Ratos.E.TOCA], "chegou e entrou")
	# outro é pego
	var outro: Dictionary = r.ratos.values()[1] if r.ratos.size() > 1 else r._novo_rato(id_t)
	outro.estado = Ratos.E.COMENDO
	outro.pos = alien[0] + Vector2(0.3, 0)
	outro.t = 5.0
	var n0 := r.ratos.size()
	var c := Carcacas.new(eco, w.amb, 1)
	r.tick(DT, _clima(0.02), foco)
	igual(r.ratos.size(), n0 - 1, "a aranha pegou: morreu")
	eco.tick(DT, foco)
	verificar(eco.eventos.any(func(ev): return ev.tipo == "morreu" and ev.especie == "rato"), "avisou o ecossistema")
	c.tick(DT)
	verificar(eco.comida.values().any(func(f): return f.tipo == "carcaca" and f.especie == "rato"), "virou carcaça (fase 4)")


func test_susto_e_fogo() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var foco := _campo(w)
	r.nova_toca(foco)
	var rato: Dictionary = r.ratos.values()[0]
	rato.estado = Ratos.E.FAREJANDO
	rato.pos = foco + Vector2(3, 3)
	rato.t = 5.0
	r.assustar(foco + Vector2(5, 3), 6.0)
	r.tick(DT, _clima(0.02), foco)
	igual(int(rato.estado), Ratos.E.FUGINDO, "tiro perto: foge")
	var amb: AmbienteVivo = w.amb
	rato.estado = Ratos.E.FAREJANDO
	rato.t = 5.0
	amb.fogo[Vector2i((rato.pos as Vector2).floor())] = 3.0
	var n0 := r.ratos.size()
	r.tick(DT, _clima(0.02), foco)
	igual(r.ratos.size(), n0 - 1, "no fogo, morre")


func test_longe_da_camera_ficam_dentro() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var foco := _campo(w)
	r.nova_toca(foco)
	for x in r.ratos.values():
		x.estado = Ratos.E.ANDANDO
		x.pos = foco + Vector2(2, 0)
		x.alvo = foco + Vector2(4, 0)
	r.tick(DT, _clima(0.02), foco + Vector2(200, 0))
	igual(_fora(r), 0, "longe: todos em casa, sem simular")


func test_trilha_e_save() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var foco := _campo(w)
	r.nova_toca(foco)
	var rato: Dictionary = r.ratos.values()[0]
	var p0 := (foco + Vector2(3, 0)).floor() + Vector2(0.5, 0.5)
	var tl := Vector2i((p0 * Ratos.TRILHA_RES).floor())
	for i in 40:
		rato.estado = Ratos.E.ANDANDO
		rato.pos = p0
		rato.alvo = rato.pos + Vector2(0.5, 0)
		rato.t = 10.0
		r._marcar_e_desmarcar(0.5)
	verificar(float(r.passagem.get(tl, 0.0)) > 0.8, "passou muito: trilha (%.2f)" % float(r.passagem.get(tl, 0.0)))
	var v := float(r.passagem[tl])
	rato.estado = Ratos.E.TOCA
	r._marcar_e_desmarcar(600.0)
	verificar(float(r.passagem.get(tl, 0.0)) < v, "sem passar, some devagar")
	var r2 := Ratos.new(w.eco, w.amb, 9)
	r2.restaurar(str_to_var(var_to_str(r.estado())))
	igual(r2.tocas.size(), r.tocas.size(), "tocas no save")
	igual(r2.ratos.size(), r.ratos.size(), "ratos no save")
	verificar(r2.ratos.values().all(func(x): return x.estado == Ratos.E.TOCA), "ao carregar, todos em casa")
	perto(float(r2.passagem.get(tl, 0.0)), float(r.passagem.get(tl, 0.0)), 1e-4, "trilha no save")


func test_especie_pelo_abrigo() -> void:
	var w := _mundo()
	var r: Ratos = w.r
	var eco: Ecossistema = w.eco
	r._d = r._d.duplicate()
	r._d.aberto_chance = 1.0
	var pardo := 0
	var saltador := 0
	for y in range(-120, 121, 3):
		for x in range(-120, 121, 3):
			var t := Vector2i(x, y)
			var esp := r.especie_de_toca(t)
			if esp == "":
				continue
			var c := Vector2(t) + Vector2(0.5, 0.5)
			var abrigo := not eco.arbustos_perto(c, 3.0).is_empty() or not eco.arvores_perto(c, 3.0).is_empty()
			igual(esp, "pardo" if abrigo else "saltador", "com abrigo pardo, aberto saltador")
			if esp == "pardo":
				pardo += 1
			else:
				saltador += 1
	verificar(pardo > 0 and saltador > 0, "as duas espécies têm lugar (%d pardo, %d saltador)" % [pardo, saltador])
	var id := r.nova_toca(Vector2(10.5, 10.5), "saltador")
	verificar(r.ratos.values().filter(func(x): return x.toca == id).all(func(x): return x.especie == "saltador"), "o rato é da espécie da toca")
	var sal: Dictionary = r.ratos.values().filter(func(x): return x.toca == id)[0]
	verificar(r._ne(sal, "vel", 0.0) > float(Registro.fauna.ratos.vel), "o saltador anda mais rápido")
