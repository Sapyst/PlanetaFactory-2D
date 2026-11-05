class_name RoteiroTeste
extends Node
## Teste visual sem humano: injeta cliques, teclas e toques de verdade (Input.parse_input_event passa pela
## interface e pelo ControleConstrucao como se fosse a pessoa) em quadros fixos. Com --write-movie e --fixed-fps
## cada quadro vira um PNG, então dá para conferir o fantasma verde/vermelho, a peça posta, a remoção etc.
##   godot --path jogo --write-movie /tmp/r/q.png --fixed-fps 30 --quit-after 130 -- camera -1 1 15 roteiro construir
##   ... -- camera -1 1 15 roteiro toque

var roteiro := ""
var cena: Node
var _quadro := 0
var _passos: Array = []      ## [quadro, Callable]


func _ready() -> void:
	# o gerenciador de janelas pode impor outro tamanho; a gravação é 1280×720, então a tela lógica também
	if not OS.get_cmdline_user_args().has("celular"):     # -- celular: tela larga como a do celular (20:9)
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	match roteiro:
		"construir": _roteiro_pc()
		"toque": _roteiro_toque()
		"trem": _roteiro_trem()
		"ataque": _roteiro_ataque()
		"poluicao": _roteiro_poluicao()
		"painel": _roteiro_painel()
		"salvar": _roteiro_salvar()
		"roda_ui": _roteiro_roda_ui()
		"pausa": _roteiro_pausa()
		"raio_foto": _roteiro_raio_foto()
		"fotos_ui": _roteiro_fotos_ui()
		"vento_cmp": _roteiro_vento_cmp()
		"estresse": _roteiro_estresse()
		"fundo": em(2, func(): cena.controle.barra.visible = false)
		"vitrine": _roteiro_vitrine()
		"fotos_finais", "carga", "ui_pc", "noite":              # fase 5: fotos de todas as peças / desempenho (roteiro_fotos.gd)
			var rf := RoteiroFotos.new()
			rf.rt = self
			add_child(rf)
		"panorama": _roteiro_panorama()
		"fios": _roteiro_fios()
		"rota": _roteiro_rota()
		"mostruario": _roteiro_mostruario()
		"encosta": _roteiro_encosta()
		"aplainar": _roteiro_aplainar()
		"aranha": _roteiro_aranha()
		"montagem": _roteiro_montagem()
		"bracos": _roteiro_bracos()
		"passagem": _roteiro_passagem()
		"enxurrada": _roteiro_enxurrada()
		"canal": _roteiro_canal()
		"limpeza": _roteiro_limpeza()
		"agua": _roteiro_agua()
		"combate": _roteiro_combate()
		"clima": _roteiro_clima()
		"drones": _roteiro_drones()
		"obras": _roteiro_obras()
		"vida": _roteiro_vida()
		"plantas": _roteiro_plantas()
		"frutos": _roteiro_frutos()
		"carcacas": _roteiro_carcacas()
		"ratos": _roteiro_ratos()
		"limpeza2": _roteiro_limpeza2()
		"lote16": _roteiro_lote16()
		"lote17": _roteiro_lote17()
		"lote13": _roteiro_lote13()
		"lote14": _roteiro_lote14()
		"lote10": _roteiro_lote10()
		"lote11": _roteiro_lote11()
		"chegada":                                     # -- novo roteiro chegada abertura --fixed-fps 30: a cápsula cai e vira o núcleo
			for q in [30, 150, 225, 235, 260, 330, 420, 450, 470, 490]:
				em(q, func():
					var ab: Abertura = null
					for c in cena.get_children():
						if c is Abertura:
							ab = c
					if ab == null:
						print("CHEGADA q%d abertura acabou; núcleo visível %s" % [q, cena._no_nucleo.visible])
						return
					print("CHEGADA q%d t=%.2f queda %s visível %s anim %.2f s impacto %s trocou %s núcleo visível %s" % [q, ab._t,
							ab._queda != null, ab._queda.visible if ab._queda != null else false,
							ab._anim.current_animation_position if ab._anim != null and ab._anim.current_animation != "" else -1.0, ab._impacto, ab._trocou, ab.nucleo.visible]))
		"energia": _roteiro_energia()
		"vento":                                       # rajadas passando na grama, depois a camada de vento da visão
			em(2, func():
				Sessao.config.fps = false
				_sem_ninhos(Vector2i(-14, -14))
				cena.clima.forcar("nublado", true)
				var cam: CameraJogo = cena.camera
				cam.alvo = Grade.ponto_mundo(Vector2(-14.0, -14.0))
				cam.distancia = 13.0
				cam.posicionar())
			for q in [10]:
				em(q, func():
					cena.clima.rajada = {}
					cena.clima.prox_rajada = 0.0)
			em(250, func():
				cena.clima.vento_medio = cena.clima.direcao_vento * 0.6
				var cam: CameraJogo = cena.camera
				cam.alvo = Vector3.ZERO
				cam.distancia = 70.0
				cam.posicionar()
				cena.controle.alternar_recursos()
				cena.controle.alternar_recursos())
			em(262, func(): mover(tela(Vector2i(4, 6))))
		"turbina":                                     # painel da turbina (vento do lugar, corte, bandeira)
			_roteiro_energia()
			em(185, func():
				cena.clima.forcar("tempestade", true)
				_clicar_id(_ids.turbina_eolica)
				var cam: CameraJogo = cena.camera
				cam.alvo = Grade.ponto_mundo(Vector2(_ids_o) + Vector2(1.0, 4.0), 2.0)
				cam.distancia = 11.0
				cam.posicionar())
		"arvores":                                     # o bosque mais denso perto do início (use com -- estacao E F)
			em(2, func():
				Sessao.config.fps = false
				var c := _bosque()
				_sem_ninhos(c)
				var cam: CameraJogo = cena.camera
				cam.alvo = Grade.ponto_mundo(Vector2(c) + Vector2(6, 6))
				cam.distancia = 15.0
				cam.posicionar())
		"queimada":                                    # fogo num bosque: copa queima, tronco carboniza, fogo longo derruba
			em(2, func():
				Sessao.config.fps = false
				var c := _bosque()
				_sem_ninhos(c)
				cena.clima.forcar("limpo", true)
				var cam: CameraJogo = cena.camera
				cam.alvo = Grade.ponto_mundo(Vector2(c) + Vector2(6, 6))
				cam.distancia = 14.0
				cam.posicionar()
				var amb: AmbienteVivo = cena.ambiente
				for y in 12:
					for x in 12:
						var t := c + Vector2i(x, y)
						var o: Dictionary = cena.gerador.distribuicao.obstaculo(t)
						if not o.is_empty() and Distribuicao.eh_arvore(o.nome) and (x + y) % 3 == 0:
							amb.fogo[t] = 8.0 + 16.0 * float((x * 7 + y * 3) % 5) / 4.0)
		"medir":                                       # custo por quadro: desliga uma coisa por vez e mede
			_roteiro_medir()
		"inventario":                                  # quem soma os triângulos na cena
			em(120, func():
				var cam: CameraJogo = cena.camera
				cam.distancia = 60.0
				cam.posicionar())
			em(200, func(): _inventario())
			em(205, func():
				var a := Vector2(cena.camera.alvo.x, -cena.camera.alvo.z)
				for k in cena.chunks:
					var ch: DesenhoChunk = cena.chunks[k]
					for g in ch._grama_q:
						if g.rect.has_point(a) or (a - a.clamp(g.rect.position, g.rect.end)).length() < 20:
							print("GQ ", k, " ", g.rect, " esp ", g.esparsa != null and g.esparsa.visible, " det ", g.detalhe != null and g.detalhe.visible, " n ", g.esparsa.multimesh.instance_count if g.esparsa else -1)
				print("GQ alvo ", a))
		"visao":                                       # oval de visão: zoom normal, zoom longe, depois de andar
			em(2, func(): Sessao.config.fps = false)
			em(100, func():
				var cam: CameraJogo = cena.camera
				cam.distancia = 75.0
				cam.posicionar())
			em(200, func():
				var cam: CameraJogo = cena.camera
				cam.alvo += Vector3(70, 0, 40)
				cam.distancia = 70.0
				cam.posicionar())
		"telas":                                       # interface em telas de celular/tablet: nada passa da borda
			_roteiro_telas()
		"ui":                                          # modo construção (faixa + grade), painel de máquina
			em(4, func(): Sessao.config.fps = false)
			em(10, func(): cena.controle.escolher("esteira"))
			em(14, func(): mover(Vector2(560, 420)))
			em(40, func():
				cena.controle.sair_do_modo()
				var receitas := {"fornalha": "fundir_ferro", "montadora": "engrenagem", "refinador": "bateria"}
				for id in cena.mapa.estruturas:
					var e: Dictionary = cena.mapa.estruturas[id]
					if receitas.has(e.nome) and cena.fabrica.maquinas.has(id):
						cena.fabrica.escolher_receita(id, receitas[e.nome])
						var r: Dictionary = Registro.receitas[receitas[e.nome]]
						cena.fabrica.maquinas[id].entradas = {r.entradas.keys()[0]: 1}
						cena.selecionar(Grade.centro_da_area(e.minimo, e.area, e.rot))
						break)
		"pesquisa":                                    # abre a árvore de pesquisa e escolhe um nó
			em(4, func():
				Sessao.config.fps = false
				if OS.get_cmdline_user_args().has("celular"):    # tela lógica de celular (como no roteiro telas)
					get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
					get_tree().root.content_scale_factor = 1.0
					get_window().content_scale_size = Vector2i(948, 533)       # 16:9 com a escala do celular (cabe na gravação 1280×720)
				cena.abrir_pesquisa())
			em(30, func():
				var t: TelaPesquisa = cena._tela_pesquisa
				t._sel = "logistica"
				t._atualizar())
			em(50, func():                             # quadro ~70: pesquisa "em breve" da era do meio
				var t: TelaPesquisa = cena._tela_pesquisa
				t._sel = "escavar_canal"
				t._atualizar()
				var r: Rect2 = t._pos["escavar_canal"]
				t._rolagem.scroll_horizontal = int(r.position.x * t._zoom - 200.0)
				t._rolagem.scroll_vertical = int(maxf(0.0, r.position.y * t._zoom - 120.0)))
			em(62, func():                             # quadro ~75: zoom afastado (visão das eras)
				var t: TelaPesquisa = cena._tela_pesquisa
				t._zoom_em(0.3, Vector2.ZERO))
			em(70, func():                             # quadro ~85: do começo, com os títulos das eras
				var t: TelaPesquisa = cena._tela_pesquisa
				t._rolagem.scroll_horizontal = 0
				t._rolagem.scroll_vertical = 0)
		"estudos":                                     # máquinas convertidas dos estudos, uma câmera por máquina (30 quadros cada)
			_roteiro_estudos()
		"ver":                                         # câmera de perto na 1ª estrutura de um nome: -- roteiro ver fornalha
			em(6, func():
				Sessao.config.fps = false
				var args := OS.get_cmdline_user_args()
				var alvo_nome: String = args[args.find("ver") + 1] if args.find("ver") + 1 < args.size() else "fornalha"
				for id in cena.mapa.estruturas:
					var e: Dictionary = cena.mapa.estruturas[id]
					if e.nome == alvo_nome:
						var cam: CameraJogo = cena.camera
						cam.alvo = Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot))
						cam.distancia = 3.2
						cam.posicionar()
						break)
		"encardido":                                   # estruturas limpas (q~30), meio sujas (q~60) e imundas (q~90)
			for i in 3:
				var g: float = [0.0, 0.5, 1.0][i]
				em(10 + i * 30, func():
					Sessao.config.fps = false
					for id in cena.mapa.estruturas:
						cena.ambiente.encardido[id] = g)
		"dedo":                                        # celular: rolar lista com o dedo, arrastar mapa, pinça
			_roteiro_dedo()
		"faiscas":                                     # acumulador carregado de perto (use com -- hora 0.0)
			_roteiro_energia()
			em(180, func():                            # depois do roteiro de energia mexer na câmera
				var ac: int = _ids.acumulador
				cena.fabrica.acumulado[ac] = 60.0
				cena.fabrica.reconstruir()
				var cam: CameraJogo = cena.camera
				cam.alvo = Grade.ponto_mundo(Vector2(_ids_o) + Vector2(4.0, 1.0))
				cam.distancia = 6.5
				cam.posicionar())
		"filtro": _roteiro_filtro()
		"interface": _roteiro_interface()
		"grama": _roteiro_grama()
		"ambiente": _roteiro_ambiente()
		"recursos":
			em(4, func(): cena.controle.alternar_recursos())
			em(6, func(): mover(tela(Vector2i(-15, -9))))
		"vagao_tex": _roteiro_vagao_tex()
		"abas": _roteiro_abas()
		"conferir": print("DIGITAL ", digital(cena))
	print("ROTEIRO ", roteiro, " com ", _passos.size(), " passos; tela ", get_viewport().get_visible_rect().size, " janela ", DisplayServer.window_get_size())


func _process(_d: float) -> void:
	_quadro += 1
	if _voo_ini > 0 and _quadro >= _voo_ini:
		_voar((_quadro - _voo_ini) / 30.0)
	if _grama_ini >= 0:
		var tg := (_quadro - _grama_ini) / 30.0
		var cg: CameraJogo = cena.camera
		cg.alvo = Grade.ponto_mundo(Vector2(-14.0, -14.0))
		cg.distancia = 11.0
		cg.angulo = 0.4 + tg * 0.08
		cg.posicionar()
		if _quadro - _grama_ini == 60:
			_t_ant = Time.get_ticks_usec()
		elif _quadro - _grama_ini > 60:
			var ag := Time.get_ticks_usec()
			_tempos.append((ag - _t_ant) / 1000.0)
			_t_ant = ag
			if _tempos.size() == 300:
				_relatorio_tempos("grama 52 mil tufos")
				get_tree().quit()
	if _aranha != null:
		# anda em volta de um ponto (curvas e reta), a câmera acompanha de perto
		var t := _quadro / 30.0
		var c := Vector2(-6.0, -10.0)          # área livre (sem construção no caminho)
		var p := c + Vector2(cos(t * 0.45), sin(t * 0.45)) * 4.5
		_aranha.ir_para(Grade.ponto_mundo(p))
		var cam: CameraJogo = cena.camera
		cam.alvo = cam.alvo.lerp(_aranha.global_position, 0.08)
		cam.distancia = 8.5
		cam.angulo = 0.6 + t * 0.12
		cam.posicionar()
	for p in _passos:
		if p[0] == _quadro:
			p[1].call()


func em(q: int, f: Callable) -> void:
	_passos.append([q, f])


func tela(t: Vector2i) -> Vector2:
	return (cena.camera as Camera3D).unproject_position(Grade.centro_mundo(t))


func botao(chave: String) -> Vector2:
	return cena.controle.barra.centro_de(chave)


