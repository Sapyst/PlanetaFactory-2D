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
## o que é rente ao chão (esteira e trilho no nível do chão) e os itens em cima dela: fica sempre embaixo das
## construções, árvores e trens (y-sort de sprite alto erraria: trilho por cima do telhado, item sumindo sob a esteira)
var plano_sombras := Node2D.new()
var plano := Node2D.new()
var plano_itens := Node2D.new()
var _itens_plano: Array[Sprite2D] = []
var _mat_base: ShaderMaterial
var _chunks: Dictionary = {}       ## k → {mi3, mi2, assin, objs: Array}
var _est: Dictionary = {}          ## id → {spr, som, nome, variante}
var _itens: Array[Sprite2D] = []
var _moveis: Dictionary = {}       ## chave → par (trens, ninhos, drones)
var _aranhas: Dictionary = {}      ## id → {p, fase, ult, rumo}: aranha viva (sprite "aranha_animada")
var _mortas: Array[Dictionary] = [] ## aranha morrendo: {p, pos, linha, t}
var _corpos: Dictionary = {}       ## id do nó 3D do corpo (DesenhoCarcacas) → {p, linha, q, larva}: sucata e carcaça
var _ratos2d: Dictionary = {}      ## id do rato → {p, esp}: fase 5 (sprite rato_<espécie>, o nó 3D manda)
var _fauna2d: Dictionary = {}      ## fase 9: chave do DesenhoFaunaGrande ("h3", "p7", "f2") → {p}
var _afundando: Dictionary = {}     ## nó 3D da árvore dissolvendo (mundo._dissolver) → par de sprites
var _passaros: Dictionary = {}      ## nó 3D do pássaro (DesenhoPassaros) → par de sprites "passaro_<espécie>"
var _ninhos2d: Dictionary = {}      ## fase 6: nó 3D de cada ninho (DesenhoNinhosPassaros: pivô da taça/bolsa) → par
const ARVORE_MORTA := "arvore_morta"
const COR_CORROIDA := Color(0.92, 0.86, 0.72)   ## madeira desbotada pelo ácido (puxa para a terra da cratera)
const ARANHA := "aranha_animada"
const PASSO_ARANHA := 1.1           ## m que o corpo anda num ciclo da marcha (os 2 trípodes; quadros 0..11)
const MORTE_ARANHA := 1.2           ## s até a carcaça começar a sumir (queda 0,6 + parada 0,6, como no 3D)
const LARVA := "larva_acida"
const PASSO_LARVA := 0.6            ## m andados por ciclo de contração (como no 3D: Larva.CICLO_M)
var fantasmas := Node2D.new()
var marcas := Node2D.new()
var fios := Node2D.new()
var _fant_spr: Array[Sprite2D] = []
var _fant_peg: Array[Polygon2D] = []
var _fant_txt: Array[Label] = []
var _fant_seta: Array[Polygon2D] = []
var _plantas2d := PlantasReagem2D.new()   ## patch fauna, fase 2: folhas, galhos, cogumelos (escurecem com a noite)
var _camada_vida := CanvasLayer.new()  ## patch fauna, fase 1: vagalumes/insetos/olhos acima do escuro da noite
var _vida2d := VidaPequena2D.new()
var _obra_spr: Dictionary = {}          ## id da obra (patch RTS) → Sprite2D do holograma
var _assin_fios := ""
var efeitos := Node2D.new()
var ef := Efeitos2D.new()           ## efeitos de combate (disparo, projétil, impacto, sangue, cápsula, luz)
var _tiro_t: Dictionary = {}        ## id da torre → instante do último tiro (toca a animação de recuo)
var _linha_de: Dictionary = {}      ## id da estrutura/drone → linha (direção) desenhada agora: a boca sai dela
var _t_solda: Dictionary = {}       ## id do drone de reparo → próximo feixe de solda
var _portas: Array[Polygon2D] = []
var _marcadores: Array = []         ## os MarcadorPortas do mundo 3D (procurados de tempos em tempos)
var _mat_porta: Array[ShaderMaterial] = []
var _mat_folha: Dictionary = {}              ## "perfil|sombra" → copa pela estação (folhagem_2d.gdshader)
var _mudas: Dictionary = {}                  ## tile → {p (sprites), modelo, esc}: mudas e árvores plantadas
var _versao_mudas := -1
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
	plano_sombras.z_index = -14
	plano.z_index = -13
	plano_itens.z_index = -12
	fios.z_index = 3
	fantasmas.z_index = 5
	efeitos.z_index = 4
	add_child(chao)
	add_child(marcas)
	add_child(plano_sombras)
	add_child(plano)
	add_child(plano_itens)
	add_child(sombras)
	add_child(objetos)
	add_child(fios)
	add_child(efeitos)
	ef.luz_tex = _textura_luz()
	efeitos.add_child(ef)
	add_child(fantasmas)
	add_child(noite)
	add_child(_plantas2d)
	_camada_vida.layer = 2                        # acima do mundo (e do CanvasModulate dele), abaixo da interface
	add_child(_camada_vida)
	_vida2d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_camada_vida.add_child(_vida2d)


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
	_sincronizar_aranhas(delta)
	_sincronizar_afundando()
	_sincronizar_mudas()
	_sincronizar_corpos()
	_sincronizar_ratos()
	_sincronizar_fauna()
	_sincronizar_passaros()
	_sincronizar_vida()
	_sincronizar_fios()
	_sincronizar_fantasma()
	_sincronizar_obras()
	_sincronizar_portas()
	_sincronizar_voos(delta)
	_atualizar_efeitos(delta)
	_sincronizar_noite()


# ------------------------------------------------------------------ sprite + sombra
func _par(nome: String, rente := false) -> Dictionary:
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
	(plano if rente else objetos).add_child(spr)
	(plano_sombras if rente else sombras).add_child(som)
	return {"spr": spr, "som": som, "m": m, "nome": nome, "variante": ""}


