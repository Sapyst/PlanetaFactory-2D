class_name ControleConstrucao
extends Node
## Roteia toda a entrada do jogo (é o único lugar que decide se um gesto constrói ou mexe na câmera):
##
##  PC      peça na mão: passar o mouse = fantasma; clicar = pôr; arrastar = traçar (esteira/cano/trilho/muro/poste)
##          botão direito: cancela (clique) ou move a câmera (arrasto); meio ou esquerdo sem peça = move a câmera
##          roda = zoom; Q/E = gira a câmera; WASD/setas = anda; R = girar peça (Shift+R ao contrário)
##          X = remover; L = aplainar (Terraplenagem); V = visão de recursos; Ctrl+Z = desfazer; Esc = cancelar; 1..9 = peça da aba; Tab = próxima aba
##          Com estrutura selecionada: O = ligar/desligar; R = girar; Del = remover; Ctrl+C/Ctrl+V = copiar/colar configuração; Esc = fechar o painel
##  Toque   1 dedo com peça na mão: o fantasma segue o dedo e a peça é posta ao soltar (arrastar = traçar)
##          1 dedo sem peça = move a câmera; 2 dedos = move + pinça (zoom) e cancelam o traço em andamento
##
## O mundo só precisa de `sincronizar(relatorio)` para desenhar o que o Construtor mudou no mapa.

var construtor: Construtor
var camera: CameraJogo
var barra: BarraConstrucao
var fantasma: Fantasma
var mundo: Node                     ## precisa de sincronizar(rel: Dictionary)

var peca := ""                      ## "" = mão vazia
var removendo := false
const APLAINAR := "#aplainar"       ## ferramenta da Terraplenagem (peça "na mão" que planeja um retângulo)
const ESCAVAR := "#escavar"         ## Terraplenagem para baixo: buraco/canal 1 nível abaixo de onde o arraste começou
var rot := 0

var _plano: Array[Dictionary] = []
var _chave_plano := ""
var _cursor := Vector2i.ZERO
var _cursor_valido := false
var _ima_tile := Vector2i(1 << 30, 0)   ## braço: tile onde o ímã já virou a peça para a esteira
var _rot_manual := false                ## o jogador girou depois do ímã (vale até mudar de tile)
var _gesto := false                 ## traço/colocação em andamento (botão ou dedo pressionado)
var _inicio := Vector2i.ZERO
var _arrasto_camera := false
var _botao_dir := false
var _dir_moveu := 0.0
var _toques: Dictionary = {}        ## índice → posição
var _dedo := -1                     ## dedo do gesto de construção
var _pinca := 0.0
var _por_toque := false
var _aviso := ""
var _aviso_ate := 0
var _clique_ini := Vector2.INF
var _segurar := {}                     ## toque segurado: {i, pos, t, feito} — meio segundo parado = clique direito
const SEGURAR_MS := 500
## Peça pendente (máquinas e afins, não caminhos): tocar/clicar põe o holograma; ele espera Girar, Mover
## (arrastar o holograma ou tocar noutro lugar) e Construir. Caminhos (esteira, cano, trilho, muro) seguem no arraste.
var _pendente := false
var _tile_pend := Vector2i.ZERO
var _movendo := false
var _arrastando_pend := false        ## onde começou um clique/toque de mão vazia (se não arrastar, seleciona)


func configurar(p_construtor: Construtor, p_camera: CameraJogo, p_barra: BarraConstrucao, p_fantasma: Fantasma, p_mundo: Node) -> void:
	construtor = p_construtor
	camera = p_camera
	barra = p_barra
	fantasma = p_fantasma
	mundo = p_mundo
	barra.peca_escolhida.connect(escolher)
	barra.ferramenta.connect(_ferramenta)
	barra.acao_pendente.connect(_acao_pendente)
	barra.fechar_detalhe_pedido.connect(func(): mundo.selecionar(Vector2.INF))
	barra.pode_desfazer(false)
	barra.mostrar_nivel(construtor.nivel)
	_atualizar()