# ------------------------------------------------------------------ eventos
## Os eventos entram em coordenadas da JANELA; o roteiro pensa na tela lógica 1280×720 (a janela pode estar escalada).
func _jan(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func mover(p: Vector2) -> void:
	p = _jan(p)
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(e)


func botao_mouse(p: Vector2, apertado: bool, b := MOUSE_BUTTON_LEFT) -> void:
	p = _jan(p)
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = b
	e.pressed = apertado
	Input.parse_input_event(e)


func clicar(p: Vector2) -> void:
	mover(p)
	botao_mouse(p, true)
	botao_mouse(p, false)


func tecla(k: Key, ctrl := false) -> void:
	for apertada in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = apertada
		Input.parse_input_event(e)


func toque(i: int, p: Vector2, apertado: bool) -> void:
	p = _jan(p)
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = apertado
	Input.parse_input_event(e)


func arrasto(i: int, de: Vector2, para: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _jan(para)
	e.relative = _jan(para) - _jan(de)
	Input.parse_input_event(e)


## Arrasta o mouse (botão esquerdo) de um tile a outro ao longo de n quadros a partir de q.
func traco_mouse(q: int, a: Vector2i, b: Vector2i, n: int) -> void:
	em(q, func(): mover(tela(a)); botao_mouse(tela(a), true))
	for k in range(1, n + 1):
		var f := float(k) / n
		em(q + k, func(): mover(tela(a).lerp(tela(b), f)))


# ------------------------------------------------------------------ roteiros
## PC: escolhe a esteira, traça um L, põe; fornalha em cima (vermelho) e ao lado (verde);
## extrator fora da jazida (vermelho); remove um pedaço com retângulo; desfaz.
func _roteiro_pc() -> void:
	em(4, func(): clicar(botao("esteira")))
	em(6, func(): mover(tela(Vector2i(-6, -3))))
	traco_mouse(8, Vector2i(-6, -3), Vector2i(2, 2), 16)
	# quadro ~30: foto do traço verde
	em(34, func(): botao_mouse(tela(Vector2i(2, 2)), false))
	em(38, func(): clicar(botao("cat:3")))
	em(40, func(): clicar(botao("fornalha")))
	em(42, func(): mover(tela(Vector2i(-2, -3))))
	# quadro ~48: fornalha vermelha em cima da esteira
	em(50, func(): mover(tela(Vector2i(-1, 2))))
	em(52, func(): tecla(KEY_R))
	em(56, func(): clicar(tela(Vector2i(-1, 2))))
	em(60, func(): clicar(botao("extrator_cristal")))
	em(62, func(): mover(tela(Vector2i(-4, 4))))
	# quadro ~68: extrator vermelho (precisa de jazida)
	em(72, func(): tecla(KEY_X))
	traco_mouse(74, Vector2i(-6, -3), Vector2i(-3, -2), 6)
	# quadro ~84: retângulo de remoção vermelho
	em(86, func(): botao_mouse(tela(Vector2i(-3, -2)), false))
	em(92, func(): tecla(KEY_ESCAPE))
	em(96, func(): mover(Vector2(640, 40)))
	# quadro ~100: depois de remover
	em(104, func(): tecla(KEY_Z, true))
	# quadro ~112: desfeito (a esteira volta)
	em(116, func(): clicar(botao("cat:5")))
	em(118, func(): clicar(botao("muro_centro")))
	traco_mouse(120, Vector2i(-7, 5), Vector2i(-2, 5), 5)
	em(126, func(): botao_mouse(tela(Vector2i(-2, 5)), false))
	traco_mouse(128, Vector2i(-2, 4), Vector2i(-2, 1), 4)
	em(133, func(): botao_mouse(tela(Vector2i(-2, 1)), false))
	em(135, func(): tecla(KEY_ESCAPE))
	# quadro ~140: muro em L, panos ligando os pilares


# ------------------------------------------------------------------ mostruário (prints e GIF de apresentação)
## Fábrica lotada a oeste do início (brocas nas jazidas, barramento de esteiras, elevada cruzando, blocos de
## máquinas, energia, muralha com torres), sem interface, tudo animado. `-- roteiro mostruario voo` faz o voo
## de câmera (18 s a partir do quadro 60); sem "voo" a câmera fica onde o argumento `camera` mandar (prints).
const VOO := [  # [segundo, x, z, distância, ângulo]
	[0.0, -2.0, -4.0, 72.0, 0.55], [3.0, -14.0, -8.0, 34.0, 0.85], [6.0, -25.0, -2.0, 15.0, 1.25],
	[9.0, -30.0, -19.0, 21.0, 1.8], [12.0, -29.0, 18.0, 25.0, 2.5], [15.0, -12.0, 8.0, 40.0, 3.0],
	[18.0, 6.0, 0.0, 62.0, 3.35]]
var _voo_ini := 0


func _roteiro_mostruario() -> void:
	Sessao.config.fps = false
	cena.animar_tudo = true
	cena._efeitos.mostrar_icones = false
	em(2, func():
		cena.controle.barra.visible = false
		_montar_mostruario())
	em(14, func(): _encher_esteiras())
	var args := OS.get_cmdline_user_args()
	if args.has("visao"):
		em(20, func(): cena.controle.alternar_recursos())
	if args.has("setas"):
		em(20, func():
			cena.controle.escolher("esteira")
			mover(Vector2(-50, -50)))
	if args.has("voo"):
		_voo_ini = 60
		em(60 + int(VOO[-1][0] * 30.0) + 2, func(): get_tree().quit())


func _voar(t: float) -> void:
	var i := 0
	while i < VOO.size() - 2 and t > VOO[i + 1][0]:
		i += 1
	var k: Array = [VOO[maxi(i - 1, 0)], VOO[i], VOO[i + 1], VOO[mini(i + 2, VOO.size() - 1)]]
	var u := clampf((t - k[1][0]) / (k[2][0] - k[1][0]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65                # leve suavização sem parar nos pontos
	var v := []
	for c in range(1, 5):
		var a: float = k[0][c]
		var b: float = k[1][c]
		var cc: float = k[2][c]
		var d: float = k[3][c]
		if c == 3:
			a = log(a); b = log(b); cc = log(cc); d = log(d)
		var r := 0.5 * (2.0 * b + (cc - a) * u + (2.0 * a - 5.0 * b + 4.0 * cc - d) * u * u + (3.0 * b - a - 3.0 * cc + d) * u * u * u)
		v.append(exp(r) if c == 3 else r)
	var cam: CameraJogo = cena.camera
	cam.alvo = Vector3(v[0], 0, v[1])
	cam.distancia = v[2]
	cam.angulo = v[3]
	cam.posicionar()


func _montar_mostruario() -> void:
	var con: Construtor = cena.construtor
	var p := func(plano: Array[Dictionary]) -> void: cena.sincronizar(con.executar(plano))
	for x in range(-42, -8):
		for y in range(-30, 30):
			cena.mapa.limpar_obstaculo(Vector2i(x, y))
	# brocas nas jazidas de ferro (-13, 9) e carvão (-15, -9); cada uma solta um ramal do barramento para oeste
	var saidas: Array[Vector2i] = []
	for base in [Vector2i(-13, 9), Vector2i(-15, -9)]:
		for o in [Vector2i(-2, -2), Vector2i(1, -2), Vector2i(-2, 1), Vector2i(1, 1)]:
			var plano := con.plano_peca("broca_minerio", base + o, 3)
			if plano[0].motivo != "":
				continue
			var rel := con.executar(plano)
			cena.sincronizar(rel)
			for id in rel.colocados:
				var e: Dictionary = cena.mapa.estruturas[id]
				var porta := Grade.porta_no_mundo(Registro.estruturas["broca_minerio"].portas[0], e.minimo, Registro.area("broca_minerio"), e.rot)
				saidas.append(porta.tile_fora)
	var linha := 0
	for t in saidas:
		var y := -6 + linha * 2
		p.call(con.plano_linha("esteira", t, Vector2i(-33, y), 0))
		linha += 1
	# esteira elevada atravessando o barramento (norte–sul em x = −26)
	p.call(con.plano_linha("esteira", Vector2i(-26, -16), Vector2i(-26, -14), 0))
	p.call(con.plano_peca("esteira_rampa", Vector2i(-26, -13), Construtor.rot_do_fluxo(0)))
	con.nivel = 1
	p.call(con.plano_linha("esteira", Vector2i(-26, -12), Vector2i(-26, 14), 0))
	p.call(con.plano_peca("rampa_desce", Vector2i(-26, 15), Construtor.rot_do_fluxo(0)))
	con.nivel = 0
	p.call(con.plano_linha("esteira", Vector2i(-26, 16), Vector2i(-26, 18), 0))
	# blocos de máquinas: norte (montadoras e fornalhas) e sul (refinadores e laboratórios), com braço e baú
	for x in range(-35, -12, 5):
		p.call(con.plano_peca("montadora", Vector2i(x, 22), 0))
		p.call(con.plano_peca("fornalha", Vector2i(x, 17), 0))
		p.call(con.plano_peca("braco", Vector2i(x, 19), 0))
		p.call(con.plano_peca("bau", Vector2i(x + 1, 19), 0))
		p.call(con.plano_peca("refinador", Vector2i(x, -20), 0))
		p.call(con.plano_peca("laboratorio", Vector2i(x, -25), 0))
		p.call(con.plano_peca("braco", Vector2i(x, -17), 2))
		p.call(con.plano_peca("bau", Vector2i(x + 1, -17), 0))
	# energia: geradores e postes (fios automáticos)
	for g in [Vector2i(-35, 13), Vector2i(-31, 13), Vector2i(-35, -12), Vector2i(-31, -12)]:
		p.call(con.plano_peca("gerador", g, 0))
	# miolo do barramento: tanques ligados por canos
	for t in [Vector2i(-21, 0), Vector2i(-17, 0), Vector2i(-21, 4), Vector2i(-17, 4)]:
		p.call(con.plano_peca("tanque", t, 0))
	p.call(con.plano_linha("cano", Vector2i(-23, -2), Vector2i(-23, 7), 0))
	p.call(con.plano_linha("cano", Vector2i(-22, 7), Vector2i(-15, 7), 0))
	for x in range(-35, -10, 6):
		for y in [-22, -14, 10, 20]:
			p.call(con.plano_peca("poste_energia", Vector2i(x, y), 0))
	# muralha com torres nos cantos
	p.call(con.plano_linha("muro_centro", Vector2i(-38, -29), Vector2i(-10, -29), 0))
	p.call(con.plano_linha("muro_centro", Vector2i(-38, 28), Vector2i(-10, 28), 0))
	p.call(con.plano_linha("muro_centro", Vector2i(-38, -28), Vector2i(-38, 27), 0))
	for t in [Vector2i(-35, -26), Vector2i(-35, 25), Vector2i(-12, -26), Vector2i(-12, 25)]:
		p.call(con.plano_peca("torre_defesa", t, 0))
	con._historico.clear()


## Itens já correndo no barramento e na elevada (o vídeo começa com a fábrica em movimento).
func _encher_esteiras() -> void:
	var itens := ["minerio_ferro", "carvao", "minerio_cobre", "pedra"]
	for c in cena.fabrica.caminhos:
		var e: EsteiraCaminho = c.esteira
		var pos := 0.3
		var k := 0
		while pos < e.util() - 0.6:
			e.inserir_em(itens[k % itens.size()], pos)
			pos += 0.85
			k += 1


## Construção numa encosta longe do início: o chão em volta é aplainado no nível de cada peça (foto ~40).
func _roteiro_encosta() -> void:
	em(3, func():
		var con: Construtor = cena.construtor
		var c := Grade.tile_de_mundo(cena.camera.alvo)
		for x in range(c.x - 10, c.x + 11):
			for y in range(c.y - 8, c.y + 9):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		var postos := 0
		for x in range(c.x - 8, c.x + 9, 3):
			for y in range(c.y - 6, c.y + 7, 3):
				var rel := con.executar(con.plano_peca("fornalha", Vector2i(x, y), 0))
				postos += rel.colocados.size()
				cena.sincronizar(rel)
		print("ENCOSTA %d fornalhas postas" % postos))


## Terraplenagem: a central no meio, um patamar aplainado em volta (atravessando encostas) e fornalhas em cima.
func _roteiro_aplainar() -> void:
	em(3, func():
		var con: Construtor = cena.construtor
		cena.controle.barra.visible = false
		var c := Grade.tile_de_mundo(cena.camera.alvo)
		cena.sincronizar(con.executar(con.plano_peca("terraplenagem", c, 0)))
		var pl := con.plano_aplainar(c - Vector2i(14, 12), c + Vector2i(14, 12))
		cena.sincronizar(con.executar(pl))
		print("APLAINAR ", Construtor.contar(pl))
		for x in [-6, -3, 3, 6]:
			cena.sincronizar(con.executar(con.plano_peca("fornalha", c + Vector2i(x, 3), 0)))
		print("APLAINAR ok, central: ", cena.mapa.tem_terraplenagem()))


## Braços de perto: baú com minério → braço → esteira → braço → fornalha → braço → baú. Tudo item a item.
func _roteiro_bracos() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var con: Construtor = cena.construtor
		for x in range(-12, 2):
			for y in range(-16, -6):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("bau", Vector2i(-10, -12), 0))
		p.call(con.plano_peca("braco", Vector2i(-9, -12), Construtor.rot_do_fluxo(1)))
		p.call(con.plano_linha("esteira", Vector2i(-8, -12), Vector2i(-5, -12), 0))
		p.call(con.plano_peca("braco", Vector2i(-4, -12), Construtor.rot_do_fluxo(1)))
		p.call(con.plano_peca("fornalha", Vector2i(-3, -13), 0))
		p.call(con.plano_peca("braco", Vector2i(-1, -12), Construtor.rot_do_fluxo(1)))
		p.call(con.plano_peca("bau", Vector2i(0, -12), 0))
		p.call(con.plano_peca("gerador", Vector2i(-7, -16), 0))
		p.call(con.plano_peca("poste_energia", Vector2i(-7, -14), 0))
		p.call(con.plano_peca("poste_energia", Vector2i(-2, -10), 0))
		cena.camera.alvo = Grade.ponto_mundo(Vector2(-4.0, -11.5))
		cena.camera.distancia = 9.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.baus:
			var e: Dictionary = cena.mapa.estruturas[id]
			if e.minimo == Vector2i(-10, -12):
				f.baus[id].merge({"minerio_ferro": 40, "carvao": 20})
		for id in f.combustivel:
			f.combustivel[id] = 500.0)


## Rampa de junção (esteira leste entrega na lateral de uma norte) e passagem subterrânea (esteira leste passa
## por baixo de uma esteira norte e de um baú). Itens entram sem parar nas cabeceiras.
func _roteiro_passagem() -> void:
	var leste := Construtor.rot_do_fluxo(1)
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var con: Construtor = cena.construtor
		for x in range(-12, 4):
			for y in range(-17, -5):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_linha("esteira", Vector2i(-6, -11), Vector2i(-6, -6), 0))
		p.call(con.plano_linha("esteira", Vector2i(-10, -8), Vector2i(-7, -8), 0))
		p.call(con.plano_linha("esteira", Vector2i(-3, -16), Vector2i(-3, -10), 0))
		p.call(con.plano_peca("bau", Vector2i(-2, -13), 0))
		p.call(con.plano_linha("esteira", Vector2i(-9, -13), Vector2i(-5, -13), 0))
		p.call(con.plano_peca("esteira_tunel_entrada", Vector2i(-4, -13), leste))
		p.call(con.plano_peca("esteira_tunel_saida", Vector2i(-1, -13), leste))
		p.call(con.plano_linha("esteira", Vector2i(0, -13), Vector2i(2, -13), 0))
		var perto := OS.get_cmdline_user_args().has("juncao")   # foco só na rampa de junção
		var tunel := OS.get_cmdline_user_args().has("tunel")    # foco só na passagem subterrânea
		cena.camera.alvo = Grade.ponto_mundo(Vector2(-6.0, -7.5) if perto else (Vector2(-2.5, -12.5) if tunel else Vector2(-4.5, -10.5)))
		cena.camera.distancia = 4.5 if perto else (6.5 if tunel else 10.0)
		cena.camera.posicionar())
	var itens := ["minerio_ferro", "pedra", "carvao", "minerio_cobre"]
	for q in range(8, 900, 7):
		em(q, func():
			var f: Fabrica = cena.fabrica
			for t in [Vector2i(-10, -8), Vector2i(-6, -11), Vector2i(-9, -13), Vector2i(-3, -16)]:
				if f._no_tile.has(t):
					(f.caminhos[f._no_tile[t][0]].esteira as EsteiraCaminho).inserir_na_entrada(itens[(q / 7 + t.x) % itens.size()]))


## Chuva num rio sujo: acha o rio mais perto, suja a água e a margem, liga a chuva com poças cheias. Mostra os
## respingos, os anéis na água, a enxurrada e o lixo boiando com a correnteza.
func _roteiro_enxurrada() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var g := Grade.gerador
		var rio := Vector2i(9999, 0)
		for r in range(4, 160, 2):
			for k in 32:
				var t := Vector2i((Vector2.from_angle(k * TAU / 32.0) * r).round())
				if rio.x == 9999 and g.terreno(t) == GeradorMundo.Terreno.RIO:
					rio = t
		var a: AmbienteVivo = cena.ambiente
		for y in range(-10, 11):
			for x in range(-10, 11):
				var t := rio + Vector2i(x, y)
				if g.eh_agua(g.terreno(t)):
					a.somar(t, AmbienteVivo.AGUA, 0.7)
				elif Vector2(x, y).length() < 8.0:
					a.somar(t, AmbienteVivo.SUJ, 0.6)
		var c: Clima = cena.clima
		c.forcar("chuva", true)
		c.pocas = 0.9
		cena.camera.alvo = Grade.centro_mundo(rio)
		cena.camera.distancia = 7.0
		cena.camera.posicionar())


var _canal := Vector2i.ZERO


## Água em jogo: acha uma margem de rio/lago, põe a Terraplenagem, escava um canal em L (enche aos poucos),
## faz um dique num ramo, uma ponte de esteira atravessando o canal e uma montadora sobre o rio (plataforma).
func _roteiro_canal() -> void:
	em(2, func():
		var w := Vector2i(9999, 0)
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var g := Grade.gerador
		for r in range(6, 200, 2):
			for k in 48:
				var c := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w.x != 9999 or not g.terreno(c) in [GeradorMundo.Terreno.RIO, GeradorMundo.Terreno.LAGO]:
					continue
				var ok := true
				for i in range(1, 11):
					for j in range(-3, 7):
						var t := c + Vector2i(i, j)
						if g.terreno(t) != GeradorMundo.Terreno.TERRA or g.nivel(t) != g.nivel(c + Vector2i(1, 0)) or g.em_encosta(t):
							ok = false
				if ok and g.nivel(c + Vector2i(1, 0)) >= g.nivel(c):
					w = c
		print("CANAL margem ", w)
		_canal = w
		var con: Construtor = cena.construtor
		for i in range(1, 12):
			for j in range(-5, 6):
				cena.mapa.limpar_obstaculo(w + Vector2i(i, j))
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("terraplenagem", w + Vector2i(9, 5), 0))
		cena.camera.alvo = Grade.centro_mundo(w + Vector2i(4, 0))
		cena.camera.distancia = 9.0
		cena.camera.posicionar())
	em(20, func():
		var w := _canal
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		# o arraste começa na margem (nível da terra): o canal fica 1 nível abaixo — abaixo da água do rio
		var pl := con.plano_aplainar(w + Vector2i(1, 0), w + Vector2i(6, 0), 1)
		print("ESCAVA ", Construtor.contar(pl))
		p.call(pl)
		p.call(con.plano_aplainar(w + Vector2i(6, -1), w + Vector2i(6, -3), 1))
		# dique (muro no seco) e um ramo escavado atrás dele: fica seco
		p.call(con.plano_aplainar(w + Vector2i(4, 1), w + Vector2i(4, 2), 1))
		p.call(con.plano_peca("muro_centro", w + Vector2i(4, 1), 0)))
	em(80, func():
		var w := _canal
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_linha("esteira", w + Vector2i(3, -3), w + Vector2i(3, 3), 0))   # atravessa o canal: ponte
		p.call(con.plano_peca("bau", w + Vector2i(0, -2), 0))                             # no rio: plataforma
		if OS.get_cmdline_user_args().has("perto"):
			cena.camera.alvo = Grade.centro_mundo(w + Vector2i(3, 0))
			cena.camera.distancia = 3.2
			cena.camera.angulo = 0.9
			cena.camera.posicionar())


## Limpeza: margem de rio suja (chão, óleo, água), filtro na margem, coletor, viveiro com mudas e árvores, gerador
## ligando tudo; o tempo corre 6× para ver a sujeira sumindo e as mudas crescendo.
## Fase 2.3 (água): bomba d'água na margem → cano → supressor de incêndio; coletor de chuva e condensador de neblina
## com chuva forçada; um foco de fogo perto do supressor; abre o painel de cada peça nova. Sem janela serve de
## verificação (imprime "AGUA ..."): godot --headless --path jogo --quit-after 420 -- roteiro agua
func _roteiro_agua() -> void:
	var ids := {}
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		var w := Vector2i(9999, 0)
		for r in range(8, 260, 2):
			for k in 64:
				var t := Vector2i((Vector2.from_angle(k * TAU / 64.0) * r).round())
				if w.x != 9999 or g.terreno(t) != GeradorMundo.Terreno.TERRA or not g.eh_agua(g.terreno(t + Vector2i(0, -1))):
					continue
				var ok := true
				for i in range(0, 10):
					for j in range(0, 11):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q):
							ok = false
				if ok:
					w = t
		print("AGUA margem ", w)
		if w.x == 9999:
			return
		for i in range(-1, 11):
			for j in range(0, 12):
				m.limpar_obstaculo(w + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("bomba_agua", w, 0))
		p.call(con.plano_linha("cano", w + Vector2i(1, 2), w + Vector2i(1, 7), 0))
		var rs := 0                                  # supressor girado com a boca para o cano que chega do sul
		for rr in 4:
			if Grade.porta_no_mundo(Registro.modelos.supressor_fogo.portas[0], w + Vector2i(1, 8), Vector2i.ONE, rr).tile_fora == w + Vector2i(1, 7):
				rs = rr
		p.call(con.plano_peca("supressor_fogo", w + Vector2i(1, 8), rs))
		p.call(con.plano_peca("coletor_chuva", w + Vector2i(4, 3), 0))
		p.call(con.plano_linha("cano", w + Vector2i(5, 2), w + Vector2i(5, 1), 2))
		p.call(con.plano_peca("condensador_neblina", w + Vector2i(7, 7), 0))
		p.call(con.plano_linha("cano", w + Vector2i(7, 6), w + Vector2i(7, 5), 2))
		p.call(con.plano_peca("gerador", w + Vector2i(4, 8), 0))
		p.call(con.plano_peca("poste_energia", w + Vector2i(3, 6), 0))
		p.call(con.plano_peca("poste_energia", w + Vector2i(3, 2), 0))
		p.call(con.plano_peca("poste_energia", w + Vector2i(6, 6), 0))
		for id in m.estruturas:
			ids[m.estruturas[id].nome] = id
		print("AGUA construiu ", ids.keys())
		cena.clima.forcar("chuva", true)
		var a: AmbienteVivo = cena.ambiente
		for r in range(2, 7):
			for k in 16:
				var t := w + Vector2i(1, 8) + Vector2i((Vector2.from_angle(k * TAU / 16.0) * r).round())
				if a.fogo.is_empty() and a._inflamavel(t):
					a._acender(t)
		print("AGUA fogo ", a.fogo.keys())
		cena.camera.alvo = Grade.centro_mundo(w + Vector2i(4, 5))
		cena.camera.distancia = 16.0
		cena.camera.posicionar())
	em(6, func():
		cena.fabrica.reconstruir()
		for id in cena.fabrica.combustivel:
			cena.fabrica.combustivel[id] = 500.0)
	var k := 0
	for nome in ["bomba_agua", "coletor_chuva", "condensador_neblina", "supressor_fogo", "cano_reto"]:
		k += 1
		em(40 + k * 60, func():
			if ids.has(nome):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("AGUA painel ", nome))
	em(1100, func():
		var f: Fabrica = cena.fabrica
		var est := {}
		for id in f.maquinas:
			est[cena.mapa.estruturas[id].nome] = [Maquina.Estado.keys()[f.maquinas[id].estado], f.maquinas[id].fluidos,
					snappedf(f.maquinas[id].velocidade, 0.01), snappedf(f.maquinas[id].energia, 0.01), f.maquinas[id].produzidos]
		print("AGUA estados ", est)
		print("AGUA redes ", f.redes_fluido.map(func(rd): return "%s %.0f/%.0f" % [rd.fluido, rd.qtd, rd.cap]))
		print("AGUA fogo restante ", cena.ambiente.fogo.size(), " jatos ", f.jatos))


## Lote 16 (trilhos, drones e lógica) sem janela: num chão plano monta uma linha com trilho energizado, sinal em
## cadeia, duas estações com bomba de estação, cano e tanque; põe um trem elétrico e um trem-tanque; uma esteira com
## sensor e um comparador mandando num braço; sensor de tanque e válvula entre duas redes; baú de estoque; braço
## quântico com alcance 3. Abre o painel de cada peça nova e imprime o estado. `-- modo demo roteiro lote16`.
func _roteiro_lote16() -> void:
	var ids := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(40, 300, 3):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 22):
					for j in range(-2, 34):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("LOTE16 chão ", o)
		if o.x == 9999:
			return
		_sem_ninhos(o + Vector2i(10, 16))
		for i in range(-2, 22):
			for j in range(-2, 34):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		var leste := Construtor.rot_do_fluxo(1)
		# ferrovia: x = o.x, de y 0 a 31, energizada no meio; sinal em cadeia; estações A (y 22) e B (y 4)
		p.call(con.plano_peca("trilho_fim", o + Vector2i(0, 0), 2))
		p.call(con.plano_linha("trilho_reto", o + Vector2i(0, 1), o + Vector2i(0, 9), 0))
		p.call(con.plano_linha("trilho_energizado", o + Vector2i(0, 10), o + Vector2i(0, 20), 0))
		p.call(con.plano_linha("trilho_reto", o + Vector2i(0, 21), o + Vector2i(0, 30), 0))
		p.call(con.plano_peca("trilho_fim", o + Vector2i(0, 31), 0))
		p.call(con.plano_peca("sinal_cadeia", o + Vector2i(-1, 14), 0))
		p.call(con.plano_peca("sinal_trem", o + Vector2i(-1, 17), 0))
		p.call(con.plano_peca("estacao", o + Vector2i(1, 22), 0))
		p.call(con.plano_peca("estacao", o + Vector2i(1, 4), 0))
		p.call(con.plano_peca("bomba_estacao", o + Vector2i(3, 23), leste))
		p.call(con.plano_linha("cano", o + Vector2i(4, 23), o + Vector2i(5, 23), leste))
		p.call(con.plano_peca("tanque", o + Vector2i(6, 23), 0))
		p.call(con.plano_peca("bomba_estacao", o + Vector2i(3, 5), leste))
		p.call(con.plano_linha("cano", o + Vector2i(4, 5), o + Vector2i(5, 5), leste))
		p.call(con.plano_peca("tanque", o + Vector2i(6, 5), 0))
		p.call(con.plano_peca("gerador", o + Vector2i(9, 14), 0))
		for y in [6, 12, 18, 24]:
			p.call(con.plano_peca("poste_energia", o + Vector2i(2, y), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(7, 14), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(11, 10), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(14, 15), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(11, 5), 0))
		# lógica: esteira com sensor e comparador mandando num braço; sensor de tanque + válvula entre duas redes
		p.call(con.plano_linha("esteira", o + Vector2i(10, 2), o + Vector2i(18, 2), leste))
		p.call(con.plano_peca("sensor_esteira", o + Vector2i(14, 1), 0))
		p.call(con.plano_peca("bau", o + Vector2i(12, 4), 0))
		p.call(con.plano_peca("braco", o + Vector2i(12, 3), 0))
		p.call(con.plano_peca("comparador", o + Vector2i(13, 3), 0))
		p.call(con.plano_peca("cano_reto", o + Vector2i(10, 8), leste))
		p.call(con.plano_peca("sensor_tanque", o + Vector2i(11, 8), leste))
		p.call(con.plano_peca("valvula", o + Vector2i(12, 8), leste))
		p.call(con.plano_peca("cano_reto", o + Vector2i(13, 8), leste))
		p.call(con.plano_peca("bau_estoque", o + Vector2i(16, 10), 0))
		p.call(con.plano_peca("bau", o + Vector2i(16, 13), 0))
		p.call(con.plano_peca("braco_quantico", o + Vector2i(16, 16), 0))
		p.call(con.plano_peca("bau", o + Vector2i(16, 17), 0))
		for id in m.estruturas:
			ids[m.estruturas[id].nome] = id
		var bq: int = ids.get("braco_quantico", -1)
		if bq >= 0:
			m.estruturas[bq]["alcance"] = 3
		p.call(con.plano_peca("trem_eletrico", o + Vector2i(0, 14), 0))
		p.call(con.plano_peca("trem_tanque", o + Vector2i(0, 1), 0))
		print("LOTE16 construiu ", ids.keys(), " trens ", cena.trens.map(func(t): return t.peca()))
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(8, 14))
		cena.camera.distancia = 26.0
		cena.camera.posicionar())
	em(6, func():
		if w[0].x == 9999:
			return
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 5000.0
		var o: Vector2i = w[0]
		if ids.has("bau_estoque"):
			f.baus[ids.bau_estoque]["engrenagem"] = 20
		var bq: int = ids.get("braco_quantico", -1)
		if bq >= 0:
			var de: int = cena.mapa.tiles.get(o + Vector2i(16, 13), -1)
			if de >= 0:
				f.baus[de]["placa_ferro"] = 64
		var est: Dictionary = cena.estoques
		for e in cena.grafo.estacoes:
			Fabrica.tanque_estacao(est[e.estrutura])
		var ea: int = cena.mapa.tiles.get(o + Vector2i(1, 22), -1)
		if ea >= 0:
			est[ea].fluido.modo = "carregar"
		var r := f.rede_de(cena.mapa.tiles.get(o + Vector2i(5, 23), -1))
		if not r.is_empty():
			r.fluido = "agua"
			r.qtd = 20000.0
		var eb: int = cena.mapa.tiles.get(o + Vector2i(1, 4), -1)
		for t in cena.trens:
			if t.peca() != "trem":                    # os da linha nova rodam entre as duas estações dela
				t.rota.assign([ea, eb])
				t.condicoes[str(ea)] = "tempo"
				t.planejar()
		var rs := f.rede_de(cena.mapa.tiles.get(o + Vector2i(10, 8), -1))
		if not rs.is_empty():
			rs.fluido = "seiva"
			rs.qtd = 250.0)
	for q in range(10, 400, 8):                       # itens passando pelo sensor de esteira
		em(q, func():
			if w[0].x == 9999:
				return
			var t: Vector2i = w[0] + Vector2i(10, 2)
			if cena.fabrica._no_tile.has(t):
				var a: Array = cena.fabrica._no_tile[t]
				cena.fabrica.caminhos[a[0]].esteira.inserir_na_entrada("pedra"))
	var k := 0
	for nome in ["sinal_cadeia", "bomba_estacao", "trilho_energizado", "sensor_esteira", "sensor_tanque", "comparador", "valvula",
			"bau_estoque", "braco_quantico"]:
		k += 1
		em(30 + k * 20, func():
			if ids.has(nome):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("LOTE16 painel ", nome))
	em(260, func():
		for t in cena.trens:
			cena._sel = {"trem": t.id}
			cena._detalhe()
			print("LOTE16 painel trem ", t.peca()))
	em(890, func():
		var f: Fabrica = cena.fabrica
		print("LOTE16 trens ", cena.trens.map(func(t): return "%s %s v=%.1f vmax=%.1f fluido %.0f" % [t.peca(), Trem.Estado.keys()[t.estado], t.v, t.vel_max, t.fluido_qtd]))
		print("LOTE16 canais ", f.canais, " desligados ", f.logica_off.keys(), " sensores ", f.sensores)
		print("LOTE16 bombas ", f.bombeando, " válvulas ", f.valvula_passou, " estoques ", cena.estoques.values().map(func(e): return e.get("fluido", {})))
		if ids.has("braco_quantico"):
			print("LOTE16 braço quântico entregou ", f.bracos[ids.braco_quantico].entregues, " energia ", f.bracos[ids.braco_quantico].energia))