## `z_ordem`: z do mundo pelo qual o sprite se ordena (NAN = o próprio pé). Construção grande usa a fileira sul da
## área: o que está embaixo dela (trem sob o telhado) fica atrás, o que está ao sul fica na frente.
func _por(p: Dictionary, pos3: Vector3, linha: int, q: int, variante := "", z_ordem := NAN) -> void:
	if variante != p.variante:
		p.variante = variante
		(p.spr as Sprite2D).texture = Catalogo2D.folha(p.nome, variante)
		(p.som as Sprite2D).texture = Catalogo2D.folha(p.nome, variante, true)
	var r := Catalogo2D.regiao(p.m, linha, q)
	var chao_p := Camera2DJogo.projetar(Vector3(pos3.x, 0.0, pos3.z))
	var alto := Camera2DJogo.projetar(pos3) - chao_p          # altura do pé (relevo, esteira elevada) vira deslocamento
	var ordem := chao_p if is_nan(z_ordem) else Camera2DJogo.projetar(Vector3(pos3.x, 0.0, z_ordem))
	(p.spr as Sprite2D).position = ordem                       # ordenação pelo pé no chão
	(p.spr as Sprite2D).offset = -Vector2(p.m.ancora[0], p.m.ancora[1]) + alto + chao_p - ordem
	(p.spr as Sprite2D).region_rect = r
	(p.som as Sprite2D).position = ordem
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
	var c3: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()   # A: 1 rio, 0,35 lago
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
		cor[i] = Color(mar.x, mar.y, luz, c3[i].a if i < c3.size() else 0.0)
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
		for p in ["mapa_camadas", "origem_mapa", "mapa_fabrica", "mapa_ambiente", "mapa_teia", "tex_teia"]:
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
		if n is MultiMeshInstance3D and n.name != "grama" and (n as MultiMeshInstance3D).multimesh != null \
				and not n.is_queued_for_deletion():
			mmis.append(n)
			assin += "%d:%d;" % [n.get_instance_id(), (n as MultiMeshInstance3D).multimesh.instance_count]
	if assin == c.assin:
		return
	c.assin = assin
	for p in c.objs:
		_soltar(p)
	c.objs = []
	for mmi: MultiMeshInstance3D in mmis:
		var nome_no := String(mmi.get_meta("modelo", mmi.name))   # o chunk guarda o modelo (o nome o Godot pode trocar)
		var nome := nome_no.get_slice("#", 0)
		var corroida := nome_no.ends_with("#corroida")
		if corroida and Distribuicao.eh_arvore(nome) and Catalogo2D.tem(ARVORE_MORTA):
			nome = ARVORE_MORTA                                     # morta pelo ácido: tronco seco, sem copa
		if not Catalogo2D.tem(nome):
			continue
		var perfil := Ecossistema.perfil_folha(nome)              # a copa muda pela estação, como no 3D
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
			elif corroida:
				(p.spr as Sprite2D).modulate = COR_CORROIDA
			elif perfil >= 1:
				(p.spr as Sprite2D).material = _material_folha(perfil, false)
				(p.som as Sprite2D).material = _material_folha(perfil, true)
			c.objs.append(p)


func _material_folha(perfil: int, sombra: bool) -> ShaderMaterial:
	var k := "%d|%s" % [perfil, sombra]
	if not _mat_folha.has(k):
		var m := ShaderMaterial.new()
		m.shader = preload("res://versao2d/folhagem_2d.gdshader")
		m.set_shader_parameter("perfil", perfil)
		m.set_shader_parameter("sombra", sombra)
		_mat_folha[k] = m
	return _mat_folha[k]


# ------------------------------------------------------------------ construções
func _sincronizar_estruturas() -> void:
	var mapa: MapaOcupacao = mundo.get("mapa")
	var nos: Dictionary = mundo.get("_nos")
	var vistos := {}
	for id in nos:
		var n: Node3D = nos[id]
		if not is_instance_valid(n) or not mapa.estruturas.has(id):
			continue
		var e: Dictionary = mapa.estruturas[id]
		vistos[id] = true
		var z_ordem := NAN
		if Grade.area_girada(e.area, e.rot).y > 1:
			z_ordem = -float(e.minimo.y) - 0.05                # logo dentro da borda sul da área
		_desenhar_estrutura(id, String(e.nome), n.global_transform, n, z_ordem)
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


func _desenhar_estrutura(id: int, nome: String, t: Transform3D, n: Node3D, z_ordem := NAN) -> void:
	if not _est.has(id) or _est[id].nome != nome:
		if _est.has(id):
			_soltar(_est[id])
		var p := _par(nome, n == null and _rente(nome, t.origin))
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
		_linha_de[id] = linha
		var dt_tiro: float = _t - float(_tiro_t.get(id, -99.0))
		if "tiro" in m.get("variantes", []) and dt_tiro < float(m.quadros) / 24.0:
			variante = "tiro"                          # o cano recua e volta logo depois do tiro
			q = int(dt_tiro * 24.0)
		elif "tiro" in m.get("variantes", []):
			q = 0
	_por(p, t.origin, linha, q, variante, z_ordem)
	(p.spr as Sprite2D).visible = n == null or n != ocultar
	(p.som as Sprite2D).visible = (p.spr as Sprite2D).visible


## Esteira e trilho no nível do chão (não a rampa nem a elevada) vão para a camada rente ao chão.
static func _rente(nome: String, pos: Vector3) -> bool:
	if not (nome.begins_with("esteira") or nome.begins_with("trilho")) or nome.begins_with("esteira_rampa"):
		return false
	return pos.y - Grade.altura_em(Vector2(pos.x, -pos.z)) < 0.25