# ------------------------------------------------------------------ ações
func _usa_pendente() -> bool:
	return peca != "" and not removendo and peca != APLAINAR and peca != ESCAVAR and not Construtor.arrastavel(peca)


func _acao_pendente(a: String) -> void:
	match a:
		"girar": girar()
		"mover": _movendo = not _movendo
		"construir": _construir_pendente()
		"cancelar_peca":
			_pendente = false
			_movendo = false
	_chave_plano = ""
	_atualizar()


func _construir_pendente() -> void:
	if not _pendente:
		return
	_cursor = _tile_pend
	_cursor_valido = true
	_chave_plano = ""
	_atualizar()
	_confirmar()
	_pendente = false
	_movendo = false


## Fim de um toque/clique sobre o mapa com peça de pôr na mão: põe/move o holograma (dois toques no mesmo
## lugar = construir).
func _soltar_pendente() -> void:
	if not _cursor_valido:
		return
	if _pendente and not _movendo and not _arrastando_pend and _cursor == _tile_pend:
		_construir_pendente()
		return
	_pendente = true
	_tile_pend = _cursor
	_movendo = false
	_chave_plano = ""


func _perto_do_holograma(tela: Vector2) -> bool:
	if not _pendente:
		return false
	var p := camera.no_chao(tela)
	if p == Vector3.INF:
		return false
	var c := Grade.centro_da_area(_tile_pend, Registro.area(peca), rot)
	return Vector2(p.x, -p.z).distance_to(c) < maxf(1.4, Registro.area(peca).x * 0.8)


func escolher(nome: String) -> void:
	if nome != "" and not nome.begins_with("#") and barra.peca_em_desenvolvimento(nome):
		_avisar("%s: %s (ainda não está no jogo)" % [barra.rotulo(nome), Tema.TEXTO_DESENVOLVIMENTO.to_lower()])
		return
	_pendente = false
	_movendo = false
	if peca == nome and not removendo:
		nome = ""                          # tocar de novo na peça solta ela
	peca = nome
	removendo = false
	_cancelar_gesto()
	barra.marcar(peca, removendo)
	_atualizar()


func girar(passo := -1) -> void:
	if peca == "":
		return
	rot = posmod(rot + passo, 4)           # −1 = horário (como o jogador espera do botão)
	_rot_manual = true
	_atualizar()


func alternar_aplainar() -> void:
	escolher(APLAINAR)


func alternar_escavar() -> void:
	escolher(ESCAVAR)


func alternar_remover() -> void:
	removendo = not removendo
	peca = ""
	_cancelar_gesto()
	barra.marcar(peca, removendo)
	_atualizar()


## Nível da esteira (0 chão, 1 = 0,5 m, 2 = 1,0 m). `ciclo` = volta ao chão depois do último.
func mudar_nivel(passo: int, ciclo := false) -> void:
	var n := construtor.nivel + passo
	n = posmod(n, MapaOcupacao.NIVEIS + 1) if ciclo else clampi(n, 0, MapaOcupacao.NIVEIS)
	construtor.nivel = n
	barra.mostrar_nivel(n)
	_chave_plano = ""
	_atualizar()


func alternar_recursos() -> void:
	if mundo.has_method("alternar_recursos"):
		var sim: bool = mundo.alternar_recursos()
		barra.ligar_recursos(sim, mundo.camada_visao() if mundo.has_method("camada_visao") else "recursos")


func alternar_poluicao() -> void:
	if mundo.has_method("alternar_poluicao"):
		barra.ligar_poluicao(mundo.alternar_poluicao())


## Pressionar e segurar (celular) = clique direito do mouse: larga o traço, o holograma e a peça na mão.
## Vibra de leve para o dedo sentir que pegou.
func _clique_direito_toque() -> void:
	_clique_ini = Vector2.INF
	if not (_ativo() or _gesto or _pendente):
		return
	Input.vibrate_handheld(35)
	sair_do_modo()                                # traço, holograma e peça na mão: larga tudo (o dedo ainda está encostado)
	_avisar("Cancelado")


