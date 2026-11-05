class_name Efeitos2D
extends Node2D
## Efeitos de combate da versão 2D, em pixel art desenhado por código:
##  - disparo: clarão na boca, faíscas para a frente, fumacinha, luz curta;
##  - projétil: traçante (bala), raio (energia), arco elétrico (carregada), foguete com fumaça e chama, granada em arco
##    alto (artilharia), gosma ácida em arco pingando (larva);
##  - impacto: faíscas e lascas (metal, carapaça), poeira e torrões (chão), respingo de ácido (gotas em arco que viram
##    poça), explosão (clarão, bola de fogo, fumaça, terra voando, anel de choque, chão queimado), luz.
## Partículas com ALTURA: andam no chão (x, y) e sobem/caem (h, em pixels de tela), quicam e pousam — é o que faz a
## gota cair em arco e a fumaça subir. Três camadas: chão (poça, queimado), normal (fumaça, lascas, gotas) e brilho
## (soma de luz: faíscas, traçantes, clarões). Unidade: pixel do sprite (Camera2DJogo.projetar).

const G := 520.0                          ## gravidade (px/s²)
const PX_M := 1.0 / (4.6 / 160.0)         ## pixels por metro
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var som: Callable                         ## (opcional) func(nome: String, pos: Vector2)
var luz_tex: Texture2D
var _chao := Node2D.new()
var _normal := Node2D.new()
var _brilho := Node2D.new()
var _parts: Array = []
var _linhas: Array = []
var _proj: Array = []
var _marcas: Array = []
var _luzes: Array = []
var _rng := RandomNumberGenerator.new()
var _cache_disco := {}                    ## (raio, nível de alfa) → textura de disco pontilhado (branco; a cor vem do modulate)
var _folhas := {}                         ## nome → [meta, textura] das folhas de efeito (explosão, clarão)
var _anims: Array = []                    ## {nome, p, h, t, escala, camada}: folha de efeito tocando


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chao.z_as_relative = false
	_chao.z_index = -12
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_brilho.material = add
	for c in [_chao, _normal, _brilho]:
		add_child(c)
	_chao.draw.connect(_desenhar_chao)
	_normal.draw.connect(func(): _desenhar(_normal, 0))
	_brilho.draw.connect(func(): _desenhar(_brilho, 1))
	if luz_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		luz_tex = t


## Mundo (Godot) → (ponto no chão em pixels, altura em pixels de tela).
static func no_chao(p: Vector3) -> Array:
	return [Camera2DJogo.projetar(Vector3(p.x, 0.0, p.z)), p.y * cos(Camera2DJogo.ELEVACAO) * PX_M]


# ================================================================== API
## Um tiro inteiro: disparo na boca, o projétil e o impacto quando ele chega. `dur` = voo (projétil lento).
func disparar(arma: String, de: Vector3, para: Vector3, alvo := "chao", dur := 0.0, impacta := true) -> void:
	var a := no_chao(de)
	var b := no_chao(para)
	var p0: Vector2 = a[0]
	var h0: float = a[1]
	var p1: Vector2 = b[0]
	var h1: float = b[1]
	var dir := (p1 - p0).normalized()
	p0 += dir * 1.5                                      # nasce logo à frente da boca, nunca dentro do cano
	var n_antes := _proj.size()
	_disparar(arma, p0, h0, p1, h1, dir, para, alvo, dur)
	for k in range(n_antes, _proj.size()):
		_proj[k]["impacta"] = impacta


