class_name DesenhoNinhosPassaros
extends Node3D
## Patch fauna, fase 6: o desenho dos ninhos dos pássaros (NinhosPassaros), perto da câmera. O ninho fica no lugar
## certo da árvore (dados/ninhos_arvores.json: os pontos de cada modelo de árvore, achados nos galhos dela pela
## exportação; a árvore gira com o tile, o ninho junto). Em obra, cresce (graveto a graveto). Adultos do bando vêm
## e voltam (visita: com graveto na obra, com comida para os filhotes); filhotes piam (som) de dia. Quando o ninho cai
## (árvore cortada/queimada, construção, velho no inverno), ele despenca até o chão e some depois de um tempo.

const RAIO := 60.0               ## m da câmera: ninho desenhado
const MAX_VISITAS := 4
const CAIDO_S := 40.0             ## s que o ninho caído fica no chão antes de sumir

var ninhos: NinhosPassaros
var clima: Clima
var foco_de: Callable
var nos: Dictionary = {}          ## tile → {no, tipo, n}
var visitas: Array = []           ## adultos indo ao ninho e voltando: {no, anim, acao, de, ninho, fase, t, rumo, esp}
var caindo: Array = []            ## ninhos caídos: {no, vel, chao, t}
var _t_piado: Dictionary = {}
static var _cenas: Dictionary = {}
static var _locais: Dictionary = {}


static func cena(tipo: String) -> PackedScene:
	if not _cenas.has(tipo):
		var m: Dictionary = Registro.modelos.get("ninho_" + tipo, {})
		_cenas[tipo] = load(m.modelo) if not m.is_empty() else null
	return _cenas[tipo]


## Pontos do ninho no modelo da árvore (coordenadas do modelo, no Godot): [{p, giro, galho}…]. Taça = a forquilha;
## bolsa = na beira de baixo da copa, com o giro que aponta o raminho dela para a ponta de galho `galho` (de onde o
## raminho fino vem). Sem dado para a árvore: no meio da copa.
static func pontos(arvore: String, tipo: String) -> Array:
	if _locais.is_empty():
		var f := FileAccess.open("res://dados/ninhos_arvores.json", FileAccess.READ)
		_locais = JSON.parse_string(f.get_as_text()) if f != null else {}
		if _locais == null:
			_locais = {}
		_locais["_lido"] = true
	var d: Dictionary = _locais.get(arvore, {})
	var out: Array = []
	for p in d.get(tipo, []):
		var q := {"p": Vector3(float(p[0]), float(p[1]), float(p[2])), "giro": float(p[3]) if p.size() > 3 else 0.0}
		if p.size() > 6:
			q.galho = Vector3(float(p[4]), float(p[5]), float(p[6]))
		out.append(q)
	if out.is_empty():
		var alto := float(Registro.modelos.get(arvore, {}).get("dims", [1, 1, 2])[2])
		if tipo == "bolsa":
			for k in 3:
				out.append({"p": Vector3(cos(k * 2.1) * 0.22, alto * 0.68, sin(k * 2.1) * 0.22), "giro": k * 2.1})
		else:
			out.append({"p": Vector3(0.0, alto * 0.64, 0.0), "giro": 0.0})
	return out


## Transformação da árvore no tile (a mesma do DesenhoChunk: gira com o tile, no relevo).
static func da_arvore(g: GeradorMundo, t: Vector2i) -> Transform3D:
	var o := g.distribuicao.obstaculo(t)
	if o.is_empty():
		return Transform3D(Basis(), Grade.ponto_mundo(Vector2(t) + Vector2(0.5, 0.5)))
	var centro := Grade.centro_da_area(o.ancora, o.area, 0)
	return Transform3D(Basis(Vector3.UP, Grade.angulo(o.rot)), Grade.ponto_mundo(centro, g.micro_em(centro - Vector2(0.5, 0.5))))


## Pontos do ninho `n`: na árvore (pelo modelo) ou, na fase 7, no alto da estrutura (poste, silo).
static func pontos_de(n: Dictionary) -> Array:
	if n.has("estrutura"):
		return [{"p": Vector3(0.0, float(n.alto), 0.0), "giro": 0.0}]
	return pontos(String(n.arvore), String(n.tipo))


## Transformação de onde o ninho está: a da árvore no tile, ou a da estrutura (centro, girada, no relevo).
func transformacao(n: Dictionary) -> Transform3D:
	if n.has("estrutura"):
		var e: Dictionary = ninhos.passaros.mapa.estruturas.get(int(n.estrutura), {})
		if not e.is_empty():
			return Transform3D(Basis(Vector3.UP, Grade.angulo(e.rot)), Grade.ponto_mundo(Grade.centro_da_area(e.minimo, e.area, e.rot)))
		return Transform3D(Basis(), Grade.ponto_mundo(n.pos))
	return da_arvore(ninhos.passaros.gerador, n.tile)


## Onde fica (mundo) o ninho `n` (o primeiro ponto; a bolsa tem um por bolsa).
func ponto_do_ninho(n: Dictionary, k := 0) -> Vector3:
	var ps := pontos_de(n)
	return transformacao(n) * (ps[k % ps.size()].p as Vector3)


