class_name GeradorMundo
extends RefCounted
## Mundo plano infinito, determinístico pela semente. Tudo é função do tile (sem estado):
## gerar o mesmo tile por qualquer chunk dá sempre o mesmo resultado — não existe costura entre chunks.
##
## Camadas (cada uma um FastNoiseLite):
##   continente  → terra × água (oceano/mar); o spawn é puxado para terra
##   temperatura, umidade (com distorção de domínio) → bioma pelo centro mais próximo em biomas.json
##   rio         → faixas onde |ruído| ≈ 0 (rede de rios que serpenteiam)
##   lago        → manchas baixas em terra (lago), e pequenas (lagoa)

enum Terreno { TERRA, PRAIA, RIO, LAGO, LAGOA, MAR, OCEANO }
const NOMES_TERRENO := ["terra", "praia", "rio", "lago", "lagoa", "mar", "oceano"]
const RAIO_SPAWN_TERRA := 90.0

var semente: int
var _continente := FastNoiseLite.new()
var _temperatura := FastNoiseLite.new()
var _umidade := FastNoiseLite.new()
var _distorcao := FastNoiseLite.new()
var _rio := FastNoiseLite.new()
var _lago := FastNoiseLite.new()
var _lagoa := FastNoiseLite.new()
var _relevo := FastNoiseLite.new()
var relevo_ativo := true
var hidro: Hidrologia
var _aplainado := {}                 ## tile → nível imposto pela Terraplenagem (sobrepõe o relevo)
var versao_nivel := 0               ## muda quando o nível de um tile muda (aplainar, inundar): quem guarda alturas refaz
var _superficie := {}                ## tile escavado e cheio d'água → nível da superfície (AguaJogo)
const NIVEL_MAR := -2                ## superfície do mar (em níveis de relevo)            ## falso = mundo todo plano (testes de desempenho com fábricas enormes)
var _niveis := {}                 ## chunk → PackedByteArray (nível + 8)
var _trava := Mutex.new()
var _biomas: Dictionary
var _nomes_biomas: Array[String] = []
var distribuicao: Distribuicao
var registro: Node   ## autoload Registro (buscado em tempo de execução: funciona também em scripts -s)


func _init(p_semente := 1337, biomas: Dictionary = {}) -> void:
	semente = p_semente
	registro = (Engine.get_main_loop() as SceneTree).root.get_node("Registro")
	_biomas = biomas if not biomas.is_empty() else registro.biomas
	for n in _biomas:
		_nomes_biomas.append(n)
	_config(_continente, 1, 0.0028, 5)
	_config(_temperatura, 2, 0.0035, 3)
	_config(_umidade, 3, 0.0040, 3)
	_config(_distorcao, 4, 0.02, 2)
	_config(_rio, 5, 0.0045, 2)
	_config(_lago, 6, 0.018, 2)
	_config(_lagoa, 7, 0.03, 2)
	_config(_relevo, 8, 0.0085, 3)
	distribuicao = Distribuicao.new(self)
	hidro = Hidrologia.new(self)


func _config(n: FastNoiseLite, salt: int, freq: float, oitavas: int) -> void:
	n.seed = semente * 7919 + salt
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oitavas


## Elevação "continental" −1..1 com o spawn garantido em terra.
func elevacao(tile: Vector2i) -> float:
	return elevacao_em(Vector2(tile))


func elevacao_em(p: Vector2) -> float:
	var e := _continente.get_noise_2d(p.x, p.y)
	var d2 := p.length_squared()
	# dois sinos somados: um forte e estreito (spawn sempre em terra) e um largo (continente em volta)
	return e + 0.9 * exp(-d2 / (2.0 * 60.0 * 60.0)) + 0.3 * exp(-d2 / (2.0 * RAIO_SPAWN_TERRA * RAIO_SPAWN_TERRA * 2.8))


## Mar e oceano pela elevação continental; baixada da costa abaixo do nível do mar é invadida pelo mar; rios e
## lagos vêm da hidrologia (nascente → relevo → mar ou depressão; ver Hidrologia).
func _terreno_bruto(tile: Vector2i) -> int:
	var e := elevacao(tile)
	if e < -0.32: return Terreno.OCEANO
	if e < -0.18: return Terreno.MAR
	if e < 0.0 and relevo_ativo and nivel_bruto(tile) <= NIVEL_MAR: return Terreno.MAR
	if e < -0.14: return Terreno.PRAIA
	if relevo_ativo:
		var a := hidro.agua_em(tile)
		if not a.is_empty():
			return a.tipo
	return Terreno.TERRA


