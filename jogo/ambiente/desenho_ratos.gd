class_name DesenhoRatos
extends Node3D
## Patch fauna, fase 5 (docs/PLANO_FAUNA.md): o desenho dos ratos (a lógica é Ratos).
##  tocas  buraco escuro no chão com a terra cavada em volta (malha feita por código, MultiMesh).
##  ratos  o modelo da espécie (rato_pardo / rato_saltador.glb, com esqueleto e as ações), só os que estão fora da
##         toca e perto da câmera: sai do buraco subindo, anda no ritmo da distância andada, fareja, come sentado,
##         cava, foge correndo (o saltador aos pulos), entra afundando no buraco. Quando morre, o mesmo nó deita de
##         lado ("morto") e vira a carcaça (DesenhoCarcacas.corpos).
## Sons perto da câmera: a voz (evento "chiou" e quando foge), ao acaso o trinado ou o guincho, e o raspar de quem
## cava.

const ESCALA := 1.5               ## o rato perto do capim do jogo (em escala real o capim de 40 cm o esconde inteiro)
const MAX_RATOS := 30
const CICLO_M := {"pardo": 0.09, "saltador": 0.16}   ## m andados por ciclo de "andar" (sem escorregar o pé)

const LADO_TRILHA := 64
const RES_TRILHA := 4              ## pixels por tile (25 cm): a abertura em volta do rato cabe no bicho

var ratos: Ratos
var foco_de: Callable              ## () -> Vector2: onde a câmera olha (o mundo põe)
var nos: Dictionary = {}           ## id do rato → {no, mod, anim, acao, ult: Vector2, esp}
var _mm_toca: MultiMeshInstance3D
var _versao := ""
var _img_trilha: Image            ## o que vai para o shader: a trilha + os ratos de agora
var _img_base: Image              ## só a trilha (refeita quando a passagem muda)
var _tex_trilha: ImageTexture
var _trilha_v := -1
var _trilha_c := Vector2i(1 << 30, 0)
var _t_trilha := 0.0


static func _modelo(esp: String) -> PackedScene:
	var m: Dictionary = Registro.modelos.get("rato_" + esp, {})
	return load(m.modelo) if not m.is_empty() else null


## Um rato: raiz no chão virada pelo rumo, o modelo dentro (olha para +X, como o rumo 0 do jogo).
static func _montar(esp: String) -> Dictionary:
	var cena := _modelo(esp)
	if cena == null:
		return {}
	var raiz := Node3D.new()
	raiz.set_meta("rato", esp)                     # o 2D desenha o sprite da espécie (também o corpo morto)
	var mod: Node3D = cena.instantiate()
	mod.scale = Vector3.ONE * ESCALA
	raiz.add_child(mod)
	Materiais.converter(mod)
	var anims := mod.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = anims[0] if not anims.is_empty() else null
	if anim != null:
		for nome in ["andar", "correr", "farejar", "comer", "cavar"]:
			if anim.has_animation(nome):
				anim.get_animation(nome).loop_mode = Animation.LOOP_LINEAR
	return {"no": raiz, "mod": mod, "anim": anim, "acao": "", "esp": esp}


static func _parar_morto(anim: AnimationPlayer) -> void:
	if anim != null and anim.has_animation("morto"):
		anim.play("morto")
		anim.seek(anim.current_animation_length, true)
		anim.pause()


## Corpo do rato morto, deitado de lado (a carcaça recriada ao carregar o jogo; `variante` = a espécie).
static func corpo_morto(pos: Vector3, ang: float, variante := "pardo") -> Node3D:
	var r := _montar(variante if variante != "" else "pardo")
	if r.is_empty():
		return null
	var no: Node3D = r.no
	no.position = pos
	no.rotation.y = ang
	no.set_meta("pronta", true)
	no.ready.connect(func(): _parar_morto(r.anim), CONNECT_ONE_SHOT)
	return no


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malha_toca()
	_mm_toca = MultiMeshInstance3D.new()
	_mm_toca.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/shaders/planta_pequena.gdshader")
	_mm_toca.material_override = mat
	_mm_toca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_toca)


