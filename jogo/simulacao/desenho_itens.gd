class_name DesenhoItens
extends Node3D
## Itens nas esteiras (e o que cada braço segura): um MultiMesh por tipo de item, refeito a partir da Fabrica.
## Para caber no celular:
##  - só os caminhos cuja caixa encosta na área vista pela câmera;
##  - com a câmera longe (> DIST_ESCONDE) os itens nem são desenhados (seriam pontinhos);
##  - os itens das esteiras só são refeitos quando a simulação andou (30 Hz) ou a câmera mexeu — a tela pode rodar
##    a 60+; só o item na garra de cada braço é reposto a cada quadro (a garra anda com a animação);
##  - posição calculada direto num buffer de floats (uma chamada por tipo de item), numa passada só.

const DIST_ESCONDE := 50.0

var fabrica: Fabrica
var mapa: MapaOcupacao
var garra: Callable              ## id do braço → ponto da garra no mundo (o item segue o modelo animado)
var _mm: Dictionary = {}          ## item → MultiMeshInstance3D
var _base: Dictionary = {}        ## item → quantas instâncias são itens de esteira (as das garras vêm depois delas)
var custo_us := 0                 ## tempo do último quadro (medição)
var _ultimo := ""                 ## passo da simulação + câmera do último desenho das esteiras
var _geo: Dictionary = {}         ## índice do caminho → [caminho, versão do nível, altura do chão por tile, curva por tile]


func _process(_d: float) -> void:
	if fabrica == null:
		return
	var cam := get_viewport().get_camera_3d() as CameraJogo
	var chave := "%d|%s|%s" % [fabrica.passos, cam.alvo if cam else "", cam.distancia if cam else ""]
	var t0 := Time.get_ticks_usec()
	if chave != _ultimo:
		_ultimo = chave
		_desenhar()
	if not fabrica.bracos.is_empty():
		_desenhar_garras(cam)                    # a garra anda a cada quadro
	custo_us = Time.get_ticks_usec() - t0