func _disparar(arma: String, p0: Vector2, h0: float, p1: Vector2, h1: float, dir: Vector2, para: Vector3, alvo: String, dur: float) -> void:
	match arma:
		"metralhadora", "perfurante", "drone":
			var forte := arma == "perfurante"
			var cor := Color(1.0, 0.85, 0.45) if arma != "drone" else Color(1.0, 0.45, 0.3)
			_anim("clarao", p0, h0, 1, 1)
			_clarao(p0, h0, 6.0 if forte else 4.5, cor, 0.06)
			_faiscas(p0, h0, dir, 7 if forte else 4, cor, 200.0, 0.45, 0.14)
			_fumaca(p0, h0, 4 if forte else 3, Color(0.5, 0.47, 0.44, 0.55), 3.0, 0.6)
			_luz(p0 - Vector2(0, h0), cor, 0.6 if forte else 0.45, 0.45, 0.07)
			_proj.append({"tipo": "bala", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0,
					"dur": maxf(0.04, p0.distance_to(p1) / 900.0), "cor": cor, "arma": arma, "alvo": alvo, "larg": 2.0 if forte else 1.0})
			_capsula(p0 - dir * (6.0 if arma != "drone" else 2.0), h0 - 3.0, dir, 1.0 if arma != "drone" else 0.6)
		"carregada":
			_anim("clarao", p0, h0, 1, 1)
			_clarao(p0, h0, 5.0, Color(0.6, 0.85, 1.0), 0.08)
			_faiscas(p0, h0, dir, 5, Color(0.6, 0.85, 1.0), 180.0, 0.6, 0.12)
			_luz(p0 - Vector2(0, h0), Color(0.5, 0.75, 1.0), 0.6, 0.5, 0.08)
			_proj.append({"tipo": "bala", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0, "dur": maxf(0.05, p0.distance_to(p1) / 800.0),
					"cor": Color(0.65, 0.85, 1.0), "arma": arma, "alvo": alvo, "larg": 1.0, "eletrico": true})
			_capsula(p0 - dir * 6.0, h0 - 3.0, dir, 1.0)
		"energia":                                       # torre padrão com energia: pulso curto, fraco
			_clarao(p0, h0, 4.5, Color(0.5, 0.9, 1.0), 0.08)
			_faiscas(p0, h0, dir, 3, Color(0.5, 0.9, 1.0), 140.0, 0.4, 0.1)
			_luz(p0 - Vector2(0, h0), Color(0.5, 0.85, 1.0), 0.45, 0.4, 0.08)
			_proj.append({"tipo": "pulso", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0,
					"dur": maxf(0.06, p0.distance_to(p1) / 650.0), "arma": arma, "alvo": alvo})
		"laser":                                         # laser: feixe forte, contínuo enquanto dura
			_clarao(p0, h0, 8.0, Color(0.55, 0.95, 1.0), 0.12)
			_linhas.append({"a": p0 - Vector2(0, h0), "b": p1 - Vector2(0, h1), "t": 0.0, "vida": 0.2, "cor": Color(0.55, 0.95, 1.0),
					"larg": 3.0, "tremor": 2.0})
			_linhas.append({"a": p0 - Vector2(0, h0), "b": p1 - Vector2(0, h1), "t": 0.0, "vida": 0.12, "cor": Color(0.9, 1.0, 1.0),
					"larg": 1.0, "tremor": 0.6})
			_luz(p0 - Vector2(0, h0), Color(0.5, 0.9, 1.0), 0.8, 0.6, 0.16)
			_luz(p1 - Vector2(0, h1), Color(0.5, 0.9, 1.0), 0.8, 0.6, 0.16)
			impacto("laser", para, alvo)
		"reparo":                                        # drone de reparo: feixe vermelho de solda e faíscas no ponto
			_linhas.append({"a": p0 - Vector2(0, h0), "b": p1 - Vector2(0, h1), "t": 0.0, "vida": maxf(dur, 0.6), "cor": Color(1.0, 0.25, 0.15),
					"larg": 1.0, "tremor": 0.8, "quebra": 3})
			_luz(p1 - Vector2(0, h1), Color(1.0, 0.55, 0.2), 0.6, 0.45, maxf(dur, 0.6))
			for k in int(maxf(dur, 0.6) / 0.05):
				get_tree().create_timer(k * 0.05).timeout.connect(func():
					_faiscas(p1, h1, Vector2.ZERO, 2, Color(1.0, 0.8, 0.4), 120.0, 1.0, 0.25)
					_clarao(p1, h1, 2.5, Color(1.0, 0.9, 0.6), 0.04))
		"foguete", "enxame":
			_anim("clarao", p0, h0, 1, 1)
			_clarao(p0, h0, 6.0, Color(1.0, 0.7, 0.3), 0.1)
			_fumaca(p0, h0, 12, Color(0.6, 0.57, 0.54, 0.75), 5.0, 1.2)
			_luz(p0 - Vector2(0, h0), Color(1.0, 0.6, 0.25), 0.7, 0.6, 0.14)
			_proj.append({"tipo": "foguete", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0,
					"dur": dur if dur > 0.0 else maxf(0.25, p0.distance_to(p1) / 360.0), "arma": arma, "alvo": alvo,
					"arco": p0.distance_to(p1) * 0.12, "solta": 0.0})
		"artilharia":
			_anim("clarao", p0, h0, 2, 1)
			_clarao(p0, h0, 10.0, Color(1.0, 0.75, 0.35), 0.12)
			_fumaca(p0, h0, 22, Color(0.62, 0.59, 0.55, 0.85), 7.0, 1.8)
			_faiscas(p0, h0, dir, 10, Color(1.0, 0.7, 0.3), 220.0, 0.6, 0.25)
			_luz(p0 - Vector2(0, h0), Color(1.0, 0.65, 0.3), 1.0, 0.9, 0.18)
			_proj.append({"tipo": "granada", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0,
					"dur": dur if dur > 0.0 else maxf(0.6, p0.distance_to(p1) / 260.0), "arma": arma, "alvo": alvo,
					"arco": maxf(60.0, p0.distance_to(p1) * 0.45), "solta": 0.0})
		"cuspe":
			var verde := Color(0.6, 0.95, 0.15)
			_clarao(p0, h0, 4.5, verde, 0.1)
			_luz(p0 - Vector2(0, h0), Color(0.55, 0.95, 0.2), 0.6, 0.5, 0.2)
			_gotas(p0, h0, dir, 12, verde, 130.0, 0.6, 70.0)                 # o jato espirra na saída
			_fumaca(p0, h0, 5, Color(0.55, 0.68, 0.32, 0.5), 3.0, 0.8)
			_proj.append({"tipo": "gosma", "a": p0, "ha": h0, "b": p1, "hb": h1, "t": 0.0,
					"dur": dur if dur > 0.0 else maxf(0.35, p0.distance_to(p1) / 300.0), "arma": arma, "alvo": alvo,
					"arco": maxf(26.0, p0.distance_to(p1) * 0.3), "solta": 0.0})


