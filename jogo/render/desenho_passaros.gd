class_name DesenhoPassaros
extends Node3D
## Desenho dos pássaros (Passaros), EM MASSA: cada bando vira seus pássaros (modelo leve passaro_<espécie>.glb com
## esqueleto) e cada pássaro voa por conta própria, como bando de verdade — vai para a sua vaga em volta do centro
## do bando (as vagas ondulam e giram devagar: o bando respira), alinha com o rumo do grupo, desvia dos vizinhos e
## tem um pouco de vento próprio. Pousando, cada um procura o seu galho (copa das árvores do lugar) ou um pedaço de
## chão, freia ("pousar") e fica olhando em volta / comendo ("parado"/"bicando"); decolando ou fugindo, sai um de cada
## vez numa onda (o susto passa de um para o outro). O planador-cinza plana e bate devagar.
## Sons: canto (por espécie), revoada (bando levantando) e o grito do planador.

const MAX_PASSAROS := 90          ## no máximo isso desenhado ao mesmo tempo (celular)
const ESCALA := 0.75              ## o pássaro perto das árvores do jogo (que são pequenas)
const POR_COPA := 4               ## pássaros por copa de árvore
const SEPARA := 0.35              ## m: distância que um pássaro mantém do outro

var passaros: Passaros
var _bandos: Dictionary = {}      ## id do bando → Array de pássaros (ver _novo_passaro)
var _cenas: Dictionary = {}
var _t := 0.0


func _cena(esp: String) -> PackedScene:
	if not _cenas.has(esp):
		var m: Dictionary = Registro.modelos.get("passaro_" + esp, {})
		_cenas[esp] = load(m.modelo) if not m.is_empty() else null
	return _cenas[esp]


func _novo_passaro(esp: String, k: int, id: int, onde: Vector3) -> Dictionary:
	var cena := _cena(esp)
	if cena == null:
		return {}
	var raiz := Node3D.new()
	var mod: Node3D = cena.instantiate()
	mod.rotation.y = PI / 2.0                       # o modelo olha para +X; o jogo, para −Z
	mod.scale = Vector3.ONE * ESCALA
	raiz.add_child(mod)
	add_child(raiz)
	Materiais.converter(mod)
	var anims := mod.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = anims[0] if not anims.is_empty() else null
	for nome in ["voo", "planar", "parado", "bicando"]:
		if anim != null and anim.has_animation(nome):
			anim.get_animation(nome).loop_mode = Animation.LOOP_LINEAR
	var h := float(hash(Vector2i(id, k)) % 1000) / 1000.0
	var h2 := float(hash(Vector2i(k, id * 7)) % 1000) / 1000.0
	raiz.position = onde + Vector3((h - 0.5) * 3.0, (h2 - 0.5), (h2 - 0.5) * 3.0)
	return {"no": raiz, "anim": anim, "fase": h, "k": k, "vel": Vector3.ZERO, "vaga": Vector3(h - 0.5, h2 - 0.5, fposmod(h * 7.3, 1.0) - 0.5),
			"chao_off": Vector2.from_angle(h * TAU) * sqrt(h2), "t_troca": h * 4.0, "acao": "", "rumo": h * TAU,
			"planando": 0.0, "pousado": false, "espera": 0.0, "estado_ant": -1, "come": false}


func _tocar(p: Dictionary, nome: String, vel := 1.0, ao_contrario := false) -> void:
	var anim: AnimationPlayer = p.anim
	if anim == null or not anim.has_animation(nome):
		return
	anim.speed_scale = vel
	var chave := nome + ("<" if ao_contrario else "")
	if p.acao == chave:
		return
	p.acao = chave
	if ao_contrario:
		anim.play_backwards(nome)
	else:
		anim.play(nome, 0.12)
		if anim.get_animation(nome).loop_mode != Animation.LOOP_NONE:
			anim.seek(float(p.fase) * anim.current_animation_length, true)