## Combate do meio (fase 2.4) sem janela: num chão plano longe do spawn monta lança-foguetes, artilharia, mina, muros de
## liga e de campo e o gerador de escudo (com gerador e postes), abastece, solta um ataque e imprime o que aconteceu
## (tiros, explosões, pulsos, impactos no escudo, vida dos muros) e os painéis. `-- modo demo roteiro combate`.
func _roteiro_combate() -> void:
	var ids := {}
	var cont := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(40, 260, 3):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 26):
					for j in range(-2, 16):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("COMBATE chão ", o)
		if o.x == 9999:
			return
		_sem_ninhos(o + Vector2i(12, 6))
		for i in range(-2, 26):
			for j in range(-2, 16):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("gerador", o + Vector2i(0, 0), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(3, 2), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(8, 2), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(13, 4), 0))
		p.call(con.plano_peca("gerador_escudo", o + Vector2i(5, 4), 0))
		p.call(con.plano_peca("torre_foguetes", o + Vector2i(9, 5), 0))
		p.call(con.plano_peca("artilharia", o + Vector2i(1, 6), 0))
		p.call(con.plano_linha("muro_liga", o + Vector2i(16, 2), o + Vector2i(16, 6), 0))
		p.call(con.plano_linha("muro_escudo", o + Vector2i(16, 7), o + Vector2i(16, 11), 0))
		p.call(con.plano_peca("mina_pulso", o + Vector2i(19, 5), 0))
		for id in m.estruturas:
			ids[m.estruturas[id].nome] = id
		print("COMBATE construiu ", ids.keys())
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(10, 6))
		cena.camera.distancia = 22.0
		cena.camera.posicionar())
	em(6, func():
		if w[0].x == 9999:
			return
		var f: Fabrica = cena.fabrica
		var col: Colonia = cena.colonia
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 500.0
		if ids.has("torre_foguetes"):
			col.carregar_torre(ids.torre_foguetes, 18)
		if ids.has("artilharia"):
			col.carregar_torre(ids.artilharia, 10)
		var o: Vector2i = w[0]
		var ninho := -1
		for k in 40:                                     # ninho para a artilharia, a ~60 m
			var t := o + Vector2i((Vector2.from_angle(k * 0.3) * 60.0).round())
			for i in range(-1, 5):
				for j in range(-1, 5):
					cena.mapa.limpar_obstaculo(t + Vector2i(i, j))
			ninho = col._criar_ninho(t, 1.0)
			if ninho >= 0:
				break
		print("COMBATE ninho ", ninho)
		var alvo: int = ids.get("gerador_escudo", -1)
		for k in 6:                                      # ataque vindo do leste, passando pela mina e pelos muros
			var a := col._nova_aranha(ninho) if ninho >= 0 else -1
			if a < 0:
				continue
			col.aranhas[a].pos = Vector2(o + Vector2i(24, 4 + k))
			col.aranhas[a].estado = Colonia.E.ATACANDO
			col.aranhas[a].alvo = alvo)
	em(700, func():                                      # segunda onda, com as torres já sem munição: mina, muros, escudo
		if w[0].x == 9999 or cena.colonia.ninhos.is_empty():
			return
		var col: Colonia = cena.colonia
		var o: Vector2i = w[0]
		for k in 4:
			var a := col._nova_aranha(col.ninhos.keys()[0])
			col.aranhas[a].pos = Vector2(o + Vector2i(22, 4 + k))
			col.aranhas[a].estado = Colonia.E.ATACANDO
			col.aranhas[a].alvo = ids.get("muro_escudo", -1) if k % 2 == 0 else ids.get("gerador_escudo", -1))
	for q in range(8, 1300):
		em(q, func():
			for e in cena.colonia.eventos:
				cont[e.tipo] = int(cont.get(e.tipo, 0)) + 1)
	var k := 0
	for nome in ["torre_foguetes", "artilharia", "mina_pulso", "gerador_escudo", "muro_escudo"]:
		k += 1
		em(300 + k * 60, func():
			if ids.has(nome) and cena.mapa.estruturas.has(ids[nome]):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("COMBATE painel ", nome))
	em(1300, func():
		var col: Colonia = cena.colonia
		var vidas := {}
		for nome in ids:
			if col.vida.has(ids[nome]):
				vidas[nome] = snappedf(float(col.vida[ids[nome]]), 0.1)
		print("COMBATE eventos ", cont)
		print("COMBATE munição ", col.torres.keys().map(func(t): return [cena.mapa.estruturas[t].nome if cena.mapa.estruturas.has(t) else "?", col.torres[t].municao]))
		print("COMBATE escudo MJ ", snappedf(float(cena.fabrica.carga_torre.get(ids.get("gerador_escudo", -1), -1.0)), 0.01), " vidas ", vidas, " aranhas ", col.aranhas.size()))


## Clima (fase 2.5) sem janela: num chão plano monta gerador, postes, acumuladores, para-raios (comum e de cristal),
## captador de carga (com cristal e água), semeador com coletor de chuva, defletor, cúpula e regulador, solta uma
## tempestade e raios em pontos escolhidos (no captador, na cúpula, no regulador, no para-raios, numa fornalha
## desprotegida) e imprime o que aconteceu e os painéis. `-- modo demo roteiro clima`.
func _roteiro_clima() -> void:
	var ids := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(40, 300, 3):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 34):
					for j in range(-2, 14):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("CLIMA chão ", o)
		if o.x == 9999:
			return
		_sem_ninhos(o + Vector2i(16, 6))
		for i in range(-2, 34):
			for j in range(-2, 14):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("gerador", o + Vector2i(0, 0), 0))
		for x in [3, 8, 13, 18, 23, 28]:
			p.call(con.plano_peca("poste_energia", o + Vector2i(x, 3), 0))
		p.call(con.plano_peca("acumulador", o + Vector2i(4, 0), 0))
		p.call(con.plano_peca("acumulador", o + Vector2i(9, 0), 0))
		p.call(con.plano_peca("para_raios", o + Vector2i(7, 5), 0))
		p.call(con.plano_peca("para_raios_2", o + Vector2i(30, 5), 0))
		p.call(con.plano_peca("captador_carga", o + Vector2i(14, 0), 0))
		p.call(con.plano_peca("semeador_nuvens", o + Vector2i(1, 6), 0))
		p.call(con.plano_peca("coletor_chuva", o + Vector2i(4, 9), 0))
		p.call(con.plano_peca("defletor_vento", o + Vector2i(19, 0), 1))
		p.call(con.plano_peca("cupula_raios", o + Vector2i(24, 0), 0))
		p.call(con.plano_peca("fornalha", o + Vector2i(11, 9), 0))
		for id in m.estruturas:
			ids[m.estruturas[id].nome] = id
		print("CLIMA construiu ", ids.keys())
		cena.clima.forcar("tempestade", true)
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(15, 6))
		cena.camera.distancia = 26.0
		cena.camera.posicionar())
	em(6, func():
		if w[0].x == 9999:
			return
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 500.0
		if ids.has("captador_carga"):
			var mq: Maquina = f.maquinas[ids.captador_carga]
			mq.receber("cristal_lapidado")
			mq.receber("cristal_lapidado")
			mq.receber_fluido("agua", 90.0))
	em(40, func():                                       # raios em pontos escolhidos
		if w[0].x == 9999:
			return
		var r: Raios = cena.raios
		var o := Vector2(w[0])
		var cu: int = ids.get("cupula_raios", -1)
		if cu >= 0:                                      # cúpula desligada: os outros pegam
			cena.mapa.estruturas[cu]["desligada"] = true
		cena.clima_local.atualizar()
		for alvo in [["captador", Vector2(15.5, 1.5)], ["para_raios", Vector2(7.5, 8.5)], ["fornalha", Vector2(12.0, 10.0)],
				["para_raios_2", Vector2(31.0, 12.0)], ["chão_longe", Vector2(-40.0, 40.0)]]:
			var q := r.cair(o + alvo[1])
			print("CLIMA raio em %s → %s (alt %.1f, %s MJ)" % [alvo[0], q.tipo, float(q.get("alt", 0.0)), q.get("mj", "-")])
		if cu >= 0:
			cena.mapa.estruturas[cu].erase("desligada")
		cena.clima_local.atualizar()
		for alvo in [["cupula_ligada", Vector2(31.0, 12.0)], ["captador_sob_a_cupula", Vector2(15.5, 1.5)]]:
			var q := r.cair(o + alvo[1])
			print("CLIMA raio em %s → %s (alt %.1f, %s MJ)" % [alvo[0], q.tipo, float(q.get("alt", 0.0)), q.get("mj", "-")]))
	em(120, func():
		var cl: ClimaLocal = cena.clima_local
		print("CLIMA zonas ", cl.zonas.map(func(z): return [z.tipo, z.raio]))
		if ids.has("coletor_chuva"):
			print("CLIMA chuva no coletor ", cena.fabrica.chuva_maq.get(ids.coletor_chuva, -1.0)))
	var k := 0
	for nome in ["para_raios", "para_raios_2", "captador_carga", "semeador_nuvens", "defletor_vento", "cupula_raios", "coletor_chuva"]:
		k += 1
		em(150 + k * 20, func():
			if ids.has(nome) and cena.mapa.estruturas.has(ids[nome]):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("CLIMA painel ", nome))
	em(900, func():
		var f: Fabrica = cena.fabrica
		var r: Raios = cena.raios
		var mq: Maquina = f.maquinas.get(ids.get("captador_carga", -1))
		print("CLIMA raios total %d, descargas %s" % [r.total, r.descargas])
		print("CLIMA acumulado ", f.acumulado.values().map(func(v): return snappedf(v, 0.1)))
		if mq != null:
			print("CLIMA captador ", Maquina.Estado.keys()[mq.estado], " pronto ", mq.saidas, " dentro ", mq.entradas, " agua ", mq.fluidos)
		var vidas := {}
		for nome in ids:
			if cena.colonia.vida.has(ids[nome]):
				vidas[nome] = snappedf(float(cena.colonia.vida[ids[nome]]), 0.1)
		print("CLIMA vidas ", vidas, " fogo ", cena.ambiente.fogo.size()))


## Drones (fase 2.6): três estações (reparo, combate, logística) num chão plano longe de ninhos; muro mordido, aranhas
## soltas e dois baús (provedor → requisitante). Imprime o que os drones fizeram e o que o desenho mostrou.
func _roteiro_drones() -> void:
	var ids := {}
	var cont := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(40, 300, 3):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 34):
					for j in range(-2, 18):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("DRONES chão ", o)
		if o.x == 9999:
			return
		_sem_ninhos(o + Vector2i(16, 8))
		for i in range(-2, 34):
			for j in range(-2, 18):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("gerador", o + Vector2i(0, 0), 0))
		for x in [3, 9, 15, 21, 27]:
			p.call(con.plano_peca("poste_energia", o + Vector2i(x, 3), 0))
		p.call(con.plano_peca("estacao_drones", o + Vector2i(4, 0), 0))
		p.call(con.plano_peca("estacao_drones", o + Vector2i(14, 0), 0))
		p.call(con.plano_peca("estacao_drones", o + Vector2i(24, 0), 0))
		for x in range(4, 12):
			p.call(con.plano_peca("muro_centro", o + Vector2i(x, 10), 0))
		p.call(con.plano_peca("bau", o + Vector2i(22, 12), 0))
		p.call(con.plano_peca("bau", o + Vector2i(30, 14), 0))
		for id in m.estruturas:
			var e: Dictionary = m.estruturas[id]
			if e.nome == "estacao_drones":
				ids["est_%d" % int(e.minimo.x - o.x)] = id
			elif e.nome == "bau":
				ids["bau_%d" % int(e.minimo.x - o.x)] = id
			elif e.nome == "muro_centro":
				ids["muro_%d" % int(e.minimo.x - o.x)] = id
		print("DRONES construiu ", ids.keys())
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(15, 6))
		cena.camera.distancia = 26.0
		cena.camera.posicionar())
	em(6, func():
		if w[0].x == 9999 or not ids.has("est_4"):
			return
		var f: Fabrica = cena.fabrica
		var dr: Drones = cena.drones
		var m: MapaOcupacao = cena.mapa
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 500.0
		var tipos := {"est_4": "reparo", "est_14": "combate", "est_24": "logistico"}
		for k in tipos:
			dr.definir_tipo(ids[k], tipos[k])
			for i in 3:
				dr.novo(ids[k])
		var mq: Maquina = f.maquinas[ids.est_4]                 # a estação de reparo monta mais um
		for it in ["placa_ferro", "placa_ferro", "placa_ferro", "placa_ferro", "motor", "circuito", "circuito"]:
			mq.receber(it)
		mq.receber_fluido("agua", 60.0)
		for x in [4, 6, 8, 10]:                                  # muro mordido
			cena.colonia.vida[ids["muro_%d" % x]] = 120.0
		var o := Vector2(w[0])
		for k in 3:                                              # aranhas soltas (sem ninho: vão morder o muro)
			cena.colonia.aranhas[9000 + k] = {"id": 9000 + k, "pos": o + Vector2(6 + k * 2, 16), "vida": 60.0, "ninho": -1,
					"estado": Colonia.E.PARADA, "alvo": -1, "destino": o + Vector2(6 + k * 2, 16), "mordendo": false, "t": 0.0, "preso": 0.0}
		m.estruturas[ids.bau_22]["logistica"] = "provedor"
		m.estruturas[ids.bau_30]["logistica"] = "requisitante"
		m.estruturas[ids.bau_30]["pede_item"] = "engrenagem"
		m.estruturas[ids.bau_30]["pede_qtd"] = 4
		f.baus[ids.bau_22]["engrenagem"] = 20)
	em(7, func():
		var dr: Drones = cena.drones
		print("DRONES frota ", dr.drones.size(), " tipos ", dr.estacoes().map(func(e): return dr.tipo_de(e))))
	var t_ant := [-1.0]
	for q in range(8, 2400):
		em(q, func():
			if float(cena._tempo) != t_ant[0]:                 # só conta os eventos de um tick novo
				t_ant[0] = float(cena._tempo)
				for e in cena.drones.eventos:
					cont[e.tipo] = int(cont.get(e.tipo, 0)) + 1
			var dd: DesenhoDrones = cena._desenho_drones
			cont["max_visiveis"] = maxi(int(cont.get("max_visiveis", 0)), dd.visiveis())
			cont["max_scan"] = maxi(int(cont.get("max_scan", 0)), dd.escaneando().size())
			cont["max_capsulas"] = maxi(int(cont.get("max_capsulas", 0)), cena._desenho_colonia.capsulas()))
	var k := 0
	for nome in ["est_4", "est_14", "est_24", "bau_30"]:
		k += 1
		em(300 + k * 20, func():
			if ids.has(nome) and cena.mapa.estruturas.has(ids[nome]):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("DRONES painel ", nome))
	em(2398, func():
		var dr: Drones = cena.drones
		print("DRONES tempo de jogo %.1f s" % cena._tempo)
		var vidas := {}
		for x in [4, 6, 8, 10]:
			vidas[x] = cena.colonia.vida.get(ids.get("muro_%d" % x, -1), "inteiro")
		print("DRONES eventos ", cont)
		print("DRONES muros ", vidas, " aranhas soltas ", [9000, 9001, 9002].filter(func(a): return cena.colonia.aranhas.has(a)).size())
		if ids.has("bau_30") and cena.fabrica.baus.has(ids.bau_30):
			print("DRONES requisitante ", cena.fabrica.baus[ids.bau_30], " provedor ", cena.fabrica.baus.get(ids.bau_22, {}))
		print("DRONES aranhas ", [9000, 9001, 9002].map(func(a): return cena.colonia.aranhas[a].vida if cena.colonia.aranhas.has(a) else "morta"))
		print("DRONES estados ", dr.drones.values().map(func(d): return [d.tipo, Drones.NOMES_ESTADO[int(d.e)]])))



## Limpeza nova (fase 2.6): coletor 2, purificadores, viveiro 2, semeador de bioma e biodigestor ligados num chão
## sujo e queimado; abre o painel de cada um e imprime o efeito no ambiente.
func _roteiro_limpeza2() -> void:
	var ids := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(40, 300, 3):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 34):
					for j in range(-2, 14):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("LIMPEZA2 chão ", o)
		if o.x == 9999:
			return
		_sem_ninhos(o + Vector2i(16, 6))
		for i in range(-2, 34):
			for j in range(-2, 14):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("gerador", o + Vector2i(0, 0), 0))
		p.call(con.plano_peca("gerador", o + Vector2i(0, 8), 0))
		for x in [3, 9, 15, 21, 27]:
			p.call(con.plano_peca("poste_energia", o + Vector2i(x, 4), 0))
		var lugares := {"coletor_lixo_2": Vector2i(4, 0), "purificador_ar": Vector2i(8, 0), "purificador_ar_2": Vector2i(12, 0),
				"viveiro_2": Vector2i(17, 0), "semeador_bioma": Vector2i(21, 0), "biodigestor": Vector2i(26, 0)}
		for n in lugares:
			p.call(con.plano_peca(n, o + lugares[n], 0))
		for id in m.estruturas:
			if lugares.has(m.estruturas[id].nome):
				ids[m.estruturas[id].nome] = id
		print("LIMPEZA2 construiu ", ids.keys())
		var a: AmbienteVivo = cena.ambiente
		for i in range(-2, 34):
			for j in range(-2, 14):
				a.somar(o + Vector2i(i, j), AmbienteVivo.SUJ, 0.4)
				a.somar(o + Vector2i(i, j), AmbienteVivo.QUEIM, 0.5)
		cena.poluicao.emitir(o + Vector2i(13, 1), 300.0)
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(15, 5))
		cena.camera.distancia = 26.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 500.0
		if ids.has("biodigestor"):
			var mq: Maquina = f.maquinas[ids.biodigestor]
			for i in 8:
				mq.receber("residuo")
			mq.receber_fluido("agua", 80.0))
	for q in range(8, 1200, 30):
		em(q, func():
			var f: Fabrica = cena.fabrica
			for n in ["viveiro_2", "semeador_bioma"]:
				if ids.has(n) and f.maquinas.has(ids[n]):
					f.maquinas[ids[n]].receber_fluido("seiva", 40.0))
	var k := 0
	for nome in ["coletor_lixo_2", "purificador_ar", "purificador_ar_2", "viveiro_2", "semeador_bioma", "biodigestor"]:
		k += 1
		em(200 + k * 20, func():
			if ids.has(nome) and cena.mapa.estruturas.has(ids[nome]):
				cena._sel = {"estrutura": ids[nome]}
				cena._detalhe()
				print("LIMPEZA2 painel ", nome, " ", Maquina.Estado.keys()[cena.fabrica.maquinas[ids[nome]].estado]))
	em(1190, func():
		if w[0].x == 9999:
			return
		var f: Fabrica = cena.fabrica
		var a: AmbienteVivo = cena.ambiente
		var o: Vector2i = w[0]
		print("LIMPEZA2 tempo %.1f s" % cena._tempo)
		print("LIMPEZA2 sujeira perto do coletor 2 %.3f, longe %.3f" % [a.valor(o + Vector2i(5, 6), AmbienteVivo.SUJ), a.valor(o + Vector2i(33, 13), AmbienteVivo.SUJ)])
		print("LIMPEZA2 queimado perto do semeador %.3f" % a.valor(o + Vector2i(22, 5), AmbienteVivo.QUEIM))
		print("LIMPEZA2 poluição no chunk %.1f" % cena.poluicao.em(o + Vector2i(13, 1)))
		print("LIMPEZA2 mudas %d com espécie %d" % [a.plantas.size(), a.especies.size()])
		for n in ids:
			if f.maquinas.has(ids[n]):
				var mq: Maquina = f.maquinas[ids[n]]
				print("LIMPEZA2 %s %s saídas %s fluidos %s" % [n, Maquina.Estado.keys()[mq.estado], mq.saidas, mq.fluidos]))


