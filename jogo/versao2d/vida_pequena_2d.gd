class_name VidaPequena2D
extends Node2D
## Patch fauna, fase 1 na versão 2D: desenha os mesmos pontos do DesenhoVidaPequena (vagalumes, insetos, olhos no
## mato) em pixel art — cada bicho é 1 pixel do mundo, o rastro são pixels mais fracos atrás e a luz do vagalume é
## uma cruz e um quadrado fraco em volta. Fica numa CanvasLayer própria (acima do escuro da noite, que é um
## CanvasModulate do mundo): a luz do vagalume não escurece com a noite. A camada copia o enquadramento do mundo.

const AMARELO := DesenhoVidaPequena.AMARELO
const OLHO := DesenhoVidaPequena.OLHO
const INSETO := DesenhoVidaPequena.INSETO
const MOSCA := DesenhoVidaPequena.MOSCA

var vida: DesenhoVidaPequena
var _brilho := Node2D.new()          ## soma de luz (vagalumes, olhos)
var _pontos := Node2D.new()          ## mosquitos (claros, mistura normal)


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_brilho.material = m
	_brilho.draw.connect(_desenhar_brilho)
	_pontos.draw.connect(_desenhar_pontos)
	add_child(_pontos)
	add_child(_brilho)


func _process(_d: float) -> void:
	_brilho.queue_redraw()
	_pontos.queue_redraw()


static func _px(p: Vector3) -> Vector2:
	return Camera2DJogo.projetar(p).round()


func _pixel(no: Node2D, p: Vector2, c: Color, lado := 1.0) -> void:
	no.draw_rect(Rect2(p - Vector2(lado, lado) * 0.5 + Vector2(0.5, 0.5) - Vector2(0.5, 0.5), Vector2(lado, lado)), c)


func _desenhar_brilho() -> void:
	if vida == null:
		return
	for v in vida.vagalumes:
		var p := _px(v.pos)
		var b := float(v.brilho)
		for i in 2:
			var br := float(v.b_rastro[i])
			if br > 0.05:
				_pixel(_brilho, _px(v.rastro[i]), Color(AMARELO, br * (0.4 - 0.18 * i)))
		if b > 0.05:
			_brilho.draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color(AMARELO, 0.10 * b))
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_pixel(_brilho, p + d, Color(AMARELO, 0.35 * b))
		_pixel(_brilho, p, Color(AMARELO, 0.35 + 0.65 * b))
	for o in vida.olhos:
		var b := float(o.brilho)
		if b > 0.0:
			var a := _px(o.a)
			var c := _px(o.b)
			if a == c:
				c = a + Vector2(2, 0)                       # de longe os dois olhos ainda são dois pixels
			_pixel(_brilho, a, Color(OLHO, b))
			_pixel(_brilho, c, Color(OLHO, b))


func _desenhar_pontos() -> void:
	if vida == null:
		return
	for ins in vida.insetos:
		if ins.has("enxame"):                              # fase 9: mosquito da nuvem do verão (a asa pega a luz)
			_pixel(_pontos, _px(ins.rastro[0]), Color(DesenhoVidaPequena.ENXAME, 0.3))
			_pixel(_pontos, _px(ins.pos), Color(DesenhoVidaPequena.ENXAME, 0.7))
			continue
		_pixel(_pontos, _px(ins.rastro[1]), Color(INSETO, 0.2))
		_pixel(_pontos, _px(ins.rastro[0]), Color(INSETO, 0.45))
		_pixel(_pontos, _px(ins.pos), Color(INSETO, 0.85))
	for mo in vida.moscas:                                 # fase 4: moscas em volta da carcaça (escuras)
		if not mo.pousada:
			_pixel(_pontos, _px(mo.rastro[0]), Color(MOSCA, 0.35))
		_pixel(_pontos, _px(mo.pos), Color(MOSCA, 0.95))
