class_name DesenhoPassaros
extends Node3D
## Desenho dos pássaros (Passaros), EM MASSA: cada bando vira seus pássaros (modelo leve passaro_<espécie>.glb com
## esqueleto) e cada pássaro voa por conta própria, como bando de verdade — vai para a sua vaga em volta do centro
## do bando (as vagas ondulam e giram devagar: o bando respira), alinha com o rumo do grupo, desvia dos vizinhos e
## tem um pouco de vento próprio. Pousando, cada um procura o seu galho (copa das árvores do lugar) ou um pedaço de
## chão, freia ("pousar") e fica olhando em volta / comendo ("parado"/"bicando"); decolando ou fugindo, sai um de cada
## vez numa onda (o susto passa de um para o outro). O planador-cinza plana e bate devagar.
## Sons: canto (por espécie), revoada (bando levantando) e o grito do planador.
## Fase 6: quem morre cai (o corpo despenca girando, mole, e deita na pose "morto" onde a carcaça está; o mesmo nó vira
## a carcaça: DesenhoCarcacas.corpos); a revoada de migração é uma faixa comprida e solta no rumo da viagem; os do
## chão bicam em volta dos frutos; o planador no chão fica de frente para a carne e bica; filhotes que voam do ninho
## nascem no ninho e vão para o bando.

const MAX_PASSAROS := 90          ## no máximo isso desenhado ao mesmo tempo (celular)
const ESCALA := 0.75              ## o pássaro perto das árvores do jogo (que são pequenas)
const POR_COPA := 4               ## pássaros por copa de árvore
const SEPARA := 0.35              ## m: distância que um pássaro mantém do outro

var passaros: Passaros
var foco_de: Callable             ## onde a câmera olha (sons de migração só perto)
var _bandos: Dictionary = {}      ## id do bando → Array de pássaros (ver _novo_passaro)
var _caindo: Array = []           ## fase 6: corpos despencando até o chão (depois viram carcaça)
var _nascer: Dictionary = {}      ## id do bando → [posição do ninho, quantos]: os próximos pássaros nascem ali
var _t := 0.0
var _t_mig := {}                  ## id do bando migrando → quando tocou o som pela última vez
static var _cenas: Dictionary = {}


static func _cena(esp: String) -> PackedScene:
	if not _cenas.has(esp):
		var m: Dictionary = Registro.modelos.get("passaro_" + esp, {})
		_cenas[esp] = load(m.modelo) if not m.is_empty() else null
	return _cenas[esp]


## O nó do pássaro (raiz que vira com o rumo + o modelo de lado), sem pôr na árvore. Meta "passaro" = a espécie (o 2D
## desenha o sprite dela; também o corpo morto).
static func _montar(esp: String) -> Dictionary:
	var cena := _cena(esp)
	if cena == null:
		return {}
	var raiz := Node3D.new()
	raiz.set_meta("passaro", esp)
	var mod: Node3D = cena.instantiate()
	mod.rotation.y = PI / 2.0                       # o modelo olha para +X; o jogo, para −Z
	mod.scale = Vector3.ONE * ESCALA
	raiz.add_child(mod)
	Materiais.converter(mod)
	var anims := mod.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = anims[0] if not anims.is_empty() else null
	for nome in ["voo", "planar", "parado", "bicando"]:
		if anim != null and anim.has_animation(nome):
			anim.get_animation(nome).loop_mode = Animation.LOOP_LINEAR
	return {"no": raiz, "anim": anim}


## Morto de lado ou de costas: sorteado pelo corpo (o mesmo ao cair e ao recriar a carcaça carregando o jogo).
static func de_costas(corpo: Variant) -> bool:
	return hash(str(corpo)) % 2 == 1


static func _parar_morto(anim: AnimationPlayer, costas := false) -> void:
	var nome := "morto_costas" if costas else "morto"
	if anim != null and anim.has_animation(nome):
		anim.speed_scale = 1.0
		anim.play(nome)
		anim.seek(anim.current_animation_length, true)
		anim.pause()


## Corpo do pássaro morto já deitado (a carcaça recriada ao carregar o jogo; `variante` = a espécie; `corpo` = a chave
## do corpo, que decide se caiu de lado ou de costas).
static func corpo_morto(pos: Vector3, ang: float, variante := "pardelo", corpo: Variant = "") -> Node3D:
	var m := _montar(variante if variante != "" else "pardelo")
	if m.is_empty():
		return null
	var no: Node3D = m.no
	var costas := de_costas(corpo)
	no.position = pos
	no.rotation.y = ang
	no.set_meta("pronta", true)
	no.set_meta("costas", costas)
	no.ready.connect(func(): _parar_morto(m.anim, costas), CONNECT_ONE_SHOT)
	return no