func _roteiro_limpeza() -> void:
	em(2, func():
		var w := Vector2i(9999, 0)
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var g := Grade.gerador
		for r in range(6, 200, 2):
			for k in 48:
				var c := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w.x != 9999 or not g.terreno(c) in [GeradorMundo.Terreno.RIO, GeradorMundo.Terreno.LAGO]:
					continue
				var ok := true
				for i in range(1, 13):
					for j in range(-4, 5):
						var t := c + Vector2i(i, j)
						if g.terreno(t) != GeradorMundo.Terreno.TERRA or g.nivel(t) != g.nivel(c + Vector2i(1, 0)) or g.em_encosta(t):
							ok = false
				if ok:
					w = c
		print("LIMPEZA margem ", w)
		_canal = w
		var con: Construtor = cena.construtor
		for i in range(-2, 16):
			for j in range(-8, 9):
				cena.mapa.limpar_obstaculo(w + Vector2i(i, j))
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("filtro_agua", w + Vector2i(1, -1), 0))
		p.call(con.plano_peca("coletor_lixo", w + Vector2i(4, 1), 0))
		p.call(con.plano_peca("viveiro", w + Vector2i(9, -4), 0))
		p.call(con.plano_peca("gerador", w + Vector2i(10, 2), 0))
		p.call(con.plano_peca("poste_energia", w + Vector2i(7, 1), 0))
		p.call(con.plano_peca("poste_energia", w + Vector2i(3, 0), 0))
		var a: AmbienteVivo = cena.ambiente
		for y in range(-8, 9):
			for x in range(-4, 15):
				var t := w + Vector2i(x, y)
				if g.eh_agua(g.terreno(t)):
					a.somar(t, AmbienteVivo.AGUA, 0.7)
				elif Vector2(x - 5, y - 2).length() < 6.0:
					a.somar(t, AmbienteVivo.SUJ, 0.55)
					if (x + y) % 3 == 0:
						a.somar(t, AmbienteVivo.OLEO, 0.6)
				elif Vector2(x - 10, y + 2).length() < 7.0:
					a.somar(t, AmbienteVivo.QUEIM, 0.8)
		for i in 14:
			var t: Variant = a.plantar_perto(Vector2(w + Vector2i(10, -3)), 8.0)
			if t != null:
				a.plantas[t] = [0.08, 0.35, 0.7, 1.0][i % 4]
		a.versao_plantas += 1
		_sem_ninhos(w)
		cena.camera.alvo = Grade.centro_mundo(w + Vector2i(6, -3))
		cena.camera.distancia = 12.0
		cena.camera.posicionar())
	em(6, func():
		_sem_ninhos(_canal)
		if OS.get_cmdline_user_args().has("perto"):
			cena.camera.alvo = Grade.centro_mundo(_canal + Vector2i(5, -3))
			cena.camera.distancia = 7.5
			cena.camera.posicionar()
		for id in cena.fabrica.combustivel:
			cena.fabrica.combustivel[id] = 500.0
		for id in cena.fabrica.maquinas:
			var m: Maquina = cena.fabrica.maquinas[id]
			if m.nome == "viveiro":
				m.fluidos["seiva"] = 1000.0
				m.acordar()
		Engine.time_scale = 6.0)


var _med := {}


func _roteiro_medir() -> void:
	var etapas := [["tudo", func(): pass],
		["sem árvores/vegetação", func(): _vegetacao(false)],
		["sem grama", func(): _vegetacao(true); _grama(false)],
		["sem sombras", func(): _grama(true); (cena.get_node("Sol") as DirectionalLight3D).shadow_enabled = false],
		["céu parado", func(): (cena.get_node("Sol") as DirectionalLight3D).shadow_enabled = true; _desenho_clima().mexer_ceu = false],
		["só céu parado + sem árvores + sem grama", func(): _vegetacao(false); _grama(false)]]
	em(3, func():
		Sessao.config.fps = false
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var cam: CameraJogo = cena.camera
		cam.distancia = 60.0
		cam.posicionar())
	for i in etapas.size():
		var e: Array = etapas[i]
		em(120 + i * 150, func():
			e[1].call()
			_med = {"nome": e[0], "n": 0, "gpu": 0.0, "cpu": 0.0, "draw": 0, "prim": 0})
		for q in range(150 + i * 150, 265 + i * 150):
			em(q, func():
				var vp := get_viewport().get_viewport_rid()
				_med.n += 1
				_med.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				_med.cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
				_med.draw += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				_med.prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		em(266 + i * 150, func():
			var n := float(_med.n)
			print("MEDIDA %-40s gpu %.2f ms · cpu render %.2f ms · %d chamadas · %d mil triângulos" % [_med.nome, _med.gpu / n, _med.cpu / n, int(_med.draw / n), int(_med.prim / n / 1000.0)]))


func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		t += (idx.size() if idx.size() > 0 else v.size()) / 3
	return t


func _tris_superficie(m: Mesh, s: int) -> int:
	var a := m.surface_get_arrays(s)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	return (idx.size() if idx.size() > 0 else v.size()) / 3


func _inventario() -> void:
	var soma := {}
	var cont := {}
	var cache := {}
	for n in cena.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var chave := ""
		var tris := 0
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			if not cache.has(mm.mesh):
				cache[mm.mesh] = _tris(mm.mesh)
			var vis := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = int(cache[mm.mesh]) * vis
			chave = "MM " + str(g.name).get_slice("#", 0).rstrip("0123456789_")
			if str(g.get_parent().get_class()) == "Node3D" and g.get_parent() is DesenhoChunk and g == g.get_parent().grama:
				chave = "MM grama"
		elif g is MeshInstance3D:
			var me := (g as MeshInstance3D).mesh
			if me == null:
				continue
			if not cache.has(me):
				cache[me] = _tris(me) if not (me is ImmediateMesh) else 0
			tris = int(cache[me])
			chave = "MI " + str(g.get_parent().name).left(18) + "/" + str(g.name).left(14)
			if g.get_parent() is DesenhoChunk:
				chave = "MI chunk/" + str(g.name).left(14)
		else:
			chave = g.get_class()
		soma[chave] = int(soma.get(chave, 0)) + tris
		cont[chave] = int(cont.get(chave, 0)) + 1
	var ks := soma.keys()
	ks.sort_custom(func(a, b): return soma[a] > soma[b])
	var total := 0
	for k in soma:
		total += soma[k]
	print("INVENT total %d mil triângulos em cena (visíveis, sem recorte)" % (total / 1000))
	for k in ks.slice(0, 18):
		print("INVENT %-46s %8d mil  (%d nós)" % [k, soma[k] / 1000, cont[k]])


func _vegetacao(sim: bool) -> void:
	for k in cena.chunks:
		for o in cena.chunks[k]._objetos:
			if Registro.modelos.get(str(o.name).get_slice("#", 0), {}).get("categoria", "") == "mapa/vegetacao":
				o.visible = sim


func _grama(sim: bool) -> void:
	for k in cena.chunks:
		cena.chunks[k].ajustar_grama(Vector2(cena.camera.alvo.x, -cena.camera.alvo.z), not sim)


func _desenho_clima() -> DesenhoClima:
	for c in cena.get_children():
		if c is DesenhoClima:
			return c
	return null


## Canto (12×12 tiles) com mais árvores destas espécies num raio de 90 tiles do início.
func _bosque(especies: Array = ["arv_carvalho", "arv_betula"]) -> Vector2i:
	var g: GeradorMundo = cena.gerador
	var melhor := Vector2i.ZERO
	var mais := -1
	for cy in range(-90, 90, 6):
		for cx in range(-90, 90, 6):
			var n := 0
			for y in range(0, 12, 2):
				for x in range(0, 12, 2):
					var o := g.distribuicao.obstaculo(Vector2i(cx + x, cy + y))
					if not o.is_empty() and Distribuicao.especie(o.nome) in especies:
						n += 1
			if n > mais:
				mais = n
				melhor = Vector2i(cx, cy)
	print("BOSQUE em ", melhor, " árvores (amostra) ", mais)
	return melhor


## Tira ninhos (e suas aranhas) a até 60 tiles: cena só da limpeza.
## Lote 17 (proliferação) sem janela: num chão plano longe do spawn põe gerador, poste e um sensor de varredura; adianta
## o relógio dele para revelar um chunk por passo e imprime chunks revelados, ninhos marcados, jazidas medidas (a demo
## tem a Varredura profunda), as marcas desenhadas e o painel. Também põe um farol de cristal no poste e outro no posto
## avançado (energia própria, sem cabo), um lançador de sementes ligado ao posto com uma semente e alvo a 100 m:
## dispara, a cápsula voa e o pouso vira um posto avançado novo (na demonstração, colônia); a colônia manda um pacote
## gênese por cápsula ao receptor de cápsulas; dois transportadores quânticos no canal A trocam engrenagens; vira
## meia-noite e os faróis acendem; um silo de lançamento com o foguete montado (partes e carga postas pelo roteiro:
## as peças ainda não existem) lança — o roteiro não abre a tela de vitória.
## `-- modo demo roteiro lote17`.
## Lote 14 (energia II) + acumulador 2: uma linha de postes com as 6 peças e 6 refinadores de carga; reatores
## abastecidos pelo destino de braço e pelo cano. `-- modo demo roteiro lote14`.
func _roteiro_lote14() -> void:
	var ids := {}
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		var o := Vector2i(9999, 0)
		for r in range(60, 400, 4):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if o.x != 9999:
					break
				var ok := true
				for i in range(-2, 40):
					for j in range(-6, 8):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					o = t
		print("LOTE14 chão ", o)
		if o.x == 9999:
			return
		for i in range(-2, 40):
			for j in range(-6, 8):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(nome: String, d: Vector2i) -> int:
			cena.sincronizar(con.executar(con.plano_peca(nome, o + d, 0)))
			return int(m.tiles.get(o + d, -1))
		for x in range(0, 40, 6):
			p.call("poste_energia", Vector2i(x, 0))
		ids["ac2"] = p.call("acumulador_2", Vector2i(2, -2))
		ids["ta"] = p.call("turbina_alta", Vector2i(8, -3))
		ids["acc"] = p.call("acumulador_cristal", Vector2i(14, -2))
		ids["rc"] = p.call("reator_cristal", Vector2i(20, -3))
		ids["rf"] = p.call("reator_fusao", Vector2i(26, -3))
		ids["ns"] = p.call("nucleo_singularidade", Vector2i(32, -3))
		var e: Dictionary = m.estruturas[ids.rf]
		for pt in Registro.modelos.reator_fusao.portas:
			if pt.tipo == "FLUIDO":
				var pm := Grade.porta_no_mundo(pt, e.minimo, e.area, e.rot)
				cena.sincronizar(con.executar(con.plano_linha("cano", pm.tile_fora, pm.tile_fora + pm.dir, Construtor.rot_do_fluxo(Grade.DIRECOES.find(pm.dir)))))
				ids["cano"] = m.tiles.get(pm.tile_fora, -1)
		for x in range(0, 36, 6):
			ids["q%d" % x] = p.call("refinador", Vector2i(x, 3))
		print("LOTE14 construiu ", ids.values())
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(18, 0))
		cena.camera.distancia = 40.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 0.0
		var dc: Object = f.destino_em(cena.mapa.estruturas[ids.rc].minimo)
		print("LOTE14 reator de cristal aceita célula ", dc.aceita("celula_energia"), " carvão ", dc.aceita("carvao"))
		dc.receber("celula_energia")
		var df: Object = f.destino_em(cena.mapa.estruturas[ids.rf].minimo)
		df.receber("cristal_carregado")
		var rc := f.rede_de(int(ids.cano))
		rc.fluido = "agua"
		rc.qtd = 400.0)
	em(90, func():
		var f: Fabrica = cena.fabrica
		for k in ["ac2", "ta", "acc", "rc", "rf", "ns"]:
			var id: int = ids[k]
			var an: Animador = cena._animador(id)
			print("LOTE14 %s: %s kw %.0f comb %.0f acum %.1f água %.0f anima %s" % [k, cena.mapa.estruturas[id].nome, -f.kw_de(id), f.combustivel.get(id, 0.0), f.acumulado.get(id, 0.0),
					f.agua_reator.get(id, 0.0), an.ativo if an != null else "sem animador"])
			cena._sel = {"estrutura": id}
			cena._detalhe()
		print("LOTE14 painéis ok; rede ", f.rede.estat_de(ids.ns)))


## Lote 10 (produção I, 2ª parte): fornalha de aço, fornalha elétrica e laboratório 2 no mesmo poste; broca grande na
## jazida, com gerador próprio. Abastece e abre os painéis. `-- modo demo roteiro lote10`.
func _roteiro_lote10() -> void:
	var ids := {}
	em(2, func():
		Sessao.config.fps = false
		var m: MapaOcupacao = cena.mapa
		var con: Construtor = cena.construtor
		var o := Vector2i(9999, 0)
		for r in range(60, 400, 4):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if o.x == 9999 and m.gerador.distribuicao.jazida(t + Vector2i(1, 1)).get("tipo", "") in Registro.estruturas.broca_grande.requer_jazida:
					var ok := true
					for i in range(-2, 22):
						for j in range(-3, 8):
							var q := t + Vector2i(i, j)
							if m.gerador.terreno(q) != GeradorMundo.Terreno.TERRA or m.gerador.nivel(q) != m.gerador.nivel(t) or m.gerador.em_encosta(q) or m.tiles.has(q):
								ok = false
					if ok:
						o = t
		print("LOTE10 chão ", o)
		if o.x == 9999:
			return
		for i in range(-2, 22):
			for j in range(-3, 8):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var p := func(nome: String, d: Vector2i) -> int:
			cena.sincronizar(con.executar(con.plano_peca(nome, o + d, 0)))
			return int(m.tiles.get(o + d, -1))
		ids["broca"] = p.call("broca_grande", Vector2i(0, 0))
		var e: Dictionary = m.estruturas[ids.broca]
		var pm := Grade.porta_no_mundo(Registro.modelos.broca_grande.portas[0], e.minimo, e.area, e.rot)
		cena.sincronizar(con.executar(con.plano_linha("esteira", pm.tile_fora, pm.tile_fora + pm.dir, Construtor.rot_do_fluxo(Grade.DIRECOES.find(pm.dir)))))
		ids["ge"] = p.call("gerador", Vector2i(6, 0))
		p.call("poste_energia", Vector2i(4, 2))
		p.call("poste_energia", Vector2i(10, 2))
		p.call("poste_energia", Vector2i(16, 2))
		ids["aco"] = p.call("fornalha_aco", Vector2i(9, 3))
		ids["ele"] = p.call("fornalha_eletrica", Vector2i(12, 3))
		ids["lab"] = p.call("laboratorio_2", Vector2i(16, 5))
		print("LOTE10 construiu ", ids.values())
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(9, 2))
		cena.camera.distancia = 30.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		f.combustivel[ids.ge] = 5000.0
		f.combustivel[ids.aco] = 8.0
		for k in ["aco", "ele"]:
			var mq: Maquina = f.maquinas[ids[k]]
			for i in 40:
				f.destino_em(cena.mapa.estruturas[ids[k]].minimo).receber("minerio_ferro")
			print("LOTE10 ", k, " receita ", mq.receita_id)
		cena.pesquisa.ativa = "aco"
		f.laboratorios[ids.lab].pacotes = {"pacote_pesquisa": 10})
	em(120, func():
		var f: Fabrica = cena.fabrica
		for k in ["broca", "aco", "ele", "lab"]:
			var id: int = ids[k]
			var an: Animador = cena._animador(id)
			print("LOTE10 %s: %s kw %.0f comb %.1f emissão %.3f anima %s" % [k, cena.mapa.estruturas[id].nome, f.kw_de(id), f.combustivel.get(id, 0.0), f.emissao.get(id, 0.0),
					an.ativo if an != null else "sem animador"])
			cena._sel = {"estrutura": id}
			cena._detalhe()
		print("LOTE10 broca: ", f.maquinas[ids.broca].receita_id, " na esteira ", f.caminhos.filter(func(c): return not c.esteira.itens.is_empty()).size())
		print("LOTE10 pacotes do laboratório ", f.laboratorios[ids.lab].pacotes))


func _chao_lote11(m: MapaOcupacao) -> Vector2i:
	for r in range(40, 500, 4):
		for k in 24:
			var t := Vector2i((Vector2.from_angle(k * TAU / 24.0) * r).round())
			var ok := true
			for i in 26:
				for j in 12:
					var q := t + Vector2i(i, j)
					if m.gerador.terreno(q) != GeradorMundo.Terreno.TERRA or m.gerador.nivel(q) != m.gerador.nivel(t) or m.gerador.em_encosta(q) or m.tiles.has(q):
						ok = false
			if ok:
				for i in 26:
					for j in 12:
						m.limpar_obstaculo(t + Vector2i(i, j))
				return t
	return Vector2i(9999, 0)


## Lote 11 (produção II): as 8 peças num pátio com fonte própria, módulos encaixados e o painel de cada uma. `-- modo demo roteiro lote11`.
func _roteiro_lote11() -> void:
	var ids := {}
	em(2, func():
		Sessao.config.fps = false
		var m: MapaOcupacao = cena.mapa
		var con: Construtor = cena.construtor
		var o := _chao_lote11(m)
		print("LOTE11 chão ", o)
		if o.x == 9999:
			return
		var p := func(nome: String, d: Vector2i) -> int:
			var plano := con.plano_peca(nome, o + d, 0)
			if not Construtor.pode_tudo(plano):
				print("LOTE11 não coube ", nome, " ", plano.map(func(it): return it.motivo))
			cena.sincronizar(con.executar(plano))
			return int(m.tiles.get(o + d, -1))
		p.call("nucleo_singularidade", Vector2i(0, 0))
		for x in [3, 8, 13, 18, 23]:
			p.call("poste_energia", Vector2i(x, 4))
		ids["forja"] = p.call("forja_quantica", Vector2i(5, 0))
		ids["fundicao"] = p.call("fundicao_cristal", Vector2i(9, 0))
		ids["m3"] = p.call("montadora_3", Vector2i(13, 7))
		ids["mq"] = p.call("montadora_quantica", Vector2i(17, 0))
		ids["lab"] = p.call("laboratorio_quantico", Vector2i(5, 5))
		ids["irr"] = p.call("irradiador_modulos", Vector2i(9, 7))
		print("LOTE11 construiu ", ids)
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(11, 4))
		cena.camera.distancia = 34.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		f.por_modulo(ids.irr, "modulo_velocidade_3", true)
		f.por_modulo(ids.m3, "modulo_produtividade_3", true)
		f.por_modulo(ids.fundicao, "modulo_eficiencia_3", true)
		f.escolher_receita(ids.forja, "processador_quantico")
		f.escolher_receita(ids.mq, "fio")
		f.escolher_receita(ids.mq, "engrenagem", 2)
		for it in ["processador", "processador", "cristal_carregado", "liga_leve"]:
			f.destino_em(cena.mapa.estruturas[ids.forja].minimo).receber(it)
		for i in 5:
			f.destino_em(cena.mapa.estruturas[ids.fundicao].minimo).receber("minerio_ferro")
		for it in ["placa_cobre", "placa_ferro", "placa_ferro"]:
			f.destino_em(cena.mapa.estruturas[ids.mq].minimo).receber(it)
		cena.pesquisa.ativa = "aco"
		f.laboratorios[ids.lab].pacotes = {"pacote_pesquisa": 10})
	em(60, func():
		var f: Fabrica = cena.fabrica
		for k in ids:
			var id: int = ids[k]
			if id < 0:
				continue
			var an: Animador = cena._animador(id)
			print("LOTE11 %s: %s kw %.0f energia %.2f efeito %s anima %s" % [k, cena.mapa.estruturas[id].nome, f.kw_de(id), f.energia(id), f.efeito_modulos(id),
					an.ativo if an != null else "sem animador"])
			cena._sel = {"estrutura": id}
			cena._detalhe()
		print("LOTE11 forja ", f.maquinas[ids.forja].estado, " fundição receita ", f.maquinas[ids.fundicao].receita_id, " linha 2 ", f.linha2[ids.mq].receita_id, " pacotes do lab ", f.laboratorios[ids.lab].pacotes))


