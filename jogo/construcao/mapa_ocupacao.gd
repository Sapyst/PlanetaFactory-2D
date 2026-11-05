class_name MapaOcupacao
extends RefCounted
## Quem ocupa cada tile e cada canto da grade. Regras de construção:
##  - área inteira em terra construível, sem outra estrutura e sem obstáculo natural (precisa limpar antes);
##  - extratores/brocas/bombas exigem jazida compatível em pelo menos um tile da área;
##  - cantos: pilares de esteira elevada só em canto que nenhuma estrutura "ocupa_canto" reivindica,
##    e estrutura "ocupa_canto" (muro, trilho, obstáculo) não pode cobrir canto que já tem pilar.
##  - esteira elevada (nível n = n × 0,5 m) mora em `altos`, não ocupa o chão: passa por cima de estrutura mais
##    baixa que o nível − FOLGA; e nada mais alto que isso pode ser construído debaixo dela depois.

var gerador: GeradorMundo
var registro: Node
var tiles: Dictionary = {}          ## Vector2i → id
var cantos: Dictionary = {}         ## Vector2i (vértice) → id (estrutura que ocupa canto ou pilar)
var estruturas: Dictionary = {}     ## id → {nome, minimo, rot, area}
var limpos: Dictionary = {}         ## tiles cujo obstáculo natural já foi removido
var arvores: Dictionary = {}        ## tile → {e: "queimada"}, {e: "caida", dir: Vector2} (fogo) ou {e: "corroida"} (ácido das larvas); some ao limpar
var altos: Dictionary = {}          ## Vector3i(x, y, nível 1..2) → id (esteira elevada / rampa de cima)
var reservas: Dictionary = {}       ## tile → id da obra encomendada (patch RTS: ainda não construída, ninguém põe em cima)
var reservas_altas: Dictionary = {} ## Vector3i(x, y, nível) → id da obra elevada encomendada
const NIVEIS := 2                   ## até 1,0 m
const FOLGA := 0.25
var _prox_id := 1
const AGUA_RASA := [GeradorMundo.Terreno.RIO, GeradorMundo.Terreno.LAGO, GeradorMundo.Terreno.LAGOA]   ## dá para construir em cima (plataforma)
var versao := 0                     ## muda a cada colocar/remover (quem guarda listas sabe quando refazer)


func _init(p_gerador: GeradorMundo) -> void:
	gerador = p_gerador
	registro = gerador.registro


## "" se pode; senão o motivo.
func motivo_bloqueio(nome: String, minimo: Vector2i, rot: int) -> String:
	var def: Dictionary = registro.estruturas.get(nome, registro.modelos.get(nome, {}))
	if def.is_empty():
		return "estrutura desconhecida"
	var area: Vector2i = registro.area(nome)
	var precisa: Array = def.get("requer_jazida", [])
	var achou_jazida := precisa.is_empty()
	var nivel0 := gerador.nivel(minimo)
	for t in Grade.tiles_da_area(minimo, area, rot):
		if gerador.nivel(t) != nivel0:
			return "desnivel"                          # (encosta pode: a construção aplaina o chão)
		if tiles.has(t) or reservas.has(t):
			return "ocupado"
		var ter := gerador.terreno(t)
		if gerador.eh_agua(ter) and (Colonia.eh_toca(nome) or not ter in AGUA_RASA):
			return "agua"                              # mar/oceano: fundo demais para pilar
		if not limpos.has(t) and not gerador.distribuicao.obstaculo(t).is_empty():
			return "obstaculo"
		if not achou_jazida:
			var j := gerador.distribuicao.jazida(t)
			if not j.is_empty() and precisa.has(j.tipo):
				achou_jazida = true
	if not achou_jazida:
		return "sem_jazida"
	if def.get("perto_agua", false) and not encosta_na_agua(minimo, area, rot):
		return "longe_da_agua"
	if def.get("tomada_agua", false) and tiles_da_tomada(minimo, area, rot).filter(_tem_agua).is_empty():
		return "tomada_seca"
	if def.get("no_rio", false) and not no_rio(minimo, area, rot):
		return "fora_do_rio"
	var alt := _altura(nome)
	for t in Grade.tiles_da_area(minimo, area, rot):
		for n in range(1, NIVEIS + 1):
			if altos.has(Vector3i(t.x, t.y, n)) and alt > n * 0.5 - FOLGA:
				return "esteira_em_cima"
	if def.get("ocupa_canto", false):
		for c in Grade.cantos_da_area(minimo, area, rot):
			if cantos.has(c) and estruturas[cantos[c]].nome.begins_with("pilar"):
				return "pilar_no_canto"
	return ""


## A área (ou a volta dela, 1 tile) toca água — rio, lago ou buraco cheio?
func encosta_na_agua(minimo: Vector2i, area: Vector2i, rot: int) -> bool:
	for t in Grade.tiles_da_area(minimo, area, rot):
		for y in range(-1, 2):
			for x in range(-1, 2):
				var n := t + Vector2i(x, y)
				if gerador.eh_agua(gerador.terreno(n)) or gerador.superficie_em(n) != null:
					return true
	return false


