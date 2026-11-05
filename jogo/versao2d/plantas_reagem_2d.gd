class_name PlantasReagem2D
extends Node2D
## Patch fauna, fase 2 na versão 2D: o que as plantas largam, em pixel — folhas do outono (caindo por cima de tudo,
## no chão por baixo das coisas), galhos depois da tempestade, cogumelos depois da chuva. No mundo (escurece com a
## noite como o resto). Lê o DesenhoPlantasReagem (folhas) e a PlantasReagem (galhos, cogumelos).

var desenho: DesenhoPlantasReagem
var plantas: PlantasReagem
var _chao := Node2D.new()            ## folhas no chão, galhos, cogumelos (abaixo das construções e árvores)
var _ar := Node2D.new()              ## folhas caindo (acima)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chao.z_index = -11
	_ar.z_index = 12
	_chao.draw.connect(_desenhar_chao)
	_ar.draw.connect(_desenhar_ar)
	add_child(_chao)
	add_child(_ar)


func _process(_d: float) -> void:
	_chao.queue_redraw()
	_ar.queue_redraw()


static func _px(p: Vector3) -> Vector2:
	return Camera2DJogo.projetar(p).round()


func _desenhar_ar() -> void:
	if desenho == null:
		return
	for f in desenho.folhas:
		if not f.chao:
			var c: Color = f.cor
			_ar.draw_rect(Rect2(_px(f.pos), Vector2(1, 1) if absf(cos(float(f.giro))) < 0.5 else Vector2(2, 1)), c)


func _desenhar_chao() -> void:
	if desenho != null:
		for f in desenho.folhas:
			if f.chao and float(f.cor.a) > 0.3:
				var c: Color = f.cor
				_chao.draw_rect(Rect2(_px(f.pos), Vector2(2, 1)), Color(c.r, c.g, c.b))
	if plantas == null:
		return
	for g in plantas.galhos:
		var p: Vector2 = g.pos
		var some := plantas.some_galho(g)
		if some > 0.8:
			continue
		var meio := Grade.ponto_mundo(p)
		var dir := Vector3(cos(float(g.ang)), 0, -sin(float(g.ang))) * 0.45 * float(g.tam)
		var a := _px(meio - dir)
		var b := _px(meio + dir)
		var casca := DesenhoPlantasReagem.CASCA
		_chao.draw_line(a, b, casca, 1.0)
		_chao.draw_rect(Rect2(((a + b) * 0.5 + Vector2(1, -1)).round(), Vector2(1, 1)), casca)      # galhinho
	for c in plantas.cogumelos:
		var e := plantas.escala_cogumelo(c)
		if e < 0.45:
			continue
		var base := _px(Grade.ponto_mundo(c.pos))
		var cor: Color = DesenhoPlantasReagem.CORES_COGUMELO[int(c.cor) % 4]
		_chao.draw_rect(Rect2(base + Vector2(0, -1), Vector2(1, 1)), Color(0.86, 0.83, 0.74))          # pé
		_chao.draw_rect(Rect2(base + Vector2(-1, -2), Vector2(3 if e > 0.8 else 2, 1)), cor)         # chapéu
