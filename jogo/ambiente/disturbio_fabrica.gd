class_name DisturbioFabrica
extends RefCounted
## Patch fauna, fase 7 (docs/PLANO_FAUNA.md), lógica pura: o quanto a fábrica perturba a natureza num ponto (0..1).
##  barulho  cada máquina trabalhando agora faz barulho até um raio que cresce com o tamanho dela (cai até zero na
##           borda); máquinas juntas somam sem passar de 1. Grade de `cel` m refeita a cada `passo_s`, só perto da
##           câmera.
##  fumaça   a poluição do ar (Poluicao, por chunk, interpolada entre os centros) em escala log: `poluicao_ref` pontos
##           = o máximo; pesa `poluicao_peso`. É ela que deixa o capim cinza (`fuligem`).
## O Ecossistema pergunta `em(p)` (fonte_disturbio) e `fuligem(p)`; a fauna se afasta, a vida pequena se cala.

var mapa: MapaOcupacao
var fabrica: Fabrica
var poluicao: Poluicao
var grade: Dictionary = {}            ## célula → barulho 0..1
var _t := 0.0
var _d: Dictionary


func _init(p_mapa: MapaOcupacao, p_fabrica: Fabrica, p_poluicao: Poluicao) -> void:
	mapa = p_mapa
	fabrica = p_fabrica
	poluicao = p_poluicao
	_d = Registro.fauna.get("disturbio", {})


func _n(k: String, padrao: float) -> float:
	return float(_d.get(k, padrao))


func tick(dt: float, foco: Vector2) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = _n("passo_s", 1.0)
	atualizar(foco)


## Raio do barulho de uma máquina (m): base + por tile do lado maior, × o fator do tipo (prefixo do nome).
func raio_de(nome: String, area: Vector2i) -> float:
	var b: Dictionary = _d.get("barulho", {})
	var r := float(b.get("base", 5.0)) + float(b.get("por_tile", 1.8)) * maxi(area.x, area.y)
	var pre: Dictionary = b.get("tipos", {})
	for p in pre:
		if nome.begins_with(String(p)):
			r *= float(pre[p])
			break
	return minf(r, float(b.get("max", 16.0)))


func atualizar(foco: Vector2) -> void:
	grade.clear()
	if not bool(_d.get("liga", true)) or fabrica == null:
		return
	var cel := _n("cel", 4.0)
	var alcance := _n("raio", 70.0)
	var forca := float(_d.get("barulho", {}).get("forca", 0.9))
	var ids: Array = fabrica.maquinas.keys()
	ids.append_array(fabrica.linha2.keys())
	var vistos := {}
	for id in ids:
		if vistos.has(id) or not mapa.estruturas.has(id) or not fabrica.trabalhando(id):
			continue
		vistos[id] = true
		var e: Dictionary = mapa.estruturas[id]
		var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
		var r := raio_de(String(e.nome), e.area)
		if c.distance_to(foco) > alcance + r or r <= 0.0:
			continue
		var k0 := Vector2i(floori((c.x - r) / cel), floori((c.y - r) / cel))
		var k1 := Vector2i(floori((c.x + r) / cel), floori((c.y + r) / cel))
		for y in range(k0.y, k1.y + 1):
			for x in range(k0.x, k1.x + 1):
				var q := (Vector2(x, y) + Vector2(0.5, 0.5)) * cel
				var v := (1.0 - q.distance_to(c) / r) * forca
				if v <= 0.0:
					continue
				var k := Vector2i(x, y)
				grade[k] = 1.0 - (1.0 - float(grade.get(k, 0.0))) * (1.0 - v)


func barulho(p: Vector2) -> float:
	var cel := _n("cel", 4.0)
	return float(grade.get(Vector2i(floori(p.x / cel), floori(p.y / cel)), 0.0))


## Fumaça no ar em `p` (0..1): a poluição do chunk, interpolada entre os centros (sem degrau na borda), em escala log.
func fuligem(p: Vector2) -> float:
	if poluicao == null or poluicao.valores.is_empty():
		return 0.0
	var tc := float(Grade.TAM_CHUNK)
	var q := p / tc - Vector2(0.5, 0.5)
	var b := Vector2i(floori(q.x), floori(q.y))
	var f := q - Vector2(b)
	var v00 := poluicao.em_chunk(b)
	var v10 := poluicao.em_chunk(b + Vector2i(1, 0))
	var v01 := poluicao.em_chunk(b + Vector2i(0, 1))
	var v11 := poluicao.em_chunk(b + Vector2i(1, 1))
	var v := lerpf(lerpf(v00, v10, f.x), lerpf(v01, v11, f.x), f.y)
	return clampf(log(1.0 + v) / log(1.0 + _n("poluicao_ref", 150.0)), 0.0, 1.0)


func em(p: Vector2) -> float:
	var pd := fuligem(p) * _n("poluicao_peso", 0.6)
	return clampf(1.0 - (1.0 - barulho(p)) * (1.0 - pd), 0.0, 1.0)
