class_name Desenho2D
extends Node2D
## Espelho 2D do mundo 3D (que segue simulando, só não é desenhado). Lê o que o 3D já calcula e desenha os sprites:
##  - chão: a malha de cada chunk (com relevo) projetada, com o shader de pixel art e os mesmos mapas do 3D
##    (camadas, fábrica → piso que cresce em volta das construções, ambiente → sujeira, óleo, água suja, queimado);
##  - natureza: os MultiMesh de cada chunk (árvores, rochas, jazidas…), um sprite por instância;
##  - construções: os nós de cada estrutura (com o Animador: ativo, fase do braço, giro da torre) e os lotes
##    (esteira, cano, trilho);
##  - itens nas esteiras e nas garras: os MultiMesh do DesenhoItens.
## Unidade do desenho = pixel do sprite; a câmera vira escala (zoom inteiro) e deslocamento.

const SOL := Vector3(-0.628, 0.574, 0.527)        ## direção da luz dos sprites (Godot: x, y para cima, z sul)
const FPS := 12.0

var mundo: Node3D
var camera: Camera2DJogo
var chao := Node2D.new()
var sombras := Node2D.new()
var objetos := Node2D.new()
var _mat_base: ShaderMaterial
var _chunks: Dictionary = {}       ## k → {mi3, mi2, assin, objs: Array}
var _est: Dictionary = {}          ## id → {spr, som, nome, variante}
var _itens: Array[Sprite2D] = []
var _moveis: Dictionary = {}       ## chave → par (trens, aranhas, ninhos, drones)
var fantasmas := Node2D.new()
var marcas := Node2D.new()
var fios := Node2D.new()
var _fant_spr: Array[Sprite2D] = []
var _fant_peg: Array[Polygon2D] = []
var _fant_txt: Array[Label] = []
var _fant_seta: Array[Polygon2D] = []
var _assin_fios := ""
var efeitos := Node2D.new()
var _efs: Array[Dictionary] = []    ## {no, vida, dur, tipo, ...}
var _voos: Dictionary = {}          ## nó 3D do foguete → {no, fumaca}
var noite := CanvasModulate.new()
var _luzes: Dictionary = {}         ## id → {luz: PointLight2D, chamas: Array[Sprite2D]}
static var _tex_luz: Texture2D
var _t := 0.0
var ocultar: Node3D = null          ## estrutura que não se desenha agora (núcleo durante a abertura)
var _tremor := 0.0
var _tremor_forca := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chao.z_index = -20
	sombras.z_index = -10
	objetos.y_sort_enabled = true
	marcas.z_index = -15
	fios.z_index = 3
	fantasmas.z_index = 5
	efeitos.z_index = 4
	add_child(chao)
	add_child(marcas)
	add_child(sombras)
	add_child(objetos)
	add_child(fios)
	add_child(efeitos)
	add_child(fantasmas)
	add_child(noite)


func _process(delta: float) -> void:
	if mundo == null or camera == null or not mundo.is_node_ready():
		return
	_t += delta
	if Engine.get_process_frames() == 12 and OS.get_cmdline_user_args().has("olhar_leste"):
		camera.alvo += Vector3(9, 0, 0)               # teste: o ataque vem do leste
	var vp := get_viewport_rect().size
	scale = Vector2.ONE * camera.zoom_px
	position = (vp * 0.5 - Camera2DJogo.projetar(camera.alvo) * camera.zoom_px).round()
	if _tremor > 0.0:
		_tremor -= delta
		position += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _tremor_forca * camera.zoom_px
	_sincronizar_chunks()
	_sincronizar_estruturas()
	_sincronizar_itens()
	_sincronizar_moveis()
	_sincronizar_fios()
	_sincronizar_fantasma()
	_sincronizar_voos(delta)
	_atualizar_efeitos(delta)
	_sincronizar_noite()


# ------------------------------------------------------------------ sprite + sombra
func _par(nome: String) -> Dictionary:
	var m := Catalogo2D.meta(nome)
	if m.is_empty():
		return {}
	var spr := Sprite2D.new()
	spr.centered = false
	spr.region_enabled = true
	spr.texture = Catalogo2D.folha(nome)
	spr.offset = -Vector2(m.ancora[0], m.ancora[1])
	var som := Sprite2D.new()
	som.centered = false
	som.region_enabled = true
	som.texture = Catalogo2D.folha(nome, "", true)
	som.offset = spr.offset
	objetos.add_child(spr)
	sombras.add_child(som)
	return {"spr": spr, "som": som, "m": m, "nome": nome, "variante": ""}


