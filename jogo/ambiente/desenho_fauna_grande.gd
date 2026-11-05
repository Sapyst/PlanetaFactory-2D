class_name DesenhoFaunaGrande
extends Node3D
## Patch fauna, fase 9 (docs/PLANO_FAUNA.md): o desenho da fauna grande e dos peixes (a lógica é Manadas,
## Predadores e Peixes).
##  herbívoros  o galhudo (herbivoro_galhudo.glb, com esqueleto e ações): pasta, anda no ritmo da distância
##              andada, fica alerta, galopa na fuga; o filhote é menor.
##  predadores  o uivador (predador_uivador.glb): deitado no covil, anda, espreita agachado, corre, morde, come.
##  peixes      o couraça (peixe_couraca.glb) no arco do pulo, com respingo na saída e na volta (coroa d'água que
##              abre e anel que se espalha, malhas 3D como as da chuva); o morto boia de barriga para cima.
## Quem morre: o mesmo nó fica na pose "morto" e o DesenhoCarcacas adota (vira a carcaça).
## Sons perto da câmera: alarme da manada, galope em laço enquanto foge, uivo e rosnado da matilha, pulo do peixe.

const MAX := 40
const DIST := 75.0                ## além disso o bicho não é desenhado
## m andados por ciclo de cada ação (o pé não escorrega): andar e correr.
const CICLO_M := {"galhudo": {"andar": 0.85, "correr": 2.0}, "uivador": {"andar": 0.72, "correr": 1.7, "espreitar": 0.42},
		"corcova": {"andar": 0.85, "correr": 1.7}, "espreitador": {"andar": 0.62, "correr": 1.55, "espreitar": 0.34}}
const BOIA := 0.06                ## o peixe morto boia meio afundado (a origem do modelo é o ponto mais baixo)
const SUPERFICIE := 0.12          ## a água desenhada fica esse tanto abaixo do nível do tile (DesenhoChunk)

var manadas: Manadas
var predadores: Predadores
var peixes: Peixes
var foco_de: Callable              ## () -> Vector2
var nos: Dictionary = {}           ## "h<id>" / "p<id>" / "f<id>" → {no, mod, anim, acao, esp, tipo}
var _respingos: Array = []         ## {no, t, dur, esc}
var _coroa: Mesh
var _anel: Mesh
var _mat_agua: StandardMaterial3D


static func _modelo(nome: String) -> PackedScene:
	var m: Dictionary = Registro.modelos.get(nome, {})
	return load(m.modelo) if not m.is_empty() and ResourceLoader.exists(String(m.modelo)) else null


static func nome_modelo(tipo: String, esp: String) -> String:
	return {"h": "herbivoro_", "p": "predador_", "f": "peixe_"}[tipo] + esp


## Um bicho: raiz no chão virada pelo rumo, o modelo dentro (olha para +X, como o rumo 0 do jogo).
static func _montar(tipo: String, esp: String) -> Dictionary:
	var cena := _modelo(nome_modelo(tipo, esp))
	if cena == null:
		return {}
	var raiz := Node3D.new()
	raiz.set_meta("fauna", nome_modelo(tipo, esp))        # o 2D desenha o sprite dele (também o corpo morto)
	var mod: Node3D = cena.instantiate()
	raiz.add_child(mod)
	Materiais.converter(mod)
	var anims := mod.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = anims[0] if not anims.is_empty() else null
	if anim != null:
		for nome in ["andar", "correr", "pastar", "alerta", "espreitar", "morder", "comer", "deitado", "nadar"]:
			if anim.has_animation(nome):
				anim.get_animation(nome).loop_mode = Animation.LOOP_LINEAR
	return {"no": raiz, "mod": mod, "anim": anim, "acao": "", "esp": esp, "tipo": tipo}


static func _parar_morto(anim: AnimationPlayer) -> void:
	if anim != null and anim.has_animation("morto"):
		anim.play("morto")
		anim.seek(anim.current_animation_length, true)
		anim.pause()