## Itens das esteiras: posição (x, y, z) e tipo de cada item visível em vetores locais, depois um buffer por tipo.
func _desenhar() -> void:
	if fabrica == null:
		return
	var cam := get_viewport().get_camera_3d() as CameraJogo
	var pos := PackedFloat32Array()
	var tipo := PackedInt32Array()
	var tipos: Array[String] = []
	var indice := {}
	if cam == null or cam.distancia <= DIST_ESCONDE:
		var vista := _area_vista(cam)
		for ci in fabrica.caminhos.size():
			var c: Dictionary = fabrica.caminhos[ci]
			if vista.has_area() and not vista.intersects(c.caixa):
				continue
			var est: EsteiraCaminho = c.esteira
			var n: int = c.tiles.size()
			var oculto: Array = c.get("oculto", [])
			var papel: Array = c.get("papel", [])
			var lat := _laterais(ci, est.velocidade)
			var geo := _geometria(ci, c)
			var alt: PackedFloat64Array = geo[2]
			var curvas: Array = geo[3]
			var acum := 0.0
			for i in est.itens.size():
				acum += est.espacos[i]
				var bruto := est.comprimento - acum - EsteiraCaminho.ESPACO * 0.5
				var s := clampf(bruto, 0.0, float(n) - 1e-4)
				var k := int(s)
				var f := s - k
				if not oculto.is_empty() and (oculto[k] or (papel[k] == "entrada" and f > 0.52) or (papel[k] == "saida" and f < 0.48)):
					continue                                  # debaixo da terra (ou dentro do pórtico)
				var t: Vector2i = c.tiles[k]
				var entra: int = c.entra[k]
				var sai: int = c.sai[k]
				var p: Vector2
				var sobe := 0.0
				if bruto > float(n):
					# rampa de junção: passa da borda, sobe por cima do trilho da vizinha e deita nela
					var e := bruto - float(n)
					p = Vector2(t.x + 0.5, t.y + 0.5) + Vector2(Grade.DIRECOES[sai]) * (0.5 + e)
					sobe = Fabrica.altura_calha(e)
				elif sai < 0:
					# fim de linha: o item para encostado no para-choque (lado de dentro), não por cima dele
					p = Vector2(t.x + 0.5, t.y + 0.5) + Vector2(Grade.DIRECOES[entra]) * (f * 0.74 - 0.5)
				elif sai == entra:
					p = Vector2(t.x + 0.5, t.y + 0.5) + Vector2(Grade.DIRECOES[entra]) * (f - 0.5)
				else:
					var cv: Array = curvas[k]                     # = Fabrica.ponto_no_tile, com o arco guardado
					p = (cv[0] as Vector2) + Vector2.from_angle(float(cv[1]) + float(cv[2]) * f) * 0.5
				for j in lat:
					if absf(acum - j.x) < 0.12:
						p += j.dir * j.y                          # acabou de entrar pela lateral: termina de deslizar
						break
				var nv: Vector2i = c.niveis[k]
				var item: String = est.itens[i]
				if not indice.has(item):
					indice[item] = tipos.size()
					tipos.append(item)
				tipo.append(indice[item])
				pos.append(p.x)
				pos.append(0.16 + sobe + lerpf(nv.x, nv.y, f) * 0.5 + alt[k])
				pos.append(-p.y)
	for ci in _geo.keys():
		if ci >= fabrica.caminhos.size():
			_geo.erase(ci)
	# 2ª passada: um buffer por tipo. Os índices entram agrupados por tipo numa passada só (ordem de cada tipo mantida).
	var nt := tipos.size()
	var inicio := PackedInt32Array()
	inicio.resize(nt + 1)
	for ti in tipo:
		inicio[ti + 1] += 1
	for ti in nt:
		inicio[ti + 1] += inicio[ti]
	var ordem := PackedInt32Array()
	ordem.resize(tipo.size())
	var prox := inicio.duplicate()
	for i in tipo.size():
		ordem[prox[tipo[i]]] = i
		prox[tipo[i]] += 1
	_base.clear()
	var reserva := fabrica.bracos.size()                 # lugar para o item de cada garra depois dos da esteira
	for ti in nt:
		var mmi := _instancia(tipos[ti])
		if mmi == null:
			continue
		var n := inicio[ti + 1] - inicio[ti]
		var mm := mmi.multimesh
		if mm.instance_count < n + reserva:
			mm.instance_count = (n + reserva) * 2
		var buf := PackedFloat32Array()
		buf.resize(mm.instance_count * 12)
		var w := 0
		for j in range(inicio[ti], inicio[ti + 1]):
			var i := ordem[j]
			buf[w] = 1.0
			buf[w + 3] = pos[i * 3]
			buf[w + 5] = 1.0
			buf[w + 7] = pos[i * 3 + 1]
			buf[w + 10] = 1.0
			buf[w + 11] = pos[i * 3 + 2]
			w += 12
		mm.buffer = buf
		mm.visible_instance_count = n
		_base[tipos[ti]] = n
	for item in _mm:
		if not indice.has(item):
			(_mm[item] as MultiMeshInstance3D).multimesh.visible_instance_count = 0


## Desempenho (2026-11-11): o que não muda enquanto o caminho existe — a altura do chão de cada tile (antes uma
## consulta com trava ao gerador por item, a cada passo) e o arco de cada curva — fica guardado por caminho. Refaz se
## a Fabrica remontou (outro dicionário no índice) ou o nível de algum tile mudou (aplainar, água).
func _geometria(ci: int, c: Dictionary) -> Array:
	var v := Grade.gerador.versao_nivel if Grade.gerador != null else 0
	var g: Array = _geo.get(ci, [])
	if not g.is_empty() and is_same(g[0], c) and int(g[1]) == v:
		return g
	var alt := PackedFloat64Array()
	var curvas := []
	for k in c.tiles.size():
		var t: Vector2i = c.tiles[k]
		alt.append(Grade.altura_chao(t))
		var entra: int = c.entra[k]
		var sai: int = c.sai[k]
		if sai < 0 or sai == entra:
			curvas.append([])
			continue
		var centro := Vector2(t) + Vector2(0.5, 0.5)
		var din := Vector2(Grade.DIRECOES[entra])
		var a := centro - din * 0.5
		var dout := Vector2(Grade.DIRECOES[sai])
		var b := centro + dout * 0.5
		var canto := a + dout * 0.5
		var ang0 := (a - canto).angle()
		var ang1 := (b - canto).angle()
		curvas.append([canto, ang0, angle_difference(ang0, ang1)])
	g = [c, v, alt, curvas]
	_geo[ci] = g
	return g