## Lote 13 (energia I): gerador → poste alto → poste alto a 28 m → montadora; o fio desenhado e o anel girando.
func _roteiro_lote13() -> void:
	var ids := {}
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		var o := Vector2i(9999, 0)
		for r in range(60, 400, 4):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if o.x != 9999:
					break
				var ok := true
				for i in range(-1, 36):
					for j in range(-4, 5):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					o = t
		print("LOTE13 chão ", o)
		if o.x == 9999:
			return
		for i in range(-1, 36):
			for j in range(-4, 5):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("gerador", o, 0))
		p.call(con.plano_peca("poste_alto", o + Vector2i(3, 0), 0))
		p.call(con.plano_peca("poste_alto", o + Vector2i(31, 0), 0))
		p.call(con.plano_peca("montadora", o + Vector2i(31, 2), 0))
		p.call(con.plano_peca("gerador_fluido", o + Vector2i(6, -2), 0))     # (cursor no centro) boca sul em (6, −4): um cano
		p.call(con.plano_peca("cano_reto", o + Vector2i(6, -4), Construtor.rot_do_fluxo(2)))
		ids["cano_gf"] = m.tiles.get(o + Vector2i(6, -4), -1)
		p.call(con.plano_peca("painel_solar_2", o + Vector2i(16, -2), 0))
		ids["ps2"] = m.tiles.get(o + Vector2i(16, -2), -1)
		p.call(con.plano_peca("montadora_2", o + Vector2i(22, -2), 0))          # lote 10: montadora 2 na linha alta
		p.call(con.plano_peca("poste_energia", o + Vector2i(25, 0), 0))
		ids["m2"] = m.tiles.get(o + Vector2i(22, -2), -1)
		p.call(con.plano_peca("refinador_2", o + Vector2i(27, -2), 0))           # lote 10: refinador 2 no mesmo poste
		ids["r2"] = m.tiles.get(o + Vector2i(27, -2), -1)
		for id in m.estruturas:
			var e: Dictionary = m.estruturas[id]
			if e.minimo == o + Vector2i(3, 0):
				ids["a1"] = id
			elif e.minimo == o + Vector2i(31, 0):
				ids["a2"] = id
			elif e.nome == "gerador_fluido":
				ids["gf"] = id
			elif e.nome == "gerador":
				ids["g"] = id
			elif e.nome == "montadora" and Fiacao.centro(e).distance_to(Vector2(o + Vector2i(31, 2))) < 4.0:
				ids["maq"] = id
		print("LOTE13 construiu ", ids.keys(), " fio a1-a2 ", ids.has("a1") and ids.has("a2") and m.estruturas[ids.a1].get("fios", []).has(ids.a2))
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(17, 0))
		cena.camera.distancia = 40.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 5000.0
		if ids.has("gf") and ids.has("g"):                 # a linha alta passa a vir só do gerador a fluido, pelo cano
			f.combustivel[ids.g] = 0.0
			f.combustivel[ids.gf] = 0.0
			var rc := f.rede_de(int(ids.get("cano_gf", -1)))
			if not rc.is_empty():
				rc.fluido = "combustivel_seiva"
				rc.qtd = 90.0
			print("LOTE13 gerador a fluido no cano ", f.gerador_no_cano(ids.gf))
		if f.maquinas.has(int(ids.get("m2", -1))):
			f.escolher_receita(ids.m2, "engrenagem")
		if f.maquinas.has(int(ids.get("r2", -1))):
			f.escolher_receita(ids.r2, "resina"))
	for q in range(8, 60, 2):                          # braço de mentira: põe placas na montadora 2 e tira as engrenagens
		em(q, func():
			if cena.fabrica.maquinas.has(int(ids.get("m2", -1))):
				var mq: Maquina = cena.fabrica.maquinas[ids.m2]
				while mq.receber("placa_ferro"):
					pass
				mq.saidas.erase("engrenagem")
			if cena.fabrica.maquinas.has(int(ids.get("r2", -1))):         # (canos de mentira: seiva e água direto)
				var mr: Maquina = cena.fabrica.maquinas[ids.r2]
				mr.receber_fluido("seiva", 30.0)
				mr.receber_fluido("agua", 10.0)
				mr.saidas.erase("resina"))
	em(60, func():
		if ids.has("gf"):
			var f: Fabrica = cena.fabrica
			var an: Animador = cena._animador(ids.gf)
			print("LOTE13 gerador a fluido %.1f MJ, ligado ao a1 %s, queimando %s, anima %s" % [f.combustivel.get(ids.gf, 0.0),
					cena.mapa.estruturas[ids.gf].get("fios", []).has(ids.get("a1", -1)), f.transmitindo(ids.gf), an.ativo if an != null else "sem animador"])
			cena._sel = {"estrutura": ids.gf}
			cena._detalhe()
		if cena.fabrica.maquinas.has(int(ids.get("m2", -1))):
			var mq: Maquina = cena.fabrica.maquinas[ids.m2]
			var an2: Animador = cena._animador(ids.m2)
			print("LOTE10 montadora 2: estado %s energia %.2f velocidade %.2f anima %s" % [Maquina.Estado.keys()[mq.estado], mq.energia, mq.velocidade,
					an2.ativo if an2 != null else "sem animador"])
			cena._sel = {"estrutura": ids.m2}
			cena._detalhe()
		if cena.fabrica.maquinas.has(int(ids.get("r2", -1))):
			var mr: Maquina = cena.fabrica.maquinas[ids.r2]
			var an3: Animador = cena._animador(ids.r2)
			print("LOTE10 refinador 2: estado %s energia %.2f velocidade %.2f anima %s" % [Maquina.Estado.keys()[mr.estado], mr.energia, mr.velocidade,
					an3.ativo if an3 != null else "sem animador"])
			cena._sel = {"estrutura": ids.r2}
			cena._detalhe()
		if int(ids.get("ps2", -1)) >= 0:
			var f: Fabrica = cena.fabrica
			var an: Animador = cena._animador(ids.ps2)
			print("LOTE13 painel solar 2: %.0f kW (painel 1 renderia %.0f) dia %.2f encoberto %.2f anima %s" % [-f.kw_de(ids.ps2), 300.0 * f.sol,
					f.sol_limpo, f.encoberto, an.ativo if an != null else "sem animador"])
			cena._sel = {"estrutura": ids.ps2}
			cena._detalhe()
		if not ids.has("a2"):
			return
		var f: Fabrica = cena.fabrica
		var an: Animador = cena._animador(ids.a2)
		print("LOTE13 energia na montadora %.2f transmitindo %s anel %s cabos %s" % [f.rede.satisfacao(ids.get("maq", -1)), f.transmitindo(ids.a2),
				an.ativo if an != null else "sem animador", cena._fios._cabos.mesh != null])
		cena._sel = {"estrutura": ids.a2}
		cena._detalhe()
		print("LOTE13 painel poste alto"))
	em(8, func():                                     # turbina de correnteza no rio mais perto, com um poste alto na margem
		var m: MapaOcupacao = cena.mapa
		var con: Construtor = cena.construtor
		var g := Grade.gerador
		for r in range(50, 300, 2):
			if ids.has("turb"):
				break
			for k in 64:
				var t := Vector2i((Vector2.from_angle(k * TAU / 64.0) * r).round())
				if g.terreno(t) != GeradorMundo.Terreno.RIO or m.motivo_bloqueio("turbina_correnteza", t, 0) != "":
					continue
				cena.sincronizar(con.executar(con.plano_peca("turbina_correnteza", t, 0)))
				if not m.tiles.has(t):
					continue
				ids["turb"] = m.tiles[t]
				for d in [Vector2i(-2, 0), Vector2i(3, 0), Vector2i(0, -2), Vector2i(0, 3), Vector2i(-2, 1), Vector2i(3, 1), Vector2i(1, -2), Vector2i(1, 3)]:
					m.limpar_obstaculo(t + d)
					if m.motivo_bloqueio("poste_alto", t + d, 0) == "":
						cena.sincronizar(con.executar(con.plano_peca("poste_alto", t + d, 0)))
						ids["pt"] = m.tiles.get(t + d, -1)
						break
				print("LOTE13 turbina no rio em ", t, " poste ", ids.get("pt", -1))
				break)
	em(70, func():
		if not ids.has("turb"):
			print("LOTE13 sem rio por perto")
			return
		var f: Fabrica = cena.fabrica
		var an: Animador = cena._animador(ids.turb)
		print("LOTE13 turbina %.0f kW (vazão %.2f, %s) ligada a %d fio(s) anima %s plataforma %s" % [-f.kw_de(ids.turb), f.rio, cena.clima.nome_estacao(),
				cena.mapa.estruturas[ids.turb].get("fios", []).size(), an.ativo if an != null else "sem animador",
				Registro.estruturas.turbina_correnteza.flutua])
		cena._sel = {"estrutura": ids.turb}
		cena._detalhe()
		print("LOTE13 painel turbina"))


func _roteiro_lote17() -> void:
	var ids := {}
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(120, 400, 4):
			for k in 48:
				var t := Vector2i((Vector2.from_angle(k * TAU / 48.0) * r).round())
				if w[0].x != 9999:
					break
				var ok := true
				for i in range(-2, 20):
					for j in range(-2, 15):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("LOTE17 chão ", o)
		if o.x == 9999:
			return
		for i in range(-2, 20):
			for j in range(-2, 15):
				m.limpar_obstaculo(o + Vector2i(i, j))
		var con: Construtor = cena.construtor
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_peca("sensor_varredura", o + Vector2i(1, 2), 0))
		p.call(con.plano_peca("poste_energia", o + Vector2i(4, 3), 0))
		p.call(con.plano_peca("gerador", o + Vector2i(7, 2), 0))
		p.call(con.plano_peca("farol_cristal", o + Vector2i(4, 6), 0))
		p.call(con.plano_peca("posto_avancado", o + Vector2i(10, 6), 0))
		p.call(con.plano_peca("farol_cristal", o + Vector2i(14, 8), 0))
		p.call(con.plano_peca("lancador_sementes", o + Vector2i(14, 1), 0))
		p.call(con.plano_peca("receptor_capsulas", o + Vector2i(1, 7), 0))
		p.call(con.plano_peca("transportador_quantico", o + Vector2i(17, 6), 0))
		p.call(con.plano_peca("transportador_quantico", o + Vector2i(6, 9), 0))
		p.call(con.plano_peca("silo_lancamento", o + Vector2i(1, 11), 0))
		var tqs: Array = m.estruturas.keys().filter(func(i): return m.estruturas[i].nome == "transportador_quantico")
		if tqs.size() == 2:
			ids["tq_a"] = tqs[0]
			ids["tq_b"] = tqs[1]
			(cena.transportador as Transportador).entrada(tqs[0])["engrenagem"] = 10
		for id in m.estruturas:
			ids[m.estruturas[id].nome] = id
		print("LOTE17 construiu ", ids.has("sensor_varredura"), " ", ids.has("gerador"), " farol ", ids.has("farol_cristal"),
				" posto ", ids.has("posto_avancado"), " lançador ", ids.has("lancador_sementes"))
		if ids.has("lancador_sementes"):
			var l: Lancador = cena.lancador
			var li: int = ids.lancador_sementes
			m.estruturas[li]["sementes"] = 1
			for r in 8:                                    # primeiro rumo com pouso a 100 m
				l.mirar(li, r, 100)
				if l.lugar_de_pouso(l.alvo(li)) != Lancador.SEM_LUGAR:
					break
			print("LOTE17 lançador alvo %s %d m motivo '%s'" % [Lancador.RUMOS[l.rumo(li)], l.distancia(li), l.motivo(li)])
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(2, 3))
		cena.camera.distancia = 30.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		f.reconstruir()
		for id in f.combustivel:
			f.combustivel[id] = 5000.0)
	for q in range(20, 360, 20):                      # adianta o minuto do sensor: 1 chunk a cada passo
		em(q, func():
			var v: Varredura = cena.varredura
			var s: int = ids.get("sensor_varredura", -1)
			if s >= 0 and v.sensores.has(s):
				v.sensores[s].t = 59.9)
	em(150, func():                                    # adianta a carga do lançador: dispara já
		if ids.has("lancador_sementes"):
			var l: Lancador = cena.lancador
			if l.lancadores.has(ids.lancador_sementes):
				l.lancadores[ids.lancador_sementes].t = 19.99
			print("LOTE17 lançador energia %.2f carga %.2f motivo '%s'" % [l.energia_de(ids.lancador_sementes), l.carga(ids.lancador_sementes), l.motivo(ids.lancador_sementes)]))
	em(190, func():                                    # foguete montado pelo roteiro (as peças ainda não existem): lança
		if ids.has("silo_lancamento"):
			cena.mapa.estruturas[ids.silo_lancamento]["partes"] = 100
			cena.mapa.estruturas[ids.silo_lancamento]["carga"] = true
			print("LOTE17 silo pronto %s lançou %s" % [(cena.silo as SiloLancamento).pronto(ids.silo_lancamento), (cena.silo as SiloLancamento).lancar(ids.silo_lancamento)]))
	em(260, func():
		if ids.has("silo_lancamento"):
			var ds: DesenhoSilo = null
			for c in cena.get_children():
				if c is DesenhoSilo:
					ds = c
			var sl: SiloLancamento = cena.silo
			cena._sel = {"estrutura": ids.silo_lancamento}
			cena._detalhe()
			print("LOTE17 silo subindo %.1f m, foguetes à vista %d, anima %s" % [sl.subida(ids.silo_lancamento), ds.visiveis() if ds != null else -1,
					(cena._animador(ids.silo_lancamento) as Animador).ativo if cena._animador(ids.silo_lancamento) != null else "sem animador"]))
	em(185, func():
		if ids.has("lancador_sementes"):
			var l: Lancador = cena.lancador
			var dl: DesenhoLancador = null
			for c in cena.get_children():
				if c is DesenhoLancador:
					dl = c
			print("LOTE17 disparo %s voos %d anima %s desenho %s" % [l.disparando(ids.lancador_sementes), l.voos.size(),
					(cena._animador(ids.lancador_sementes) as Animador).ativo if cena._animador(ids.lancador_sementes) != null else "sem animador",
					dl.contagem() if dl != null else {}])
			cena._sel = {"estrutura": ids.lancador_sementes}
			cena._detalhe()
			print("LOTE17 painel lançador"))
	em(300, func():
		(cena.clima as Clima).hora = 0.0                # meia-noite: os faróis acendem
		var g: Genese = cena.genese
		for c in g.colonias():                           # adianta a colônia: o pacote gênese sai já
			cena.mapa.estruturas[c]["genese_t"] = 29.9
		print("LOTE17 colônias %d receptores %d" % [g.colonias().size(), g.receptores().size()]))
	em(330, func():
		var g: Genese = cena.genese
		print("LOTE17 cápsulas gênese no ar %d" % g.voos.size()))
	em(200, func():
		if ids.has("sensor_varredura"):
			cena._sel = {"estrutura": ids.sensor_varredura}
			cena._detalhe()
			print("LOTE17 painel sensor"))
	em(390, func():
		var v: Varredura = cena.varredura
		var s: int = ids.get("sensor_varredura", -1)
		if s < 0:
			return
		var dv: DesenhoVarredura = null
		for c in cena.get_children():
			if c is DesenhoVarredura:
				dv = c
		print("LOTE17 energia %.2f revelados %d de %d ninhos marcados %d jazidas %s marcas %s" % [v.energia_de(s), v.feitos(s), v.limite(s),
				v.ninhos_marcados().size(), v.jazidas(s).map(func(j): return "%s %d %s" % [j.tipo, j.total, j.nivel]),
				dv.contagem() if dv != null else {}])
		var a := cena._animador(s) as Animador
		print("LOTE17 anima ", a != null and a.ativo)
		var fa: Farol = cena.farol
		var df: DesenhoFarol = null
		for c in cena.get_children():
			if c is DesenhoFarol:
				df = c
		var f: Fabrica = cena.fabrica
		var postos := m_postos(cena.mapa)
		print("LOTE17 faróis acesos %d luzes %d · energia farol do posto %.2f · postos %d · lançador sementes %d voos %d" % [fa.acesos().size(),
				df.acesas() if df != null else -1, f.energia(_farol_do_posto(cena.mapa, ids)), postos.size(),
				(cena.lancador as Lancador).sementes(ids.get("lancador_sementes", -1)), (cena.lancador as Lancador).voos.size()])
		var g: Genese = cena.genese
		var tr: Transportador = cena.transportador
		var recs := g.receptores()
		print("LOTE17 receptor gênese %d · colônias %d (kit drones %s) · transportador saída B %s" % [Genese._total(g.recebido(recs[0])) if not recs.is_empty() else -1,
				g.colonias().size(), str(g.colonias().map(func(c): return int(f.baus.get(c, {}).get("drone", 0)))),
				str(tr.saida(ids.tq_b)) if ids.has("tq_b") else "-"])
		for k in ["posto_avancado", "receptor_capsulas", "tq_a"]:
			if ids.has(k):
				cena._sel = {"estrutura": ids[k]}
				cena._detalhe()
		if not g.colonias().is_empty():
			cena._sel = {"estrutura": g.colonias()[0]}
			cena._detalhe()
		print("LOTE17 painéis posto, receptor, transportador, colônia")
		if ids.has("silo_lancamento"):
			print("LOTE17 silo lançados %d partes %d" % [int(cena.mapa.estruturas[ids.silo_lancamento].get("lancados", 0)),
					(cena.silo as SiloLancamento).partes(ids.silo_lancamento)]))


static func m_postos(m: MapaOcupacao) -> Array:
	return m.estruturas.keys().filter(func(i): return m.estruturas[i].nome == "posto_avancado")


## O farol posto encostado no posto avançado (o segundo farol do roteiro).
static func _farol_do_posto(m: MapaOcupacao, ids: Dictionary) -> int:
	var melhor := -1
	for i in m.estruturas:
		if m.estruturas[i].nome == "farol_cristal" and (melhor < 0 or i > melhor):
			melhor = i
	return melhor


## Patch fauna, fase 2 (-- novo roteiro plantas): bosque de árvores caducas perto do núcleo. PNG em
## user://fotos_plantas: flores de dia e de noite (primavera), folhas caindo (outono com vento), copa abrindo no fim do
## outono e nua no inverno, galhos e cogumelos depois da tempestade e da chuva, capim seco e viçoso (verão), limo no
## lago mais perto.
func _roteiro_plantas() -> void:
	var w := [Vector2.ZERO]
	var foto := func(nome: String) -> void:
		DirAccess.make_dir_recursive_absolute("user://fotos_plantas")
		get_viewport().get_texture().get_image().save_png("user://fotos_plantas/%s.png" % nome)
		print("PLANTAS foto ", nome)
	var estacao := func(e: int, hora: float, estado: String) -> void:
		var cl: Clima = cena.clima
		cl.ciclo = false
		cl.tempo_real = false
		cl.estacao = e
		cl.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * 0.5
		cl.hora = hora
		cl.forcar(estado, true)
		cl.restante = 1.0e9
	em(2, func():
		Sessao.config.fps = false
		var eco: Ecossistema = cena.ecossistema
		var n := -1
		for y in range(-80, 81, 10):
			for x in range(-80, 81, 10):
				if Vector2(x, y).length() < 14.0:
					continue
				var k := eco.arvores_perto(Vector2(x, y), 10.0).filter(func(a): return a.caduca).size()
				if k > n:
					n = k
					w[0] = Vector2(x, y)
		print("PLANTAS bosque ", w[0], " caducas ", n)
		_sem_ninhos(Vector2i(w[0]))
		estacao.call(0, 0.45, "limpo")
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(w[0])
		cam.distancia = 12.0
		cam.posicionar())
	em(80, func(): foto.call("1_primavera_dia"))
	em(82, func(): cena.clima.hora = 0.02)
	em(120, func(): foto.call("2_primavera_noite"))
	em(122, func(): estacao.call(2, 0.45, "nublado"))
	em(330, func():
		var dp: DesenhoPlantasReagem = cena._desenho_plantas_reagem
		print("PLANTAS folhas=%d no_chao=%d taxa=%.2f" % [dp.folhas.size(), dp.folhas.filter(func(f): return f.chao).size(), dp.taxa_folhas()])
		foto.call("3_outono_folhas"))
	em(331, func(): cena.clima.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * 0.93)
	em(350, func(): foto.call("3b_fim_do_outono"))
	em(351, func(): estacao.call(3, 0.45, "nublado"))
	em(370, func(): foto.call("3c_inverno"))
	em(372, func(): estacao.call(1, 0.45, "tempestade"))
	em(430, func():
		estacao.call(1, 0.45, "limpo")
		cena.clima.valores.vento = 0.2
		cena.clima.molhado = 0.95)
	em(510, func():
		var p: PlantasReagem = cena.plantas_reagem
		p.t += 45.0                                  # os cogumelos já cresceram
		print("PLANTAS galhos=%d cogumelos=%d" % [p.galhos.size(), p.cogumelos.size()])
		var cam = cena.camera
		if not p.cogumelos.is_empty():
			cam.alvo = Grade.ponto_mundo(p.cogumelos[0].pos)
		cam.distancia = 7.0
		cam.posicionar())
	em(520, func(): foto.call("4_cogumelos"))
	em(521, func():
		var p: PlantasReagem = cena.plantas_reagem
		var cam = cena.camera
		if not p.galhos.is_empty():
			var perto: Dictionary = p.galhos[0]
			for g in p.galhos:
				if (g.pos as Vector2).distance_to(cena.ecossistema.foco) < (perto.pos as Vector2).distance_to(cena.ecossistema.foco):
					perto = g
			cam.alvo = Grade.ponto_mundo(perto.pos)
			print("PLANTAS galho perto ", perto.pos, " tela depois ")
		cam.distancia = 4.0
		cam.posicionar())
	em(526, func(): foto.call("4b_galhos"))
	em(528, func():
		cena.clima.vico = -0.9
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(w[0])
		cam.distancia = 12.0
		cam.posicionar())
	em(550, func(): foto.call("5_verao_seco"))
	em(552, func(): cena.clima.vico = 1.0)
	em(580, func(): foto.call("6_viçoso_depois_da_chuva"))
	em(582, func():
		var g: GeradorMundo = cena.gerador
		var lagos: Array = g.hidro.lagos(Vector2i(-160, -160), Vector2i(160, 160)) if g.relevo_ativo else []
		var melhor: Dictionary = {}
		for lg in lagos:
			if melhor.is_empty() or (lg.centro as Vector2).length() < (melhor.centro as Vector2).length():
				melhor = lg
		if not melhor.is_empty():
			print("PLANTAS lago ", melhor.centro, " raio ", melhor.raio)
			var cam = cena.camera
			cam.alvo = Grade.ponto_mundo(melhor.centro + Vector2(float(melhor.raio) * 0.7, 0.0))
			cam.distancia = 18.0
			cam.posicionar())
	em(640, func(): foto.call("7_limo_no_lago"))