func _process(delta: float) -> void:
	if ninhos == null:
		return
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	var dia := clima == null or clima.luz_dia() >= 0.2
	var d: Dictionary = Registro.fauna.get("ninhos", {})
	var vistos := {}
	for t in ninhos.ninhos:
		var n: Dictionary = ninhos.ninhos[t]
		if (n.pos as Vector2).distance_to(foco) > RAIO:
			continue
		var r := _garantir(n)
		if r.is_empty():
			continue
		vistos[t] = true
		var cresce := 1.0
		if int(n.fase) == NinhosPassaros.F.OBRA:
			cresce = lerpf(0.3, 1.0, clampf(float(n.t) / float(d.get("obra_s", 240.0)), 0.0, 1.0))
		for c in (r.no as Node3D).get_children():
			if c.has_meta("piv"):
				(c as Node3D).scale = Vector3.ONE * cresce
		# filhotes piando de dia, perto da câmera
		if int(n.fase) == NinhosPassaros.F.FILHOTES and dia and (n.pos as Vector2).distance_to(foco) < float(d.get("som_dist", 18.0)):
			var t_p := float(_t_piado.get(t, 0.0)) - delta
			if t_p <= 0.0:
				var ps: Array = d.get("piado_s", [3, 7])
				t_p = randf_range(float(ps[0]), float(ps[1]))
				Som.tocar("filhotes", ponto_do_ninho(n), -3.0)
			_t_piado[t] = t_p
	for t in nos.keys():
		if not vistos.has(t):
			(nos[t].no as Node3D).queue_free()
			nos.erase(t)
	_visitar(delta)
	_cair(delta)


func _garantir(n: Dictionary) -> Dictionary:
	var r: Dictionary = nos.get(n.tile, {})
	if not r.is_empty() and int(r.n) == int(n.n):
		return r
	if not r.is_empty():
		(r.no as Node3D).queue_free()
	var cn := cena(String(n.tipo))
	if cn == null:
		return {}
	var raiz := Node3D.new()
	raiz.set_meta("ninho", String(n.tipo))           # o 2D desenha o sprite do ninho
	add_child(raiz)
	var ps := pontos_de(n)
	var tr := transformacao(n)
	for k in mini(int(n.n), ps.size()):
		var m: Node3D = cn.instantiate()
		Materiais.converter(m)
		var piv := Node3D.new()
		piv.position = tr * (ps[k].p as Vector3)
		piv.set_meta("piv", true)                      # (o 2D desenha um sprite por pivô)
		piv.rotation.y = tr.basis.get_euler().y + float(ps[k].giro)
		piv.add_child(m)
		raiz.add_child(piv)
		if ps[k].has("galho"):                          # o raminho fino da ponta do galho até a bolsa (vergando)
			var fim := piv.transform * Vector3(-0.0525, 0.0225, 0.0)
			raiz.add_child(_raminho(tr * (ps[k].galho as Vector3), fim))
	r = {"no": raiz, "tipo": String(n.tipo), "n": int(n.n)}
	nos[n.tile] = r
	return r


static var _mat_raminho: StandardMaterial3D


## Raminho fino de `a` (ponta do galho) até `b` (a bolsa), vergando um pouco no meio: tubo de 4 lados.
func _raminho(a: Vector3, b: Vector3) -> MeshInstance3D:
	if _mat_raminho == null:
		_mat_raminho = StandardMaterial3D.new()
		_mat_raminho.albedo_color = Color(0.2, 0.15, 0.1)
		_mat_raminho.roughness = 0.95
	var meio := (a + b) * 0.5 + Vector3(0.0, -0.025 * a.distance_to(b) / 0.3, 0.0)
	var pts := [a, a.lerp(meio, 0.5) + Vector3(0, -0.004, 0), meio, meio.lerp(b, 0.5) - Vector3(0, 0.003, 0), b]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var aneis: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var u := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.95 else Vector3.RIGHT
		var v := dir.cross(u)
		var r := lerpf(0.006, 0.0028, float(i) / (pts.size() - 1))
		var anel: Array = []
		for k in 4:
			anel.append(p + (u * cos(k * PI / 2.0) + v * sin(k * PI / 2.0)) * r)
		aneis.append(anel)
	for i in aneis.size() - 1:
		for k in 4:
			var a0: Vector3 = aneis[i][k]
			var a1: Vector3 = aneis[i][(k + 1) % 4]
			var b0: Vector3 = aneis[i + 1][k]
			var b1: Vector3 = aneis[i + 1][(k + 1) % 4]
			for q in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat_raminho
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func efeitos_de(eventos: Array) -> void:
	if ninhos == null:
		return
	var foco: Vector2 = foco_de.call() if foco_de.is_valid() else Vector2.ZERO
	for e in eventos:
		match String(e.get("tipo", "")):
			"visita":
				if visitas.size() < MAX_VISITAS and (e.pos as Vector2).distance_to(foco) < RAIO and ninhos.ninhos.has(e.tile):
					_nova_visita(e)
			"caiu":
				var r: Dictionary = nos.get(e.tile, {})
				if not r.is_empty():
					nos.erase(e.tile)
					var no: Node3D = r.no
					var alto := 99.0                          # quanto cai: do ponto mais baixo até o chão
					var bolsa := String(r.tipo) == "bolsa"
					for piv: Node3D in no.get_children():
						if not piv.has_meta("piv"):
							piv.queue_free()                  # o raminho fica (some com o galho)
							continue
						alto = minf(alto, piv.position.y - Grade.altura_em(Vector2(piv.position.x, -piv.position.z)))
					alto = 1.0 if alto > 50.0 else alto
					alto = maxf(0.0, alto - (0.05 if bolsa else 0.0))
					caindo.append({"no": no, "vel": Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)),
							"base_y": no.position.y, "queda": 0.0, "alto": alto, "t": 0.0, "bolsa": bolsa,
							"giro": randf_range(-2.0, 2.0)})