## Direção da correnteza num tile de rio (rio abaixo); zero fora de rio.
func direcao_rio(tile: Vector2i) -> Vector2:
	if not relevo_ativo:
		return Vector2.ZERO
	return hidro.agua_em(tile).get("fluxo", Vector2.ZERO)


func eh_agua(t: int) -> bool:
	return t in [Terreno.RIO, Terreno.LAGO, Terreno.LAGOA, Terreno.MAR, Terreno.OCEANO]


# ------------------------------------------------------------------ relevo
## Nível do terreno (−3..3; 1 nível = Grade.ALT_NIVEL m).
## Cache por chunk: 1 byte por tile = nível + 8 (bits 0–3) | encosta (bit 4) | terreno (bits 5–7). Ruído de relevo + a elevação continental, quantizado em
## terraços; plano em volta do início (some suave entre 42 e 95 tiles). Guardado por chunk (seguro entre threads).
func nivel(tile: Vector2i) -> int:
	if not _superficie.is_empty():
		_trava.lock()
		var s: Variant = _superficie.get(tile)
		_trava.unlock()
		if s != null:
			return s                                    # buraco cheio d'água: constrói em cima, na superfície
	if not _aplainado.is_empty():
		_trava.lock()
		var a: Variant = _aplainado.get(tile)
		_trava.unlock()
		if a != null:
			return a
	return (_info(tile) & 15) - 8


## Água de jogo (AguaJogo): o tile escavado encheu até o nível `s` da água vizinha (null = secou).
func inundar(tile: Vector2i, s: Variant) -> void:
	versao_nivel += 1
	_trava.lock()
	if s == null:
		_superficie.erase(tile)
	else:
		_superficie[tile] = int(s)
	_trava.unlock()


func superficie_em(tile: Vector2i) -> Variant:
	if _superficie.is_empty():
		return null
	_trava.lock()
	var s: Variant = _superficie.get(tile)
	_trava.unlock()
	return s


## Terraplenagem: impõe um nível ao tile (−1 = volta ao relevo natural).
func aplainar(tile: Vector2i, nv: Variant) -> void:
	versao_nivel += 1
	_trava.lock()
	if nv == null:
		_aplainado.erase(tile)
	else:
		_aplainado[tile] = int(nv)
	_trava.unlock()


func aplainado_em(tile: Vector2i) -> Variant:
	_trava.lock()
	var a: Variant = _aplainado.get(tile)
	_trava.unlock()
	return a


func aplainados() -> Dictionary:
	_trava.lock()
	var c := _aplainado.duplicate()
	_trava.unlock()
	return c


func terreno(tile: Vector2i) -> int:
	return _info(tile) >> 5


## Tile no meio de uma encosta (o chão desenhado ali não bate com o nível do tile): não aceita construção.
func em_encosta(tile: Vector2i) -> bool:
	return (_info(tile) & 16) != 0 and aplainado_em(tile) == null


func _info(tile: Vector2i) -> int:
	var k := Grade.chunk_de(tile)
	_trava.lock()
	var arr: PackedByteArray = _niveis.get(k, PackedByteArray())
	_trava.unlock()
	if arr.is_empty():
		arr = PackedByteArray()
		arr.resize(Grade.TAM_CHUNK * Grade.TAM_CHUNK)
		var base := k * Grade.TAM_CHUNK
		for j in Grade.TAM_CHUNK:
			for i in Grade.TAM_CHUNK:
				var t := base + Vector2i(i, j)
				var ter := _terreno_bruto(t)
				var nv := _nivel_final(t, ter)
				var enc := relevo_ativo and not eh_agua(ter) and (absf(patamar(relevo_em(Vector2(t))) - float(nv)) > 0.12 or elevacao(t) < -0.10)
				# (praia desce em rampa até o mar: não é chão plano)
				arr[j * Grade.TAM_CHUNK + i] = (nv + 8) | (16 if enc else 0) | (ter << 5)
		_trava.lock()
		if _niveis.size() > 6000:
			_niveis.clear()
		_niveis[k] = arr
		_trava.unlock()
	var l := Grade.local_de(tile)
	return arr[l.y * Grade.TAM_CHUNK + l.x]


## Nível com a água: mar no nível do mar, rio/lago no nível do leito; terra = relevo.
func _nivel_final(tile: Vector2i, t: int) -> int:
	if not relevo_ativo:
		return 0
	if t == Terreno.MAR or t == Terreno.OCEANO:
		return NIVEL_MAR
	var a := hidro.agua_em(tile)
	if not a.is_empty():
		return int(a.nivel)
	return nivel_bruto(tile)