## Impacto no ponto (mundo). alvo: "aranha", "larva", "estrutura" ou "chao".
func impacto(arma: String, onde: Vector3, alvo := "chao") -> void:
	var a := no_chao(onde)
	var p: Vector2 = a[0]
	var h: float = a[1]
	match arma:
		"foguete", "enxame", "artilharia":
			explosao(onde, 1.4 if arma == "artilharia" else (0.9 if arma == "foguete" else 0.6))
			return
		"cuspe":
			_respingo(p, h)
			return
	var metal := alvo in ["aranha", "estrutura"]
	var eletrico := arma == "carregada"
	var energia := arma == "energia" or arma == "laser"
	var cor := Color(1.0, 0.8, 0.4)
	if eletrico or energia:
		cor = Color(0.55, 0.9, 1.0)
	if metal or eletrico or energia:
		var forte := 1.6 if arma in ["perfurante", "laser"] else (0.6 if arma in ["energia", "drone"] else 1.0)
		_clarao(p, h, 4.0 * forte, cor, 0.06)
		_faiscas(p, h, Vector2.ZERO, int((6 if alvo == "aranha" else 10) * forte), cor, 210.0, 1.0, 0.3)
		_lascas(p, h, int(3 * forte) + 1, Color(0.42, 0.42, 0.44) if alvo == "aranha" else Color(0.35, 0.33, 0.3), true)
		if alvo == "aranha":                              # biomáquina: sangra (vermelho-escuro) além das lascas de metal
			_sangue(p, h, Color(0.42, 0.03, 0.03), Color(0.24, 0.02, 0.02), forte)
		_fumaca(p, h, 2, Color(0.4, 0.38, 0.36, 0.45), 2.5, 0.5)
		_luz(p - Vector2(0, h), cor, 0.5, 0.4, 0.08)
		if eletrico:
			for k in 3:
				var fim := p - Vector2(0, h) + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-12, 6))
				_linhas.append({"a": p - Vector2(0, h), "b": fim, "t": 0.0, "vida": 0.14, "cor": cor, "larg": 1.0, "tremor": 2.5, "quebra": 4})
	elif alvo == "larva":                                 # verme: sangue verde e lasca de carapaça
		_clarao(p, h, 3.0, Color(0.7, 0.9, 0.4), 0.05)
		_sangue(p, h, Color(0.42, 0.62, 0.08), Color(0.2, 0.34, 0.04), 1.0)
		_lascas(p, h, 2, Color(0.1, 0.08, 0.06))
	else:                                                                                  # chão: terra e poeira
		_poeira(p, 7, Color(0.45, 0.38, 0.29, 0.7))
		_lascas(p, 0.0, 5, Color(0.3, 0.24, 0.17))
		_marca(p, 3.0, Color(0.12, 0.1, 0.08, 0.7), 4.0, "queimado")


## Arco elétrico (salto da bala carregada de uma aranha para outra).
func arco(de: Vector3, para: Vector3) -> void:
	var a := no_chao(de)
	var b := no_chao(para)
	var cor := Color(0.6, 0.9, 1.0)
	_linhas.append({"a": (a[0] as Vector2) - Vector2(0, a[1]), "b": (b[0] as Vector2) - Vector2(0, b[1]), "t": 0.0, "vida": 0.16, "cor": cor, "larg": 1.0, "tremor": 2.5, "quebra": 5})
	_faiscas(b[0], b[1], Vector2.ZERO, 6, cor, 160.0, 1.0, 0.25)
	_luz((b[0] as Vector2) - Vector2(0, b[1]), cor, 0.5, 0.4, 0.1)


## Bicho morrendo: aranha (biomáquina) solta sangue, lascas de metal e faíscas; larva, gosma verde.
func morte(onde: Vector3, especie := "aranha") -> void:
	var a := no_chao(onde)
	var p: Vector2 = a[0]
	var h: float = maxf(a[1], 6.0)
	if especie == "larva":
		_sangue(p, h, Color(0.42, 0.62, 0.08), Color(0.2, 0.34, 0.04), 2.5)
		_fumaca(p, h, 5, Color(0.5, 0.62, 0.3, 0.5), 3.5, 1.4)
		_marca(p, 10.0, Color(0.25, 0.4, 0.05, 0.9), 10.0, "acido")
		return
	_sangue(p, h, Color(0.42, 0.03, 0.03), Color(0.24, 0.02, 0.02), 2.5)
	_lascas(p, h, 8, Color(0.42, 0.42, 0.44), true)
	_faiscas(p, h, Vector2.ZERO, 14, Color(1.0, 0.75, 0.35), 200.0, 1.0, 0.4)
	_fumaca(p, h, 6, Color(0.3, 0.28, 0.27, 0.7), 4.0, 1.5)
	_clarao(p, h, 6.0, Color(1.0, 0.8, 0.4), 0.08)
	_marca(p, 9.0, Color(0.24, 0.02, 0.02, 0.9), 12.0, "sangue")