# ------------------------------------------------------------------ itens (esteira e garra)
func _sincronizar_itens() -> void:
	var di = mundo.get("_desenho_itens")
	var k := 0
	var kp := 0
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
				# item baixo (na esteira do chão) vai por cima dela na camada rente; o da garra se ordena com o resto
				var rente := i < int(di._base.get(item, 0)) and p.y - Grade.altura_em(Vector2(p.x, -p.z)) < 0.45
				var lista := _itens_plano if rente else _itens
				var j := kp if rente else k
				if j >= lista.size():
					var s := Sprite2D.new()
					s.centered = false
					s.region_enabled = true
					(plano_itens if rente else objetos).add_child(s)
					lista.append(s)
				var s: Sprite2D = lista[j]
				if rente:
					kp += 1
				else:
					k += 1
				s.visible = true
				s.texture = Catalogo2D.folha(item)
				s.region_rect = Catalogo2D.regiao(m, 0, 0)
				var pc := Camera2DJogo.projetar(Vector3(p.x, 0.0, p.z))
				s.position = pc + Vector2(0, 0.6)          # fica na frente da esteira do mesmo tile
				s.offset = -Vector2(m.ancora[0], m.ancora[1]) + Camera2DJogo.projetar(p) - pc - Vector2(0, 0.6)
	for j in range(k, _itens.size()):
		_itens[j].visible = false
	for j in range(kp, _itens_plano.size()):
		_itens_plano[j].visible = false


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
		for id in dc._ninhos:
			var no: Node3D = dc._ninhos[id]
			if is_instance_valid(no) and no.visible:
				var toca := "ninho_aranha"
				if dc.colonia != null and dc.colonia.ninhos.has(id):
					toca = Colonia.toca_de(String(dc.colonia.ninhos[id].get("especie", "aranha")))
				_movel("ni%d" % id, toca, no, int(_t * FPS) if toca == "ninho_aranha" else 0, vistos)
	var dd = mundo.get("_desenho_drones")
	if dd != null:
		for id in dd._nos:
			var r: Dictionary = dd._nos[id]
			var raiz: Node3D = r.get("no")
			if raiz == null or not is_instance_valid(raiz) or raiz.get_child_count() == 0:
				continue
			var corpo := raiz.get_child(0) as Node3D
			var nome_dr := _nome_do_arquivo(corpo)
			_movel("dr%d" % id, nome_dr, corpo, int(_t * FPS), vistos)
			if Catalogo2D.tem(nome_dr):
				_linha_de["dr%d" % id] = Catalogo2D.linha_do_angulo(Catalogo2D.meta(nome_dr), corpo.global_transform.basis.get_euler().y)
				_solda(id, nome_dr, corpo)
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


# ------------------------------------------------------------------ aranhas: andar (pela distância), ataque e morte
func _sincronizar_aranhas(delta: float) -> void:
	var dc = mundo.get("_desenho_colonia")
	if dc == null or not Catalogo2D.tem(ARANHA):
		return
	for id in dc._aranhas:
		var no: Node3D = dc._aranhas[id]
		if not is_instance_valid(no):
			continue
		var larva := no is Larva
		var a: Dictionary = _aranhas.get(id, {})
		if a.is_empty():
			var p := _par(LARVA if larva else ARANHA)
			if p.is_empty():
				return
			a = {"p": p, "fase": randf(), "ult": no.global_position, "rumo": no.rotation.y, "larva": larva, "no": no}
			_aranhas[id] = a
		var pos := no.global_position
		# a marcha avança com o chão percorrido (e com o giro no lugar): o pé plantado não escorrega
		var anda := Vector2(pos.x - a.ult.x, pos.z - a.ult.z).length() + absf(angle_difference(float(a.rumo), no.rotation.y)) * 0.6
		a.ult = pos
		a.rumo = no.rotation.y
		var linha := Catalogo2D.linha_do_angulo(a.p.m, no.rotation.y)
		if larva:
			var cusp := float((no as Larva).cuspindo)
			if cusp > 0.0:
				_por(a.p, pos, linha, clampi(int((1.0 - cusp) * 12.0), 0, 11), "cuspe")
			else:
				a.fase = fposmod(float(a.fase) + anda / PASSO_LARVA, 1.0)
				_por(a.p, pos, linha, int(float(a.fase) * 12.0), "andar")
		elif no.atacando:
			_por(a.p, pos, linha, int(_t * FPS), "ataque")
		else:
			a.fase = fposmod(float(a.fase) + anda / PASSO_ARANHA, 1.0)
			_por(a.p, pos, linha, int(float(a.fase) * 12.0), "andar")
		(a.p.spr as Sprite2D).visible = no.visible
		(a.p.som as Sprite2D).visible = no.visible
	for id in _aranhas.keys():
		if dc._aranhas.has(id):
			continue
		var a: Dictionary = _aranhas[id]               # saiu da lista do 3D = morreu (o nó 3D segue a própria morte)
		_aranhas.erase(id)
		_mortas.append({"p": a.p, "pos": a.ult, "linha": Catalogo2D.linha_do_angulo(a.p.m, float(a.rumo)), "t": 0.0,
				"larva": bool(a.get("larva", false)), "q": int(float(a.fase) * 12.0), "no": a.get("no")})
	for i in range(_mortas.size() - 1, -1, -1):
		var m: Dictionary = _mortas[i]
		m.t += delta
		if m.larva:                                   # larva: murcha e achata no lugar (como o 3D), sem quadros de morte
			_por(m.p, m.pos, m.linha, int(m.q), "andar")
			var k := clampf(m.t / 0.5, 0.0, 1.0)
			(m.p.spr as Sprite2D).scale = Vector2(1.0 + 0.15 * k, 1.0 - 0.6 * k)
			(m.p.som as Sprite2D).scale = Vector2(1.0 + 0.15 * k, 1.0)
		else:
			_por(m.p, m.pos, m.linha, mini(int(m.t * FPS), 11), "morte")
		var no_m: Variant = m.get("no")
		if m.t >= MORTE_ARANHA and no_m != null and is_instance_valid(no_m) and bool((no_m as Node3D).get("fica")):
			# fase 4: o corpo fica — o mesmo sprite passa a ser a carcaça (sem troca), o DesenhoCarcacas cuida dela
			_corpos[(no_m as Node).get_instance_id()] = {"p": m.p, "linha": m.linha, "q": mini(int(m.t * FPS), 11) if not m.larva else int(m.q),
					"larva": m.larva, "no": no_m, "t0": _t}
			_mortas.remove_at(i)
			continue
		var alfa := clampf(1.0 - (m.t - MORTE_ARANHA) / 0.8, 0.0, 1.0)
		(m.p.spr as Sprite2D).modulate.a = alfa
		(m.p.som as Sprite2D).modulate.a = alfa
		if alfa <= 0.0:
			(m.p.spr as Sprite2D).scale = Vector2.ONE
			(m.p.som as Sprite2D).scale = Vector2.ONE
			_soltar(m.p)
			_mortas.remove_at(i)


