class_name Ecossistema
extends RefCounted
## Patch fauna, fase 0 (docs/PLANO_FAUNA.md): a fundação que todo bicho usa, lógica pura (sem desenho).
##
##  índice    quem tem bichos se apresenta com uma fonte (`registrar_fonte(tipo, func() -> Array)`): pássaros,
##            aranhas e larvas, tocas. A cada `indice_s` o índice espacial (células de `cel` m) é refeito a partir
##            das fontes — ninguém mexe por dentro do outro; quem precisa saber o que tem perto pergunta `perto()`.
##  eventos   `morreu`, `comeu`, `fugiu`: quem produz chama `avisar()`; no tick viram `eventos` (valem um passo).
##            As fases seguintes (carcaças, moscas, ratos) leem daqui.
##  comida    fontes de comida no chão (fruta, semente, carcaça — fases 3 e 4); vai no save.
##  saúde     quanto o chão está vivo (mato, árvore, sem cinza, ácido, teia, fábrica): decide onde a vida pequena,
##            os pássaros e, depois, os ratos ficam. Era dos Passaros; agora é de todos.
##  orçamento `detalhe(p)`: 2 = perto da câmera (lógica e desenho completos), 1 = meio, 0 = longe (só contagem).

var gerador: GeradorMundo
var mapa: MapaOcupacao
var ambiente: AmbienteVivo
var infestacao: Infestacao
var foco := Vector2.ZERO
var fontes: Dictionary = {}              ## tipo → Callable() -> Array[{id, pos: Vector2, especie?, n?}]
var contagem: Dictionary = {}            ## tipo → quantos no último índice
var comida: Dictionary = {}              ## id → {id, tipo, pos, valor, idade}
var eventos: Array[Dictionary] = []      ## os avisos do último tick
var _novos: Array[Dictionary] = []
var _indice: Dictionary = {}             ## célula (Vector2i) → Array[{tipo, id, pos, especie, n}]
var _t := 0.0
var _prox_comida := 1
var _d: Dictionary


func _init(p_gerador: GeradorMundo, p_mapa: MapaOcupacao, p_ambiente: AmbienteVivo = null, p_infestacao: Infestacao = null) -> void:
	gerador = p_gerador
	mapa = p_mapa
	ambiente = p_ambiente
	infestacao = p_infestacao
	_d = Registro.fauna.get("ecossistema", {})


func _n(chave: String, padrao: float) -> float:
	return float(_d.get(chave, padrao))


# ------------------------------------------------------------------ índice
func registrar_fonte(tipo: String, f: Callable) -> void:
	fontes[tipo] = f
	_t = 0.0                                             # refaz no próximo tick


func tick(dt: float, p_foco: Vector2) -> void:
	foco = p_foco
	eventos = _novos
	_novos = []
	_t -= dt
	if _t <= 0.0:
		_t = _n("indice_s", 0.5)
		reindexar()


func reindexar() -> void:
	_indice.clear()
	contagem.clear()
	var cel := _n("cel", 8.0)
	for tipo in fontes:
		var f: Callable = fontes[tipo]
		if not f.is_valid():
			continue
		var lista: Array = f.call()
		contagem[tipo] = lista.size()
		for s in lista:
			var p: Vector2 = s.pos
			var k := Vector2i(floori(p.x / cel), floori(p.y / cel))
			if not _indice.has(k):
				_indice[k] = []
			_indice[k].append({"tipo": tipo, "id": s.get("id", -1), "pos": p, "especie": String(s.get("especie", "")),
					"n": int(s.get("n", 1))})


## Quem está a até `raio` de `c` (do último índice), de um tipo ou de todos ("").
func perto(c: Vector2, raio: float, tipo := "") -> Array:
	var cel := _n("cel", 8.0)
	var out: Array = []
	var k0 := Vector2i(floori((c.x - raio) / cel), floori((c.y - raio) / cel))
	var k1 := Vector2i(floori((c.x + raio) / cel), floori((c.y + raio) / cel))
	for y in range(k0.y, k1.y + 1):
		for x in range(k0.x, k1.x + 1):
			for s in _indice.get(Vector2i(x, y), []):
				if (tipo == "" or s.tipo == tipo) and (s.pos as Vector2).distance_to(c) <= raio:
					out.append(s)
	return out


## Distância até o mais perto de um tipo (INF se nenhum no raio).
func distancia(c: Vector2, tipo: String, raio: float) -> float:
	var m := INF
	for s in perto(c, raio, tipo):
		m = minf(m, (s.pos as Vector2).distance_to(c))
	return m