func explosao(onde: Vector3, forca := 1.0) -> void:
	var a := no_chao(onde)
	var p: Vector2 = a[0]
	var h: float = maxf(a[1], 2.0)
	var r := 14.0 * forca
	_anim("explosao", p, 0.0, clampi(int(round(forca * 1.6)), 1, 3), 0)
	_clarao(p, h, r * 1.4, Color(1.0, 0.85, 0.5), 0.14)
	_luz(p - Vector2(0, h), Color(1.0, 0.6, 0.25), 1.4 * forca, 0.8 + 0.6 * forca, 0.4)
	for k in int(18 * forca):                                                              # bola de fogo subindo
		var ang := _rng.randf() * TAU
		var v := Vector2.from_angle(ang) * _rng.randf_range(15, 60) * forca
		_parts.append(_part(p, h + _rng.randf_range(0, 8), v, _rng.randf_range(15, 70) * forca, -0.1, 3.0, 0.0,
				_rng.randf_range(0.3, 0.6), Color(1.0, 0.95, 0.65), Color(0.8, 0.2, 0.04, 0.0), _rng.randf_range(4.0, 8.0) * forca, 2.0, "q", 1))
	_fumaca(p, h + 4.0, int(22 * forca), Color(0.2, 0.18, 0.17, 0.9), 8.0 * forca, 2.2 + forca)
	_faiscas(p, h, Vector2.ZERO, int(20 * forca), Color(1.0, 0.7, 0.3), 260.0 * forca, 1.0, 0.5)
	_lascas(p, h, int(16 * forca), Color(0.22, 0.17, 0.12))                                   # terra voando
	_poeira(p, int(10 * forca), Color(0.42, 0.36, 0.28, 0.7))
	_linhas.append({"anel": true, "c": p, "t": 0.0, "vida": 0.32, "raio": r * 2.6, "cor": Color(1.0, 0.92, 0.75, 0.8)})
	_marca(p, r * 1.2, Color(0.05, 0.045, 0.04, 0.9), 14.0, "queimado")
	if som.is_valid():
		som.call("explosao_grande" if forca > 1.2 else "explosao", p)


# ================================================================== emissores
func _part(p: Vector2, h: float, v: Vector2, vh: float, g: float, arrasto: float, quica: float, vida: float,
		c0: Color, c1: Color, tam0: float, tam1: float, forma: String, camada: int) -> Dictionary:
	return {"p": p, "h": h, "v": v, "vh": vh, "g": g, "arr": arrasto, "quica": quica, "t": 0.0, "vida": vida,
			"c0": c0, "c1": c1, "tam0": tam0, "tam1": tam1, "forma": forma, "cam": camada}


func _faiscas(p: Vector2, h: float, dir: Vector2, n: int, cor: Color, vel: float, espalha: float, vida: float) -> void:
	for k in n:
		var ang := (dir.angle() if dir != Vector2.ZERO else _rng.randf() * TAU) + _rng.randf_range(-PI, PI) * espalha * 0.5
		var v := Vector2.from_angle(ang) * vel * _rng.randf_range(0.5, 1.2)
		_parts.append(_part(p, h, v, _rng.randf_range(20, 110), 1.0, 2.0, 0.4, vida * _rng.randf_range(0.6, 1.3),
				Color(1, 1, 0.9), Color(cor.r, cor.g * 0.6, cor.b * 0.4, 0.0), 4.0, 1.5, "r", 1))


func _fumaca(p: Vector2, h: float, n: int, cor: Color, tam: float, vida: float) -> void:
	for k in n:
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4, 18) * tam * 0.3
		var c1 := Color(cor.r * 1.2, cor.g * 1.2, cor.b * 1.2, 0.0)
		_parts.append(_part(p + Vector2(_rng.randf_range(-2, 2), 0), h + _rng.randf_range(0, 3), v, _rng.randf_range(8, 22),
				-0.02, 1.5, 0.0, vida * _rng.randf_range(0.6, 1.2), cor, c1, tam * 0.6, tam * 1.8, "f", 0))


func _poeira(p: Vector2, n: int, cor: Color) -> void:
	for k in n:
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10, 30)
		_parts.append(_part(p, 1.0, v, _rng.randf_range(5, 15), -0.01, 2.5, 0.0, _rng.randf_range(0.5, 0.9),
				cor, Color(cor.r, cor.g, cor.b, 0.0), 2.0, 4.5, "f", 0))


func _lascas(p: Vector2, h: float, n: int, cor: Color, metal := false) -> void:
	for k in n:
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(25, 70)
		var l := _part(p, h, v, _rng.randf_range(60, 150), 1.0, 0.6, 0.35, _rng.randf_range(0.9, 1.6) if metal else _rng.randf_range(0.7, 1.2),
				cor, Color(cor.r, cor.g, cor.b, 0.0), _rng.randf_range(1.0, 2.5), 1.5 if metal else 1.0, "m" if metal else "q", 0)
		_parts.append(l)


## Sangue: gotas em arco que viram respingo no chão, e uma mancha onde bateu (cor do bicho: aranha vermelha, verme verde).
func _sangue(p: Vector2, h: float, cor: Color, escuro: Color, forca: float) -> void:
	for k in int(8 * forca) + 3:
		var ang := _rng.randf() * TAU
		var g := _part(p, h, Vector2.from_angle(ang) * _rng.randf_range(20, 75), _rng.randf_range(30, 90), 1.0, 0.5, 0.0, 1.5,
				cor, escuro, 2.0, 1.0, "g", 0)
		g["pinga"] = true
		g["mancha"] = escuro
		_parts.append(g)
	_marca(p, 3.0 + 2.5 * forca, Color(escuro.r, escuro.g, escuro.b, 0.9), 6.0, "sangue")


