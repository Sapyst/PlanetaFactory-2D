class_name DesenhoDrones
extends Node3D
## Desenha os drones (lógica em Drones) com os modelos convertidos de estudo_drones_modelo.py — só lê a lógica e os
## eventos do tick, não decide nada. Cada ação do estudo:
##  nascer     holograma vermelho na fabricadora: os 3 projetores da estação lançam leques de luz, o drone se monta
##             de baixo para cima (shader holograma, `corte` subindo), vira matéria com a borda ainda acesa e desce
##             para dentro da estação;
##  voo        hélices girando (sentidos alternados, mais rápido com mais empuxo); atitude por mola-amortecedor:
##             inclina para onde acelera, passa do ponto e volta; paira com balanço de rajada; guinada com tranco;
##  reparo     para ao lado da peça: folha de laser vermelha corre de cima a baixo sobre ela (shader scan_reparo como
##             sobreposição na estrutura + contorno e leque do olho até a folha) e o braço de solda trabalha com
##             faíscas e o clarão do arco;
##  combate    torre gira e o canhão abaixa até a aranha; cada tiro: traçante vermelho, clarão de boca, recuo, e a
##             cápsula sai pela janela de ejeção com fumacinha (a mesma cápsula do DesenhoColonia.ejetar_capsula);
##  logístico  a garra balança em pêndulo (aceleração do drone) com o item que leva (modelo do item);
##  derrubado  gira descontrolado soltando fumaça, bate no chão (faíscas, poeira) e fica como sucata fumegando.

const MODELOS := {"reparo": "drone_reparo", "combate": "drone_defesa", "logistico": "drone_logistico",
		"construtor": "drone_reparo"}          ## construtor (patch RTS): o de reparo, que tem o braço de solda
const VERMELHO := Color(1.0, 0.06, 0.03)
const HOLO := preload("res://render/shaders/holograma.gdshader")
const SCAN := preload("res://render/shaders/scan_reparo.gdshader")
const SUCATA_S := 8.0

var drones: Drones
var mapa: MapaOcupacao
var desenho_colonia: DesenhoColonia     ## cápsulas ejetadas (o mesmo sistema das torres)
var no_estrutura: Callable              ## func(id) -> Node3D da estrutura (ou null; peça em lote não tem nó)

var _nos: Dictionary = {}               ## id do drone → {no, partes, vis…}
var _sucatas: Array[Dictionary] = []
var _scan: Dictionary = {}              ## id da estrutura → {mat, nos: Array[GeometryInstance3D]}
var _malha: ImmediateMesh
var _vs := PackedVector3Array()          ## triângulos de luz do quadro (leques, folha de scan, traçantes)
var _cs := PackedColorArray()
var _tracos: Array[Dictionary] = []     ## {de, para, vida}
var _mat_holo: ShaderMaterial
var _t := 0.0
var _r: Dictionary


func _ready() -> void:
	_r = Registro.estruturas.get(Drones.ESTACAO, {}).get("drones", {})
	_malha = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _malha
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)
	_mat_holo = ShaderMaterial.new()
	_mat_holo.shader = HOLO


## Chamado a cada quadro depois do tick lógico. `eventos` = os do Drones acumulados desde o último quadro.
func atualizar(eventos: Array[Dictionary], delta: float) -> void:
	_t += delta
	for e in eventos:
		match e.tipo:
			"drone_tiro":
				_tiro(e)
			"drone_abatido":
				if _nos.has(e.id):
					_nos[e.id].fumaca.emitting = true
			"drone_sucata":
				_sucata(e)
	_vs.clear()
	_cs.clear()
	var vistos := {}
	for id in drones.drones:
		var d: Dictionary = drones.drones[id]
		if d.e == Drones.E.HANGAR and d.tipo != "construtor" or not mapa.estruturas.has(d.est) and d.e != Drones.E.CAINDO:
			continue
		vistos[id] = true
		var n: Dictionary = _nos.get(id, {})
		if n.is_empty() or n.tipo != String(d.tipo):
			if not n.is_empty():
				_apagar(id)
			n = _novo(d)
			_nos[id] = n
		_desenhar(d, n, delta)
	for id in _nos.keys():
		if not vistos.has(id):
			_apagar(id)
	_scans(delta)
	_desenhar_tracos(delta)
	_malha.clear_surfaces()
	if not _vs.is_empty():
		_malha.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in _vs.size():
			_malha.surface_set_color(_cs[i])
			_malha.surface_add_vertex(_vs[i])
		_malha.surface_end()
	_mover_sucatas(delta)


