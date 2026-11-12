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
const CORROI_S := 20.0             ## s de ácido forte (valor 1) até a árvore morrer de pé (desbotada, sem folha)
const DISSOLVE_S := 60.0           ## s até ela afundar no chão corroído e sumir (o tile fica limpo)
const ARVORE_MIN := 0.35           ## abaixo disso (beira da mancha) o ácido não chega às raízes

var colonia: Colonia
var versao := 0                    ## muda quando o desenho precisa refazer (toca nova, cresceu, sumindo)
var _vivas: Dictionary = {}        ## id da toca → {centro: Vector2, raio: float, larva: bool}
var _restos: Dictionary = {}       ## id → {centro, raio, t}: toca destruída, a infestação sumindo
var _ruido := FastNoiseLite.new()
var eventos: Array = []            ## {tipo: "arvores_mudaram", tiles} e {tipo: "arvore_dissolvida", tile, nome, tiles, silencioso}
var _corroendo: Dictionary = {}    ## tile da árvore → s de ácido acumulados
var _acc := 0.0
var _veg: Dictionary = {}           ## centro da cratera → {alc, lista}: vegetação comível em volta (_vegetacao_em_volta)


func _init(p_colonia: Colonia = null, semente := 11) -> void:
	colonia = p_colonia
	_ruido.seed = semente
	_ruido.frequency = 0.16


## Raio (tiles) da infestação de uma toca: cresce com a obra e com a idade.
static func raio_de(n: Dictionary) -> float:
	var k := clampf(float(n.get("idade", 0.0)) / MADURA_S, 0.0, 1.0)
	return lerpf(RAIO_INI, RAIO_MAX, 1.0 - pow(1.0 - k, 2.0)) * (0.35 + 0.65 * clampf(float(n.get("obra", 1.0)), 0.0, 1.0)) \
			+ float(n.get("raio_extra", 0.0))                # fase 8: a toca que ganha a disputa cobre o chão da outra


func tick(dt: float) -> void:
	if colonia == null:
		return
	for id in colonia.ninhos:
		var n: Dictionary = colonia.ninhos[id]
		var r := raio_de(n)
		var v: Dictionary = _vivas.get(id, {})
		if v.is_empty() or absf(float(v.raio) - r) > 0.05:
			var nova := v.is_empty()
			_vivas[id] = {"centro": n.centro, "raio": r, "larva": n.get("especie", "aranha") == "larva"}
			if nova and _vivas[id].larva and float(n.get("idade", 0.0)) >= MADURA_S:
				_consumir(DISSOLVE_S * 1.7, true, n.centro)   # cratera antiga do mapa: as árvores de perto já se foram
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
	_acc += dt
	if _acc >= 1.0:
		_consumir(_acc)
		_acc = 0.0


## O ácido das larvas consome a vegetação do chão corroído (arbusto e cogumelo afundam direto em CORROI_S): cada uma acumula o valor da corrosão por segundo; passou
## CORROI_S morre de pé (estado "corroida" no mapa); passou DISSOLVE_S afunda e o tile fica limpo. `silencioso`: sem
## animação (cratera que já nasce antiga no mapa); `so_centro`: só a mancha dessa cratera (as outras seguem no seu ritmo).
func _consumir(passo: float, silencioso := false, so_centro := Vector2.INF) -> void:
	if colonia == null or colonia.mapa == null or colonia.mapa.gerador == null:
		return
	var mapa: MapaOcupacao = colonia.mapa
	var fs := fontes()
	var mudaram: Array = []
	var vistos := {}
	for f in fs:
		if not bool(f[3]):
			continue
		var c: Vector2 = f[0]
		vistos[c] = true
		if so_centro != Vector2.INF and c != so_centro:
			continue
		var alcance := int(ceil(float(f[1]) * 1.3 + BORDA))
		var perto := _larvas_perto(c, alcance, fs)
		for veg: Array in _vegetacao_em_volta(c, alcance, mapa):
			var t: Vector2i = veg[0]
			if mapa.limpos.has(t):
				continue
			var arvore: bool = veg[2]
			var v := _valor(Vector2(t) + Vector2(0.5, 0.5), perto, true)
			if v < ARVORE_MIN:
				continue
			var e: String = mapa.arvores.get(t, {}).get("e", "")
			if e == "caida":
				continue
			var acc: float = float(_corroendo.get(t, 0.0)) + passo * v
			if acc >= (DISSOLVE_S if arvore else CORROI_S):   # arbusto, cogumelo: sem fase de pé, só afunda
				_corroendo.erase(t)
				mapa.arvores.erase(t)
				mapa.limpar_obstaculo(t)
				eventos.append({"tipo": "arvore_dissolvida", "tile": t, "nome": veg[1], "silencioso": silencioso,
						"tiles": Grade.tiles_da_area(t, veg[3], 0)})
				continue
			_corroendo[t] = acc
			if acc >= CORROI_S and e != "corroida":
				mapa.arvores[t] = {"e": "corroida"}
				mudaram.append(t)
	for c in _veg.keys():
		if not vistos.has(c):
			_veg.erase(c)                                    # cratera que sumiu: a lista dela também
	if not mudaram.is_empty():
		eventos.append({"tipo": "arvores_mudaram", "tiles": mudaram})


