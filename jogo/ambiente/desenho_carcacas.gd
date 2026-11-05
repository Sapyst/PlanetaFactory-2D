class_name DesenhoCarcacas
extends Node3D
## Patch fauna, fase 4 (docs/PLANO_FAUNA.md): o desenho do ciclo da morte (a lógica é Carcacas).
##  O corpo que acabou de morrer é o mesmo nó da morte: a aranha ou a larva param na pose final (`fica`) e este nó
##  adota (o DesenhoColonia o põe em `corpos`, pelo id do bicho), sem troca nem salto. Ao carregar o jogo, recria o corpo já
##  na pose final (`pose_morta`). Os materiais de cada corpo ficam só dele, para mudar sem mexer nos vivos.
##  sucata    (aranha) fumaça escura e faísca de vez em quando no começo; a ferrugem cresce (material_pf `ferrugem`);
##            no fim desmonta para o chão e afunda no capim.
##  carcaça   (larva) inteiro → inchado (cresce, escurece, brilho úmido) → restos (achata e seca, `podre`) → afunda.
## O 2D lê `nos` (o nó 3D de cada corpo, com os metas "ferrugem", "podre", "escala" e "afunda").

static var corpos: Dictionary = {}   ## id do bicho → nó da morte esperando adoção (o DesenhoColonia põe)
var carcacas: Carcacas
var eco: Ecossistema
var nos: Dictionary = {}          ## "s<id>" / "c<id>" → {no: Node3D, mats: Array, fumaca, t_faisca, base_y, base_esc}
var _d: Dictionary


func _ready() -> void:
	_d = Registro.fauna.get("carcacas", {})


func _process(delta: float) -> void:
	if carcacas == null or eco == null:
		return
	var vivos := {}
	for s in carcacas.sucatas:
		var k := "s%d" % int(s.id)
		vivos[k] = true
		var n := _garantir(k, s)
		if not n.is_empty():
			_sucata(n, s, delta)
	for f in eco.comida.values():
		if f.tipo != "carcaca":
			continue
		var k := "c%d" % int(f.id)
		vivos[k] = true
		var n := _garantir(k, f)
		if not n.is_empty():
			_carcaca(n, f)
	_varrer()
	for k in nos.keys():
		if not vivos.has(k):
			var n: Dictionary = nos[k]
			if is_instance_valid(n.no):
				(n.no as Node).queue_free()
			if n.fumaca != null and is_instance_valid(n.fumaca):
				(n.fumaca as Node).queue_free()
			nos.erase(k)


## Corpo parado que ninguém adotou (a carcaça já sumiu pelo limite, ou a lógica não fez corpo): some.
func _varrer() -> void:
	var t := Time.get_ticks_msec()
	if t - int(get_meta("_varreu", 0)) < 3000:
		return
	set_meta("_varreu", t)
	var bichos := {}
	for s in carcacas.sucatas:
		bichos[s.get("bicho", -1)] = true
	for f in eco.comida.values():
		if f.tipo == "carcaca":
			bichos[f.get("bicho", -1)] = true
	for b in corpos.keys():
		var m: Variant = corpos[b]
		if m == null or not is_instance_valid(m):
			corpos.erase(b)
		elif bool((m as Node).get_meta("pronta", false)) and not bichos.has(b):
			(m as Node).queue_free()
			corpos.erase(b)


