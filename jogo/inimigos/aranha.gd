class_name Aranha
extends Node3D
## Aranha mecânica visível: corpo + 6 pernas (fêmur e tíbia soltos) posadas por MarchaAranha + IK a cada quadro.
## A lógica de passo (e a garantia de não deslizar) está em marcha_aranha.gd, testada em testes/test_aranha.gd.

const CORPO := preload("res://assets/modelos/inimigos/aranha/aranha_corpo.glb")
const FEMUR := preload("res://assets/modelos/inimigos/aranha/aranha_femur.glb")
const TIBIA := preload("res://assets/modelos/inimigos/aranha/aranha_tibia.glb")

var marcha: MarchaAranha
var destino := Vector3.ZERO
var rumo_desejado := 0.0
var atacando := false             ## golpeia com o par da frente (no ar: não conta como pé plantado)
var alvo_golpe := Vector3.ZERO
var _morta := false
var fica := false                 ## patch fauna, fase 4: depois da queda o corpo fica (vira sucata do DesenhoCarcacas)
var _t_morte := 0.0
var _pe_morte: Array[Vector3] = []   ## onde cada pé estava quando morreu (desliza para fora dali)
var _corpo: Node3D
var _femures: Array[Node3D] = []
var _tibias: Array[Node3D] = []
var _furia := 0.0


func _init(pos := Vector3.ZERO, p_rumo := 0.0) -> void:
	position = pos
	rotation.y = p_rumo
	marcha = MarchaAranha.new(pos, p_rumo)
	destino = pos
	rumo_desejado = p_rumo


func _ready() -> void:
	var p := global_position if is_inside_tree() and global_position != Vector3.ZERO else position
	if marcha == null:
		marcha = MarchaAranha.new(p, rotation.y)
	elif global_position != Vector3.ZERO:
		marcha.posicao = global_position
		marcha.rumo = rotation.y
		destino = global_position
		rumo_desejado = rotation.y
	_corpo = CORPO.instantiate()
	add_child(_corpo)
	Materiais.converter(_corpo)
	for i in 6:
		var f: Node3D = FEMUR.instantiate()
		var t: Node3D = TIBIA.instantiate()
		Materiais.converter(f)
		Materiais.converter(t)
		f.top_level = true
		t.top_level = true
		add_child(f)
		add_child(t)
		_femures.append(f)
		_tibias.append(t)


## Fúria (0..1, chão sujo em volta do ninho): os olhos acendem mais e puxam para o vermelho.
func definir_furia(f: float) -> void:
	if absf(f - _furia) < 0.1:
		return
	_furia = f
	for n in _corpo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var base: Material = mi.mesh.surface_get_material(s)
			if base == null or base.resource_name != "P_OlhoInimigo":
				continue
			var m: ShaderMaterial = Materiais.material(base).duplicate()
			var c: Color = m.get_shader_parameter("cor_emissao")
			m.set_shader_parameter("cor_emissao", c.lerp(Color(1.0, 0.08, 0.02), f))
			m.set_shader_parameter("forca_emissao", float(m.get_shader_parameter("forca_emissao")) * (1.0 + 2.5 * f))
			mi.set_surface_override_material(s, m)


func ir_para(p: Vector3) -> void:
	destino = p
	var d := p - marcha.posicao
	if Vector2(d.x, d.z).length() > 0.005:
		rumo_desejado = atan2(-d.x, -d.z)


## Encara um ponto (para atacar) sem sair do lugar.
func encarar(p: Vector3) -> void:
	var d := p - marcha.posicao
	if Vector2(d.x, d.z).length() > 0.005:
		rumo_desejado = atan2(-d.x, -d.z)


const MORTE_QUEDA := 0.6          ## s: o corpo cai até a barriga encostar no chão e as pernas se abrem
const MORTE_FICA := 0.6           ## s: a carcaça fica parada antes de sumir
const MORTE_DESCE := 0.2          ## m: a barriga (0,225 m do chão) encosta no chão
const MORTE_TOMBA := 0.22         ## rad: tomba de lado
const MORTE_ABRE := 0.35          ## m: os pés escorregam para fora