## O item que cada braço segura vai preso na garra (posição real do modelo animado): entra depois dos itens de
## esteira do mesmo tipo, a cada quadro.
func _desenhar_garras(cam: CameraJogo) -> void:
	var extra := {}
	if cam == null or cam.distancia <= DIST_ESCONDE:
		for id in fabrica.bracos:
			var b: Braco = fabrica.bracos[id]
			if b.segurando == "" or not mapa.estruturas.has(id):
				continue
			var e: Dictionary = mapa.estruturas[id]
			var g: Vector3 = garra.call(id) if garra.is_valid() else Vector3.INF
			if g == Vector3.INF:
				var fr := Vector2(Grade.DIRECOES[Construtor.fluxo_da_rot(e.rot)])
				var cc := Vector2(e.minimo) + Vector2(0.5, 0.5)
				var a := clampf(b.fase() * 2.0, 0.0, 1.0)
				var p := (cc - fr * 0.75).lerp(cc + fr * 0.75, a)
				g = Grade.ponto_mundo(p, 0.55 + 0.25 * sin(a * PI))
			var mmi := _instancia(b.segurando)
			if mmi == null:
				continue
			var i: int = int(_base.get(b.segurando, 0)) + int(extra.get(b.segurando, 0))
			var mm := mmi.multimesh
			if i >= mm.instance_count:
				mm.instance_count = (i + 1) * 2
				_ultimo = ""                         # crescer apaga o buffer: as esteiras deste tipo voltam no próximo quadro
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(g.x, g.y - 0.11, g.z)))
			extra[b.segurando] = i + 1 - int(_base.get(b.segurando, 0))
	for item in _mm:
		(_mm[item] as MultiMeshInstance3D).multimesh.visible_instance_count = int(_base.get(item, 0)) + int(extra.get(item, 0))


## Itens que entraram pela lateral deste caminho há pouco: (posição esperada agora, recuo lateral restante) + direção.
## O item foi posto no eixo da esteira, mas o desenho o mostra ainda vindo da rampa e desliza até o eixo em ~0,13 s.
func _laterais(ci: int, vel: float) -> Array:
	var out := []
	for j in fabrica.juncoes:
		if j.caminho != ci:
			continue
		var dt := float(fabrica.passos - int(j.passo)) / 30.0
		var resto := 0.25 - vel * dt
		if resto > 0.0:
			out.append({"x": float(j.pos) - vel * dt, "y": resto, "dir": -(j.lado as Vector2)})
	return out


## Quadrado (plano da grade) que cobre o que a câmera vê, com folga.
func _area_vista(cam: CameraJogo) -> Rect2:
	if cam == null:
		return Rect2()
	var tam := get_viewport().get_visible_rect().size
	var meia_alt := cam.distancia * tan(deg_to_rad(cam.fov) / 2.0) / maxf(sin(cam.inclinacao()), 0.3)
	var raio := Vector2(meia_alt * tam.x / maxf(tam.y, 1.0), meia_alt).length() * 1.15
	var c := Vector2(cam.alvo.x, -cam.alvo.z)
	return Rect2(c - Vector2(raio, raio), Vector2(raio, raio) * 2.0)


## Troca o matiz da parte colorida (cristal/tijolo) mantendo saturação e brilho: pacote de automação = frasco do
## pacote de pesquisa com líquido âmbar; briquete = tijolos na cor da biomassa (o ícone é derivado do mesmo jeito,
## ferramentas/derivar_icone.gd).
static func _tingir(malha: Mesh, matiz: float) -> void:
	for s in malha.get_surface_count():
		var m := malha.surface_get_material(s) as ShaderMaterial
		if m == null or not m.resource_name.begins_with("P_Cristal") and not m.resource_name.begins_with("P_Tijolo"):
			continue
		m = m.duplicate()
		var c: Color = m.get_shader_parameter("cor")
		m.set_shader_parameter("cor", Color.from_hsv(matiz, c.s, c.v, c.a))
		var e = m.get_shader_parameter("cor_emissao")
		if e is Color:
			m.set_shader_parameter("cor_emissao", Color.from_hsv(matiz, e.s, e.v, e.a))
		malha.surface_set_material(s, m)


func _instancia(item: String) -> MultiMeshInstance3D:
	if _mm.has(item):
		return _mm[item]
	var info: Dictionary = Registro.itens.get(item, {})
	var base: String = info.get("modelo_de", item)          # item sem modelo próprio usa o de outro (com outra cor)
	if not Registro.modelos.has(base):
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Materiais.malha_de(load(Registro.modelos[base].modelo))
	if info.has("matiz"):
		_tingir(mm.mesh, float(info.matiz))
	mm.instance_count = 64
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # sombra de item miúdo não compensa
	add_child(mmi)
	_mm[item] = mmi
	return mmi