## Gotas de líquido: saem em arco, caem e, ao tocar o chão, viram uma manchinha (poça miúda).
func _gotas(p: Vector2, h: float, dir: Vector2, n: int, cor: Color, vel: float, espalha: float, sobe: float) -> void:
	for k in n:
		var ang := (dir.angle() if dir != Vector2.ZERO else _rng.randf() * TAU) + _rng.randf_range(-PI, PI) * espalha * 0.5
		var v := Vector2.from_angle(ang) * vel * _rng.randf_range(0.4, 1.1)
		var g := _part(p, h, v, _rng.randf_range(sobe * 0.4, sobe), 1.0, 0.4, 0.0, 1.5, cor, cor, 2.0, 1.0, "g", 0)
		g["pinga"] = true
		_parts.append(g)


## Cápsula (estojo) saindo pela lateral da arma: gira no ar (1×2 ↔ 2×1), quica e fica no chão um tempo.
func _capsula(p: Vector2, h: float, dir: Vector2, escala: float) -> void:
	var lado := Vector2(-dir.y, dir.x) * (1.0 if _rng.randf() < 0.85 else -1.0)
	var v := (lado * _rng.randf_range(35, 60) - dir * _rng.randf_range(5, 20)) * escala
	var c := _part(p, maxf(h, 2.0), v, _rng.randf_range(70, 110) * escala, 1.0, 1.5, 0.35, _rng.randf_range(2.5, 4.0),
			Color(0.82, 0.64, 0.26), Color(0.55, 0.42, 0.18), 1.0, 1.0, "c", 0)
	_parts.append(c)


func _respingo(p: Vector2, h: float) -> void:
	var verde := Color(0.62, 0.95, 0.15)
	_clarao(p, h, 6.0, verde, 0.09)
	_luz(p - Vector2(0, h), Color(0.5, 0.95, 0.2), 0.7, 0.5, 0.35)
	_gotas(p, h, Vector2.ZERO, 26, verde, 95.0, 2.0, 120.0)                        # coroa de gotas
	_gotas(p, h, Vector2.ZERO, 10, Color(0.4, 0.6, 0.1), 45.0, 2.0, 70.0)
	_fumaca(p, 1.0, 10, Color(0.6, 0.72, 0.35, 0.55), 4.5, 2.0)                    # o ácido chiando
	_marca(p, 12.0, Color(0.32, 0.52, 0.06, 0.95), 8.0, "acido")
	if som.is_valid():
		som.call("acido_respingo", p)


## Patch fauna, fase 9: o peixe saindo ou caindo na água — gotas claras e um anel que se espalha (sem clarão nem
## marca no chão).
func respingo_agua(onde: Vector3, forca := 1.0) -> void:
	var a := no_chao(onde)
	var p: Vector2 = a[0]
	var h: float = a[1]
	var agua := Color(0.78, 0.86, 0.9, 0.85)
	_gotas(p, h, Vector2.ZERO, int(round(12 * forca)), agua, 28.0 * forca, 2.0, 45.0 * forca)
	_linhas.append({"anel": true, "c": p, "t": 0.0, "vida": 1.0, "raio": 9.0 * forca, "cor": Color(0.8, 0.88, 0.92, 0.6)})


func _clarao(p: Vector2, h: float, raio: float, cor: Color, vida: float) -> void:
	_parts.append(_part(p, h, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, vida, Color(1, 1, 0.95), Color(cor.r, cor.g, cor.b, 0.0),
			raio, raio * 0.4, "d", 1))


func _marca(p: Vector2, raio: float, cor: Color, vida: float, tipo: String) -> void:
	var bolhas := []
	for k in 5:
		bolhas.append([Vector2(_rng.randf_range(-raio, raio), _rng.randf_range(-raio, raio) * 0.6) * 0.7, _rng.randf() * 2.0])
	var ri := int(ceil(raio)) + 2
	var img := Image.create(ri * 2 + 1, ri * 2 + 1, false, Image.FORMAT_RGBA8)
	for k in 6:                                                    # mancha irregular: discos achatados somados
		var o := Vector2(_rng.randf_range(-raio, raio), _rng.randf_range(-raio, raio) * 0.55) * 0.55
		var rr := raio * _rng.randf_range(0.45, 0.8)
		for y in img.get_height():
			for x in img.get_width():
				var d := sqrt(pow(x - ri - o.x, 2.0) + pow(y - ri - o.y, 2.0) / 0.3) / maxf(rr, 0.5)
				var limiar: float = (float(BAYER[(x % 4) + 4 * (y % 4)]) + 0.5) / 16.0
				if d <= 1.0 and cor.a * (1.25 - d) > limiar:
					img.set_pixel(x, y, Color(cor.r, cor.g, cor.b, 1.0))
	_marcas.append({"p": p, "r": raio, "cor": cor, "t": 0.0, "vida": vida, "tipo": tipo, "bolhas": bolhas,
			"tex": ImageTexture.create_from_image(img), "ri": ri})