## Toca: terra solta cavada e jogada de um lado (monte baixo e irregular, granulado: torrões), em volta de um buraco
## escuro cujo fundo desce; nada fica por cima do chão além da terra. UV.y = 1 (a cor vem do vértice).
static func malha_toca() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var fundo := Color(0.015, 0.012, 0.01)
	# anéis: raio (m), altura (m), cor
	var aneis := [[0.055, -0.07, fundo], [0.06, -0.012, Color(0.035, 0.027, 0.02)], [0.072, 0.018, Color(0.09, 0.07, 0.05)],
			[0.11, 0.024, Color(0.12, 0.09, 0.065)], [0.15, 0.008, Color(0.1, 0.08, 0.06)], [0.18, -0.004, Color(0.08, 0.065, 0.05)]]
	var pts: Array = []
	for k in aneis.size():
		var a: Array = aneis[k]
		var anel: Array = []
		for i in n:
			var ang := TAU * i / n
			var h1 := fposmod(sin(i * 12.9898 + k * 78.233) * 43758.5453, 1.0)
			var h2 := fposmod(sin(i * 39.346 + k * 11.135) * 24634.634, 1.0)
			var monte := 1.0 + 0.7 * maxf(0.0, cos(ang - 0.6))          # a terra cavada fica de um lado
			var r := float(a[0]) * (lerpf(1.0, monte, smoothstep(0.065, 0.12, float(a[0])))) * (0.85 + 0.3 * h1)
			var y := float(a[1]) * (monte if float(a[1]) > 0.0 else 1.0) + (0.006 * (h2 - 0.5) if k >= 2 else 0.0)
			var cor: Color = (a[2] as Color) * (0.8 + 0.4 * h2)                  # torrões: cada vértice num tom
			anel.append([Vector3(cos(ang) * r, y, sin(ang) * r), cor])
		pts.append(anel)
	for k in pts.size() - 1:
		for i in n:
			var j := (i + 1) % n
			for v in [pts[k][i], pts[k + 1][j], pts[k][j], pts[k][i], pts[k + 1][i], pts[k + 1][j]]:
				st.set_color(v[1])
				st.set_uv(Vector2(0, 1.0))
				st.add_vertex(v[0])
	var c := Vector3(0, -0.07, 0)
	for i in n:
		var j := (i + 1) % n
		for v in [c, pts[0][i][0], pts[0][j][0]]:
			st.set_color(fundo)
			st.set_uv(Vector2(0, 1.0))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Mapa global da trilha (64×64 tiles em volta da câmera, 4 px por tile; R = capim deitado): o capim
## (grama.gdshader) e o chão do 2D leem. A base (trilha e boca das tocas) refaz quando a passagem muda ou a câmera
## anda 8 tiles; por cima, 15 vezes por segundo, a abertura em volta de cada rato fora da toca.
func _trilha(delta: float) -> void:
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	var c := Vector2i(foco.floor()) - Vector2i(LADO_TRILHA / 2, LADO_TRILHA / 2)
	var lado := LADO_TRILHA * RES_TRILHA
	if _img_trilha == null:
		_img_base = Image.create(lado, lado, false, Image.FORMAT_RG8)
		_img_trilha = Image.create(lado, lado, false, Image.FORMAT_RG8)
		_tex_trilha = ImageTexture.create_from_image(_img_trilha)
		RenderingServer.global_shader_parameter_set("trilha_mapa", _tex_trilha)
	var base_mudou := false
	if ratos.versao_passagem != _trilha_v or (c - _trilha_c).length() >= 8.0 or ratos.tocas.size() != int(get_meta("_n_tocas", -1)):
		_trilha_v = ratos.versao_passagem
		_trilha_c = c
		set_meta("_n_tocas", ratos.tocas.size())
		_img_base.fill(Color(0, 0, 0))
		for cel: Vector2i in ratos.passagem:                # Ratos.TRILHA_RES = RES_TRILHA: uma célula, um pixel
			var p := cel - c * RES_TRILHA
			if p.x >= 0 and p.y >= 0 and p.x < lado and p.y < lado:
				var v := float(ratos.passagem[cel])
				_img_base.set_pixel(p.x, p.y, Color(v, 0, 0))
		for tc in ratos.tocas.values():                      # a boca da toca: capim baixo em volta (sem gastar o chão)
			_carimbo(_img_base, (tc.pos as Vector2) - Vector2(c), 0.45, 0.9)
		RenderingServer.global_shader_parameter_set("trilha_origem", Vector3(c.x, c.y, LADO_TRILHA))
		base_mudou = true
	_t_trilha -= delta
	if _t_trilha > 0.0 and not base_mudou:
		return
	_t_trilha = 1.0 / 15.0
	_img_trilha.copy_from(_img_base)
	for r in ratos.ratos.values():
		if r.estado != Ratos.E.TOCA:
			_carimbo(_img_trilha, (r.pos as Vector2) - Vector2(_trilha_c), 0.38, 1.0)
	_tex_trilha.update(_img_trilha)


## Mancha redonda e suave (raio em m) no canal G do mapa (o capim abre; o chão não gasta), em `p` (tiles a partir do
## canto do mapa).
func _carimbo(img: Image, p: Vector2, raio: float, v: float) -> void:
	var cp := p * RES_TRILHA
	var r := raio * RES_TRILHA
	var lado := img.get_width()
	for y in range(floori(cp.y - r), ceili(cp.y + r) + 1):
		for x in range(floori(cp.x - r), ceili(cp.x + r) + 1):
			if x < 0 or y < 0 or x >= lado or y >= lado:
				continue
			var k := 1.0 - clampf(Vector2(x + 0.5, y + 0.5).distance_to(cp) / r, 0.0, 1.0)
			if k <= 0.0:
				continue
			var a := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(a.r, maxf(a.g, v * smoothstep(0.0, 0.6, k)), 0))