func nivel_bruto(tile: Vector2i) -> int:
	return clampi(roundi(relevo_em(Vector2(tile))), -3, 3)


## Relevo contínuo (em níveis, sem arredondar) num ponto qualquer: o nível do tile é este valor arredondado no
## canto do tile; o desenho do chão usa o valor em cada ponto — a encosta segue a curva do ruído, não a grade.
func relevo_em(p: Vector2) -> float:
	return campos_em(p).x


## (relevo contínuo, elevação continental) no ponto, calculando a elevação uma vez só (desenho do chão).
func campos_em(p: Vector2) -> Vector2:
	var e := elevacao_em(p)
	if not relevo_ativo:
		return Vector2(0.0, e)
	var r := _relevo.get_noise_2d(p.x, p.y) * 1.5 + (e - 0.25) * 0.9
	return Vector2(clampf(r * smoothstep(42.0, 95.0, p.length()) * 2.4, -3.49, 3.49), e)


## Ondulação natural do chão (metros, ±~0,25): o mundo nunca é plano perfeito; não muda o nível dos tiles.
## Onde se constrói, o desenho aplaina (mapa da fábrica no shader). `q` em coordenadas de relevo.
func micro_em(q: Vector2) -> float:
	if not relevo_ativo or q.length() < 30.0:
		return 0.0 if not relevo_ativo else (_distorcao.get_noise_2d(q.x * 4.0, q.y * 4.0) * 0.12)
	return _distorcao.get_noise_2d(q.x * 4.0, q.y * 4.0) * 0.20 + _lagoa.get_noise_2d(q.x * 7.0 + 31.0, q.y * 7.0 - 5.0) * 0.08


## Altura desenhada (em níveis) a partir do relevo contínuo: patamar plano e encosta curta onde cruza um meio nível.
static func patamar(x: float) -> float:
	var k := floorf(x)
	return k + smoothstep(0.41, 0.59, x - k)


## (temperatura, umidade) em 0..1, com distorção para bordas de bioma orgânicas.
func clima(tile: Vector2i) -> Vector2:
	# deslocamento em x e y independentes (com o mesmo valor nos dois eixos a borda saía em retas a 45°)
	var wx := _distorcao.get_noise_2d(tile.x, tile.y) * 18.0
	var wy := _distorcao.get_noise_2d(tile.x + 913.0, tile.y - 577.0) * 18.0
	var t := _temperatura.get_noise_2d(tile.x + wx, tile.y + wy) * 0.5 + 0.5
	var u := _umidade.get_noise_2d(tile.x - wy, tile.y + wx) * 0.5 + 0.5
	return Vector2(clampf(t * 1.25 - 0.12, 0, 1), clampf(u * 1.25 - 0.12, 0, 1))


func bioma(tile: Vector2i) -> String:
	var c := clima(tile)
	var melhor := ""
	var dist := INF
	for n in _nomes_biomas:
		var cc: Array = _biomas[n].centro
		var d := c.distance_squared_to(Vector2(cc[0], cc[1]))
		if d < dist:
			dist = d
			melhor = n
	return melhor


func indice_bioma(nome: String) -> int:
	return _nomes_biomas.find(nome)


func nomes_biomas() -> Array[String]:
	return _nomes_biomas


func dados_bioma(nome: String) -> Dictionary:
	return _biomas.get(nome, {})


## Tudo de um chunk de uma vez (para desenhar e para o mapa de ocupação).
func gerar_chunk(chunk: Vector2i) -> ChunkDados:
	var c := ChunkDados.new()
	c.coord = chunk
	var n := Grade.TAM_CHUNK
	c.terreno.resize(n * n)
	c.bioma.resize(n * n)
	var base := chunk * n
	var cx := Distribuicao.contexto()          # cada tile é calculado uma vez só neste chunk
	for j in n:
		for i in n:
			var t := base + Vector2i(i, j)
			var k := j * n + i
			c.terreno[k] = distribuicao._ter(t, cx)
			c.bioma[k] = indice_bioma(distribuicao._bio(t, cx))
			var jaz := distribuicao.jazida(t, cx)
			if not jaz.is_empty():
				c.jazidas[t] = jaz
			var ob := distribuicao.obstaculo(t, cx)
			if not ob.is_empty() and ob.ancora == t:
				c.obstaculos[t] = ob
			var dc := distribuicao.deco(t, cx, ob)
			if not dc.is_empty():
				c.decos.append(dc)
	return c