## Folha de pixel art (assets2d/efeitos: clarao, explosao) tocando uma vez no ponto; camada 0 normal, 1 brilho.
func _anim(nome: String, p: Vector2, h: float, escala: int, camada: int) -> void:
	if not _folhas.has(nome):
		var m = JSON.parse_string(FileAccess.get_file_as_string("res://assets2d/efeitos/%s.json" % nome))
		_folhas[nome] = [m, load("res://assets2d/efeitos/%s.png" % nome)] if m != null else []
	if (_folhas[nome] as Array).is_empty():
		return
	_anims.append({"nome": nome, "p": p, "h": h, "t": 0.0, "escala": escala, "cam": camada})


func _luz(p: Vector2, cor: Color, energia: float, escala: float, vida: float) -> void:
	var l := PointLight2D.new()
	l.texture = luz_tex
	l.color = cor
	l.energy = energia
	l.texture_scale = escala
	l.position = p
	add_child(l)
	_luzes.append({"no": l, "t": 0.0, "vida": vida, "e": energia})


# ================================================================== passo
func _process(delta: float) -> void:
	_passo_projeteis(delta)
	_passo_particulas(delta)
	for i in range(_anims.size() - 1, -1, -1):
		_anims[i].t += delta
		var m: Dictionary = _folhas[_anims[i].nome][0]
		if _anims[i].t >= float(m.quadros) / float(m.fps):
			_anims.remove_at(i)
	for i in range(_linhas.size() - 1, -1, -1):
		_linhas[i].t += delta
		if _linhas[i].t >= _linhas[i].vida:
			_linhas.remove_at(i)
	for i in range(_marcas.size() - 1, -1, -1):
		_marcas[i].t += delta
		if _marcas[i].t >= _marcas[i].vida:
			_marcas.remove_at(i)
	for i in range(_luzes.size() - 1, -1, -1):
		var l: Dictionary = _luzes[i]
		l.t += delta
		var k: float = 1.0 - l.t / l.vida
		(l.no as PointLight2D).energy = l.e * maxf(k, 0.0) * maxf(k, 0.0)
		if k <= 0.0:
			(l.no as Node).queue_free()
			_luzes.remove_at(i)
	_chao.queue_redraw()
	_normal.queue_redraw()
	_brilho.queue_redraw()


func _passo_projeteis(delta: float) -> void:
	for i in range(_proj.size() - 1, -1, -1):
		var pr: Dictionary = _proj[i]
		pr.t += delta
		var u: float = minf(pr.t / pr.dur, 1.0)
		var pos: Vector2 = (pr.a as Vector2).lerp(pr.b, u)
		var h: float = lerpf(pr.ha, pr.hb, u) + float(pr.get("arco", 0.0)) * 4.0 * u * (1.0 - u)
		pr["pos"] = pos
		pr["h"] = h
		pr.solta = float(pr.get("solta", 0.0)) - delta
		match String(pr.tipo):
			"foguete":
				if pr.solta <= 0.0:
					pr.solta = 0.02
					_parts.append(_part(pos, h, Vector2.ZERO, 6.0, -0.02, 1.0, 0.0, _rng.randf_range(0.5, 0.9),
							Color(0.62, 0.6, 0.58, 0.7), Color(0.7, 0.68, 0.66, 0.0), 2.5, 7.0, "f", 0))
					_parts.append(_part(pos, h, Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, 0.08, Color(1, 0.9, 0.5), Color(1, 0.4, 0.1, 0), 2.0, 1.0, "q", 1))
			"granada":
				if pr.solta <= 0.0:
					pr.solta = 0.035
					_parts.append(_part(pos, h, Vector2.ZERO, 2.0, -0.01, 1.0, 0.0, 0.5, Color(0.5, 0.48, 0.46, 0.4), Color(0.6, 0.58, 0.56, 0.0), 1.0, 2.5, "f", 0))
			"gosma":
				if pr.solta <= 0.0:
					pr.solta = 0.045
					var g := _part(pos, h, Vector2.ZERO, -10.0, 1.0, 0.0, 0.0, 1.2, Color(0.55, 0.85, 0.12), Color(0.55, 0.85, 0.12), 1.0, 1.0, "g", 0)
					g["pinga"] = true
					_parts.append(g)
					_parts.append(_part(pos, h, Vector2.ZERO, 8.0, -0.02, 1.0, 0.0, 0.4, Color(0.5, 0.65, 0.3, 0.35), Color(0.5, 0.65, 0.3, 0.0), 1.0, 2.5, "f", 0))
		if u >= 1.0:
			_proj.remove_at(i)
			if pr.get("impacta", true) == false:
				continue
			impacto_tela(pr.arma, pr.b, pr.hb, pr.alvo)


## Impacto já em coordenadas de tela (fim do projétil).
func impacto_tela(arma: String, p: Vector2, h: float, alvo: String) -> void:
	var m := 1.0 / PX_M
	var w := Vector3(p.x * m, h / cos(Camera2DJogo.ELEVACAO) * m, 0.0)
	# volta do pixel para o mundo: z da projeção sem altura (y_tela = z·sin)
	w.z = p.y * m / sin(Camera2DJogo.ELEVACAO)
	impacto(arma, w, alvo)