## O nó do corpo: adota o da morte (mesma pose) ou, ao carregar o jogo, recria já morto.
func _garantir(k: String, f: Dictionary) -> Dictionary:
	if nos.has(k):
		return nos[k] if is_instance_valid(nos[k].no) else {}
	var no: Node3D = null
	var m: Variant = corpos.get(f.get("bicho", -1))
	if m != null and is_instance_valid(m) and not (m as Node).is_queued_for_deletion():
		if not bool((m as Node).get_meta("pronta", false)):
			return {}                                          # ainda caindo: adota quando parar na pose final
		no = m
	if no != null:
		corpos.erase(f.get("bicho", -1))
		no.reparent(self, no.is_inside_tree())
	else:
		if float(f.idade) < 2.0:
			return {}                                          # morreu agora: espera o nó da morte chegar
		var pos := Grade.ponto_mundo(f.pos)
		match String(f.especie):
			"larva":
				no = Larva.new(pos, float(f.ang))
			"aranha":
				no = Aranha.new(pos, float(f.ang))
			"rato":
				no = DesenhoRatos.corpo_morto(pos, float(f.ang), String(f.get("variante", "pardo")))
			"passaro":
				no = DesenhoPassaros.corpo_morto(pos, float(f.ang), String(f.get("variante", "pardelo")), f.get("bicho", ""))
		if no == null:
			return {}
		if no.get_parent() == null:
			add_child(no)
		if no.has_method("pose_morta"):
			no.pose_morta()
	var n := {"no": no, "mats": _materiais_unicos(no), "fumaca": null, "t_faisca": randf_range(0.5, 2.0),
			"base_y": no.position.y, "base_esc": no.scale}
	nos[k] = n
	return n


## Luz do corpo morto (o olho e o led da aranha, o ácido da larva): `k` de 0 a 1 sobre a força original.
func _luz(n: Dictionary, k: float) -> void:
	if is_equal_approx(float(n.get("_luz", -1.0)), k):
		return
	n["_luz"] = k
	for m: ShaderMaterial in n.mats:
		if not m.has_meta("emissao0"):
			var f0 = m.get_shader_parameter("forca_emissao")
			m.set_meta("emissao0", float(f0) if f0 != null else 0.0)
		var o: float = m.get_meta("emissao0")
		if float(o) > 0.0:
			m.set_shader_parameter("forca_emissao", float(o) * k)


## Cada superfície do corpo ganha a própria cópia do material (os vivos da mesma espécie não mudam junto).
func _materiais_unicos(no: Node) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in no.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is ShaderMaterial:
			mi.material_override = (mi.material_override as ShaderMaterial).duplicate()
			out.append(mi.material_override)
			continue
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m is ShaderMaterial:
				var u := (m as ShaderMaterial).duplicate() as ShaderMaterial
				mi.set_surface_override_material(i, u)
				out.append(u)
	return out


func _param(n: Dictionary, nome: String, v: float) -> void:
	if is_equal_approx(float(n.get("_" + nome, -1.0)), v):
		return
	n["_" + nome] = v
	for m: ShaderMaterial in n.mats:
		m.set_shader_parameter(nome, v)
	(n.no as Node3D).set_meta(nome, v)


func _sucata(n: Dictionary, s: Dictionary, delta: float) -> void:
	var rel := Carcacas.idade_rel(s)
	_param(n, "ferrugem", smoothstep(0.02, 0.65, rel))
	# os leds piscam alguns segundos e apagam (curto-circuito), nunca mais acendem
	var id_s := float(s.idade)
	var acesa := 0.0 if id_s > 5.0 else (1.0 if fposmod(id_s * 7.3 + sin(id_s * 23.0), 1.0) < 0.4 + 0.1 * id_s else 0.15)
	_luz(n, acesa)
	_param(n, "desligada", 1.0 - acesa)
	var desmonta := smoothstep(0.75, 0.95, rel)
	var afunda := Carcacas.afunda(s)
	var no: Node3D = n.no
	no.position.y = float(n.base_y) - 0.12 * desmonta - 0.5 * afunda        # desmonta no capim e afunda no fim
	no.set_meta("afunda", afunda)
	# fumaça e faísca da sucata fresca
	var fum := float(Registro.fauna.get("carcacas", {}).get("tipos", {}).get(String(s.especie), {}).get("fumaca_s", 45.0))
	var idade := float(s.idade)
	if idade < fum and (n.fumaca == null or not is_instance_valid(n.fumaca)):
		n.fumaca = _nova_fumaca()
		(n.fumaca as Node3D).position = no.position + Vector3.UP * 0.3          # este nó fica na origem do mundo
	if n.fumaca != null and is_instance_valid(n.fumaca):
		var p: CPUParticles3D = n.fumaca
		p.emitting = idade < fum
		if idade > fum + 3.0:
			p.queue_free()
			n.fumaca = null
	n.t_faisca = float(n.t_faisca) - delta
	if idade < fum * 0.6 and float(n.t_faisca) <= 0.0:
		n.t_faisca = randf_range(1.5, 5.0)
		var onde := no.position + Vector3(randf_range(-0.4, 0.4), 0.25, randf_range(-0.4, 0.4))
		_faisca(onde)
		Som.tocar("faisca", onde, -16.0)