## Morte: as pernas cedem e se abrem, o corpo cai na barriga e tomba de lado, fica um instante e some
## (faíscas ficam por conta de quem chamou). A versão 2D desenha a mesma pose (sprite "morte").
func morrer() -> void:
	if _morta:
		return
	_morta = true
	atacando = false
	_t_morte = 0.0
	_pe_morte.clear()
	for i in 6:
		_pe_morte.append(marcha.pes[i])


## Pose final da morte, direto (sucata recriada ao carregar o jogo). Chamar depois de entrar na árvore.
func pose_morta() -> void:
	fica = true
	morrer()
	_t_morte = MORTE_QUEDA
	_morrendo(0.0)
	set_process(false)


func _morrendo(delta: float) -> void:
	_t_morte += delta
	if _t_morte >= MORTE_QUEDA + MORTE_FICA:
		if fica:                                               # a pose final já está posta: para aqui e fica
			set_process(false)
			set_meta("pronta", true)
			return
		queue_free()
		return
	var k := minf(_t_morte / MORTE_QUEDA, 1.0)
	var g := k * k                                             # cai acelerando
	if _corpo != null:
		_corpo.position.y = -MORTE_DESCE * g
		_corpo.rotation.z = MORTE_TOMBA * g
	if not is_inside_tree():
		return
	for i in _femures.size():
		var q := marcha.quadril(i) + Vector3.DOWN * MORTE_DESCE * g
		var fora := marcha.casa(i) - marcha.quadril(i)
		fora.y = 0.0
		var ini := _pe_morte[i]
		var chao := Grade.altura_em(Vector2(ini.x, -ini.z))
		var pe := ini.lerp(Vector3(ini.x, chao, ini.z), k) + fora.normalized() * MORTE_ABRE * k
		var ik := MarchaAranha.resolver_ik(q, pe)
		_femures[i].global_transform = _segmento(q, ik.joelho)
		_tibias[i].global_transform = _segmento(ik.joelho, pe)


func _process(delta: float) -> void:
	if _morta:
		_morrendo(delta)
		return
	marcha.tick(delta, destino, rumo_desejado)
	if marcha.passo_pousou:
		marcha.passo_pousou = false
		if is_inside_tree():
			Som.tocar("aranha_passo", marcha.posicao, -12.0)
	if is_inside_tree():
		global_position = marcha.posicao
	else:
		position = marcha.posicao
	rotation.y = marcha.rumo
	if _corpo != null:
		_corpo.position.y = sin(Time.get_ticks_msec() * 0.012) * 0.02 * minf(marcha.velocidade.length(), 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in _femures.size():
		var q := marcha.quadril(i)
		var pe := marcha.pes[i]
		if atacando and i < 2:
			# golpe: o par da frente sobe e desce alternado na direção do alvo
			var frente := (marcha.base() * Vector3(0, 0, -1)).normalized()
			var lado := (marcha.base() * Vector3(MarchaAranha.QUADRIS[i].x, 0, 0)).normalized()
			var f := 0.5 + 0.5 * sin(t * 13.0 + i * PI)
			pe = Vector3(q.x, 0, q.z) + frente * (0.95 + 0.25 * f) + lado * 0.25 + Vector3.UP * (0.15 + 0.55 * (1.0 - f))
		var ik := MarchaAranha.resolver_ik(q, pe)
		if is_inside_tree():
			_femures[i].global_transform = _segmento(q, ik.joelho)
			_tibias[i].global_transform = _segmento(ik.joelho, pe)


## Transform de um segmento modelado ao longo de +X com origem na articulação.
static func _segmento(a: Vector3, b: Vector3) -> Transform3D:
	var x := (b - a).normalized()
	var z := x.cross(Vector3.UP)
	if z.length() < 1e-4:
		z = Vector3.BACK
	z = z.normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), a)