## Quantos drones estão desenhados agora (testes).
func visiveis() -> int:
	return _nos.size()


# ------------------------------------------------------------------ nó de cada drone
func _novo(d: Dictionary) -> Dictionary:
	var nome: String = MODELOS.get(String(d.tipo), "drone_reparo")
	var raiz := Node3D.new()
	add_child(raiz)
	var corpo: Node3D = (load(Registro.modelos[nome].modelo) as PackedScene).instantiate()
	raiz.add_child(corpo)
	Materiais.converter(corpo)
	var esc := float(_r.get("escala", 1.5))
	corpo.scale = Vector3(esc, esc, esc)
	var partes := {}
	var base := {}
	for c in corpo.find_children("*", "Node3D", true, false):
		var i := String(c.name).rfind("_")
		if i > 0:
			var pn := String(c.name).substr(i + 1)
			partes[pn] = c
			base[pn] = (c as Node3D).transform
	var malhas: Array[GeometryInstance3D] = []
	for g in corpo.find_children("*", "GeometryInstance3D", true, false):
		malhas.append(g)
	var fumaca := _particulas_fumaca()
	add_child(fumaca)
	var p0 := Grade.ponto_mundo(d.pos, float(d.alt))
	raiz.position = p0
	var n := {"no": raiz, "corpo": corpo, "partes": partes, "base": base, "malhas": malhas, "tipo": String(d.tipo),
			"pos": p0, "vel": Vector3.ZERO, "ac": Vector3.ZERO, "tilt": Vector2.ZERO, "w_tilt": Vector2.ZERO,
			"yaw": 0.0, "w_yaw": 0.0, "rot": 0.0, "giro_rotor": 0.0, "pend": Vector2.ZERO, "w_pend": Vector2.ZERO,
			"recuo": 0.0, "fumaca": fumaca, "holo": -1.0, "faisca_t": 0.0, "item": "", "item_no": null, "luz": null}
	if d.e == Drones.E.NASCENDO:
		_holo(n, true)
	return n


func _apagar(id: int) -> void:
	var n: Dictionary = _nos[id]
	(n.no as Node).queue_free()
	(n.fumaca as CPUParticles3D).emitting = false
	var f: Node = n.fumaca
	if is_inside_tree():
		get_tree().create_timer(3.0).timeout.connect(f.queue_free)
	else:
		f.queue_free()
	_nos.erase(id)


func _holo(n: Dictionary, liga: bool) -> void:
	for g in n.malhas:
		if is_instance_valid(g):
			g.material_override = _mat_holo.duplicate() if liga else null
			g.material_overlay = null
	n.holo = 0.0 if liga else -1.0