# ------------------------------------------------------------------ adulto visitando
func _nova_visita(e: Dictionary) -> void:
	var m := DesenhoPassaros._montar(String(e.especie))
	if m.is_empty():
		return
	var no: Node3D = m.no
	add_child(no)
	var n: Dictionary = ninhos.ninhos[e.tile]
	var alvo := ponto_do_ninho(n, randi() % maxi(1, int(n.n)))
	if n.tipo == "bolsa":
		alvo += Vector3(0.0, -0.18, 0.0)              # agarra na boca da bolsa
	else:
		alvo += Vector3(0.0, 0.035, 0.0)              # na beira da taça
	var de := Grade.ponto_mundo(e.de, 5.0)
	if de.distance_to(alvo) > 30.0:
		de = alvo + (de - alvo).normalized() * 30.0
	no.position = de
	visitas.append({"no": no, "anim": m.anim, "acao": "", "de": de, "ninho": alvo, "fase": 0, "t": 0.0, "esp": String(e.especie)})


func _tocar(v: Dictionary, nome: String, vel := 1.0, ao_contrario := false) -> void:
	var anim: AnimationPlayer = v.anim
	if anim == null or not anim.has_animation(nome) or v.acao == nome + ("<" if ao_contrario else ""):
		return
	v.acao = nome + ("<" if ao_contrario else "")
	anim.speed_scale = vel
	if ao_contrario:
		anim.play_backwards(nome)
	else:
		anim.play(nome, 0.12)


## Vai voando até o ninho (descendo no fim), pousa, fica uns segundos e volta para o bando.
func _visitar(delta: float) -> void:
	for i in range(visitas.size() - 1, -1, -1):
		var v: Dictionary = visitas[i]
		var no: Node3D = v.no
		if not is_instance_valid(no):
			visitas.remove_at(i)
			continue
		v.t = float(v.t) + delta
		var alvo: Vector3 = v.ninho if int(v.fase) <= 1 else v.de
		var d := alvo - no.position
		match int(v.fase):
			0:                                         # indo
				no.position = no.position.move_toward(alvo, delta * clampf(d.length() * 2.0, 1.2, 7.0))
				_tocar(v, "pousar" if d.length() < 0.9 else "voo", 1.0 if d.length() < 0.9 else 1.3)
				if d.length() < 0.02:
					v.fase = 1
					v.t = 0.0
			1:                                         # no ninho
				_tocar(v, "parado", 1.4)
				if float(v.t) > randf_range(2.5, 4.0):
					v.fase = 2
					v.t = 0.0
			2:                                         # voltando
				no.position = no.position.move_toward(alvo, delta * 7.0)
				_tocar(v, "voo", 1.3)
				if d.length() < 0.5 or float(v.t) > 8.0:
					no.queue_free()
					visitas.remove_at(i)
					continue
		var h := Vector2(d.x, d.z)
		if h.length() > 0.05 and int(v.fase) != 1:
			no.rotation.y = rotate_toward(no.rotation.y, atan2(-d.x, -d.z), delta * 8.0)


# ------------------------------------------------------------------ ninho caindo
func _cair(delta: float) -> void:
	for i in range(caindo.size() - 1, -1, -1):
		var c: Dictionary = caindo[i]
		var no: Node3D = c.no
		if not is_instance_valid(no):
			caindo.remove_at(i)
			continue
		c.t = float(c.t) + delta
		if float(c.queda) < float(c.alto):
			var v: Vector3 = c.vel
			v.y -= 9.8 * delta
			c.vel = v
			c.queda = minf(float(c.alto), float(c.queda) - v.y * delta)
			no.position = Vector3(no.position.x + v.x * delta, float(c.base_y) - float(c.queda), no.position.z + v.z * delta)
			if bool(c.bolsa):                              # a bolsa tomba e deita de lado no chão
				for piv: Node3D in no.get_children():
					if piv.has_meta("piv"):
						piv.rotation.x = minf(1.5, piv.rotation.x + delta * 3.0)
		var some := clampf((float(c.t) - CAIDO_S) / 4.0, 0.0, 1.0)
		if some > 0.0:
			no.scale = Vector3.ONE * (1.0 - some)
		if some >= 1.0:
			no.queue_free()
			caindo.remove_at(i)