func _passo_particulas(delta: float) -> void:
	for i in range(_parts.size() - 1, -1, -1):
		var q: Dictionary = _parts[i]
		q.t += delta
		if q.t >= q.vida:
			_parts.remove_at(i)
			continue
		q.v = (q.v as Vector2) * maxf(0.0, 1.0 - float(q.arr) * delta)
		q.p = (q.p as Vector2) + (q.v as Vector2) * delta
		q.vh = float(q.vh) - G * float(q.g) * delta
		q.h = float(q.h) + float(q.vh) * delta
		if float(q.h) < 0.0:
			if q.has("pinga"):                                   # gota tocou o chão: vira manchinha e some
				var cm: Color = q.get("mancha", Color(0.36, 0.55, 0.08))
				_marca(q.p, _rng.randf_range(1.5, 3.0), Color(cm.r, cm.g, cm.b, 0.9), _rng.randf_range(2.5, 5.0), "pingo")
				_parts.remove_at(i)
				continue
			q.h = 0.0
			q.vh = -float(q.vh) * float(q.quica)
			q.v = (q.v as Vector2) * 0.5


# ================================================================== desenho
func _desenhar(no: Node2D, camada: int) -> void:
	for a in _anims:
		if int(a.cam) != camada:
			continue
		var m: Dictionary = _folhas[a.nome][0]
		var tex: Texture2D = _folhas[a.nome][1]
		var q := mini(int(float(a.t) * float(m.fps)), int(m.quadros) - 1)
		var w: float = m.quadro[0]
		var hh: float = m.quadro[1]
		var e := float(a.escala)
		var org: Vector2 = (a.p as Vector2) - Vector2(0, a.h) - Vector2(m.ancora[0], m.ancora[1]) * e
		no.draw_texture_rect_region(tex, Rect2(org.round(), Vector2(w, hh) * e), Rect2(q * w, 0, w, hh))
	for q in _parts:
		if int(q.cam) != camada:
			continue
		var u: float = float(q.t) / float(q.vida)
		var cor: Color = (q.c0 as Color).lerp(q.c1, u)
		var tam: float = lerpf(q.tam0, q.tam1, u)
		var p: Vector2 = ((q.p as Vector2) - Vector2(0, q.h)).round()
		match String(q.forma):
			"q":
				var s := maxf(1.0, round(tam))
				no.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), cor)
			"r":                                                  # faísca: risco ao longo da velocidade
				var v: Vector2 = (q.v as Vector2) - Vector2(0, q.vh)
				var fim := p - v.normalized() * tam * 1.5
				no.draw_line(p, fim.round(), cor, 1.0)
			"m":                                                  # lasca de metal: pisca de brilho enquanto gira
				var s2 := maxf(1.0, round(tam))
				var brilha := int(float(q.t) * 20.0 + float(q.vh)) % 3 == 0
				no.draw_rect(Rect2(p, Vector2(s2, 1)), cor.lightened(0.5) if brilha else cor)
			"c":                                                  # cápsula: gira enquanto voa, deita no chão
				var deitada := float(q.h) <= 0.01 or int(float(q.t) * 18.0) % 2 == 0
				no.draw_rect(Rect2(p, Vector2(2, 1) if deitada else Vector2(1, 2)), cor)
			"g":                                                  # gota: 1×2 com brilho
				no.draw_rect(Rect2(p, Vector2(1, 2)), cor)
				no.draw_rect(Rect2(p, Vector2(1, 1)), cor.lightened(0.4))
			"f":                                                  # fumaça: disco pontilhado (pixel art, sem borrão)
				var r := clampi(int(round(tam)), 1, 24)
				var nivel := clampi(int(round(cor.a * 8.0)), 0, 8)
				if nivel > 0:
					no.draw_texture(_disco(r, nivel), p - Vector2(r, r), Color(cor.r, cor.g, cor.b, 1.0))
			"d":                                                  # clarão: disco cheio
				no.draw_circle(p, maxf(1.0, tam), cor)
	if camada == 1 or camada == 0:
		for l in _linhas:
			var u: float = float(l.t) / float(l.vida)
			if l.has("anel"):
				if camada == 1:
					var c: Color = l.cor
					c.a *= 1.0 - u
					var r: float = float(l.raio) * (0.3 + 0.7 * u)
					no.draw_arc(l.c, r, 0, TAU, 32, c, 1.0)
				continue
			if camada != 1:
				continue
			var c2: Color = l.cor
			c2.a = 1.0 - u
			var a: Vector2 = l.a
			var b: Vector2 = l.b
			var pts := PackedVector2Array()
			var partes := int(l.get("quebra", 6))
			for k in partes + 1:
				var t := float(k) / partes
				var off := Vector2.ZERO if k == 0 or k == partes else Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * float(l.tremor)
				pts.append((a.lerp(b, t) + off).round())
			no.draw_polyline(pts, Color(c2.r, c2.g, c2.b, c2.a * 0.35), float(l.larg) + 2.0)
			no.draw_polyline(pts, c2, float(l.larg))
	for pr in _proj:
		if not pr.has("pos"):
			continue
		var p: Vector2 = ((pr.pos as Vector2) - Vector2(0, pr.h)).round()
		match String(pr.tipo):
			"bala":
				if camada == 1:
					var u: float = minf(float(pr.t) / float(pr.dur), 1.0)
					var cauda: Vector2 = ((pr.a as Vector2) - Vector2(0, pr.ha)).lerp(p, maxf(0.0, (u - 0.25) / maxf(u, 0.001)))
					var c: Color = pr.cor
					if pr.has("eletrico"):
						var pts := PackedVector2Array([cauda.round()])
						for k in 3:
							pts.append((cauda.lerp(p, (k + 1) / 4.0) + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))).round())
						pts.append(p)
						no.draw_polyline(pts, c, 1.0)
					else:
						no.draw_line(cauda.round(), p, Color(c.r, c.g, c.b, 0.35), float(pr.larg) + 1.0)
						no.draw_line((p - (p - cauda).normalized() * 6.0).round(), p, Color(1, 1, 0.9), float(pr.larg))
			"pulso":
				if camada == 1:
					var d := ((pr.b as Vector2) - (pr.a as Vector2)).normalized()
					no.draw_line((p - d * 7.0).round(), p, Color(0.4, 0.8, 1.0, 0.5), 3.0)
					no.draw_line((p - d * 4.0).round(), p, Color(0.85, 1.0, 1.0), 1.0)
			"foguete":
				if camada == 0:
					no.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 2)), Color(0.25, 0.24, 0.22))
				else:
					no.draw_rect(Rect2(p - Vector2(1, 0), Vector2(2, 2)), Color(1, 0.8, 0.4))
			"granada":
				if camada == 0:
					no.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(0.15, 0.14, 0.13))
			"gosma":
				if camada == 0:
					no.draw_circle(p, 2.5, Color(0.2, 0.3, 0.04))
					no.draw_circle(p, 1.8, Color(0.55, 0.85, 0.12))
					no.draw_rect(Rect2(p - Vector2(1, 1), Vector2(1, 1)), Color(0.9, 1.0, 0.6))
				else:
					no.draw_circle(p, 3.5, Color(0.3, 0.6, 0.05, 0.4))