func _process(delta: float) -> void:
	if ratos == null:
		return
	_trilha(delta)
	_ratos(delta)
	_sons(delta)
	var chave := "%d|%d" % [ratos.tocas.size(), ratos._prox]
	if chave != _versao:
		_versao = chave
		var mm := _mm_toca.multimesh
		mm.instance_count = ratos.tocas.size()
		var i := 0
		for tc in ratos.tocas.values():
			var p: Vector2 = tc.pos
			var b := Basis(Vector3.UP, float(int(tc.id) * 2.39996))
			mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, Grade.altura_em(p), -p.y)))
			i += 1


func _tocar(n: Dictionary, nome: String, vel := 1.0) -> void:
	var anim: AnimationPlayer = n.anim
	if anim == null or not anim.has_animation(nome):
		return
	anim.speed_scale = vel
	if n.acao == nome:
		return
	n.acao = nome
	anim.play(nome, 0.1)


func _ratos(delta: float) -> void:
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	var vistos := {}
	for r in ratos.ratos.values():
		if r.estado == Ratos.E.TOCA or (r.pos as Vector2).distance_to(foco) > 40.0 or vistos.size() >= MAX_RATOS:
			continue
		vistos[r.id] = true
		var n: Dictionary = nos.get(r.id, {})
		if n.is_empty():
			n = _montar(String(r.get("especie", "pardo")))
			if n.is_empty():
				continue
			add_child(n.no)
			n.ult = r.pos
			nos[r.id] = n
		var p: Vector2 = r.pos
		var no: Node3D = n.no
		var y := Grade.altura_em(p)
		match int(r.estado):
			Ratos.E.SAINDO:                                   # sobe do buraco
				y -= 0.14 * clampf(float(r.t) / float(Registro.fauna.ratos.get("sair_s", 0.8)), 0.0, 1.0)
				_tocar(n, "andar", 0.6)
			Ratos.E.ENTRANDO:                                 # afunda no buraco
				y -= 0.14 * (1.0 - clampf(float(r.t) / float(Registro.fauna.ratos.get("entrar_s", 0.6)), 0.0, 1.0))
				_tocar(n, "andar", 0.6)
			Ratos.E.ANDANDO:
				var andou := p.distance_to(n.ult)
				_tocar(n, "andar", clampf(andou / maxf(delta, 1e-4) / float(CICLO_M.get(n.esp, 0.1)) / 2.0, 0.2, 3.0))
			Ratos.E.FUGINDO:
				_tocar(n, "correr", 1.6 if n.esp == "saltador" else 2.2)
			Ratos.E.FAREJANDO:
				_tocar(n, "farejar")
			Ratos.E.COMENDO:
				_tocar(n, "comer")
			Ratos.E.CAVANDO:
				_tocar(n, "cavar", 1.5)
		n.ult = p
		no.position = Vector3(p.x, y, -p.y)
		no.rotation.y = lerp_angle(no.rotation.y, float(r.rumo), clampf(delta * 12.0, 0.0, 1.0))
	for id in nos.keys():
		if vistos.has(id):
			continue
		var n: Dictionary = nos[id]
		nos.erase(id)
		if ratos.mortos.has(id) and is_instance_valid(n.no):
			# morreu: o mesmo nó deita de lado e espera o DesenhoCarcacas adotar (vira a carcaça)
			_parar_morto(n.anim)
			(n.no as Node).set_meta("bicho", id)
			(n.no as Node).set_meta("pronta", true)
			DesenhoCarcacas.corpos[id] = n.no
			continue
		if is_instance_valid(n.no):
			(n.no as Node).queue_free()


func _sons(delta: float) -> void:
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	for ev in ratos.eventos:
		if ev.tipo in ["chiou", "fugiu"] and (ev.pos as Vector2).distance_to(foco) < 15.0:
			Som.tocar("rato_chiado" if randf() < 0.5 else "rato_guincho", Grade.ponto_mundo(ev.pos, 0.1), -12.0)
	for r in ratos.ratos.values():
		if r.estado != Ratos.E.CAVANDO or (r.pos as Vector2).distance_to(foco) > 12.0:
			continue
		var n: Dictionary = nos.get(r.id, {})
		if n.is_empty():
			continue
		n.t_som = float(n.get("t_som", 0.0)) - delta
		if float(n.t_som) <= 0.0:
			n.t_som = 1.25
			Som.tocar("rato_cavar", Grade.ponto_mundo(r.pos), -14.0)