func _desenhar(d: Dictionary, n: Dictionary, delta: float) -> void:
	var raiz: Node3D = n.no
	var alvo := Grade.ponto_mundo(d.pos, float(d.alt))
	var dt := maxf(delta, 1e-3)
	# posição suave (lógica a 30 Hz) e física da atitude
	var ant: Vector3 = n.pos
	var pos := ant.lerp(alvo, 1.0 - exp(-18.0 * dt)) if d.e != Drones.E.NASCENDO else alvo
	var vel := (pos - ant) / dt
	n.ac = (n.ac as Vector3).lerp((vel - (n.vel as Vector3)) / dt, 1.0 - exp(-10.0 * dt))
	n.vel = vel
	n.pos = pos
	var ac: Vector3 = n.ac
	var voando: bool = d.e in [Drones.E.DECOLANDO, Drones.E.INDO, Drones.E.TRABALHANDO, Drones.E.VOLTANDO, Drones.E.POUSANDO] \
			or d.tipo == "construtor" and d.e == Drones.E.HANGAR          # construtor parado orbita o cristal
	# inclina para onde acelera (e um pouco com a velocidade, como freio aerodinâmico); mola passa do ponto e volta
	var quer := Vector2(ac.x, ac.z) * 0.055 + Vector2(vel.x, vel.z) * 0.03
	if voando:                                                   # rajadas: balanço de quem paira
		quer += Vector2(sin(_t * 1.7 + float(d.id)), cos(_t * 2.3 + float(d.id) * 1.3)) * 0.035
	if quer.length() > 0.45:
		quer = quer.normalized() * 0.45
	var w: Vector2 = n.w_tilt
	var tl: Vector2 = n.tilt
	w += ((quer - tl) * 80.0 - w * 6.0) * dt                    # ω ≈ 9 rad/s, amortecimento baixo (passa do ponto)
	tl += w * dt
	n.w_tilt = w
	n.tilt = tl
	# guinada: de frente para onde vai; trabalhando, de frente para o alvo
	var rumo := Vector2(vel.x, -vel.z)
	var olhar := _olhar_para(d)
	if olhar != Vector2.INF:
		rumo = olhar - (d.pos as Vector2)
	if rumo.length() > 0.3:
		var alvo_yaw := atan2(rumo.y, rumo.x)
		var dif := wrapf(alvo_yaw - float(n.yaw), -PI, PI)
		var wy := float(n.w_yaw)
		wy += (dif * 40.0 - wy * 7.0) * dt
		n.w_yaw = wy
		n.yaw = float(n.yaw) + wy * dt
	if d.e == Drones.E.CAINDO:                                   # derrubado: gira descontrolado
		n.yaw = float(n.yaw) + dt * (6.0 + float(d.t) * 10.0)
		n.tilt = Vector2(sin(_t * 9.0), cos(_t * 7.0)) * 0.7
		tl = n.tilt
	var tilt3 := Vector3(tl.x, 0.0, tl.y)
	var ang := tilt3.length()
	var b := Basis(Vector3.UP, float(n.yaw))
	if ang > 1e-4:
		b = Basis(Vector3.UP.cross(tilt3 / ang), ang) * b
	var bob := sin(_t * 3.1 + float(d.id)) * 0.025 if voando else 0.0
	raiz.global_transform = Transform3D(b, pos + Vector3(0, bob, 0))
	_rotores(d, n, dt, voando)
	match String(d.tipo):
		"reparo", "construtor": _braco_solda(d, n, dt)
		"combate": _torre(d, n, dt)
		"logistico": _pendulo(d, n, dt)
	_nascer(d, n, dt)
	(n.fumaca as CPUParticles3D).global_position = raiz.global_position


## Ponto (grade) que o drone encara quando está trabalhando; INF = segue o voo.
func _olhar_para(d: Dictionary) -> Vector2:
	if d.e != Drones.E.TRABALHANDO and not (d.tipo == "combate" and d.e == Drones.E.INDO):
		return Vector2.INF
	match String(d.tipo):
		"reparo":
			if mapa.estruturas.has(d.alvo):
				var e: Dictionary = mapa.estruturas[d.alvo]
				return Grade.centro_da_area(e.minimo, e.area, e.rot)
		"construtor":
			if drones.obras != null and drones.obras.obras.has(int(d.alvo)):
				return drones.obras.obras[int(d.alvo)].pos
		"combate":
			if drones.colonia.aranhas.has(d.alvo):
				return drones.colonia.aranhas[d.alvo].pos
	return Vector2.INF