func _por(p: Dictionary, pos3: Vector3, linha: int, q: int, variante := "") -> void:
	if variante != p.variante:
		p.variante = variante
		(p.spr as Sprite2D).texture = Catalogo2D.folha(p.nome, variante)
		(p.som as Sprite2D).texture = Catalogo2D.folha(p.nome, variante, true)
	var r := Catalogo2D.regiao(p.m, linha, q)
	var chao_p := Camera2DJogo.projetar(Vector3(pos3.x, 0.0, pos3.z))
	var alto := Camera2DJogo.projetar(pos3) - chao_p          # altura do pé (relevo, esteira elevada) vira deslocamento
	(p.spr as Sprite2D).position = chao_p                      # ordenação pelo pé no chão
	(p.spr as Sprite2D).offset = -Vector2(p.m.ancora[0], p.m.ancora[1]) + alto
	(p.spr as Sprite2D).region_rect = r
	(p.som as Sprite2D).position = chao_p
	(p.som as Sprite2D).offset = (p.spr as Sprite2D).offset
	(p.som as Sprite2D).region_rect = r


func _soltar(p: Dictionary) -> void:
	if p.is_empty():
		return
	(p.spr as Node).queue_free()
	(p.som as Node).queue_free()


# ------------------------------------------------------------------ chão
func _material() -> ShaderMaterial:
	if _mat_base == null:
		var imgs: Array[Image] = []
		for nome in DesenhoChunk._camadas:
			var img: Image
			if nome == "piso_fabrica":
				var t := (load(Catalogo2D.RAIZ + "chao/piso_fabrica.png") as Texture2D).get_image()
				t.decompress()
				img = Image.create(140, 80, false, Image.FORMAT_RGBA8)
				for j in 4:
					for i in 4:
						img.blit_rect(t, Rect2i(0, 0, 35, 20), Vector2i(i * 35, j * 20))
			elif nome.begins_with("agua"):
				img = (load(Catalogo2D.RAIZ + "chao/%s.png" % nome) as Texture2D).get_image()
				img.decompress()
				img = img.get_region(Rect2i(0, 0, 140, 80))
			else:
				var caminho := Catalogo2D.RAIZ + "chao/%s.png" % nome
				img = (load(caminho if ResourceLoader.exists(caminho) else Catalogo2D.RAIZ + "chao/campina.png") as Texture2D).get_image()
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			imgs.append(img)
		var arr := Texture2DArray.new()
		arr.create_from_images(imgs)
		_mat_base = ShaderMaterial.new()
		_mat_base.shader = load("res://versao2d/chao_2d.gdshader")
		_mat_base.set_shader_parameter("texturas", arr)
		_mat_base.set_shader_parameter("agua_rasa", load(Catalogo2D.RAIZ + "chao/agua_rasa.png"))
		_mat_base.set_shader_parameter("agua_funda", load(Catalogo2D.RAIZ + "chao/agua_funda.png"))
		_mat_base.set_shader_parameter("detalhe", load("res://assets/texturas/ruido_detalhe.png"))
		_mat_base.set_shader_parameter("camada_piso", float(DesenhoChunk._camadas.find("piso_fabrica")))
		_mat_base.set_shader_parameter("camada_jazida", float(DesenhoChunk._camadas.find("jazida")))
		_mat_base.set_shader_parameter("camada_praia", float(DesenhoChunk._camadas.find("praia")))
		_mat_base.set_shader_parameter("primeira_agua", float(DesenhoChunk._camadas.find("agua_rasa")))
	return _mat_base