## Fase 4: sucata e carcaça (os nós 3D do DesenhoCarcacas). O sprite que morreu na tela continua o mesmo; ao carregar
## o jogo, nasce direto na pose final. A ferrugem e a podridão tingem o sprite; o inchado estica para cima, os restos
## achatam; no fim apaga (o afundar do 3D).
func _sincronizar_corpos() -> void:
	var dcc = mundo.get("_desenho_carcacas")
	if dcc == null:
		return
	var vivos := {}
	for k in dcc.nos:
		var no: Node3D = dcc.nos[k].no
		if not is_instance_valid(no):
			continue
		var id := no.get_instance_id()
		vivos[id] = true
		var larva := no is Larva
		var rato := String(no.get_meta("rato", ""))
		var passaro := String(no.get_meta("passaro", ""))       # fase 6: pássaro morto (de lado ou de costas)
		var fauna := String(no.get_meta("fauna", ""))           # fase 9: herbívoro, predador, peixe boiando
		if fauna != "":
			rato = fauna                                      # (vira de lado e quadro como o rato)
		var c: Dictionary = _corpos.get(id, {})
		if c.is_empty():
			var nome_c := fauna if fauna != "" else (("rato_" + rato) if rato != "" else (("passaro_" + passaro) if passaro != "" else (LARVA if larva else ARANHA)))
			if not Catalogo2D.tem(nome_c):
				continue
			var p := _par(nome_c)
			if p.is_empty():
				continue
			var ang := no.rotation.y - PI / 2.0 if rato != "" else no.rotation.y
			c = {"p": p, "linha": Catalogo2D.linha_do_angulo(p.m, ang), "q": 0 if larva or rato != "" or passaro != "" else 11,
					"larva": larva, "no": no, "t0": _t}
			_corpos[id] = c
		var var_c := "morto" if rato != "" else ("andar" if larva else "morte")
		if passaro != "":
			var_c = "morto_costas" if bool(no.get_meta("costas", false)) else "morto"
		_por(c.p, no.global_position, int(c.linha), int(c.q), var_c)
		var spr := c.p.spr as Sprite2D
		if not (spr.material is ShaderMaterial):
			var mt := ShaderMaterial.new()
			mt.shader = preload("res://versao2d/corpo_2d.gdshader")
			spr.material = mt
		var mat := spr.material as ShaderMaterial
		var afunda := float(no.get_meta("afunda", 0.0))
		if larva:
			var esc: Vector3 = no.get_meta("escala", Vector3.ONE)
			spr.scale = Vector2(1.15 * esc.x, 0.4 * esc.y)
			(c.p.som as Sprite2D).scale = Vector2(1.15 * esc.x, 1.0)
		for nome in ["ferrugem", "podre", "desligada"]:
			mat.set_shader_parameter(nome, float(no.get_meta(nome, 0.0)))
		mat.set_shader_parameter("alfa", 1.0 - afunda)
		spr.modulate = Color.WHITE
		(c.p.som as Sprite2D).modulate = Color(1, 1, 1, 1.0 - afunda)
	for id in _corpos.keys():
		var c: Dictionary = _corpos[id]
		# recém-morto ainda não adotado pelo DesenhoCarcacas: espera uns segundos parado na pose final
		if not vivos.has(id) and (not is_instance_valid(c.get("no")) or _t - float(c.get("t0", 0.0)) > 3.0):
			(c.p.spr as Sprite2D).scale = Vector2.ONE
			(c.p.som as Sprite2D).scale = Vector2.ONE
			(c.p.spr as Sprite2D).material = null
			_soltar(c.p)
			_corpos.erase(id)


## Fase 5: os ratos fora da toca, pelo nó 3D do DesenhoRatos (posição, rumo, a ação e o quadro da animação). Saindo e
## entrando na toca o sprite aparece e some (o 3D sobe e afunda no buraco).
func _sincronizar_ratos() -> void:
	var dr = mundo.get("_desenho_ratos")
	if dr == null:
		return
	var vistos := {}
	for id in dr.nos:
		var n: Dictionary = dr.nos[id]
		var no: Node3D = n.no
		if not is_instance_valid(no):
			continue
		var nome := "rato_" + String(n.esp)
		if not Catalogo2D.tem(nome):
			continue
		vistos[id] = true
		var r: Dictionary = _ratos2d.get(id, {})
		if r.is_empty():
			var p := _par(nome)
			if p.is_empty():
				continue
			r = {"p": p}
			_ratos2d[id] = r
		var acao := String(n.acao) if String(n.acao) != "" else "andar"
		var anim: AnimationPlayer = n.anim
		var q := 0
		if anim != null and anim.is_playing() and anim.current_animation_length > 0.0:
			q = int(anim.current_animation_position / anim.current_animation_length * 8.0) % 8
		var pos := no.global_position
		_por(r.p, pos, Catalogo2D.linha_do_angulo(r.p.m, no.rotation.y - PI / 2.0), q, acao)
		var chao := Grade.altura_em(Vector2(pos.x, -pos.z))
		var a := 1.0 - clampf((chao - pos.y) / 0.12, 0.0, 1.0)          # dentro do buraco: some
		(r.p.spr as Sprite2D).modulate.a = a
		(r.p.som as Sprite2D).modulate.a = a
	for id in _ratos2d.keys():
		if not vistos.has(id):
			_soltar(_ratos2d[id].p)
			_ratos2d.erase(id)