## Turbina de correnteza: pelo menos metade da área em tile de rio (água corrente; lago e canal não correm).
func no_rio(minimo: Vector2i, area: Vector2i, rot: int) -> bool:
	var tiles := Grade.tiles_da_area(minimo, area, rot)
	return tiles.filter(func(t): return gerador.terreno(t) == GeradorMundo.Terreno.RIO).size() * 2 >= tiles.size()


## Bomba d'água: os tiles logo além do lado SUL do modelo (girado com a peça) — onde fica a tomada com a grade.
static func tiles_da_tomada(minimo: Vector2i, area: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in area.x:
		var p := {"nome": "", "tipo": "", "io": "", "pos": [-area.x * 0.5 + 0.5 + i, -area.y * 0.5, 0.0], "dir": [0, -1, 0]}
		out.append(Grade.porta_no_mundo(p, minimo, area, rot).tile_fora)
	return out


func _tem_agua(t: Vector2i) -> bool:
	return gerador.eh_agua(gerador.terreno(t)) or gerador.superficie_em(t) != null


## Algum tile da área é água (rio, lago ou buraco cheio)? Então a construção vai sobre plataforma com pilares.
func sobre_agua(minimo: Vector2i, area: Vector2i, rot: int) -> bool:
	for t in Grade.tiles_da_area(minimo, area, rot):
		if gerador.eh_agua(gerador.terreno(t)) or gerador.superficie_em(t) != null:
			return true
	return false


## Esteira/rampa no nível n ≥ 1 (só peças 1×1 de esteira): livre naquele nível, estrutura de baixo mais baixa.
func motivo_alto(t: Vector2i, n: int) -> String:
	if altos.has(Vector3i(t.x, t.y, n)) or reservas_altas.has(Vector3i(t.x, t.y, n)):
		return "ocupado"
	if altura_no_tile(t) > n * 0.5 - FOLGA:
		return "estrutura_alta_embaixo"
	if not limpos.has(t) and not gerador.distribuicao.obstaculo(t).is_empty():
		return "obstaculo"
	return ""


## `extras`: campos a mais na entrada (nivel, desce, pilares). Nível ≥ 1 vai para `altos`.
func colocar(nome: String, minimo: Vector2i, rot: int, extras := {}) -> int:
	var n: int = extras.get("nivel", 0)
	var motivo := motivo_bloqueio(nome, minimo, rot) if n == 0 else motivo_alto(minimo, n)
	if motivo != "":
		return -1
	var id := _prox_id
	_prox_id += 1
	versao += 1
	var area: Vector2i = registro.area(nome)
	estruturas[id] = {"nome": nome, "minimo": minimo, "rot": rot, "area": area}
	estruturas[id].merge(extras)
	if n == 0 and not extras.has("sobre_agua") and sobre_agua(minimo, area, rot):
		estruturas[id]["sobre_agua"] = true            # plataforma/ponte com pilares (não barra a água)
	if n > 0:
		altos[Vector3i(minimo.x, minimo.y, n)] = id
		return id
	for t in Grade.tiles_da_area(minimo, area, rot):
		tiles[t] = id
	var def: Dictionary = registro.estruturas.get(nome, {})
	if def.get("ocupa_canto", false):
		for c in Grade.cantos_da_area(minimo, area, rot):
			cantos[c] = id
	return id


func remover(id: int) -> void:
	if not estruturas.has(id):
		return
	var e: Dictionary = estruturas[id]
	versao += 1
	if e.get("nivel", 0) > 0:
		altos.erase(Vector3i(e.minimo.x, e.minimo.y, e.nivel))
		estruturas.erase(id)
		return
	# só a área da própria estrutura (não varre o mapa inteiro)
	for t in Grade.tiles_da_area(e.minimo, e.area, e.rot):
		if tiles.get(t, -1) == id:
			tiles.erase(t)
	for c in Grade.cantos_da_area(e.minimo, e.area, e.rot):
		if cantos.get(c, -1) == id:
			cantos.erase(c)
	estruturas.erase(id)


## Gira uma estrutura já posta em torno do próprio centro (mesmo id: a máquina guarda receita e estoque).
## Recusa se a área girada encosta em outra estrutura ou se é peça elevada. `passo` −1 = horário.
func girar(id: int, passo := -1) -> bool:
	if not estruturas.has(id):
		return false
	var e: Dictionary = estruturas[id]
	if e.get("nivel", 0) > 0 or e.nome == "pilar":
		return false
	var nova := posmod(int(e.rot) + passo, 4)
	var c := Grade.centro_da_area(e.minimo, e.area, e.rot)
	var g := Grade.area_girada(e.area, nova)
	var minimo := Vector2i(roundi(c.x - g.x / 2.0), roundi(c.y - g.y / 2.0))
	var novos := Grade.tiles_da_area(minimo, e.area, nova)
	for t in novos:
		if tiles.get(t, id) != id:
			return false
	for t in Grade.tiles_da_area(e.minimo, e.area, e.rot):
		if tiles.get(t, -1) == id:
			tiles.erase(t)
	var canto: bool = registro.estruturas.get(e.nome, {}).get("ocupa_canto", false)
	if canto:
		for k in Grade.cantos_da_area(e.minimo, e.area, e.rot):
			if cantos.get(k, -1) == id:
				cantos.erase(k)
	for t in novos:
		tiles[t] = id
	if canto:
		for k in Grade.cantos_da_area(minimo, e.area, nova):
			cantos[k] = id
	e.rot = nova
	e.minimo = minimo
	versao += 1
	return true


var _terra_versao := -1
var _terra := false


## Há uma Terraplenagem construída (libera Aplainar em qualquer lugar do mapa).
func tem_terraplenagem() -> bool:
	if _terra_versao != versao:
		_terra_versao = versao
		_terra = false
		for id in estruturas:
			if estruturas[id].nome == "terraplenagem":
				_terra = true
				break
	return _terra


func limpar_obstaculo(tile: Vector2i) -> Dictionary:
	var o := gerador.distribuicao.obstaculo(tile)
	if o.is_empty() or limpos.has(tile):
		return {}
	for t in Grade.tiles_da_area(o.ancora, o.area, 0):
		limpos[t] = true
	if arvores.has(tile):                             # queimada/caída rende carvão, não biomassa
		o = o.duplicate()
		o["estado"] = arvores[tile].e
		arvores.erase(tile)
	return o


## O que remover este obstáculo rende (árvore queimada/caída = carvão).
static func drops_de(o: Dictionary) -> Dictionary:
	var d: Dictionary = Registro.progressao.get("drops", {})
	match o.get("estado", ""):
		"queimada", "corroida": return d.get("arvore_queimada", {})
		"caida": return d.get("tronco_caido", {})
	return d.get(o.nome, d.get(Distribuicao.especie(o.nome), {}))


## Canto livre para pilar: ninguém reivindica e nenhum tile em volta é obstáculo natural de pé.
func canto_livre(c: Vector2i) -> bool:
	if cantos.has(c):
		return false
	for d in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var t: Vector2i = c + d
		if gerador.eh_agua(gerador.terreno(t)):
			return false
		if not limpos.has(t) and not gerador.distribuicao.obstaculo(t).is_empty():
			return false
	return true


func reservar_pilar(c: Vector2i, altura: float) -> int:
	if not canto_livre(c):
		return -1
	var id := _prox_id
	_prox_id += 1
	estruturas[id] = {"nome": "pilar", "minimo": c, "rot": 0, "area": Vector2i.ZERO, "altura": altura}
	cantos[c] = id
	return id


## Altura (m) da estrutura mais alta no tile (0 se vazio). Usado para saber se a esteira elevada passa por cima.
func altura_no_tile(t: Vector2i) -> float:
	if not tiles.has(t):
		return 0.0
	return _altura(estruturas[tiles[t]].nome)


func _altura(nome: String) -> float:
	var dims: Array = registro.modelos.get(nome, {}).get("dims", [0, 0, 0])
	return float(dims[2])


## Ids de tudo no tile: chão primeiro, depois os níveis de cima.
func ids_no_tile(t: Vector2i) -> Array[int]:
	var out: Array[int] = []
	if tiles.has(t):
		out.append(tiles[t])
	for n in range(1, NIVEIS + 1):
		var k := Vector3i(t.x, t.y, n)
		if altos.has(k):
			out.append(altos[k])
	return out


## Recria o mapa de um salvamento: mesmas estruturas com os MESMOS ids (estações, trens, torres e máquinas
## guardam estado pelo id). Tiles e cantos são refeitos a partir das estruturas.
func restaurar(p_estruturas: Dictionary, p_limpos: Array, prox_id: int, p_arvores: Dictionary = {}) -> void:
	arvores = p_arvores.duplicate()
	estruturas.clear()
	tiles.clear()
	cantos.clear()
	limpos.clear()
	altos.clear()
	for t in p_limpos:
		limpos[t] = true
	for id in p_estruturas:
		var e: Dictionary = p_estruturas[id]
		estruturas[id] = e
		if e.nome == "pilar":
			cantos[e.minimo] = id
			continue
		if e.get("nivel", 0) > 0:
			altos[Vector3i(e.minimo.x, e.minimo.y, e.nivel)] = id
			continue
		for t in Grade.tiles_da_area(e.minimo, e.area, e.rot):
			tiles[t] = id
		if registro.estruturas.get(e.nome, {}).get("ocupa_canto", false):
			for c in Grade.cantos_da_area(e.minimo, e.area, e.rot):
				cantos[c] = id
	_prox_id = prox_id
