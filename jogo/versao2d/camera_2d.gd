class_name Camera2DJogo
extends CameraJogo
## Câmera da versão 2D: a MESMA projeção dos sprites (ortográfica, 35° acima do horizonte, olhando para o norte),
## para que o clique, o arrasto e a construção do jogo (que usam o raio da câmera 3D) acertem o tile desenhado em 2D.
## Zoom em degraus inteiros (pixel nítido); de longe, 0,5× e 0,25×. Não gira (os sprites têm 4 rotações fixas).

const ELEVACAO := deg_to_rad(35.0)
const PX := 4.6 / 160.0                         ## metros por pixel do sprite
const NIVEIS: Array[float] = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0]
var zoom_px := 2.0                              ## pixels de tela por pixel de sprite


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	near = 0.05
	far = 900.0
	angulo = 0.0
	_ajustar_zoom()
	posicionar()


func inclinacao() -> float:
	return ELEVACAO


func _ajustar_zoom() -> void:
	var z := 44.0 / maxf(distancia, 0.1)          # mais ou menos a mesma área que o 3D mostra nessa distância
	var melhor := NIVEIS[0]
	for n in NIVEIS:
		if absf(log(n / z)) < absf(log(melhor / z)):
			melhor = n
	zoom_px = melhor


func posicionar() -> void:
	angulo = 0.0
	_ajustar_zoom()                           # o jogo também muda a distância direto (roteiro, carregar)
	var dir := Vector3(0.0, sin(ELEVACAO), cos(ELEVACAO))
	position = alvo + dir * 200.0
	look_at(alvo)
	var h := maxf(get_viewport().get_visible_rect().size.y, 1.0) if is_inside_tree() else 720.0
	size = h * PX / zoom_px


func zoom(fator: float) -> void:
	distancia = clampf(distancia * fator, DIST_MIN, DIST_MAX)
	_ajustar_zoom()
	posicionar()


func arrastar(rel: Vector2) -> void:
	var mpp := size / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var r := rel * mpp
	r.y /= sin(ELEVACAO)
	destino += Vector3(-r.x, 0, -r.y)
	var agora := Time.get_ticks_msec()
	var dt := maxf((agora - _ultimo_arrasto) / 1000.0, 1.0 / 120.0)
	_vel = _vel.lerp(Vector3(-r.x, 0, -r.y) / dt, 0.5) if dt < 0.1 else Vector3.ZERO
	_ultimo_arrasto = agora


func girar(_d: float) -> void:
	pass                                         # 2D: vista fixa


## Mundo (Godot: x, y para cima, z para o sul) → pixel do sprite (x para a direita, y para baixo).
static func projetar(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z * sin(ELEVACAO) - p.y * cos(ELEVACAO)) / PX