## Patch fauna, fase 5 (-- roteiro ratos): uma toca de rato-pardo ao pé de arbusto e uma de saltador no campo
## aberto, com bolotas perto; de manhã (atividade forçada no máximo): saem, andam, farejam, comem, cavam; um susto
## faz fugir; a trilha marcada; um rato morto vira carcaça com mosca; à noite, os olhos no mato. PNG em
## user://fotos_ratos; imprime RATOS a cada 2 s.
func _roteiro_ratos() -> void:
	var w := [Vector2.ZERO, Vector2.ZERO]
	var foto := func(nome: String) -> void:
		DirAccess.make_dir_recursive_absolute("user://fotos_ratos")
		get_viewport().get_texture().get_image().save_png("user://fotos_ratos/%s.png" % nome)
		print("RATOS foto ", nome)
	var olhar := func(p: Vector2, dist: float) -> void:
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(p)
		cam.distancia = dist
		cam.posicionar()
	em(2, func():
		Sessao.config.fps = false
		var r: Ratos = cena.ratos
		r._d = r._d.duplicate()
		r._d.meio_dia = 1.0                                # de dia também (para a foto)
		r._d.tocas_max = 0                                 # só as do roteiro
		for id in r.tocas.keys():
			r.abandonar(id)
		r._d.aberto_chance = 1.0
		var pardos: Array = []
		var abertos: Array = []
		for y in range(-60, 61, 3):
			for x in range(-60, 61, 3):
				var t := Vector2i(x, y)
				if Vector2(t).length() < 18.0:
					continue
				var esp := r.especie_de_toca(t)
				if esp == "pardo":
					pardos.append(Vector2(t) + Vector2(0.5, 0.5))
				elif esp == "saltador":
					abertos.append(Vector2(t) + Vector2(0.5, 0.5))
		var melhor := INF
		for a in pardos:                                   # o par mais perto do núcleo com 11 a 20 m entre as tocas
			for b in abertos:
				var d: float = (a as Vector2).distance_to(b)
				if d > 11.0 and d < 20.0 and (a as Vector2).length() + (b as Vector2).length() < melhor:
					melhor = (a as Vector2).length() + (b as Vector2).length()
					w[0] = a
					w[1] = b
		print("RATOS tocas ", w)
		_sem_ninhos(Vector2i(w[0]))
		var col: Colonia = cena.colonia
		for id in col.aranhas.keys():
			if (col.aranhas[id].pos as Vector2).distance_to(w[0]) < 90.0:
				col.aranhas.erase(id)
		var t1 := r.nova_toca(w[0], "pardo")
		var t2 := r.nova_toca(w[1], "saltador")
		for x in r.ratos.values():
			x.t = randf_range(0.5, 4.0)
		var eco: Ecossistema = cena.ecossistema
		for k in 6:
			var id := eco.por_comida("fruta", w[0] + Vector2.from_angle(k * 1.1) * (2.0 + k * 0.4), 1.0)
			eco.comida[id].especie = "bolota"
			eco.comida[id].fonte = "arv_carvalho"
			eco.comida[id].vida = 4000.0
		var cl: Clima = cena.clima
		cl.ciclo = false
		cl.tempo_real = false
		cl.estacao = 1
		cl.hora = 0.36
		cl.forcar("limpo", true)
		cl.restante = 1.0e9
		olhar.call((w[0] + w[1]) * 0.5, 14.0))
	for q in range(60, 1500, 60):
		em(q, func():
			var r: Ratos = cena.ratos
			var est := {}
			for x in r.ratos.values():
				est[Ratos.E.keys()[int(x.estado)]] = int(est.get(Ratos.E.keys()[int(x.estado)], 0)) + 1
			print("RATOS q=%d ratos=%d %s enterradas=%d desenhados=%d" % [Engine.get_process_frames(), r.ratos.size(), str(est), r.enterradas, (cena._desenho_ratos as DesenhoRatos).nos.size()]))
	var na_tela := func() -> void:
		var vp_t := get_viewport().get_visible_rect().size
		var cam3: Camera3D = cena.camera
		var lista: Array = []
		for n in (cena._desenho_ratos as DesenhoRatos).nos.values():
			var q: Vector3 = (n.no as Node3D).global_position + Vector3(0, 0.05, 0)
			var sp := cam3.unproject_position(q)
			if not cam3.is_position_behind(q) and Rect2(Vector2.ZERO, vp_t).has_point(sp):
				lista.append([String(n.esp), Vector2i(sp), String(n.acao)])
		print("RATOS na tela ", lista)
	em(419, na_tela)
	em(519, na_tela)
	em(619, na_tela)
	em(420, func(): foto.call("1_tocas_de_manha"))
	em(422, func(): olhar.call(w[0], 4.0))
	em(520, func(): foto.call("2_pardo_perto"))
	em(522, func(): olhar.call(w[1], 4.0))
	em(620, func(): foto.call("3_saltador_perto"))
	em(622, func():
		(cena.ratos as Ratos).assustar(w[1] + Vector2(1.5, 0), 8.0)
		(cena.ratos as Ratos).assustar(w[0] + Vector2(1.5, 0), 8.0))
	em(640, func(): foto.call("4_fugindo"))
	em(700, func():
		var r: Ratos = cena.ratos
		for k in 160:                                     # trilha marcada entre as tocas (um caminho que serpenteia)
			var p: Vector2 = w[0].lerp(w[1], k / 159.0)
			p += Vector2(-(w[1] - w[0]).y, (w[1] - w[0]).x).normalized() * sin(k * 0.08) * 0.8
			r.passagem[Vector2i((p * Ratos.TRILHA_RES).floor())] = 1.0
		r.versao_passagem += 1
		olhar.call((w[0] + w[1]) * 0.5, 9.0))
	em(759, func():
		var dr: DesenhoRatos = cena._desenho_ratos
		var meio: Vector2 = (w[0] + w[1]) * 0.5
		var p := (Vector2i(meio.floor()) - dr._trilha_c) * DesenhoRatos.RES_TRILHA
		print("RATOS trilha no meio: passagem %.2f img %.2f c %s origem %s" % [float((cena.ratos as Ratos).passagem.get(Vector2i(meio.floor()), -1.0)),
				dr._img_trilha.get_pixelv(p).r if p.x >= 0 and p.y >= 0 and p.x < 256 and p.y < 256 else -1.0, str(dr._trilha_c),
				str(RenderingServer.global_shader_parameter_get("trilha_origem"))])
		var cam3: Camera3D = cena.camera
		for k in 5:
			var q: Vector2 = w[0].lerp(w[1], k / 4.0)
			print("RATOS trilha tela ", Vector2i(cam3.unproject_position(Grade.ponto_mundo(q)))))
	em(760, func(): foto.call("5_trilha"))
	em(762, func():
		var r: Ratos = cena.ratos
		for x in r.ratos.values():
			if x.estado != Ratos.E.TOCA and x.especie == "pardo":
				x.morto = true                                # morreu (o corpo deita e vira carcaça)
				break
		olhar.call(w[0], 4.0))
	em(860, func():
		for f in cena.ecossistema.comida.values():
			if f.tipo == "carcaca" and f.especie == "rato":
				f.idade = float(f.vida) * 0.45
				print("RATOS carcaca de rato ", f.pos, " variante ", f.get("variante"))
				olhar.call(f.pos, 3.0))
	em(920, func(): foto.call("6_carcaca_de_rato"))
	em(922, func():
		cena.clima.hora = 0.02
		olhar.call(w[0], 7.0))
	em(1000, func(): foto.call("7_olhos_a_noite"))


## Patch fauna, fase 4 (-- roteiro carcacas): campo aberto no verão ao meio-dia com 3 larvas mortas (inteira, inchada,
## restos) e 3 aranhas mortas (sucata nova fumegando, enferrujada, desmontando); moscas em volta da carne; o planador
## descendo por cima. PNG em user://fotos_carcacas.
func _roteiro_carcacas() -> void:
	var w := [Vector2.ZERO]
	var foto := func(nome: String) -> void:
		DirAccess.make_dir_recursive_absolute("user://fotos_carcacas")
		get_viewport().get_texture().get_image().save_png("user://fotos_carcacas/%s.png" % nome)
		print("CARCACAS foto ", nome)
	var olhar := func(p: Vector2, dist: float) -> void:
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(p)
		cam.distancia = dist
		cam.posicionar()
	em(2, func():
		Sessao.config.fps = false
		var eco: Ecossistema = cena.ecossistema
		var nota := -1.0
		for y in range(-60, 61, 6):
			for x in range(-60, 61, 6):
				var c := Vector2(x, y)
				if c.length() < 16.0:
					continue
				var s := 0.0
				for j in range(-4, 5, 2):
					for i in range(-4, 5, 2):
						var t := Vector2i(x + i, y + j)
						s += eco.saude(t) if (cena.ambiente as AmbienteVivo).pode_plantar(t) else -1.0
				if s > nota:
					nota = s
					w[0] = c
		print("CARCACAS campo ", w[0])
		_sem_ninhos(Vector2i(w[0]))
		var col: Colonia = cena.colonia
		for id in col.aranhas.keys():                      # sem aranha viva perto (o planador tem medo)
			if (col.aranhas[id].pos as Vector2).distance_to(w[0]) < 90.0:
				col.aranhas.erase(id)
		var cl: Clima = cena.clima
		cl.ciclo = false
		cl.tempo_real = false
		cl.estacao = 1
		cl.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * 0.5
		cl.hora = 0.45
		cl.forcar("limpo", true)
		cl.restante = 1.0e9
		var cc: Carcacas = cena.carcacas
		var fr := [0.12, 0.5, 0.86]
		for i in 3:
			var idl := cc.morreu("larva", w[0] + Vector2(-2.2 + 2.2 * i, -1.2), 9000 + i)
			var f: Dictionary = eco.comida[idl]
			f.idade = float(f.vida) * float(fr[i])
			cc.morreu("aranha", w[0] + Vector2(-2.6 + 2.6 * i, 1.6), 9100 + i)
			var s: Dictionary = cc.sucatas[-1]
			s.idade = [3.0, float(s.vida) * 0.5, float(s.vida) * 0.86][i]
		olhar.call(w[0], 9.0))
	em(60, func():
		print("CARCACAS nos=%d moscas=%d" % [(cena._desenho_carcacas as DesenhoCarcacas).nos.size(), (cena._vida_pequena as DesenhoVidaPequena).moscas.size()])
		foto.call("1_todas"))
	em(62, func(): olhar.call(w[0] + Vector2(0, -1.2), 4.0))
	em(90, func(): foto.call("2_larva_inchada_moscas"))
	em(92, func(): olhar.call(w[0] + Vector2(-2.6, 1.6), 3.5))
	em(120, func(): foto.call("3_sucata_nova"))
	em(122, func(): olhar.call(w[0] + Vector2(1.3, 1.6), 5.0))
	em(150, func(): foto.call("4_sucata_enferrujada"))
	em(152, func():
		var pa: Passaros = cena.passaros
		var b: Dictionary = pa._novo("planador", w[0] + Vector2(30, 0))
		b.centro = w[0] + Vector2(25, 5)
		b.estado = Passaros.E.CIRCULANDO
		b.alt = 22.0
		b.alt_alvo = 22.0
		pa.bandos[b.id] = b
		olhar.call(w[0], 30.0))
	em(470, func():
		for b in (cena.passaros as Passaros).bandos.values():
			if b.especie == "planador":
				print("CARCACAS planador centro %s raio %.1f alt %.1f" % [b.centro, b.raio, b.alt])
		foto.call("5_planador_por_cima"))


## Patch fauna, fase 3 (-- novo roteiro frutos): bolotas embaixo dos carvalhos no outono, sementes voando das bétulas e
## pinheiros no começo do outono com vento, bagas embaixo do arbusto no verão, frutos apodrecendo e mudas nascidas de
## semente. PNG em user://fotos_frutos.
func _roteiro_frutos() -> void:
	var w := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]          # carvalhos, bétulas/pinheiros, arbustos
	var foto := func(nome: String) -> void:
		DirAccess.make_dir_recursive_absolute("user://fotos_frutos")
		get_viewport().get_texture().get_image().save_png("user://fotos_frutos/%s.png" % nome)
		print("FRUTOS foto ", nome)
	var estacao := func(e: int, frac: float, estado: String) -> void:
		var cl: Clima = cena.clima
		cl.ciclo = false
		cl.tempo_real = false
		cl.estacao = e
		cl.t_estacao = float(Registro.clima.get("estacao_s", 604800)) * frac
		cl.hora = 0.45
		cl.forcar(estado, true)
		cl.restante = 1.0e9
	var olhar := func(p: Vector2, dist: float) -> void:
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(p)
		cam.distancia = dist
		cam.posicionar()
	var encher := func(foco: Vector2) -> void:
		var f: Frutos = cena.frutos
		for i in 80:
			f.cair(foco, cena.clima.estacao)
	em(2, func():
		Sessao.config.fps = false
		var eco: Ecossistema = cena.ecossistema
		var notas := [-1, -1, -1]
		for y in range(-90, 91, 10):
			for x in range(-90, 91, 10):
				var c := Vector2(x, y)
				if c.length() < 16.0:
					continue
				var arvs := eco.arvores_perto(c, 9.0)
				var k := [arvs.filter(func(a): return Frutos.fruto_de(String(a.nome)) == "bolota").size(),
						arvs.filter(func(a): return Ecossistema.especie_arvore(String(a.nome)) in ["arv_betula", "arv_pinheiro", "arv_salgueiro"]).size(),
						eco.arbustos_perto(c, 9.0).size()]
				for i in 3:
					if k[i] > notas[i]:
						notas[i] = k[i]
						w[i] = c
		print("FRUTOS carvalhos ", w[0], " ", notas[0], " · sementeiras ", w[1], " ", notas[1], " · arbustos ", w[2], " ", notas[2])
		for i in 3:
			_sem_ninhos(Vector2i(w[i]))
		estacao.call(2, 0.5, "limpo")
		olhar.call(w[0], 9.0))
	em(20, func(): encher.call(w[0]))
	em(70, func():
		var perto: Array = cena.ecossistema.comida_perto(w[0], 15.0, "fruta")
		var dp: DesenhoPlantasReagem = cena._desenho_plantas_reagem
		print("FRUTOS bolotas=%d perto=%d desenhados=%d" % [cena.ecossistema.comida.values().filter(func(f): return f.especie == "bolota").size(),
				perto.size(), dp._mm_ponto.multimesh.visible_instance_count])
		var vp_t := get_viewport().get_visible_rect().size
		var na_tela: Array = []
		for f in perto:
			var p0: Vector2 = f.pos
			var q := Vector3(p0.x, Grade.altura_em(p0) + 0.3, -p0.y)
			var sp := (cena.camera as Camera3D).unproject_position(q)
			if not (cena.camera as Camera3D).is_position_behind(q) and Rect2(Vector2.ZERO, vp_t).has_point(sp):
				na_tela.append(Vector2i(sp))
		print("FRUTOS na tela ", na_tela.size(), " ", na_tela.slice(0, 8))
		foto.call("1_bolotas"))
	em(72, func():
		estacao.call(2, 0.02, "nublado")
		olhar.call(w[1], 16.0))
	em(130, func():
		var dp: DesenhoPlantasReagem = cena._desenho_plantas_reagem
		print("FRUTOS sementes voando=%d" % dp.sementes.size())
		foto.call("2_sementes_no_vento"))
	em(132, func():
		estacao.call(1, 0.5, "limpo")
		olhar.call(w[2], 7.0))
	em(140, func(): encher.call(w[2]))
	em(190, func():
		print("FRUTOS bagas=%d" % cena.ecossistema.comida.values().filter(func(f): return f.especie == "baga").size())
		foto.call("3_bagas"))
	em(192, func():
		for f in cena.ecossistema.comida.values():
			f.idade = float(f.get("vida", 0.0)) * 0.93)
	em(230, func(): foto.call("4_podres"))
	em(232, func():
		estacao.call(1, 0.99, "limpo")
		cena.clima.direcao_vento = Vector2(1, 0.2).normalized())
	em(236, func():
		var f: Frutos = cena.frutos
		var cl: Clima = cena.clima
		cl.estacao = 2
		cl.t_estacao = 0.0
		f.semear(w[1], 2, cl.direcao_vento)
		var amb: AmbienteVivo = cena.ambiente
		var perto := Vector2.INF
		for t: Vector2i in amb.plantas:
			if (Vector2(t) - w[1]).length() < 40.0:
				amb.plantas[t] = 0.3                                    # já cresceram um pouco (para a foto)
				if (Vector2(t) - w[1]).length() < (perto - w[1]).length():
					perto = Vector2(t)
		amb.versao_plantas += 1
		print("FRUTOS mudas de semente=%d" % f.semeadas)
		if perto != Vector2.INF:
			olhar.call(perto, 8.0))
	em(280, func(): foto.call("5_mudas_de_semente"))


## Patch fauna, fase 1 (-- novo roteiro vida): campo de capim saudável perto do núcleo; noite de verão com
## vagalumes e olhos no mato (perto e mais longe), depois meio-dia com os mosquitos de perto. Imprime VIDA a cada 2 s.
func _roteiro_vida() -> void:
	var w := [Vector2.ZERO]
	em(2, func():
		Sessao.config.fps = false
		var eco: Ecossistema = cena.ecossistema
		var nota := -1.0
		for y in range(-70, 71, 8):
			for x in range(-70, 71, 8):
				if Vector2(x, y).length() < 14.0:
					continue
				var s := 0.0
				for j in range(-8, 9, 4):
					for i in range(-8, 9, 4):
						s += eco.saude(Vector2i(x + i, y + j)) + (0.3 if eco.perto_da_agua(Vector2i(x + i, y + j), 2) else 0.0)
				if s > nota:
					nota = s
					w[0] = Vector2(x, y)
		print("VIDA campo ", w[0])
		_sem_ninhos(Vector2i(w[0]))
		cena.clima.ciclo = false
		cena.clima.tempo_real = false
		cena.clima.estacao = 1
		cena.clima.hora = 0.0
		cena.clima.forcar("limpo", true)
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo(w[0])
		cam.distancia = 16.0
		cam.posicionar())
	em(240, func():
		var cam = cena.camera
		cam.distancia = 32.0
		cam.posicionar())
	em(420, func(): cena.clima.hora = 0.5)
	em(440, func():                                  # de dia: câmera de perto num enxame de mosquitos
		var v: DesenhoVidaPequena = cena._vida_pequena
		var cam = cena.camera
		if not v._enx_i.is_empty():
			cam.alvo = Grade.ponto_mundo(v._enx_i[0].c)
		cam.distancia = 9.0
		cam.posicionar())
	for q in range(60, 600, 60):
		em(q, func():
			var v: DesenhoVidaPequena = cena._vida_pequena
			var olhos := v.olhos.filter(func(o): return float(o.brilho) > 0.0).size()
			print("VIDA q=%d vagalumes=%d insetos=%d olhos=%d silencio=%.2f" % [q, v.vagalumes.size(), v.insetos.size(), olhos, v.fatores.silencio]))
	for q in [200, 330, 560]:                        # PNG sem compressão (o vídeo borra a cor de ponto de 1 pixel)
		em(q, func():
			DirAccess.make_dir_recursive_absolute("user://fotos_vida")
			get_viewport().get_texture().get_image().save_png("user://fotos_vida/vida_%d.png" % q))


## Patch RTS (-- novo roteiro obras): encomenda uma linha de esteira, máquinas, postes sem cobre (âmbar) e uma
## remoção; os construtores saem do núcleo, soldam, voltam e buscam o resto. Imprime OBRAS a cada 2 s.
func _roteiro_obras() -> void:
	var w := [Vector2i(9999, 0)]
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var m: MapaOcupacao = cena.mapa
		for r in range(4, 40):
			for k in 32:
				if w[0].x != 9999:
					break
				var t := Vector2i(3, -6) + Vector2i((Vector2.from_angle(k * TAU / 32.0) * r).round())
				var ok := true
				for i in range(0, 14):
					for j in range(0, 10):
						var q := t + Vector2i(i, j)
						if g.terreno(q) != GeradorMundo.Terreno.TERRA or g.nivel(q) != g.nivel(t) or g.em_encosta(q) or m.tiles.has(q):
							ok = false
				if ok:
					w[0] = t
		var o: Vector2i = w[0]
		print("OBRAS chão ", o)
		_sem_ninhos(o)
		var ks := {}
		for i in range(-1, 15):
			for j in range(-1, 11):
				m.limpar_obstaculo(o + Vector2i(i, j))
				ks[Grade.chunk_de(o + Vector2i(i, j))] = true
		for k in ks:
			cena._redesenhar_chunk(k)
		var con: Construtor = cena.construtor
		var velho: int = cena._instanciar_id("bau", o + Vector2i(12, 8), 0)      # este o drone vai desmontar
		cena.inventario["placa_cobre"] = 0                                   # postes ficam âmbar até chegar cobre
		cena.encomendar(con.plano_linha("esteira", o + Vector2i(0, 2), o + Vector2i(10, 2), 0))
		cena.encomendar(con.plano_peca("fornalha", o + Vector2i(2, 4), 0))
		cena.encomendar(con.plano_peca("bau", o + Vector2i(6, 4), 0))
		cena.encomendar(con.plano_peca("poste_energia", o + Vector2i(0, 7), 0))
		cena.encomendar(con.plano_peca("poste_energia", o + Vector2i(6, 7), 0))
		if velho >= 0:
			cena.obras.remover(velho)
		var cam = cena.camera
		cam.alvo = Grade.ponto_mundo((Vector2(o) + Vector2(5, 3) + Vector2(cena.NUCLEO_EM)) * 0.5 + Vector2(1, 1))
		cam.distancia = 30.0
		cam.posicionar())
	em(150, func():                                  # pedido depois da saída: buscam no núcleo e voltam
		var o: Vector2i = w[0]
		cena.encomendar(cena.construtor.plano_peca("montadora", o + Vector2i(9, 4), 0)))
	em(330, func(): cena.inventario["placa_cobre"] = 20)     # chegou cobre: os postes âmbar saem
	for q in range(60, 900, 60):
		em(q, func():
			var ob: Obras = cena.obras
			var fora := ob.construtores().filter(func(d): return d.e != Drones.E.HANGAR).size()
			print("OBRAS q=%d fila=%d esperando=%d drones_fora=%d" % [q, ob.pendentes(), ob.esperando(), fora]))


func _sem_ninhos(w: Vector2i) -> void:
	var col: Colonia = cena.colonia
	for id in col.ninhos.keys():
		if col.ninhos[id].centro.distance_to(Vector2(w)) < 60.0:
			for ar in col.aranhas_do_ninho(id):
				col.aranhas.erase(ar)
			col.ninhos.erase(id)
			cena.sincronizar(cena.construtor.destruir(id))
			var dc: DesenhoColonia = cena._desenho_colonia
			if dc._ninhos.has(id):
				dc._ninhos[id].queue_free()
				dc._ninhos.erase(id)


## Interface B: abre Produção (painel com explicações), escolhe a fornalha, toca no mapa (holograma + ações),
## gira, e por fim constrói. Fotos: ~40 painel aberto, ~80 holograma pendente, ~120 construída.
## Toques injetados: abre as peças, rola a lista arrastando EM CIMA de um botão (não pode escolher a peça),
## toca numa peça (escolhe), arrasta o mapa com um dedo e dá pinça. Imprime o que aconteceu.
## Tamanhos lógicos (já com a escala 1,35 do celular): 20:9, 16:9, tablet 4:3, celular em pé seria outro jogo.
func _roteiro_telas() -> void:
	var telas := [Vector2i(1185, 533), Vector2i(948, 533), Vector2i(948, 711), Vector2i(1280, 720)]
	em(4, func():
		Sessao.config.fps = false
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		get_tree().root.content_scale_factor = 1.0)
	for i in telas.size():
		var t: Vector2i = telas[i]
		em(10 + i * 40, func():
			get_window().content_scale_size = t
			cena.controle.barra._tocar_categoria(3)
			cena.selecionar(Vector2(8, 1)))
		em(30 + i * 40, func():
			var vis := get_viewport().get_visible_rect()
			var ruins: Array[String] = []
			for c in cena.controle.barra.find_children("*", "Control", true, false):
				var ct := c as Control
				if not ct.is_visible_in_tree() or ct is ScrollContainer or ct.get_parent() is VBoxContainer and ct.get_parent().get_parent() is ScrollContainer:
					continue
				if ct is Label or ct is Button or ct is PanelContainer:
					var r := ct.get_global_rect()
					if r.size.x > 1 and not vis.grow(1).encloses(r):
						ruins.append("%s %s" % [ct.name, r])
			print("TELA %s: visível %s · fora da tela: %d %s" % [t, vis.size, ruins.size(), ruins.slice(0, 4)]))