func _rotores(d: Dictionary, n: Dictionary, dt: float, voando: bool) -> void:
	var empuxo := 1.0 + (n.ac as Vector3).length() * 0.04
	var alvo_w := (38.0 * empuxo) if voando else (0.0 if d.e == Drones.E.NASCENDO else 10.0)
	n.giro_rotor = move_toward(float(n.giro_rotor), alvo_w, dt * 60.0)
	n.rot = float(n.rot) + float(n.giro_rotor) * dt
	for k in 4:
		var p := "rotor%d" % k
		if n.partes.has(p):
			var bt: Transform3D = n.base[p]
			(n.partes[p] as Node3D).transform = Transform3D(Basis(Vector3.UP, float(n.rot) * (1.0 if k % 2 == 0 else -1.0)) * bt.basis, bt.origin)


func _girar(n: Dictionary, parte: String, eixo: Vector3, a: float) -> void:
	if n.partes.has(parte):
		var bt: Transform3D = n.base[parte]
		(n.partes[parte] as Node3D).transform = Transform3D(bt.basis * Basis(eixo, a), bt.origin)


## Ponto de uma parte (em coordenadas locais dela, Godot) no mundo.
func _ponto(n: Dictionary, parte: String, local: Vector3) -> Vector3:
	if not n.partes.has(parte):
		return (n.no as Node3D).global_position
	return (n.partes[parte] as Node3D).global_transform * local


# ------------------------------------------------------------------ nascer (holograma)
func _nascer(d: Dictionary, n: Dictionary, dt: float) -> void:
	if d.e != Drones.E.NASCENDO:
		if float(n.holo) >= 0.0:
			_holo(n, false)
		return
	var tot := float(_r.get("nascer_s", 3.0))
	var t := float(d.t)
	var raiz: Node3D = n.no
	var y0 := raiz.global_position.y - 0.3
	var y1 := raiz.global_position.y + 0.35
	var monta := clampf(t / (tot * 0.5), 0.0, 1.0)
	if t < tot * 0.55:
		for g in n.malhas:
			var m := (g as GeometryInstance3D).material_override as ShaderMaterial
			if m != null:
				m.set_shader_parameter("corte", lerpf(y0, y1, monta))
				m.set_shader_parameter("forca", 1.0)
	elif float(n.holo) >= 0.0 and n.holo < 1.0:
		n.holo = 1.0                                        # virou matéria: material de verdade + borda acesa
		for g in n.malhas:
			if is_instance_valid(g):
				(g as GeometryInstance3D).material_override = null
				var o := _mat_holo.duplicate() as ShaderMaterial
				(g as GeometryInstance3D).material_overlay = o
	if float(n.holo) >= 1.0:
		var f := clampf(1.0 - (t - tot * 0.55) / (tot * 0.25), 0.0, 1.0)
		for g in n.malhas:
			var o := (g as GeometryInstance3D).material_overlay as ShaderMaterial
			if o != null:
				o.set_shader_parameter("forca", f)
	if d.tipo == "construtor":                       # nasce na órbita do cristal do núcleo (sem projetores)
		return
	# no fim desce para dentro da fabricadora
	var desce := clampf((t - tot * 0.8) / (tot * 0.2), 0.0, 1.0)
	raiz.global_position.y -= desce * desce * 0.6
	# leques dos 3 projetores até o drone
	var forca := (1.0 - clampf((t - tot * 0.6) / (tot * 0.2), 0.0, 1.0)) * 0.55
	if forca <= 0.0 or not mapa.estruturas.has(d.est):
		return
	var c := raiz.global_position
	for j in 3:
		var a := PI / 2 + j * TAU / 3.0
		var loc := Vector2(-0.5, 0.0) + Vector2(cos(a), sin(a)) * 0.44
		var pj := Grade.ponto_mundo(drones.ponto_estacao(d.est, loc), 1.34)
		var lado := (c - pj).cross(Vector3.UP).normalized() * 0.32
		_tri(pj, c + lado + Vector3(0, -0.12, 0), c - lado + Vector3(0, 0.12, 0), Color(VERMELHO, 0.0), Color(VERMELHO, forca))