func _malha_chao(mi3: MeshInstance3D) -> ArrayMesh:
	var a := mi3.mesh.surface_get_arrays(0)
	var v3: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var g := mi3.global_transform
	var v2 := PackedVector2Array(); v2.resize(v3.size())
	var uv := PackedVector2Array(); uv.resize(v3.size())
	var cor := PackedColorArray(); cor.resize(v3.size())
	var sol := SOL.normalized()
	for i in v3.size():
		var p := g * v3[i]
		v2[i] = Camera2DJogo.projetar(p)
		uv[i] = Vector2(p.x, -p.z)
		var luz := clampf(1.0 + 0.9 * (nr[i].normalized().dot(sol) - 0.574), 0.55, 1.25) if i < nr.size() else 1.0
		var mar := uv2[i] if i < uv2.size() else Vector2.ZERO
		cor[i] = Color(mar.x, mar.y, luz, 1.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v2
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cor
	arr[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _sincronizar_chunks() -> void:
	var chunks: Dictionary = mundo.get("chunks")
	for k in _chunks.keys():
		if not chunks.has(k) or not is_instance_valid(_chunks[k].dono):
			_soltar_chunk(k)
	for k in chunks:
		var d: Node3D = chunks[k]
		if not is_instance_valid(d) or not d.is_inside_tree():
			continue
		var mi3 := d.get_node_or_null("chao") as MeshInstance3D
		if mi3 == null:
			continue
		var c: Dictionary = _chunks.get(k, {})
		if c.is_empty() or c.dono != d or c.mi3 != mi3:
			if not c.is_empty():
				_soltar_chunk(k)
			var mi2 := MeshInstance2D.new()
			mi2.mesh = _malha_chao(mi3)
			var mat := _material().duplicate() as ShaderMaterial
			mi2.material = mat
			chao.add_child(mi2)
			c = {"dono": d, "mi3": mi3, "mi2": mi2, "mat": mat, "assin": "", "objs": []}
			_chunks[k] = c
		# mapas do 3D (a fábrica cresce, o ambiente suja): os mesmos objetos de textura, só repassar se trocou
		var m3 := mi3.material_override as ShaderMaterial
		for p in ["mapa_camadas", "origem_mapa", "mapa_fabrica", "mapa_ambiente"]:
			var v = m3.get_shader_parameter(p)
			if v != null and (c.mat as ShaderMaterial).get_shader_parameter(p) != v:
				(c.mat as ShaderMaterial).set_shader_parameter(p, v)
		_sincronizar_natureza(c, d)


func _soltar_chunk(k: Vector2i) -> void:
	var c: Dictionary = _chunks[k]
	if is_instance_valid(c.mi2):
		(c.mi2 as Node).queue_free()
	for p in c.objs:
		_soltar(p)
	_chunks.erase(k)


func _sincronizar_natureza(c: Dictionary, d: Node3D) -> void:
	var mmis: Array = []
	var assin := ""
	for n in d.get_children():
		if n is MultiMeshInstance3D and n.name != "grama" and (n as MultiMeshInstance3D).multimesh != null:
			mmis.append(n)
			assin += "%d:%d;" % [n.get_instance_id(), (n as MultiMeshInstance3D).multimesh.instance_count]
	if assin == c.assin:
		return
	c.assin = assin
	for p in c.objs:
		_soltar(p)
	c.objs = []
	for mmi: MultiMeshInstance3D in mmis:
		var nome_no := String(mmi.name)
		var nome := nome_no.get_slice("#", 0)
		if not Catalogo2D.tem(nome):
			continue
		var mm := mmi.multimesh
		var g := mmi.global_transform
		for i in mm.instance_count:
			var t := g * mm.get_instance_transform(i)
			var p := _par(nome)
			if p.is_empty():
				continue
			_por(p, t.origin, 0, 0)
			if nome_no.contains("queimada"):
				(p.spr as Sprite2D).modulate = Color(0.25, 0.22, 0.2)
			c.objs.append(p)


# ------------------------------------------------------------------ construções
func _sincronizar_estruturas() -> void:
	var mapa: MapaOcupacao = mundo.get("mapa")
	var nos: Dictionary = mundo.get("_nos")
	var vistos := {}
	for id in nos:
		var n: Node3D = nos[id]
		if not is_instance_valid(n) or not mapa.estruturas.has(id):
			continue
		var nome: String = mapa.estruturas[id].nome
		vistos[id] = true
		_desenhar_estrutura(id, nome, n.global_transform, n)
	var lotes: DesenhoLotes = mundo.get("_lotes")
	if lotes != null:
		for chave in lotes._lotes:
			var nome: String = String(chave).get_slice("|", 2).get_slice("#", 0)
			var ids: Dictionary = lotes._lotes[chave].ids
			for id in ids:
				vistos[id] = true
				_desenhar_estrutura(id, nome, ids[id], null)
	for id in _est.keys():
		if not vistos.has(id):
			_soltar(_est[id])
			_est.erase(id)


func _desenhar_estrutura(id: int, nome: String, t: Transform3D, n: Node3D) -> void:
	if not _est.has(id) or _est[id].nome != nome:
		if _est.has(id):
			_soltar(_est[id])
		var p := _par(nome)
		if p.is_empty():
			return
		_est[id] = p
	var p: Dictionary = _est[id]
	var m: Dictionary = p.m
	var a: Animador = null
	if n != null:
		for ch in n.get_children():
			if ch is Animador:
				a = ch
				break
	var yaw := t.basis.get_euler().y
	var linha := Catalogo2D.linha_do_angulo(m, yaw)
	var q := 0
	var variante := ""
	var qs := int(m.quadros)
	match String(m.get("animacao", "parado")):
		"trabalho":
			if a != null and a._player != null and a._player.current_animation != "":
				var ln := a._player.get_animation(a._player.current_animation).length
				q = int(a._player.current_animation_position / maxf(ln, 0.01) * qs)
			elif a != null and a.ativo:
				q = int(_t * FPS)
		"braco":
			if a != null:
				variante = "atras" if absf(absf(a.giro_origem) - PI) < 0.3 else ("esquerda" if a.giro_origem > 0.0 else "direita")
				q = int(a.fase_braco * qs)
		"pecas":
			if nome.begins_with("esteira"):
				q = int(_t * FPS)                     # a lona roda sempre
			elif a != null and a.ativo:
				q = int(a.tempo * FPS)
	if String(m.get("tipo_linha", "")) == "direcao" and a != null and a.tem("giro"):
		linha = Catalogo2D.linha_do_angulo(m, (a._partes["giro"] as Node3D).global_rotation.y)
	_por(p, t.origin, linha, q, variante)
	(p.spr as Sprite2D).visible = n == null or n != ocultar
	(p.som as Sprite2D).visible = (p.spr as Sprite2D).visible


# ------------------------------------------------------------------ itens (esteira e garra)
func _sincronizar_itens() -> void:
	var di = mundo.get("_desenho_itens")
	var k := 0
	if di != null:
		for item in di._mm:
			var mmi: MultiMeshInstance3D = di._mm[item]
			if not is_instance_valid(mmi) or not mmi.visible or not Catalogo2D.tem(item):
				continue
			var mm := mmi.multimesh
			var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var g := mmi.global_transform
			var m := Catalogo2D.meta(item)
			for i in n:
				var p := g * mm.get_instance_transform(i).origin
				if k >= _itens.size():
					var s := Sprite2D.new()
					s.centered = false
					s.region_enabled = true
					objetos.add_child(s)
					_itens.append(s)
				var s: Sprite2D = _itens[k]
				k += 1
				s.visible = true
				s.texture = Catalogo2D.folha(item)
				s.region_rect = Catalogo2D.regiao(m, 0, 0)
				var pc := Camera2DJogo.projetar(Vector3(p.x, 0.0, p.z))
				s.position = pc + Vector2(0, 0.6)          # fica na frente da esteira do mesmo tile
				s.offset = -Vector2(m.ancora[0], m.ancora[1]) + Camera2DJogo.projetar(p) - pc - Vector2(0, 0.6)
	for j in range(k, _itens.size()):
		_itens[j].visible = false


# ------------------------------------------------------------------ trens, aranhas, ninhos, drones (nós que andam)
static func _nome_do_arquivo(n: Node) -> String:
	return n.scene_file_path.get_file().get_basename()


func _sincronizar_moveis() -> void:
	var vistos := {}
	var dt = mundo.get("_desenho_trens")
	if dt != null:
		for id in dt._carros:
			var lista: Array = dt._carros[id]
			for i in lista.size():
				var no: Node3D = lista[i]
				if is_instance_valid(no):
					_movel("trem%d_%d" % [id, i], _nome_do_arquivo(no), no, 0, vistos)
	var dc = mundo.get("_desenho_colonia")
	if dc != null:
		for id in dc._aranhas:
			var no: Node3D = dc._aranhas[id]
			if is_instance_valid(no) and no.visible:
				_movel("ar%d" % id, "aranha_montada", no, 0, vistos)
		for id in dc._ninhos:
			var no: Node3D = dc._ninhos[id]
			if is_instance_valid(no) and no.visible:
				_movel("ni%d" % id, "ninho_aranha", no, int(_t * FPS), vistos)
	var dd = mundo.get("_desenho_drones")
	if dd != null:
		for id in dd._nos:
			var r: Dictionary = dd._nos[id]
			var raiz: Node3D = r.get("no")
			if raiz == null or not is_instance_valid(raiz) or raiz.get_child_count() == 0:
				continue
			var corpo := raiz.get_child(0) as Node3D
			_movel("dr%d" % id, _nome_do_arquivo(corpo), corpo, int(_t * FPS), vistos)
	for k in _moveis.keys():
		if not vistos.has(k):
			_soltar(_moveis[k])
			_moveis.erase(k)


func _movel(chave: String, nome: String, no: Node3D, q: int, vistos: Dictionary) -> void:
	if not Catalogo2D.tem(nome):
		return
	vistos[chave] = true
	if not _moveis.has(chave):
		var p := _par(nome)
		if p.is_empty():
			return
		_moveis[chave] = p
	var p: Dictionary = _moveis[chave]
	var g := no.global_transform
	_por(p, g.origin, Catalogo2D.linha_do_angulo(p.m, g.basis.get_euler().y), q)


# ------------------------------------------------------------------ fios de energia (linha de 1 px com barriga)
func _sincronizar_fios() -> void:
	var df = mundo.get("_fios")
	if df == null:
		return
	var assin: String = str(df._assinatura) + str(df._lista.size())
	if assin == _assin_fios:
		return
	_assin_fios = assin
	for c in fios.get_children():
		c.queue_free()
	for cabo in df._lista:
		var a: Vector3 = cabo[0]
		var b: Vector3 = cabo[1]
		var flecha: float = cabo[2]
		var l := Line2D.new()
		l.width = 1.0
		l.default_color = Color(0.07, 0.06, 0.06, 0.95)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for k in 13:
			var t := k / 12.0
			l.add_point(Camera2DJogo.projetar(a.lerp(b, t) - Vector3(0, flecha * 4.0 * t * (1.0 - t), 0)))
		fios.add_child(l)


# ------------------------------------------------------------------ fantasma da construção (o mesmo plano do 3D)
func _cor_de(no: Node) -> Color:
	for mi in no.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m != null:
			var c = m.get_shader_parameter("cor")
			if c is Color:
				return c
	return Color(0.5, 1.0, 0.6)


func _sincronizar_fantasma() -> void:
	var ctl = mundo.get("controle")
	var f: Fantasma = ctl.fantasma if ctl != null else null
	var ns := 0
	var np := 0
	var nt := 0
	var nf := 0
	if f != null and f.visible:
		for nome in f._modelos:
			if not Catalogo2D.tem(nome):
				continue
			for no: Node3D in f._modelos[nome]:
				if not no.visible:
					continue
				if ns >= _fant_spr.size():
					var s := Sprite2D.new()
					s.centered = false
					s.region_enabled = true
					fantasmas.add_child(s)
					_fant_spr.append(s)
				var s: Sprite2D = _fant_spr[ns]
				ns += 1
				var m := Catalogo2D.meta(nome)
				var g := no.global_transform
				s.visible = true
				s.texture = Catalogo2D.folha(nome, "atras" if String(m.get("animacao", "")) == "braco" else "")
				s.region_rect = Catalogo2D.regiao(m, Catalogo2D.linha_do_angulo(m, g.basis.get_euler().y), 0)
				s.position = Camera2DJogo.projetar(g.origin)
				s.offset = -Vector2(m.ancora[0], m.ancora[1])
				var c := _cor_de(no)
				s.modulate = Color(c.r * 0.6 + 0.4, c.g * 0.6 + 0.4, c.b * 0.6 + 0.4, 0.72) if c.g > 0.5 else Color(1.0, 0.35, 0.3, 0.7)
		for p in f._pegadas:
			if not p.visible:
				continue
			if np >= _fant_peg.size():
				var pg := Polygon2D.new()
				marcas.add_child(pg)
				_fant_peg.append(pg)
			var pg: Polygon2D = _fant_peg[np]
			np += 1
			pg.visible = true
			var o := p.global_position
			var h := 0.46
			pg.polygon = PackedVector2Array([Camera2DJogo.projetar(o + Vector3(-h, 0, -h)), Camera2DJogo.projetar(o + Vector3(h, 0, -h)),
					Camera2DJogo.projetar(o + Vector3(h, 0, h)), Camera2DJogo.projetar(o + Vector3(-h, 0, h))])
			var c := _cor_de(p)
			pg.color = Color(c.r, c.g, c.b, 0.38)
		for r in f._rotulos:
			if not r.visible:
				continue
			if nt >= _fant_txt.size():
				var lb := Label.new()
				lb.add_theme_font_size_override("font_size", 14)
				lb.add_theme_color_override("font_outline_color", Color.BLACK)
				lb.add_theme_constant_override("outline_size", 4)
				fantasmas.add_child(lb)
				_fant_txt.append(lb)
			var lb: Label = _fant_txt[nt]
			nt += 1
			lb.visible = true
			lb.text = r.text
			lb.modulate = r.modulate
			lb.scale = Vector2.ONE / camera.zoom_px
			lb.position = Camera2DJogo.projetar(r.global_position) - Vector2(lb.size.x * 0.5, lb.size.y) / camera.zoom_px
		for st in f._setas:
			if not st.visible:
				continue
			if nf >= _fant_seta.size():
				var sp := Polygon2D.new()
				fantasmas.add_child(sp)
				_fant_seta.append(sp)
			var sp: Polygon2D = _fant_seta[nf]
			nf += 1
			sp.visible = true
			var g := st.global_transform
			var esc := sqrt(g.basis.get_scale().x)
			var frente := -g.basis.z.normalized() * 0.3 * esc
			var lado := g.basis.x.normalized() * 0.14 * esc
			sp.polygon = PackedVector2Array([Camera2DJogo.projetar(g.origin + frente), Camera2DJogo.projetar(g.origin - frente * 0.4 + lado),
					Camera2DJogo.projetar(g.origin - frente * 0.4 - lado)])
			var c := _cor_de(st)
			sp.color = Color(c.r, c.g, c.b, 0.9)
	for i in range(ns, _fant_spr.size()):
		_fant_spr[i].visible = false
	for i in range(np, _fant_peg.size()):
		_fant_peg[i].visible = false
	for i in range(nt, _fant_txt.size()):
		_fant_txt[i].visible = false
	for i in range(nf, _fant_seta.size()):
		_fant_seta[i].visible = false


# ------------------------------------------------------------------ efeitos de combate (dos mesmos eventos do 3D)
func _folha_efeito(nome: String) -> Array:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalogo2D.RAIZ + "efeitos/%s.json" % nome))
	return [m, load(Catalogo2D.RAIZ + "efeitos/%s.png" % nome)]