func _carcaca(n: Dictionary, f: Dictionary) -> void:
	var rel := Carcacas.idade_rel(f)
	var tipo: Dictionary = Registro.fauna.get("carcacas", {}).get("tipos", {}).get(String(f.especie), {})
	var e: Array = tipo.get("etapas", [0.3, 0.7])
	var incha := float(tipo.get("incha", 1.1))             # quanto o inchado cresce para cima (pássaro: pouco)
	var e0 := float(e[0])
	var e1 := float(e[1])
	var podre: float
	var esc := Vector3.ONE
	if rel < e0:                                            # inteiro: só escurece um pouco
		podre = 0.15 * rel / e0
	elif rel < e1:                                          # inchado: cresce e fica úmido
		var k := (rel - e0) / (e1 - e0)
		podre = lerpf(0.15, 0.5, k)
		var i := smoothstep(0.0, 0.5, k)
		esc = Vector3(1.0 + 0.15 * i, 1.0 + incha * i, 1.0 + 0.15 * i)
	else:                                                   # restos: murcha e seca
		var k := (rel - e1) / (1.0 - e1)
		podre = lerpf(0.5, 1.0, smoothstep(0.0, 0.6, k))
		var m := smoothstep(0.0, 0.4, k)
		esc = Vector3(1.15 - 0.07 * m, lerpf(1.0 + incha, 0.35, m), 1.15 - 0.07 * m)
	_param(n, "podre", podre)
	var apaga := clampf(float(f.idade) / 60.0, 0.0, 1.0)              # o ácido aceso vai apagando no primeiro minuto
	_luz(n, (1.0 - apaga) * 0.6)
	_param(n, "desligada", 0.7 * apaga)
	var no: Node3D = n.no
	no.scale = (n.base_esc as Vector3) * esc
	var afunda := Carcacas.afunda(f)
	no.position.y = float(n.base_y) - 0.25 * afunda
	no.set_meta("escala", esc)
	no.set_meta("afunda", afunda)


func _nova_fumaca() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 1.6
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 20.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0.08, 0.25, 0.0)
	p.damping_min = 0.1
	p.damping_max = 0.3
	# óleo da hidráulica queimando: fumaça escura e fina, não a cinza clara de chaminé
	Fumaca.configurar(p, [Color(0.12, 0.11, 0.1, 0.0), Color(0.16, 0.15, 0.14, 0.45), Color(0.3, 0.29, 0.28, 0.0)], 0.12, 0.3, 2.6)
	add_child(p)
	return p


func _faisca(p: Vector3) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.emitting = true
	f.amount = 6
	f.lifetime = 0.45
	f.explosiveness = 0.95
	f.direction = Vector3.UP
	f.spread = 60.0
	f.initial_velocity_min = 1.2
	f.initial_velocity_max = 2.6
	f.gravity = Vector3(0, -9.0, 0)
	f.scale_amount_min = 0.03
	f.scale_amount_max = 0.05
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.75, 0.35)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	q.material = m
	f.mesh = q
	add_child(f)
	f.position = p
	get_tree().create_timer(1.0).timeout.connect(f.queue_free)