## Fase 9: herbívoros, predadores e o peixe no pulo, pelo nó 3D do DesenhoFaunaGrande (posição, rumo, a ação e o
## quadro da animação; o filhote no tamanho dele). O peixe respinga na saída e na volta.
func _sincronizar_fauna() -> void:
	var df = mundo.get("_desenho_fauna")
	if df == null:
		return
	var vistos := {}
	for k in df.nos:
		var n: Dictionary = df.nos[k]
		var no: Node3D = n.no
		if not is_instance_valid(no):
			continue
		var nome := String(no.get_meta("fauna", ""))
		if nome == "" or not Catalogo2D.tem(nome):
			continue
		vistos[k] = true
		var r: Dictionary = _fauna2d.get(k, {})
		if r.is_empty():
			var p := _par(nome)
			if p.is_empty():
				continue
			r = {"p": p}
			_fauna2d[k] = r
		var acao := String(n.acao) if String(n.acao) != "" else "andar"
		var anim: AnimationPlayer = n.anim
		var q := 0
		if anim != null and anim.current_animation != "" and anim.current_animation_length > 0.0:
			q = int(anim.current_animation_position / anim.current_animation_length * 8.0) % 8
		_por(r.p, no.global_position, Catalogo2D.linha_do_angulo(r.p.m, no.rotation.y - PI / 2.0), q, acao)
		var esc := (n.mod as Node3D).scale.x
		(r.p.spr as Sprite2D).scale = Vector2.ONE * esc
		(r.p.som as Sprite2D).scale = Vector2.ONE * esc
	for k in _fauna2d.keys():
		if not vistos.has(k):
			var p: Dictionary = _fauna2d[k].p
			(p.spr as Sprite2D).scale = Vector2.ONE
			(p.som as Sprite2D).scale = Vector2.ONE
			_soltar(p)
			_fauna2d.erase(k)
	var pe: Peixes = mundo.get("peixes")
	if pe == null:
		return
	for ev in pe.eventos:
		if ev.tipo == "pulo":
			ef.respingo_agua(df._na_agua(ev.pos), 1.0)
	for pu in pe.pulos:
		if float(pu.t) / float(pu.dur) > 0.85 and not pu.has("caiu2d"):
			pu.caiu2d = true
			ef.respingo_agua(df._na_agua(pu.para), 0.8)


## Mudas e árvores plantadas (viveiro, pássaros, sementes no vento: AmbienteVivo.plantas): o sprite da espécie no
## tamanho do crescimento, no mesmo modelo, lugar e escala do 3D (DesenhoPlantas), com a copa pela estação. Só refaz
## quando `versao_plantas` muda (nasce, cai ou cresce um degrau).
func _sincronizar_mudas() -> void:
	var amb: AmbienteVivo = mundo.get("ambiente")
	if amb == null or amb.versao_plantas == _versao_mudas:
		return
	_versao_mudas = amb.versao_plantas
	for t in _mudas.keys():
		if not amb.plantas.has(t):
			_soltar(_mudas[t].p)
			_mudas.erase(t)
	var g: GeradorMundo = amb.gerador
	for t: Vector2i in amb.plantas:
		var modelo := DesenhoPlantas.modelo_de(amb, t)
		var esc := DesenhoPlantas.escala_de(t, float(amb.plantas[t]))
		var m: Dictionary = _mudas.get(t, {})
		if not m.is_empty() and m.modelo == modelo and absf(float(m.esc) - esc) < 0.005:
			continue
		if m.is_empty() or m.modelo != modelo:
			if not m.is_empty():
				_soltar(m.p)
				_mudas.erase(t)
			var p := _par(modelo) if Catalogo2D.tem(modelo) else {}
			if p.is_empty():
				continue
			var perfil := Ecossistema.perfil_folha(modelo)
			if perfil >= 1:
				(p.spr as Sprite2D).material = _material_folha(perfil, false)
				(p.som as Sprite2D).material = _material_folha(perfil, true)
			m = {"p": p, "modelo": modelo, "esc": esc}
			_mudas[t] = m
		m.esc = esc
		var pg := DesenhoPlantas.pos_de(t)
		var pos3 := Grade.ponto_mundo(pg, g.micro_em(pg - Vector2(0.5, 0.5)))
		_por(m.p, pos3, 0, 0)
		var alto := Camera2DJogo.projetar(pos3) - Camera2DJogo.projetar(Vector3(pos3.x, 0.0, pos3.z))
		for spr: Sprite2D in [m.p.spr, m.p.som]:
			spr.scale = Vector2.ONE * esc                         # cresce a partir do pé
			spr.offset = -Vector2(m.p.m.ancora[0], m.p.m.ancora[1]) + alto / esc   # o relevo não encolhe junto


## Árvore dissolvendo no chão corroído: o tronco morto afunda (a parte de baixo do sprite some no chão, como se
## entrasse nele) acompanhando a cópia 3D que o mundo anima (grupo "pf_afundando").
func _sincronizar_afundando() -> void:
	if not Catalogo2D.tem(ARVORE_MORTA):
		return
	var vivos := {}
	for no: Node3D in get_tree().get_nodes_in_group("pf_afundando"):
		if not is_instance_valid(no):
			continue
		vivos[no] = true
		if not _afundando.has(no):
			var nome_v := String(no.get_meta("modelo", ARVORE_MORTA))
			if Distribuicao.eh_arvore(nome_v) or not Catalogo2D.tem(nome_v):
				nome_v = ARVORE_MORTA
			var p := _par(nome_v)
			if p.is_empty():
				continue
			(p.spr as Sprite2D).modulate = COR_CORROIDA
			_afundando[no] = p
		var pa: Dictionary = _afundando[no]
		var origem: Vector3 = no.get_meta("origem")
		var k := clampf((origem.y - no.global_position.y) / maxf(0.1, float(no.get_meta("alto", 3.0))), 0.0, 1.0)
		_por(pa, origem, 0, 0)
		var r: Rect2 = (pa.spr as Sprite2D).region_rect
		var corte := floorf(r.size.y * k)
		r.size.y -= corte
		(pa.spr as Sprite2D).region_rect = r
		(pa.spr as Sprite2D).offset.y += corte
		(pa.som as Sprite2D).visible = k < 0.5
	for no in _afundando.keys():
		if not vivos.has(no):
			_soltar(_afundando[no])
			_afundando.erase(no)