# ------------------------------------------------------------------ reparo: braço de solda + scan
func _braco_solda(d: Dictionary, n: Dictionary, dt: float) -> void:
	var obra: Dictionary = drones.obras.obras.get(int(d.alvo), {}) if d.tipo == "construtor" and drones.obras != null else {}
	var trabalha: bool = d.e == Drones.E.TRABALHANDO and (mapa.estruturas.has(d.alvo) if d.tipo != "construtor" else not obra.is_empty())
	var t := _t
	# trabalhando: braço baixa até a peça e a tocha vai e volta no cordão; no voo: a pose do modelo (esticado para a
	# frente abaixo do corpo, entre os patins e acima do chão quando pousado — não cruza nada)
	var q_om := -0.95 + 0.12 * sin(t * 3.1) if trabalha else 0.0
	var q_co := -0.65 + 0.25 * sin(t * 5.3) if trabalha else 0.0
	var q_gi := 0.25 * sin(t * 1.3) if trabalha else 0.0
	var br: Vector3 = n.get("braco", Vector3.ZERO)
	br = Vector3(move_toward(br.x, q_gi, dt * 2.0), move_toward(br.y, q_om, dt * 2.5), move_toward(br.z, q_co, dt * 3.5))
	n.braco = br
	_girar(n, "giro", Vector3.UP, br.x)
	_girar(n, "ombro", Vector3(0, 0, 1), br.y)
	_girar(n, "cotovelo", Vector3(0, 0, 1), br.z)
	trabalha = trabalha and absf(br.y - q_om) < 0.3                # a solda começa com o braço já embaixo
	if not trabalha:
		if n.luz != null:
			(n.luz as Node).queue_free()
			n.luz = null
		return
	var ponta := _ponto(n, "cotovelo", Vector3(0.135, 0, 0))
	if n.luz == null:
		var l := OmniLight3D.new()
		l.light_color = Color(0.8, 0.85, 1.0)
		l.omni_range = 2.2
		l.shadow_enabled = false
		add_child(l)
		n.luz = l
	(n.luz as OmniLight3D).global_position = ponta
	(n.luz as OmniLight3D).light_energy = 1.2 + 1.8 * absf(sin(_t * 37.0))
	n.faisca_t = float(n.faisca_t) - dt
	if float(n.faisca_t) <= 0.0:
		n.faisca_t = 0.12
		_faiscas(ponta, 6, Color(1.0, 0.55, 0.15), 1.6)
	if d.tipo != "construtor":
		_scan_em(int(d.alvo), d, n)
	elif obra.acao == "remover" and mapa.estruturas.has(int(obra.item.get("id", -1))):
		_scan_em(int(obra.item.id), d, n)              # desmontando: a folha de laser corre pela peça


## Marca a estrutura como escaneada neste quadro e desenha o contorno da folha de laser e o leque do olho.
func _scan_em(id: int, d: Dictionary, n: Dictionary) -> void:
	var e: Dictionary = mapa.estruturas[id]
	var dims: Array = Registro.modelos.get(e.nome, {}).get("dims", [1, 1, 1])
	var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
	var base := Grade.ponto_mundo(c).y
	var topo := base + float(dims[2])
	var h := lerpf(base + 0.05, topo, 0.5 + 0.5 * sin(_t * 2.4 + float(d.id)))
	var s: Dictionary = _scan.get(id, {})
	if s.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = SCAN
		var nos: Array = []
		var no: Variant = no_estrutura.call(id) if no_estrutura.is_valid() else null
		if no != null and is_instance_valid(no):
			for g in (no as Node).find_children("*", "GeometryInstance3D", true, false):
				if (g as GeometryInstance3D).material_overlay == null:
					(g as GeometryInstance3D).material_overlay = mat
					nos.append(g)
		s = {"mat": mat, "nos": nos}
		_scan[id] = s
	s.visto = true
	(s.mat as ShaderMaterial).set_shader_parameter("altura", h)
	# contorno da folha (área girada, um pouco para fora) e leque do olho até a borda de perto
	var ar := Grade.area_girada(e.area, e.rot)
	var hx := float(ar.x) * 0.5 + 0.06
	var hy := float(ar.y) * 0.5 + 0.06
	var cantos: Array[Vector3] = []
	for q: Vector2 in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
		var p := c + q
		cantos.append(Vector3(p.x, h, -p.y))
	for i in 4:
		_fita(cantos[i], cantos[(i + 1) % 4], 0.035, Color(VERMELHO, 0.9))
	var olho := _ponto(n, "corpo", Vector3(0.162, 0, 0)) if n.partes.has("corpo") else (n.no as Node3D).global_position
	var perto := 0
	for i in 4:
		if cantos[i].distance_to(olho) < cantos[perto].distance_to(olho):
			perto = i
	_tri(olho, cantos[perto], cantos[(perto + 1) % 4], Color(VERMELHO, 0.35), Color(VERMELHO, 0.1))
	_tri(olho, cantos[perto], cantos[(perto + 3) % 4], Color(VERMELHO, 0.35), Color(VERMELHO, 0.1))