var _cache_ef: Dictionary = {}
func _sprite_efeito(nome: String, pos: Vector2, escala := 1) -> void:
	if not _cache_ef.has(nome):
		_cache_ef[nome] = _folha_efeito(nome)
	var m: Dictionary = _cache_ef[nome][0]
	var s := Sprite2D.new()
	s.texture = _cache_ef[nome][1]
	s.centered = false
	s.region_enabled = true
	s.scale = Vector2.ONE * escala
	s.offset = -Vector2(m.ancora[0], m.ancora[1])
	s.position = pos
	efeitos.add_child(s)
	_efs.append({"no": s, "vida": 0.0, "dur": float(m.quadros) / float(m.fps), "tipo": "folha", "m": m})


func efeitos_de(eventos: Array) -> void:
	var dc = mundo.get("_desenho_colonia")
	if OS.get_cmdline_user_args().has("depurar2d") and not eventos.is_empty():
		print("EV2D ", Engine.get_process_frames(), " ", eventos.map(func(e): return e.get("tipo", "?")), " aranhas=", dc._aranhas.size() if dc else -1, " moveis=", _moveis.size(), " efs=", _efs.size())
	for e in eventos:
		match String(e.get("tipo", "")):
			"tiro":
				var de: Vector3 = dc._boca(e, 1.25) if dc != null else Grade.ponto_mundo(e.de, 1.25)
				var para := Grade.ponto_mundo(e.para, 0.6)
				_sprite_efeito("clarao", Camera2DJogo.projetar(de))
				if not bool(e.get("projetil", false)):
					var energia: bool = String(e.get("nome", "")) == "torre_energia"
					_traco(de, para, Color(0.6, 0.95, 1.0) if energia else Color(1.0, 0.9, 0.55), 0.09)
			"salto":
				_traco(Grade.ponto_mundo(e.de, 0.6), Grade.ponto_mundo(e.para, 0.6), Color(0.7, 0.9, 1.0) if bool(e.get("eletrico", false)) else Color(1.0, 0.85, 0.5), 0.12)
			"explosao":
				_sprite_efeito("explosao", Camera2DJogo.projetar(Grade.ponto_mundo(e.pos, 0.0)), clampi(int(round(float(e.raio) / 1.6)), 1, 3))
			"pulso":
				_anel(Grade.ponto_mundo(e.pos, 0.05), float(e.raio), Color(0.75, 0.55, 1.0))


