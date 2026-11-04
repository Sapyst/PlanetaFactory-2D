class_name Larva
extends Node3D
## Larva ácida visível: o modelo com esqueleto (larva_acida.glb). Segue a posição lógica da Colonia como a Aranha:
## anda (animação "andar" no ritmo da distância andada: a massa contrai e estica), vira para onde vai ou para o alvo,
## cospe (animação "cuspe") e, ao morrer, murcha e afunda. Mesma interface da Aranha para o DesenhoColonia.

const VEL_MAX := 1.2              ## m/s que o desenho acompanha (a lógica anda ~0,75)
const CICLO_M := 0.6              ## metros andados por ciclo da animação "andar" (uma onda de contração)

var destino := Vector3.ZERO
var rumo_desejado := 0.0
var atacando := false
var cuspindo := 0.0               ## s restantes da animação de cuspe
var _morta := false
var _anim: AnimationPlayer
var _modelo: Node3D
var _ultima := Vector3.ZERO


func _init(pos := Vector3.ZERO, p_rumo := 0.0) -> void:
	position = pos
	rotation.y = p_rumo
	destino = pos
	rumo_desejado = p_rumo


func _ready() -> void:
	_modelo = (load(Registro.modelos["larva_acida"].modelo) as PackedScene).instantiate()
	_modelo.rotation.y = PI / 2.0                     # o modelo olha para +X; o jogo, para −Z
	add_child(_modelo)
	Materiais.converter(_modelo)
	_anim = _modelo.find_children("*", "AnimationPlayer", true, false).front() if not _modelo.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if _anim != null and _anim.has_animation("andar"):
		_anim.get_animation("andar").loop_mode = Animation.LOOP_LINEAR
		_anim.play("andar")
	_ultima = position


func definir_furia(_f: float) -> void:
	pass


func ir_para(p: Vector3) -> void:
	destino = p
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.02:
		rumo_desejado = atan2(-d.x, -d.z)


func encarar(p: Vector3) -> void:
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.02:
		rumo_desejado = atan2(-d.x, -d.z)


## Começa a animação de cuspe (o DesenhoColonia chama no evento "cuspe").
func cuspir() -> void:
	cuspindo = 1.0
	if _anim != null and _anim.has_animation("cuspe"):
		_anim.play("cuspe")


func morrer() -> void:
	if _morta:
		return
	_morta = true
	set_process(false)
	if _anim != null:
		_anim.pause()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.15, 0.35, 1.1), 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.15, 0.9)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	var d := destino - position
	var passo := minf(d.length(), VEL_MAX * delta)
	if d.length() > 0.001:
		position += d.normalized() * passo
	rotation.y = rotate_toward(rotation.y, rumo_desejado, 4.0 * delta)
	if cuspindo > 0.0:
		cuspindo -= delta
		if cuspindo <= 0.0 and _anim != null and _anim.has_animation("andar"):
			_anim.play("andar")
		return
	if _anim != null and _anim.current_animation == "andar":
		var andou := Vector2(position.x - _ultima.x, position.z - _ultima.z).length()
		_anim.speed_scale = clampf(andou / maxf(delta, 1e-4) / CICLO_M, 0.0, 3.0)
	_ultima = position