func _scans(_delta: float) -> void:
	for id in _scan.keys():
		var s: Dictionary = _scan[id]
		if s.get("visto", false):
			s.visto = false
			continue
		for g in s.nos:
			if is_instance_valid(g) and (g as GeometryInstance3D).material_overlay == s.mat:
				(g as GeometryInstance3D).material_overlay = null
		_scan.erase(id)


## Estruturas com o scan ligado agora (testes).
func escaneando() -> Array:
	return _scan.keys()


# ------------------------------------------------------------------ combate: torre, tiro, cápsula
func _torre(d: Dictionary, n: Dictionary, dt: float) -> void:
	var olhar := _olhar_para(d)
	var yaw_t := 0.0
	var pitch_t := 0.0
	if olhar != Vector2.INF:
		var alvo := Grade.ponto_mundo(olhar, 0.5)
		var loc := (n.no as Node3D).global_transform.affine_inverse() * alvo
		yaw_t = atan2(-loc.z, loc.x)
		pitch_t = -atan2(-loc.y, Vector2(loc.x, loc.z).length())
	var gy := float(n.get("t_yaw", 0.0))
	var gp := float(n.get("t_pitch", 0.0))
	gy = gy + clampf(wrapf(yaw_t - gy, -PI, PI), -dt * 6.0, dt * 6.0)
	gp = move_toward(gp, clampf(pitch_t, -1.3, 0.2), dt * 4.0)
	n.t_yaw = gy
	n.t_pitch = gp
	n.recuo = maxf(0.0, float(n.recuo) - dt * 8.0)
	_girar(n, "torre", Vector3.UP, gy)
	_girar(n, "canhao", Vector3(0, 0, 1), gp)
	if n.partes.has("canhao") and float(n.recuo) > 0.0:
		var no: Node3D = n.partes.canhao
		no.position -= no.transform.basis.x * 0.02 * float(n.recuo)


func _tiro(e: Dictionary) -> void:
	var n: Dictionary = _nos.get(e.id, {})
	var para := Grade.ponto_mundo(e.para, 0.55)
	var de := Grade.ponto_mundo(e.de, float(e.alt))
	if not n.is_empty():
		n.recuo = 1.0
		var lado := 1.0 if int(n.get("cano", 0)) % 2 == 0 else -1.0
		n.cano = int(n.get("cano", 0)) + 1
		de = _ponto(n, "canhao", Vector3(0.19, 0, 0.014 * lado))
		_faiscas(de, 3, Color(1.0, 0.25, 0.08), 1.0)
		# cápsula pela janela de ejeção (lado −Y do Blender = +Z local do canhão), com fumacinha
		var ej := _ponto(n, "canhao", Vector3(0.03, 0.004, 0.034))
		var fora := (_ponto(n, "canhao", Vector3(0.03, 0.004, 0.2)) - ej).normalized()
		if desenho_colonia != null:
			desenho_colonia.ejetar_capsula(ej, fora * 1.6 + Vector3(0, 1.2, 0) + (n.vel as Vector3) * 0.8,
					Grade.ponto_mundo(e.de).y, 0.75)
			if desenho_colonia.pool_efeitos != null:
				desenho_colonia.pool_efeitos.disparar_rastro("drone_combate", de, para)
				desenho_colonia.pool_efeitos.disparar_impacto("drone_combate", para, "aranha")
		_baforada(ej)
	_tracos.append({"de": de, "para": para, "vida": 0.08})
	Som.tocar("tiro_drone", de, -8.0)