func cancelar() -> void:
	if _pendente:
		_pendente = false
		_movendo = false
	elif _gesto:
		_cancelar_gesto()
	else:
		peca = ""
		removendo = false
		barra.marcar(peca, removendo)
	_atualizar()


func _obras() -> Obras:
	return mundo.get("obras") if mundo != null else null


func desfazer() -> void:
	var ob := _obras()
	if ob != null and ob.cancelar_ultimo():         # patch RTS: cancela a última encomenda que ainda não foi feita
		_avisar("Encomenda cancelada")
		_chave_plano = ""
		_atualizar()
		return
	if not construtor.pode_desfazer():
		return
	mundo.sincronizar(construtor.desfazer())
	_avisar("Desfeito")
	_chave_plano = ""
	_atualizar()


func _ferramenta(nome: String) -> void:
	match nome:
		"girar": girar()
		"remover": alternar_remover()
		"desfazer": desfazer()
		"cancelar": cancelar()
		"sair": sair_do_modo()
		"poluicao": alternar_poluicao()
		"recursos": alternar_recursos()
		"aplainar": alternar_aplainar()
		"escavar": alternar_escavar()
		"nivel": mudar_nivel(1, true)
		"pesquisa": mundo.abrir_pesquisa()
		"menu": mundo.abrir_pausa()


func _ativo() -> bool:
	return peca != "" or removendo


## Sai de vez do modo construção (traço, holograma e peça na mão).
func sair_do_modo() -> void:
	for i in 3:
		if _ativo() or _gesto or _pendente:
			cancelar()
	_atualizar()


## Texto da faixa do modo construção ("" = fora dele).
func _texto_modo() -> String:
	if not _ativo():
		return ""
	var sair := "segure o dedo ou toque em Sair para parar" if _por_toque else "clique direito ou Sair para parar"
	if removendo:
		return ("Removendo — clique ou arraste sobre o que tirar · " if Tema.estilo("atalhos") and not _por_toque else "Removendo — toque ou arraste sobre o que tirar · ") + sair
	if peca == APLAINAR:
		return "Aplainando — arraste a área no chão · " + sair
	if peca == ESCAVAR:
		return "Escavando — arraste a área no chão · " + sair
	return "Construindo: %s — %s · %s" % [barra.rotulo(peca), "arraste no chão" if Construtor.arrastavel(peca) else ("clique no chão" if Tema.estilo("atalhos") and not _por_toque else "toque no chão"), sair]


func _confirmar() -> void:
	if _plano.is_empty():
		return
	if removendo and mundo != null and mundo.has_method("eh_armazem_com_itens"):
		var bau_itens := -1
		for it in _plano:
			if it.get("acao") == "remover" and it.motivo == "" and mundo.eh_armazem_com_itens(it.get("id", -1)):
				bau_itens = it.get("id")
				break
		if bau_itens >= 0:
			mundo.pedir_confirmacao_remocao_bau(bau_itens)
			_plano.clear()
			_chave_plano = ""
			return
	var n := Construtor.contar(_plano)
	var enc := 0
	if _obras() != null and mundo.has_method("encomendar"):
		enc = int(mundo.encomendar(_plano).n)              # patch RTS: o drone construtor sai do núcleo e faz
	else:
		mundo.sincronizar(construtor.executar(_plano))
	if n.ok > 0 and peca == "esteira_rampa":
		mudar_nivel(1)                        # subiu: o próximo traço já é no alto
	elif n.ok > 0 and peca == "rampa_desce":
		mudar_nivel(-1)
	if removendo:
		_avisar(("Remoção encomendada: %d" % enc) if enc > 0 else ("Removido: %d" % _plano.size()))
		Som.tocar("remover")
	elif peca == APLAINAR or peca == ESCAVAR:
		if n.ok > 0:
			Som.tocar("construir")
		_avisar("%s: %d tile(s)%s" % ["Escavado" if peca == ESCAVAR else "Aplainado", n.ok,
				"  ·  %d bloqueado(s)" % n.bloqueados if n.bloqueados > 0 else ""])
	elif enc > 0:
		Som.tocar("construir")
		_avisar("Encomendado: %d — o drone sai do núcleo%s" % [enc, "  ·  %d bloqueada(s)" % n.bloqueados if n.bloqueados > 0 else ""])
	elif n.ok > 0:
		Som.tocar("construir")
		_avisar("Construído: %d%s" % [n.ok, "  ·  %d bloqueada(s)" % n.bloqueados if n.bloqueados > 0 else ""])
	_chave_plano = ""