## Corpo morto recriado ao carregar o jogo (DesenhoCarcacas): herbívoro e predador deitados; o peixe boiando.
static func corpo_morto(especie: String, pos: Vector3, ang: float, variante := "") -> Node3D:
	var tipo: String = {"herbivoro": "h", "predador": "p", "peixe": "f"}.get(especie, "h")
	var esp: String = variante if variante != "" else {"h": "galhudo", "p": "uivador", "f": "couraca"}[tipo]
	var r := _montar(tipo, esp)
	if r.is_empty():
		return null
	var no: Node3D = r.no
	no.position = pos - (Vector3(0, SUPERFICIE + BOIA, 0) if tipo == "f" else Vector3.ZERO)
	no.rotation.y = ang
	no.set_meta("pronta", true)
	no.ready.connect(func(): _parar_morto(r.anim), CONNECT_ONE_SHOT)
	return no


func _ready() -> void:
	_mat_agua = StandardMaterial3D.new()
	_mat_agua.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_agua.albedo_color = Color(0.78, 0.84, 0.86, 0.55)
	_mat_agua.roughness = 0.15
	_mat_agua.metallic_specular = 0.8
	_mat_agua.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c := CylinderMesh.new()                    # coroa: tubo aberto que sobe e abre
	c.top_radius = 0.09
	c.bottom_radius = 0.06
	c.height = 0.12
	c.radial_segments = 12
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	c.material = _mat_agua
	_coroa = c
	var a := TorusMesh.new()                       # anel rente à água que se espalha
	a.inner_radius = 0.16
	a.outer_radius = 0.19
	a.rings = 20
	a.ring_segments = 4
	a.material = _mat_agua
	_anel = a


func _process(delta: float) -> void:
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	var vistos := {}
	if manadas != null:
		for b in manadas.bichos.values():
			if (b.pos as Vector2).distance_to(foco) <= DIST and vistos.size() < MAX:
				_herbivoro(b, delta, vistos)
	if predadores != null:
		for b in predadores.bichos.values():
			if (b.pos as Vector2).distance_to(foco) <= DIST and vistos.size() < MAX:
				_predador(b, delta, vistos)
	if peixes != null:
		for p in peixes.pulos:
			_peixe(p, vistos)
		for ev in peixes.eventos:
			if ev.tipo == "pulo" and (ev.pos as Vector2).distance_to(foco) < DIST:
				_respingo(ev.pos, 1.0)
				if (ev.pos as Vector2).distance_to(foco) < 30.0:
					Som.tocar("peixe_pulo", _na_agua(ev.pos), -12.0)
			elif ev.tipo == "boiou":
				_boiar(ev)
	_tirar(vistos)
	_animar_respingos(delta)
	_sons(foco)


func _tocar(n: Dictionary, nome: String, vel := 1.0) -> void:
	var anim: AnimationPlayer = n.anim
	if anim == null or not anim.has_animation(nome):
		return
	anim.speed_scale = vel
	if n.acao == nome:
		return
	n.acao = nome
	anim.play(nome, 0.25)


## Velocidade da animação de andar/correr pela distância andada (o casco não escorrega).
func _ritmo(n: Dictionary, acao: String, andou_m_s: float) -> float:
	var anim: AnimationPlayer = n.anim
	if anim == null or not anim.has_animation(acao):
		return 1.0
	var ciclo := float(CICLO_M.get(n.esp, {}).get(acao, 1.0))
	return clampf(andou_m_s / maxf(0.01, ciclo / anim.get_animation(acao).length), 0.25, 2.5)


func _no(chave: String, tipo: String, esp: String, pos: Vector2) -> Dictionary:
	var n: Dictionary = nos.get(chave, {})
	if n.is_empty():
		n = _montar(tipo, esp)
		if n.is_empty():
			return {}
		add_child(n.no)
		n.ult = pos
		nos[chave] = n
	return n