func _roteiro_dedo() -> void:
	var m := {}                                   # dicionário é referência: os passos enxergam o que o anterior guardou
	var rol := func() -> ScrollContainer:
		return cena.controle.barra._pecas.get_parent() as ScrollContainer
	em(4, func():
		Sessao.config.fps = false
		if OS.get_cmdline_user_args().has("lista_cheia"):
			get_tree().root.content_scale_factor = 2.4)      # lista maior que a tela: dá para rolar
	em(10, func():
		var c := botao("cat:3")
		toque(0, c, true)
		toque(0, c, false))
	em(30, func():
		var r: ScrollContainer = rol.call()
		print("TOQUE limiar ", snappedf(Toque.limiar(get_viewport()), 0.1), " escala ", get_tree().root.content_scale_factor, " tela ", get_viewport().get_visible_rect().size)
		print("TOQUE lista: altura ", r.size.y, " conteúdo ", r.get_v_scroll_bar().max_value, " rolagem ", r.scroll_vertical))
	em(32, func():
		m.b0 = botao("fornalha")
		toque(0, m.b0, true))
	for k in 12:
		em(34 + k, func(): arrasto(0, m.b0 - Vector2(0, 14.0 * k), m.b0 - Vector2(0, 14.0 * (k + 1))))
	em(47, func(): toque(0, m.b0 - Vector2(0, 168), false))
	em(70, func():
		print("TOQUE rolagem depois de arrastar sobre a fornalha: ", rol.call().scroll_vertical, " · peça na mão '", cena.controle.peca, "' (vazia = certo)"))
	em(80, func():
		var c := botao("montadora")
		toque(0, c, true)
		toque(0, c, false))
	em(90, func():
		print("TOQUE tocou montadora: peça na mão '", cena.controle.peca, "'")
		toque(0, Vector2(300, 300), true))        # segurar parado = clique direito: larga a peça
	em(97, func():
		toque(0, Vector2(300, 300), false))
	em(99, func(): print("TOQUE segurou parado: peça na mão '", cena.controle.peca, "' (vazia = certo)"))
	var p0 := Vector2(500, 420)
	em(100, func():
		m.alvo0 = cena.camera.alvo
		m.chao0 = cena.camera.no_chao(p0)
		toque(0, p0, true))
	for k in 10:
		em(102 + k, func(): arrasto(0, p0 + Vector2(20.0 * k, 0), p0 + Vector2(20.0 * (k + 1), 0)))
	em(124, func():
		var chao: Vector3 = cena.camera.no_chao(p0 + Vector2(200, 0))
		print("TOQUE arrasto: câmera andou ", snappedf(m.alvo0.distance_to(cena.camera.alvo), 0.01), " m · o chão do dedo saiu ", snappedf(Vector2(chao.x - m.chao0.x, chao.z - m.chao0.z).length(), 0.01), " m do lugar (≈0 = preso no dedo)")
		toque(0, p0 + Vector2(200, 0), false)
		m.alvo1 = cena.camera.alvo)
	em(150, func(): print("TOQUE deslize depois de soltar parado: ", snappedf(m.alvo1.distance_to(cena.camera.alvo), 0.01), " m (≈0 = certo)"))
	em(160, func():
		m.d0 = cena.camera.distancia
		m.meio0 = cena.camera.no_chao(Vector2(640, 360))
		toque(0, Vector2(540, 360), true)
		toque(1, Vector2(740, 360), true))
	for k in 8:
		em(162 + k, func():
			arrasto(0, Vector2(540 - 15.0 * k, 360), Vector2(540 - 15.0 * (k + 1), 360))
			arrasto(1, Vector2(740 + 15.0 * k, 360), Vector2(740 + 15.0 * (k + 1), 360)))
	em(171, func():
		toque(1, Vector2(860, 360), false)
		toque(0, Vector2(420, 360), false)
		var meio: Vector3 = cena.camera.no_chao(Vector2(640, 360))
		print("TOQUE pinça: distância ", snappedf(m.d0, 0.1), " → ", snappedf(cena.camera.distancia, 0.1), " (abrir aproxima) · ponto entre os dedos saiu ", snappedf(Vector2(meio.x - m.meio0.x, meio.z - m.meio0.z).length(), 0.01), " m"))


func _roteiro_interface() -> void:
	em(4, func():
		Sessao.config.fps = false
		for x in range(-8, 4):
			for y in range(-8, 4):
				cena.mapa.limpar_obstaculo(Vector2i(x, y)))
	em(10, func(): clicar(botao("cat:3")))
	em(50, func(): clicar(botao("fornalha")))
	em(60, func(): toque(0, tela(Vector2i(-4, -3)), true))
	em(62, func(): toque(0, tela(Vector2i(-4, -3)), false))
	em(90, func(): clicar(botao("girar")))
	em(118, func(): clicar(botao("construir")))


## Braço com filtro pegando do meio da esteira: pedra e carvão passando, só o carvão vai para o baú.
func _roteiro_filtro() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var con: Construtor = cena.construtor
		for x in range(-14, 2):
			for y in range(-16, -6):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		var p := func(pl: Array[Dictionary]) -> void: cena.sincronizar(con.executar(pl))
		p.call(con.plano_linha("esteira", Vector2i(-12, -12), Vector2i(-1, -12), 0))
		p.call(con.plano_peca("braco", Vector2i(-6, -11), 0))
		p.call(con.plano_peca("bau", Vector2i(-6, -10), 0))
		p.call(con.plano_peca("gerador", Vector2i(-9, -9), 0))
		p.call(con.plano_peca("poste_energia", Vector2i(-7, -10), 0))
		for id in cena.mapa.estruturas:
			if cena.mapa.estruturas[id].nome == "braco":
				cena.mapa.estruturas[id]["filtros"] = ["carvao"]
		cena.camera.alvo = Grade.ponto_mundo(Vector2(-5.5, -11.0))
		cena.camera.distancia = 8.0
		cena.camera.posicionar())
	em(6, func():
		cena.fabrica.reconstruir()
		for id in cena.fabrica.combustivel:
			cena.fabrica.combustivel[id] = 500.0)
	for k in 20:
		em(10 + k * 18, func():
			var f: Fabrica = cena.fabrica
			if f._no_tile.has(Vector2i(-12, -12)):
				f.caminhos[f._no_tile[Vector2i(-12, -12)][0]].esteira.inserir_na_entrada("carvao" if k % 2 == 0 else "pedra"))


## Animação de construção: três máquinas postas uma depois da outra num chão vazio (a montagem e o piso crescendo).
func _roteiro_montagem() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		cena.animar_tudo = true
		for x in range(-14, -1):
			for y in range(-16, -6):
				cena.mapa.limpar_obstaculo(Vector2i(x, y)))
	var pecas := [["fornalha", Vector2i(-12, -12)], ["montadora", Vector2i(-8, -13)], ["gerador", Vector2i(-4, -12)]]
	for i in pecas.size():
		var p: Array = pecas[i]
		em(20 + i * 45, func():
			var con: Construtor = cena.construtor
			cena.sincronizar(con.executar(con.plano_peca(p[0], p[1], 0))))


## Ambiente vivo acelerado: verão, 15 min de fábrica trabalhando (sujeira e óleo em volta), e um foco de fogo na
## campina perto da câmera.
func _roteiro_ambiente() -> void:
	em(40, func():
		var c: Clima = cena.clima
		c.estacao = 1
		var a: AmbienteVivo = cena.ambiente
		for i in 900:
			if cena.fabrica.emissao.is_empty():
				cena.fabrica.tick(1.0)
			a._passo(cena.fabrica, c)
			# deixa a emissão da fábrica viva entre os passos acelerados
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		var alvo := Grade.tile_de_mundo(cena.camera.alvo)
		var acesos := 0
		for r in range(0, 8):
			for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
				if acesos < 3 and a._inflamavel(alvo + d):
					a._acender(alvo + d)
					acesos += 1
		print("AMBIENTE chunks=%d fogo=%d" % [a.dados.size(), a.fogo.size()]))


## Bloco de grama em massa (teste isolado): campo 24×24 m ao lado do início, câmera girando devagar em volta.
func _roteiro_grama() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		var g := Grama.new()
		g.position = Grade.ponto_mundo(Vector2(-14.0, -14.0))
		cena.add_child(g)
		_grama_ini = _quadro)


var _grama_ini := -1


## Aranha andando de perto (GIF da animação): uma aranha solta circulando no chão plano do início.
var _aranha: Aranha = null


func _roteiro_aranha() -> void:
	em(2, func():
		cena.controle.barra.visible = false
		Sessao.config.fps = false
		_aranha = Aranha.new()
		_aranha.position = Grade.ponto_mundo(Vector2(-1.5, -10.0))
		cena.add_child(_aranha)
		cena.camera.alvo = _aranha.position)


## Traço inteligente: fornalha no caminho → o fantasma contorna (foto ~30); põe; um traço novo começando ao lado
## do fim vira o fim em curva (foto ~70).
func _roteiro_rota() -> void:
	em(2, func():
		var con: Construtor = cena.construtor
		cena.sincronizar(con.executar(con.plano_peca("fornalha", Vector2i(-2, -1), 0))))
	em(4, func(): clicar(botao("esteira")))
	em(6, func(): mover(tela(Vector2i(-7, -1))))
	traco_mouse(8, Vector2i(-7, -1), Vector2i(2, -1), 16)
	em(34, func(): botao_mouse(tela(Vector2i(2, -1)), false))
	traco_mouse(40, Vector2i(2, 0), Vector2i(2, 3), 8)
	em(52, func(): botao_mouse(tela(Vector2i(2, 3)), false))
	em(56, func(): mover(Vector2(640, 40)))


## Toque: escolhe a esteira tocando no botão, traça com um dedo, solta (põe), e dois dedos fazem pinça.
func _roteiro_toque() -> void:
	em(4, func(): toque(0, botao("esteira"), true))
	em(5, func(): toque(0, botao("esteira"), false))
	var a := Vector2i(-6, 3)
	var b := Vector2i(1, -2)
	em(8, func(): toque(0, tela(a), true))
	for k in range(1, 15):
		var f0 := float(k - 1) / 14
		var f1 := float(k) / 14
		em(8 + k, func(): arrasto(0, tela(a).lerp(tela(b), f0), tela(a).lerp(tela(b), f1)))
	# quadro ~26: traço verde sob o dedo
	em(30, func(): toque(0, tela(b), false))
	# dois dedos: pinça para afastar
	var c := Vector2(640, 360)
	em(40, func(): toque(0, c + Vector2(-120, 0), true); toque(1, c + Vector2(120, 0), true))
	for k in range(1, 11):
		var d0 := 120.0 - (k - 1) * 6.0
		var d1 := 120.0 - k * 6.0
		em(40 + k, func(): arrasto(0, c + Vector2(-d0, 0), c + Vector2(-d1, 0)); arrasto(1, c + Vector2(d0, 0), c + Vector2(d1, 0)))
	em(52, func(): toque(0, c + Vector2(-60, 0), false); toque(1, c + Vector2(60, 0), false))
	# quadro ~60: câmera afastada, nada construído pelo gesto de dois dedos


## Trem: câmera segue a composição saindo da estação A; no fim, o fantasma de um trem novo na aba Trilhos.
func _roteiro_trem() -> void:
	for q in range(2, 200, 2):
		em(q, func():
			if cena.trens.is_empty():
				return
			var t: Trem = cena.trens[0]
			var c: Vector2 = t.ponto_em(t.s - t.comprimento() / 2.0).pos
			cena.camera.alvo = cena.camera.alvo.lerp(Grade.ponto_mundo(c), 0.15)
			cena.camera.posicionar())
	em(150, func(): clicar(botao("cat:6")))
	em(152, func(): clicar(botao("trem")))
	em(154, func(): mover(tela(Vector2i(13, -8))))


## Ataque: um grupo vem para a fábrica pelo leste (torres atiram); outro, fora do alcance, morde um muro a oeste.
func _roteiro_ataque() -> void:
	em(3, func():
		var col: Colonia = cena.colonia
		for x in range(-3, 4):                     # o mapa carrega no fundo: garante os ninhos em volta
			for y in range(-3, 4):
				col.descobrir_chunk(Vector2i(x, y))
		var ninho: int = col.ninhos.keys()[0]
		var alvo := -1
		for id in cena.mapa.estruturas:
			if cena.mapa.estruturas[id].nome == "fornalha": alvo = id
		for k in 5:
			var a := col._nova_aranha(ninho)
			col.aranhas[a].pos = Vector2(34 + (k % 2) * 1.5, -4 + k * 1.3)
			col.aranhas[a].estado = Colonia.E.ATACANDO
			col.aranhas[a].alvo = alvo
		# muro a oeste e 3 aranhas atrás dele
		var con: Construtor = cena.construtor
		for y in range(-8, -1):
			con.mapa.limpar_obstaculo(Vector2i(-24, y))
		cena.sincronizar(con.executar(con.plano_linha("muro_centro", Vector2i(-24, -8), Vector2i(-24, -2), 0)))
		for k in 3:
			var a := col._nova_aranha(ninho)
			col.aranhas[a].pos = Vector2(-29, -6 + k * 1.6)
			col.aranhas[a].estado = Colonia.E.ATACANDO
			col.aranhas[a].alvo = alvo)
	# câmera: primeiro o leste (tiros), depois o muro
	em(4, func(): cena.camera.alvo = Vector3(25, 0, 7); cena.camera.distancia = 15; cena.camera.posicionar())
	em(130, func(): cena.camera.alvo = Vector3(-24, 0, 4); cena.camera.distancia = 11; cena.camera.posicionar())


## Poluição: adianta 6 minutos de emissão (só a nuvem) e liga a camada com a câmera bem afastada.
func _roteiro_poluicao() -> void:
	em(3, func():
		for i in 360:
			cena.poluicao.emitir(Vector2i(15, 5), 40.0 / 60.0)     # ~ a mini-fábrica a pleno
			cena.poluicao.tick(1.0)
		cena.camera.alvo = Vector3(14, 0, 0); cena.camera.distancia = 70; cena.camera.posicionar())
	em(6, func(): tecla(KEY_P))


func _tela_mundo(p: Vector2) -> Vector2:
	return (cena.camera as Camera3D).unproject_position(Grade.ponto_mundo(p, 0.5))


func _botao_detalhe(i: int) -> Vector2:
	var bs: Array = cena.controle.barra._det_botoes.get_children()
	return (bs[i] as Control).get_global_rect().get_center() if i < bs.size() else Vector2(-1, -1)


## Painel: clica no trem (rota: liga a estação 2), depois na fornalha (escolhe receita de tijolo).
func _roteiro_painel() -> void:
	em(3, func(): cena.camera.alvo = Vector3(12, 0, 6); cena.camera.distancia = 16; cena.camera.posicionar())
	em(8, func():
		var t: Trem = cena.trens[0]
		clicar(_tela_mundo(t.poses()[1].pos)))
	em(14, func(): clicar(_botao_detalhe(1)))
	# quadro ~30: painel do trem com a estação 2 na rota
	em(40, func():
		for id in cena.mapa.estruturas:
			if cena.mapa.estruturas[id].nome == "fornalha":
				var e: Dictionary = cena.mapa.estruturas[id]
				clicar(_tela_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot))))
	em(46, func(): clicar(_botao_detalhe(2)))
	# quadro ~60: painel da fornalha com a receita escolhida


## Variações de energia: painel solar, turbina eólica, acumulador, baú grande e montadora em turbo (avariada).
## Quadro ~40: painel do acumulador; ~100: painel da montadora (integridade, reparo, liga/desliga, modos).
var _ids := {}
var _ids_o := Vector2i.ZERO


func _roteiro_energia() -> void:
	em(2, func():
		Sessao.config.fps = false
		var g := Grade.gerador
		var o := Vector2i(9999, 0)
		for r in range(14, 80, 2):
			for k in 32:
				var c := Vector2i((Vector2.from_angle(k * TAU / 32.0) * r).round())
				if o.x != 9999:
					continue
				var ok := true
				for i in 10:
					for j in 9:
						var t := c + Vector2i(i, j)
						if g.terreno(t) != GeradorMundo.Terreno.TERRA or g.nivel(t) != g.nivel(c) or g.em_encosta(t) or cena.mapa.tiles.has(t):
							ok = false
				if ok:
					o = c
		print("ENERGIA em ", o)
		_ids_o = o
		var con: Construtor = cena.construtor
		for i in range(-1, 11):
			for j in range(-1, 10):
				cena.mapa.limpar_obstaculo(o + Vector2i(i, j))
		var p := func(nome: String, d: Vector2i) -> void:
			cena.sincronizar(con.executar(con.plano_peca(nome, o + d, 0)))
			_ids[nome] = cena.mapa.tiles.get(o + d, -1)
		p.call("painel_solar", Vector2i(0, 0))
		p.call("turbina_eolica", Vector2i(0, 3))
		p.call("acumulador", Vector2i(3, 0))
		p.call("poste_energia", Vector2i(4, 3))
		p.call("montadora", Vector2i(6, 0))
		p.call("bau_grande", Vector2i(3, 5))
		cena.clima.forcar("limpo", true)
		cena.camera.alvo = Grade.centro_mundo(o + Vector2i(4, 3))
		cena.camera.distancia = 12.0
		cena.camera.posicionar())
	em(6, func():
		var f: Fabrica = cena.fabrica
		var mq: int = _ids.montadora
		cena.mapa.estruturas[mq]["modo"] = "turbo"
		cena.colonia.vida[mq] = 140.0
		f.reconstruir()
		f.escolher_receita(mq, "engrenagem")
		f.maquinas[mq].entradas = {"placa_ferro": 4}
		f.maquinas[mq].acordar()
		f.baus[_ids.bau_grande].merge({"placa_ferro": 900, "engrenagem": 240})
		f.acumulado[_ids.acumulador] = 31.0
		f._membros[_ids.acumulador].acum_mj = 31.0)
	em(20, func(): _clicar_id(_ids.acumulador))
	em(70, func(): _clicar_id(_ids.montadora))
	em(122, func(): cena.selecionar(Vector2.INF))
	em(130, func(): clicar(botao("cat:5")))
	# quadro ~160: peças de Energia com a ficha (gera/usa kW, MJ, itens, integridade)
	em(170, func():
		cena.controle.barra.fechar_pecas()
		cena.camera.alvo = Grade.centro_mundo(_ids_o + Vector2i(1, 4))
		cena.camera.distancia = 8.0
		cena.camera.posicionar())
	# quadros 180+: turbina girando de perto


func _clicar_id(id: int) -> void:
	var e: Dictionary = cena.mapa.estruturas[id]
	clicar(_tela_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot)))


## Resumo do estado que tem que sobreviver a salvar + carregar.
static func digital(c: Node) -> String:
	var itens := 0
	for cm in c.fabrica.caminhos:
		itens += cm.esteira.itens.size()
	var inv := 0
	for k in c.inventario:
		inv += int(c.inventario[k])
	var nomes := {}
	for id in c.mapa.estruturas:
		nomes[c.mapa.estruturas[id].nome] = int(nomes.get(c.mapa.estruturas[id].nome, 0)) + 1
	var chaves := nomes.keys()
	chaves.sort()
	return "estr=%d %s inv=%d itens=%d aranhas=%d ninhos=%d polu=%.1f pesq=%s/%d trens=%d limpos=%d sem=%d" % [
			c.mapa.estruturas.size(), ",".join(chaves.map(func(k): return "%s:%d" % [k, nomes[k]])), inv, itens,
			c.colonia.aranhas.size(), c.colonia.ninhos.size(), c.poluicao.total(), c.pesquisa.ativa, c.pesquisa.feitos,
			c.trens.size(), c.mapa.limpos.size(), c.semente]


## Jogo novo: constrói (com custo), escolhe pesquisa, põe itens na esteira, salva e imprime o resumo.
func _roteiro_salvar() -> void:
	em(5, func():
		var con: Construtor = cena.construtor
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-8, 4), Vector2i(-2, 4), 0)))
		cena.sincronizar(con.executar(con.plano_peca("bau", Vector2i(4, 4), 0)))
		cena.sincronizar(con.executar(con.plano_remocao(Vector2i(-12, -12), Vector2i(12, 12))))  # limpa e devolve
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-8, 4), Vector2i(-2, 4), 0)))
		cena.pesquisa.escolher("defesa")
		cena.pesquisa.feitos = 3)
	em(20, func():
		var e: EsteiraCaminho = cena.fabrica.caminhos[0].esteira
		e.inserir_em("pedra", 2.0)
		e.inserir_em("carvao", 4.0))
	em(22, func():
		cena.salvar()
		print("DIGITAL ", digital(cena))
		get_tree().quit())


## Roda do mouse de verdade (push_input): sobre o mapa dá zoom; sobre qualquer interface, não. Imprime RODA_UI OK/FALHA
## e sai (funciona sem janela: -- modo demo roteiro roda_ui).
func _roteiro_roda_ui() -> void:
	var falhas: Array[String] = []
	var roda := func(p: Vector2, sentido := MOUSE_BUTTON_WHEEL_UP) -> float:
		var cam: CameraJogo = cena.camera
		var antes := cam.distancia
		for pressionado in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = sentido
			ev.pressed = pressionado
			ev.position = _jan(p)
			ev.global_position = _jan(p)
			get_viewport().push_input(ev)
		return cam.distancia - antes
	var conf := func(nome: String, p: Vector2, deve: bool) -> void:
		var mudou: bool = absf(roda.call(p)) > 0.0001
		print("  roda em %s %s: %s" % [nome, p, "zoom" if mudou else "sem zoom"])
		if mudou != deve:
			falhas.append(nome)
	process_mode = Node.PROCESS_MODE_ALWAYS        # o menu de pausa para a árvore
	em(3, func(): cena.controle.barra._tocar_categoria(0))
	em(5, func():
		var barra: BarraConstrucao = cena.controle.barra
		var tela_r := get_viewport().get_visible_rect()
		# o ponto do mapa fica entre o status e o painel de peças
		conf.call("mapa", Vector2(tela_r.size.x * 0.4, tela_r.size.y * 0.5), true)
		conf.call("mapa embaixo", Vector2(tela_r.size.x * 0.4, tela_r.size.y - 30.0), true)
		conf.call("painel de peças", barra._painel_pecas.get_global_rect().get_center(), false)
		conf.call("categorias", barra.centro_de("cat:0"), false)
		conf.call("ferramentas", barra.centro_de("menu"), false)
		conf.call("status", barra._info.get_global_rect().get_center(), false)
		cena._sel = {"estrutura": cena.mapa.estruturas.keys()[0]}
		cena._detalhe())
	em(8, func():
		var barra: BarraConstrucao = cena.controle.barra
		conf.call("detalhe", barra._detalhe.get_global_rect().get_center(), false)
		if barra._recursos != null and barra._recursos.visible:
			conf.call("recursos", barra._recursos.get_global_rect().get_center(), false)
		cena._sel = {}
		cena._detalhe()
		barra.fechar_pecas()
		cena.pausa.abrir())
	em(11, func():
		conf.call("menu de pausa", get_viewport().get_visible_rect().get_center(), false)
		if not Toque.sobre_ui(get_tree(), get_viewport().get_visible_rect().get_center()):
			falhas.append("sobre_ui no menu de pausa")
		cena.pausa.fechar()
		cena.abrir_pesquisa())
	em(14, func():
		conf.call("tela de pesquisa", get_viewport().get_visible_rect().get_center(), false)
		cena.abrir_pesquisa())
	em(17, func():
		conf.call("mapa de novo", get_viewport().get_visible_rect().size * Vector2(0.4, 0.5), true)
		print("RODA_UI ", "OK" if falhas.is_empty() else "FALHA %s" % str(falhas))
		get_tree().quit())