func _desenhar_tracos(delta: float) -> void:
	var vivos: Array[Dictionary] = []
	for tr in _tracos:
		tr.vida = float(tr.vida) - delta
		if tr.vida > 0.0:
			vivos.append(tr)
			_fita(tr.de, tr.para, 0.05, Color(1.0, 0.15, 0.06, 0.95))
	_tracos = vivos


# ------------------------------------------------------------------ logístico: pêndulo com a carga
func _pendulo(d: Dictionary, n: Dictionary, dt: float) -> void:
	var ac: Vector3 = n.ac
	var w: Vector2 = n.w_pend
	var p: Vector2 = n.pend
	var L := 0.25
	# pêndulo amortecido empurrado pela aceleração do drone (para trás de quem acelera)
	w += (-(9.81 / L) * p - w * 2.2 - Vector2(ac.x, ac.z) / L * 0.25) * dt
	p += w * dt
	p = p.limit_length(0.3)                                     # a garra larga do estudo passa rente aos patins
	n.w_pend = w
	n.pend = p
	# pousando/decolando, o guincho recolhe a garra 0,10 m (no berço ela ficaria abaixo dos patins)
	var recolhe: float = n.get("recolhe", 0.0)
	recolhe = move_toward(recolhe, 0.10 if d.e in [Drones.E.POUSANDO, Drones.E.DECOLANDO] else 0.0, dt * 0.25)
	n.recolhe = recolhe
	if n.partes.has("pendulo"):
		var no: Node3D = n.partes.pendulo
		var bt: Transform3D = n.base.pendulo
		var inv := (n.no as Node3D).global_transform.basis.inverse()
		var local := inv * Vector3(p.x, 0, p.y)                 # balanço do mundo no espaço do drone
		no.transform = Transform3D(Basis(Vector3(0, 0, 1), local.x) * Basis(Vector3(1, 0, 0), -local.z) * bt.basis,
				bt.origin + Vector3(0, recolhe, 0))
	var item := String(d.item) if int(d.n) > 0 else ""
	if item != String(n.item):
		n.item = item
		if n.item_no != null:
			(n.item_no as Node).queue_free()
			n.item_no = null
		if n.partes.has("carga"):
			(n.partes.carga as Node3D).visible = false
		if item != "" and n.partes.has("pendulo"):
			var info: Dictionary = Registro.itens.get(item, {})
			var base: String = info.get("modelo_de", item)
			if Registro.modelos.has(base):
				var mi := MeshInstance3D.new()
				mi.mesh = Materiais.malha_de(load(Registro.modelos[base].modelo))
				(n.partes.pendulo as Node3D).add_child(mi)
				mi.position = Vector3(0, -0.2, 0)
				mi.scale = Vector3.ONE * 0.55
				n.item_no = mi
			elif n.partes.has("carga"):
				(n.partes.carga as Node3D).visible = true


# ------------------------------------------------------------------ derrubado / sucata
func _sucata(e: Dictionary) -> void:
	var n: Dictionary = _nos.get(e.id, {})
	var p := Grade.ponto_mundo(e.pos, 0.18)
	_faiscas(p, 30, Color(1.0, 0.6, 0.25), 3.0)
	_poeira(p)
	Som.tocar("impacto_estrutura", p, -6.0)
	if n.is_empty():
		return
	var no: Node3D = n.no
	_nos.erase(e.id)
	no.global_position = p
	no.global_transform.basis = Basis(Vector3(1, 0, 0.3).normalized(), 0.6) * Basis(Vector3.UP, randf() * TAU)
	var f: CPUParticles3D = n.fumaca
	f.global_position = p
	f.emitting = true
	_sucatas.append({"no": no, "fumaca": f, "t": 0.0})