func _herbivoro(b: Dictionary, delta: float, vistos: Dictionary) -> void:
	var k := "h%d" % int(b.id)
	var n := _no(k, "h", String(b.especie), b.pos)
	if n.is_empty():
		return
	vistos[k] = true
	var p: Vector2 = b.pos
	var andou := p.distance_to(n.ult) / maxf(delta, 1e-4)
	match int(b.estado):
		Manadas.E.PASTANDO:
			_tocar(n, "pastar")
		Manadas.E.ALERTA:
			_tocar(n, "alerta")
		Manadas.E.ANDANDO:
			_tocar(n, "andar", _ritmo(n, "andar", andou) if andou > 0.05 else 0.35)
		Manadas.E.CORRENDO:
			_tocar(n, "correr", _ritmo(n, "correr", andou) if andou > 0.5 else 0.6)
	_por(n, p, float(b.rumo), float(b.get("escala", 1.0)), delta)


func _predador(b: Dictionary, delta: float, vistos: Dictionary) -> void:
	var k := "p%d" % int(b.id)
	var n := _no(k, "p", String(b.especie), b.pos)
	if n.is_empty():
		return
	vistos[k] = true
	var p: Vector2 = b.pos
	var andou := p.distance_to(n.ult) / maxf(delta, 1e-4)
	match int(b.estado):
		Predadores.E.DEITADO:
			_tocar(n, "deitado")
		Predadores.E.ANDANDO:
			_tocar(n, "andar", _ritmo(n, "andar", andou) if andou > 0.05 else 0.35)
		Predadores.E.ESPREITANDO:
			_tocar(n, "espreitar", _ritmo(n, "espreitar", andou) if andou > 0.05 else 0.3)
		Predadores.E.CORRENDO:
			_tocar(n, "correr", _ritmo(n, "correr", andou) if andou > 0.5 else 0.6)
		Predadores.E.MORDENDO:
			_tocar(n, "morder", 1.2)
		Predadores.E.COMENDO:
			_tocar(n, "comer")
	_por(n, p, float(b.rumo), 1.0, delta)


func _por(n: Dictionary, p: Vector2, rumo: float, esc: float, delta: float) -> void:
	n.ult = p
	var no: Node3D = n.no
	no.position = Vector3(p.x, Grade.altura_em(p), -p.y)
	no.rotation.y = lerp_angle(no.rotation.y, rumo, clampf(delta * 10.0, 0.0, 1.0))
	(n.mod as Node3D).scale = Vector3.ONE * esc


func _na_agua(p: Vector2, alt := 0.0) -> Vector3:
	return Vector3(p.x, Grade.altura_em(p) - SUPERFICIE + alt, -p.y)


## O peixe no arco do pulo: nariz para cima subindo, para baixo descendo.
func _peixe(pu: Dictionary, vistos: Dictionary) -> void:
	var k := "f%d" % int(pu.id)
	var n := _no(k, "f", String(pu.get("especie", "couraca")), pu.de)
	if n.is_empty():
		return
	vistos[k] = true
	var ar := Peixes.no_ar(pu)
	var no: Node3D = n.no
	no.position = _na_agua(ar[0], float(ar[1]) - 0.04)
	no.rotation = Vector3(0.0, float(pu.rumo), float(ar[2]))
	var anim: AnimationPlayer = n.anim
	if anim != null and anim.has_animation("pulo"):
		if n.acao != "pulo":
			n.acao = "pulo"
			anim.play("pulo")
		anim.seek(clampf(float(pu.t) / float(pu.dur), 0.0, 1.0) * anim.get_animation("pulo").length, true)
	if float(pu.t) + get_process_delta_time() >= float(pu.dur) and not bool(pu.get("caiu", false)):
		pu.caiu = true
		_respingo(pu.para, 0.8)


## Peixe morto que subiu: o nó já nasce boiando de barriga para cima e o DesenhoCarcacas adota.
func _boiar(ev: Dictionary) -> void:
	var r := _montar("f", "couraca")
	if r.is_empty():
		return
	var no: Node3D = r.no
	add_child(no)
	no.position = _na_agua(ev.pos, -BOIA)
	no.rotation.y = randf() * TAU
	_parar_morto(r.anim)
	no.set_meta("bicho", String(ev.id))
	no.set_meta("pronta", true)
	DesenhoCarcacas.corpos[String(ev.id)] = no


