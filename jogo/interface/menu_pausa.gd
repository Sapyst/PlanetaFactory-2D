class_name MenuPausa
extends CanvasLayer
## Pausa (Esc sem nada para cancelar, ou botão Menu): o jogo para; Continuar, Salvar agora, Configurações,
## Sair para o menu. Também mostra a tela de derrota quando o núcleo cai e a de vitória quando o foguete de
## proliferação parte (fim da campanha; dá para continuar jogando).
## Pausar para a árvore (lógica, animações, partículas) e zera Engine.time_scale: só isso congela o TIME dos shaders
## (lona da esteira, chama, grama), que a árvore parada não segura. Esc com o menu aberto volta ao jogo.

signal pediu_salvar

var pode_salvar := true
var _escala_antes := 1.0                 # Engine.time_scale de antes da pausa (os roteiros aceleram com "acelerar")
var _derrota := false
var _fundo: ColorRect
var _caixa: VBoxContainer
var _config: PainelConfig
var _titulo: Label
var _aviso: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.theme = Tema.criar()
	add_child(raiz)
	_fundo = ColorRect.new()
	_fundo.color = Color(0.03, 0.03, 0.05, 0.65)
	_fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(_fundo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)
	var painel := PanelContainer.new()
	centro.add_child(painel)
	var m := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + lado, Tema.n("pausa_margem"))
	painel.add_child(m)
	var pilha := VBoxContainer.new()
	m.add_child(pilha)
	_caixa = VBoxContainer.new()
	_caixa.add_theme_constant_override("separation", Tema.n("menu_sep"))
	pilha.add_child(_caixa)
	_config = PainelConfig.new()
	_config.visible = false
	_config.voltar.connect(func(): _config.visible = false; _caixa.visible = true)
	pilha.add_child(_config)
	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", Tema.n("f_pausa_titulo"))
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caixa.add_child(_titulo)
	_aviso = Label.new()
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
	_caixa.add_child(_aviso)


func abrir(derrota := false, vitoria := false) -> void:
	_derrota = derrota
	for c in _caixa.get_children():
		if c is Button:
			c.queue_free()
	_titulo.text = "O núcleo caiu" if derrota else ("A IA se proliferou" if vitoria else "Pausa")
	_titulo.add_theme_color_override("font_color", BarraConstrucao.COR_PERIGO if derrota else BarraConstrucao.COR_DESTAQUE)
	_aviso.text = ("As aranhas destruíram a base." if derrota else "") if pode_salvar or derrota else "A demonstração não é salva."
	if vitoria:
		_aviso.text = "O foguete de proliferação partiu levando a carga-semente: fim da campanha.\nAs melhorias infinitas continuam."
	if not derrota:
		_botao("Continuar", fechar)
		var s := _botao("Salvar agora", func(): pediu_salvar.emit(); _aviso.text = "Salvo.")
		s.disabled = not pode_salvar
	if Salvamento.existe() and pode_salvar:
		_botao("Carregar o último salvo", func(): _trocar("continuar"))
	if derrota:
		_botao("Novo jogo", func(): _trocar("novo"))
	_botao("Configurações", func(): _caixa.visible = false; _config.visible = true)
	_botao("Sair para o menu", func():
		if pode_salvar and not derrota: pediu_salvar.emit()
		_soltar()
		get_tree().change_scene_to_file("res://cenas/menu.tscn"))
	_caixa.visible = true
	_config.visible = false
	visible = true
	_parar()


func fechar() -> void:
	visible = false
	_soltar()


## Esc com o menu aberto: fecha as configurações se estiverem abertas, senão volta ao jogo (na derrota não há volta).
func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if _config.visible:
		_config.visible = false
		_caixa.visible = true
	elif not _derrota:
		fechar()


func _parar() -> void:
	if not get_tree().paused:
		_escala_antes = Engine.time_scale
	get_tree().paused = true
	Engine.time_scale = 0.0


func _soltar() -> void:
	get_tree().paused = false
	Engine.time_scale = _escala_antes


func _trocar(modo: String) -> void:
	Sessao.modo = modo
	_soltar()
	get_tree().change_scene_to_file("res://versao2d/mundo_2d.tscn")


func _botao(texto: String, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Tema.v("pausa_botao")
	b.pressed.connect(acao)
	_caixa.add_child(b)
	return b
