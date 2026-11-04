extends Node2D
## Vitrine dos efeitos de combate da versão 2D (Efeitos2D): cada arma atira num alvo, em sequência, com o som do jogo.
## Rodar: godot --path jogo res://versao2d/vitrine_efeitos.tscn   (grava: --write-movie saida.avi)

const LARVA_PNG := "/mnt/d/Projetos/Jogos/PlanetaFactory_2D/sprites/inimigos_larva/larva_acida/"
var ef := Efeitos2D.new()
var mundo := Node2D.new()
var rotulo := Label.new()
var _t := 0.0
var _feitos := {}
var _sprites: Array[Sprite2D] = []
var _larva_tex: Texture2D
var _larva_meta: Dictionary
var _larva: Sprite2D
var _cuspe_t := -1.0
const ZOOM := 3.0

# roteiro: [início (s), título, atirador (sprite), alvo (sprite), arma, alvo do impacto, tiros, intervalo, som do tiro]
const ROTEIRO := [
	[0.0, "Torre padrão: tiro de energia (fraco)", "torre_defesa", "aranha_animada", "energia", "aranha", 7, 0.33, "tiro_energia"],
	[3.2, "Laser (energia forte)", "torre_defesa", "aranha_animada", "laser", "aranha", 3, 0.7, "tiro_energia"],
	[5.8, "Metralhadora: munição comum", "torre_metralhadora", "aranha_animada", "metralhadora", "aranha", 18, 0.1, "tiro_metralhadora"],
	[8.6, "Bala perfurante", "torre_metralhadora", "aranha_animada", "perfurante", "aranha", 6, 0.22, "tiro_perfurante"],
	[11.0, "Bala carregada (elétrica)", "torre_metralhadora", "aranha_animada", "carregada", "aranha", 6, 0.22, "tiro_carregada"],
	[13.4, "Lança-foguetes", "torre_foguetes", "aranha_animada", "foguete", "aranha", 3, 0.6, "tiro_foguete"],
	[16.2, "Enxame", "torre_foguetes", "aranha_animada", "enxame", "chao", 6, 0.12, "tiro_enxame"],
	[18.8, "Artilharia: só de longe (mínimo 32 m)", "artilharia", "ninho_aranha", "artilharia", "estrutura", 2, 3.0, "tiro_artilharia"],
	[26.0, "Drone de defesa", "drone_defesa", "aranha_animada", "drone", "aranha", 12, 0.16, "tiro_drone"],
	[29.0, "Drone de reparo: solda", "drone_reparo", "fornalha", "reparo", "estrutura", 1, 0.1, ""],
	[32.0, "Larva: cuspe ácido", "larva", "fornalha", "cuspe", "estrutura", 3, 1.2, ""],
]
const FIM := 36.5
const ARTILHARIA_DIST := 34.0
var _foco := Vector2.ZERO
var _zoom := ZOOM
var _atirador: Sprite2D
var _atirador_nome := ""
var _alvo_spr: Sprite2D
var _ultimo_tiro := -10.0
var _de := Vector3.ZERO
var _alvo_base := Vector3.ZERO


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.15))
	add_child(mundo)
	var chao := Image.load_from_file(ProjectSettings.globalize_path("res://assets2d/chao/campina.png"))
	var tex_chao := ImageTexture.create_from_image(chao)
	for x in range(-8, 8):
		for y in range(-5, 5):
			var s := Sprite2D.new()
			s.texture = tex_chao
			s.centered = false
			s.position = Vector2(x, y) * chao.get_width()
			mundo.add_child(s)
	mundo.add_child(ef)
	ef.z_index = 10
	ef.som = func(nome: String, _p: Vector2): Som.tocar(nome, Vector3.INF, -4.0)
	var c := CanvasLayer.new()
	add_child(c)
	rotulo.position = Vector2(24, 18)
	rotulo.add_theme_font_size_override("font_size", 30)
	rotulo.add_theme_color_override("font_outline_color", Color.BLACK)
	rotulo.add_theme_constant_override("outline_size", 8)
	c.add_child(rotulo)
	_larva_tex = ImageTexture.create_from_image(Image.load_from_file(LARVA_PNG + "larva_acida_cuspe.png"))
	_larva_meta = JSON.parse_string(FileAccess.get_file_as_string(LARVA_PNG + "larva_acida.json"))