func _process(delta: float) -> void:
	if passaros == null:
		return
	_t += delta
	var total := 0
	for id in passaros.bandos:
		var b: Dictionary = passaros.bandos[id]
		var lista: Array = _bandos.get(id, [])
		var centro := Grade.ponto_mundo(b.pos, float(b.alt))
		while lista.size() < int(b.n) and total + lista.size() < MAX_PASSAROS:
			var p := _novo_passaro(String(b.especie), lista.size(), int(id), centro)
			if p.is_empty():
				break
			lista.append(p)
		_bandos[id] = lista
		total += lista.size()
		_desenhar_bando(b, lista, delta)
	for id in _bandos.keys():
		if not passaros.bandos.has(id):
			for p in _bandos[id]:
				(p.no as Node3D).queue_free()
			_bandos.erase(id)


## Onde o pássaro `i` fica parado: num galho de uma das copas do lugar, senão no chão em volta.
func _lugar_parado(b: Dictionary, p: Dictionary, i: int) -> Vector3:
	var poleiros: Array = b.get("poleiros", [])
	if i < poleiros.size() * POR_COPA:
		var pol: Array = poleiros[i % poleiros.size()]
		var anel := i / poleiros.size()
		var c: Vector2 = (pol[0] as Vector2) + Vector2.from_angle(float(anel) * 1.6 + float(p.fase) * 1.3) * 0.2
		return Grade.ponto_mundo(c, float(pol[1]) - 0.07 * float(anel))
	var co: Vector2 = (p.chao_off as Vector2) * (0.6 + sqrt(float(b.n)) * 0.25)
	return Grade.ponto_mundo((b.pos as Vector2) + co, 0.02)


func _desenhar_bando(b: Dictionary, lista: Array, delta: float) -> void:
	var esp := String(b.especie)
	var grande := esp == "planador"
	var estado := int(b.estado)
	var v2: Vector2 = b.vel
	var vel_bando := Vector3(v2.x, 0.0, -v2.y)
	var centro := Grade.ponto_mundo(b.pos, float(b.alt))
	var espalha := 0.0 if grande else 0.7 + sqrt(float(lista.size())) * 0.32
	var no_chao := estado in [Passaros.E.POUSADO, Passaros.E.POUSANDO]
	var saindo := estado in [Passaros.E.DECOLANDO, Passaros.E.FUGINDO]
	var n := lista.size()
	for i in n:
		var p: Dictionary = lista[i]
		var no: Node3D = p.no
		# mudou o estado do bando: decolagem/fuga em onda (cada um espera um pouco: o susto passa de um para o outro)
		if int(p.estado_ant) != estado:
			if saindo and bool(p.pousado):
				p.espera = float(p.fase) * (0.25 if estado == Passaros.E.FUGINDO else 0.7)
			p.estado_ant = estado
		var alvo: Vector3
		var parado_aqui := false
		if no_chao:
			alvo = _lugar_parado(b, p, i)
			parado_aqui = true
		elif bool(p.pousado) and float(p.espera) > 0.0:
			p.espera = float(p.espera) - delta
			alvo = no.position
			parado_aqui = true
		else:
			# vaga em volta do centro: gira e ondula devagar (o bando "respira" e muda de forma)
			var vg: Vector3 = p.vaga
			var ang := _t * 0.35 + float(p.fase) * TAU
			var ond := Vector3(sin(ang + vg.x * 5.0), sin(ang * 1.3 + vg.y * 4.0) * 0.5, cos(ang * 0.8 + vg.z * 5.0))
			alvo = centro + (vg * 2.0 + ond * 0.35) * espalha
		var pos := no.position
		if parado_aqui and bool(p.pousado):
			no.position = no.position.lerp(alvo, clampf(delta * 3.0, 0.0, 1.0))
		else:
			# voo próprio: vai para a vaga, alinha com o bando, desvia dos vizinhos
			var vel: Vector3 = p.vel
			var quer := (alvo - pos) * (2.2 if parado_aqui else 1.4) + vel_bando * (0.0 if parado_aqui else 0.9)
			for j in range(maxi(0, i - 4), mini(n, i + 5)):    # vizinhos de lista (barato e basta para não colar)
				if j == i:
					continue
				var d: Vector3 = pos - (lista[j].no as Node3D).position
				var dl := d.length()
				if dl < SEPARA and dl > 0.001:
					quer += d / dl * (SEPARA - dl) * 12.0
			quer += Vector3(sin(_t * 1.7 + float(p.fase) * 9.0), 0.0, cos(_t * 1.3 + float(p.fase) * 7.0)) * 0.6
			var vmax := (8.0 if grande else 11.0) * (1.4 if estado == Passaros.E.FUGINDO else 1.0)
			vel = vel.lerp(quer, clampf(delta * 2.2, 0.0, 1.0)).limit_length(vmax)
			p.vel = vel
			no.position = pos + vel * delta
			if parado_aqui and no.position.distance_to(alvo) < 0.12:
				p.pousado = true                       # chegou ao galho/chão
			elif not parado_aqui:
				p.pousado = false
			var horiz := Vector2(vel.x, vel.z)
			if horiz.length() > 0.3:
				p.rumo = atan2(-vel.x, -vel.z)
		no.rotation.y = rotate_toward(no.rotation.y, float(p.rumo), delta * 6.0)
		_animar(b, p, estado, parado_aqui, delta)