## Pássaros: cada pássaro 3D (DesenhoPassaros) vira o sprite da espécie, na mesma posição, direção e animação
## (voo, planar, parado, bicando; pousar e decolar pelo andamento da animação). No ar, fica por cima de tudo e a
## sombra fica no chão, mais clara quanto mais alto ele voa.
func _sincronizar_passaros() -> void:
	var dp = mundo.get("_desenho_passaros")
	if dp == null:
		return
	var vistos := {}
	for id in dp._bandos:
		var esp := ""
		var b: Dictionary = mundo.passaros.bandos.get(id, {})
		if b.is_empty():
			continue
		esp = "passaro_" + String(b.especie)
		if not Catalogo2D.tem(esp):
			continue
		for p3 in dp._bandos[id]:
			var no: Node3D = p3.no
			if not is_instance_valid(no):
				continue
			vistos[no] = true
			if not _passaros.has(no):
				var par := _par(esp)
				if par.is_empty():
					continue
				_passaros[no] = par
			var pa: Dictionary = _passaros[no]
			var acao := String(p3.acao)
			var variante := acao.trim_suffix("<")
			if not variante in ["voo", "planar", "parado", "bicando", "pousar"]:
				variante = "voo"
			var anim: AnimationPlayer = p3.anim
			var q := 0
			if anim != null and anim.current_animation != "" and anim.current_animation_length > 0.0:
				q = clampi(int(anim.current_animation_position / anim.current_animation_length * 8.0), 0, 7)
			var linha := Catalogo2D.linha_do_angulo(pa.m, no.rotation.y)
			var pos := no.global_position
			_por(pa, pos, linha, q, variante)
			var alt := pos.y - Grade.altura_em(Vector2(pos.x, -pos.z))
			var alto := Camera2DJogo.projetar(pos) - Camera2DJogo.projetar(Vector3(pos.x, pos.y - alt, pos.z))
			(pa.som as Sprite2D).offset -= alto                       # a sombra fica no chão
			(pa.som as Sprite2D).modulate.a = clampf(1.0 - alt / 25.0, 0.25, 1.0)
			(pa.spr as Sprite2D).z_index = 20 if alt > 1.0 else 0     # voando: por cima das árvores e construções
	# fase 6: quem morreu despencando (mole, girando) e os adultos indo e voltando do ninho
	var extras: Array = []
	for c in dp._caindo:
		extras.append([c.no, "morto_costas" if bool((c.no as Node3D).get_meta("costas", false)) else "morto", null])
	var dn = mundo.get("_desenho_ninhos")
	if dn != null:
		for v in dn.visitas:
			extras.append([v.no, String(v.acao), v.anim])
	for ex in extras:
		var no: Node3D = ex[0]
		if not is_instance_valid(no):
			continue
		var esp := "passaro_" + String(no.get_meta("passaro", ""))
		if not Catalogo2D.tem(esp):
			continue
		vistos[no] = true
		if not _passaros.has(no):
			var par := _par(esp)
			if par.is_empty():
				continue
			_passaros[no] = par
		var pa: Dictionary = _passaros[no]
		var variante := String(ex[1]).trim_suffix("<")
		if not variante in ["voo", "planar", "parado", "bicando", "pousar", "morto", "morto_costas"]:
			variante = "voo"
		var q := 0
		var anim: AnimationPlayer = ex[2]
		if anim != null and anim.current_animation != "" and anim.current_animation_length > 0.0:
			q = clampi(int(anim.current_animation_position / anim.current_animation_length * 8.0), 0, 7)
		var pos := no.global_position
		_por(pa, pos, Catalogo2D.linha_do_angulo(pa.m, no.rotation.y), q, variante)
		var alt := pos.y - Grade.altura_em(Vector2(pos.x, -pos.z))
		var alto := Camera2DJogo.projetar(pos) - Camera2DJogo.projetar(Vector3(pos.x, pos.y - alt, pos.z))
		(pa.som as Sprite2D).offset -= alto
		(pa.som as Sprite2D).modulate.a = clampf(1.0 - alt / 25.0, 0.25, 1.0)
		(pa.spr as Sprite2D).z_index = 20 if alt > 1.0 else 0
		(pa.spr as Sprite2D).rotation = no.rotation.x * 0.8 if variante.begins_with("morto") else 0.0   # girando na queda
	for no in _passaros.keys():
		if not vistos.has(no):
			(_passaros[no].spr as Sprite2D).rotation = 0.0
			_soltar(_passaros[no])
			_passaros.erase(no)
	_sincronizar_ninhos()


## Fase 6: os ninhos (os pivôs do DesenhoNinhosPassaros, com a mesma posição e o mesmo giro do 3D), ordenados pelo
## próprio pé: a bolsa do lado de cá da copa fica na frente, a do lado de lá, atrás. A taça (na forquilha, dentro da
## copa) só aparece quando a árvore está sem folha (outono avançado e inverno nas que perdem folha; verão seco na
## acácia), como no 3D, onde a folha a esconde. Ninho caído fica no chão e some.
const COPA_RALA := {1: [3], 4: [3], 2: [3], 3: [1]}      ## perfil da folha → estações sem folha

func _sincronizar_ninhos() -> void:
	var dn = mundo.get("_desenho_ninhos")
	if dn == null:
		return
	var vistos := {}
	var raizes: Array = []
	for r in dn.nos.values():
		raizes.append([r.no, String(r.tipo), false])
	for c in dn.caindo:
		raizes.append([c.no, "bolsa" if bool(c.get("bolsa", false)) else "taca", true])
	var est: int = mundo.clima.estacao if mundo.get("clima") != null else 0
	for rz in raizes:
		var raiz: Node3D = rz[0]
		if not is_instance_valid(raiz):
			continue
		var nome := "ninho_" + String(rz[1])
		if not Catalogo2D.tem(nome):
			continue
		var ralo := 1.0
		if rz[1] == "taca" and not bool(rz[2]):
			var t3 := Grade.tile_de_mundo((raiz.get_child(0) as Node3D).global_position) if raiz.get_child_count() > 0 else Vector2i.ZERO
			var o: Dictionary = mundo.gerador.distribuicao.obstaculo(t3)
			if o.is_empty() or not Distribuicao.eh_arvore(String(o.nome)):
				ralo = 1.0                                     # fase 7: ninho no alto do poste/silo, sempre à vista
			else:
				var perfil := Ecossistema.perfil_folha(String(o.get("nome", "")))
				ralo = 1.0 if est in COPA_RALA.get(perfil, []) else 0.0
		for piv: Node3D in raiz.get_children():
			if not piv.has_meta("piv"):
				continue                                       # o raminho até a bolsa (fica de fora no 2D: fino demais)
			vistos[piv] = true
			var pa: Dictionary = _ninhos2d.get(piv, {})
			if pa.is_empty():
				pa = _par(nome)
				if pa.is_empty():
					continue
				_ninhos2d[piv] = pa
			var pos := piv.global_position
			if rz[1] == "bolsa" and not bool(rz[2]):
				pos.y -= 0.34 * piv.scale.y                   # a folha da bolsa foi feita 34 cm acima (ela pende da origem)
			var z_o := pos.z + 0.06 if rz[1] == "taca" and not bool(rz[2]) else NAN   # a taça na frente do tronco
			_por(pa, pos, Catalogo2D.linha_do_angulo(pa.m, piv.global_rotation.y), 0, "", z_o)
			(pa.spr as Sprite2D).scale = Vector2.ONE * piv.scale.x * raiz.scale.x          # cresce na obra, some caído
			(pa.spr as Sprite2D).visible = ralo > 0.5
			(pa.som as Sprite2D).visible = ralo > 0.5 and bool(rz[2])                   # sombra só no chão
	for piv in _ninhos2d.keys():
		if not vistos.has(piv):
			(_ninhos2d[piv].spr as Sprite2D).scale = Vector2.ONE
			_soltar(_ninhos2d[piv])
			_ninhos2d.erase(piv)


