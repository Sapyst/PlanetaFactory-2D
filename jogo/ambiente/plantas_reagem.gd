class_name PlantasReagem
extends RefCounted
## Patch fauna, fase 2 (docs/PLANO_FAUNA.md), lógica pura: o que sobra no chão depois do tempo ruim.
##  galhos     quando uma tempestade (raios ou ventania) passa, galhos quebrados caem embaixo das árvores perto da
##             câmera — mais quanto mais forte foi; ficam uns dias de jogo e somem (afundam no capim).
##  cogumelos  com o chão molhado (fora do inverno) brotam touceiras pequenas no pé das árvores, em chão saudável;
##             crescem, ficam um dia e murcham.
## As folhas que caem no outono não estão aqui: são só desenho (DesenhoPlantasReagem), sem estado.
## O desenho 3D e o 2D leem `galhos` e `cogumelos` (posição na grade, giro, tamanho e idade).

var eco: Ecossistema
var galhos: Array = []          ## {pos: Vector2, ang, tam, nasc, vida}
var cogumelos: Array = []       ## {pos: Vector2, ang, tam, cor: int, nasc, vida}
var t := 0.0
var tormenta := 0.0             ## força da tempestade em curso (0 = não há)
var _t_cog := 0.0
var _rng := RandomNumberGenerator.new()
var _d: Dictionary


func _init(p_eco: Ecossistema, semente := 77) -> void:
	eco = p_eco
	_rng.seed = semente
	_d = Registro.fauna.get("plantas_reagem", {})


func _n(grupo: String, chave: String, padrao: float) -> float:
	return float(_d.get(grupo, {}).get(chave, padrao))


func tick(dt: float, clima: Clima, foco: Vector2) -> void:
	t += dt
	if clima == null:
		return
	var v: Dictionary = clima.valores
	var raios: bool = bool(Registro.clima.estados.get(clima.atual, {}).get("raios", false))
	var vento := float(v.get("vento", 0.0))
	if bool(_d.get("galhos", {}).get("liga", true)):
		if raios or vento > _n("galhos", "vento_min", 0.9):
			tormenta = maxf(tormenta, vento + (0.3 if raios else 0.0))
		elif tormenta > 0.0 and vento < _n("galhos", "vento_fim", 0.5):
			soltar_galhos(foco, tormenta)
			tormenta = 0.0
	_t_cog -= dt
	if _t_cog <= 0.0 and bool(_d.get("cogumelos", {}).get("liga", true)):
		_t_cog = _n("cogumelos", "intervalo_s", 4.0)
		if clima.molhado >= _n("cogumelos", "molhado_min", 0.45) and clima.estacao != 3:
			brotar(foco)
	var some_g := _n("galhos", "some_s", 60.0)
	galhos = galhos.filter(func(g): return t < float(g.nasc) + float(g.vida) + some_g)
	var some_c := _n("cogumelos", "murcha_s", 60.0)
	cogumelos = cogumelos.filter(func(c): return t < float(c.nasc) + float(c.vida) + some_c)


## Lugar bom no chão (terra, sem construção, sem água) perto de `p`; null se não achar.
func _chao_livre(p: Vector2) -> bool:
	var tl := Vector2i(p.floor())
	return eco.gerador.terreno(tl) == GeradorMundo.Terreno.TERRA and not eco.mapa.tiles.has(tl) \
			and eco.gerador.aplainado_em(tl) == null


func soltar_galhos(foco: Vector2, forca: float) -> int:
	var arvs := eco.arvores_perto(foco, _n("galhos", "raio", 30.0))
	if arvs.is_empty():
		return 0
	var n := int(lerpf(_n("galhos", "min", 6.0), _n("galhos", "max_por_vez", 26.0), clampf((forca - 0.6) / 0.7, 0.0, 1.0)))
	var poe := 0
	for i in n * 3:
		if poe >= n or galhos.size() >= int(_n("galhos", "max", 70.0)):
			break
		var a: Dictionary = arvs[_rng.randi() % arvs.size()]
		var p: Vector2 = a.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, float(a.copa) * 1.6 + 0.4)
		if not _chao_livre(p):
			continue
		galhos.append({"pos": p, "ang": _rng.randf() * TAU, "tam": _rng.randf_range(0.6, 1.25), "nasc": t,
				"vida": _n("galhos", "vida_s", 1080.0) * _rng.randf_range(0.8, 1.2)})
		poe += 1
	return poe


func brotar(foco: Vector2) -> int:
	if cogumelos.size() >= int(_n("cogumelos", "max", 50.0)):
		return 0
	var arvs := eco.arvores_perto(foco, _n("cogumelos", "raio", 25.0))
	if arvs.is_empty():
		return 0
	for tentativa in 6:
		var a: Dictionary = arvs[_rng.randi() % arvs.size()]
		var c: Vector2 = a.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.5, 1.4)
		if not _chao_livre(c) or eco.saude(Vector2i(c.floor())) < 0.4:
			continue
		var cor := _rng.randi() % 4
		var k := _rng.randi_range(2, 5)
		for j in k:
			cogumelos.append({"pos": c + Vector2(_rng.randf_range(-0.22, 0.22), _rng.randf_range(-0.22, 0.22)),
					"ang": _rng.randf() * TAU, "tam": _rng.randf_range(0.6, 1.3), "cor": cor, "nasc": t + j * 2.5,
					"vida": _n("cogumelos", "vida_s", 720.0) * _rng.randf_range(0.8, 1.2)})
		return k
	return 0


## 0..1: tamanho agora (cresce, fica, murcha/afunda).
func escala_cogumelo(c: Dictionary) -> float:
	var idade := t - float(c.nasc)
	if idade < 0.0:
		return 0.0
	var cresce := clampf(idade / _n("cogumelos", "cresce_s", 40.0), 0.0, 1.0)
	var murcha := clampf((idade - float(c.vida)) / _n("cogumelos", "murcha_s", 60.0), 0.0, 1.0)
	return cresce * (1.0 - murcha)


func some_galho(g: Dictionary) -> float:
	return clampf((t - float(g.nasc) - float(g.vida)) / _n("galhos", "some_s", 60.0), 0.0, 1.0)


func estado() -> Dictionary:
	return {"galhos": galhos, "cogumelos": cogumelos, "t": t, "tormenta": tormenta}


func restaurar(d: Dictionary) -> void:
	galhos = d.get("galhos", [])
	cogumelos = d.get("cogumelos", [])
	t = float(d.get("t", 0.0))
	tormenta = float(d.get("tormenta", 0.0))