func _cancelar_gesto() -> void:
	_gesto = false
	_dedo = -1


func _avisar(t: String) -> void:
	_aviso = t
	_aviso_ate = Time.get_ticks_msec() + 1600


# ------------------------------------------------------------------ entrada
func _unhandled_input(e: InputEvent) -> void:
	if mundo != null and mundo.has_method("modal_aberto") and mundo.modal_aberto() and not e is InputEventKey:
		return                                      # tela por cima (pesquisa): o toque não mexe no mapa por baixo
	if e is InputEventKey:
		_tecla(e)
	elif e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return                                  # toque já tratado como toque
	elif e is InputEventMouseButton:
		_mouse_botao(e)
	elif e is InputEventMouseMotion:
		_mouse_moveu(e)
	elif e is InputEventScreenTouch:
		_toque(e)
	elif e is InputEventScreenDrag:
		_toque_arrastou(e)
	elif e is InputEventMagnifyGesture:
		if not Toque.sobre_ui(get_tree(), e.position):
			camera.zoom(1.0 / e.factor)
	elif e is InputEventPanGesture:
		if not Toque.sobre_ui(get_tree(), e.position):
			camera.arrastar(-e.delta * 8.0)


func _tecla(e: InputEventKey) -> void:
	if not e.pressed or e.echo:
		return
	var sem_mao := not _ativo() and not _gesto
	if e.ctrl_pressed and e.keycode == KEY_C and sem_mao and mundo.atalho_selecao("copiar"):
		return
	if e.ctrl_pressed and e.keycode == KEY_V and sem_mao and mundo.atalho_selecao("colar"):
		return
	match e.keycode:
		KEY_R:
			if peca == "" and sem_mao:
				mundo.atalho_selecao("girar")
			else:
				girar(1 if e.shift_pressed else -1)
		KEY_O:
			if sem_mao:
				mundo.atalho_selecao("ligar")
		KEY_DELETE:
			if sem_mao:
				mundo.atalho_selecao("remover")
		KEY_X: alternar_remover()
		KEY_P: alternar_poluicao()
		KEY_V: alternar_recursos()
		KEY_L: alternar_aplainar()
		KEY_K: alternar_escavar()
		KEY_N: mudar_nivel(1, true)
		KEY_PAGEUP: mudar_nivel(1)
		KEY_PAGEDOWN: mudar_nivel(-1)
		KEY_ENTER, KEY_KP_ENTER: _construir_pendente()
		KEY_ESCAPE:
			if _ativo() or _gesto: cancelar()
			elif not mundo.atalho_selecao("fechar"): mundo.abrir_pausa()     # Esc fecha o painel antes de abrir o menu
		KEY_T: mundo.abrir_pesquisa()
		KEY_Q: camera.girar(-0.3)
		KEY_E: camera.girar(0.3)
		KEY_TAB: barra.proxima_categoria(-1 if e.shift_pressed else 1)
		KEY_Z:
			if e.ctrl_pressed or e.meta_pressed: desfazer()
		_:
			var n: int = e.keycode - KEY_1
			var lista := barra.pecas_da_categoria()
			if n >= 0 and n < mini(9, lista.size()):
				escolher(lista[n])
	_atualizar()