func _sprite(nome: String, pos: Vector3, yaw: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.region_enabled = true
	if nome == "larva":
		s.texture = _larva_tex
		s.offset = -Vector2(_larva_meta.ancora[0], _larva_meta.ancora[1])
		s.region_rect = Rect2(0, 0, _larva_meta.quadro[0], _larva_meta.quadro[1])
		_larva = s
	else:
		var m := Catalogo2D.meta(nome)
		s.texture = Catalogo2D.folha(nome, "andar" if nome == "aranha_animada" else "")
		s.offset = -Vector2(m.ancora[0], m.ancora[1])
		s.region_rect = Catalogo2D.regiao(m, Catalogo2D.linha_do_angulo(m, yaw), 0)
	s.position = Camera2DJogo.projetar(pos)
	mundo.add_child(s)
	_sprites.append(s)
	return s


func _alvo_agora(i: int) -> Vector3:
	var r: Array = ROTEIRO[i]
	if r[3] != "aranha_animada":
		return _alvo_base
	return _alvo_base + Vector3(sin(_t * 0.9) * 1.3, 0, cos(_t * 0.6) * 1.6)      # a aranha anda: as torres acompanham


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	mundo.scale = Vector2.ONE * _zoom
	mundo.position = (vp * 0.5 - _foco * _zoom).round()
	_t += delta
	for i in ROTEIRO.size():
		var r: Array = ROTEIRO[i]
		var fim: float = ROTEIRO[i + 1][0] if i + 1 < ROTEIRO.size() else FIM
		if _t < r[0] or _t >= fim:
			continue
		var voa: bool = String(r[2]).begins_with("drone")
		if not _feitos.has("cena%d" % i):
			_feitos["cena%d" % i] = true
			for s in _sprites:
				s.queue_free()
			_sprites.clear()
			_larva = null
			rotulo.text = r[1]
			_de = Vector3(-3.4, 2.6 if voa else 0.0, 0.4)
			_alvo_base = Vector3(3.0, 0, 0.0)
			_zoom = ZOOM
			_foco = Vector2.ZERO
			if r[4] == "artilharia":                        # arma grande: alvo bem longe, a câmera acompanha a granada
				_de = Vector3(-ARTILHARIA_DIST / 2.0, 0, 0)
				_alvo_base = Vector3(ARTILHARIA_DIST / 2.0, 0, 0)
				_zoom = 2.0
			_alvo_spr = _sprite(r[3], _alvo_base, PI * 0.5)
			_atirador = _sprite(r[2], _de, 0.0)
			_atirador_nome = r[2]
			_ultimo_tiro = -10.0
		var alvo := _alvo_agora(i)
		if r[4] == "artilharia":
			var dt_tiro := _t - _ultimo_tiro
			var de2 := Camera2DJogo.projetar(_de)
			var al2 := Camera2DJogo.projetar(_alvo_base)
			var u := clampf((dt_tiro - 0.2) / 1.6, 0.0, 1.0) if dt_tiro < 2.6 else 1.0 - clampf((dt_tiro - 2.6) / 0.4, 0.0, 1.0)
			if _ultimo_tiro < 0.0:
				u = 0.0
			_foco = de2.lerp(al2, u * u * (3.0 - 2.0 * u))
		if _alvo_spr != null and r[3] == "aranha_animada":
			var m := Catalogo2D.meta("aranha_animada")
			_alvo_spr.position = Camera2DJogo.projetar(alvo)
			_alvo_spr.region_rect = Catalogo2D.regiao(m, Catalogo2D.linha_do_angulo(m, atan2(cos(_t * 0.9) * -1.3, sin(_t * 0.6) * 1.6)), int(_t * 14.0))
		_mirar(alvo)
		for k in int(r[6]):
			var tk: float = r[0] + 0.5 + k * float(r[7])
			if _t >= tk and not _feitos.has("t%d_%d" % [i, k]):
				_feitos["t%d_%d" % [i, k]] = true
				var d3 := (alvo - _de)
				d3.y = 0.0
				d3 = d3.normalized()
				var boca := _boca(r[2], d3, alvo)
				var mira := alvo + Vector3(randf_range(-0.3, 0.3), 0.6 if r[5] != "chao" else 0.0, randf_range(-0.4, 0.4))
				if r[4] == "enxame":
					mira = alvo + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.2, 1.2))
				if r[4] == "reparo":
					mira = alvo + Vector3(-0.4, 1.0, 0.3)
					ef.disparar("reparo", boca, mira, "estrutura", 2.4)
					continue
				if r[4] == "cuspe":
					_cuspe_t = 0.0
					Som.tocar("cuspe_acido", Vector3.INF, -2.0)
					get_tree().create_timer(0.38).timeout.connect(func(): ef.disparar("cuspe", boca, mira, r[5]))
					continue
				_ultimo_tiro = _t
				ef.disparar(r[4], boca, mira, r[5], 1.6 if r[4] == "artilharia" else 0.0)
				if r[8] != "":
					Som.tocar(r[8], Vector3.INF, -3.0)
				if r[4] in ["metralhadora", "perfurante", "carregada", "drone"]:
					get_tree().create_timer(0.06).timeout.connect(func(): Som.tocar("impacto_aranha", Vector3.INF, -8.0))
	if _larva != null and _cuspe_t >= 0.0:
		_cuspe_t += delta
		var q := mini(int(_cuspe_t * 12.0), 11)
		_larva.region_rect = Rect2(q * _larva_meta.quadro[0], 0, _larva_meta.quadro[0], _larva_meta.quadro[1])
	if _t >= FIM:
		get_tree().quit()


