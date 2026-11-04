class_name Infestacao
extends RefCounted
## Infestação: teia e sujeira orgânica que brotam no chão em volta de cada toca e crescem com a idade dela — de colada
## na toca (RAIO_INI) até RAIO_MAX tiles em MADURA_S segundos de vida, com a borda irregular (ruído). Toca destruída:
## o chão volta devagar (SOME_S). Valor por tile de 0 a 1 (lógica pura, sem nós); o desenho é o terreno (3D) e o chão
## da versão 2D, pela imagem de cada chunk (`imagem`). É a base da propagação dos monstros: quem precisa saber se um
## tile está tomado lê `valor`. Duas espécies: a toca das aranhas deixa teia e terra escura (canal R da imagem); a
## cratera das larvas, chão corroído pelo ácido (canal G).

const RAIO_INI := 2.2              ## tiles em volta do centro da toca quando ela fica pronta
const RAIO_MAX := 6.5              ## tiles com a toca madura
const MADURA_S := 600.0            ## s de vida até o raio máximo (toca que já nasce pronta no mapa = madura)
const BORDA := 1.8                 ## tiles de degradê na borda
const SOME_S := 90.0               ## s para o chão voltar depois que a toca cai
const T := Grade.TAM_CHUNK

var colonia: Colonia
var versao := 0                    ## muda quando o desenho precisa refazer (toca nova, cresceu, sumindo)
var _vivas: Dictionary = {}        ## id da toca → {centro: Vector2, raio: float, larva: bool}
var _restos: Dictionary = {}       ## id → {centro, raio, t}: toca destruída, a infestação sumindo
var _ruido := FastNoiseLite.new()


func _init(p_colonia: Colonia = null, semente := 11) -> void:
	colonia = p_colonia
	_ruido.seed = semente
	_ruido.frequency = 0.16


## Raio (tiles) da infestação de uma toca: cresce com a obra e com a idade.
static func raio_de(n: Dictionary) -> float:
	var k := clampf(float(n.get("idade", 0.0)) / MADURA_S, 0.0, 1.0)
	return lerpf(RAIO_INI, RAIO_MAX, 1.0 - pow(1.0 - k, 2.0)) * (0.35 + 0.65 * clampf(float(n.get("obra", 1.0)), 0.0, 1.0))


func tick(dt: float) -> void:
	if colonia == null:
		return
	for id in colonia.ninhos:
		var n: Dictionary = colonia.ninhos[id]
		var r := raio_de(n)
		var v: Dictionary = _vivas.get(id, {})
		if v.is_empty() or absf(float(v.raio) - r) > 0.05:
			_vivas[id] = {"centro": n.centro, "raio": r, "larva": n.get("especie", "aranha") == "larva"}
			_restos.erase(id)
			versao += 1
	for id in _vivas.keys():
		if not colonia.ninhos.has(id):
			_restos[id] = {"centro": _vivas[id].centro, "raio": _vivas[id].raio, "larva": _vivas[id].larva, "t": 0.0}
			_vivas.erase(id)
			versao += 1
	for id in _restos.keys():
		_restos[id].t += dt
		if _restos[id].t >= SOME_S:
			_restos.erase(id)
		versao += 1


## (centro, raio, força, larva) de cada fonte: toca viva = força 1; resto sumindo = força caindo até 0.
func fontes() -> Array:
	var out := []
	for id in _vivas:
		out.append([_vivas[id].centro, float(_vivas[id].raio), 1.0, bool(_vivas[id].larva)])
	for id in _restos:
		out.append([_restos[id].centro, float(_restos[id].raio), 1.0 - float(_restos[id].t) / SOME_S, bool(_restos[id].larva)])
	return out


## Quanto o tile está tomado (0 a 1), qualquer espécie.
func valor(t: Vector2i) -> float:
	var p := Vector2(t) + Vector2(0.5, 0.5)
	var fs := fontes()
	return maxf(_valor(p, fs, false), _valor(p, fs, true))


## Só a corrosão das larvas.
func valor_larva(t: Vector2i) -> float:
	return _valor(Vector2(t) + Vector2(0.5, 0.5), fontes(), true)


func _valor(p: Vector2, fs: Array, larva := false) -> float:
	var v := 0.0
	for f in fs:
		if bool(f[3]) != larva:
			continue
		var d: float = p.distance_to(f[0])
		if d > float(f[1]) * 1.4 + BORDA:
			continue
		var r: float = float(f[1]) * (1.0 + 0.3 * _ruido.get_noise_2d(p.x, p.y))
		v = maxf(v, clampf((r - d) / BORDA, 0.0, 1.0) * float(f[2]))
	return v


## Chunks que a infestação toca agora.
func chunks() -> Dictionary:
	var out := {}
	for f in fontes():
		var c: Vector2 = f[0]
		var alcance := float(f[1]) * 1.4 + BORDA
		var a := Grade.chunk_de(Vector2i((c - Vector2(alcance, alcance)).floor()))
		var b := Grade.chunk_de(Vector2i((c + Vector2(alcance, alcance)).floor()))
		for cx in range(a.x, b.x + 1):
			for cy in range(a.y, b.y + 1):
				out[Vector2i(cx, cy)] = true
	return out


## Imagem do chunk (T+2 de lado, a mesma moldura do mapa do ambiente): R = teia (aranhas), G = corrosão (larvas).
func imagem(k: Vector2i) -> Image:
	var img := Image.create(T + 2, T + 2, false, Image.FORMAT_RG8)
	var fs := fontes()
	var base: Vector2i = k * T - Vector2i.ONE
	for j in T + 2:
		for i in T + 2:
			var p := Vector2(base + Vector2i(i, j)) + Vector2(0.5, 0.5)
			var v := _valor(p, fs, false)
			var g := _valor(p, fs, true)
			if v > 0.0 or g > 0.0:
				img.set_pixel(i, j, Color(v, g, 0))
	return img