func _mouse_botao(e: InputEventMouseButton) -> void:
	_por_toque = false
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:      # sobre a interface a roda é dela (rola a lista ou nada)
			if not Toque.sobre_ui(get_tree(), e.position):
				camera.zoom(0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
		MOUSE_BUTTON_MIDDLE: _arrasto_camera = e.pressed
		MOUSE_BUTTON_RIGHT:
			_botao_dir = e.pressed
			if e.pressed:
				_dir_moveu = 0.0
			elif _dir_moveu < 6.0:
				cancelar()
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				if barra.sobre_interface(e.position):
					return
				if _ativo() and (not _pendente or _movendo or _perto_do_holograma(e.position)):
					_mirar(e.position)
					_gesto = true
					_inicio = _cursor
					_arrastando_pend = _pendente and _perto_do_holograma(e.position)
				else:
					_arrasto_camera = true
					_clique_ini = e.position
			else:
				if _clique_ini != Vector2.INF and _clique_ini.distance_to(e.position) < 8.0:
					if _pendente:
						_mirar(e.position)
						_tile_pend = _cursor                  # toque noutro lugar: o holograma vai para lá
						_chave_plano = ""
					else:
						_selecionar(e.position)
				_clique_ini = Vector2.INF
				if _gesto:
					_mirar(e.position)
					if _usa_pendente():
						_soltar_pendente()
					else:
						_atualizar()
						_confirmar()
					_gesto = false
					_arrastando_pend = false
				_arrasto_camera = false
	_atualizar()


func _mouse_moveu(e: InputEventMouseMotion) -> void:
	_por_toque = false
	if _botao_dir:
		_dir_moveu += e.relative.length()
		camera.arrastar(e.relative)
	elif _arrasto_camera:
		camera.arrastar(e.relative)
	_mirar(e.position)
	_atualizar()


func _toque(e: InputEventScreenTouch) -> void:
	_por_toque = true
	if e.pressed:
		if _toques.is_empty() and barra.sobre_interface(e.position):
			return
		_toques[e.index] = e.position
		camera.segurando = true
		_segurar = {"i": e.index, "pos": e.position, "t": 0.0, "feito": false} if _toques.size() == 1 else {}
		if _toques.size() == 1 and _ativo() and (not _pendente or _movendo or _perto_do_holograma(e.position)):
			_dedo = e.index
			_gesto = true
			_arrastando_pend = _pendente and _perto_do_holograma(e.position)
			_mirar(e.position)
			_inicio = _cursor
		elif _toques.size() == 1:
			_clique_ini = e.position
		elif _toques.size() >= 2:
			_clique_ini = Vector2.INF
			_cancelar_gesto()                   # segundo dedo = câmera
			_pinca = _distancia_dedos()
	else:
		if not _toques.has(e.index):
			return
		_toques.erase(e.index)
		if not _segurar.is_empty() and _segurar.i == e.index:
			if _segurar.feito:
				_clique_ini = Vector2.INF               # já agiu como clique direito: soltar não é toque
			_segurar = {}
		if _toques.is_empty():
			camera.soltar()                         # dedo parado antes de soltar: a câmera não sai deslizando
		if _clique_ini != Vector2.INF and _toques.is_empty() and _clique_ini.distance_to(e.position) < Toque.limiar(get_viewport()):
			if _pendente:
				_mirar(e.position)
				_tile_pend = _cursor                    # toque noutro lugar: o holograma vai para lá
				_chave_plano = ""
			else:
				_selecionar(e.position)             # toque curto de mão vazia = ver a peça/trem
		_clique_ini = Vector2.INF
		if _gesto and e.index == _dedo:
			_mirar(e.position)
			if _usa_pendente():
				_soltar_pendente()
			else:
				_atualizar()
				_confirmar()
			_cancelar_gesto()
			_arrastando_pend = false
		if _toques.size() < 2:
			_pinca = 0.0
		if _toques.is_empty():
			_cursor_valido = false        # sem "hover" no toque: o fantasma some ao soltar
	_atualizar()


func _toque_arrastou(e: InputEventScreenDrag) -> void:
	_por_toque = true
	if not _toques.has(e.index):
		return
	var antes: Vector2 = _toques[e.index]
	_toques[e.index] = e.position
	if not _segurar.is_empty() and _segurar.i == e.index and (_segurar.pos as Vector2).distance_to(e.position) >= Toque.limiar(get_viewport()):
		_segurar = {}                               # o dedo andou: é arrasto, não segurar
	if _toques.size() >= 2:
		# dois dedos: o meio deles arrasta o chão e a abertura dá o zoom em volta do meio
		var meio := _meio_dedos()
		camera.arrastar_tela(meio - e.relative / float(_toques.size()), meio)
		var d := _distancia_dedos()
		if _pinca > 0.0 and d > 0.0:
			camera.zoom_em(_pinca / d, meio)
		_pinca = d
	elif _gesto and e.index == _dedo:
		_mirar(e.position)
	elif not _gesto:
		if _clique_ini != Vector2.INF and _clique_ini.distance_to(e.position) < Toque.limiar(get_viewport()):
			return                                  # ainda pode ser um toque: o mapa não treme com o dedo
		if _clique_ini != Vector2.INF:
			antes = _clique_ini                     # começou a arrastar: leva o chão desde onde o dedo encostou
			_clique_ini = Vector2.INF
		camera.arrastar_tela(antes, e.position)
	_atualizar()


func _selecionar(tela: Vector2) -> void:
	var p := camera.no_chao(tela)
	if p != Vector3.INF and mundo.has_method("selecionar"):
		mundo.selecionar(Vector2(p.x, -p.z))


func _meio_dedos() -> Vector2:
	var ps := _toques.values()
	return ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5 if ps.size() >= 2 else Vector2.ZERO


func _distancia_dedos() -> float:
	var ps := _toques.values()
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0


func _mirar(tela: Vector2) -> void:
	if barra.sobre_interface(tela) and not _gesto:
		_cursor_valido = false
		return
	var p := camera.no_chao(tela)
	_cursor_valido = p != Vector3.INF
	if _cursor_valido:
		_cursor = Grade.tile_de_mundo(p)


# ------------------------------------------------------------------ plano + fantasma + dica
func _atualizar() -> void:
	barra.pode_desfazer(construtor.pode_desfazer() or (_obras() != null and _obras().pendentes() > 0))
	barra.modo_construcao(_texto_modo())
	if _pendente and not _usa_pendente():
		_pendente = false
	if _pendente and _gesto and _arrastando_pend and _cursor_valido:
		_tile_pend = _cursor                          # arrastando o holograma
	var mostrar := _ativo() and (_pendente or (_cursor_valido and (_gesto or not _por_toque)))
	if not mostrar:
		barra.acoes_em(Vector2.INF, false, false)
		fantasma.limpar()
		_plano.clear()
		_chave_plano = ""
		barra.dica(_dica_parada(), false)
		return
	var alvo := _tile_pend if _pendente else _cursor
	_ima_braco(alvo)
	var chave := "%s|%s|%d|%s|%s|%s|%d|%s" % [peca, removendo, rot, _inicio, alvo, _gesto, construtor.nivel, _pendente]
	if chave != _chave_plano:
		_chave_plano = chave
		var a := _inicio if _gesto else _cursor
		if removendo:
			_plano = construtor.plano_remocao(a, _cursor)
		elif peca == APLAINAR:
			_plano = construtor.plano_aplainar(a, _cursor)
		elif peca == ESCAVAR:
			_plano = construtor.plano_aplainar(a, _cursor, 1)
		elif Construtor.arrastavel(peca):
			_plano = construtor.plano_linha(peca, a, _cursor, rot)
		else:
			_plano = construtor.plano_peca(peca, alvo, rot)
		fantasma.mostrar(_plano, removendo)
		_previa_fios()
	if _pendente:
		var c := Grade.centro_da_area(_tile_pend, Registro.area(peca), rot)
		var tela := camera.unproject_position(Grade.ponto_mundo(c))
		var raio := camera.unproject_position(Grade.ponto_mundo(c + Vector2(0, -Registro.area(peca).y * 0.6))).y - tela.y
		barra.acoes_em(tela + Vector2(0, absf(raio)), Construtor.pode_tudo(_plano), _movendo)
	else:
		barra.acoes_em(Vector2.INF, false, false)
	_dica_do_plano()


## Ímã do braço: posto encostado numa esteira, ele vira sozinho com a frente (onde solta) para ela, seja qual for o
## giro de antes — sem confusão de lado. Girar depois disso vale até o braço ir para outro tile.
func _ima_braco(alvo: Vector2i) -> void:
	if not Portas.eh_braco(peca) or removendo:
		return
	if alvo != _ima_tile:
		_ima_tile = alvo
		_rot_manual = false
	if _rot_manual:
		return
	for i in 4:
		for id in construtor.mapa.ids_no_tile(alvo + Grade.DIRECOES[i]):
			if Portas.eh_esteira(construtor.mapa.estruturas[id].nome):
				rot = posmod(-i, 4)              # frente do braço (norte girado) aponta para a esteira
				return


## Poste/torre/máquina no fantasma: mostra os fios que vão aparecer e o alcance do poste.
func _previa_fios() -> void:
	var pares := []
	var anel := 0.0
	var centro := Vector3.ZERO
	if not removendo and _plano.size() >= 1:
		for it in _plano:
			if it.motivo != "" or Fiacao.papel(it.nome) == "":
				continue
			var e := {"nome": it.nome, "minimo": it.minimo, "rot": it.rot, "area": Registro.area(it.nome), "fios": []}
			if Fiacao.papel(it.nome) == "poste":
				for alvo in Fiacao.alvos_do_poste(construtor.mapa, e):
					var o: Dictionary = construtor.mapa.estruturas[alvo]
					pares.append([Fiacao.ponto_fio(e, Fiacao.centro(o)), Fiacao.ponto_fio(o, Fiacao.centro(e))])
				anel = float(Registro.estruturas[it.nome].raio_fio)
				centro = Grade.ponto_mundo(Fiacao.centro(e), 0.05)
			else:
				var melhor := -1
				var md := INF
				for pid in construtor.mapa.estruturas:
					var p: Dictionary = construtor.mapa.estruturas[pid]
					if Fiacao.papel(p.nome) == "poste":
						var d := Fiacao.distancia(p, e)
						if d <= Fiacao.alcance(p, e) and d < md:
							md = d
							melhor = pid
				if melhor >= 0:
					var p: Dictionary = construtor.mapa.estruturas[melhor]
					pares.append([Fiacao.ponto_fio(p, Fiacao.centro(e)), Fiacao.ponto_fio(e, Fiacao.centro(p))])
	fantasma.mostrar_fios(pares, centro, anel)


func _dica_parada() -> String:
	if Time.get_ticks_msec() < _aviso_ate:
		return _aviso
	if removendo:
		return "Remover — %s numa peça ou árvore · arraste para um retângulo" % ("toque" if _por_toque else "clique")
	if peca == APLAINAR:
		if not construtor.mapa.tem_terraplenagem():
			return "Aplainar — construa uma Terraplenagem primeiro (aba Produção)"
		return "Aplainar — arraste uma área em qualquer lugar: vira patamar no nível de onde começou · 1 pedra por tile alterado"
	if peca == ESCAVAR:
		if not construtor.mapa.tem_terraplenagem():
			return "Escavar — construa uma Terraplenagem primeiro (aba Produção)"
		if construtor.pesquisa != null and not construtor.pesquisa.modo_liberado("escavar_canal"):
			return "Escavar — precisa pesquisar: Escavação de canal (botão Pesquisa)"
		return "Escavar — arraste um buraco ou canal 1 nível abaixo de onde começou · ligado a rio ou lago, enche d'água"
	if peca == "":
		return ""
	return _dica_peca()


func _dica_peca() -> String:
	if peca == APLAINAR or peca == ESCAVAR:
		return _dica_parada()
	var acao := "toque" if _por_toque else "clique"
	var t := "%s — %s para pôr" % [barra.rotulo(peca), acao]
	if _usa_pendente():
		t = "%s — %s no mapa para posicionar; depois Girar, Mover e Construir" % [barra.rotulo(peca), acao]
		if _pendente:
			t = "%s — arraste o holograma para mover · ✓ Construir" % barra.rotulo(peca)
	if construtor.pesquisa != null and construtor.pesquisa.peca_em_desenvolvimento(peca):
		return "%s — %s: ainda não está no jogo" % [barra.rotulo(peca), Tema.TEXTO_DESENVOLVIMENTO.to_lower()]
	if construtor.cobrar:
		if construtor.pesquisa != null and not construtor.pesquisa.peca_liberada(peca):
			return "%s — precisa pesquisar: %s (botão Pesquisa)" % [barra.rotulo(peca), construtor.pesquisa.quem_libera(peca)]
		var partes: Array[String] = []
		var c := Construtor.custo_de("esteira_reta" if peca == "esteira" else ("cano_reto" if peca == "cano" else peca))
		for k in c:
			partes.append("%d %s (tem %d)" % [c[k], Registro.itens.get(k, {}).get("nome", k).to_lower(), int(construtor.inventario.get(k, 0))])
		t += " · custo: " + ", ".join(partes)
	if Construtor.arrastavel(peca):
		t += " · arraste para traçar"
	return t + ("" if _por_toque else " · R gira")


func _dica_do_plano() -> void:
	if Time.get_ticks_msec() < _aviso_ate:
		barra.dica(_aviso, false)
		return
	if removendo:
		var n := _plano.size()
		barra.dica("Remover %d" % n if n > 0 else "Nada para remover aqui", false)
		return
	var c := Construtor.contar(_plano)
	var bloqueio := ""
	for it in _plano:
		if it.motivo != "":
			bloqueio = _motivo_legivel(it)
			break
	if bloqueio == "":
		var extra := "  ·  %d peças" % c.ok if c.ok > 1 else ""
		barra.dica(_dica_peca() + extra, false)
	elif c.ok > 0:
		barra.dica("%d ok · %d bloqueada(s): %s" % [c.ok, c.bloqueados, bloqueio], true)
	else:
		barra.dica(bloqueio, true)


func _motivo_legivel(it: Dictionary) -> String:
	if it.motivo == "sem_jazida":
		var nomes: Array[String] = []
		for j in Registro.estruturas.get(it.nome, {}).get("requer_jazida", []):
			nomes.append(Registro.menu.get("jazidas", {}).get(j, j))
		return "Precisa ficar sobre jazida de " + ", ".join(nomes)
	return barra.texto_motivo(it.motivo)


var _forca_grade := 0.0
var _grade_ligada := false


func _process(delta: float) -> void:
	# grade no chão enquanto constrói: em volta do cursor (ou do ponto olhado), acende e apaga suave
	_forca_grade = move_toward(_forca_grade, 1.0 if _ativo() else 0.0, delta * 4.0)
	if _forca_grade > 0.0 or _grade_ligada:
		_grade_ligada = _forca_grade > 0.0
		var c := Vector2(_cursor) + Vector2(0.5, 0.5) if _cursor_valido else Vector2(camera.alvo.x, -camera.alvo.z)
		if _pendente:
			c = Vector2(_tile_pend) + Vector2(0.5, 0.5)
		RenderingServer.global_shader_parameter_set("grade_construcao", Vector4(c.x, c.y, 16.0, _forca_grade))
	if not _segurar.is_empty() and not _segurar.feito:
		_segurar.t = float(_segurar.t) + delta
		if _segurar.t * 1000.0 >= SEGURAR_MS:
			_segurar.feito = true
			_clique_direito_toque()
	if _pendente:
		_atualizar()                                  # a barra de ações acompanha o holograma quando a câmera anda
	# o aviso ("Construído: 5") some sozinho
	if _aviso != "" and Time.get_ticks_msec() >= _aviso_ate:
		_aviso = ""
		_atualizar()