func _traco(de: Vector3, para: Vector3, cor: Color, vida: float) -> void:
	var l := Line2D.new()
	l.width = 1.0
	l.default_color = cor
	l.add_point(Camera2DJogo.projetar(de))
	l.add_point(Camera2DJogo.projetar(para))
	efeitos.add_child(l)
	_efs.append({"no": l, "vida": 0.0, "dur": vida, "tipo": "some"})


func _anel(c: Vector3, raio: float, cor: Color) -> void:
	var l := Line2D.new()
	l.width = 1.0
	l.default_color = cor
	l.closed = true
	efeitos.add_child(l)
	_efs.append({"no": l, "vida": 0.0, "dur": 0.55, "tipo": "anel", "c": c, "raio": raio})


func _atualizar_efeitos(delta: float) -> void:
	for i in range(_efs.size() - 1, -1, -1):
		var f: Dictionary = _efs[i]
		f.vida += delta
		var u: float = f.vida / f.dur
		if u >= 1.0:
			(f.no as Node).queue_free()
			_efs.remove_at(i)
			continue
		match String(f.tipo):
			"folha":
				var m: Dictionary = f.m
				var q := int(u * float(m.quadros))
				(f.no as Sprite2D).region_rect = Rect2(q * float(m.quadro[0]), 0, m.quadro[0], m.quadro[1])
			"some":
				(f.no as CanvasItem).modulate.a = 1.0 - u
			"anel":
				var l: Line2D = f.no
				l.clear_points()
				var r: float = f.raio * (0.2 + 0.8 * u)
				for k in 24:
					var a := k * TAU / 24.0
					l.add_point(Camera2DJogo.projetar(f.c + Vector3(cos(a) * r, 0, sin(a) * r)))
				l.modulate.a = 1.0 - u
			"fumaca":
				var s: Polygon2D = f.no
				s.position.y -= delta * 6.0
				s.scale = Vector2.ONE * (1.0 + u * 1.5)
				s.modulate.a = 0.7 * (1.0 - u)