## Orçamento: 2 perto da câmera, 1 no meio, 0 longe.
func detalhe(p: Vector2) -> int:
	var d := p.distance_to(foco)
	if d <= _n("raio_perto", 40.0):
		return 2
	return 1 if d <= _n("raio_medio", 80.0) else 0


# ------------------------------------------------------------------ eventos
func avisar(ev: Dictionary) -> void:
	_novos.append(ev)


func morreu(tipo: String, especie: String, pos: Vector2, extra := {}) -> void:
	var ev := {"tipo": "morreu", "quem": tipo, "especie": especie, "pos": pos}
	ev.merge(extra)
	avisar(ev)


# ------------------------------------------------------------------ comida (fases 3 e 4)
func por_comida(tipo: String, pos: Vector2, valor := 1.0) -> int:
	var id := _prox_comida
	_prox_comida += 1
	comida[id] = {"id": id, "tipo": tipo, "pos": pos, "valor": valor, "idade": 0.0}
	return id


func comida_perto(c: Vector2, raio: float, tipo := "") -> Array:
	var out: Array = []
	for f in comida.values():
		if (tipo == "" or f.tipo == tipo) and (f.pos as Vector2).distance_to(c) <= raio:
			out.append(f)
	return out


func comer(id: int, quem: String) -> bool:
	if not comida.has(id):
		return false
	var f: Dictionary = comida[id]
	comida.erase(id)
	avisar({"tipo": "comeu", "quem": quem, "comida": f.tipo, "pos": f.pos})
	return true


# ------------------------------------------------------------------ saúde do chão
## Saúde do lugar (0..1): mato e árvore (de pé, de muda crescida) contam; cinza, sujeira, ácido, teia, construção e
## água tiram. Média de 9 pontos em volta (2 m de passo).
func saude(t: Vector2i) -> float:
	var soma := 0.0
	for j in range(-2, 3, 2):
		for i in range(-2, 3, 2):
			soma += saude_tile(t + Vector2i(i, j))
	return soma / 9.0


func saude_tile(t: Vector2i) -> float:
	if mapa.tiles.has(t) or gerador.aplainado_em(t) != null:
		return 0.0
	if gerador.terreno(t) != GeradorMundo.Terreno.TERRA:
		return 0.15
	var v := 0.4
	if not mapa.limpos.has(t):
		var o := gerador.distribuicao.obstaculo(t)
		if not o.is_empty() and Registro.modelos.get(o.nome, {}).get("categoria", "") == "mapa/vegetacao":
			v = 1.0 if mapa.arvores.get(Vector2i(o.ancora), {}).is_empty() else 0.2
	if ambiente != null:
		if float(ambiente.plantas.get(t, 0.0)) > 0.3:
			v = 1.0
		v *= (1.0 - ambiente.valor(t, AmbienteVivo.QUEIM)) * (1.0 - 0.7 * ambiente.valor(t, AmbienteVivo.SUJ))
		if ambiente.fogo.has(t):
			return 0.0
	if infestacao != null:
		v *= 1.0 - infestacao.valor(t)
	return clampf(v, 0.0, 1.0)


## Chão morto onde a semente pega: dá para plantar, está queimado ou sem vida em volta, e o ácido/teia já não está ali.
func morto(t: Vector2i) -> bool:
	if ambiente == null or not ambiente.pode_plantar(t):
		return false
	if infestacao != null and infestacao.valor(t) > 0.15:
		return false
	return ambiente.valor(t, AmbienteVivo.QUEIM) > 0.15 or saude(t) < 0.3


func perto_de_construcao(t: Vector2i, r: int) -> bool:
	for j in range(-r, r + 1, 2):
		for i in range(-r, r + 1, 2):
			if mapa.tiles.has(t + Vector2i(i, j)):
				return true
	return false


## Água a até `r` tiles (passo 1): margem de rio, lago ou lagoa.
func perto_da_agua(t: Vector2i, r: int) -> bool:
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			if gerador.eh_agua(gerador.terreno(t + Vector2i(i, j))):
				return true
	return false


# ------------------------------------------------------------------ salvamento
func estado() -> Dictionary:
	return {"comida": comida, "prox": _prox_comida}


func restaurar(d: Dictionary) -> void:
	comida.clear()
	var c: Dictionary = d.get("comida", {})
	for k in c:
		comida[int(k)] = c[k]
	_prox_comida = int(d.get("prox", 1))