func _tirar(vistos: Dictionary) -> void:
	for k in nos.keys():
		if vistos.has(k):
			continue
		var n: Dictionary = nos[k]
		nos.erase(k)
		var id := int(String(k).substr(1))
		var morto := false
		var corpo := ""
		if n.tipo == "h" and manadas != null and manadas.mortos.has(id):
			morto = true
			corpo = Manadas.corpo_id(id)
		elif n.tipo == "p" and predadores != null and predadores.mortos.has(id):
			morto = true
			corpo = Predadores.corpo_id(id)
		if morto and is_instance_valid(n.no):
			_parar_morto(n.anim)                         # o mesmo nó deita e vira a carcaça
			(n.no as Node).set_meta("bicho", corpo)
			(n.no as Node).set_meta("pronta", true)
			DesenhoCarcacas.corpos[corpo] = n.no
			continue
		if is_instance_valid(n.no):
			(n.no as Node).queue_free()


# ------------------------------------------------------------------ respingo
func _respingo(p: Vector2, forca: float) -> void:
	for malha in [_coroa, _anel]:
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _mat_agua.duplicate()
		add_child(mi)
		mi.position = _na_agua(p, 0.01)
		_respingos.append({"no": mi, "t": 0.0, "dur": (0.35 if malha == _coroa else 1.1) * (0.8 + 0.4 * forca),
				"coroa": malha == _coroa, "f": forca})


func _animar_respingos(delta: float) -> void:
	for r in _respingos:
		r.t = float(r.t) + delta
		var u := clampf(float(r.t) / float(r.dur), 0.0, 1.0)
		var mi: MeshInstance3D = r.no
		if not is_instance_valid(mi):
			continue
		var f := float(r.f)
		if bool(r.coroa):                                # sobe e abre, depois cai
			var h := sin(u * PI) * f
			mi.scale = Vector3(1.0 + 1.6 * u, 0.2 + 1.6 * h, 1.0 + 1.6 * u)
		else:                                            # o anel se espalha e some
			var s := (0.6 + 4.0 * sqrt(u)) * (0.7 + 0.3 * f)
			mi.scale = Vector3(s, 0.25, s)
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - u) * (1.0 - u)
	for r in _respingos.filter(func(r): return float(r.t) >= float(r.dur)):
		if is_instance_valid(r.no):
			(r.no as Node).queue_free()
	_respingos = _respingos.filter(func(r): return float(r.t) < float(r.dur))


## Respingos de agora (o 2D desenha o anel): [pos 3D, raio m, alfa].
func respingos_agora() -> Array:
	var out: Array = []
	for r in _respingos:
		if not bool(r.coroa) and is_instance_valid(r.no):
			var u := clampf(float(r.t) / float(r.dur), 0.0, 1.0)
			out.append([(r.no as Node3D).position, 0.19 * (r.no as Node3D).scale.x, 0.55 * (1.0 - u) * (1.0 - u)])
	return out


# ------------------------------------------------------------------ sons
func _sons(foco: Vector2) -> void:
	if manadas != null:
		for ev in manadas.eventos:
			if ev.tipo == "alarme" and (ev.pos as Vector2).distance_to(foco) < 60.0:
				Som.tocar("herbivoro_alarme", Grade.ponto_mundo(ev.pos, 1.2), -6.0)
		for m in manadas.manadas.values():
			if int(m.estado) == Manadas.M.FUGA and (m.centro as Vector2).distance_to(foco) < 60.0:
				Som.loop_maquina("manada_%d" % int(m.id), "manada_galope", Grade.ponto_mundo(m.centro, 0.3), -4.0, 70.0)
	if predadores != null:
		for ev in predadores.eventos:
			if (ev.pos as Vector2).distance_to(foco) > 90.0:
				continue
			if ev.tipo == "uivo":
				Som.tocar("predador_uivo", Grade.ponto_mundo(ev.pos, 0.8), -4.0)
			elif ev.tipo in ["briga", "pegou"] and (ev.pos as Vector2).distance_to(foco) < 40.0:
				Som.tocar("predador_rosnado", Grade.ponto_mundo(ev.pos, 0.6), -6.0)
