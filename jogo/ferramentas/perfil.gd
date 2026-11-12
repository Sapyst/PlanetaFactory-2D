extends SceneTree
## Perfil sem janela (checkup): quanto custa cada pedaço do quadro, chamado direto, na demonstração e numa fábrica
## grande (as 40 linhas de esteira e 20 torres do roteiro `estresse`): remontar a fábrica, montar um chunk, animar
## estruturas, tick do mundo, HUD, itens das esteiras, luzes, fios, e uma construção (sincronizar + o piso crescendo).
##   godot --headless --audio-driver Dummy --path jogo -s res://ferramentas/perfil.gd
## Só CPU. Grava em user://testes_salvos (nunca no save de quem joga). (Script `-s`: nada aqui pode citar classe do
## jogo pelo nome — elas compilariam antes dos autoloads existirem — por isso tudo é Variant e load().)

const DT := 1.0 / 30.0


func _initialize() -> void:
	Salvamento.pasta = "user://testes_salvos"
	load("res://nucleo/sessao.gd").arq_config = "user://testes_configuracoes.cfg"
	_perfil.call_deferred()


func _ms(f: Callable, vezes: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in vezes:
		f.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / vezes


func _perfil() -> void:
	root.get_node("Sessao").modo = "demo"
	change_scene_to_packed(load("res://cenas/mundo_demo.tscn"))
	while current_scene == null:
		await process_frame
	var cena: Node = current_scene
	for i in 90:
		await process_frame
	_medir_cena(cena, "demo")
	# fábrica grande (igual ao roteiro estresse): 40 linhas de 60 esteiras cheias + 20 torres
	var con = cena.construtor
	for x in range(20, 110):
		for y in range(-40, 30):
			cena.mapa.limpar_obstaculo(Vector2i(x, y))
	var t0 := Time.get_ticks_usec()
	for i in 40:
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(24 + i * 2, -35), Vector2i(24 + i * 2, 24), 0)))
	for i in 20:
		cena.sincronizar(con.executar(con.plano_peca("torre_defesa", Vector2i(24 + i * 4, 27), 0)))
	print("PERFIL grande: construir 40 linhas + 20 torres (sincronizar) %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	cena.camera.alvo = Vector3(64, 0, 5)
	cena.camera.distancia = 44.0
	cena.camera.posicionar()
	for i in 60:
		await process_frame
	for cm in cena.fabrica.caminhos:
		for k in 200:
			cm.esteira.inserir_em("pedra", k * 0.3)
	for i in 30:
		await process_frame
	_medir_cena(cena, "grande")
	var ini := _Marco.new()
	ini.process_priority = -100000
	var fim := _Marco.new()
	fim.process_priority = 100000
	root.add_child(ini)
	root.add_child(fim)
	var parado := await _quadros(ini, fim, 120)
	print("PERFIL grande: scripts por quadro parado (120 quadros): média %.1f ms, p95 %.1f, pior %.1f ms" % parado)
	# uma construção na fábrica grande: o sincronizar e os quadros seguintes (piso crescendo, fábrica remontando)
	t0 = Time.get_ticks_usec()
	var rel: Dictionary = con.executar(con.plano_peca("fornalha", Vector2i(20, 0), 0))
	cena.sincronizar(rel)
	var t_sinc := (Time.get_ticks_usec() - t0) / 1000.0
	var obra := await _quadros(ini, fim, 60)
	print("PERFIL grande: construir 1 fornalha (%d colocada): sincronizar %.1f ms · scripts nos 60 quadros seguintes: média %.1f ms, p95 %.1f, pior %.1f ms" % [rel.colocados.size(), t_sinc, obra[0], obra[1], obra[2]])
	cena.camera.alvo += Vector3(40, 0, 20)                 # câmera anda: chunks novos entram (1 por quadro)
	cena.camera.posicionar()
	var anda := await _quadros(ini, fim, 60)
	print("PERFIL grande: câmera pulou 45 m: scripts nos 60 quadros seguintes: média %.1f ms, p95 %.1f, pior %.1f ms" % anda)
	cena.camera.alvo += Vector3(-80, 0, -40)
	cena.camera.posicionar()
	print("PERFIL grande: câmera pulou de novo, _process por nó nos 40 quadros seguintes: %s" % _por_no(cena, 40))
	print("PERFIL memória: estática %.1f MB · nós %d · objetos %d" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])
	quit(0)