## Fotos de um raio caindo na peça mais alta da demo, quadro a quadro (-- modo demo roteiro raio_foto saida_fotos <pasta>,
## com --fixed-fps 30 sob xvfb-run): para conferir o desenho do relâmpago sem abrir janela na tela de ninguém.
func _roteiro_raio_foto() -> void:
	var args := OS.get_cmdline_user_args()
	var pasta: String = args[args.find("saida_fotos") + 1] if args.has("saida_fotos") else "/tmp"
	DirAccess.make_dir_recursive_absolute(pasta)
	var alvo := [Vector2.ZERO]
	em(2, func():
		Sessao.config.fps = false
		cena.controle.barra.visible = false
		var melhor := -1
		var alt := 0.0
		for id in cena.mapa.estruturas:
			var h := Raios.altura(cena.mapa.estruturas[id].nome)
			if h > alt:
				alt = h
				melhor = id
		var e: Dictionary = cena.mapa.estruturas[melhor]
		alvo[0] = Grade.centro_da_area(e.minimo, e.area, e.rot)
		print("RAIO_FOTO alvo %s (%.1f m) em %s" % [e.nome, alt, alvo[0]])
		cena.clima.forcar("tempestade", true)
		cena.camera.alvo = Grade.centro_mundo(Vector2i(alvo[0].floor()))
		cena.camera.distancia = 30.0
		cena.camera.posicionar())
	var foto := func(nome: String) -> void:
		get_viewport().get_texture().get_image().save_png(pasta.path_join(nome + ".png"))
	em(40, func(): cena.raios.cair(alvo[0]))
	em(42, func(): foto.call("raio_q2"))
	em(44, func(): foto.call("raio_q4"))
	em(47, func(): foto.call("raio_q7"))
	em(70, func():
		cena.camera.distancia = 60.0
		cena.camera.posicionar()
		cena.raios.cair(alvo[0] + Vector2(6, -4)))
	em(72, func(): foto.call("raio_longe_q2"))
	em(75, func(): foto.call("raio_longe_q5"))
	em(80, func(): get_tree().quit())


## Pausa de verdade (teclas injetadas): Esc abre o menu, a árvore para e o relógio dos shaders (Engine.time_scale) zera;
## Esc de novo volta ao jogo com o relógio de antes; Esc nas configurações só volta à lista. Imprime PAUSA OK/FALHA e sai
## (sem janela: -- modo demo roteiro pausa).
func _roteiro_pausa() -> void:
	var falhas: Array[String] = []
	var escala := Engine.time_scale
	var conf := func(nome: String, aberto: bool) -> void:
		if cena.pausa.visible != aberto or get_tree().paused != aberto:
			falhas.append("%s: menu %s, árvore %s" % [nome, "aberto" if cena.pausa.visible else "fechado", "parada" if get_tree().paused else "andando"])
		if not is_equal_approx(Engine.time_scale, 0.0 if aberto else escala):
			falhas.append("%s: time_scale %.2f" % [nome, Engine.time_scale])
	process_mode = Node.PROCESS_MODE_ALWAYS        # o menu de pausa para a árvore
	em(3, func(): cena.controle.barra.fechar_pecas(); tecla(KEY_ESCAPE))
	em(6, func(): conf.call("esc abre", true); tecla(KEY_ESCAPE))
	em(9, func(): conf.call("esc fecha", false); tecla(KEY_ESCAPE))
	em(12, func():
		conf.call("abre de novo", true)
		cena.pausa._caixa.visible = false
		cena.pausa._config.visible = true
		tecla(KEY_ESCAPE))
	em(15, func():
		conf.call("esc nas configurações", true)
		if cena.pausa._config.visible or not cena.pausa._caixa.visible:
			falhas.append("esc não voltou das configurações à lista")
		tecla(KEY_ESCAPE))
	em(18, func():
		conf.call("fecha pela lista", false)
		cena.pausa.abrir(true)
		tecla(KEY_ESCAPE))
	em(21, func():
		conf.call("derrota não fecha com esc", true)
		cena.pausa.fechar()
		conf.call("fechar()", false)
		print("PAUSA ", "OK" if falhas.is_empty() else "FALHA %s" % str(falhas))
		get_tree().quit())


## Mesmo lugar e câmera, céu limpo x tufão: uma foto a cada 0,4 s por 12 s, para comparar amplitude e ritmo. Só para
## conferir: -- modo demo roteiro vento_cmp <pasta> (com --fixed-fps 30)
func _roteiro_vento_cmp() -> void:
	var args := OS.get_cmdline_user_args()
	var pasta: String = args[args.find("vento_cmp") + 1]
	var foto := func(nome: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(pasta.path_join(nome + ".png"))
	for c in cena.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	var cam: CameraJogo = cena.camera
	cam.set_process(false)
	cena.controle.process_mode = Node.PROCESS_MODE_DISABLED
	var alvo := Vector3(float(args[args.find("vento_cmp") + 2]), 0.0, float(args[args.find("vento_cmp") + 3]))
	var enquadrar := func() -> void:
		cam.alvo = alvo
		cam.distancia = float(args[args.find("vento_cmp") + 4])
		cam.posicionar()
		cena.clima.direcao_vento = Vector2(1, 0)
	var q := 5
	for forca in [0.35, 1.0]:                         # céu limpo em ambos: só o vento muda (chuva atrapalharia a comparação)
		var f: float = forca
		for i in 30 + 30 * 12:
			em(q + i, func(): cena.clima.valores.vento = f)
		em(q, func():
			cena.clima.forcar("limpo", true)
			enquadrar.call())
		q += 30
		for i in 30:
			var k: int = i
			em(q + i * 12, func():
				enquadrar.call()
				foto.call("v%03d_%02d" % [roundi(f * 100), k]))
		q += 30 * 12 + 2
	em(q, func(): get_tree().quit())


## Conferência da interface nova (estoque e painel do braço), com a tela de verdade. Só para conferir: as imagens vão
## para a pasta do argumento: -- modo novo roteiro fotos_ui <pasta>
func _roteiro_fotos_ui() -> void:
	var args := OS.get_cmdline_user_args()
	var pasta: String = args[args.find("fotos_ui") + 1]
	var foto := func(nome: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(pasta.path_join(nome + ".png"))
		print("foto ", nome)
	var estoque_cheio := func() -> void:
		for k in Registro.itens:
			cena.inventario[k] = 3 + (k.hash() % 2000 + 2000) % 2000
		cena.inventario["placa_ferro"] = 123456
	var braco := func(nome: String) -> void:
		var con: Construtor = cena.construtor
		cena.sincronizar(con.executar(con.plano_peca(nome, Vector2i(6, 6), 0)))
		for id in cena.mapa.estruturas:
			if cena.mapa.estruturas[id].nome == nome:
				cena.fabrica.reconstruir()
				cena._sel = {"estrutura": id}
				cena.mapa.estruturas[id]["filtros"] = ["carvao"]
				cena.fabrica.reconstruir()
				cena._detalhe()
	em(4, func(): cena.controle.barra.indicador_salvando(true))
	em(10, func(): foto.call("a_kit_inicial"))
	em(14, func():
		cena.controle.barra.indicador_salvando(false)
		estoque_cheio.call())
	em(25, func(): foto.call("b_estoque_vertical"))
	em(28, func():
		Sessao.config.recursos_orientacao = "horizontal"
		cena._hud())
	em(35, func(): foto.call("c_estoque_horizontal"))
	em(38, func():
		Sessao.config.recursos_orientacao = "vertical"
		braco.call("braco"))
	em(48, func(): foto.call("d_braco_comum"))
	em(50, func():                                  # aperta os botões de verdade da grade
		var e: Dictionary = cena.mapa.estruturas[cena._sel.estrutura]
		var barra: BarraConstrucao = cena.controle.barra
		var aperta := func(dica: String) -> void:
			for b in barra._det_botoes.find_children("*", "Button", true, false):
				if b.tooltip_text == dica or b.text.begins_with(dica):
					(b as Button).pressed.emit()
					return
		aperta.call("Pedra")
		print("FILTRO_UI pedra -> ", e.filtros, " ", cena.fabrica.bracos[cena._sel.estrutura].filtro)
		aperta.call("Carvão")
		print("FILTRO_UI troca -> ", e.filtros)
		aperta.call("Carvão")
		print("FILTRO_UI de novo -> ", e.filtros)
		aperta.call("Pedra")
		aperta.call("Auto")
		print("FILTRO_UI auto -> ", e.filtros, " '", cena.fabrica.bracos[cena._sel.estrutura].filtro, "'"))
	em(52, func():
		cena._sel = {}
		cena._detalhe()
		cena.controle.barra._tocar_categoria(1))
	em(60, func(): foto.call("e_pecas_abertas"))
	em(64, func():
		cena.controle.barra.fechar_pecas()
		cena.pausa.abrir())
	em(66, func():
		cena.pausa._config.visible = true
		cena.pausa._caixa.visible = false)
	em(72, func(): foto.call("f_config"))
	em(78, func(): get_tree().quit())
	process_mode = Node.PROCESS_MODE_ALWAYS


## Estresse: 2 400 esteiras + 20 torres + itens; mede quadros por segundo e chamadas de desenho na janela real.
func _roteiro_estresse() -> void:
	em(3, func():
		var con: Construtor = cena.construtor
		for x in range(20, 110):
			for y in range(-40, 30):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		for i in 40:
			cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(24 + i * 2, -35), Vector2i(24 + i * 2, 24), 0)))
		for i in 20:
			cena.sincronizar(con.executar(con.plano_peca("torre_defesa", Vector2i(24 + i * 4, 27), 0)))
		cena.camera.alvo = Vector3(64, 0, 5)
		cena.camera.distancia = 44.0
		cena.camera.posicionar())
	em(10, func():
		for cm in cena.fabrica.caminhos:
			for k in 200:
				cm.esteira.inserir_em("pedra", k * 0.3))
	for q in [120, 240, 360]:
		em(q, _medir.bind(q))


func _medir(q: int) -> void:
	var tf := Time.get_ticks_usec()
	for i in 10:
		cena.fabrica.tick(1.0 / 30.0)
	var tc := Time.get_ticks_usec()
	for i in 10:
		cena.colonia.tick(1.0 / 30.0, [] as Array[Dictionary])
	print("      itens %.1f ms · fábrica %.2f ms · colônia %.2f ms" % [cena._desenho_itens.custo_us / 1000.0, (tc - tf) / 10000.0, (Time.get_ticks_usec() - tc) / 10000.0])
	print("ESTRESSE quadro %d: %d fps · %.1f ms de processo · %d chamadas de desenho · %d objetos · %d estruturas · %d nós" % [q,
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), cena.mapa.estruturas.size(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


## Vitrine (fotos): esteira elevada com rampas e pilares sobre outra esteira, fumaça e ícones de estado, painel de
## pesquisa, menu de pausa.
func _roteiro_vitrine() -> void:
	em(3, func():
		var con: Construtor = cena.construtor
		for x in range(-14, 2):
			for y in range(-14, -4):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-6, -13), Vector2i(-6, -5), 0)))
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-13, -9), Vector2i(-11, -9), 0)))
		cena.sincronizar(con.executar(con.plano_peca("esteira_rampa", Vector2i(-10, -9), Construtor.rot_do_fluxo(1))))
		con.nivel = 1
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-9, -9), Vector2i(-3, -9), 0)))
		cena.sincronizar(con.executar(con.plano_peca("rampa_desce", Vector2i(-2, -9), Construtor.rot_do_fluxo(1))))
		con.nivel = 0
		cena.sincronizar(con.executar(con.plano_linha("esteira", Vector2i(-1, -9), Vector2i(1, -9), 0)))
		cena.sincronizar(con.executar(con.plano_peca("montadora", Vector2i(-11, -12), 0)))
		cena.camera.alvo = Vector3(-6, 0, 9); cena.camera.distancia = 15; cena.camera.posicionar())
	em(12, func():
		var e: EsteiraCaminho = cena.fabrica.caminhos[cena.fabrica._no_tile[Vector2i(-13, -9)][0]].esteira
		for k in 12:
			e.inserir_em("minerio_ferro", k * 0.6)
		var c2: EsteiraCaminho = cena.fabrica.caminhos[cena.fabrica._no_tile[Vector2i(-6, -13)][0]].esteira
		for k in 10:
			c2.inserir_em("carvao", k * 0.7))
	# quadro ~70: foto da elevada
	em(80, func(): cena.camera.alvo = Vector3(12, 0, -2); cena.camera.distancia = 18; cena.camera.posicionar())
	# quadro ~110: fumaça do gerador/extrator e ícone "sem receita" da fornalha
	em(120, func(): cena.abrir_pesquisa())
	# quadro ~135: painel de pesquisa (na demo: tudo liberado)
	em(140, func(): cena.abrir_pausa())
	# quadro ~150: pausa


## Panorama: arrasta a câmera a 18 m/s por terreno novo durante 12 s (zoom padrão) e depois 6 s afastada;
## mede o tempo de cada quadro na janela real (média, pior 5%, pior caso, quadros acima de 33 ms).
var _tempos: PackedFloat32Array = []
var _t_ant := 0
var _fase := 0
func _roteiro_panorama() -> void:
	em(30, func(): _fase = 1; _t_ant = Time.get_ticks_usec())


func _physics_process(_d: float) -> void:
	pass


func _notification(what: int) -> void:
	if what != NOTIFICATION_PROCESS or _fase == 0:
		return
	var agora := Time.get_ticks_usec()
	var dt := (agora - _t_ant) / 1000.0
	_t_ant = agora
	var cam: CameraJogo = cena.camera
	cam.alvo += Vector3(18.0, 0, 6.0) * dt / 1000.0
	cam.posicionar()
	_tempos.append(dt)
	var total := 0.0
	for t in _tempos: total += t
	if _fase == 1 and total > 12000.0:
		_relatorio_tempos("zoom padrão (44 m)")
		_tempos.clear()
		cam.distancia = 110.0
		_fase = 2
	elif _fase == 2 and total > 6000.0:
		_relatorio_tempos("zoom longe (110 m)")
		_fase = 0
		get_tree().quit()


func _relatorio_tempos(rotulo: String) -> void:
	var v := Array(_tempos)
	v.sort()
	var soma := 0.0
	var acima := 0
	for t in v:
		soma += t
		if t > 33.4: acima += 1
	print("PANORAMA %s: %d quadros · média %.1f ms · pior 5%% %.1f ms · pior %.1f ms · %d acima de 33 ms" % [
			rotulo, v.size(), soma / v.size(), v[int(v.size() * 0.95)], v[-1], acima])


## Fios: a rede da demo (gerador → postes → extrator e braços) e a prévia de um poste novo com o anel de alcance.
func _roteiro_fios() -> void:
	em(3, func(): cena.camera.alvo = Vector3(13, 0, -2); cena.camera.distancia = 17; cena.camera.posicionar())
	em(60, func(): clicar(botao("cat:4")))
	em(62, func(): clicar(botao("poste_energia")))
	em(64, func(): mover(tela(Vector2i(19, 9))))
	# quadro ~75: fios da demo + prévia amarela do poste novo e o anel de 9 m


## Teste de textura: o trem com o vagão texturizado; câmera de perto acompanhando a composição.
func _roteiro_vagao_tex() -> void:
	cena.controle.barra.visible = false
	for q in range(2, 300, 2):
		em(q, func():
			if cena.trens.is_empty():
				return
			var t: Trem = cena.trens[0]
			var c: Vector2 = t.ponto_em(t.s - t.comprimento() / 2.0).pos
			cena.camera.alvo = Grade.ponto_mundo(c)
			cena.camera.distancia = 9.0
			cena.camera.posicionar())


const ESTUDOS := ["montadora", "fornalha", "laboratorio", "viveiro", "refinador", "nucleo", "terraplenagem",
		"gerador", "painel_solar", "acumulador", "coletor_lixo"]


## Vitrine dos modelos convertidos (arte/estudos/para_jogo.py): limpa um terreno, põe uma de cada em duas fileiras
## e leva a câmera de perto em cada uma — quadro 30 + 30·i (foto no quadro 52 + 30·i).
func _roteiro_estudos() -> void:
	Sessao.config.fps = false
	cena.animar_tudo = true
	var posicoes: Array[Vector2i] = []
	em(4, func():
		cena.controle.barra.visible = false
		cena._efeitos.mostrar_icones = false
		var con: Construtor = cena.construtor
		for x in range(-44, -6):
			for y in range(-14, 14):
				cena.mapa.limpar_obstaculo(Vector2i(x, y))
		for i in ESTUDOS.size():
			var t := Vector2i(-42 + (i % 7) * 5, -8 if i < 7 else 4)
			cena.sincronizar(con.executar(con.plano_peca(ESTUDOS[i], t, 0)))
			posicoes.append(t))
	for i in ESTUDOS.size():
		em(30 + 30 * i, func():
			var area := Registro.area(ESTUDOS[i])
			var cam: CameraJogo = cena.camera
			cam.alvo = Grade.ponto_mundo(Vector2(posicoes[i]) + Vector2(area) / 2.0)
			cam.distancia = 4.2 if area.x >= 3 else 3.4
			cam.posicionar())
	em(30 + 30 * ESTUDOS.size() + 4, func(): get_tree().quit())


## Medição detalhada da troca de categoria na BarraConstrucao (ícone, pesquisa, texto/autowrap, add_child/layout e _tocar_categoria).
func _roteiro_abas() -> void:
	em(5, func():
		var barra: BarraConstrucao = cena.controle.barra
		var cats: Array = Registro.menu.get("categorias", [])
		var icones: Dictionary = Registro.menu.get("icones", {})
		var expl: Dictionary = Registro.menu.get("explicacoes", {})
		var t_ic := 0
		var t_custo := 0
		var t_lib := 0
		var t_dev := 0
		var t_btn := 0
		var t_add := 0
		var t_marcar := 0
		var t_layout := 0
		var cx_med := VBoxContainer.new()
		cx_med.custom_minimum_size.x = 280.0
		barra._raiz.add_child(cx_med)
		for i in cats.size():
			var pecas: Array = cats[i].pecas
			for k in pecas.size():
				var nome: String = pecas[k]
				var u0 := Time.get_ticks_usec()
				var ic := barra._icone(icones.get(nome, nome))
				var u1 := Time.get_ticks_usec()
				var custo := Construtor.custo_de(nome)
				var partes: Array[String] = []
				for it in custo:
					partes.append("%d %s" % [custo[it], Registro.itens.get(it, {}).get("nome", it).to_lower()])
				var f := BarraConstrucao.ficha(nome)
				var extra := (" · " + f) if f != "" else ""
				var u2 := Time.get_ticks_usec()
				var bloqueada: bool = barra.liberado.is_valid() and not barra.liberado.call(nome)
				var u3 := Time.get_ticks_usec()
				var dev := barra.peca_em_desenvolvimento(nome)
				var u4 := Time.get_ticks_usec()
				var b := Button.new()
				b.custom_minimum_size = Vector2(0, Tema.n("peca_alt"))
				b.focus_mode = Control.FOCUS_NONE
				b.icon = ic
				b.expand_icon = false
				b.add_theme_constant_override("icon_max_width", Tema.n("peca_icone"))
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				var custo_txt: String = "" if dev else ("🔒 pesquisar" if bloqueada else ", ".join(partes))
				b.text = "%s\n%s\n%s%s" % [barra.rotulo(nome), expl.get(nome, ""), custo_txt, "" if bloqueada or dev else extra]
				b.add_theme_font_size_override("font_size", Tema.n("f_peq"))
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				var u5 := Time.get_ticks_usec()
				cx_med.add_child(b)
				var u6 := Time.get_ticks_usec()
				t_ic += u1 - u0
				t_custo += u2 - u1
				t_lib += u3 - u2
				t_dev += u4 - u3
				t_btn += u5 - u4
				t_add += u6 - u5
		var um0 := Time.get_ticks_usec()
		barra.marcar(barra._selecionada, barra._removendo)
		var um1 := Time.get_ticks_usec()
		var _s := cx_med.get_combined_minimum_size()
		var um2 := Time.get_ticks_usec()
		t_marcar = um1 - um0
		t_layout = um2 - um1
		cx_med.free()
		print("ABAS_PARTES icone=%.2fms custo_ficha=%.2fms liberado=%.2fms em_dev=%.2fms botao_txt=%.2fms add_child=%.2fms marcar=%.2fms layout=%.2fms" % [
			t_ic / 1000.0, t_custo / 1000.0, t_lib / 1000.0, t_dev / 1000.0, t_btn / 1000.0, t_add / 1000.0, t_marcar / 1000.0, t_layout / 1000.0])
		barra.atualizar_bloqueios()
		var tempos_troca: Array[float] = []
		for volta in 3:
			for i in cats.size():
				var ti := Time.get_ticks_usec()
				barra._tocar_categoria(i)
				var tf := Time.get_ticks_usec()
				tempos_troca.append((tf - ti) / 1000.0)
		var soma := 0.0
		var pior := 0.0
		for v in tempos_troca:
			soma += v
			pior = maxf(pior, v)
		print("ABAS_TROCA trocas=%d total=%.2fms media=%.3fms pior=%.3fms" % [
			tempos_troca.size(), soma, soma / maxf(1, tempos_troca.size()), pior])
		get_tree().quit())