func _novo_passaro(esp: String, k: int, id: int, onde: Vector3) -> Dictionary:
	var m := _montar(esp)
	if m.is_empty():
		return {}
	var raiz: Node3D = m.no
	var anim: AnimationPlayer = m.anim
	add_child(raiz)
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
			var onde := centro
			var nasce: Array = _nascer.get(id, [])
			if not nasce.is_empty():                   # filhote saindo do ninho: nasce lá
				onde = nasce[0]
				nasce[1] = int(nasce[1]) - 1
				if int(nasce[1]) <= 0:
					_nascer.erase(id)
			var p := _novo_passaro(String(b.especie), lista.size(), int(id), onde)
			if p.is_empty():
				break
			if onde != centro:
				(p.no as Node3D).position = onde
			lista.append(p)
		_bandos[id] = lista
		total += lista.size()
		_desenhar_bando(b, lista, delta)
	for id in _bandos.keys():
		if not passaros.bandos.has(id):
			for p in _bandos[id]:
				(p.no as Node3D).queue_free()
			_bandos.erase(id)
	_cair(delta)


## Onde o pássaro `i` fica parado: num galho de uma das copas do lugar, senão no chão em volta (perto dos frutos,
## quando há: bicando). O planador pousa onde a lógica pôs (do lado da carne).
func _lugar_parado(b: Dictionary, p: Dictionary, i: int) -> Vector3:
	if b.especie == "planador":
		return Grade.ponto_mundo(b.pos, 0.02)
	var poleiros: Array = b.get("poleiros", [])
	var frutas: Array = b.get("frutas", [])
	var nos_galhos := poleiros.size() * POR_COPA
	if not frutas.is_empty() and i >= mini(nos_galhos, int(b.n) / 2):   # metade (pelo menos) desce aos frutos
		var fr: Vector2 = frutas[i % frutas.size()]
		p.come = true
		return Grade.ponto_mundo(fr + Vector2.from_angle(float(p.fase) * TAU) * (0.16 + 0.1 * float(i % 3)), 0.02)
	if i < nos_galhos:
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
		elif estado == Passaros.E.MIGRANDO:
			# revoada de migração: faixa comprida e solta no rumo da viagem (uns na frente, outros atrás e dos lados)
			var vg: Vector3 = p.vaga
			var rm: Vector2 = b.get("rumo_mig", Vector2.UP)
			var fr := Vector3(rm.x, 0.0, -rm.y)
			var ld := Vector3(-fr.z, 0.0, fr.x)
			var ang := _t * 0.5 + float(p.fase) * TAU
			alvo = centro + (fr * vg.x * 3.2 + ld * vg.z * 1.3 + Vector3.UP * vg.y * 0.8) * espalha \
					+ Vector3(sin(ang), sin(ang * 1.4) * 0.4, cos(ang * 0.7)) * 0.5
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
		if parado_aqui and bool(p.pousado) and b.get("olha") != null:   # o planador de frente para a carne
			var ol := Grade.ponto_mundo(b.olha) - no.position
			p.rumo = atan2(-ol.x, -ol.z)
			p.come = true
		elif parado_aqui and bool(p.pousado) and not (b.get("frutas", []) as Array).is_empty() and bool(p.come):
			var fr := Grade.ponto_mundo(_fruta_perto(b, no.position)) - no.position
			if Vector2(fr.x, fr.z).length() > 0.05:
				p.rumo = atan2(-fr.x, -fr.z)            # bicando o fruto
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
			var no_fruto := not (b.get("frutas", []) as Array).is_empty() or b.get("olha") != null
			p.come = randf() < (0.85 if no_fruto else 0.55)
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
			"morreu":
				_derrubar(e)
			"migracao":
				var foco: Vector2 = foco_de.call() if foco_de.is_valid() else (e.pos as Vector2)
				if (e.pos as Vector2).distance_to(foco) < 45.0 and Time.get_ticks_msec() - int(_t_mig.get(e.id, -99999)) > 4500:
					_t_mig[e.id] = Time.get_ticks_msec()
					Som.tocar("bando_migrando", Grade.ponto_mundo(e.pos, minf(float(e.get("alt", 18.0)), 12.0)), -4.0)
			"mergulho":
				Som.tocar("planador_grito", Grade.ponto_mundo(e.pos, float(e.get("alt", 10.0))), -1.0)
			"voaram":                              # filhotes do ninho: os novos do bando nascem no ninho
				_nascer[e.para] = [Grade.ponto_mundo(e.pos, float(e.get("alto", 1.5))), int(e.n)]