func _mover_sucatas(delta: float) -> void:
	var ficam: Array[Dictionary] = []
	for s in _sucatas:
		s.t = float(s.t) + delta
		if s.t > SUCATA_S * 0.6:
			(s.fumaca as CPUParticles3D).emitting = false
		if s.t > SUCATA_S:
			var no: Node3D = s.no
			no.position.y -= delta * 0.4                          # afunda no chão e some
			if s.t > SUCATA_S + 1.5:
				no.queue_free()
				(s.fumaca as Node).queue_free()
				continue
		ficam.append(s)
	_sucatas = ficam


# ------------------------------------------------------------------ partículas e fitas
func _particulas_fumaca() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.1, 0.6, 0.0)
	Fumaca.configurar(p, [Color(0.08, 0.08, 0.08, 0.0), Color(0.12, 0.11, 0.1, 0.75), Color(0.3, 0.3, 0.3, 0.0)], 0.25, 0.45, 3.0)
	return p


func _baforada(p: Vector3) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.emitting = true
	f.amount = 6
	f.lifetime = 0.8
	f.explosiveness = 0.9
	f.local_coords = false
	f.direction = Vector3.UP
	f.spread = 40.0
	f.initial_velocity_min = 0.1
	f.initial_velocity_max = 0.35
	f.gravity = Vector3(0, 0.3, 0)
	Fumaca.configurar(f, [Color(0.5, 0.48, 0.46, 0.0), Color(0.55, 0.53, 0.5, 0.45), Color(0.7, 0.7, 0.7, 0.0)], 0.07, 0.13, 2.6)
	add_child(f)
	f.global_position = p
	if is_inside_tree():
		get_tree().create_timer(1.2).timeout.connect(f.queue_free)


func _poeira(p: Vector3) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.emitting = true
	f.amount = 24
	f.lifetime = 1.6
	f.explosiveness = 0.95
	f.local_coords = false
	f.direction = Vector3(1, 0.3, 0)
	f.spread = 180.0
	f.flatness = 0.8
	f.initial_velocity_min = 1.0
	f.initial_velocity_max = 2.2
	f.damping_min = 2.0
	f.damping_max = 3.0
	Fumaca.configurar(f, [Color(0.5, 0.45, 0.38, 0.7), Color(0.52, 0.47, 0.4, 0.5), Color(0.6, 0.56, 0.5, 0.0)], 0.3, 0.6, 2.2)
	add_child(f)
	f.global_position = p
	if is_inside_tree():
		get_tree().create_timer(2.0).timeout.connect(f.queue_free)


func _faiscas(p: Vector3, n: int, cor: Color, vel: float) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.emitting = true
	f.amount = n
	f.lifetime = 0.45
	f.explosiveness = 0.95
	f.local_coords = false
	f.direction = Vector3.DOWN
	f.spread = 75.0
	f.initial_velocity_min = vel * 0.5
	f.initial_velocity_max = vel
	f.gravity = Vector3(0, -9.0, 0)
	f.scale_amount_min = 0.02
	f.scale_amount_max = 0.04
	var malha := BoxMesh.new()
	malha.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = cor
	malha.material = m
	f.mesh = malha
	add_child(f)
	f.global_position = p
	if is_inside_tree():
		get_tree().create_timer(0.8).timeout.connect(f.queue_free)


## Fita virada para a câmera (laser, traçante).
func _fita(a: Vector3, b: Vector3, larg: float, cor: Color) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var d := (b - a).normalized()
	var olho := (cam.global_position - a).normalized() if cam != null else Vector3.UP
	var lado := d.cross(olho).normalized() * larg * 0.5
	if lado.length() < 1e-5:
		lado = Vector3(larg * 0.5, 0, 0)
	_tri(a - lado, a + lado, b + lado, cor, cor)
	_tri(a - lado, b + lado, b - lado, cor, cor)


## Triângulo com cor no primeiro vértice e outra nos dois de baixo (leque que esmaece).
func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color) -> void:
	_vs.append_array([a, b, c])
	_cs.append_array([ca, cb, cb])
