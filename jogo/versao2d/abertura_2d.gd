class_name Abertura2D
extends Node2D
## Abertura do jogo novo na versão 2D (~7 s; tecla, clique ou toque pula): a cápsula de reentrada (sprite
## nucleo_queda) despenca do céu em brasa, bate no lugar do núcleo (poeira, tremor, estrondo) e a animação
## "chegada" do modelo toca do impacto em diante (pétalas cravam, monólito sobe); as linhas de sistema aparecem.
## No fim, o núcleo do jogo volta a ser desenhado.

signal terminou
const LINHAS := ["UNIDADE SEMEADORA 7 · CHEGADA CONFIRMADA", "DIRETRIZ: PROLIFERAR",
		"ERRO 0x1F · limite da diretriz não encontrado", "…prosseguindo."]
const T_QUEDA := 1.9
const Q_IMPACTO := 12               ## quadro do impacto na folha (animação "chegada": quadro 60 de 240 → 12 de 48)
const FPS := 12.0
const ALTURA := 560.0               ## px do sprite acima do chão onde a queda começa

var desenho: Desenho2D
var nucleo: Node3D
var _t := 0.0
var _m: Dictionary
var _spr := Sprite2D.new()
var _som := Sprite2D.new()
var _texto := Label.new()
var _camada := CanvasLayer.new()
var _bateu := false
var _fumaca := 0.0
var _fim := 0.0


func _ready() -> void:
	_m = Catalogo2D.meta("nucleo_queda")
	for s in [_som, _spr]:
		s.centered = false
		s.region_enabled = true
		s.offset = -Vector2(_m.ancora[0], _m.ancora[1])
	_spr.texture = Catalogo2D.folha("nucleo_queda")
	_som.texture = Catalogo2D.folha("nucleo_queda", "", true)
	desenho.sombras.add_child(_som)
	desenho.efeitos.add_child(_spr)
	_camada.layer = 20
	add_child(_camada)
	_texto.add_theme_font_size_override("font_size", 20)
	_texto.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
	_texto.add_theme_color_override("font_outline_color", Color.BLACK)
	_texto.add_theme_constant_override("outline_size", 6)
	_texto.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto.position = Vector2(-360, -150)
	_texto.size = Vector2(720, 120)
	_camada.add_child(_texto)
	_fim = T_QUEDA + float(int(_m.quadros) - Q_IMPACTO) / FPS + 1.4
	desenho.camera.alvo = Vector3(nucleo.global_position.x, 0.0, nucleo.global_position.z)
	desenho.ocultar = nucleo


func _input(e: InputEvent) -> void:
	if _t < 0.6:
		return
	if (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		_t = maxf(_t, _fim)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	var chao := Camera2DJogo.projetar(Vector3(nucleo.global_position.x, 0.0, nucleo.global_position.z))
	var q := 0
	var alto := 0.0
	if _t < T_QUEDA:
		var u := _t / T_QUEDA
		alto = ALTURA * (1.0 - u * u)                      # acelera até o chão
		_spr.modulate = Color(1.0, 0.55 + 0.45 * u, 0.35 + 0.65 * u)   # em brasa lá em cima
		_som.scale = Vector2.ONE * (0.4 + 0.6 * u)
		_fumaca += delta
		if _fumaca > 0.05:
			_fumaca = 0.0
			desenho.fumacinha(chao + Vector2(0, -alto - 20))
	else:
		if not _bateu:
			_bateu = true
			_spr.modulate = Color.WHITE
			_som.scale = Vector2.ONE
			desenho._sprite_efeito("explosao", chao, 3)
			desenho.tremer(0.45, 5.0)
			Som.tocar("explosao_grande", nucleo.global_position, 0.0)
		q = mini(Q_IMPACTO + int((_t - T_QUEDA) * FPS), int(_m.quadros) - 1)
		var linhas := int(clampf((_t - T_QUEDA - 0.4) / 0.9, 0.0, LINHAS.size()))
		var txt := "\n".join(LINHAS.slice(0, linhas))
		if linhas < LINHAS.size():
			var parcial := String(LINHAS[linhas])
			var n := int(fmod(_t - T_QUEDA - 0.4, 0.9) / 0.9 * parcial.length() * 1.6)
			txt += ("\n" if linhas > 0 else "") + parcial.substr(0, clampi(n, 0, parcial.length()))
		_texto.text = txt
	var r := Catalogo2D.regiao(_m, 0, q)
	for s in [_spr, _som]:
		s.region_rect = r
		s.position = chao
	_spr.offset = -Vector2(_m.ancora[0], _m.ancora[1]) - Vector2(0, alto)
	if _t >= _fim:
		_terminar()


func _terminar() -> void:
	set_process(false)
	desenho.ocultar = null
	_spr.queue_free()
	_som.queue_free()
	terminou.emit()
	queue_free()