## Foguetes e granadas no ar: o 3D calcula o voo (arco, tempo); aqui um ponto com fumaça atrás.
func _sincronizar_voos(_delta: float) -> void:
	var dc = mundo.get("_desenho_colonia")
	if dc == null:
		return
	var vivos := {}
	for v in dc._voos:
		var no3: Node3D = v.get("no")
		if no3 == null or not is_instance_valid(no3):
			continue
		vivos[no3] = true
		if not _voos.has(no3):
			var p := Polygon2D.new()
			p.polygon = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
			p.color = Color(0.85, 0.8, 0.55)
			efeitos.add_child(p)
			_voos[no3] = {"no": p, "t": 0.0}
		var r: Dictionary = _voos[no3]
		(r.no as Polygon2D).position = Camera2DJogo.projetar(no3.global_position).round()
		r.t += _delta
		if r.t > 0.04:
			r.t = 0.0
			var f := Polygon2D.new()
			f.polygon = PackedVector2Array([Vector2(-1.5, -1), Vector2(1.5, -1), Vector2(1.5, 1), Vector2(-1.5, 1)])
			f.color = Color(0.55, 0.53, 0.5)
			f.position = (r.no as Polygon2D).position
			efeitos.add_child(f)
			_efs.append({"no": f, "vida": 0.0, "dur": 0.9, "tipo": "fumaca"})
	for k in _voos.keys():
		if not vivos.has(k):
			(_voos[k].no as Node).queue_free()
			_voos.erase(k)