## Vegetação que o ácido pode comer em volta da cratera (âncora no tile, árvore ou mapa/vegetacao), na ordem da varredura
## (linha por linha). O obstáculo do gerador nunca muda (só some, e `limpos` é olhado a cada passo), então a lista é
## feita uma vez por cratera e alcance: antes o gerador era consultado em ~500 tiles por cratera a cada segundo
## (~130 ms de quadro com 19 crateras).
func _vegetacao_em_volta(c: Vector2, alcance: int, mapa: MapaOcupacao) -> Array:
	var cache: Dictionary = _veg.get(c, {})
	if not cache.is_empty() and int(cache.alc) == alcance:
		return cache.lista
	var lista := []
	for y in range(int(c.y) - alcance, int(c.y) + alcance + 1):
		for x in range(int(c.x) - alcance, int(c.x) + alcance + 1):
			var t := Vector2i(x, y)
			var o := mapa.gerador.distribuicao.obstaculo(t)
			if o.is_empty() or Vector2i(o.ancora) != t:
				continue
			var arvore := Distribuicao.eh_arvore(o.nome)
			if not arvore and Registro.modelos.get(o.nome, {}).get("categoria", "") != "mapa/vegetacao":
				continue                                 # pedra, cristal…: o ácido não come
			lista.append([t, o.nome, arvore, o.area])
	_veg[c] = {"alc": alcance, "lista": lista}
	return lista


## Só as crateras de larva que alcançam o quadrado varrido em volta de c (as outras não mudam o valor de nenhum tile dele).
func _larvas_perto(c: Vector2, alcance: int, fs: Array) -> Array:
	var out := []
	for f in fs:
		if bool(f[3]) and (f[0] as Vector2).distance_to(c) <= alcance * 1.5 + float(f[1]) * 1.4 + BORDA:
			out.append(f)
	return out


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


## Fontes que alcançam o chunk k (com a moldura de 1 tile da imagem): o resto do mapa não muda nenhum pixel dele.
func fontes_do_chunk(k: Vector2i, fs: Array = []) -> Array:
	if fs.is_empty():
		fs = fontes()
	var r0 := Vector2(k * T - Vector2i.ONE)
	var r1 := r0 + Vector2(T + 2, T + 2)
	var out := []
	for f in fs:
		var c: Vector2 = f[0]
		var a := float(f[1]) * 1.4 + BORDA
		if c.x + a < r0.x or c.x - a > r1.x or c.y + a < r0.y or c.y - a > r1.y:
			continue
		out.append(f)
	return out


## Assinatura do que o chunk k mostra: só muda quando uma fonte que alcança o chunk mudou de verdade (raio ou força em
## passos de 1%). O desenho refaz a imagem só então (antes refazia todos os chunks a cada segundo: ~0,8 s de quadro
## numa fábrica com muitas tocas).
func assinatura(k: Vector2i, fs: Array = []) -> String:
	var partes: PackedStringArray = []
	for f in fontes_do_chunk(k, fs):
		partes.append("%.1f,%.1f,%.2f,%.2f,%d" % [f[0].x, f[0].y, f[1], f[2], int(f[3])])
	return ";".join(partes)


## Imagem do chunk (T+2 de lado, a mesma moldura do mapa do ambiente): R = teia (aranhas), G = corrosão (larvas).
func imagem(k: Vector2i) -> Image:
	var img := Image.create(T + 2, T + 2, false, Image.FORMAT_RG8)
	var fs := fontes_do_chunk(k)
	if fs.is_empty():
		return img
	var base: Vector2i = k * T - Vector2i.ONE
	for j in T + 2:
		for i in T + 2:
			var p := Vector2(base + Vector2i(i, j)) + Vector2(0.5, 0.5)
			var v := _valor(p, fs, false)
			var g := _valor(p, fs, true)
			if v > 0.0 or g > 0.0:
				img.set_pixel(i, j, Color(v, g, 0))
	return img
