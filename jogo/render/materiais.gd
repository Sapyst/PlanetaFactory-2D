class_name Materiais
## Troca os StandardMaterial3D que vêm do .glb pelo material único do jogo (material_pf.gdshader),
## mantendo cor/emissão e ligando o efeito certo pelo nome do material (P_Esteira rola, P_Cristal pulsa…).
## Materiais iguais são compartilhados (cache) — essencial para o desenho em lote no celular.

const SHADER := preload("res://render/shaders/material_pf.gdshader")
## Só o cristal das construções usa `instance uniform trabalho` (brilho por objeto): quem tem esse uniform reserva
## espaço no buffer global, então o resto do jogo fica no shader sem ele (ver material_pf.gdshader).
const SHADER_CRISTAL := preload("res://render/shaders/material_pf_cristal.gdshader")
const VELOCIDADE_ESTEIRA := 1.875
## Lona que rola pelo shader (m/s = tiles/s, igual à velocidade da esteira da classe): básica, rápida (logistica_3),
## expressa (logistica_4) e quântica (logistica_5).
const ROLAGEM := {"P_Esteira": VELOCIDADE_ESTEIRA, "P_EsteiraRapida": VELOCIDADE_ESTEIRA * 2.0,
		"P_EsteiraExpressa": VELOCIDADE_ESTEIRA * 3.0, "P_EsteiraQuantica": VELOCIDADE_ESTEIRA * 4.0}
## Lona de cada classe, para a esteira se distinguir de longe (a básica fica no aço do .glb). O encardido vem do shader.
const COR_LONA := {"P_EsteiraRapida": Color(0.42, 0.07, 0.05), "P_EsteiraExpressa": Color(0.09, 0.20, 0.40),
		"P_EsteiraQuantica": Color(0.27, 0.07, 0.50)}

static var _cache: Dictionary = {}

## Folhagem das árvores por receita: perfil da estação no shader (0 perene, 1 caduca laranja, 2 salgueiro,
## 3 acácia, 4 caduca amarela).
const PERFIL_FOLHA := {"P_FolhaPerene": 0, "P_FolhaCaduca": 1, "P_FolhaSalgueiro": 2, "P_FolhaSeca": 3, "P_FolhaBetula": 4}


## `uv2` = a malha tem 2º canal de UV (modelo texturizado: a lona da esteira rola por ele).
## `carbonizada` = versão queimada (árvore em pé carbonizada ou caída): tudo carvão, sem folha.
static func material(origem: Material, vento := 0.0, boiar := 0.0, uv2 := false, carbonizada := false) -> Material:
	if not (origem is BaseMaterial3D):
		return origem
	var nome := origem.resource_name
	var cor_nome := nome
	nome = nome.get_slice(".", 0)          # P_Fogo.001 (paleta do conversor: um material por cor) → efeito de P_Fogo
	var b := origem as BaseMaterial3D
	var tex := b.albedo_texture
	# a cor entra na chave: P_Fogo de modelos diferentes pode ter cor diferente com o mesmo nome
	var chave := "%s|%s|%.2f|%.2f|%s|%d|%s" % [cor_nome, b.albedo_color.to_html(), vento, boiar, uv2, tex.get_instance_id() if tex != null else 0, carbonizada]
	if _cache.has(chave):
		return _cache[chave]
	if nome in ["P_Teia", "P_TeiaSuja"]:
		# véu de seda da toca: fios opacos e buracos (recorte de alfa da textura teia.png), visto dos dois lados
		var t := StandardMaterial3D.new()
		t.resource_name = cor_nome
		t.albedo_texture = load("res://assets/texturas/teia.png")
		t.albedo_color = b.albedo_color
		t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		t.alpha_scissor_threshold = 0.3
		t.cull_mode = BaseMaterial3D.CULL_DISABLED
		t.roughness = 0.75
		_cache[chave] = t
		return t
	var m := ShaderMaterial.new()
	m.shader = SHADER_CRISTAL if nome == "P_Cristal" else SHADER
	m.resource_name = cor_nome
	m.set_shader_parameter("cor", b.albedo_color)
	m.set_shader_parameter("aspereza", b.roughness)
	m.set_shader_parameter("metal", b.metallic)
	if b.emission_enabled:
		m.set_shader_parameter("cor_emissao", b.emission)
		m.set_shader_parameter("forca_emissao", maxf(b.emission_energy_multiplier, 1.0))
	if ROLAGEM.has(nome):
		m.set_shader_parameter("rolagem", ROLAGEM[nome])
	if COR_LONA.has(nome):
		m.set_shader_parameter("cor", COR_LONA[nome])
	if nome in ["P_Cristal", "P_Biomassa", "P_OlhoInimigo", "P_Fogo", "P_Seiva"]:
		m.set_shader_parameter("pulso", 1.0)
	if nome == "P_Cristal":
		m.set_shader_parameter("por_trabalho", true)
	if nome == "P_Seiva":
		m.set_shader_parameter("seiva", true)
	# vegetação: o material assado ("<modelo>_Tex") também balança e queima (antes só os de nome P_Folha…)
	if vento > 0.0 and (nome in ["P_Folha", "P_FolhaClara", "P_Biomassa", "P_Lodo", "P_Malaquita", "P_Cristal", "P_FungoCaule"] or nome.ends_with("_Tex") or PERFIL_FOLHA.has(nome)):
		m.set_shader_parameter("vento", vento)
	if PERFIL_FOLHA.has(nome):
		m.set_shader_parameter("perfil_folha", PERFIL_FOLHA[nome])
	if carbonizada:
		m.set_shader_parameter("carbonizada", true)
	m.set_shader_parameter("boiar", boiar)
	if tex != null:
		m.set_shader_parameter("textura", tex)
		m.set_shader_parameter("tem_textura", true)
		m.set_shader_parameter("cor", Color.WHITE)
	if uv2 and ROLAGEM.has(nome):
		m.set_shader_parameter("rolagem_uv2", true)
	_cache[chave] = m
	return m