## Vida pequena (fase 1 do patch fauna): os mesmos pontos do 3D, na camada própria com o enquadramento do mundo.
func _sincronizar_vida() -> void:
	if _vida2d.vida == null:
		_vida2d.vida = mundo.get("_vida_pequena")
	if _plantas2d.desenho == null:
		_plantas2d.desenho = mundo.get("_desenho_plantas_reagem")
		_plantas2d.plantas = mundo.get("plantas_reagem")
		_plantas2d.ratos = mundo.get("ratos")
	_camada_vida.transform = Transform2D(0.0, scale, 0.0, position)


## Drone de reparo trabalhando numa estrutura: feixe de solda vermelho e faíscas, de tempos em tempos.
func _solda(id: int, nome: String, corpo: Node3D) -> void:
	if not nome.begins_with("drone_reparo"):
		return
	var dr = mundo.get("drones")
	if dr == null or not dr.drones.has(id):
		return
	var d: Dictionary = dr.drones[id]
	if int(d.e) != Drones.E.TRABALHANDO or int(d.get("alvo", -1)) < 0:
		return
	var alvo: Vector3
	if d.tipo == "construtor":                       # patch RTS: solda na obra (o holograma)
		var ob = mundo.get("obras")
		if ob == null or not ob.obras.has(int(d.alvo)):
			return
		alvo = Grade.ponto_mundo(ob.obras[int(d.alvo)].pos, 0.6)
	else:
		if not mundo.mapa.estruturas.has(int(d.alvo)):
			return
		var e: Dictionary = mundo.mapa.estruturas[int(d.alvo)]
		alvo = Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot), 0.8)
	if _t < float(_t_solda.get(id, 0.0)):
		return
	_t_solda[id] = _t + (0.35 if d.tipo == "construtor" else 0.7)
	ef.disparar("reparo", corpo.global_position + Vector3(0, -0.15, 0), alvo, "estrutura", 0.6)


## Boca da arma pelo sprite (meta "boca", por direção desenhada); sem medida: a do 3D (Animador) ou o centro alto.
func _boca_2d(chave, nome: String, origem: Vector3, reserva: Vector3) -> Vector3:
	if not Catalogo2D.tem(nome):
		return reserva
	var m := Catalogo2D.meta(nome)
	if not m.has("boca") or not _linha_de.has(chave):
		return reserva
	var b: Array = m.boca[posmod(int(_linha_de[chave]), (m.boca as Array).size())]
	return origem + Vector3(b[0], b[1], b[2])


## Qual efeito: torre + munição do evento → arma do Efeitos2D.
static func arma_do_tiro(e: Dictionary) -> String:
	var nome := String(e.get("nome", ""))
	var mun := String(e.get("municao", ""))
	if nome == "torre_metralhadora":
		return "perfurante" if mun == "municao_perfurante" else ("carregada" if mun == "municao_carregada" else "metralhadora")
	if nome == "torre_foguetes":
		return "enxame" if mun.contains("enxame") else "foguete"
	if nome == "artilharia":
		return "artilharia"
	if nome == "torre_defesa":
		return "metralhadora" if bool(e.get("bala", false)) else "energia"   # sem energia, atira a munição
	if nome == "torre_energia":
		return "laser"
	return "metralhadora"


# ------------------------------------------------------------------ fios de energia (linha de 1 px com barriga)
func _sincronizar_fios() -> void:
	var df = mundo.get("_fios")
	if df == null:
		return
	var assin: String = str(df._assinatura) + str(df._lista.size()) + "|" + str(df._soltos.size())
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
	for pts in df._soltos:                             # fase 7: cabo roído, as pontas caídas até o chão
		var l := Line2D.new()
		l.width = 1.0
		l.default_color = Color(0.07, 0.06, 0.06, 0.95)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for p in pts:
			l.add_point(Camera2DJogo.projetar(p))
		fios.add_child(l)


# ------------------------------------------------------------------ marcadores de porta (o que o MarcadorPortas pinta no 3D)
func _sincronizar_portas() -> void:
	if _marcadores.is_empty() or Engine.get_process_frames() % 60 == 0:
		_marcadores = []
		for n in mundo.get_children():
			if n is DesenhoPortas:
				_marcadores.append(n._marcador)          # aviso de porta solta das máquinas postas
		var ctl = mundo.get("controle")
		if ctl != null and ctl.fantasma != null:
			_marcadores.append(ctl.fantasma._marcador)    # verde/vermelho do que se vai construir
	if _mat_porta.is_empty():
		for f in 2:
			var m := ShaderMaterial.new()
			m.shader = preload("res://versao2d/marcador_porta_2d.gdshader")
			m.set_shader_parameter("fluido", float(f))
			_mat_porta.append(m)
	var k := 0
	const L := MarcadorPortas.LADO * 0.5
	for mp: MarcadorPortas in _marcadores:
		if not is_instance_valid(mp) or not mp.is_visible_in_tree():
			continue
		var mm := mp.multimesh
		for i in mm.instance_count:
			var t := mp.global_transform * mm.get_instance_transform(i)
			if k >= _portas.size():
				var pg := Polygon2D.new()
				pg.texture = _branco()
				pg.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
				objetos.add_child(pg)
				_portas.append(pg)
			var pg: Polygon2D = _portas[k]
			k += 1
			pg.visible = true
			# ordena pela borda sul do tile: fica por cima das pedras do próprio tile e embaixo do que está mais ao sul
			var ordem := Camera2DJogo.projetar(Vector3(t.origin.x, 0.0, t.origin.z + 0.49))
			pg.position = ordem
			pg.polygon = PackedVector2Array([Camera2DJogo.projetar(t * Vector3(-L, 0, -L)) - ordem, Camera2DJogo.projetar(t * Vector3(L, 0, -L)) - ordem,
					Camera2DJogo.projetar(t * Vector3(L, 0, L)) - ordem, Camera2DJogo.projetar(t * Vector3(-L, 0, L)) - ordem])
			pg.color = mm.get_instance_color(i)
			pg.material = _mat_porta[1 if mm.get_instance_custom_data(i).r > 0.5 else 0]
	for j in range(k, _portas.size()):
		_portas[j].visible = false