func _animar(b: Dictionary, p: Dictionary, estado: int, parado_aqui: bool, delta: float) -> void:
	if estado == Passaros.E.CIRCULANDO:
		p.planando = float(p.planando) - delta     # planador: plana e de vez em quando bate um pouco
		if p.planando < -2.0:
			p.planando = randf_range(6.0, 12.0)
		_tocar(p, "planar" if p.planando > 0.0 else "voo", 1.0 if p.planando > 0.0 else 0.55)
		return
	if parado_aqui and bool(p.pousado):
		if float(p.espera) > 0.0:
			_tocar(p, "parado", 1.6)                # olhando, prestes a sair
			return
		p.t_troca = float(p.t_troca) - delta
		if p.t_troca <= 0.0:                       # alterna olhar em volta e comer; às vezes vira o corpo
			p.t_troca = randf_range(1.5, 4.5)
			p.rumo = float(p.rumo) + randf_range(-1.2, 1.2)
			p.come = randf() < 0.55
		if bool(b.dormindo):
			_tocar(p, "parado", 0.15)
		else:
			_tocar(p, "bicando" if bool(p.come) else "parado", 1.0)
		return
	if parado_aqui:                                # chegando no galho: freia e fecha as asas
		_tocar(p, "pousar", 1.0)
		return
	if p.acao == "pousar" or p.acao == "parado" or p.acao == "bicando":
		_tocar(p, "pousar", 1.5, true)            # saiu do galho: decola
		return
	if p.acao == "pousar<" and p.anim != null and (p.anim as AnimationPlayer).is_playing():
		return
	# no ar: batem e planam em ondas curtas (voo ondulado); fugindo, só batem, mais rápido
	p.planando = float(p.planando) - delta
	if p.planando < -0.9:
		p.planando = randf_range(0.3, 0.7)
	var plana: bool = float(p.planando) > 0.0 and estado != Passaros.E.FUGINDO
	_tocar(p, "planar" if plana else "voo", 1.0 if plana else (1.6 if estado == Passaros.E.FUGINDO else 1.2))


## Eventos do Passaros (o mundo chama com a lista e depois limpa): sons e bandos que se juntaram.
func efeitos_de(eventos: Array) -> void:
	for e in eventos:
		match String(e.get("tipo", "")):
			"canto":
				Som.tocar(String(e.som), Grade.ponto_mundo(e.pos, float(e.get("alt", 0.0))), -2.0)
			"revoada":
				Som.tocar("revoada", Grade.ponto_mundo(e.pos, 0.5), -3.0)
			"juntou":                              # os pássaros do bando que sumiu passam para o outro (sem piscar)
				if _bandos.has(e.de):
					var dst: Array = _bandos.get(e.para, [])
					dst.append_array(_bandos[e.de])
					_bandos[e.para] = dst
					_bandos.erase(e.de)