## Aplica em todas as malhas de uma cena instanciada.
static func converter(raiz: Node, vento := 0.0, boiar := 0.0) -> void:
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var uv2: bool = (mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
			mi.set_surface_override_material(s, material(mi.mesh.surface_get_material(s), vento, boiar, uv2))


## O objeto usa o brilho por trabalho (tem superfície com a variante do cristal)? O Animador só manda para esses.
static func usa_trabalho(g: GeometryInstance3D) -> bool:
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as ShaderMaterial
		if m != null and m.shader == SHADER_CRISTAL:
			return true
	return false


## Malha única de um .glb de uma parte só (para MultiMesh), já com materiais convertidos e no lugar que a cena dá a
## ela: o nó da parte pode ter translação compensando a malha (cano_reto: nó em x −20, vértices em x +19,84).
static func malha_de(cena: PackedScene, vento := 0.0, boiar := 0.0, carbonizada := false) -> Mesh:
	var inst := cena.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		inst.free()
		return null
	var mi := mis[0] as MeshInstance3D
	var orig: Mesh = mi.mesh
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != inst:                         # a raiz fica de fora: quem instancia a cena põe a posição nela
		t = (n as Node3D).transform * t
		n = n.get_parent()
	var copia := (orig.duplicate() as Mesh) if t.is_equal_approx(Transform3D.IDENTITY) else _malha_assada(orig, t)
	for s in copia.get_surface_count():
		var uv2: bool = (copia.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
		copia.surface_set_material(s, material(orig.surface_get_material(s), vento, boiar, uv2, carbonizada))
	inst.free()
	return copia


## Cópia da malha com a transformação aplicada aos vértices. Os níveis de detalhe da importação não dão para ler daqui
## (nem transformar): gera de novo, para o lote de canos não pesar mais de longe que o resto.
static func _malha_assada(orig: Mesh, t: Transform3D) -> Mesh:
	var normal := t.basis.inverse().transposed()
	var im := ImporterMesh.new()
	for s in orig.get_surface_count():
		var arr := orig.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] = t * vs[i]
		arr[Mesh.ARRAY_VERTEX] = vs
		if arr[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in ns.size():
				ns[i] = (normal * ns[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = ns
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(0, tg.size(), 4):
				var v := (t.basis * Vector3(tg[i], tg[i + 1], tg[i + 2])).normalized()
				tg[i] = v.x
				tg[i + 1] = v.y
				tg[i + 2] = v.z
			arr[Mesh.ARRAY_TANGENT] = tg
		im.add_surface(orig.surface_get_primitive_type(s), arr, [], {}, orig.surface_get_material(s), (orig as ArrayMesh).surface_get_name(s) if orig is ArrayMesh else "")
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()