static var _tex_branca: Texture2D
static func _branco() -> Texture2D:
	if _tex_branca == null:
		var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		im.fill(Color.WHITE)
		_tex_branca = ImageTexture.create_from_image(im)
	return _tex_branca


# ------------------------------------------------------------------ obras encomendadas (patch RTS): holograma do sprite
## O mesmo DesenhoObras do 3D: cada obra tem o modelo instanciado no lugar; aqui vira o sprite da peça tingido
## (azul na fila, âmbar esperando recurso, vermelho remoção), pulsando; soldando, fica mais aceso.
func _sincronizar_obras() -> void:
	var dob = mundo.get("_desenho_obras")
	var ob = mundo.get("obras")
	var vistos := {}
	if dob != null and ob != null:
		for id in dob._nos:
			var n: Dictionary = dob._nos[id]
			var no: Node3D = n.get("no")
			if no == null or not is_instance_valid(no) or not ob.obras.has(id):
				continue
			var nome := _nome_do_arquivo(no)
			if not Catalogo2D.tem(nome):
				continue
			vistos[id] = true
			var s: Sprite2D = _obra_spr.get(id)
			if s == null:
				s = Sprite2D.new()
				s.centered = false
				s.region_enabled = true
				fantasmas.add_child(s)
				_obra_spr[id] = s
			var m := Catalogo2D.meta(nome)
			var g := no.global_transform
			s.texture = Catalogo2D.folha(nome, "atras" if String(m.get("animacao", "")) == "braco" else "")
			s.region_rect = Catalogo2D.regiao(m, Catalogo2D.linha_do_angulo(m, g.basis.get_euler().y), 0)
			s.position = Camera2DJogo.projetar(g.origin)
			s.offset = -Vector2(m.ancora[0], m.ancora[1])
			var o: Dictionary = ob.obras[id]
			var c: Color = DesenhoObras.VERMELHO if o.acao == "remover" else (DesenhoObras.AMBAR if o.espera else DesenhoObras.AZUL)
			var soldando: bool = float(o.prog) > 0.0
			var a := (0.62 if soldando else 0.45) + 0.08 * sin(_t * 3.0 + float(id))
			s.modulate = Color(c.r * 0.55 + 0.45, c.g * 0.55 + 0.45, c.b * 0.55 + 0.45, a)
	for id in _obra_spr.keys():
		if not vistos.has(id):
			(_obra_spr[id] as Node).queue_free()
			_obra_spr.erase(id)


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
				var arma := arma_do_tiro(e)
				var id_t := int(e.get("torre", -1))
				_tiro_t[id_t] = _t
				var no_t: Node3D = (mundo.get("_nos") as Dictionary).get(id_t)
				var reserva: Vector3 = dc._boca(e, 1.25) if dc != null else Grade.ponto_mundo(e.de, 1.25)
				var de: Vector3 = _boca_2d(id_t, String(e.get("nome", "")), no_t.global_position, reserva) if no_t != null else reserva
				var alvo := _especie(int(e.get("aranha", -1))) if int(e.get("aranha", -1)) >= 0 else ("estrutura" if int(e.get("ninho", -1)) >= 0 else "chao")
				var alto := 0.6 if alvo != "chao" else 0.0
				var projetil := bool(e.get("projetil", false))
				ef.disparar(arma, de, Grade.ponto_mundo(e.para, alto), alvo, float(e.get("dur", 0.0)), not projetil)
			"drone_tiro":
				var chave := "dr%d" % int(e.get("id", -1))
				var p_dr := Grade.ponto_mundo(e.de, float(e.get("alt", 2.4)))
				var de_dr := _boca_2d(chave, "drone_defesa", p_dr, p_dr)
				var ar_pos: Vector2 = e.para
				ef.disparar("drone", de_dr, Grade.ponto_mundo(ar_pos, 0.6), _especie(int(e.get("aranha", -1))))
			"cuspe":
				# a gosma sai da boca da larva (meta "boca" do sprite, se houver) e cai onde a Colonia diz; o respingo
				# vem no evento "respingo", quando ela chega
				var pl: Vector3 = Grade.ponto_mundo(e.de, 0.3)
				var de_l := _boca_2d("", LARVA, pl, pl)
				ef.disparar("cuspe", de_l, Grade.ponto_mundo(e.para, 0.1), "estrutura", float(e.get("dur", 0.6)), false)
			"respingo":
				ef.impacto("cuspe", Grade.ponto_mundo(e.pos, 0.1), "estrutura")
			"salto":
				ef.arco(Grade.ponto_mundo(e.de, 0.6), Grade.ponto_mundo(e.para, 0.6))
			"aranha_morta":
				ef.morte(Grade.ponto_mundo(e.pos, 0.5), String(e.get("especie", "aranha")))
			"explosao":
				ef.explosao(Grade.ponto_mundo(e.pos, 0.0), clampf(float(e.raio) / 2.5, 0.5, 1.6))
			"pulso":
				_anel(Grade.ponto_mundo(e.pos, 0.05), float(e.raio), Color(0.75, 0.55, 1.0))


## "aranha" ou "larva" (sangue e lascas do impacto) pelo id do bicho na Colonia.
func _especie(id: int) -> String:
	var dc = mundo.get("_desenho_colonia")
	if dc != null and dc.colonia != null and dc.colonia.aranhas.has(id):
		return String(dc.colonia.aranhas[id].get("especie", "aranha"))
	return "aranha"


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