# ------------------------------------------------------------------ noite: escurece pelo relógio do jogo; luzes e labaredas
func _textura_luz() -> Texture2D:
	if _tex_luz == null:
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
		_tex_luz = t
	return _tex_luz


func _sincronizar_noite() -> void:
	var lz = mundo.get("luzes")
	var escuro: float = float(lz._escuro) if lz != null else 0.0
	noite.color = Color(1, 1, 1).lerp(Color(0.2, 0.23, 0.38), escuro)
	var vistos := {}
	for id in _est:
		var p: Dictionary = _est[id]
		var luz: Dictionary = p.m.get("luz", {})
		if luz.is_empty():
			continue
		vistos[id] = true
		var nos: Dictionary = mundo.get("_nos")
		var a: Animador = null
		if nos.has(id) and is_instance_valid(nos[id]):
			for ch in (nos[id] as Node).get_children():
				if ch is Animador:
					a = ch
		var aceso: bool = a == null or a.ativo
		if not _luzes.has(id):
			var pl := PointLight2D.new()
			pl.texture = _textura_luz()
			pl.blend_mode = Light2D.BLEND_MODE_ADD
			add_child(pl)
			var chs: Array[Sprite2D] = []
			for c in luz.get("chamas", []):
				var h := maxi(6, int(round(float(c.tamanho_px) / 2.0)) * 2)
				var nome := "labareda_%dpx%s" % [h, "_cresce" if c.cresce else ""]
				if not _cache_ef.has(nome):
					_cache_ef[nome] = _folha_efeito(nome)
				var s := Sprite2D.new()
				s.texture = _cache_ef[nome][1]
				s.centered = false
				s.region_enabled = true
				s.offset = -Vector2(_cache_ef[nome][0].ancora[0], _cache_ef[nome][0].ancora[1])
				s.set_meta("m", _cache_ef[nome][0])
				efeitos.add_child(s)
				chs.append(s)
			_luzes[id] = {"luz": pl, "chamas": chs}
		var r: Dictionary = _luzes[id]
		var spr: Sprite2D = p.spr
		var base := spr.position + spr.offset + Vector2(p.m.ancora[0], p.m.ancora[1])    # o pixel da âncora na tela
		var linha := int(round(spr.region_rect.position.y / float(p.m.quadro[1]))) / int(p.m.get("fileiras_por_linha", 1))
		var pos_px: Array = luz.pos_px[mini(linha, luz.pos_px.size() - 1)]
		var pl: PointLight2D = r.luz
		pl.position = base + Vector2(pos_px[0], pos_px[1]) - Vector2(p.m.ancora[0], p.m.ancora[1])
		var cor := Color(1.0, 0.8, 0.42) if luz.tipo == "poste" else Color(luz.cor[0], luz.cor[1], luz.cor[2])
		var tremor := (0.85 + 0.15 * sin(_t * 23.0 + id) * sin(_t * 7.0 + id * 0.3)) if luz.tipo == "fogo" else (0.85 + 0.15 * sin(_t * 3.0 + id)) if luz.tipo == "cristal" else 1.0
		pl.color = cor
		pl.energy = float(luz.forca) * 1.3 * escuro * tremor if aceso else 0.0
		pl.texture_scale = float(luz.raio_px) * 1.2 / 128.0
		pl.visible = pl.energy > 0.01
		var chamas: Array = luz.get("chamas", [])
		for i in r.chamas.size():
			var s: Sprite2D = r.chamas[i]
			s.visible = aceso
			var cp: Array = chamas[i].pos_px[mini(linha, chamas[i].pos_px.size() - 1)]
			s.position = base + Vector2(cp[0], cp[1]) - Vector2(p.m.ancora[0], p.m.ancora[1])
			var mm: Dictionary = s.get_meta("m")
			var q := int(_t * float(mm.fps) + id) % int(mm.quadros)
			s.region_rect = Rect2(q * float(mm.quadro[0]), 0, mm.quadro[0], mm.quadro[1])
	for id in _luzes.keys():
		if not vistos.has(id):
			(_luzes[id].luz as Node).queue_free()
			for s in _luzes[id].chamas:
				(s as Node).queue_free()
			_luzes.erase(id)


# ------------------------------------------------------------------ abertura do jogo novo e ajudas dela
func abrir(nucleo: Node3D, fim: Callable) -> void:
	var ab := Abertura2D.new()
	ab.desenho = self
	ab.nucleo = nucleo
	ab.terminou.connect(fim)
	add_child(ab)


func tremer(dur: float, forca: float) -> void:
	_tremor = dur
	_tremor_forca = forca


func fumacinha(pos: Vector2) -> void:
	var f := Polygon2D.new()
	f.polygon = PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])
	f.color = Color(0.5, 0.47, 0.45)
	f.position = pos
	efeitos.add_child(f)
	_efs.append({"no": f, "vida": 0.0, "dur": 1.4, "tipo": "fumaca"})