func _desenhar_chao() -> void:
	for m in _marcas:
		var u: float = float(m.t) / float(m.vida)
		var c: Color = m.cor
		c.a *= 1.0 - smoothstep(0.6, 1.0, u)
		var p: Vector2 = (m.p as Vector2).round()
		var r: float = float(m.r) * (1.0 if m.tipo != "acido" else (0.5 + 0.5 * minf(u * 6.0, 1.0)))
		var ri: int = m.ri
		var esc: float = r / float(m.r)
		_chao.draw_texture_rect(m.tex, Rect2(p - Vector2(ri, ri) * esc, Vector2(ri * 2 + 1, ri * 2 + 1) * esc), false, Color(1, 1, 1, c.a / maxf((m.cor as Color).a, 0.01)))
		if m.tipo == "acido":                                     # bolhas chiando na poça
			for b in m.bolhas:
				var fase: float = fmod(float(m.t) * 2.2 + float(b[1]), 2.0)
				if fase < 1.0:
					var bp: Vector2 = (p + (b[0] as Vector2) * (r / 7.0)).round()
					_chao.draw_rect(Rect2(bp, Vector2(1, 1)), Color(0.85, 1.0, 0.45, c.a))
					if fase > 0.7:
						_chao.draw_rect(Rect2(bp + Vector2(-1, 0), Vector2(3, 1)), Color(0.75, 0.95, 0.35, c.a * 0.6))


## Disco pontilhado branco (raio r, nível de alfa 1..8) guardado: a fumaça desenha com uma textura só.
func _disco(r: int, nivel: int) -> Texture2D:
	var chave := r * 16 + nivel
	if not _cache_disco.has(chave):
		var img := Image.create(r * 2 + 1, r * 2 + 1, false, Image.FORMAT_RGBA8)
		var a := nivel / 8.0
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := sqrt(float(x * x + y * y)) / maxf(r, 0.5)
				var limiar: float = (float(BAYER[posmod(x, 4) + 4 * posmod(y, 4)]) + 0.5) / 16.0
				if d <= 1.0 and a * (1.15 - d * 0.6) > limiar:
					img.set_pixel(x + r, y + r, Color.WHITE)
		_cache_disco[chave] = ImageTexture.create_from_image(img)
	return _cache_disco[chave]


func _disco_pontilhado(no: Node2D, c: Vector2, r: float, cor: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var d := sqrt(float(x * x + y * y)) / maxf(r, 0.5)
			if d > 1.0:
				continue
			var limiar: float = (float(BAYER[(posmod(int(c.x) + x, 4)) + 4 * posmod(int(c.y) + y, 4)]) + 0.5) / 16.0
			if cor.a * (1.15 - d * 0.6) > limiar:
				no.draw_rect(Rect2(c + Vector2(x, y), Vector2.ONE), Color(cor.r, cor.g, cor.b, 1.0))


func _elipse_pontilhada(no: Node2D, c: Vector2, r: float, cor: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var d := sqrt(float(x * x) + float(y * y) / 0.3) / maxf(r, 0.5)
			if d > 1.0:
				continue
			var limiar: float = (float(BAYER[(posmod(int(c.x) + x, 4)) + 4 * posmod(int(c.y) + y, 4)]) + 0.5) / 16.0
			if cor.a * (1.25 - d) > limiar:
				no.draw_rect(Rect2(c + Vector2(x, y), Vector2.ONE), Color(cor.r, cor.g, cor.b, 1.0))