## _process de cada nó da cena chamado à mão `reps` vezes: média e pior por nó (pega quem trabalha de vez em quando).
func _por_no(cena: Node, reps: int) -> String:
	var custos := {}
	for rep in reps:
		for c in [cena] + cena.get_children():
			if not c.has_method("_process") or not c.is_processing():
				continue
			var chave := "%s(%s)" % [c.name, c.get_class()] if c.get_script() == null else str(c.get_script().resource_path.get_file())
			var t := _ms(c._process.bind(DT), 1)
			var v: Array = custos.get(chave, [0.0, 0.0])
			custos[chave] = [v[0] + t, maxf(v[1], t)]
	var ordem := custos.keys()
	ordem.sort_custom(func(a, b): return custos[a][0] > custos[b][0])
	var partes: Array[String] = []
	for ch_k in ordem.slice(0, 9):
		partes.append("%s %.2f (pior %.1f)" % [ch_k, custos[ch_k][0] / reps, custos[ch_k][1]])
	return " · ".join(partes)


## [média, p95, pior] do tempo de scripts por quadro em n quadros.
func _quadros(ini: _Marco, fim: _Marco, n: int) -> Array:
	var v: PackedFloat32Array = []
	for i in n:
		await process_frame
		v.append((fim.marca - ini.marca) / 1000.0)
	var ord := v.duplicate()
	ord.sort()
	var soma := 0.0
	for x in v:
		soma += x
	return [soma / n, ord[int(n * 0.95)], ord[-1]]