## Os pássaros no chão agora (pousados rente ao chão, não nos galhos): [posição, raio] para o capim abrir em volta.
func no_chao() -> Array:
	var out: Array = []
	for lista in _bandos.values():
		for p in lista:
			var no: Node3D = p.no
			if bool(p.pousado) and is_instance_valid(no):
				var g := Vector2(no.position.x, -no.position.z)
				if no.position.y - Grade.altura_em(g) < 0.12:
					out.append([g, 0.6 if String(no.get_meta("passaro", "")) == "planador" else 0.18])
	return out


func _fruta_perto(b: Dictionary, onde: Vector3) -> Vector2:
	var melhor: Vector2 = b.frutas[0]
	var p := Vector2(onde.x, -onde.z)
	for f: Vector2 in b.frutas:
		if f.distance_to(p) < melhor.distance_to(p):
			melhor = f
	return melhor


## Um pássaro do bando morreu: o desenhado mais perto de onde a carcaça vai ficar despenca até lá (mole, girando),
## deita na pose "morto" e passa para o DesenhoCarcacas (o mesmo nó vira a carcaça).
func _derrubar(e: Dictionary) -> void:
	var lista: Array = _bandos.get(e.id, [])
	if lista.is_empty():
		return                                         # não estava desenhado: a carcaça aparece já deitada
	var chao := Grade.ponto_mundo(e.pos, 0.0)
	var k := 0
	for i in lista.size():
		if (lista[i].no as Node3D).position.distance_to(chao) < (lista[k].no as Node3D).position.distance_to(chao):
			k = i
	var p: Dictionary = lista[k]
	lista.remove_at(k)
	var no: Node3D = p.no
	var costas := de_costas(e.corpo)
	no.set_meta("costas", costas)
	_parar_morto(p.anim, costas)
	var v: Vector3 = p.vel
	_caindo.append({"no": no, "vel": Vector3(v.x * 0.4, minf(v.y, 0.5), v.z * 0.4), "chao": chao, "corpo": String(e.corpo),
			"giro": Vector3(randf_range(-7.0, 7.0), randf_range(-3.0, 3.0), randf_range(-7.0, 7.0)), "t": 0.0})


func _cair(delta: float) -> void:
	for i in range(_caindo.size() - 1, -1, -1):
		var c: Dictionary = _caindo[i]
		var no: Node3D = c.no
		if not is_instance_valid(no):
			_caindo.remove_at(i)
			continue
		c.t = float(c.t) + delta
		var chao: Vector3 = c.chao
		var v: Vector3 = c.vel
		v.y -= 9.8 * delta
		var h := Vector2(chao.x - no.position.x, chao.z - no.position.z)   # a deriva leva ao lugar da carcaça
		var falta := maxf(0.15, sqrt(maxf(0.0, 2.0 * maxf(no.position.y - chao.y, 0.0) / 9.8)))
		v.x = lerpf(v.x, h.x / falta, clampf(delta * 4.0, 0.0, 1.0))
		v.z = lerpf(v.z, h.y / falta, clampf(delta * 4.0, 0.0, 1.0))
		v.y = maxf(v.y, -14.0)
		c.vel = v
		no.position += v * delta
		var alto := no.position.y - chao.y
		var giro: Vector3 = c.giro
		var mole := clampf(alto / 1.2, 0.0, 1.0)           # perto do chão, endireita para deitar na pose
		no.rotation.x = lerp_angle(0.0, no.rotation.x + giro.x * delta, mole)
		no.rotation.z = lerp_angle(0.0, no.rotation.z + giro.z * delta, mole)
		no.rotation.y += giro.y * delta * mole
		if alto <= 0.0 or float(c.t) > 6.0:
			no.position = chao
			no.rotation.x = 0.0
			no.rotation.z = 0.0
			no.set_meta("bicho", c.corpo)
			no.set_meta("pronta", true)
			DesenhoCarcacas.corpos[c.corpo] = no
			_caindo.remove_at(i)