## Boca do atirador: a ponta do cano medida no sprite (meta "boca", por direção); larva: a boca dela, na frente.
func _boca(nome: String, d3: Vector3, alvo: Vector3) -> Vector3:
	if nome == "larva":
		return _de + Vector3(0, 0.22, 0) + d3 * 0.68
	var m := Catalogo2D.meta(nome)
	if m.has("boca"):
		var d := alvo - _de
		var b: Array = m.boca[Catalogo2D.linha_do_angulo(m, atan2(-d.x, -d.z))]
		return _de + Vector3(b[0], b[1], b[2])
	return _de + Vector3(0, 1.3, 0) + d3 * 0.7


## O atirador vira para o alvo (linha da folha) e, logo depois de cada tiro, toca a animação de recuo.
func _mirar(alvo: Vector3) -> void:
	if _atirador == null or _atirador_nome == "larva" or not Catalogo2D.tem(_atirador_nome):
		return
	var m := Catalogo2D.meta(_atirador_nome)
	var d := alvo - _de
	var linha := Catalogo2D.linha_do_angulo(m, atan2(-d.x, -d.z))
	var dt := _t - _ultimo_tiro
	var n := int(m.quadros)
	var var_tiro: bool = "tiro" in m.get("variantes", [])
	var q := 0
	var variante := ""
	if var_tiro and dt < n / 24.0:
		variante = "tiro"
		q = int(dt * 24.0)
	elif n > 1 and _atirador_nome.begins_with("drone"):
		q = int(_t * 12.0) % n                                    # hélices girando
	_atirador.texture = Catalogo2D.folha(_atirador_nome, variante)
	_atirador.region_rect = Catalogo2D.regiao(m, linha, q)