func _medir_cena(cena: Node, nome: String) -> void:
	var itens := 0
	for c in cena.fabrica.caminhos:
		itens += c.esteira.itens.size()
	print("PERFIL %s: %d estruturas · %d caminhos · %d itens · %d chunks · %d nós" % [nome, cena.mapa.estruturas.size(), cena.fabrica.caminhos.size(), itens, cena.chunks.size(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var k: Vector2i = cena.chunks.keys()[0]
	var g = cena.gerador
	var DC = load("res://render/desenho_chunk.gd")
	var t_prep := _ms(func(): DC.preparar_dados(k, g), 3)
	var dados_chunk: Dictionary = DC.preparar_dados(k, g)
	var t_mont := _ms(func():
		var d = DC.new()
		cena.add_child(d)
		d.montar(dados_chunk, cena.mapa)
		d.free(), 3)
	var ch = cena.chunks[k]
	var centro := Vector2(k * 32) + Vector2(16, 16)
	var t_atu := _ms(func(): ch.atualizar(cena.mapa, [centro]), 3)
	var t_cresce := _ms(ch._compor_crescer, 10)
	var t_fab := _ms(ch.atualizar_fabrica, 3)
	ch._t_crescer = -1.0
	print("PERFIL %s: chunk preparar (thread) %.1f ms · montar (no quadro) %.1f ms · atualizar (obra) %.1f ms · _compor_crescer (por quadro, 1,6 s) %.2f ms · atualizar_fabrica %.1f ms" % [nome, t_prep, t_mont, t_atu, t_cresce, t_fab])
	var f = cena.fabrica
	var t_rec := _ms(f.reconstruir, 3)
	var partes_rec := [_ms(f._montar_esteiras, 3), _ms(f._montar_maquinas, 3), _ms(f._montar_energia, 3), _ms(f._ligar_pontas, 3),
			_ms(f._montar_portas, 3), _ms(f._montar_bracos, 3), _ms(f._montar_fluidos, 3), _ms(f._montar_logica, 3), _ms(f._guardar_itens, 3)]
	var soma_rec := 0.0
	for x in partes_rec:
		soma_rec += x
	print("PERFIL %s: fabrica.reconstruir %.1f ms = esteiras %.1f + máquinas %.1f + energia %.1f + pontas %.1f + portas %.1f + braços %.1f + fluidos %.1f + lógica %.1f + guardar itens %.1f + restaurar itens e resto %.1f" % ([nome, t_rec] + partes_rec + [t_rec - soma_rec]))
	f.reconstruir()
	print("PERFIL %s: fabrica.reconstruir por partes (obra de uma metade): só esteiras %.1f ms · sem esteiras %.1f ms" % [nome,
			_ms(f.reconstruir.bind("esteiras"), 3), _ms(f.reconstruir.bind("resto"), 3)])
	print("PERFIL %s: fabrica.tick %.2f ms · _tick_mundo %.2f ms = ambiente._passo (1×/s) %.2f + clima.tick %.2f + raios.tick %.2f + agua.tick %.2f + poluicao.tick %.2f + clima_local.atualizar %.2f" % [nome,
			_ms(f.tick.bind(DT), 30), _ms(cena._tick_mundo.bind(DT), 30), _ms(cena.ambiente._passo.bind(f, cena.clima), 5), _ms(cena.clima.tick.bind(DT), 30),
			_ms(cena.raios.tick.bind(cena.clima), 30), _ms(cena.agua.tick.bind(DT), 30), _ms(cena.poluicao.tick.bind(DT), 30), _ms(cena.clima_local.atualizar, 30)])
	print("PERFIL %s: outros ticks: drones %.2f · varredura %.2f · farol %.2f · lancador %.2f · genese %.2f · transportador %.2f · silo %.2f · colonia %.2f" % [nome,
			_ms(cena.drones.tick.bind(DT), 30), _ms(cena.varredura.tick.bind(DT), 30), _ms(cena.farol.tick.bind(DT), 30), _ms(cena.lancador.tick.bind(DT), 30),
			_ms(cena.genese.tick.bind(DT), 30), _ms(cena.transportador.tick.bind(DT), 30), _ms(cena.silo.tick.bind(DT), 30), _ms(cena.colonia.tick.bind(DT, [] as Array[Dictionary]), 30)])
	print("PERFIL %s: _animar_estruturas %.2f ms · _hud %.2f ms · itens._desenhar %.2f ms" % [nome,
			_ms(cena._animar_estruturas, 30), _ms(cena._hud, 10), _ms(cena._desenho_itens._desenhar, 10)])
	var Visao = load("res://ambiente/visao.gd")
	print("PERFIL %s: desenho_colonia.atualizar %.2f · desenho_drones.atualizar %.2f · desenho_trens.sincronizar %.2f · _atualizar_rotulos %.2f · ajustar_grama (todos os chunks) %.2f · _refazer_fontes (luzes) %.2f" % [nome,
			_ms(cena._desenho_colonia.atualizar.bind([] as Array[Dictionary], DT), 30), _ms(cena._desenho_drones.atualizar.bind([] as Array[Dictionary], DT), 30),
			_ms(cena._desenho_trens.sincronizar.bind(cena.trens), 30), _ms(cena._atualizar_rotulos, 30),
			_ms(func():
				for ck in cena.chunks:
					cena.chunks[ck].ajustar_grama(Visao.centro, false), 10),
			_ms(cena.luzes._refazer_fontes, 5)])
	print("PERFIL %s: _process por nó (média ms · pior): %s" % [nome, _por_no(cena, 60)])
	cena.mapa.versao += 1                      # o que cada nó refaz quando o mapa muda (obra, ninho novo)
	print("PERFIL %s: mapa mudou (versao += 1): _animar_estruturas %.1f ms · _process por nó: %s" % [nome, _ms(cena._animar_estruturas, 1), _por_no(cena, 1)])
	var por_versao: Array[String] = []
	for par in [["_tick_mundo", cena._tick_mundo.bind(DT)], ["fabrica.tick", cena.fabrica.tick.bind(DT)], ["clima_local.atualizar", cena.clima_local.atualizar],
			["colonia.tick", cena.colonia.tick.bind(DT, [] as Array[Dictionary])], ["drones.tick", cena.drones.tick.bind(DT)], ["raios.tick", cena.raios.tick.bind(cena.clima)],
			["varredura.tick", cena.varredura.tick.bind(DT)], ["farol.tick", cena.farol.tick.bind(DT)], ["lancador.tick", cena.lancador.tick.bind(DT)],
			["desenho_colonia.atualizar", cena._desenho_colonia.atualizar.bind([] as Array[Dictionary], DT)], ["_animar_estruturas", cena._animar_estruturas]]:
		cena.mapa.versao += 1
		por_versao.append("%s %.1f" % [par[0], _ms(par[1], 1)])
	print("PERFIL %s: mapa mudou, cada um sozinho (ms): %s" % [nome, " · ".join(por_versao)])
	print("PERFIL %s: luzes._avaliar %.2f ms · fios.refazer %.1f ms · colonia.tick %.2f ms · _atualizar_chunks %.2f ms" % [nome,
			_ms(cena.luzes._avaliar, 10), _ms(cena._fios.refazer, 3), _ms(cena.colonia.tick.bind(DT, [] as Array[Dictionary]), 30),
			_ms(cena._atualizar_chunks, 30)])


class _Marco extends Node:
	var marca := 0
	func _process(_d: float) -> void:
		marca = Time.get_ticks_usec()
